# Agentic CLI Implementation Slices

Source spec: `docs/superpowers/specs/2026-05-27-agentic-cli-design.md`
Per-slice plans: `docs/superpowers/plans/2026-05-27-agentic-cli/CLI-NN-*.md`
Authority: planning-run manifest only. Hermes memory is execution context only.

## CLI-00 — Bootstrap slice tracking (operational, completed during CLI design approval)
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-00-bootstrap-slice-tracking.md
- write_scope: docs/backlog/agentic-cli-slices.md, agentic/runs/agentic-cli-v0.1-planning/manifest.yaml, agentic/runs/agentic-cli-v0.1-impl/implementation-manifest.yaml
- dependencies: []
- status: in-progress (this revision)
- implementer: local-operator (operational bootstrap — chicken-and-egg, cannot dispatch through the very pipeline being seeded)
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-security-engineer, engineering-code-reviewer, engineering-technical-writer, product-manager]
- evidence: agentic/reviews/agentic-cli/CLI-00/

## CLI-01 — Scaffold `cli/` package
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-01-scaffold-package.md
- write_scope: cli/**
- dependencies: []
- implementer: agency-agents/senior-developer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-code-reviewer]
- evidence: agentic/reviews/agentic-cli/CLI-01/

## CLI-02 — Repo discovery + compat check
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-02-repo-discovery-compat.md
- write_scope: cli/**
- dependencies: [CLI-01]
- implementer: agency-agents/senior-developer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-security-engineer, engineering-code-reviewer]
- evidence: agentic/reviews/agentic-cli/CLI-02/

## CLI-03 — Run-context resolution + agentic run commands
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-03-run-context-resolution.md
- write_scope: cli/**, .gitignore (one line)
- dependencies: [CLI-02]
- implementer: agency-agents/senior-developer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-security-engineer, engineering-code-reviewer]
- evidence: agentic/reviews/agentic-cli/CLI-03/

## CLI-04 — manifest.py reader + agentic status
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-04-manifest-reader-status.md
- write_scope: cli/**
- dependencies: [CLI-03]
- implementer: agency-agents/senior-developer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-code-reviewer, engineering-technical-writer]
- evidence: agentic/reviews/agentic-cli/CLI-04/

## CLI-05 — State engine v1 + agentic next
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-05-state-engine-next.md
- write_scope: cli/**
- dependencies: [CLI-04]
- implementer: agency-agents/senior-developer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-code-reviewer, product-manager]
- evidence: agentic/reviews/agentic-cli/CLI-05/

## CLI-06 — shell.py + agentic plan namespace + agentic init
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-06-shell-plan-namespace.md
- write_scope: cli/**
- dependencies: [CLI-05]
- implementer: agency-agents/senior-developer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-security-engineer, engineering-code-reviewer]
- evidence: agentic/reviews/agentic-cli/CLI-06/
- notes: Also wires top-level `agentic init "goal"` per spec §5.1 (closes coverage gap flagged in round-1 review)

## CLI-10 — agentic raw escape hatch (floor of wrapper coverage)
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-10-raw-escape-hatch.md
- write_scope: cli/**
- dependencies: [CLI-06]
- implementer: agency-agents/senior-developer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-security-engineer, engineering-code-reviewer]
- evidence: agentic/reviews/agentic-cli/CLI-10/
- notes: Lands BEFORE CLI-07/08/09a/09b so `agentic raw` is available throughout the rest of the rollout (spec §5.7 promise)

## CLI-07 — agentic impl namespace
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-07-impl-namespace.md
- write_scope: cli/**
- dependencies: [CLI-10]
- implementer: agency-agents/senior-developer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-security-engineer, engineering-code-reviewer]
- evidence: agentic/reviews/agentic-cli/CLI-07/

## CLI-08 — agentic boss namespace (24 scripts, 12 validators)
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-08-boss-namespace.md
- write_scope: cli/**
- dependencies: [CLI-10]
- implementer: agency-agents/senior-developer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-security-engineer, engineering-code-reviewer]
- evidence: agentic/reviews/agentic-cli/CLI-08/

## CLI-09a — hermes + identity namespaces (security-heavy)
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-09-remaining-namespaces.md  (will be split during implementation)
- write_scope: cli/**
- dependencies: [CLI-10]
- implementer: agency-agents/senior-developer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-security-engineer (mandatory), engineering-code-reviewer]
- evidence: agentic/reviews/agentic-cli/CLI-09a/

## CLI-09b — evidence + fixtures + manifest + validate namespaces
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-09-remaining-namespaces.md  (will be split during implementation)
- write_scope: cli/**
- dependencies: [CLI-10]
- implementer: agency-agents/senior-developer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-code-reviewer]
- evidence: agentic/reviews/agentic-cli/CLI-09b/

## CLI-11 — --json mode + structured errors + cli_v1.schema.json
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-11-json-mode-structured-errors.md
- write_scope: cli/**
- dependencies: [CLI-07, CLI-08, CLI-09a, CLI-09b]
- implementer: agency-agents/senior-developer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-code-reviewer, engineering-technical-writer, product-manager]
- evidence: agentic/reviews/agentic-cli/CLI-11/

## CLI-12 — Tab completion + agentic doctor
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-12-completion-and-doctor.md
- write_scope: cli/**
- dependencies: [CLI-11]
- implementer: agency-agents/senior-developer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-code-reviewer]
- evidence: agentic/reviews/agentic-cli/CLI-12/

## CLI-13 — CI workflow + e2e smoke
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-13-ci-and-smoke.md
- write_scope: .github/workflows/cli.yml, cli/tests/smoke/**, cli/pyproject.toml (cov config)
- dependencies: [CLI-12]
- implementer: agency-agents/senior-developer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-security-engineer (mandatory: .github/workflows/* is a supply-chain trust boundary), engineering-code-reviewer]
- evidence: agentic/reviews/agentic-cli/CLI-13/

## CLI-14 — README + goal-prompt footnotes
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-14-readme-and-goal-prompt-footnotes.md
- write_scope: agentic/README.md, docs/auto-docs-to-implementation-goal-prompt.md, docs/hermes-adapter-slices-goal-prompt.md (if tracked)
- dependencies: [CLI-12]
- implementer: agency-agents/senior-developer
- reviewer: claude-code-cli-via-ait [engineering-technical-writer, product-manager, engineering-software-architect]
- evidence: agentic/reviews/agentic-cli/CLI-14/

## CLI-15 — PyPI publish workflow + v0.1.0 release
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-15-pypi-publish-release.md
- write_scope: .github/workflows/cli-publish.yml, cli/CHANGELOG.md
- dependencies: [CLI-13, CLI-14]
- implementer: agency-agents/senior-developer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-security-engineer, engineering-code-reviewer]
- evidence: agentic/reviews/agentic-cli/CLI-15/

---

## Purpose

Track the public-safe slice backlog for the agentic CLI v0.1 implementation, mapping each slice to its detailed plan, write scope, dependencies, implementer (agency-agents Senior Developer), and adversarial reviewer roster (Claude Code CLI via AIT).

## Scope

In scope: the 15 implementation slices CLI-01 .. CLI-15 that build the `agentic` CLI inside this repo, the operational CLI-00 bootstrap that seeded the planning + implementation runs, and the post-round-1 split of CLI-09 into CLI-09a (hermes + identity, security-heavy) and CLI-09b (evidence + fixtures + manifest + validate). Each slice's full file-by-file plan lives at `docs/superpowers/plans/2026-05-27-agentic-cli/CLI-NN-*.md`. CLI-09a/09b will share the existing `CLI-09-remaining-namespaces.md` plan, split into two halves during implementation.

Documented `cli/**` write_scope exceptions:

- `.gitignore` — one line, CLI-03 (`.agentic/` for the run-context file).
- `agentic/README.md`, `docs/auto-docs-to-implementation-goal-prompt.md`, `docs/hermes-adapter-slices-goal-prompt.md` (if tracked) — CLI-14 footnotes.
- `.github/workflows/cli.yml` — CLI-13 (CI workflow; supply-chain boundary, mandatory security review).
- `.github/workflows/cli-publish.yml` — CLI-15 (PyPI publish trust root; supply-chain boundary, mandatory security review).
- `cli/pyproject.toml` re-opened for coverage configuration in CLI-13 (technically inside `cli/**` so not really an exception; called out here for clarity).

Out of scope here: any path not under `cli/**` or the documented exceptions above, Hermes adapter changes, distribution channels beyond PyPI, and post-v0.1 features.

## Acceptance Criteria

The backlog is accepted when: (1) every slice listed maps 1:1 to its plan file under `docs/superpowers/plans/2026-05-27-agentic-cli/`; (2) each slice records implementer = `agency-agents/senior-developer` (or higher), reviewer runtime = `claude-code-cli-via-ait`, and evidence directory under `agentic/reviews/agentic-cli/CLI-NN/`; (3) dependencies form a valid DAG matching the sequencing diagram in spec §13.x; (4) write_scope of every slice is strictly inside `cli/**` or the documented exceptions; (5) the planning run that owns this backlog passes `scripts/validate-manifest-schema.sh`, `scripts/validate-artifact-templates.sh`, and `scripts/privacy-scan-tracked.sh`.

## Validation

This backlog is validated by: (a) `scripts/validate-manifest-schema.sh agentic-cli-v0.1-planning` exit 0; (b) `scripts/validate-artifact-templates.sh agentic-cli-v0.1-planning` exit 0 (the file you are reading provides the required H2 sections — Purpose, Scope, Acceptance Criteria, Validation, Rollback, Review Expectations); (c) `scripts/privacy-scan-tracked.sh` exit 0; (d) for each slice, the per-slice plan validates against its own acceptance criteria (TDD tests, ruff, mypy, coverage ≥ 85, AIT + Claude Code CLI adversarial review evidence).

## Rollback

If the backlog needs withdrawal before any slice ships: mark this artifact `rejected` in the planning manifest with a public-safe reason. Because the backlog drives nothing on its own (it is documentation), the rollback is a documentation revert. If a downstream slice has already landed and the slice itself needs reversal, follow that slice's own Rollback section in its plan file. The implementation manifest can be reset by deleting `agentic/runs/agentic-cli-v0.1-impl/` (it is gitignored) and re-running CLI-00 Task 4 after the corrective plan is in place.

## Review Expectations

Each slice CLI-01 .. CLI-15 goes through adversarial AIT + Claude Code CLI review per spec §12.3 — no direct Anthropic API calls; `--apply never --review never --sandbox read-only --format json`. Review agents per slice are listed inline above. Review evidence lands under `agentic/reviews/agentic-cli/CLI-NN/round-N.json`, ignored by git. Five-round cap per the existing pipeline rule; round-5 unresolved findings move the slice to `blocked_human_decision_required`. This backlog itself is reviewed alongside spec `docs/superpowers/specs/2026-05-27-agentic-cli-design.md` by `engineering-software-architect`, `engineering-technical-writer`, and `product-manager` in the planning run that owns it.
