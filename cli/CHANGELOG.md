# Changelog

All notable changes to the `agentic-delivery` CLI.

## [0.1.0] — unreleased

- Initial scaffold: Typer root, `version`, `--help`.
- Added `agentic doctor` batching `validate-agentic-system`, `validate-manifest-schema --all`,
  `privacy-scan-tracked`, and `validate-identity-policy`. Failure aggregates as
  `validation_failed` (exit 3); JSON mode emits the `agentic.cli/v1` envelope
  with a `checks: [...]` array.
- Tab completion available via `agentic --install-completion <bash|zsh|fish>`
  (Typer built-in).
- Migrated `agentic raw` error paths (refusals, no_repo, script_failed) from
  `typer.echo + typer.Exit` to structured `AgenticError`, closing the CLI-11
  review gap so non-zero forwarded-script exits emit the standard envelope
  (category `script_failed`, exit `64 + min(rc, 15)`).
