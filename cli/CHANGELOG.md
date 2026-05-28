# Changelog

All notable changes to the `agentic-delivery` CLI.

## [0.1.0] — 2026-05-28

### Added
- `agentic` CLI scaffold: Typer root, `--help`, `version`.
- Global flags: `--repo`, `--run-id`, `--actor`, `--role`, `--json`,
  `--no-compat-check`, `-v`, `-vv`, `--no-color`.
- Repo discovery (flag > env > walk-up > config).
- Pipeline compatibility check (`pipeline.compat_version`) with
  `--no-compat-check` escape hatch.
- Run-context resolution (flag > env > file) and `agentic run list/use/show/clear`.
- Read-only `Manifest` loader and `agentic status` (text + JSON).
- Declarative state engine and `agentic next` (suggest-only).
- Namespaces wrapping the full `scripts/` catalog: `plan`, `impl`, `boss`,
  `hermes`, `identity`, `evidence`, `fixtures`, `manifest`, `validate`.
- `agentic raw <script.sh>` escape hatch with name validation and
  structured `script_failed` errors.
- `--json` envelope `_schema: agentic.cli/v1` with snapshot-locked schema.
- Structured errors (`AgenticError`) with text + JSON renderers.
- `agentic doctor` batching `validate-agentic-system`,
  `validate-manifest-schema --all`, `privacy-scan-tracked`, and
  `validate-identity-policy`; aggregates failures as `validation_failed`
  (exit 3); JSON mode emits `checks: [...]` array.
- Tab completion via `agentic --install-completion <bash|zsh|fish>`
  (Typer built-in).
- CI matrix (`ubuntu-latest` + `macos-latest` × Python 3.10–3.13) with
  ruff, mypy `--strict`, pytest coverage gate (≥85%), and end-to-end
  smoke script.

### Notes
- Wraps `scripts/*.sh`; does not mutate manifests.
- `agency-agents` Staff+ implementers, AIT + Claude Code CLI adversarial review.
