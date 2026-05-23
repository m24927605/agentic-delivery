# Success Metrics Module

## Purpose

Success Metrics defines how the team decides whether research, POC, or MVP work
answered the original idea.

## Scope

Active scope:

- define qualitative and quantitative success criteria;
- define evidence collection method;
- define pass, fail, and inconclusive thresholds;
- connect metrics to the post-timebox decision;
- keep metrics measurable within the selected timebox.

## Deferred Scope

- long-term product analytics platform;
- revenue attribution;
- customer pilot telemetry;
- automated executive dashboards.

## Workflow

```text
decision memo + POC/MVP plan
  -> metrics
  -> evidence method
  -> threshold
  -> validation record
  -> go/no-go input
```

## Artifact Schema

Metric fields:

- `metric_id`
- `question_answered`
- `measurement_method`
- `target_threshold`
- `minimum_threshold`
- `evidence_path`
- `owner_role`
- `review_method`
- `decision_mapping`

## CLI / Manifest / Pipeline Contract

Future command:

```bash
scripts/validate-boss-idea-success-metrics.sh <run-id>
```

Contract:

- validates metric shape;
- records validation evidence in ignored paths;
- requires metrics before POC/MVP execution can be marked complete;
- does not decide go/no-go by itself.

## Failure Behavior

Block metric approval when:

- no metric maps to the original business question;
- thresholds are missing;
- evidence method is missing;
- owner role is missing;
- metric cannot be measured inside the timebox;
- metric implies automatic go/no-go without decision review.

## Validation Strategy

Validation checks:

- every metric has method, threshold, owner, and decision mapping;
- pass/fail/inconclusive mapping is explicit;
- evidence path is ignored or public-safe;
- metric count is small enough for the timebox.

## Test Cases

- complete metric plan passes;
- missing threshold fails;
- missing owner role fails;
- tracked raw evidence path fails;
- unmeasurable metric fails;
- automatic decision claim fails.

## Acceptance Criteria

- The team knows before implementation what evidence will count as success.
- The metric plan supports go/no-go without hiding uncertainty.
- Metrics are realistic for the chosen POC or MVP timebox.

## Doc Review Standard

Claude Code review must check metric relevance, measurability, thresholds,
evidence paths, and decision mapping clarity.

## Code Review Standard

Implementation review must check metric validation, evidence path handling,
negative-path tests, and manifest state updates.

## Rollback

Revert metric templates and validators. Remove ignored metric validation output.

## Review Expectations

Review must confirm that success metrics make the next decision easier, not more
ambiguous.
