# Hermes Orchestration Adapter

## Purpose

Hermes Orchestration Adapter lets Hermes drive the Agentic Delivery System through repo-local commands. The adapter is a thin execution layer over scripts and manifests; it is not a state store, not a product surface, and not an implementation runtime.

## Architecture

```text
Hermes Agent
  -> agentic/hermes-actions.yaml
  -> scripts/*.sh
  -> agentic/runs/<run-id>/manifest.yaml
  -> agentic/runs/<run-id>/implementation-manifest.yaml
  -> ignored review / dispatch evidence
```

Hermes memory is useful for context, but every action starts by reading the relevant manifest. If Hermes memory disagrees with the manifest, the manifest wins.

## Action Contract

Hermes actions are defined in `agentic/hermes-actions.yaml`. Each action declares:

- `id`
- `purpose`
- `mode`
- `command_template`
- `required_inputs`
- `reads`
- `writes`
- `authorization.action` for executable mutating actions
- `success_signals`
- `failure_states`
- `retry_policy`

Every action must map to a repo-local command that can be manually rerun. The adapter must not create hidden state or execute an unmapped command.

## Artifact Status Actions

H7 adds `update_artifact_status`, mapped to:

```bash
scripts/update-artifact-status.sh <run-id> <artifact-path> <status> --reason <text>
```

The action updates only the planning `manifest.yaml`. It rejects invalid run ids, missing manifests, unknown artifacts, invalid statuses, and missing required action inputs. Valid statuses are:

```text
planned drafted reviewed changes_requested approved rejected deferred
```

The command appends audit metadata to the artifact and to the manifest decision log. Hermes may call this command, but Hermes memory cannot approve an artifact. Approval exists only when the manifest artifact entry has `status: approved`.

When Hermes executes this action, the runner must authorize the supplied or
default actor against `agentic/identity-policy.yaml`. Approval transitions need
an actor role that can pass both the Hermes action authorization and the
underlying `artifact.approve` check in `scripts/update-artifact-status.sh`.

`--reason` is required for `approved`, `rejected`, `deferred`, and `changes_requested`. The reason is stored in the local manifest and must remain public-safe.

## Approval Gate Contract

`start_implementation_run` maps to:

```bash
scripts/init-implementation-run.sh --planning-run <planning-run-id>
```

When a planning run is provided, the implementation initializer must filter the parent manifest to `status: approved` artifacts only. If the approved set is empty, it exits non-zero with `blocked_missing_approved_artifact` semantics.

This gate is fail-closed:

- `planned`, `drafted`, `reviewed`, `changes_requested`, `rejected`, and `deferred` artifacts are excluded.
- Unknown artifacts are rejected.
- Implementation without a parent planning run is blocked.
- Explicit artifacts supplied with a parent planning run must also be approved in that parent manifest.
- The implementation manifest records the parent planning run and approval source.

## Recovery

Hermes recovery follows manifest state:

1. Read the planning or implementation manifest.
2. Report status with `scripts/report-run-status.sh <run-id>`.
3. Choose the next action from `agentic/hermes-actions.yaml`.
4. Re-run the repo-local command.
5. Treat manifest or filesystem mismatch as a blocked state requiring human decision.

Hermes must not infer completion from memory, logs, or partial output when the manifest does not show completion.

## H8-H13 Actions

The adapter now exposes the post-approval automation as manually rerunnable
actions:

- `generate_artifacts` drafts planned artifacts and updates only planning
  manifest generation metadata and artifact status.
- `run_artifact_generation_agent` previews AI document-generation work for
  requested artifacts declared by a goal file. Execute mode remains a manual
  repo-local command because it can edit artifact files.
- `run_agency_review` and `summarize_review` provide the AIT-backed
  multi-agent planning deliberation gate before non-trivial artifacts are
  generated. Their outputs are evidence and planning input, not approval.
- `run_artifact_review_loop` records bounded ignored review evidence and blocks
  at the 5-round cap.
- `generate_implementation_task_graph` converts approved inputs into
  implementation tasks with scope, files touched, validation commands, rollback
  notes, review paths, and dependencies.
- `dispatch_implementation_task` refuses overlapping write scopes before writing
  a worker dispatch record.
- `hermes_memory_sync`, `hermes_scheduler_dry_run`, and
  `hermes_gateway_dry_run` list the payload Hermes may consume without making
  Hermes memory authoritative.

## H14-H22 Actions

The adapter also exposes the completed post-H13 automation surface:

- `create_artifact_revision_tasks` converts failed artifact review findings into
  bounded revision tasks without approving artifacts.
- `validate_artifact_templates` enforces required sections for generated and
  requested artifacts.
- `validate_manifest_schema` checks planning and implementation manifest schema
  invariants.
- `execute_implementation_task` records bounded worker execution, validation
  evidence, result status, changed files, rollback notes, and lease release.
- `run_implementation_review_loop` records bounded implementation review-fix
  rounds and blocks repeated review without changed content.
- `privacy_scan_tracked` scans tracked files for public-safety and common secret
  assignment patterns.
- `run_golden_fixtures` exercises the approval gate, requested artifact
  generation, revision tasks, worker execution, review loop, and negative paths.

Execute mode is governed by `execute_mode` in `agentic/hermes-actions.yaml`.
Executable actions are listed explicitly there. Mutating actions run the
configured pre-validation and post-validation command before and after execution.
Mutating actions also declare an `authorization.action`; `scripts/run-hermes-action.sh`
checks that action before rendering and executing the repo-local command, then
passes the resolved identity to called scripts as `AIT_ACTOR` and
`AIT_ACTOR_ROLE`. Dry-run remains available for every action.

All H13 commands are dry-run first. The gateway dry run lists the exact boundary:
run id, run mode, run state, manifest path, and next suggested repo-local action
may cross to Hermes; secrets, customer identifiers, private strategy, raw review
traces, and approval decisions outside the manifest must not cross.

## Review Evidence

AIT + Claude Code review evidence is real and local. It is stored under ignored paths such as:

```text
agentic/reviews/auto-doc-to-implementation/<doc-or-slice-id>/round-<n>.json
agentic/reviews/auto-doc-to-implementation/<doc-or-slice-id>/decision-log.md
```

These files may contain trace metadata and must not be committed. Public tracked docs should summarize decisions without copying private traces, ownership tokens, secrets, or private strategy.
