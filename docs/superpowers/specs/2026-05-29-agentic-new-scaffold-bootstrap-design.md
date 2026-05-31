# `agentic new` — Scaffold Bootstrap Design

- **Date**: 2026-05-29
- **Status**: Approved (brainstorm)
- **Owner**: CLI
- **Related**:
  - `cli/agentic/context.py` (resolve_repo, RepoNotFound)
  - `cli/agentic/app.py` (Typer sub-apps)
  - `agentic/pipeline.yaml`, `agentic/profiles/*.yaml`
  - `docs/architecture/agentic-delivery-system.md`
  - `docs/adr/003-agentic-delivery-boundary.md`

## Problem

Installing the CLI via `pipx install agentic-delivery` does not make it immediately usable. The CLI is a wrapper over `scripts/*.sh` and needs a repo containing `agentic/pipeline.yaml` to do anything meaningful. Today the user must additionally `git clone` the reference repo (or otherwise materialize a compatible tree) before any `agentic` command works. This violates the "install → use" expectation set by tools like `cargo`, `npm create`, and `django-admin startproject`.

## Goal

After `pipx install agentic-delivery`, a user can run **one command** to materialize a fresh, validation-passing agentic-delivery project in a chosen directory and start the pipeline immediately.

Non-goals:

- Repo-less mode (where the CLI runs without any project on disk). Manifest authority still lives in a git-tracked repo.
- Cross-platform parity. `scripts/*.sh` remain bash-only; Windows is out of scope for v1.
- In-place scaffold upgrade (`agentic upgrade-scaffold`). Future feature.

## Decisions

1. **Command name**: new top-level command `agentic new <name>`. Avoids collision with existing `agentic init "<goal>"` (planning-run init inside an existing repo). Mirrors `cargo new`, `npm create`, `django-admin startproject`.
2. **Scaffold scope**: Full. Includes both `default-delivery` and `boss-idea-response` profiles plus their schemas, prompts, scripts, fixtures, ADRs, architecture, standards, and backlogs referenced by each profile's `source_of_truth`.
3. **Bundle mechanism**: scaffold tree is shipped inside the wheel at `agentic/scaffold/_scaffold/`, populated at build time by a Hatch build hook that copies tracked files from the repo root. Runtime access via `importlib.resources`.
4. **Versioning**: scaffold is lockstepped to the CLI release. The scaffold's `agentic/pipeline.yaml.version` ships at whatever value is current at build time; the CLI's `COMPATIBLE_PIPELINE_VERSIONS` keeps it in range.
5. **Git init**: enabled by default. `--no-git` skips. When enabled, the command runs `git init -b main`, `git add .`, and a single conventional initial commit.
6. **Target directory**: by default the target must not exist (the command creates it). `--force` allows the target to exist as long as it is empty. A non-empty existing target always fails, regardless of `--force`.
7. **Doctor / RepoNotFound message**: the no-repo error message and `agentic doctor` no-repo branch both include `Or run \`agentic new <name>\` to scaffold a new agentic-delivery project here.` as the fourth remedy.

## Architecture

```text
cli/
  build_scaffold.py            ← Hatch build hook
  pyproject.toml               ← registers build hook, force-includes _scaffold
  agentic/
    app.py                     ← register `new` command
    context.py                 ← RepoNotFound message update
    scaffold/
      __init__.py              ← importlib.resources accessor
      _scaffold/               ← populated at build time, gitignored in CLI source tree
        agentic/...
        scripts/...
        docs/...
        .gitignore
        README.md              ← scaffold-target README template (NOT the reference repo README)
    commands/
      new.py                   ← `agentic new <name>` implementation
      doctor.py                ← no-repo hint update
```

### `agentic new <name>` behavior

```
agentic new <name>
  [--path <parent_dir>]   default: cwd
  [--no-git]              default: git init + initial commit
  [--force]               default: refuse non-empty target; --force permits empty-existing
```

Execution:

1. Resolve `target = (--path or cwd) / <name>`.
2. Decide whether to proceed based on target state:
   - `target` does not exist → create it.
   - `target` exists and is empty and `--force` is set → proceed.
   - `target` exists and is empty and `--force` is **not** set → exit `5` with "target exists; rerun with `--force` to materialize into it".
   - `target` exists and is non-empty (regardless of `--force`) → exit `5` and list up to 5 blocking entries.
3. Iterate `importlib.resources.files("agentic.scaffold._scaffold")` and copy the entire tree to `target`:
   - Preserve POSIX file mode (so `scripts/*.sh` remain executable).
   - Render `{{PROJECT_NAME}}` and `{{CLI_VERSION}}` placeholders in the scaffold `README.md` template.
4. Unless `--no-git`:
   - `git init -b main` in target.
   - `git add .`.
   - `git commit -m "chore: bootstrap agentic-delivery scaffold (CLI v<CLI_VERSION>)"` with no signing override.
5. Print a success banner with next steps:

   ```
   ✅ Scaffolded my-project (default-delivery, boss-idea-response).

   Next steps:
     cd my-project
     scripts/validate-agentic-system.sh
     agentic init "Your first delivery goal"
     agentic next
   ```

Exit codes:

| Code | Meaning |
|------|---------|
| 0 | Success |
| 2 | Invalid invocation (bad `<name>`, e.g. contains `/`, `..`, or empty) |
| 5 | Target exists and is non-empty, or target exists empty without `--force` |
| 7 | Git operation failed (only when `--no-git` not set) |

### Scaffold contents (Full)

Included from this reference repo at build time:

- `agentic/pipeline.yaml`
- `agentic/hermes-actions.yaml`
- `agentic/identity-policy.yaml`
- `agentic/profiles/default-delivery.yaml`
- `agentic/profiles/boss-idea-response.yaml`
- `agentic/schemas/*.yaml` (all 18)
- `agentic/prompts/*.md` (all 10)
- `agentic/fixtures/` (all)
- `agentic/runs/.gitkeep`
- `scripts/*.sh` (all 55) and `scripts/lib/`
- `docs/architecture/agentic-delivery-system.md`
- `docs/architecture/agentic-delivery-automation-roadmap.md`
- `docs/architecture/hermes-orchestration-adapter.md`
- `docs/architecture/agentic-identity-authorization.md`
- `docs/architecture/boss-idea-response-system.md`
- `docs/architecture/boss-idea-modules/` (all)
- `docs/architecture/boss-idea-productionization-roadmap.md`
- `docs/standards/agentic-delivery-quality-standard.md`
- `docs/standards/boss-idea-response-quality-standard.md`
- `docs/adr/003-agentic-delivery-boundary.md`
- `docs/adr/004-hermes-orchestration-adapter.md`
- `docs/adr/005-artifact-approval-gate.md`
- `docs/adr/006-boss-idea-crawl4ai-market-discovery.md`
- `docs/adr/007-boss-idea-no-paid-search-provider.md`
- `docs/runbooks/` (all)
- `docs/backlog/boss-idea-response-slices.md`
- `docs/backlog/boss-idea-productionization-slices.md`
- `.gitignore` (sanitized template — drops repo-specific paths like `docs/connectors/`)
- `README.md` (template; NOT this reference repo's top-level README)

Excluded:

- `cli/` (the CLI is installed via pipx, not vendored)
- `docs/superpowers/` (process docs)
- `docs/backlog/agentic-*.md`, `docs/backlog/hermes-*.md`, `docs/backlog/agentic-cli-slices.md` (this reference repo's roadmap)
- `docs/connectors/`
- `.github/workflows/cli-*.yml`
- `agentic/reviews/`, `agentic/runs/*` (run state; only `.gitkeep` ships)
- The top-level reference `README.md`
- `.envrc`, `.claude/`, `.codex/`, `.agentic/`, `.ait/`

### Build hook

`cli/build_scaffold.py` is a Hatch custom build hook that runs before wheel packaging:

1. Computes repo root as `cli/..`.
2. Reads the allowlist defined in `cli/scaffold_manifest.yaml` (tracked).
3. Clears `cli/agentic/scaffold/_scaffold/` and re-populates it from the allowlist.
4. Validates `agentic/pipeline.yaml.version` is in the CLI's `COMPATIBLE_PIPELINE_VERSIONS`; fails the build on mismatch.
5. Preserves file modes (especially executable bit on `scripts/*.sh`).
6. Strips repo-specific entries from `.gitignore` and writes the sanitized template.

`cli/agentic/scaffold/_scaffold/` is gitignored in the CLI source tree (build artifact, not tracked source).

`cli/scaffold_manifest.yaml` is the single source of truth for what ships. Reviewers can read this file to audit scaffold contents.

### Doctor / context error wording

`cli/agentic/context.py:65-67` updated:

```python
raise RepoNotFound(
    "no agentic-delivery repo found. Pass --repo, set AGENTIC_HOME, "
    "cd into a repo, or run `agentic new <name>` to scaffold a new project here."
)
```

Any code path that surfaces no-repo state (including `agentic doctor`'s rendered output, if it catches `RepoNotFound` and re-renders rather than letting the exception's message propagate) lists the same fourth remedy. The single source of truth for the wording is `context.py`; renderers must reference it rather than duplicate the string.

## Data flow

```
build time:
  repo root (tracked files)
    → build_scaffold.py (allowlist)
      → cli/agentic/scaffold/_scaffold/
        → wheel (force-include)

install time:
  pipx install agentic-delivery
    → wheel unpacked into pipx venv
      → _scaffold/ available via importlib.resources

run time:
  agentic new my-project
    → resolve_target
    → copy_tree(resources, target)
    → (optional) git_init
    → print next-steps banner
```

## Error handling

| Failure mode | Behavior |
|--------------|----------|
| `<name>` contains `/`, `..`, or null | Exit 2, "name must be a single path segment, got `<name>`" |
| Target exists and non-empty | Exit 5, list first 5 entries blocking the operation |
| Target exists, empty, no `--force` | Exit 5, "target exists; rerun with `--force` to materialize into it" |
| Resource copy fails mid-flight | Exit 7 (IO), attempt best-effort cleanup of newly created `target` (only if we created it this run) |
| `git init` / `git add` / `git commit` fails | Exit 7, leave target intact (no rollback), tell user how to redo manually |
| Resource missing (build hook drift) | Exit 8, "scaffold bundle missing — please reinstall the CLI" |

All errors flow through the existing `AgenticError` class so `--json` mode emits structured output.

## Testing

### Unit (`cli/tests/commands/test_new.py`)

- `test_new_creates_valid_repo`: in tmpdir, `agentic new foo` produces a tree where `_is_repo(foo)` is True and `pipeline.yaml.version` matches `COMPATIBLE_PIPELINE_VERSIONS`.
- `test_new_preserves_executable_bit`: every `scripts/*.sh` is executable in the target.
- `test_new_renders_readme_placeholders`: target `README.md` contains `foo` (substituted) and the CLI version string.
- `test_new_git_init_default`: target has a `.git/` and one commit.
- `test_new_no_git_skips_repo`: `--no-git` produces no `.git/`.
- `test_new_existing_nonempty_fails`: target with stray files exits 5.
- `test_new_force_on_empty_dir`: pre-created empty dir + `--force` succeeds.
- `test_new_rejects_bad_name`: names with `/`, `..`, empty → exit 2.
- `test_new_json_mode`: `--json` emits structured success and structured error.

### Context (`cli/tests/test_context.py`)

- `test_repo_not_found_mentions_new`: `RepoNotFound` message contains `agentic new`.

### Build (`cli/tests/test_build_scaffold.py`)

- `test_allowlist_files_present`: every entry in `cli/scaffold_manifest.yaml` exists at repo root before build.
- `test_excluded_paths_not_in_bundle`: `cli/`, `docs/superpowers/`, etc. are absent from the populated `_scaffold/`.
- `test_pipeline_version_in_compat_range`: bundled `pipeline.yaml.version` matches `COMPATIBLE_PIPELINE_VERSIONS`.

### Integration (`cli/tests/integration/test_new_validates.py`)

- `test_scaffolded_project_passes_validate_agentic_system`: `agentic new foo` then run `foo/scripts/validate-agentic-system.sh`; assert exit 0.

Skip integration test on non-POSIX with a clear marker.

## CI

Existing `.github/workflows/cli.yml` runs pytest + mypy + ruff. The new tests fit. Add one job step to verify the build hook produces a non-empty `_scaffold/` after `hatch build`.

`.github/workflows/cli-publish.yml` (release) needs no changes if the build hook runs as part of `hatch build`; the resulting wheel automatically contains the scaffold.

## Migration / backwards compatibility

- No existing command changes shape. `agentic init "<goal>"` keeps its current behavior.
- `context.py:RepoNotFound` message text changes; any tests asserting exact text need updates (one test in `cli/tests/test_context.py`).
- New optional dependency: none. `git` is required at runtime only when `--no-git` is not passed; we detect and surface a clear error if `git` is missing.

## Open questions

None blocking. Future work:

- `agentic upgrade-scaffold` to refresh scaffold files in an existing project against a newer CLI's bundle (with three-way merge / diff prompts).
- Per-profile selective install for power users (`--profile default-delivery` only).
- Windows-friendly `scripts/*.ps1` parity.

## Acceptance criteria

1. `pipx install agentic-delivery && agentic new my-project && cd my-project && scripts/validate-agentic-system.sh` exits 0 with no manual file edits.
2. The materialized project has `git log` showing exactly one initial commit (unless `--no-git`).
3. `agentic doctor` from within the new project reports a healthy scaffold.
4. `agentic new` invoked from outside any repo with `<name>` colliding with a non-empty dir exits 5 and changes nothing.
5. The CLI wheel built from a fresh checkout contains `agentic/scaffold/_scaffold/agentic/pipeline.yaml` and the file has the expected version.
6. The no-repo error message and `agentic doctor` no-repo output both mention `agentic new <name>`.
