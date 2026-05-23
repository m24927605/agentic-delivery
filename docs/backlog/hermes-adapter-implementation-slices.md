# Hermes Adapter Implementation Slices

## Principles

Hermes Adapter work must move in small slices. Each slice needs a focused scope, a validation command, rollback notes, and real AIT + Claude Code review evidence.

Every slice must define:

- scope;
- files touched;
- acceptance criteria;
- validation command;
- rollback notes;
- AIT review record path;
- maximum 5 review rounds;
- Staff-level escalation path after 5 failed rounds.

Review evidence is local-only and ignored. Store it under:

```text
agentic/reviews/auto-doc-to-implementation/<slice-id>/round-<n>.json
agentic/reviews/auto-doc-to-implementation/<slice-id>/decision-log.md
```

If round 5 still has blocking issues, convene a Staff-level internal council and record the decision in the ignored decision log. Valid decisions are: accept with known risk, simplify scope, split the slice, defer part of the requirement, or change design.

## Completed Foundation

H0-H6 established the Hermes adapter scaffold: action contract, run status reporting, action validation, dry-run rendering, planning orchestration, implementation orchestration, and review orchestration.

H7-H11 and H13 are implemented as repo-local commands with manifest authority,
dry-run paths, validation commands, ignored review evidence, and Hermes action
mappings. H12 CI/PR publishing is intentionally deferred out of the active flow.

Post-H13 active automation is split in
`docs/backlog/agentic-delivery-automation-slices.md`. The active roadmap is
`docs/architecture/agentic-delivery-automation-roadmap.md`, and the quality bar
is `docs/standards/agentic-delivery-quality-standard.md`.

## H7: Artifact Status + Approval Gate

Scope:

- H7a: add artifact lifecycle and approval gate documentation.
- H7b: add `scripts/update-artifact-status.sh` and planning manifest status metadata.
- H7c: update implementation gating, reporting, Hermes action wiring, and public-safe profile defaults.

Files touched:

- `docs/architecture/agentic-delivery-system.md`
- `docs/architecture/hermes-orchestration-adapter.md`
- `docs/adr/005-artifact-approval-gate.md`
- `docs/backlog/hermes-adapter-implementation-slices.md`
- `agentic/README.md`
- `agentic/hermes-actions.yaml`
- `agentic/pipeline.yaml`
- `agentic/profiles/default-delivery.yaml`
- `scripts/init-agentic-run.sh`
- `scripts/init-implementation-run.sh`
- `scripts/report-run-status.sh`
- `scripts/update-artifact-status.sh`
- `scripts/run-hermes-action.sh`
- `scripts/validate-agentic-system.sh`
- `scripts/validate-hermes-actions.sh`
- `scripts/validate-implementation-run.sh`

Acceptance criteria:

- Planning artifacts initialize with `status: planned`, timestamps, decision/reason fields, and status history.
- `scripts/update-artifact-status.sh <run-id> <artifact-path> <status> [--reason <text>]` accepts only the seven valid statuses.
- The status script rejects invalid run ids, missing manifests, unknown artifacts, invalid statuses, invalid transitions, and missing reasons for decision statuses.
- Status updates append artifact-level history and manifest-level decision records.
- `scripts/init-implementation-run.sh --planning-run <id>` consumes only `status: approved` artifacts.
- Direct implementation without `--planning-run` is blocked.
- A planning run with no approved artifacts fails clearly with `blocked_missing_approved_artifact` semantics.
- `scripts/report-run-status.sh` reports `artifacts_total`, `artifacts_approved`, `artifacts_pending`, `artifacts_rejected`, and `artifacts_deferred`.
- `agentic/hermes-actions.yaml` maps `update_artifact_status` to the repo-local status script.
- Review evidence and run outputs remain ignored.

Validation command:

```bash
scripts/validate-agentic-system.sh
scripts/validate-hermes-actions.sh
bash -n scripts/update-artifact-status.sh
rm -rf agentic/runs/h7-approval-smoke
RUN_ID=h7-approval-smoke scripts/init-agentic-run.sh "H7 approval smoke"
scripts/report-run-status.sh h7-approval-smoke
scripts/update-artifact-status.sh h7-approval-smoke docs/architecture/agentic-delivery-system.md approved --reason "H7 smoke approval"
scripts/report-run-status.sh h7-approval-smoke
RUN_ID=h7-implementation-smoke scripts/init-implementation-run.sh --planning-run h7-approval-smoke
scripts/validate-implementation-run.sh h7-implementation-smoke
scripts/report-run-status.sh h7-implementation-smoke
rm -rf agentic/runs/h7-approval-smoke agentic/runs/h7-implementation-smoke
find agentic/runs -maxdepth 2 -type f | sort
```

Rollback notes:

- Revert the files listed in this slice.
- Remove temporary runs under `agentic/runs/h7-*`.
- Remove local ignored review evidence under `agentic/reviews/auto-doc-to-implementation/h7-*` if the slice is abandoned.

AIT review record path:

```text
agentic/reviews/auto-doc-to-implementation/h7/round-<n>.json
agentic/reviews/auto-doc-to-implementation/h7/decision-log.md
```

Maximum review rounds: 5.

Staff-level escalation path:

```text
agentic/reviews/auto-doc-to-implementation/h7/decision-log.md
```

After 5 failed rounds, convene `engineering-software-architect`, `engineering-senior-developer` or `engineering-backend-architect`, `engineering-security-engineer`, `engineering-technical-writer`, and `product-manager`.

## H8: Generate Artifacts

Status: implemented.

Scope: add a repo-local command that creates or updates planned artifact files from a goal and profile while preserving manifest authority.

Files touched: `scripts/generate-artifacts.sh`, `scripts/run-artifact-generation-agent.sh`, `scripts/init-agentic-run.sh`, `agentic/hermes-actions.yaml`, `agentic/README.md`, `docs/architecture/agentic-delivery-system.md`, `docs/architecture/hermes-orchestration-adapter.md`, and `agentic/fixtures/h8-generate-artifacts/`.

Acceptance criteria: generated artifacts are recorded in `manifest.yaml`; new artifacts move only to `drafted`; no artifact is marked `approved` automatically; stdout contains `generated artifacts`; generated text contains no private profile identifiers; goal files can request extra artifacts with agent instructions; AI generation can be previewed with `scripts/run-artifact-generation-agent.sh --dry-run <run-id>`.

Validation command: `scripts/validate-agentic-system.sh` and `RUN_ID=h8-generate-smoke scripts/init-agentic-run.sh "H8 smoke"; scripts/generate-artifacts.sh h8-generate-smoke; scripts/report-run-status.sh h8-generate-smoke`.

Rollback notes: revert H8 files and remove generated smoke run directories.

AIT review record path: `agentic/reviews/auto-doc-to-implementation/h8/round-<n>.json`.

Maximum review rounds: 5. Staff escalation path: H8 decision log under the same ignored review directory with the H7 Staff council roster.

## H9: Review-Fix Loop

Status: implemented.

Scope: formalize repeated AIT review, finding extraction, revision, and re-review for each document.

Files touched: `scripts/run-artifact-review-loop.sh`, `agentic/prompts/review-agent.md`, `agentic/prompts/integration-agent.md`, `agentic/hermes-actions.yaml`, `agentic/README.md`, and `docs/backlog/hermes-adapter-implementation-slices.md`.

Acceptance criteria: each round records ignored review evidence; each next round requires a changed artifact timestamp or content hash; round 5 triggers Staff-level escalation instead of an infinite loop; stdout contains `review loop completed` or `blocked_human_decision_required`.

Validation command: `scripts/validate-agentic-system.sh` and `scripts/run-artifact-review-loop.sh --dry-run h9-review-loop-smoke`.

Rollback notes: revert H9 files and remove fixture runs/reviews.

AIT review record path: `agentic/reviews/auto-doc-to-implementation/h9/round-<n>.json`.

Maximum review rounds: 5. Staff escalation path: H9 decision log under the same ignored review directory with the H7 Staff council roster.

## H10: Implementation Task Graph

Status: implemented.

Scope: convert approved artifacts into small implementation slices with dependencies, acceptance criteria, validation commands, rollback notes, and review paths.

Files touched: `scripts/generate-implementation-task-graph.sh`, `scripts/init-implementation-run.sh`, `scripts/validate-implementation-run.sh`, `agentic/hermes-actions.yaml`, `agentic/README.md`, and architecture docs.

Acceptance criteria: implementation tasks are derived only from approved artifacts; each task has scope, files touched, acceptance criteria, validation command, rollback notes, AIT review path, and dependency metadata; generated task descriptions contain no private profile identifiers and no paths outside the repo-local scope; stdout contains `implementation task graph ok`.

Validation command: `scripts/validate-implementation-run.sh <run-id>` and `scripts/generate-implementation-task-graph.sh --dry-run <run-id>`.

Rollback notes: revert H10 files and remove generated implementation smoke runs.

AIT review record path: `agentic/reviews/auto-doc-to-implementation/h10/round-<n>.json`.

Maximum review rounds: 5. Staff escalation path: H10 decision log under the same ignored review directory with the H7 Staff council roster.

## H11: Worker Dispatch

Status: implemented.

Scope: dispatch implementation tasks to workers while keeping manifest state authoritative and avoiding conflicting file ownership.

Files touched: `scripts/dispatch-implementation-task.sh`, `scripts/validate-implementation-run.sh`, `agentic/hermes-actions.yaml`, `agentic/README.md`, and `docs/architecture/hermes-orchestration-adapter.md`.

Acceptance criteria: each worker receives a bounded task, disjoint write scope, validation command, rollback notes, and review record path; dispatcher refuses overlapping write scopes; worker stdout is redacted before any tracked summary.

Validation command: `scripts/validate-agentic-system.sh` and `scripts/dispatch-implementation-task.sh --dry-run <implementation-run-id> <task-id>`.

Rollback notes: revert H11 files and remove dispatch fixture outputs.

AIT review record path: `agentic/reviews/auto-doc-to-implementation/h11/round-<n>.json`.

Maximum review rounds: 5. Staff escalation path: H11 decision log under the same ignored review directory with `engineering-security-engineer` mandatory.

## H12: Deferred CI/PR Publisher

Status: deferred.

Scope: out of current active flow. CI feedback, PR packaging, push, and PR
creation remain manual for now. The delivery scaffold focuses on artifact
generation, review, approval, implementation task graph, worker dispatch, and
Hermes dry-run integration.

Rollback notes: no active H12 repo-local command is required.

AIT review record path: not required while deferred.

## H13: Hermes-Native Integration

Status: implemented.

Scope: connect the adapter to Hermes-native integration in three sub-slices while preserving repo-local manifest authority: H13a memory/skills, H13b scheduler, and H13c gateway.

Files touched: `docs/architecture/hermes-orchestration-adapter.md`, `agentic/hermes-actions.yaml`, `scripts/validate-hermes-actions.sh`, `scripts/hermes-memory-sync.sh`, `scripts/hermes-scheduler-dry-run.sh`, `scripts/hermes-gateway-dry-run.sh`, and `agentic/fixtures/h13-hermes-native/`.

Acceptance criteria: Hermes can schedule and resume delivery work; manifests remain authoritative; every action remains manually rerunnable; gateway dry run lists exactly what data crosses the boundary; Hermes-disabled mode remains functional.

Validation command: `scripts/validate-agentic-system.sh`, `scripts/validate-hermes-actions.sh`, `scripts/hermes-memory-sync.sh --dry-run`, `scripts/hermes-scheduler-dry-run.sh`, and `scripts/hermes-gateway-dry-run.sh`.

Rollback notes: revert H13 files and remove generated integration fixture output.

AIT review record path: `agentic/reviews/auto-doc-to-implementation/h13/round-<n>.json`.

Maximum review rounds: 5. Staff escalation path: H13 decision log under the same ignored review directory with `engineering-security-engineer` mandatory.
