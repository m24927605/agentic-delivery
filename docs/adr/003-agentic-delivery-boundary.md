# ADR 003: Agentic Delivery Boundary

## Status

Accepted

## Context

The Agentic Delivery System is an internal planning and implementation delivery scaffold. It turns a profile and a goal into repo-local planning artifacts, review evidence, implementation task records, validation results, and PR or release preparation records.

The system must stay separate from any customer-facing runtime. It can coordinate documents, scripts, reviews, and implementation slices, but it must not become a product feature, a runtime dependency, a customer data processor, or a hidden state store.

## Decision

Keep the Agentic Delivery System as a repo-local delivery pipeline.

Profiles define project-specific source material, artifacts, reviewers, and rejected directions. The core pipeline defines reusable mechanics only: manifests, run states, Hermes action contracts, validation scripts, review execution, artifact approval gates, and implementation manifests.

## Boundary Rules

- `agentic/runs/<run-id>/manifest.yaml` is authoritative for planning run state and artifact status.
- `agentic/runs/<run-id>/implementation-manifest.yaml` is authoritative for implementation run state.
- Hermes memory is execution context only and cannot approve artifacts or replace manifests.
- AIT + Claude Code agency-agent review must be real review evidence, not simulated output.
- Review outputs and other evidence that may contain trace metadata stay local and ignored.
- Implementation runs consume approved artifacts only.
- Every Hermes action maps to a repo-local command that can be manually rerun.
- Profiles may be private locally, but tracked profiles must remain public-safe.

## Consequences

The scaffold is slower than an unconstrained autonomous agent because it records state and requires explicit approval. The tradeoff is intentional: delivery state is reproducible, reviewable, recoverable after interruption, and safe to publish as a public scaffold.

## Related Documents

- `docs/architecture/agentic-delivery-system.md`
- `docs/architecture/hermes-orchestration-adapter.md`
- `docs/adr/004-hermes-orchestration-adapter.md`
- `docs/adr/005-artifact-approval-gate.md`
- `docs/backlog/hermes-adapter-implementation-slices.md`
