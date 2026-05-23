# Go/No-Go Decision Module

## Purpose

Go/No-Go Decision records the final decision after research, recommendation,
POC, or MVP evidence is reviewed.

## Scope

Active scope:

- record decision: go, no-go, defer, pivot, or research more;
- cite the artifacts and evidence used;
- record residual risks and owner;
- define the next approved action;
- prevent implementation from starting without approved artifacts.

## Deferred Scope

- contract approval;
- production launch approval;
- budget approval;
- external governance workflow integration.

## Workflow

```text
evidence package
  -> Staff+ review
  -> decision record
  -> artifact status update
  -> approved implementation inputs or closure
```

## Artifact Schema

Decision fields:

- `decision`
- `decision_owner`
- `decision_date`
- `evidence_artifacts`
- `metric_result`
- `residual_risks`
- `accepted_risks`
- `next_action`
- `follow_up_date`
- `implementation_allowed`

Valid decisions:

- `go`
- `no_go`
- `defer`
- `pivot`
- `research_more`

## CLI / Manifest / Pipeline Contract

Future command:

```bash
scripts/record-boss-idea-decision.sh <run-id> --decision <decision> --reason <text>
```

Contract:

- appends a manifest decision record;
- requires repo-local actor authorization;
- records the decision artifact path;
- never substitutes for `approved` artifact status;
- blocks implementation unless approved artifacts exist.

## Failure Behavior

Block decision recording when:

- decision value is unknown;
- reason is missing;
- evidence artifact list is empty;
- decision owner is missing;
- go decision has no success metric result;
- implementation is requested without approved artifacts.

## Validation Strategy

Validation checks:

- decision fields are complete;
- evidence artifacts exist and are repo-local;
- go decisions reference metric results;
- no-go and defer decisions include follow-up handling;
- manifest artifact approval remains separate.

## Test Cases

- valid go decision with approved artifacts passes;
- go decision without metric result fails;
- no-go decision without reason fails;
- implementation request without approved artifacts fails;
- evidence path outside repo fails;
- unknown decision value fails.

## Acceptance Criteria

- The decision record explains what was decided, why, using which evidence, and
  what happens next.
- The record can close a bad idea cleanly without creating engineering work.
- A go decision still respects the base approval gate.

## Doc Review Standard

Claude Code review must check decision clarity, evidence traceability, residual
risk handling, and approval-gate separation.

## Code Review Standard

Implementation review must check authorization, manifest decision append,
approved artifact filtering, negative-path tests, and privacy scan evidence.

## Rollback

Revert decision command and templates. Remove ignored decision smoke output.

## Review Expectations

Review must confirm that the decision module prevents ambiguous "maybe build it"
states and keeps implementation authority explicit.
