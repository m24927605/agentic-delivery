# Boss Decision Memo Module

## Purpose

Boss Decision Memo converts research, feasibility scoring, and engineering
options into a concise executive recommendation.

## Scope

Active scope:

- present the answer first;
- explain do, defer, no-go, POC, or MVP recommendation;
- summarize evidence and uncertainty;
- list cost, timebox, staffing assumption, risks, and next decision;
- keep a public-safe record of why the team recommends a path.

## Deferred Scope

- board-level investment memo;
- sales collateral;
- legal approval;
- automatic roadmap scheduling.

## Workflow

```text
intake + research + feasibility
  -> options
  -> recommendation
  -> executive memo
  -> doc review
  -> artifact status decision
```

## Artifact Schema

Markdown sections:

- `Recommendation`
- `Decision Needed`
- `Context`
- `Evidence Summary`
- `Options Considered`
- `Recommended Path`
- `Time And Staffing`
- `Risks And Unknowns`
- `Success Metrics`
- `Next Step`

## CLI / Manifest / Pipeline Contract

Future command:

```bash
scripts/generate-boss-decision-memo.sh <run-id>
```

Contract:

- reads intake, research, and scoring artifacts;
- writes a memo draft;
- marks the memo at most `drafted` or `reviewed`;
- requires explicit artifact approval before implementation can consume it.

## Failure Behavior

Block memo generation when:

- recommendation is missing;
- evidence summary is empty;
- options considered are missing;
- risks and unknowns are missing;
- POC or MVP recommendation lacks timebox or staffing assumptions;
- next step is missing;
- memo claims approval without manifest status.

## Validation Strategy

Validation checks:

- all required memo sections exist;
- recommendation is one of `do`, `defer`, `no_go`, `poc`, or `mvp`;
- evidence summary references research artifact paths;
- staffing and timebox are present for POC or MVP recommendations;
- no ignored evidence path is copied into tracked memo text.

## Test Cases

- complete recommendation memo passes;
- missing options considered fails;
- POC recommendation without timebox fails;
- MVP recommendation without staffing assumption fails;
- memo with approval language but unapproved manifest status fails.

## Acceptance Criteria

- A busy executive can read the recommendation, reason, risk, and next step in
  one pass.
- Engineering can point to the memo as decision context but not as implementation
  authority until it is approved.

## Doc Review Standard

Codex CLI Staff+ review must check clarity, evidence traceability, explicit
recommendation, risk visibility, and lack of hidden implementation approval.

## Code Review Standard

Implementation review must check section validation, input artifact references,
public-safe output, and negative-path tests for missing decision fields.

## Rollback

Revert memo templates and generation scripts. Remove ignored memo drafts created
by smoke runs.

## Review Expectations

Review must confirm that the memo is decision-ready, not a collection of raw
agent notes.
