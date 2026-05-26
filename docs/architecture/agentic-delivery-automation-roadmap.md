# Agentic Delivery Automation Roadmap

## Purpose

This roadmap defines the remaining automation work for the Agentic Delivery
System after CI publishing, PR packaging, and strong identity controls were
removed from the active scope. The active roadmap keeps the system focused on
artifact generation, review, approval, implementation slicing, worker dispatch,
and Hermes dry-run orchestration.

This roadmap is the post-H13 automation map. H14-H22 are now implemented as
repo-local commands, schemas, validators, fixtures, and Hermes action policy.

The quality target is zero known blocking defects at merge time. Each slice must
meet its acceptance criteria, pass validation, and pass AIT-driven Codex CLI Staff+
review before the next slice proceeds.

## Staff+ Review Board

Remaining automation decisions are owned by a Staff+ AI review board:

| Role | Responsibility |
| --- | --- |
| Staff Software Architect | Maintains manifest authority, slice boundaries, and system contracts. |
| Staff Platform Engineer | Owns repo-local command behavior, worker dispatch, and Hermes action fit. |
| Staff Security Engineer | Reviews privacy boundary, command safety, evidence handling, and redaction. |
| Staff QA Architect | Owns acceptance criteria, regression fixtures, and validation evidence. |
| Staff Technical Writer | Ensures artifacts are implementation-ready and public-safe. |
| Product Manager | Confirms the slice solves the intended delivery workflow without expanding scope. |

The board is used for slice design, fifth-round review deadlocks, and decisions
that would otherwise create unclear state transitions.

## Authority Model

The current authority model stays unchanged:

- planning manifests own artifact lifecycle state;
- implementation manifests own approved inputs and task state;
- Git-tracked docs own public-safe design and process contracts;
- Hermes memory is execution context only;
- AIT and Codex CLI Staff+ outputs are review evidence only;
- implementation consumes only artifacts marked `approved`.

No future slice may approve an artifact from chat, memory, worker output, or
review output alone. Approval remains an explicit manifest status transition.

## Active Automation Gaps

### Deferred Capabilities And Trust Boundary

H12 CI/PR publishing, automated CI feedback ingestion, and strong identity
controls are not active requirements. The remaining system is a local delivery
scaffold with explicit operator decisions and ignored local evidence.

Local audit metadata can show which command produced an artifact, review, or
state transition. It cannot prove real-world actor identity, authorize a
publication, or replace a future identity design. Any future publishing or
strong identity capability must be introduced through a separate design and
slice set.

### Review Findings To Artifact Revision

Current review loops record evidence and block repeated review without changed
content. The next gap is turning accepted review findings into bounded artifact
revision tasks while preserving the manifest lifecycle.

Required behavior:

- extract actionable findings from ignored review evidence;
- map each finding to one artifact path and one revision task;
- update the artifact only through a normal draft revision;
- record the changed content hash before re-review;
- move the artifact to `changes_requested`, `drafted`, or `reviewed` through
  explicit status updates.

### Artifact Template And Schema Enforcement

Generated and requested artifacts need stricter shape checks. The system should
validate that each artifact type contains the sections needed for implementation,
review, rollback, and approval.

Required behavior:

- define required sections per artifact kind;
- fail validation when an artifact lacks acceptance criteria, validation steps,
  rollback notes, or review expectations;
- keep templates public-safe and repo-local;
- allow goal-file requested artifacts to declare additional document needs.

### Manifest Schema And Migration

Manifests are authoritative, so their shape needs field-level documentation and
validation. Scripts must not drift into undocumented state fields.

Required behavior:

- define planning and implementation manifest versions;
- document required and optional fields;
- document valid task and artifact states;
- define compatibility behavior for older ignored run manifests;
- fail validation when a manifest violates required invariants;
- document migration rules before changing a manifest version.

### Implementation Worker Execution

Worker dispatch currently emits bounded instructions and protects write scopes.
The next gap is executing an implementation worker against one task while
recording local evidence and preserving disjoint ownership.

Required behavior:

- execute only one task at a time unless write scopes are disjoint;
- pass approved inputs, task scope, validation command, and rollback notes to
  the worker;
- keep raw worker output ignored;
- update implementation task state only through repo-local commands;
- reject execution when the task lacks acceptance criteria or validation.

### Post-Dispatch Worker Completion

Dispatch is not complete until the worker result is recorded in the
implementation manifest and local evidence shows what changed.

Required behavior:

- define worker result status values;
- record changed files, validation command, validation result, and rollback note;
- map worker failure to a blocked state rather than a silent retry;
- require a completed worker result before implementation review starts;
- keep stdout and full transcripts ignored.

### Implementation Review-Fix Loop

Every completed implementation slice needs a bounded review-fix loop using AIT
and Codex CLI Staff+ as the reviewer. Review evidence must not become approval
by itself.

Required behavior:

- run Codex CLI Staff+ reviewer through AIT after each slice implementation;
- cap review at 5 rounds;
- require a fix or explicit Staff+ decision after every failed round;
- prevent a next review round when the implementation has not changed;
- record the final pass, deferral, or Staff+ decision in ignored evidence.

### Concurrency And Lease Model

Disjoint write scopes are necessary but not sufficient. The system also needs a
local lease model so active task ownership, stale dispatch records, and partial
failures are deterministic.

Required behavior:

- record active write-scope leases in the implementation manifest;
- reject overlapping active leases;
- document stale lease recovery without treating local metadata as identity;
- update manifests atomically where practical;
- escalate conflicting worker outputs to Staff+ decision.

### Golden Fixtures And Regression Tests

The existing smoke scripts validate command shape. The remaining gap is fixture
coverage that catches regressions in manifest state, generated task graphs,
artifact status transitions, and Hermes action contracts.

Required behavior:

- add public-safe fixture inputs for planning, requested artifacts,
  implementation runs, and review-fix outcomes;
- compare expected manifest fields instead of raw timestamps;
- verify privacy scans stay clean;
- keep fixture updates small enough to review per slice.

### Local Validation Evidence

With CI feedback deferred, local validation evidence becomes the proof that a
slice reached `tests_passed` or equivalent readiness state.

Required behavior:

- capture validation command, exit status, and redacted output in ignored files;
- include at least one relevant negative-path check per slice;
- record which validation evidence path supports the task state;
- avoid claiming tests passed from stdout text alone;
- require privacy scans before tracked readiness summaries are written.

### Evidence Retention And Redaction

Review, validation, and worker outputs need precise retention rules. The default
is that full evidence remains ignored and tracked files contain only
public-safe summaries.

Required behavior:

- list allowed tracked evidence fields;
- list ignored evidence paths;
- redact command metadata that can contain local trace values;
- reject tracked raw review transcripts, worker stdout, or local run manifests;
- require tracked-file scans before commit.

### Hermes Execute-Mode Policy

Hermes-native work is dry-run first. Execute mode needs a policy before any
action is allowed to mutate state through Hermes orchestration.

Required behavior:

- list which actions may be executed by Hermes and which remain manual;
- require repo-local command mapping for every executable action;
- require validation before and after mutating actions;
- preserve an operator decision point for approvals and fifth-round deadlocks.

## Deferred Scope

The following items are intentionally out of the active roadmap:

- automated CI feedback ingestion;
- PR package generation, branch push, and PR creation;
- strong identity and authorization controls beyond the current local scaffold.

These can be restored later as new slices, but they must not block H14-H22.

## Slice Progression Rule

Each slice moves through this sequence:

```text
design -> implementation -> local validation evidence -> AIT Codex CLI Staff+ review -> fixes -> pass or Staff+ decision -> merge
```

After any failed review round, the slice must be revised before another review.
If round 5 still has blocking findings, the Staff+ review board records a
decision in ignored evidence and executes the selected path: simplify, split,
defer part of the scope, accept a documented risk, or change the design.
