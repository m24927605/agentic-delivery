# POC/MVP Timebox Module

## Purpose

POC/MVP Timebox defines the smallest useful experiment or product increment for
an approved idea response.

## Scope

Active scope:

- classify work as POC or MVP;
- define timebox, staffing assumption, scope boundary, and demo expectation;
- declare what is intentionally not built;
- define acceptance and rollback criteria;
- require approval before implementation tasks are generated.

## Deferred Scope

- production deployment;
- support model;
- long-term maintenance commitment;
- customer pilot agreement;
- automated cloud provisioning.

## Workflow

```text
approved recommendation
  -> POC or MVP class
  -> timebox
  -> scope boundary
  -> demo and validation plan
  -> approval gate
  -> implementation task graph
```

## Artifact Schema

Schema source of truth: `agentic/schemas/boss-idea-poc-mvp.schema.yaml`.

Markdown fields:

- `work_type`
- `timebox_days`
- `staffing_assumption`
- `scope_in`
- `scope_out`
- `demo_path`
- `validation_command`
- `acceptance_criteria`
- `rollback_notes`
- `decision_after_timebox`

## CLI / Manifest / Pipeline Contract

Future command:

```bash
scripts/plan-boss-idea-poc-mvp.sh [poc|mvp]
```

Contract:

- requires a reviewed or approved decision memo;
- writes a POC/MVP plan;
- does not initialize implementation unless the plan artifact is approved;
- implementation tasks must derive only from approved plan inputs.

## Failure Behavior

Block POC/MVP planning when:

- work type is missing or unknown;
- timebox is missing;
- scope-out list is empty;
- demo path is missing;
- validation command is missing;
- acceptance criteria are missing;
- plan attempts to include production launch without explicit scope.

The production launch guard applies to `scope_in`; production deployment should
normally appear in `scope_out` for POC/MVP plans.

Generated templates default `decision_after_timebox` to `stop` as a conservative
sentinel until the reviewer records the actual post-timebox decision.

## Validation Strategy

Validation checks:

- `work_type` is `poc` or `mvp`;
- timebox matches configured limits;
- scope-in and scope-out are both present;
- validation command is repo-local;
- rollback notes are present;
- approved artifacts are required before task graph generation.

## Test Cases

- valid POC plan passes;
- valid MVP plan passes;
- missing timebox fails;
- missing scope-out fails;
- non repo-local validation command fails;
- implementation task graph from unapproved plan fails.

## Acceptance Criteria

- The plan is small enough for one bounded implementation slice or a small set
  of dependent slices.
- A reviewer can decide whether the timebox succeeded.
- The plan protects the team from POC scope expanding into unapproved MVP work.

## Doc Review Standard

Claude Code review must check whether the timebox, scope-out list, demo path,
and post-timebox decision are explicit.

## Code Review Standard

Implementation review must check task graph boundaries, write scopes, validation
commands, rollback notes, and unapproved artifact blocking.

## Rollback

Revert planning templates and commands. Remove ignored POC/MVP run output.

## Review Expectations

Review must confirm that timebox planning reduces risk and does not create
implicit production commitments.
