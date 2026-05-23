# Feasibility Scoring Module

## Purpose

Feasibility Scoring turns research and engineering judgment into a transparent
score that helps decide whether to do nothing, continue research, build a POC,
or define an MVP.

## Scope

Active scope:

- score value, urgency, effort, risk, confidence, reversibility, and dependency
  complexity;
- record known unknowns;
- map score bands to recommendation categories;
- keep scoring explainable and reviewable.

## Deferred Scope

- automatic portfolio prioritization;
- financial forecast modeling;
- headcount allocation;
- binding roadmap commitment.

## Workflow

```text
idea intake + market evidence
  -> scoring inputs
  -> per-dimension scores
  -> weighted summary
  -> recommendation band
  -> review and decision memo input
```

## Artifact Schema

YAML-compatible scoring fields:

- `value_score`
- `urgency_score`
- `effort_score`
- `technical_risk_score`
- `security_risk_score`
- `market_confidence_score`
- `implementation_confidence_score`
- `reversibility_score`
- `dependency_score`
- `unknowns`
- `score_rationale`
- `recommendation_band`

Scores use `1` to `5`; direction is explicit per field:

| Field group | Direction |
| --- | --- |
| `value_score`, `urgency_score`, `market_confidence_score`, `implementation_confidence_score`, `reversibility_score` | Higher is better. |
| `effort_score`, `technical_risk_score`, `security_risk_score`, `dependency_score` | Higher is worse. |

The recommendation band must account for both groups instead of averaging all
scores as if higher always meant better.

## CLI / Manifest / Pipeline Contract

Future command:

```bash
scripts/score-boss-idea-feasibility.sh <run-id>
```

Contract:

- reads approved or reviewed intake and research artifacts;
- writes a scoring artifact or manifest summary;
- records missing input as blocked state;
- never changes artifact approval state.

## Failure Behavior

Block scoring when:

- intake artifact is missing;
- research evidence is missing for market-facing claims;
- any required score dimension is absent;
- rationale is missing for a high value or high risk score;
- unknowns are empty while confidence is low.

## Validation Strategy

Validation checks:

- all score fields are integers from 1 to 5;
- recommendation band is one of `no_go`, `defer`, `research_more`, `poc`, or
  `mvp`;
- high-risk scores require mitigation notes;
- low-confidence scores require follow-up questions.

## Test Cases

- complete scorecard passes;
- missing dimension fails;
- score outside 1 to 5 fails;
- high risk without mitigation fails;
- low confidence without unknowns fails;
- scorecard attempts to approve implementation fails.

## Acceptance Criteria

- The scorecard explains why the recommendation is not arbitrary.
- A reviewer can trace each high score and each risk to source evidence or
  engineering rationale.
- The scorecard is advisory and cannot approve implementation.

## Doc Review Standard

Claude Code review must check whether the score definitions are consistent,
whether risk and confidence are separated, and whether recommendation bands are
clear.

## Code Review Standard

Implementation review must check numeric validation, missing-field failures,
manifest write safety, and tests for advisory-only behavior.

## Rollback

Revert scoring templates and validators. Remove ignored scoring smoke outputs.

## Review Expectations

Review must confirm that scoring supports decision-making without pretending to
be a precise financial or roadmap model.
