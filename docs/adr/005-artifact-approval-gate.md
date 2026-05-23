# ADR 005: Artifact Approval Gate

## Status

Accepted

## Context

The delivery system can generate and review planning artifacts before implementation. Without a manifest-backed approval gate, implementation agents could consume drafts, stale review outputs, rejected work, or a Hermes memory claim that is not auditable.

The repository needs a public-safe mechanism that records artifact status, preserves history, and lets implementation consume only approved artifacts.

## Decision

Use planning `manifest.yaml` artifact entries as the authoritative approval source.

Each artifact has one of these statuses:

```text
planned drafted reviewed changes_requested approved rejected deferred
```

Only `approved` artifacts are eligible for implementation. Status changes are made through `scripts/update-artifact-status.sh`, which validates the run id, manifest, artifact path, and status, then appends audit metadata.

Implementation runs require a parent planning run. Direct implementation from a file path without `--planning-run` is blocked because there is no authoritative planning manifest approval to inspect.

## Authority Model

The approval gate is enforced by repo-local scripts plus review discipline around tracked changes. `scripts/update-artifact-status.sh` records the local actor for audit context, but that value is informational, not an authentication mechanism.

Hermes memory, chat text, local environment variables, and review output alone are not approval authority.

## Approval Semantics

- `approved` means an operator has accepted the artifact for implementation.
- `rejected` means the artifact must not be implemented.
- `deferred` means the artifact is intentionally out of scope for the current implementation run.
- `changes_requested` means the artifact requires a revised draft before another review round.
- `reviewed` is not enough for implementation; it is a pre-decision state.
- `--reason` is required for `approved`, `rejected`, `deferred`, and `changes_requested`. Reason text is stored in the local planning manifest and must stay public-safe: do not include customer identifiers, secrets, private strategy, internal-only links, or raw review evidence.

When `scripts/init-implementation-run.sh --planning-run <id>` runs, it reads the parent planning manifest and selects only artifacts with `status: approved`. If the approved set is empty, it fails with `blocked_missing_approved_artifact` semantics.

The same failure semantics apply when an explicit `--artifact <path>` is supplied with a parent planning run and that path is not approved in the parent manifest.

## Rejected Alternatives

- **Boolean approval flag**: rejected because it loses the difference between planned, drafted, reviewed, changes requested, rejected, and deferred work.
- **Hermes memory as approval source**: rejected because memory is not durable, diffable, or authoritative.
- **Review output as automatic approval**: rejected because reviewers provide evidence and findings; an explicit status transition is still required.
- **Implementation filtering by legacy review fields**: rejected because it creates multiple approval predicates and weakens the gate.

## Consequences

The approval gate adds explicit operator work, but it makes implementation inputs auditable and recoverable. It also prevents unapproved artifacts from silently entering implementation task graphs.

Review evidence and run manifests stay local and ignored. Tracked files record public-safe docs and scripts only. Any copied summary or commit message must avoid private strategy, customer data, secrets, tokens, review ownership tokens, and raw trace metadata.

## Validation

Minimum validation for this ADR and H7:

```bash
scripts/validate-agentic-system.sh
scripts/validate-hermes-actions.sh
bash -n scripts/update-artifact-status.sh
```

The smoke test must prove that a planning run without approved artifacts blocks implementation, and that approving one manifest artifact lets implementation initialize from that parent run.
