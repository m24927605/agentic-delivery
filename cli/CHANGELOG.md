# Changelog

All notable changes to the `agentic-delivery` CLI.

## [0.2.0] — 2026-05-31

### Added
- `agentic new <name>` — materialize a fresh agentic-delivery project
  in one step. After `pipx install agentic-delivery`, no separate
  `git clone` is required. Bundles the default-delivery and
  boss-idea-response profiles plus the schemas, prompts, scripts,
  ADRs, architecture, standards, runbooks, and backlogs each
  profile's `source_of_truth` references.
- `--path/-p <dir>` to materialize into a chosen parent directory.
- `--no-git` to skip the bootstrap `git init` + initial commit.
- `--force` to allow scaffolding into an existing **empty** directory.
- Three new exit-code categories: `scaffold_target_exists` (9),
  `scaffold_git_failed` (10), `scaffold_bundle_missing` (11).
- Hatch custom build hook (`cli/build_scaffold.py`) populates the
  scaffold bundle into the wheel at build time; allowlist lives in
  `cli/scaffold_manifest.yaml` for auditable scope.
- Success banner (text) and `--json` envelope (`{status, command,
  target, project_name, cli_version, files_written, git_initialized}`).
- Bootstrap commit is authored as `agentic <agentic@local>` for
  deterministic provenance; banner instructs `git commit --amend
  --reset-author` to claim it.
- `commit.gpgsign` and `tag.gpgsign` are disabled for the bootstrap
  commit so users with global GPG signing don't hit confusing errors.
- `RepoNotFound` and `agentic doctor` no-repo output now offer
  `agentic new <name>` as a remedy alongside `--repo`, `AGENTIC_HOME`,
  and `cd into a repo`.
- End-to-end integration test that installs the wheel and runs
  `scripts/validate-agentic-system.sh` inside the materialized project.

### Fixed
- `_resource_root()` uses `__path__[0]` instead of `__file__.parent`
  so the accessor works when `_scaffold/` ships as a namespace package
  (the wheel layout — the `__init__.py` placeholder is wiped by the
  build hook).
- Local `uv build`/`hatch build` no longer leaves the source-tree
  `_scaffold/__init__.py` placeholder deleted in `git status`.

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
