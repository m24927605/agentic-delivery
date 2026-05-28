# Agentic Delivery System

This directory contains a public-safe scaffold for an internal delivery pipeline.

The pipeline turns a selected profile and goal into manifest-backed planning artifacts, review evidence, explicit approval decisions, implementation tasks, validation records, and PR or release preparation records.

```text
profile + goal
  -> planning run
  -> AIT multi-agent planning deliberation
  -> generated drafts
  -> review-fix loop
  -> reviewed and approved artifacts
  -> implementation run
  -> implementation task graph
  -> worker dispatch
  -> Hermes-native dry-run integration
```

Hermes can orchestrate the pipeline, but repo-local manifests remain authoritative. Hermes memory is execution context only.

## Files

- `pipeline.yaml` defines modes, run states, agents, validation commands, and the default profile.
- `profiles/default-delivery.yaml` is the tracked public-safe default profile.
- `hermes-actions.yaml` maps Hermes actions to repo-local commands.
- `identity-policy.yaml` defines repo-local actors, roles, authorization actions, and separation-of-duty policy.
- `prompts/*.md` are review, implementation, and orchestration prompt templates.
- `runs/<run-id>/manifest.yaml` is the planning run record.
- `runs/<run-id>/implementation-manifest.yaml` is the implementation run record.
- `fixtures/` contains public-safe smoke fixtures for later adapter slices.

Related architecture:

- `docs/architecture/agentic-delivery-system.md`
- `docs/architecture/agentic-delivery-automation-roadmap.md`
- `docs/architecture/hermes-orchestration-adapter.md`
- `docs/standards/agentic-delivery-quality-standard.md`
- `docs/adr/005-artifact-approval-gate.md`
- `docs/backlog/agentic-delivery-automation-slices.md`
- `docs/backlog/hermes-adapter-implementation-slices.md`

## Quick start (CLI)

The `agentic` CLI is a state-aware wrapper over the `scripts/*.sh` pipeline.

Install:

```bash
pipx install agentic-delivery
```

In any clone of this repo:

```bash
agentic init "Your delivery goal"
agentic next                                                # see what to do next
agentic status                                              # inspect current run
agentic plan artifact docs/adr/008-xyz.md approve --reason "..."
```

The CLI shells out to the same scripts documented below; both forms remain valid.
See `cli/README.md` for the full command reference.

## Validate

Validate the scaffold and default profile:

```bash
scripts/validate-agentic-system.sh
```

Validate Hermes action contracts:

```bash
scripts/validate-hermes-actions.sh
```

Dry-run a Hermes action:

```bash
scripts/run-hermes-action.sh --dry-run validate_scaffold
scripts/run-hermes-action.sh --dry-run update_artifact_status run_id=<run-id> artifact_path=<path> status=approved reason="Approved for implementation"
scripts/run-hermes-action.sh update_artifact_status run_id=<run-id> artifact_path=<path> status=approved reason="Approved for implementation" actor=local-operator role=approver
```

## Planning Run

Initialize a planning run:

```bash
scripts/init-agentic-run.sh "Next delivery goal"
```

Set an explicit run id:

```bash
RUN_ID=<run-id> scripts/init-agentic-run.sh "Next delivery goal"
```

Use a goal file:

```bash
RUN_ID=<run-id> scripts/init-agentic-run.sh --goal-file docs/my-goal.md
```

Goal files can request additional AI-generated artifacts with YAML
frontmatter:

```markdown
---
artifacts:
  - path: docs/architecture/my-feature.md
    kind: architecture
    purpose: Explain the feature design.
    agent: document_builder
    instructions: |
      Produce an implementation-ready architecture note with validation and
      rollback expectations.
---

# Goal

Describe the delivery goal here.
```

This creates:

```text
agentic/runs/<run-id>/manifest.yaml
```

Each planned artifact starts with:

- `status: planned`
- `created_at`
- `updated_at`
- `decision`
- `decision_reason`
- `status_history`

## Planning Deliberation

Before generating non-trivial draft artifacts, run AIT-backed agency-agents for
planning deliberation:

```bash
RUN_ID=<planning-run-id> scripts/run-agency-review.sh
scripts/summarize-agency-review.sh <planning-run-id>
```

This stage lets multiple review agents brainstorm artifact gaps, risks,
implementation slices, validation strategy, and product-boundary conflicts
before drafts are produced. The output is evidence only. It cannot approve
artifacts, skip artifact review, or authorize implementation.

Use the summary to adjust requested artifacts or generation instructions, then
continue to artifact generation. If this stage is intentionally skipped, record
a public-safe Staff+ waiver reason in the planning run before generating
artifacts.

## Generate Draft Artifacts

Generate or refresh planned artifacts:

```bash
scripts/generate-artifacts.sh <planning-run-id>
```

The generator updates `manifest.yaml`, moves eligible artifacts to `drafted`,
and prints `generated artifacts`. It does not mark any artifact `approved`.
Existing tracked artifact files are not overwritten during smoke validation.

If the goal file requested artifacts with `instructions`, preview AI document
generation prompts:

```bash
scripts/run-artifact-generation-agent.sh --dry-run <planning-run-id>
```

Execute AI document generation only when you intend the agent to edit requested
artifact files:

```bash
scripts/run-artifact-generation-agent.sh --execute <planning-run-id>
```

The agent-generation command writes prompts under the ignored run directory,
updates generated artifacts to `drafted`, and still requires review plus
explicit approval before implementation can consume them.

## Review-Fix Loop

Record one bounded artifact review round:

```bash
scripts/run-artifact-review-loop.sh <planning-run-id> --artifact <path>
scripts/run-artifact-review-loop.sh --dry-run h9-review-loop-smoke
```

Review evidence is written under ignored `agentic/reviews/`. A second review
round requires changed artifact content or timestamp/hash evidence. Round 5
without approval blocks with `blocked_human_decision_required` so a Staff-level
decision can be recorded instead of continuing indefinitely.

## Artifact Approval

Implementation consumes only approved artifacts. Approval is recorded in the planning manifest by updating an artifact entry to `status: approved`.

Valid artifact statuses:

```text
planned drafted reviewed changes_requested approved rejected deferred
```

| Status | Meaning | Implementation consumable |
| --- | --- | --- |
| `planned` | The manifest expects this artifact. | No |
| `drafted` | Content exists and can enter review. | No |
| `reviewed` | Review completed without blocking findings and awaits a decision. | No |
| `changes_requested` | Review found blocking changes; a revised draft is required. | No |
| `approved` | The artifact is accepted for implementation. | Yes |
| `rejected` | The artifact must not be implemented. | No |
| `deferred` | The artifact is intentionally out of scope for now. | No |

Update status:

```bash
scripts/update-artifact-status.sh <run-id> <artifact-path> <status> [--reason <text>]
scripts/update-artifact-status.sh <run-id> <artifact-path> approved --reason "<text>" --actor local-operator --role approver
```

Examples:

```bash
scripts/update-artifact-status.sh <run-id> docs/adr/005-artifact-approval-gate.md drafted --reason "Drafted for review"
scripts/update-artifact-status.sh <run-id> docs/adr/005-artifact-approval-gate.md reviewed --reason "AIT review round completed"
scripts/update-artifact-status.sh <run-id> docs/adr/005-artifact-approval-gate.md approved --reason "Approved for H7 implementation"
```

Reason is required for `approved`, `rejected`, `deferred`, and `changes_requested`. Reason text is stored in the local planning manifest, so keep it public-safe: do not include customer identifiers, secrets, internal-only links, private strategy, or raw review evidence.

The script rejects invalid run ids, missing manifests, unknown artifact paths, invalid statuses, invalid transitions, missing required reasons, and unauthorized actor or role combinations. It appends artifact-level status history and manifest-level decision records for audit, including actor, role, authorization action, policy path, and identity authority.

Validate the repo-local identity policy:

```bash
scripts/validate-identity-policy.sh
scripts/authorize-agentic-action.sh --action artifact.approve
```

The tracked identity policy uses public-safe local actor identifiers. It is an enforcement boundary for this scaffold, not cryptographic proof of external identity.

## Implementation Run

Start implementation from a parent planning run:

```bash
RUN_ID=<implementation-run-id> scripts/init-implementation-run.sh --planning-run <planning-run-id>
```

When `--planning-run` is used, the initializer filters the parent planning manifest to artifacts with `status: approved`. If no approved artifacts exist, it fails with `blocked_missing_approved_artifact` semantics and does not create an implementation manifest.

Direct implementation from a path without `--planning-run` is blocked. When explicit artifacts are supplied together with `--planning-run`, each explicit artifact must also be approved in that parent manifest.

Validate an implementation run:

```bash
scripts/validate-implementation-run.sh <implementation-run-id>
```

Build or refresh the implementation task graph:

```bash
scripts/generate-implementation-task-graph.sh <implementation-run-id>
scripts/generate-implementation-task-graph.sh --dry-run <implementation-run-id>
```

Every generated task records scope, files touched, write scope, acceptance
criteria, validation command, rollback notes, AIT review path, and dependency
metadata. Task descriptions must stay public-safe and repo-local.

## Boss Idea Response

The `boss-idea-response` profile handles urgent or ambiguous executive ideas
without turning raw ideas directly into implementation work.

Initialize and validate a structured idea intake:

```bash
scripts/init-boss-idea-run.sh --dry-run agentic/fixtures/boss-idea-response/valid-idea.md
RUN_ID=<run-id> scripts/init-boss-idea-run.sh agentic/fixtures/boss-idea-response/valid-idea.md
```

Generate source-backed market research and market-discovery quality evidence:

```bash
scripts/collect-boss-idea-research.sh --dry-run <run-id>
scripts/collect-boss-idea-research.sh <run-id> --search-results agentic/fixtures/boss-idea-response/valid-market-search-results.yaml --output agentic/runs/<run-id>/market-research.md
scripts/validate-boss-idea-research.sh agentic/runs/<run-id>/market-research.md
scripts/crawl-boss-idea-market.sh --force <run-id> --from-query-pack --search-provider fixture --output agentic/runs/<run-id>/market-search-results.yaml
scripts/validate-boss-idea-market-discovery-quality.sh agentic/runs/<run-id>/market-discovery-quality.yaml
scripts/generate-boss-idea-competitor-brief.sh <run-id>
scripts/validate-boss-idea-competitor-brief.sh agentic/fixtures/boss-idea-response/valid-competitor-brief.md
scripts/validate-boss-idea-provider-health.sh agentic/fixtures/boss-idea-response/valid-provider-health.yaml
scripts/validate-boss-idea-provider-health-events.sh agentic/fixtures/boss-idea-response/valid-provider-health-events.yaml
scripts/summarize-boss-idea-provider-health.sh --output agentic/runs/<run-id>/provider-health.yaml <run-id>
scripts/recommend-boss-idea-provider-fallback.sh --output agentic/runs/<run-id>/provider-fallback-advisory.yaml agentic/runs/<run-id>/provider-health.yaml
```

Validate each downstream artifact independently:

```bash
scripts/validate-boss-idea-research.sh agentic/fixtures/boss-idea-response/valid-research.md
scripts/validate-boss-idea-competitor-brief.sh agentic/fixtures/boss-idea-response/valid-competitor-brief.md
scripts/score-boss-idea-feasibility.sh --dry-run agentic/fixtures/boss-idea-response/valid-scorecard.yaml
scripts/validate-boss-decision-memo.sh agentic/fixtures/boss-idea-response/valid-memo.md
scripts/validate-boss-idea-poc-mvp.sh agentic/fixtures/boss-idea-response/valid-poc-plan.md
scripts/validate-boss-idea-success-metrics.sh agentic/fixtures/boss-idea-response/valid-metrics.yaml
scripts/validate-boss-idea-decision.sh agentic/fixtures/boss-idea-response/valid-decision.yaml
scripts/validate-boss-idea-provider-health.sh agentic/fixtures/boss-idea-response/valid-provider-health.yaml
scripts/validate-boss-idea-provider-health-events.sh agentic/fixtures/boss-idea-response/valid-provider-health-events.yaml
```

Decision recording is authorized and manifest-backed:

```bash
scripts/record-boss-idea-decision.sh agentic/fixtures/boss-idea-response/valid-decision.yaml --run-id <run-id>
```

Boss idea commands preserve the same delivery boundary as the base scaffold:
research is evidence only, scoring is advisory only, go/no-go does not bypass
artifact approval, and implementation still requires approved artifacts.

Dispatch one task:

```bash
scripts/dispatch-implementation-task.sh <implementation-run-id> <task-id>
scripts/dispatch-implementation-task.sh --dry-run <implementation-run-id> <task-id>
scripts/dispatch-implementation-task.sh --actor local-operator --role operator <implementation-run-id> <task-id>
```

The dispatcher refuses overlapping write scopes and records worker instructions
without storing raw worker stdout in tracked files. Dispatch records actor, role,
authorization action, policy path, and identity authority in the implementation
manifest.

Execute one bounded implementation task and record worker evidence:

```bash
scripts/execute-implementation-task.sh --dry-run <implementation-run-id> <task-id>
scripts/execute-implementation-task.sh <implementation-run-id> <task-id>
scripts/execute-implementation-task.sh --actor implementation_agent --role implementation_worker <implementation-run-id> <task-id>
```

Run one implementation review-fix round:

```bash
scripts/run-implementation-review-loop.sh --dry-run <implementation-run-id> <task-id>
scripts/run-implementation-review-loop.sh <implementation-run-id> <task-id>
scripts/run-implementation-review-loop.sh --actor codex_cli_staff_reviewer --role code_reviewer <implementation-run-id> <task-id>
```

Review output remains evidence only. It cannot approve artifacts or override
the implementation manifest. The latest worker actor cannot record the review
result for the same task.

Validate manifests, generated artifact templates, local evidence, and fixtures:

```bash
scripts/validate-manifest-schema.sh --all
scripts/validate-artifact-templates.sh <planning-run-id>
scripts/privacy-scan-tracked.sh
scripts/run-golden-fixtures.sh
```

Manifest field contracts and migration rules live in
`agentic/schemas/manifest.schema.yaml`. The general manifest schema validator
warns on legacy manifests without `schema_version`; implementation-run
validation is strict for newly initialized implementation manifests.

## Run Status

Report planning or implementation status:

```bash
scripts/report-run-status.sh <run-id>
```

The report includes:

- `artifacts_total`
- `artifacts_approved`
- `artifacts_pending`
- `artifacts_rejected`
- `artifacts_deferred`
- review attempt count
- validation count
- next suggested action

In planning mode, `artifacts_pending` counts artifacts whose status is not `approved`, `rejected`, or `deferred`: `planned`, `drafted`, `reviewed`, and `changes_requested`.

In implementation mode, counts are derived from `approved_inputs`: `artifacts_total` and `artifacts_approved` are equal, and pending/rejected/deferred are always `0`. Lifecycle counts are meaningful in planning mode.

Status reporting is read-only. It does not approve artifacts or infer approval from review output.

## Review Rule

Codex CLI Staff+ reviewers are review-only and must run through AIT:

```bash
ait run --adapter codex --stdin none --apply never --review never --format json -- \
  "$(command -v codex)" exec \
  --cd "$PWD" \
  --sandbox read-only \
  "<review prompt>"
```

Review outputs are evidence. They do not automatically approve artifacts. After each review round, revise the artifact or implementation slice before another review round. Each loop is capped at 5 rounds; after that, record a Staff-level council decision.

The active post-H13 roadmap and per-slice quality bar are documented in:

- `docs/architecture/agentic-delivery-automation-roadmap.md`
- `docs/backlog/agentic-delivery-automation-slices.md`
- `docs/standards/agentic-delivery-quality-standard.md`

The completed H14-H22 slices cover review finding revision, artifact templates,
worker execution, lease handling, implementation review-fix, manifest schema,
golden fixtures with local validation evidence, evidence redaction, and Hermes
execute-mode policy. H23-H26 add repo-local identity and authorization
hardening. CI feedback and PR publishing remain deferred.

## Hermes Actions

Hermes actions map to repo-local commands:

| Hermes action | Command |
| --- | --- |
| `validate_scaffold` | `scripts/validate-agentic-system.sh` |
| `start_planning_run` | `PROFILE=<profile-id> RUN_ID=<run-id> scripts/init-agentic-run.sh <goal>` |
| `update_run_state` | `scripts/update-run-state.sh <run-id> <state>` |
| `update_artifact_status` | `scripts/update-artifact-status.sh <run-id> <artifact-path> <status> --reason <text>` |
| `generate_artifacts` | `scripts/generate-artifacts.sh <run-id>` |
| `run_artifact_generation_agent` | `scripts/run-artifact-generation-agent.sh --dry-run <run-id>` |
| `run_artifact_review_loop` | `scripts/run-artifact-review-loop.sh <run-id>` |
| `create_artifact_revision_tasks` | `scripts/create-artifact-revision-tasks.sh <run-id>` |
| `run_agency_review` | `RUN_ID=<run-id> scripts/run-agency-review.sh` |
| `summarize_review` | `scripts/summarize-agency-review.sh <run-id>` |
| `collect_boss_idea_research` | `scripts/collect-boss-idea-research.sh <run-id> --search-results <results.yaml> --output <research.md>` |
| `generate_boss_idea_competitor_brief` | `scripts/generate-boss-idea-competitor-brief.sh --output <brief.md> <run-id>` |
| `validate_boss_idea_competitor_brief` | `scripts/validate-boss-idea-run-competitor-brief.sh <run-id> <brief.md>` |
| `run_boss_idea_live_smoke` | `scripts/run-boss-idea-live-smoke.sh --live --force <run-id>` |
| `start_implementation_run` | `RUN_ID=<run-id> scripts/init-implementation-run.sh --planning-run <planning-run-id>` |
| `generate_implementation_task_graph` | `scripts/generate-implementation-task-graph.sh <run-id>` |
| `dispatch_implementation_task` | `scripts/dispatch-implementation-task.sh <run-id> <task-id>` |
| `execute_implementation_task` | `scripts/execute-implementation-task.sh <run-id> <task-id>` |
| `run_implementation_review_loop` | `scripts/run-implementation-review-loop.sh <run-id> <task-id>` |
| `validate_implementation_run` | `scripts/validate-implementation-run.sh <run-id>` |
| `validate_manifest_schema` | `scripts/validate-manifest-schema.sh <run-id>` |
| `validate_artifact_templates` | `scripts/validate-artifact-templates.sh <run-id>` |
| `privacy_scan_tracked` | `scripts/privacy-scan-tracked.sh` |
| `run_golden_fixtures` | `scripts/run-golden-fixtures.sh` |
| `report_run_status` | `scripts/report-run-status.sh <run-id>` |
| `hermes_memory_sync` | `scripts/hermes-memory-sync.sh --dry-run` |
| `hermes_scheduler_dry_run` | `scripts/hermes-scheduler-dry-run.sh` |
| `hermes_gateway_dry_run` | `scripts/hermes-gateway-dry-run.sh` |

Hermes must not approve artifacts from memory, bypass repo-local commands, simulate review, or use untracked private profiles as tracked source of truth.
Executable mutating Hermes actions declare an `authorization.action` in
`agentic/hermes-actions.yaml`. The runner accepts global `actor=` and `role=`
inputs, checks them against `agentic/identity-policy.yaml`, and propagates the
resolved identity to called repo-local scripts through `AIT_ACTOR` and
`AIT_ACTOR_ROLE`.
The `run_boss_idea_live_smoke` action additionally requires explicit
`actor=local-operator role=operator` inputs and the live SearXNG gate inputs.

## Hermes-Native Dry Runs

H13 integration commands are dry-run first:

```bash
scripts/hermes-memory-sync.sh --dry-run
scripts/hermes-scheduler-dry-run.sh
scripts/hermes-gateway-dry-run.sh
```

They list run ids, manifest paths, run states, and next repo-local actions.
They do not move authoritative state into Hermes memory and remain runnable when
Hermes is disabled.

## Privacy

Tracked files must stay public-safe. Do not commit non-public strategy, non-public product identifiers, customer details, credentials, tokens, reviewer trace identifiers, private profiles, or raw review evidence.

Review evidence and run outputs are ignored:

```text
agentic/reviews/
agentic/runs/<run-id>/
```

Keep `agentic/runs/.gitkeep` tracked so the run directory exists in a clean checkout.
