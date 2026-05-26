# Agentic Delivery Quality Standard

## Quality Bar

The Agentic Delivery System does not treat quality as a slogan. A slice is ready
only when all of the following are true:

- scope matches an approved artifact or active roadmap slice;
- implementation touches only declared files or explains the additional file;
- acceptance criteria are satisfied;
- validation commands pass;
- privacy checks are clean for tracked files;
- mutating commands pass the repo-local identity policy when identity hardening
  is in scope;
- review evidence is stored only in ignored paths;
- AIT-driven Codex CLI Staff+ review has no blocking finding;
- any known residual risk is recorded by Staff+ decision.

Because automated CI feedback is deferred, local validation evidence is
mandatory for every slice that changes behavior.

Planning runs that generate non-trivial artifacts require AIT-backed
multi-agent deliberation evidence before draft generation, unless a Staff+
waiver is recorded in the planning manifest. Deliberation evidence is not
approval and does not replace artifact review or implementation review.

For a documentation-only delivery, the review target is the completeness and
consistency of the design, slice plan, validation standard, and review standard.
For a code delivery, the review target is the implemented code plus its
validation and negative-path evidence.

## Design Standard

Every design artifact must state:

- purpose and active scope;
- deferred scope;
- authority model;
- lifecycle state transitions;
- command or interface contracts;
- failure behavior;
- validation approach;
- rollback approach;
- privacy boundary.

When a design artifact is produced from a planning run, it must either reference
the planning deliberation summary or state why the Staff+ waiver allowed the run
to skip deliberation.

Design artifacts must not make Hermes memory authoritative, bypass artifact
approval, or allow unapproved artifacts to drive implementation.

## Implementation Standard

Every implementation slice must state:

- slice id;
- owner role;
- source artifact or roadmap item;
- files touched;
- write scope;
- dependencies;
- acceptance criteria;
- validation command;
- rollback notes;
- review evidence path;
- maximum review rounds;
- Staff+ escalation path.

The implementation must be small enough that a reviewer can decide whether it
meets its own acceptance criteria without re-reading unrelated slices.

## Test And Acceptance Standard

Validation must include the narrow command for the slice and the shared scaffold
checks:

```bash
scripts/validate-agentic-system.sh
scripts/validate-hermes-actions.sh
```

Use additional commands when the slice touches implementation manifests,
Hermes actions, generated artifacts, or worker dispatch:

```bash
scripts/validate-implementation-run.sh <implementation-run-id>
scripts/run-hermes-action.sh --dry-run validate_scaffold
scripts/dispatch-implementation-task.sh --dry-run <implementation-run-id> <task-id>
```

Acceptance evidence should prove behavior through repo-local commands, not
through reviewer opinion alone. Generated ids and timestamps should be checked
as fields, not as brittle full-file snapshots.

Each slice must include at least one relevant negative-path check:

- unapproved artifact blocks implementation;
- non repo-local task path is rejected;
- overlapping write scope is rejected;
- missing Hermes action input is rejected;
- unauthorized actor or role is rejected for identity-gated actions;
- repeated review without changed content is rejected;
- tracked output excludes non-public identifiers and raw local evidence.

Local validation evidence belongs under the slice review directory:

```text
agentic/reviews/auto-doc-to-implementation/<slice-id>/validation-round-<n>.log
```

The evidence should include command, exit status, and redacted output. It should
not be committed.

## AIT Codex Staff+ Review Standard

Each slice must use AIT to invoke Codex CLI as a Staff+ reviewer. The review
command shape is:

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
    "<slice review prompt>"
```

Write the result to the slice evidence path:

```text
agentic/reviews/auto-doc-to-implementation/<slice-id>/round-<n>.json
```

The prompt must ask the reviewer to inspect:

- source artifact or roadmap item;
- implementation diff;
- changed-file list;
- acceptance criteria;
- validation command output;
- negative-path evidence;
- privacy boundary;
- manifest authority and approval gate behavior;
- identity and authorization behavior when the slice touches actor-gated
  actions;
- rollback notes.

## Review Loop Rules

Review loop rules are mandatory:

1. Run review only after the slice implementation and validation are complete.
2. If review passes, record the pass in ignored evidence and proceed.
3. If review fails, fix the finding before the next review round.
4. Do not run the next round without changed code, artifact content, or a
   Staff+ decision explaining why no change is needed.
5. Stop normal retries after round 5.

Round 5 failure requires the Staff+ review board to choose one outcome:

- simplify the slice;
- split the slice;
- defer part of the requirement;
- change the design;
- accept a documented residual risk.

The decision is recorded in:

```text
agentic/reviews/auto-doc-to-implementation/<slice-id>/decision-log.md
```

## Code Review Pass Criteria

Codex CLI Staff+ review passes only when there are no blocking findings in
these areas:

- behavior contradicts the approved artifact or roadmap slice;
- implementation consumes unapproved artifacts;
- Hermes memory becomes authoritative;
- repo-local command mapping is missing or unsafe;
- validation is missing for changed behavior;
- mutating actor authorization or separation-of-duty checks are missing;
- review evidence or local run output would be committed;
- tracked files contain non-public identifiers or credentials;
- rollback path is absent for a mutating slice.

Warnings may remain only when the Staff+ board records why they are acceptable
for this slice and what follow-up will address them.

## Evidence Standard

Tracked evidence:

- design docs;
- backlog slice docs;
- validation commands in scripts and docs;
- public-safe fixtures.

Ignored evidence:

- AIT review output;
- Codex CLI Staff+ review transcripts;
- run manifests;
- worker stdout;
- Staff+ decision logs for blocked review loops.

Ignored evidence may be copied between workspaces for audit, but it must not be
committed.

Before commit, run tracked-file scans for sensitive strings and common secret
assignments:

```bash
scripts/privacy-scan-tracked.sh
scripts/privacy-scan-tracked.sh --cached
```

Record the scan command and result in ignored validation evidence.

## Manifest And Lease Standard

Manifest changes require a schema note that defines:

- version field;
- required fields;
- optional fields;
- valid states;
- compatibility behavior;
- migration rule.

Worker execution changes require a lease note that defines:

- write-scope owner field;
- active and stale lease behavior;
- conflict handling;
- partial failure handling;
- Staff+ escalation path.

Local lease metadata is coordination state only. It is not identity proof.
Identity proof for the repo-local scaffold is the resolved authorization record
from `agentic/identity-policy.yaml`; external identity proof remains an
integration outside this local policy.
