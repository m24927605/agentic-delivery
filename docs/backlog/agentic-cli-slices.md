# Agentic CLI Implementation Slices

Source spec: `docs/superpowers/specs/2026-05-27-agentic-cli-design.md`
Per-slice plans: `docs/superpowers/plans/2026-05-27-agentic-cli/CLI-NN-*.md`
Authority: planning-run manifest only. Hermes memory is execution context only.

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

## CLI-06 — shell.py + agentic plan namespace
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-06-shell-plan-namespace.md
- write_scope: cli/**
- dependencies: [CLI-05]
- implementer: agency-agents/senior-developer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-security-engineer, engineering-code-reviewer]
- evidence: agentic/reviews/agentic-cli/CLI-06/

## CLI-07 — agentic impl namespace
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-07-impl-namespace.md
- write_scope: cli/**
- dependencies: [CLI-06]
- implementer: agency-agents/senior-developer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-security-engineer, engineering-code-reviewer]
- evidence: agentic/reviews/agentic-cli/CLI-07/

## CLI-08 — agentic boss namespace
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-08-boss-namespace.md
- write_scope: cli/**
- dependencies: [CLI-06]
- implementer: agency-agents/senior-developer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-code-reviewer]
- evidence: agentic/reviews/agentic-cli/CLI-08/

## CLI-09 — Remaining namespaces (hermes, identity, evidence, fixtures, manifest, validate)
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-09-remaining-namespaces.md
- write_scope: cli/**
- dependencies: [CLI-06]
- implementer: agency-agents/senior-developer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-security-engineer, engineering-code-reviewer]
- evidence: agentic/reviews/agentic-cli/CLI-09/

## CLI-10 — agentic raw escape hatch
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-10-raw-escape-hatch.md
- write_scope: cli/**
- dependencies: [CLI-06]
- implementer: agency-agents/senior-developer
- reviewer: claude-code-cli-via-ait [engineering-security-engineer, engineering-code-reviewer]
- evidence: agentic/reviews/agentic-cli/CLI-10/

## CLI-11 — --json mode + structured errors
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-11-json-mode-structured-errors.md
- write_scope: cli/**
- dependencies: [CLI-07, CLI-08, CLI-09, CLI-10]
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
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-code-reviewer]
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
