# Boss Idea Response Implementation Slices

## Purpose

This backlog splits Boss Idea Response System implementation into small,
reviewable slices. Each slice can be designed, implemented, tested, accepted,
and reviewed independently.

## Scope

Active scope:

- implement idea-to-decision workflow on top of the existing Agentic Delivery
  System;
- keep implementation local, public-safe, and manifest-backed;
- preserve the approval gate for implementation;
- require AIT plus Claude Code review for every slice.

Deferred scope:

- automatic market web crawler;
- external dashboard;
- PR publishing;
- production deployment automation;
- external identity provider integration.

## Slice Rules

Every slice must include:

- owner role;
- source artifact;
- files touched;
- write scope;
- dependencies;
- acceptance criteria;
- validation command;
- negative-path tests;
- rollback notes;
- AIT review evidence path;
- maximum 5 review rounds;
- Staff+ escalation path.

## BIR-00: Documentation And Profile Baseline

Status: completed.

Owner role: Staff Software Architect.

Source artifact: `docs/architecture/boss-idea-response-system.md`.

Files touched:

- `docs/architecture/boss-idea-response-system.md`
- `docs/architecture/boss-idea-modules/*.md`
- `docs/standards/boss-idea-response-quality-standard.md`
- `docs/backlog/boss-idea-response-slices.md`
- `agentic/profiles/boss-idea-response.yaml`

Acceptance criteria:

- Staff+ roles are defined;
- all seven module design docs exist;
- quality standard defines doc review and code review rules;
- implementation slices are small and independently reviewable;
- each module doc is manually audited against the required section contract
  until a structural linter exists;
- profile validation passes;
- AIT plus Claude Code doc review passes.

Validation command:

```bash
scripts/validate-agentic-system.sh
scripts/validate-hermes-actions.sh
scripts/privacy-scan-tracked.sh
scripts/validate-manifest-schema.sh --all
PROFILE=boss-idea-response scripts/validate-agentic-system.sh
```

Rollback notes: revert BIR documentation and profile files.

AIT review evidence path:

```text
agentic/reviews/boss-idea-response/bir-00/round-<n>.json
agentic/reviews/boss-idea-response/bir-00/decision-log.md
```

Maximum review rounds: 5.

Staff+ escalation path: if round 5 fails, the board chooses whether to split
module docs, reduce scope, or accept a documented documentation risk.

## BIR-01: Idea Intake Command

Status: completed.

Owner role: Staff Platform Engineer.

Source artifact: `docs/architecture/boss-idea-modules/idea-intake.md`.

Files touched:

- `scripts/init-boss-idea-run.sh`
- `agentic/hermes-actions.yaml`
- `agentic/pipeline.yaml`
- `agentic/README.md`
- `agentic/fixtures/boss-idea-response/`

Acceptance criteria:

- valid goal file initializes a planning manifest;
- missing owner, deadline, or response class fails;
- run id and path validation match existing safety rules;
- initialized artifacts are `planned`;
- no artifact is drafted or approved.

Validation command:

```bash
scripts/validate-agentic-system.sh
PROFILE=boss-idea-response scripts/validate-agentic-system.sh
scripts/init-boss-idea-run.sh --dry-run agentic/fixtures/boss-idea-response/valid-idea.md
```

Rollback notes: remove the command, Hermes action, pipeline registration, and
fixtures for this slice.

AIT review evidence path: `agentic/reviews/boss-idea-response/bir-01/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: simplify intake fields or split goal-file parsing from
manifest initialization.

## BIR-02: Market Research Evidence Validator

Status: completed.

Owner role: Market Research Lead.

Source artifact: `docs/architecture/boss-idea-modules/market-research-evidence.md`.

Files touched:

- `scripts/validate-boss-idea-research.sh`
- `agentic/schemas/boss-idea-research.schema.yaml`
- `agentic/hermes-actions.yaml`
- `agentic/README.md`
- `agentic/fixtures/boss-idea-response/`

Acceptance criteria:

- source inventory requires stable reference, access date, and source type;
- key claims require source mapping;
- unsupported inferences must be labeled;
- raw evidence paths stay ignored;
- missing citation negative test fails.

Validation command:

```bash
scripts/validate-agentic-system.sh
scripts/validate-boss-idea-research.sh agentic/fixtures/boss-idea-response/valid-research.md
```

Rollback notes: remove research validator, schema, Hermes action, and fixtures.

AIT review evidence path: `agentic/reviews/boss-idea-response/bir-02/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: reduce citation schema, split source inventory and claim
mapping, or defer automated validation.

## BIR-03: Feasibility Scorecard Validator

Status: completed.

Owner role: Staff QA Architect.

Source artifact: `docs/architecture/boss-idea-modules/feasibility-scoring.md`.

Files touched:

- `scripts/score-boss-idea-feasibility.sh`
- `agentic/schemas/boss-idea-scorecard.schema.yaml`
- `agentic/hermes-actions.yaml`
- `agentic/README.md`
- `agentic/fixtures/boss-idea-response/`

Acceptance criteria:

- score dimensions are required;
- scores must be integers from 1 to 5;
- high risk requires mitigation;
- low confidence requires unknowns or follow-up questions;
- scoring cannot approve implementation.

Validation command:

```bash
scripts/validate-agentic-system.sh
scripts/score-boss-idea-feasibility.sh --dry-run agentic/fixtures/boss-idea-response/valid-scorecard.yaml
```

Rollback notes: remove scorecard command, schema, Hermes action, and fixtures.

AIT review evidence path: `agentic/reviews/boss-idea-response/bir-03/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: simplify scoring dimensions or split score validation
from recommendation mapping.

## BIR-04: Decision Memo Generator And Validator

Status: completed.

Owner role: Staff Technical Writer.

Source artifact: `docs/architecture/boss-idea-modules/boss-decision-memo.md`.

Files touched:

- `scripts/generate-boss-decision-memo.sh`
- `scripts/validate-boss-decision-memo.sh`
- `agentic/schemas/boss-decision-memo.schema.yaml`
- `agentic/hermes-actions.yaml`
- `agentic/README.md`

Acceptance criteria:

- memo includes recommendation, evidence summary, options, risks, time and
  staffing, and next step;
- POC/MVP recommendations require timebox and staffing assumptions;
- memo cannot claim approval unless artifact status is approved;
- missing options negative test fails.

Validation command:

```bash
scripts/validate-agentic-system.sh
scripts/validate-boss-decision-memo.sh agentic/fixtures/boss-idea-response/valid-memo.md
```

Rollback notes: remove memo generator, validator, schema, Hermes action, and fixtures.

AIT review evidence path: `agentic/reviews/boss-idea-response/bir-04/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: keep validator only, defer generation, or simplify memo
template.

## BIR-05: POC/MVP Timebox Planner

Status: completed.

Owner role: Engineering Manager.

Source artifact: `docs/architecture/boss-idea-modules/poc-mvp-timebox.md`.

Files touched:

- `scripts/plan-boss-idea-poc-mvp.sh`
- `scripts/validate-boss-idea-poc-mvp.sh`
- `agentic/hermes-actions.yaml`
- `agentic/README.md`

Acceptance criteria:

- POC/MVP work type is required;
- timebox, scope-in, scope-out, demo path, validation command, and rollback
  notes are required;
- validation command must be repo-local;
- implementation task graph requires approved plan artifact.

Validation command:

```bash
scripts/validate-agentic-system.sh
scripts/validate-boss-idea-poc-mvp.sh agentic/fixtures/boss-idea-response/valid-poc-plan.md
```

Rollback notes: remove planner, validator, Hermes action, and fixtures.

AIT review evidence path: `agentic/reviews/boss-idea-response/bir-05/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: split POC and MVP validators or defer planner
generation.

## BIR-06: Success Metrics Validator

Status: completed.

Owner role: Staff QA Architect.

Source artifact: `docs/architecture/boss-idea-modules/success-metrics.md`.

Files touched:

- `scripts/validate-boss-idea-success-metrics.sh`
- `agentic/schemas/boss-idea-success-metrics.schema.yaml`
- `agentic/hermes-actions.yaml`
- `agentic/README.md`

Acceptance criteria:

- every metric has method, threshold, owner role, and decision mapping;
- evidence path is ignored or public-safe;
- metric must fit the selected timebox;
- metric output cannot automatically record go/no-go.

Validation command:

```bash
scripts/validate-agentic-system.sh
scripts/validate-boss-idea-success-metrics.sh agentic/fixtures/boss-idea-response/valid-metrics.yaml
```

Rollback notes: remove metric validator, schema, Hermes action, and fixtures.

AIT review evidence path: `agentic/reviews/boss-idea-response/bir-06/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: reduce metric fields or split metric schema from
manifest integration.

## BIR-07: Go/No-Go Decision Recorder

Status: completed.

Owner role: Product Strategy Lead.

Source artifact: `docs/architecture/boss-idea-modules/go-no-go-decision.md`.

Files touched:

- `scripts/record-boss-idea-decision.sh`
- `scripts/validate-boss-idea-decision.sh`
- `agentic/hermes-actions.yaml`
- `agentic/identity-policy.yaml`
- `agentic/README.md`

Acceptance criteria:

- valid decisions are go, no-go, defer, pivot, or research-more;
- decision reason and evidence artifacts are required;
- go decision requires metric result;
- mutating action records repo-local actor authorization;
- implementation remains blocked without approved artifacts.

Validation command:

```bash
scripts/validate-agentic-system.sh
scripts/validate-boss-idea-decision.sh agentic/fixtures/boss-idea-response/valid-decision.yaml
```

Rollback notes: remove decision recorder, validator, authorization additions,
Hermes action, and fixtures.

AIT review evidence path: `agentic/reviews/boss-idea-response/bir-07/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: split decision validation and manifest mutation, or keep
decision recording manual through `update-artifact-status.sh`.

## BIR-08: Integrated Golden Fixture

Status: completed.

Owner role: Staff Platform Engineer.

Source artifact: all boss idea response module docs.

Files touched:

- `scripts/run-golden-fixtures.sh`
- `agentic/fixtures/boss-idea-response/`
- `agentic/README.md`

Acceptance criteria:

- fixture covers idea intake through no-go path;
- fixture covers idea intake through POC-approved path;
- fixture covers generated template paths and static valid fixtures;
- negative checks include missing citation, missing timebox, missing metric
  threshold, unknown decision value, unapproved go or implementation input,
  authorization failure, bad evidence or path input, and manifest authority
  failure;
- no-go records cleanly without approved implementation artifacts;
- go cannot record until manifest artifacts are approved;
- approved boss idea artifacts can seed an implementation manifest;
- privacy scan remains clean;
- fixture is deterministic, cleans up generated repo-local and temporary
  output, and does not rely on external network access.

Validation command:

```bash
scripts/validate-agentic-system.sh
scripts/run-golden-fixtures.sh
scripts/privacy-scan-tracked.sh
```

Rollback notes: remove fixture updates and ignored run output.

AIT review evidence path: `agentic/reviews/boss-idea-response/bir-08/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: split fixtures by module or defer integrated fixture
until BIR-01 through BIR-07 are complete.

## BIR-09: Market Competitor Search Automation

Status: in review.

Owner role: Market Research Lead.

Source artifact: `docs/architecture/boss-idea-modules/market-research-evidence.md`.

Files touched:

- `scripts/collect-boss-idea-research.sh`
- `scripts/run-golden-fixtures.sh`
- `scripts/validate-agentic-system.sh`
- `agentic/schemas/boss-idea-market-search.schema.yaml`
- `agentic/fixtures/boss-idea-response/`
- `agentic/hermes-actions.yaml`
- `agentic/pipeline.yaml`
- `agentic/README.md`
- `docs/architecture/boss-idea-modules/market-research-evidence.md`
- `docs/backlog/boss-idea-response-slices.md`

Acceptance criteria:

- command derives a market search query pack from boss idea intake;
- command consumes public-safe search results from a provider adapter contract;
- generated research artifact passes `validate-boss-idea-research.sh`;
- search results require competitor and mainstream-practice signals;
- missing reference, missing required signal, bad query id, bad source type,
  future access date, unsafe output path, oversized claim, multiline claim, or
  unsafe URL scheme fails;
- existing generated research cannot be overwritten without `--force`;
- generated raw evidence path stays under ignored run evidence;
- command updates the planning manifest with research artifact and evidence
  metadata without approving artifacts;
- Hermes and pipeline contracts expose the command.

Validation command:

```bash
scripts/collect-boss-idea-research.sh --dry-run <run-id>
scripts/collect-boss-idea-research.sh <run-id> --search-results agentic/fixtures/boss-idea-response/valid-market-search-results.yaml --output agentic/runs/<run-id>/market-research.md
scripts/validate-boss-idea-research.sh agentic/runs/<run-id>/market-research.md
scripts/run-golden-fixtures.sh
```

Rollback notes: remove the collector command, search schema, fixtures, Hermes
action, pipeline references, and generated golden fixture coverage.

AIT review evidence path: `agentic/reviews/boss-idea-response/bir-09/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: if round 5 fails, split query-pack generation from
research artifact generation or keep only the provider contract while deferring
artifact generation.

## Review Expectations

Each slice must pass validation and AIT plus Claude Code review before the next
dependent slice starts. If a review fails, fix the finding and rerun. If round 5
fails, the Staff+ board records a decision and continues through the selected
path rather than leaving the delivery blocked indefinitely.
