# Agentic Delivery Automation Slices

## Slice Rules

H14-H22 are the implemented post-H13 automation slices. Each slice is small,
reviewable, and tied to a concrete validation command. AIT review for these
slices must check code, validation output, negative-path evidence, and rollback
path.

Every slice must include:

- scope;
- files touched;
- acceptance criteria;
- validation command;
- rollback notes;
- AIT review evidence path;
- maximum 5 review rounds;
- Staff+ escalation path.

AIT review evidence remains ignored under:

```text
agentic/reviews/auto-doc-to-implementation/<slice-id>/round-<n>.json
agentic/reviews/auto-doc-to-implementation/<slice-id>/decision-log.md
```

Each completed slice must run Claude Code reviewer through AIT. If review fails,
fix the slice and rerun review. If round 5 still fails, the Staff+ review board
records a decision in the ignored decision log and executes that decision.

## H14: Review Finding To Artifact Revision

Status: implemented.

Scope: turn accepted artifact review findings into bounded artifact revision
tasks without changing the approval model.

Files touched:

- `scripts/run-artifact-review-loop.sh`
- new or existing review-summary helper under `scripts/`
- `agentic/hermes-actions.yaml`
- `agentic/README.md`
- `docs/architecture/agentic-delivery-system.md`

Acceptance criteria:

- review findings are read only from ignored review evidence;
- each actionable finding maps to one artifact path;
- revised artifacts record a changed content hash before re-review;
- repeated review without changed artifact content is rejected;
- status updates use `scripts/update-artifact-status.sh`;
- no review output automatically marks an artifact `approved`;
- generated revision tasks stay public-safe and repo-local.

Validation command:

```bash
scripts/validate-agentic-system.sh
scripts/run-artifact-review-loop.sh --dry-run h14-review-revision-smoke
```

Rollback notes: revert H14 files and remove ignored review outputs under the H14
review directory.

AIT review evidence path:

```text
agentic/reviews/auto-doc-to-implementation/h14/round-<n>.json
agentic/reviews/auto-doc-to-implementation/h14/decision-log.md
```

Maximum review rounds: 5.

Staff+ escalation path: if round 5 fails, Staff Software Architect, Staff QA
Architect, Staff Security Engineer, Staff Technical Writer, Staff Platform
Engineer, and Product Manager choose one of: split findings, simplify revision
scope, defer a finding, change the review parser, or accept a documented risk.

## H15: Artifact Template And Schema Enforcement

Status: implemented.

Scope: validate that generated and requested artifacts contain the sections
needed for implementation, approval, rollback, and review.

Files touched:

- artifact template schema under `agentic/schemas/`
- `scripts/validate-artifact-templates.sh`
- `scripts/generate-artifacts.sh`
- `scripts/run-artifact-generation-agent.sh`
- `agentic/README.md`
- `docs/architecture/agentic-delivery-system.md`

Acceptance criteria:

- each artifact kind declares required sections;
- missing implementation scope, acceptance criteria, validation, rollback, or
  review expectations fail validation;
- goal-file requested artifacts can ask the AI agent to produce additional
  document types with explicit instructions;
- schema validation does not overwrite existing tracked content;
- validation errors identify the artifact path and missing section;
- templates contain only public-safe scaffold language.

Validation command:

```bash
scripts/validate-agentic-system.sh
scripts/generate-artifacts.sh h15-template-smoke
```

Rollback notes: revert H15 files and remove H15 smoke runs.

AIT review evidence path:

```text
agentic/reviews/auto-doc-to-implementation/h15/round-<n>.json
agentic/reviews/auto-doc-to-implementation/h15/decision-log.md
```

Maximum review rounds: 5.

Staff+ escalation path: if round 5 fails, the board decides whether to narrow
artifact kinds, split schema work, defer optional sections, or change template
format.

## H16: Implementation Worker Execution

Status: implemented.

Scope: execute one implementation task with a bounded AI worker while preserving
approved-input scope and disjoint file ownership. This slice also introduces the
worker result contract needed before implementation review can begin.

Files touched:

- `scripts/dispatch-implementation-task.sh`
- `scripts/execute-implementation-task.sh`
- `scripts/validate-implementation-run.sh`
- `agentic/hermes-actions.yaml`
- `agentic/README.md`
- `docs/architecture/hermes-orchestration-adapter.md`

Acceptance criteria:

- worker execution requires an implementation manifest and task id;
- task must have approved inputs, write scope, acceptance criteria, validation
  command, rollback notes, and review path;
- overlapping write scopes are rejected before execution;
- raw worker output is written only to ignored paths;
- task state changes are recorded through repo-local commands;
- validation runs after worker completion;
- worker prompts cannot include non-public identifiers or ignored evidence.
- worker completion records changed files, result status, validation command,
  validation evidence path, and rollback note;
- failed worker completion maps to a blocked task state rather than silent
  retry.

Validation command:

```bash
scripts/validate-agentic-system.sh
scripts/validate-implementation-run.sh <implementation-run-id>
scripts/dispatch-implementation-task.sh --dry-run <implementation-run-id> <task-id>
scripts/execute-implementation-task.sh --dry-run <implementation-run-id> <task-id>
```

Rollback notes: revert H16 files, remove ignored worker outputs, and reset only
the implementation files owned by the failed H16 task.

AIT review evidence path:

```text
agentic/reviews/auto-doc-to-implementation/h16/round-<n>.json
agentic/reviews/auto-doc-to-implementation/h16/decision-log.md
```

Maximum review rounds: 5.

Staff+ escalation path: if round 5 fails, the board decides whether to split the
worker task, reduce write scope, change execution mode, or keep dispatch-only
behavior for that slice.

## H17: Concurrency And Lease Model

Status: implemented.

Scope: add local write-scope lease documentation and validation so parallel
worker execution cannot corrupt implementation state.

Files touched:

- `scripts/dispatch-implementation-task.sh`
- `scripts/validate-implementation-run.sh`
- `scripts/dispatch-implementation-task.sh`
- `docs/architecture/agentic-delivery-system.md`
- `docs/architecture/hermes-orchestration-adapter.md`

Acceptance criteria:

- implementation manifests record active write-scope leases;
- overlapping active leases are rejected;
- stale lease recovery is documented and does not claim real-world identity;
- partial worker failure records a blocked state and evidence path;
- manifest updates preserve existing task records;
- conflict escalation path points to Staff+ decision evidence.

Validation command:

```bash
scripts/validate-agentic-system.sh
scripts/validate-implementation-run.sh <implementation-run-id>
scripts/dispatch-implementation-task.sh --dry-run <implementation-run-id> <task-id>
```

Rollback notes: revert H17 files and clear only ignored H17 lease smoke output.

AIT review evidence path:

```text
agentic/reviews/auto-doc-to-implementation/h17/round-<n>.json
agentic/reviews/auto-doc-to-implementation/h17/decision-log.md
```

Maximum review rounds: 5.

Staff+ escalation path: if round 5 fails, the board decides whether to keep
single-worker execution, split lease handling, or simplify stale lease recovery.

## H18: Implementation Review-Fix Loop

Status: implemented.

Scope: run a bounded AIT plus Claude Code review-fix loop after each
implementation slice.

Files touched:

- `scripts/run-implementation-review-loop.sh`
- `agentic/prompts/slice-code-review.md`
- `scripts/validate-implementation-run.sh`
- `agentic/hermes-actions.yaml`
- `agentic/README.md`
- `docs/architecture/agentic-delivery-system.md`

Acceptance criteria:

- review command uses AIT with Claude Code CLI as reviewer;
- review is capped at 5 rounds per slice;
- every failed round requires a code or artifact change before the next round;
- pass/fail status is recorded in ignored evidence;
- round 5 failure blocks normal progression and requires Staff+ decision;
- review output cannot approve artifacts or implementation tasks by itself;
- final validation runs after the last fix.

Validation command:

```bash
scripts/validate-agentic-system.sh
scripts/validate-implementation-run.sh <implementation-run-id>
scripts/run-implementation-review-loop.sh --dry-run <implementation-run-id> <task-id>
```

Rollback notes: revert H18 files and remove ignored H18 review evidence if the
slice is abandoned.

AIT review evidence path:

```text
agentic/reviews/auto-doc-to-implementation/h18/round-<n>.json
agentic/reviews/auto-doc-to-implementation/h18/decision-log.md
```

Maximum review rounds: 5.

Staff+ escalation path: if round 5 fails, the board decides whether to simplify
the implementation, split review ownership, accept a documented risk, defer
part of the slice, or change the review prompt.

## H19: Manifest Schema And Migration

Status: implemented.

Scope: document and validate planning and implementation manifest versions,
field requirements, state invariants, and compatibility behavior.

Files touched:

- `agentic/schemas/manifest.schema.yaml`
- `scripts/validate-manifest-schema.sh`
- `scripts/validate-agentic-system.sh`
- `scripts/validate-implementation-run.sh`
- `scripts/init-agentic-run.sh`
- `scripts/init-implementation-run.sh`
- `agentic/README.md`

Acceptance criteria:

- planning and implementation manifest versions are documented;
- required and optional fields are listed;
- valid artifact, task, and blocked states are documented;
- validators reject missing required fields;
- migration policy exists before version changes;
- older ignored manifests have a documented compatibility path.

Validation command:

```bash
scripts/validate-agentic-system.sh
scripts/validate-implementation-run.sh <implementation-run-id>
scripts/validate-manifest-schema.sh <implementation-run-id>
```

Rollback notes: revert H19 files and remove generated schema smoke output.

AIT review evidence path:

```text
agentic/reviews/auto-doc-to-implementation/h19/round-<n>.json
agentic/reviews/auto-doc-to-implementation/h19/decision-log.md
```

Maximum review rounds: 5.

Staff+ escalation path: if round 5 fails, the board decides whether to split
schema documentation from validator changes or defer backward compatibility.

## H20: Golden Fixtures And Local Validation Evidence

Status: implemented.

Scope: add stable fixture coverage for planning, requested artifacts,
implementation task graphs, review-fix outcomes, Hermes action contracts, and
local validation evidence.

Files touched:

- new fixtures under `agentic/fixtures/`
- validation helpers under `scripts/`
- `scripts/run-golden-fixtures.sh`
- `scripts/record-validation-evidence.sh`
- `scripts/validate-agentic-system.sh`
- `scripts/validate-hermes-actions.sh`
- `agentic/README.md`

Acceptance criteria:

- fixtures cover artifact lifecycle transitions;
- fixtures cover requested AI-generated artifacts;
- fixtures cover implementation task graph generation from approved inputs;
- fixtures cover Hermes action contract validation;
- expected outputs ignore timestamps and generated ids;
- privacy scans are included in validation guidance;
- fixture failures identify the command and fixture path;
- validation evidence captures command, exit status, redacted output, and
  evidence path under ignored directories;
- each slice includes one relevant negative-path check.

Validation command:

```bash
scripts/validate-agentic-system.sh
scripts/validate-hermes-actions.sh
scripts/run-golden-fixtures.sh
```

Rollback notes: revert H20 files and remove generated fixture outputs.

AIT review evidence path:

```text
agentic/reviews/auto-doc-to-implementation/h20/round-<n>.json
agentic/reviews/auto-doc-to-implementation/h20/decision-log.md
```

Maximum review rounds: 5.

Staff+ escalation path: if round 5 fails, the board decides whether to split
fixtures by feature, reduce snapshot strictness, or defer lower-value cases.

## H21: Evidence Retention And Redaction

Status: implemented.

Scope: define where review, validation, and worker evidence is stored, what may
be summarized in tracked files, and which scans must run before commit.

Files touched:

- `docs/standards/agentic-delivery-quality-standard.md`
- `agentic/README.md`
- `scripts/privacy-scan-tracked.sh`
- `scripts/redact-local-evidence.sh`
- `scripts/validate-agentic-system.sh`

Acceptance criteria:

- tracked evidence fields are limited to public-safe summaries;
- ignored evidence paths are documented;
- raw AIT review output, worker stdout, and run manifests remain ignored;
- redaction rules cover command metadata and local trace values;
- tracked-file scan commands are documented or scripted;
- reviewers can identify the evidence path without opening tracked transcripts.

Validation command:

```bash
scripts/validate-agentic-system.sh
scripts/privacy-scan-tracked.sh
```

Rollback notes: revert H21 files and remove ignored H21 scan output.

AIT review evidence path:

```text
agentic/reviews/auto-doc-to-implementation/h21/round-<n>.json
agentic/reviews/auto-doc-to-implementation/h21/decision-log.md
```

Maximum review rounds: 5.

Staff+ escalation path: if round 5 fails, the board decides whether to reduce
tracked summaries further, add a dedicated scan script first, or split redaction
work from retention policy.

## H22: Hermes Execute-Mode Policy

Status: implemented.

Scope: define when Hermes may execute repo-local commands rather than only
render dry-run payloads.

Files touched:

- `docs/architecture/hermes-orchestration-adapter.md`
- `agentic/hermes-actions.yaml`
- `scripts/run-hermes-action.sh`
- `scripts/validate-hermes-actions.sh`
- `agentic/README.md`

Acceptance criteria:

- executable actions are explicitly listed;
- approval and fifth-round Staff+ decisions remain operator decisions;
- every executable action maps to a repo-local command;
- mutating actions require validation before and after execution;
- dry-run behavior remains available for every action;
- Hermes memory remains non-authoritative;
- execute-mode failures leave enough ignored evidence for review.

Validation command:

```bash
scripts/validate-agentic-system.sh
scripts/validate-hermes-actions.sh
scripts/run-hermes-action.sh --dry-run validate_scaffold
```

Rollback notes: revert H22 files and keep Hermes dry-run-only behavior.

AIT review evidence path:

```text
agentic/reviews/auto-doc-to-implementation/h22/round-<n>.json
agentic/reviews/auto-doc-to-implementation/h22/decision-log.md
```

Maximum review rounds: 5.

Staff+ escalation path: if round 5 fails, the board decides whether to keep a
manual-only action, split execute-mode by action type, or change the validation
precondition.
