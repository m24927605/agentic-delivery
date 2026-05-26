# Agentic Identity Authorization Slices

## Slice Rules

H23-H26 implement the strong identity and authorization hardening stream. Each
slice is intentionally small enough for adversarial AIT + Codex CLI Staff+ review.

Every slice must include:

- scope;
- files touched;
- acceptance criteria;
- validation command;
- rollback notes;
- AIT review evidence path;
- maximum 5 review rounds;
- Staff+ escalation path.

Review evidence remains ignored under:

```text
agentic/reviews/auto-doc-to-implementation/<slice-id>/round-<n>.json
agentic/reviews/auto-doc-to-implementation/<slice-id>/decision-log.md
```

## H23: Identity Policy Foundation

Status: implemented.

Scope: add a public-safe actor, role, action, and separation-of-duty policy with
a repo-local validator and authorization helper.

Files touched:

- `agentic/identity-policy.yaml`
- `agentic/schemas/identity-policy.schema.yaml`
- `scripts/lib/agentic_identity.rb`
- `scripts/authorize-agentic-action.sh`
- `scripts/validate-identity-policy.sh`
- `scripts/validate-agentic-system.sh`
- `agentic/pipeline.yaml`
- `docs/architecture/agentic-identity-authorization.md`
- `docs/backlog/agentic-identity-authorization-slices.md`

Acceptance criteria:

- policy validates roles, actors, actions, defaults, and separation-of-duty
  action references;
- authorization helper resolves actor and role from explicit input,
  environment, or action defaults;
- unauthorized role/action combinations fail closed;
- scaffold validation includes the identity policy and scripts;
- tracked policy contains only public-safe actor identifiers.

Validation command:

```bash
scripts/validate-identity-policy.sh
scripts/authorize-agentic-action.sh --action artifact.approve --format json
scripts/authorize-agentic-action.sh --action implementation.task.execute --actor codex_cli_staff_reviewer --role code_reviewer
scripts/validate-agentic-system.sh
```

The `codex_cli_staff_reviewer` worker-execution authorization command must fail.

Rollback notes: revert H23 files and remove ignored H23 review evidence.

AIT review evidence path:

```text
agentic/reviews/auto-doc-to-implementation/h23/round-<n>.json
agentic/reviews/auto-doc-to-implementation/h23/decision-log.md
```

Maximum review rounds: 5.

Staff+ escalation path: Staff Software Architect, Staff Security Engineer,
Staff Platform Engineer, Staff QA Architect, and Staff Technical Writer decide
whether to simplify policy shape, split validation, defer optional actors, or
accept a documented local-identity limitation.

## H24: Actor-Gated Artifact Decisions

Status: implemented.

Scope: require authorization for artifact status updates and stricter approval
authorization for `approved` transitions.

Files touched:

- `scripts/update-artifact-status.sh`
- `scripts/validate-manifest-schema.sh`
- `agentic/schemas/manifest.schema.yaml`
- `agentic/README.md`
- `docs/architecture/agentic-delivery-system.md`
- `docs/backlog/agentic-identity-authorization-slices.md`

Acceptance criteria:

- status updates record actor, role, authorization action, policy, and
  identity authority;
- `approved` uses `artifact.approve`, not just generic status update;
- artifact owner agent cannot approve the same artifact;
- missing or unauthorized actor fails before manifest mutation;
- existing approval gate behavior remains unchanged for authorized actors.

Validation command:

```bash
scripts/validate-identity-policy.sh
scripts/validate-agentic-system.sh
```

Rollback notes: revert H24 files and remove ignored H24 run and review evidence.

AIT review evidence path:

```text
agentic/reviews/auto-doc-to-implementation/h24/round-<n>.json
agentic/reviews/auto-doc-to-implementation/h24/decision-log.md
```

Maximum review rounds: 5.

Staff+ escalation path: the Staff+ board decides whether to split approval
audit fields, narrow the separation-of-duty rule, or keep approval as a
documented manual gate until external identity exists.

## H25: Worker And Reviewer Separation

Status: implemented.

Scope: record authorized worker and reviewer identities and block a worker from
reviewing its own implementation result.

Files touched:

- `scripts/dispatch-implementation-task.sh`
- `scripts/execute-implementation-task.sh`
- `scripts/run-implementation-review-loop.sh`
- `scripts/validate-implementation-run.sh`
- `agentic/schemas/manifest.schema.yaml`
- `agentic/README.md`
- `docs/architecture/agentic-delivery-system.md`
- `docs/backlog/agentic-identity-authorization-slices.md`

Acceptance criteria:

- dispatch records authorized dispatch actor metadata;
- worker results record actor, role, and authorization metadata;
- review attempts record reviewer actor, role, and authorization metadata;
- the latest worker actor cannot record the review result for the same task;
- validation rejects malformed worker and review authorization records.

Validation command:

```bash
scripts/validate-identity-policy.sh
scripts/validate-agentic-system.sh
scripts/validate-implementation-run.sh <implementation-run-id>
```

Rollback notes: revert H25 files and clear ignored H25 worker/review evidence.

AIT review evidence path:

```text
agentic/reviews/auto-doc-to-implementation/h25/round-<n>.json
agentic/reviews/auto-doc-to-implementation/h25/decision-log.md
```

Maximum review rounds: 5.

Staff+ escalation path: the Staff+ board chooses whether to split dispatch,
worker execution, and review recording or accept a documented limitation.

## H26: Hermes Mutating Action Authorization

Status: implemented.

Scope: require Hermes mutating action execution to pass the identity policy
before rendering and running repo-local commands.

Files touched:

- `agentic/hermes-actions.yaml`
- `scripts/run-hermes-action.sh`
- `scripts/validate-hermes-actions.sh`
- `agentic/README.md`
- `docs/architecture/hermes-orchestration-adapter.md`
- `docs/backlog/agentic-identity-authorization-slices.md`

Acceptance criteria:

- every executable mutating Hermes action declares an authorization action;
- runner accepts global actor and role identity inputs without passing them to
  command templates;
- unauthorized Hermes mutating action execution fails closed before command
  execution;
- authorized identity propagates to called repo-local scripts through
  environment variables;
- dry-runs remain available for every action.

Validation command:

```bash
scripts/validate-identity-policy.sh
scripts/validate-hermes-actions.sh
scripts/run-hermes-action.sh --dry-run update_artifact_status run_id=<run-id> artifact_path=<path> status=approved reason=<reason>
```

Rollback notes: revert H26 files and remove ignored Hermes smoke evidence.

AIT review evidence path:

```text
agentic/reviews/auto-doc-to-implementation/h26/round-<n>.json
agentic/reviews/auto-doc-to-implementation/h26/decision-log.md
```

Maximum review rounds: 5.

Staff+ escalation path: the Staff+ board decides whether to narrow Hermes
execution, keep identity enforcement only in called scripts, or defer specific
actions until external identity is available.
