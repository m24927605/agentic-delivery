# Boss Idea Response System

## Purpose

Boss Idea Response System is an extension of the Agentic Delivery System for
handling urgent, ambiguous, or exploratory executive ideas without turning every
idea directly into engineering work.

The system converts an idea into bounded research, explicit recommendation,
POC or MVP scope, success metrics, and go/no-go decisions. It keeps the same
authority model as the base scaffold: repo-local manifests and tracked
artifacts are authoritative; AI, Hermes, AIT, and Claude Code outputs are
evidence only.

## Staff+ Review Board

The review board is responsible for design quality, scope control, and final
deadlock decisions after five failed review rounds.

| Role | Responsibility |
| --- | --- |
| Product Strategy Lead | Defines business question, target user, decision owner, and expected outcome. |
| Market Research Lead | Owns source quality, competitor evidence, mainstream practice summary, and citation hygiene. |
| Staff Software Architect | Owns technical options, architecture tradeoffs, integration boundary, and manifest contracts. |
| Staff Platform Engineer | Owns repo-local commands, workflow automation, Hermes action fit, and operational feasibility. |
| Staff Security Engineer | Owns privacy boundary, security risk, data handling, evidence redaction, and approval safety. |
| Staff QA Architect | Owns validation strategy, negative-path tests, success metrics, and POC/MVP acceptance evidence. |
| Staff Technical Writer | Owns executive-readable memo format, public-safe language, and doc review completeness. |
| Engineering Manager | Owns capacity, timebox, staffing, delivery sequence, and escalation path. |

The board does not replace artifact approval. It records recommendations,
residual risks, and deadlock decisions. Implementation still requires approved
artifacts in the planning manifest.

## Scope

Active scope:

- capture a vague or urgent idea as a structured intake record;
- gather market and competitor evidence with citations and freshness metadata;
- score feasibility, impact, effort, risk, confidence, and reversibility;
- produce an executive decision memo with clear recommendation;
- define POC or MVP timebox and implementation boundary;
- define measurable success metrics and evidence requirements;
- record go/no-go decisions without bypassing artifact approval;
- split implementation work into small reviewable slices.

Deferred scope:

- automatic web crawling or paid market data ingestion;
- automatic product roadmap approval;
- automatic budget approval;
- automatic PR publishing or deployment;
- external identity proof beyond repo-local actor policy;
- treating AI-generated market research as authoritative without cited sources.

## End-To-End Workflow

```text
raw idea
  -> idea intake
  -> market research evidence
  -> feasibility scoring
  -> solution options and recommendation
  -> boss decision memo
  -> POC/MVP timebox
  -> success metrics
  -> go/no-go decision
  -> approved implementation artifacts
  -> implementation task graph
  -> worker execution and review
```

Every step produces an artifact that can be reviewed independently. Research
and review evidence remain ignored local evidence unless summarized into a
public-safe tracked artifact.

## Module Map

| Module | Design artifact | Primary output |
| --- | --- | --- |
| Idea Intake | `docs/architecture/boss-idea-modules/idea-intake.md` | Structured idea brief |
| Market Research Evidence | `docs/architecture/boss-idea-modules/market-research-evidence.md` | Source-backed market scan |
| Feasibility Scoring | `docs/architecture/boss-idea-modules/feasibility-scoring.md` | Scored feasibility record |
| Boss Decision Memo | `docs/architecture/boss-idea-modules/boss-decision-memo.md` | Executive recommendation |
| POC/MVP Timebox | `docs/architecture/boss-idea-modules/poc-mvp-timebox.md` | POC or MVP plan |
| Success Metrics | `docs/architecture/boss-idea-modules/success-metrics.md` | Measurement plan |
| Go/No-Go Decision | `docs/architecture/boss-idea-modules/go-no-go-decision.md` | Decision record |

## Artifact Set

The profile-backed deliverables are:

- `docs/architecture/boss-idea-response-system.md`
- `docs/architecture/boss-idea-modules/idea-intake.md`
- `docs/architecture/boss-idea-modules/market-research-evidence.md`
- `docs/architecture/boss-idea-modules/feasibility-scoring.md`
- `docs/architecture/boss-idea-modules/boss-decision-memo.md`
- `docs/architecture/boss-idea-modules/poc-mvp-timebox.md`
- `docs/architecture/boss-idea-modules/success-metrics.md`
- `docs/architecture/boss-idea-modules/go-no-go-decision.md`
- `docs/backlog/boss-idea-response-slices.md`
- `docs/standards/boss-idea-response-quality-standard.md`

## Authority Model

| State or evidence | Authority | Notes |
| --- | --- | --- |
| Planning manifest | Authoritative | Owns artifact lifecycle and approval state. |
| Implementation manifest | Authoritative | Owns approved inputs, task state, validation records, and leases. |
| Tracked boss idea artifacts | Authoritative | Own public-safe design, recommendation, and acceptance contracts. |
| Market source excerpts | Evidence | Must cite source, access date, and confidence. |
| AIT / Claude Code review | Evidence | Cannot approve artifacts or implementation by itself. |
| Hermes memory | Non-authoritative | May schedule and remind, but cannot decide or approve. |

## Lifecycle States

The extension uses the base artifact lifecycle:

```text
planned drafted reviewed changes_requested approved rejected deferred
```

Recommended idea decision states are recorded inside artifacts and manifest
decision records:

```text
triage_research research_complete recommend_do recommend_defer
recommend_no_go poc_approved mvp_approved go no_go pivot
```

These states do not replace artifact lifecycle status. A `go` decision is not
implementation authority unless the relevant artifacts are also `approved`.

## CLI / Manifest / Pipeline Contract

Initial implementation should add only repo-local commands and Hermes actions
after the design artifacts are approved. Expected future commands:

- `scripts/init-boss-idea-run.sh`
- `scripts/generate-boss-idea-artifacts.sh`
- `scripts/validate-boss-idea-artifacts.sh`
- `scripts/report-boss-idea-status.sh`

The commands must write only ignored run manifests and tracked public-safe
artifacts. Hermes actions must call these commands rather than implementing
logic in Hermes memory.

## Failure Behavior

The system must block or escalate when:

- the idea lacks a decision owner or requested response time;
- market research lacks source citations or dates;
- feasibility scoring omits risk, effort, confidence, or unknowns;
- a POC/MVP has no timebox or success criteria;
- a go/no-go decision is attempted without reviewed artifacts;
- implementation starts without approved artifacts;
- review reaches round 5 without pass.

Round 5 failures are resolved by the Staff+ board. The board may simplify,
split, defer, change the design, or accept a documented residual risk.

## Validation

Baseline validation:

```bash
scripts/validate-agentic-system.sh
scripts/validate-hermes-actions.sh
scripts/privacy-scan-tracked.sh
PROFILE=boss-idea-response scripts/validate-agentic-system.sh
```

Future implementation validation must include positive and negative checks for
missing citations, missing timebox, missing success metrics, unapproved
implementation inputs, and tracked evidence privacy.

## Rollback

Documentation rollback is a normal git revert of the boss idea response docs
and profile. Future command rollback must remove only new commands, Hermes
actions, ignored run output, and related fixture data for the affected slice.

## Acceptance Criteria

- Staff+ board roles are defined with clear ownership.
- Each required module has a formal design artifact.
- Each module design includes purpose, scope, deferred scope, workflow,
  artifact schema, contracts, failure behavior, validation, tests, acceptance
  criteria, doc review standard, code review standard, rollback, and review
  expectations.
- Implementation work is split into small slices in a backlog artifact.
- AIT plus Claude Code review is required for documentation and implementation
  slices.
- Five-round review limit and Staff+ deadlock decision are documented.
- No artifact bypasses the base approval gate.

## Review Expectations

Reviewers must verify that this extension improves executive idea response
without weakening manifest authority, approval gates, privacy boundaries, or
review discipline.
