# Agentic Delivery System

## Purpose

Agentic Delivery System is a public-safe internal delivery scaffold. It turns a profile and goal into planning artifacts, adversarial review records, explicit approval decisions, implementation slices, validation results, and PR or release preparation records.

It is not a customer-facing product surface and not a runtime dependency. Project-specific strategy, source material, reviewers, and rejected directions live in profiles. The tracked default profile is `agentic/profiles/default-delivery.yaml`, which contains only public-safe scaffold material.

## Pipeline

```text
profile + goal
  -> planning run manifest
  -> AIT multi-agent planning deliberation
  -> deliberation summary and accepted/rejected/deferred planning notes
  -> requested artifact expansion
  -> generated draft artifacts
  -> drafted artifacts
  -> bounded review-fix loop
  -> revised artifacts
  -> explicit artifact approval gate
  -> implementation manifest
  -> implementation task graph
  -> worker dispatch records
  -> AIT + Codex CLI Staff+ implementation review
  -> Hermes-native dry-run integration
```

The core rule is simple: implementation consumes only artifacts whose planning manifest entry has `status: approved`.

Planning also has a mandatory deliberation rule: before non-trivial draft
artifacts are generated, the run must collect AIT-backed multi-agent planning
evidence or record an explicit Staff+ waiver. Deliberation output is evidence,
not authority; it cannot approve artifacts, mutate implementation scope, or
bypass later review.

## Authoritative State

| State source | Authority | Use |
| --- | --- | --- |
| `agentic/runs/<run-id>/manifest.yaml` | Authoritative | Planning run state, artifact status, review attempts, validation, decisions |
| `agentic/runs/<run-id>/implementation-manifest.yaml` | Authoritative | Approved inputs, implementation tasks, branch plan, test plan, release notes |
| `agentic/identity-policy.yaml` | Authoritative | Repo-local actors, roles, authorization actions, and separation-of-duty policy |
| Git-tracked docs | Authoritative | Public-safe delivery artifacts |
| Hermes memory | Non-authoritative | Execution context and reminders |
| AIT trace / review output | Evidence | Local-only review evidence; not committed |

Hermes memory cannot approve an artifact, infer approval, or override a manifest. Every state-changing operation must be expressible as a repo-local command.

## Planning Deliberation

After `scripts/init-agentic-run.sh` creates the planning manifest and before
`scripts/generate-artifacts.sh` or `scripts/run-artifact-generation-agent.sh
--execute` drafts content, the run should invoke AIT-backed agency-agents:

```bash
RUN_ID=<planning-run-id> scripts/run-agency-review.sh
scripts/summarize-agency-review.sh <planning-run-id>
```

This deliberation stage is for structured brainstorming and adversarial planning
review. The agency-agents inspect the goal, profile source of truth, requested
artifacts, product boundary, security concerns, implementation risks, validation
strategy, and likely artifact gaps.

Expected participants come from the active profile or pipeline defaults, such
as:

- product manager;
- engineering software architect;
- engineering security engineer;
- compliance auditor;
- sales engineer.

The outputs are stored as ignored AIT review evidence and summarized into the
planning manifest as `review_attempts`. Operators or integration agents may use
that evidence to update requested artifacts, revise generation instructions, or
record planning decisions. They must not treat the deliberation as approval.

Accepted, rejected, and deferred ideas must be captured as explicit planning
notes or artifact changes. If the team intentionally skips this stage, the run
must record a public-safe Staff+ waiver reason before artifacts are generated.

## Artifact Lifecycle

Planning artifacts use this status set:

```text
planned drafted reviewed changes_requested approved rejected deferred
```

The lifecycle records both progress and decisions:

| Status | Meaning | Implementation consumable |
| --- | --- | --- |
| `planned` | Artifact is expected but not drafted. | No |
| `drafted` | Artifact content exists and can enter review. | No |
| `reviewed` | A review round completed without blocking findings and the artifact is awaiting an explicit decision. | No |
| `changes_requested` | Review found issues; the next step is a revised draft. | No |
| `approved` | Operator accepted the artifact for implementation. | Yes |
| `rejected` | Artifact must not be implemented. | No |
| `deferred` | Artifact is intentionally postponed. | No |

`scripts/update-artifact-status.sh` updates artifact status in the planning manifest, records timestamps, preserves the previous status, and appends audit history. Valid statuses, allowed transitions, and repo-local actor authorization are enforced by the script.

Normal transitions:

- `planned` to `drafted`, `reviewed`, `approved`, `rejected`, or `deferred`;
- `drafted` to `reviewed`, `changes_requested`, `approved`, `rejected`, or `deferred`;
- `reviewed` to `approved`, `changes_requested`, `rejected`, or `deferred`;
- `changes_requested` to `drafted`, `approved`, `rejected`, or `deferred`;
- `deferred` back to `planned`, `drafted`, `reviewed`, `approved`, or `rejected` when work resumes or receives an explicit decision.

`approved` and `rejected` are terminal in H7. Direct approval from an earlier status is an explicit operator decision and requires a public-safe reason. Approval also requires the `artifact.approve` authorization action. The artifact owner agent cannot approve that same artifact, and the manifest records the resolved actor, role, policy, and identity authority.

Each review loop is capped at 5 rounds. After each review round, the artifact or implementation slice must be revised before another review. If a document or slice cannot pass by round 5, the run must record a Staff-level council decision rather than continuing indefinitely.

## Approval Gate

Implementation can start from a planning run only after at least one artifact is approved:

```bash
scripts/update-artifact-status.sh <planning-run-id> <artifact-path> approved --reason "<approval reason>"
RUN_ID=<implementation-run-id> scripts/init-implementation-run.sh --planning-run <planning-run-id>
```

When `scripts/init-implementation-run.sh --planning-run <id>` reads the parent planning manifest, it selects only artifacts with `status: approved`. If there are no approved artifacts, it fails with `blocked_missing_approved_artifact` semantics and does not create an implementation manifest.

Direct implementation from a path without `--planning-run` is blocked. When explicit `--artifact <path>` inputs are supplied with a parent planning run, each explicit artifact must also be approved in that parent manifest.

## Hermes Execution Host

Hermes can orchestrate the delivery pipeline by calling documented actions in `agentic/hermes-actions.yaml`. Hermes may:

- initialize planning and implementation runs;
- update run and artifact status through repo-local scripts;
- report run status from manifests;
- trigger AIT + Codex CLI Staff+ review commands;
- resume from manifest state after interruption.

Hermes must not:

- store authoritative state in memory;
- approve artifacts from memory or chat context;
- simulate agency-agent review;
- bypass the approval gate;
- execute actions that are not mapped to repo-local commands.

## Implementation Slices

Implementation-oriented documents and code changes are split into small slices. Each slice must define:

- scope;
- files touched;
- acceptance criteria;
- validation command;
- rollback notes;
- AIT review record path;
- maximum 5 review rounds;
- Staff-level escalation path after 5 failed rounds.

The implementation manifest records approved inputs and one or more tasks derived from those inputs. Each task includes acceptance criteria and validation expectations so review can verify that code follows approved artifacts rather than reinterpretation.

Worker dispatch, worker execution, and implementation review records include
repo-local actor, role, authorization action, policy path, and identity
authority. The actor that produced the latest worker result cannot record the
implementation review result for that same task.

The active post-H13 automation roadmap is tracked in
`docs/architecture/agentic-delivery-automation-roadmap.md`. H14-H22 are split
in `docs/backlog/agentic-delivery-automation-slices.md`, and their review,
test, and acceptance standard is defined in
`docs/standards/agentic-delivery-quality-standard.md`.

Identity and authorization hardening is described in
`docs/architecture/agentic-identity-authorization.md` and split in
`docs/backlog/agentic-identity-authorization-slices.md`.

## H8-H13 Automation Surface

H8-H13 add repo-local commands around the H7 approval gate. They extend the
pipeline without changing the authority model:

| Slice | Command | State effect |
| --- | --- | --- |
| H8 Generate Artifacts | `scripts/generate-artifacts.sh <planning-run-id>` | Creates missing public-safe draft files conservatively, records generation metadata, and moves eligible artifacts to `drafted`. It never marks artifacts `approved`. |
| H8 Agent-Requested Artifacts | `scripts/init-agentic-run.sh --goal-file <path>` and `scripts/run-artifact-generation-agent.sh --dry-run <planning-run-id>` | Lets a goal file declare extra artifacts plus agent instructions. The generation agent can draft those requested documents, but approval remains a separate manifest status transition. |
| H9 Review-Fix Loop | `scripts/run-artifact-review-loop.sh <planning-run-id>` | Writes ignored review evidence, records content hashes, requires changed content before a repeated round, and blocks at round 5 for Staff decision. |
| H10 Task Graph | `scripts/generate-implementation-task-graph.sh <implementation-run-id>` | Derives bounded tasks only from approved inputs and records scope, files touched, validation command, rollback notes, review path, and dependencies. |
| H11 Worker Dispatch | `scripts/dispatch-implementation-task.sh <implementation-run-id> <task-id>` | Emits bounded worker instructions and refuses overlapping write scopes. |
| H13 Hermes Native | `scripts/hermes-memory-sync.sh --dry-run`, `scripts/hermes-scheduler-dry-run.sh`, `scripts/hermes-gateway-dry-run.sh` | Lists scheduler, memory, and gateway payloads while keeping manifests authoritative and Hermes-disabled mode functional. |

Generated task descriptions and gateway payloads are constrained to repo-local
paths and public-safe identifiers. Any command that would publish or package work
must pass tracked privacy scans before writing readiness records.

## H14-H22 Automation Surface

H14-H22 implement the remaining active automation without restoring deferred CI,
PR publishing, or strong identity controls:

| Slice | Command | State effect |
| --- | --- | --- |
| H14 Review Finding Revision | `scripts/create-artifact-revision-tasks.sh <run-id>` | Creates bounded artifact revision tasks from failed review evidence and keeps approval explicit. |
| H15 Artifact Templates | `scripts/validate-artifact-templates.sh <run-id>` | Validates required sections for generated and requested artifacts. |
| H16 Worker Execution | `scripts/execute-implementation-task.sh <run-id> <task-id>` | Records worker result, validation evidence, changed files, rollback notes, and task state. |
| H17 Leases | `scripts/dispatch-implementation-task.sh <run-id> <task-id>` | Records active write-scope leases and rejects overlaps. |
| H18 Implementation Review | `scripts/run-implementation-review-loop.sh <run-id> <task-id>` | Records bounded code-review rounds and blocks repeated review without changed content. |
| H19 Manifest Schema | `scripts/validate-manifest-schema.sh --all` | Validates planning and implementation manifest schema invariants. |
| H20 Fixtures | `scripts/run-golden-fixtures.sh` | Exercises the golden regression path and negative checks. |
| H21 Evidence Redaction | `scripts/privacy-scan-tracked.sh` and `scripts/redact-local-evidence.sh` | Enforces tracked-file public safety and local evidence redaction. |
| H22 Hermes Execute Policy | `scripts/run-hermes-action.sh <action-id>` | Reads executable actions from `agentic/hermes-actions.yaml` and runs pre/post validation for mutating actions. |

## Privacy Boundary

Tracked files must not include non-public strategy, non-public product identifiers, customer details, credentials, tokens, reviewer trace identifiers, private profiles, or ignored review evidence. Local review outputs belong under ignored paths such as `agentic/reviews/` or `agentic/runs/<run-id>/review-outputs/`.

Planning and implementation run directories are ignored; `agentic/runs/.gitkeep` is the only tracked file under `agentic/runs/`. Status reasons are stored in local manifests, so reason text must also be public-safe.

Before a commit, tracked files must be scanned for private strategy strings and common secret patterns. Review evidence may remain on disk for audit, but it must stay untracked.
