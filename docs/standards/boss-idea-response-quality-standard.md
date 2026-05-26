# Boss Idea Response Quality Standard

## Purpose

This standard defines the quality bar for Boss Idea Response System artifacts
and implementation slices.

## Scope

Applies to:

- Staff+ review board definitions;
- idea intake artifacts;
- market research evidence artifacts;
- feasibility scoring artifacts;
- boss decision memos;
- POC/MVP timebox plans;
- success metric plans;
- go/no-go decision records;
- future commands and Hermes actions that implement this workflow.

## Acceptance Criteria

A boss idea response slice is ready only when:

- scope maps to an approved design artifact or backlog slice;
- artifact lifecycle and implementation approval still use repo-local manifests;
- market claims have citation metadata or are labeled as inference;
- recommendation, risk, timebox, metric, and next decision are explicit;
- tracked files remain public-safe;
- validation commands pass;
- AIT plus Codex CLI Staff+ review has no blocking finding;
- any round 5 failure has a Staff+ decision log.

## Validation

Baseline validation:

```bash
scripts/validate-agentic-system.sh
scripts/validate-hermes-actions.sh
scripts/privacy-scan-tracked.sh
scripts/validate-manifest-schema.sh --all
PROFILE=boss-idea-response scripts/validate-agentic-system.sh
```

Future implementation slices must add narrow validation for the changed
behavior and at least one negative-path check.

Until a structural linter exists, doc review evidence must explicitly state
that every module doc contains the required purpose, scope, workflow, artifact
schema, contracts, failure behavior, validation, tests, acceptance, doc review,
and code review sections.

## Doc Review Standard

Documentation review must verify:

- executive idea response is separated from direct implementation;
- all seven modules have explicit contracts and failure behavior;
- every module includes acceptance criteria and review standards;
- source-backed research distinguishes fact, inference, and unknown;
- decision memos are concise and actionable;
- POC/MVP timeboxes have scope-in, scope-out, validation, and rollback;
- success metrics are measurable inside the timebox;
- go/no-go decisions do not bypass artifact approval.

## Code Review Standard

Implementation review must verify:

- commands are repo-local and shell-safe;
- paths reject absolute paths and parent traversal;
- manifests remain authoritative;
- Hermes memory is non-authoritative;
- review output is evidence only;
- authorization and separation-of-duty checks apply to mutating actions;
- raw review, research, worker, and validation evidence remain ignored;
- negative-path tests cover missing citations, missing timebox, missing metrics,
  unknown decision value, and unapproved implementation inputs.

## AIT Codex Staff+ Review

Every documentation or implementation slice must use AIT with Codex CLI as a
Staff+ reviewer:

```bash
ait run \
  --adapter codex \
  --stdin none \
  --apply never \
  --review never \
  --no-auto-commit \
  --format json -- \
  "$(command -v codex)" exec \
    --cd "$PWD" \
    --sandbox read-only \
    "<boss idea response review prompt>"
```

Write ignored evidence to:

```text
agentic/reviews/boss-idea-response/<slice-id>/round-<n>.json
agentic/reviews/boss-idea-response/<slice-id>/decision-log.md
```

The `agentic/reviews/` tree is gitignored and must remain untracked. Any
review result summarized into tracked docs must be public-safe and omit raw
review metadata.

## Review Loop Rules

1. Run review after validation evidence is available.
2. If review fails, fix the artifact or implementation before the next round.
3. Do not rerun review without changed content or a Staff+ decision explaining
   why no change is needed.
4. Stop normal retries after round 5.
5. Round 5 failure requires the Staff+ board to choose one outcome: simplify,
   split, defer, change the design, or accept a documented residual risk.

## Test Cases

Required test categories for future implementation:

- valid boss idea run initializes all module artifacts;
- missing idea owner blocks intake;
- missing research citation blocks research completion;
- missing feasibility score dimension blocks scoring;
- POC/MVP plan without timebox fails;
- success metric without threshold fails;
- go decision without metric result fails;
- implementation run without approved artifacts fails;
- tracked raw evidence fails privacy scan;
- Hermes action without repo-local command mapping fails validation.

## Rollback

Documentation rollback is a git revert of the boss idea response docs and
profile. Implementation rollback must remove only the affected command, Hermes
action, fixture, ignored run output, and validation evidence for that slice.

## Review Expectations

Reviewers should evaluate whether the system helps the engineering team respond
quickly to executive ideas while preserving scope control, evidence quality,
and implementation safety.
