# /goal: Move Agentic Delivery System Toward Fully Automated Docs-to-Implementation

## Objective

Advance this repository toward a fully automated pipeline that can:

1. Generate planning/design documents from a goal.
2. Review each document adversarially with AIT + Claude Code CLI.
3. Revise documents after each review round.
4. Approve only reviewed artifacts.
5. Convert approved artifacts into implementation slices.
6. Execute implementation slices safely.
7. Review implementation slices with AIT + Claude Code CLI.
8. Continue toward PR/release automation without leaking private strategy or secrets.

Current repo state is a public-safe scaffold. Treat private strategy docs, private profiles, and review evidence as local-only ignored artifacts unless the user explicitly says otherwise.

## Hard Constraints

- Do not expose organization strategy, private product identifiers, client details, secrets, tokens, review ownership tokens, private profiles, or ignored docs in tracked files.
- Before any commit, scan tracked files for private strategy strings and secret patterns.
- `agentic/runs/<run-id>/manifest.yaml` and `implementation-manifest.yaml` remain the authoritative state.
- Hermes memory or agent memory is execution context only, never authoritative state.
- Every Hermes action must map to a repo-local command that can be manually rerun.
- Claude Code agency-agents review must be real. Do not simulate reviewer output.
- Every document must go through AIT adversarial review.
- Every implementation-oriented document must be split into small implementation slices.
- Each review loop is capped at 5 rounds.
- After every review round, revise the document or implementation before the next review.
- If a document or slice cannot pass after 5 rounds, convene an internal Staff-level AI review council and make a decision. Do not get stuck in review.

## Use Agency Agents

First inspect available agency-agents / Claude Code agents:

```bash
ls ~/.claude/agents 2>/dev/null || true
find .claude -maxdepth 3 -type f 2>/dev/null || true
command -v claude || true
```

Use the closest installed agents from agency-agents for each role. Prefer these if available:

- `technical-writer` for docs clarity and structure.
- `software-architect` for architecture, ADRs, system boundaries, task slicing.
- `product-manager` for acceptance criteria and artifact approval flow.
- `security-engineer` for secret handling, permission gates, adversarial review risks.
- `code-reviewer` for implementation review.
- `devops-automator` or `sre` for validation, CI, release/PR automation.
- `git-workflow-master` for commit hygiene and safe history.
- `senior-developer` or `backend-architect` for implementation feasibility.

If exact names differ, use the closest installed agent. Do not fail just because one agent name is unavailable.

## Immediate Target

Implement the next foundational slice:

```text
H7: Artifact Status + Approval Gate
```

This is required before fully automated implementation, because implementation must only consume approved artifacts.

H7 must define and enforce this lifecycle:

```text
planned
-> drafted
-> reviewed
-> changes_requested
-> approved
-> rejected
-> deferred
```

## Required H7 Deliverables

Create or update public-safe scaffold documents only. Do not include private strategy.

Required docs:

1. Architecture update:
   - `docs/architecture/agentic-delivery-system.md`
   - Explain artifact lifecycle and approval gate.

2. Hermes adapter architecture update:
   - `docs/architecture/hermes-orchestration-adapter.md`
   - Explain new Hermes action contracts for artifact approval/status.

3. ADR:
   - `docs/adr/005-artifact-approval-gate.md`
   - Decide how artifacts become approved, rejected, deferred, or changes requested.

4. Backlog / slice plan:
   - `docs/backlog/hermes-adapter-implementation-slices.md`
   - Add H7 and next slices H8-H13 at a high level:
     - H8 `generate_artifacts`
     - H9 review-fix loop
     - H10 implementation task graph
     - H11 worker dispatch
     - H12 test/CI and PR publisher
     - H13 Hermes-native memory/skills/scheduler/gateway integration

5. README update:
   - `agentic/README.md`
   - Document how to approve artifacts and how implementation consumes approved artifacts.

Required implementation:

1. Add script:
   - `scripts/update-artifact-status.sh`
   - Usage:
     ```bash
     scripts/update-artifact-status.sh <run-id> <artifact-path> <status> [--reason <text>]
     ```
   - Valid statuses:
     ```text
     planned drafted reviewed changes_requested approved rejected deferred
     ```
   - Must update planning `manifest.yaml`.
   - Must reject invalid run id, missing manifest, unknown artifact, invalid status.
   - Must append state/history metadata sufficient for audit.

2. Update:
   - `scripts/init-agentic-run.sh`
   - Ensure planning manifest artifacts include explicit status, timestamps, and decision/reason fields.

3. Update:
   - `scripts/init-implementation-run.sh`
   - When using `--planning-run <id>`, only consume artifacts whose status is `approved`.
   - If no approved artifacts exist, fail clearly with `blocked_missing_approved_artifact` semantics.

4. Update:
   - `scripts/report-run-status.sh`
   - Include counts:
     - `artifacts_total`
     - `artifacts_approved`
     - `artifacts_pending`
     - `artifacts_rejected`
     - `artifacts_deferred`

5. Update:
   - `scripts/validate-agentic-system.sh`
   - Include the new script in required files and shell syntax validation.

6. Update:
   - `agentic/hermes-actions.yaml`
   - Add action contract for `update_artifact_status` or `approve_artifact`.
   - Every action must map to a repo-local command.

7. Keep default public-safe profile:
   - `agentic/profiles/default-delivery.yaml`
   - Do not reintroduce private profile as tracked file.

## Implementation Slice Rules

For any implementation document or code change, slice work into small slices. Each slice must have:

- Scope
- Files touched
- Acceptance criteria
- Validation command
- Rollback notes
- AIT review record path
- Maximum 5 review rounds
- Staff-level escalation path after 5 failed rounds

A slice is too large if it changes unrelated concerns, touches many unrelated files, or cannot be validated with focused commands.

## Document Drafting Workflow Using Agency Agents

For each required document:

1. Assign drafting to a suitable agency-agent:
   - ADR: `software-architect`
   - Architecture: `software-architect` + `technical-writer`
   - README: `technical-writer`
   - Backlog/slices: `product-manager` + `software-architect`
   - Security/approval gates: `security-engineer`

2. Ask the agent to produce only the relevant document patch or structured notes.

3. Integrate the draft into the repo yourself.

4. Run validation.

5. Run AIT adversarial review.

## AIT Adversarial Review Workflow

For every document and every implementation slice, use AIT + Claude Code CLI.

Before each review:

```bash
unset ANTHROPIC_API_KEY
```

Use this pattern, replacing `<agent-name>` and `<prompt>`:

```bash
ait run --adapter claude-code --stdin none --apply never --review never --format json -- \
  "$(command -v claude)" \
  --add-dir "$PWD" \
  --agent <agent-name> \
  -p "<prompt>"
```

Preferred review agents:

- `code-reviewer`
- `software-architect`
- `security-engineer`
- `technical-writer`

If `command -v claude` fails, find the local Claude Code CLI path and use that. Do not use Anthropic SDK or external API key mode.

Save review outputs locally under ignored paths:

```text
agentic/reviews/auto-doc-to-implementation/<doc-or-slice-id>/round-<n>.json
agentic/reviews/auto-doc-to-implementation/<doc-or-slice-id>/decision-log.md
```

Review prompt must ask for:

- Blocking correctness issues
- Contract mismatch
- Missing validation
- Security/privacy leakage
- Over-large slice scope
- Ambiguous approval semantics
- Runtime vs delivery-system boundary drift
- Whether implementation can safely consume only approved artifacts

## Review Loop

For each doc or slice:

```text
draft / implement
-> validate
-> AIT review round 1
-> fix findings
-> validate
-> AIT review round 2
-> fix findings
...
-> max round 5
```

Pass condition:

```text
status: pass
recommendation: approve
no blocking issue
```

If round 5 still does not pass:

1. Convene Staff-level internal council using available agency-agents:
   - `software-architect`
   - `senior-developer` or `backend-architect`
   - `security-engineer`
   - `technical-writer`
   - `product-manager`
2. Ask them to decide:
   - accept with known risk
   - simplify scope
   - split into smaller slice
   - defer part of the requirement
   - change design
3. Record the council decision in the local ignored decision log.
4. Apply the decision and continue. Do not stop indefinitely at review.

## Required Validation

At minimum run:

```bash
scripts/validate-agentic-system.sh
scripts/validate-hermes-actions.sh
bash -n scripts/update-artifact-status.sh
```

Also run focused smoke tests:

```bash
rm -rf agentic/runs/h7-approval-smoke
RUN_ID=h7-approval-smoke scripts/init-agentic-run.sh "H7 approval smoke"
scripts/report-run-status.sh h7-approval-smoke

# Pick one artifact path from the manifest and approve it.
scripts/update-artifact-status.sh h7-approval-smoke <artifact-path> approved --reason "H7 smoke approval"

scripts/report-run-status.sh h7-approval-smoke
RUN_ID=h7-implementation-smoke scripts/init-implementation-run.sh --planning-run h7-approval-smoke
scripts/validate-implementation-run.sh h7-implementation-smoke
scripts/report-run-status.sh h7-implementation-smoke

rm -rf agentic/runs/h7-approval-smoke agentic/runs/h7-implementation-smoke
find agentic/runs -maxdepth 2 -type f | sort
```

Expected cleanup result:

```text
agentic/runs/.gitkeep
```

## Privacy / Secret Safety Gate

Before committing, run tracked-file scans:

```bash
git grep -n -i \
  -e "private product identifier" \
  -e "private strategy document" \
  -e "client identifier" \
  -e "ownership[_-]token" \
  HEAD -- . || true
```

Also scan current tracked files:

```bash
git ls-files -z | xargs -0 rg -n \
  "(-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{20,}|[A-Za-z0-9_]*(SECRET|TOKEN|PASSWORD|PRIVATE_KEY|ACCESS_KEY)[A-Za-z0-9_]*\\s*=\\s*['\\\"][^'\\\"]{8,})" || true
```

If either scan finds real private content or secrets in tracked files, fix before committing.

Generic words such as `profile`, `strategy_gate`, `credential`, or `secret` in documentation may be acceptable when they describe safety concepts, but company-specific strategy and real secret values are not acceptable.

## Git / AIT Requirements

- Keep ignored private files local.
- Do not use `git push --mirror`.
- Do not push unless explicitly requested.
- Commit public-safe scaffold changes only.
- After successful validation and review, commit changes.
- Then run:

```bash
ait merge --to main --dry-run --format json --no-interactive
ait merge --to main --no-interactive --format json
```

If `ait merge` is blocked due to AIT metadata but `main` already contains the committed safe result, report that clearly and do not force unsafe merges.

## Final Response Requirements

When finished, report:

- Files changed
- New scripts/actions
- Review rounds completed per doc/slice
- Staff council decisions, if any
- Validation commands and results
- Privacy/secret scan result
- Commit SHA
- Whether `ait merge --to main` succeeded
- Remaining gaps toward full docs-to-implementation automation

> **CLI equivalence note:** every `scripts/<x>.sh` reference in this prompt may also be invoked via the `agentic` CLI (see `agentic/README.md` "Quick start (CLI)"). The shell form remains canonical; the CLI is a thin wrapper.
