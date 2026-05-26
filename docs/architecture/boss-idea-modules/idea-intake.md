# Idea Intake Module

## Purpose

Idea Intake turns a vague executive idea into a structured, reviewable request
before research or implementation starts.

## Scope

Active scope:

- capture the raw idea and requested outcome;
- identify decision owner, response deadline, and urgency class;
- classify the request as research, recommendation, POC, MVP, or defer;
- record assumptions, non-goals, known constraints, and required artifacts;
- prevent direct implementation from an untriaged idea.

## Deferred Scope

- automatic prioritization across the full company roadmap;
- budget approval;
- staffing commitment;
- external ticket-system synchronization.

## Workflow

```text
raw idea
  -> intake form or goal file
  -> urgency and response class
  -> required artifact set
  -> planning manifest
  -> Staff+ triage review
```

## Artifact Schema

Markdown artifact fields:

- `idea_id`
- `raw_idea`
- `decision_owner`
- `requested_by_role`
- `requested_response_time`
- `urgency_class`
- `response_class`
- `business_question`
- `target_user_or_operator`
- `assumptions`
- `constraints`
- `non_goals`
- `required_artifacts`
- `triage_recommendation`

## CLI / Manifest / Pipeline Contract

Future command:

```bash
scripts/init-boss-idea-run.sh --goal-file <path>
```

Contract:

- creates a planning manifest;
- records the selected `boss-idea-response` profile;
- records idea metadata in a public-safe manifest field;
- initializes all required module artifacts as `planned`;
- does not draft, approve, or implement anything.

## Failure Behavior

Block initialization when:

- idea text is empty;
- run id is invalid;
- goal file path is not repo-local;
- decision owner is missing;
- requested-by role is missing;
- requested response time is missing;
- business question is missing;
- response class is unknown.

## Validation Strategy

Validation checks:

- YAML frontmatter parses safely;
- required fields are present;
- response class is one of `research`, `recommendation`, `poc`, `mvp`, or
  `defer`;
- no private identifiers or credentials are written to tracked files.

## Test Cases

- valid idea goal file initializes a planning run;
- missing decision owner fails;
- missing requested response time fails;
- unknown response class fails;
- absolute or parent-directory goal path fails;
- implementation run from unapproved intake artifact fails.

## Acceptance Criteria

- A triaged idea always has a decision owner, deadline, response class, and
  required artifact set.
- Intake output is public-safe and manifest-backed.
- No implementation task can be generated from intake alone.

## Doc Review Standard

Codex CLI Staff+ review must check that the intake artifact separates raw idea,
business question, constraints, and non-goals, and that it does not imply
approval.

## Code Review Standard

Implementation review must verify input validation, repo-local path safety,
manifest updates, negative-path tests, and privacy scan evidence.

## Rollback

Revert the intake command, profile additions, and fixtures. Remove ignored run
directories created by intake smoke tests.

## Review Expectations

Review must confirm that intake reduces ambiguity without creating an automatic
commitment to research, POC, MVP, or implementation.
