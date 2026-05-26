# Agentic Identity And Authorization

## Purpose

This design hardens the Agentic Delivery System with explicit actor identity,
role-based authorization, separation of duty, and audit fields for high-risk
local commands.

The active scope is repo-local enforcement for the scaffold:

- artifact decision updates;
- implementation worker execution;
- implementation code-review recording;
- Hermes mutating action execution;
- validation of the identity policy itself.

The policy is public-safe and lives at `agentic/identity-policy.yaml`.

## Deferred Scope

This design does not claim cryptographic identity proof. The following remain
external integrations:

- SSO or workforce identity;
- OIDC workload identity;
- GitHub team or CODEOWNERS binding;
- signed commits;
- signed artifacts;
- external policy engines such as OPA.

The local policy intentionally records `identity_authority:
repo_local_asserted_actor` so operators do not confuse local command assertions
with external identity proof.

## Authority Model

| Source | Authority | Notes |
| --- | --- | --- |
| `agentic/identity-policy.yaml` | Authoritative | Actor, role, action, and separation-of-duty policy. |
| `scripts/authorize-agentic-action.sh` | Enforcement helper | Resolves actor and role, then checks action permission. |
| Planning manifest | Audit record | Stores artifact status actor, role, authorization action, and reason. |
| Implementation manifest | Audit record | Stores dispatch, worker, and review actor metadata. |
| Hermes memory | Non-authoritative | Cannot grant identity or authorization. |

Actor input can come from CLI flags, `AIT_ACTOR` / `AIT_ACTOR_ROLE`, or policy
action defaults. Defaults keep local smoke tests runnable, but every mutation
records the resolved actor and role.

## Roles And Actions

The policy defines these roles:

- `operator`;
- `approver`;
- `document_builder`;
- `implementation_worker`;
- `code_reviewer`;
- `staff_board`;
- `hermes_operator`;
- `validator`.

Each mutating command maps to a named authorization action such as
`artifact.approve`, `implementation.task.execute`, or
`implementation.review.record`. An actor is authorized only when:

- the actor exists in the policy;
- the selected role is assigned to that actor;
- the selected role is allowed for the action.

## Separation Of Duty

The local system enforces the rules that are possible with repo-local evidence:

- an artifact owner agent cannot approve its own artifact;
- the actor that executed the latest worker result cannot record the
  implementation code-review pass for the same task;
- a pure code-reviewer role cannot execute an implementation worker task.

Round-5 review exhaustion still requires Staff+ decision evidence. Staff+
decision can accept residual risk, split a slice, defer a sub-scope, simplify
the design, or revise the policy.

## Command Contracts

Validate the policy:

```bash
scripts/validate-identity-policy.sh
```

Authorize one action:

```bash
scripts/authorize-agentic-action.sh --action artifact.approve
scripts/authorize-agentic-action.sh --action implementation.review.record --actor codex_cli_staff_reviewer --role code_reviewer
```

Mutating commands that support explicit actor input use this shape:

```bash
scripts/update-artifact-status.sh <run-id> <artifact-path> approved \
  --reason "<public-safe reason>" \
  --actor local-operator \
  --role approver
```

Hermes action execution accepts identity through environment variables or
global `actor=` / `role=` parameters. The rendered repo-local command remains
the authoritative state transition path.

## Failure Behavior

Authorization failures are explicit and fail closed:

```text
authorization failed: <reason>
blocked_authorization_failed
```

The command does not update manifests after authorization failure. Existing
schema, approval, write-scope, and review-loop failures keep their current
semantics.

## Validation Approach

Every identity slice must run:

```bash
scripts/validate-identity-policy.sh
scripts/authorize-agentic-action.sh --action artifact.approve
scripts/validate-agentic-system.sh
scripts/validate-hermes-actions.sh
scripts/privacy-scan-tracked.sh
```

Behavioral slices also require a negative-path check, for example:

- unauthorized artifact approval fails;
- a worker cannot review its own implementation result;
- Hermes mutating action execution fails when actor/role is not authorized;
- tracked files stay public-safe.

## Rollback Approach

Rollback is a normal git revert of the identity slice files plus removal of
ignored run and review evidence. Since manifests under `agentic/runs/` are
ignored local evidence, rollback does not require changing tracked run state.

## Privacy Boundary

Actor ids in tracked policy are generic public-safe identifiers. Do not add
employee identifiers, private team labels, client identifiers, private emails, tokens, or
external account ids to tracked policy. External identity bindings belong in
ignored local configuration or future integration-specific policy.
