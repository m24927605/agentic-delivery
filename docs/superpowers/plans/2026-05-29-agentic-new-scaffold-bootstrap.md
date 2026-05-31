# `agentic new` Scaffold Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `pipx install agentic-delivery` immediately usable by adding `agentic new <name>`, which materializes a full (default-delivery + boss-idea-response) scaffold bundled inside the wheel.

**Architecture:** Hatch custom build hook copies an allowlisted tree from the repo root into `cli/agentic/scaffold/_scaffold/` at wheel-build time; the new `agentic new` command reads that tree via `importlib.resources`, copies it to the target directory, runs `git init` by default, and prints a next-steps banner. Error wording in `context.py` is updated so any no-repo failure also points at the new command.

**Tech Stack:** Python 3.10+, Typer, Hatch (custom build hook), `importlib.resources`, pytest, PyYAML, ruff, mypy.

**Spec:** `docs/superpowers/specs/2026-05-29-agentic-new-scaffold-bootstrap-design.md`

---

## File Structure

**Create:**
- `cli/scaffold_manifest.yaml` — allowlist of paths from repo root that ship in the scaffold.
- `cli/scaffold_templates/.gitignore` — sanitized `.gitignore` template that overrides repo root's `.gitignore` in the bundle.
- `cli/scaffold_templates/README.md` — project-template README with `{{PROJECT_NAME}}` and `{{CLI_VERSION}}` placeholders.
- `cli/build_scaffold.py` — Hatch custom build hook (copies allowlist + overlays templates + validates pipeline version).
- `cli/agentic/scaffold/__init__.py` — `importlib.resources` accessor module.
- `cli/agentic/commands/new.py` — `agentic new <name>` command.
- `cli/tests/test_build_scaffold.py` — build-hook unit tests.
- `cli/tests/test_commands_new.py` — `agentic new` unit tests.
- `cli/tests/test_integration_new_validates.py` — integration: materialized project passes `validate-agentic-system.sh`.

**Modify:**
- `cli/pyproject.toml` — register the build hook, force-include the populated `_scaffold/` tree in the wheel, add `pyyaml` to dev deps only if missing (it's already a runtime dep).
- `cli/agentic/ui/errors.py` — add three new categories to `EXIT_CODES`.
- `cli/agentic/context.py` — extend `RepoNotFound` message with the fourth remedy.
- `cli/agentic/app.py` — register the `new` command on the root Typer app.
- `cli/agentic/commands/doctor.py` — confirm no-repo branch uses the new wording (read-and-decide; modify only if it duplicates the message rather than letting `RepoNotFound` propagate).
- `cli/tests/test_context.py` — assert new wording appears in the `RepoNotFound` message.
- `cli/.gitignore` — add `agentic/scaffold/_scaffold/` so the build artifact is never tracked.

---

## Task 1: Scaffold manifest and template files

**Files:**
- Create: `cli/scaffold_manifest.yaml`
- Create: `cli/scaffold_templates/.gitignore`
- Create: `cli/scaffold_templates/README.md`
- Modify: `cli/.gitignore`

- [ ] **Step 1: Write `cli/scaffold_manifest.yaml`**

```yaml
# Source of truth for what ships inside the wheel as the agentic-delivery
# scaffold. Paths are relative to the repo root. Reviewed during PRs.
#
# include: copied as-is into _scaffold/
# overlay: copied from cli/scaffold_templates/ and overwrites any include
#          at the same target path (so the scaffold ships a sanitized
#          .gitignore and a project-template README instead of this repo's
#          own versions).
include:
  # Pipeline definition and profiles
  - agentic/pipeline.yaml
  - agentic/hermes-actions.yaml
  - agentic/identity-policy.yaml
  - agentic/profiles/default-delivery.yaml
  - agentic/profiles/boss-idea-response.yaml
  # Schemas, prompts, fixtures
  - agentic/schemas/
  - agentic/prompts/
  - agentic/fixtures/
  - agentic/runs/.gitkeep
  # Scripts
  - scripts/
  # Architecture
  - docs/architecture/agentic-delivery-system.md
  - docs/architecture/agentic-delivery-automation-roadmap.md
  - docs/architecture/hermes-orchestration-adapter.md
  - docs/architecture/agentic-identity-authorization.md
  - docs/architecture/boss-idea-response-system.md
  - docs/architecture/boss-idea-modules/
  - docs/architecture/boss-idea-productionization-roadmap.md
  # Standards
  - docs/standards/agentic-delivery-quality-standard.md
  - docs/standards/boss-idea-response-quality-standard.md
  # ADRs (only those needed by either profile's source_of_truth)
  - docs/adr/003-agentic-delivery-boundary.md
  - docs/adr/004-hermes-orchestration-adapter.md
  - docs/adr/005-artifact-approval-gate.md
  - docs/adr/006-boss-idea-crawl4ai-market-discovery.md
  - docs/adr/007-boss-idea-no-paid-search-provider.md
  # Runbooks
  - docs/runbooks/
  # Backlogs referenced by boss-idea-response profile source_of_truth
  - docs/backlog/boss-idea-response-slices.md
  - docs/backlog/boss-idea-productionization-slices.md

overlay:
  # Files written from cli/scaffold_templates/, overlaying any include.
  - .gitignore
  - README.md
```

- [ ] **Step 2: Write `cli/scaffold_templates/.gitignore`**

```gitignore
.ait/
.envrc
.claude/
.codex/

# Local private delivery artifacts.
.agentic/
docs/connectors/
agentic/reviews/
agentic/runs/*
!agentic/runs/.gitkeep
__pycache__/
```

- [ ] **Step 3: Write `cli/scaffold_templates/README.md`**

````markdown
# {{PROJECT_NAME}}

An agentic-delivery project. Scaffolded with `agentic` CLI v{{CLI_VERSION}}.

## Quick start

```bash
# Validate the scaffold and default profile
scripts/validate-agentic-system.sh

# Start a planning run
agentic init "Your first delivery goal"

# Inspect what to do next
agentic next
agentic status
```

## Profiles

This project ships with two public-safe profiles:

| Profile | Purpose |
|---------|---------|
| `default-delivery` | Generic planning + implementation pipeline runs |
| `boss-idea-response` | Triage executive ideas into research, recommendation, POC, MVP, or no-go |

Switch profile with `PROFILE=<id>` on any pipeline command.

## Pipeline

```
profile + goal
  → planning run
  → AIT multi-agent planning deliberation
  → generated drafts
  → review-fix loop
  → reviewed and approved artifacts
  → implementation run
  → implementation task graph
  → worker dispatch + execution
  → implementation review-fix
  → validation + PR/release preparation
```

See `agentic/README.md` (if vendored) or the reference repo for the full pipeline reference. Run `agentic --help` for CLI commands.

## License

This scaffold is your project's. Choose a license that fits your work.
````

- [ ] **Step 4: Update `cli/.gitignore`** so the build artifact never lands in git

Append to `cli/.gitignore`:

```gitignore
agentic/scaffold/_scaffold/
```

- [ ] **Step 5: Commit**

```bash
git add cli/scaffold_manifest.yaml cli/scaffold_templates/ cli/.gitignore
git commit -m "feat(cli): add scaffold manifest + template overlay (Task 1)

Allowlist of paths shipped into the wheel as the agentic-delivery
scaffold; sanitized .gitignore template; project-template README
with {{PROJECT_NAME}} / {{CLI_VERSION}} placeholders.
"
```

---

## Task 2: Build hook — read manifest, copy tree, overlay templates, validate

**Files:**
- Create: `cli/build_scaffold.py`
- Create: `cli/tests/test_build_scaffold.py`

- [ ] **Step 1: Write the failing test `cli/tests/test_build_scaffold.py`**

```python
"""Tests for cli/build_scaffold.py — the Hatch custom build hook."""
from __future__ import annotations

import os
import stat
import textwrap
from pathlib import Path

import pytest
import yaml

from build_scaffold import ScaffoldBuildHook, ManifestDriftError, PipelineVersionMismatch


def _make_repo(tmp_path: Path) -> Path:
    """Build a minimal fake repo with the structure the hook needs."""
    repo = tmp_path / "repo"
    (repo / "agentic").mkdir(parents=True)
    (repo / "agentic" / "pipeline.yaml").write_text(
        "pipeline:\n  version: v0.6\n", encoding="utf-8"
    )
    (repo / "agentic" / "runs").mkdir()
    (repo / "agentic" / "runs" / ".gitkeep").write_text("", encoding="utf-8")
    (repo / "scripts").mkdir()
    sh = repo / "scripts" / "demo.sh"
    sh.write_text("#!/usr/bin/env bash\necho hi\n", encoding="utf-8")
    sh.chmod(0o755)
    (repo / "docs" / "adr").mkdir(parents=True)
    (repo / "docs" / "adr" / "003-agentic-delivery-boundary.md").write_text(
        "# ADR-003\n", encoding="utf-8"
    )

    (repo / "cli").mkdir()
    (repo / "cli" / "scaffold_templates").mkdir()
    (repo / "cli" / "scaffold_templates" / ".gitignore").write_text(
        ".ait/\n", encoding="utf-8"
    )
    (repo / "cli" / "scaffold_templates" / "README.md").write_text(
        "# {{PROJECT_NAME}}\nCLI v{{CLI_VERSION}}\n", encoding="utf-8"
    )

    (repo / "cli" / "scaffold_manifest.yaml").write_text(
        textwrap.dedent(
            """
            include:
              - agentic/pipeline.yaml
              - agentic/runs/.gitkeep
              - scripts/
              - docs/adr/003-agentic-delivery-boundary.md
            overlay:
              - .gitignore
              - README.md
            """
        ).lstrip(),
        encoding="utf-8",
    )
    return repo


def test_hook_copies_include_tree(tmp_path):
    repo = _make_repo(tmp_path)
    hook = ScaffoldBuildHook(repo_root=repo, compat_versions=[">=0.6,<0.8"])

    out = hook.populate(target=repo / "cli" / "agentic" / "scaffold" / "_scaffold")

    assert (out / "agentic" / "pipeline.yaml").read_text(encoding="utf-8").startswith("pipeline:")
    assert (out / "agentic" / "runs" / ".gitkeep").exists()
    assert (out / "scripts" / "demo.sh").exists()
    assert (out / "docs" / "adr" / "003-agentic-delivery-boundary.md").exists()


def test_hook_preserves_executable_bit(tmp_path):
    repo = _make_repo(tmp_path)
    hook = ScaffoldBuildHook(repo_root=repo, compat_versions=[">=0.6,<0.8"])

    out = hook.populate(target=repo / "out")

    mode = (out / "scripts" / "demo.sh").stat().st_mode
    assert mode & stat.S_IXUSR, f"expected executable bit on demo.sh, got {oct(mode)}"


def test_hook_applies_template_overlay(tmp_path):
    repo = _make_repo(tmp_path)
    hook = ScaffoldBuildHook(repo_root=repo, compat_versions=[">=0.6,<0.8"])

    out = hook.populate(target=repo / "out")

    # .gitignore came from cli/scaffold_templates/, not repo root (which has no .gitignore here)
    assert (out / ".gitignore").read_text(encoding="utf-8") == ".ait/\n"
    # README template ships with placeholders intact — substitution happens at `agentic new` time
    assert "{{PROJECT_NAME}}" in (out / "README.md").read_text(encoding="utf-8")


def test_hook_raises_when_include_missing(tmp_path):
    repo = _make_repo(tmp_path)
    (repo / "agentic" / "pipeline.yaml").unlink()
    hook = ScaffoldBuildHook(repo_root=repo, compat_versions=[">=0.6,<0.8"])

    with pytest.raises(ManifestDriftError) as exc:
        hook.populate(target=repo / "out")
    assert "agentic/pipeline.yaml" in str(exc.value)


def test_hook_rejects_pipeline_version_mismatch(tmp_path):
    repo = _make_repo(tmp_path)
    (repo / "agentic" / "pipeline.yaml").write_text(
        "pipeline:\n  version: v0.5\n", encoding="utf-8"
    )
    hook = ScaffoldBuildHook(repo_root=repo, compat_versions=[">=0.6,<0.8"])

    with pytest.raises(PipelineVersionMismatch):
        hook.populate(target=repo / "out")


def test_hook_clears_existing_target(tmp_path):
    repo = _make_repo(tmp_path)
    target = repo / "out"
    target.mkdir()
    (target / "stale.txt").write_text("old", encoding="utf-8")

    hook = ScaffoldBuildHook(repo_root=repo, compat_versions=[">=0.6,<0.8"])
    hook.populate(target=target)

    assert not (target / "stale.txt").exists()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd cli && uv run pytest tests/test_build_scaffold.py -v`
Expected: ImportError — `No module named 'build_scaffold'`.

- [ ] **Step 3: Write `cli/build_scaffold.py`**

```python
"""Hatch custom build hook that materializes the agentic-delivery scaffold
into ``cli/agentic/scaffold/_scaffold/`` before the wheel is packaged.

The hook reads ``cli/scaffold_manifest.yaml`` for the allowlist of paths to
copy from the repo root, overlays the templates in ``cli/scaffold_templates/``
on top, and refuses to build if the bundled pipeline version drifts out of
the CLI's compatibility range.

Tested via ``cli/tests/test_build_scaffold.py``.
"""
from __future__ import annotations

import re
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

import yaml

try:
    # Hatch is only present at build time; tests use the class directly.
    from hatchling.builders.hooks.plugin.interface import BuildHookInterface
except ImportError:  # pragma: no cover - test-only path
    BuildHookInterface = object  # type: ignore[misc,assignment]


class ManifestDriftError(RuntimeError):
    """Raised when an allowlisted path does not exist at repo root."""


class PipelineVersionMismatch(RuntimeError):
    """Raised when bundled pipeline.yaml.version is outside CLI compat range."""


_VERSION_RANGE_RE = re.compile(r"^>=\s*([0-9.]+)\s*,\s*<\s*([0-9.]+)\s*$")


def _parse_version(raw: str) -> tuple[int, ...]:
    # Accept "v0.6", "0.6", "0.6.0"
    s = raw.strip()
    if s.startswith("v"):
        s = s[1:]
    return tuple(int(part) for part in s.split("."))


def _version_in_range(version: str, ranges: Sequence[str]) -> bool:
    v = _parse_version(version)
    for r in ranges:
        m = _VERSION_RANGE_RE.match(r)
        if not m:
            raise ValueError(f"unsupported compat range: {r!r}")
        lo, hi = _parse_version(m.group(1)), _parse_version(m.group(2))
        if lo <= v < hi:
            return True
    return False


@dataclass
class ScaffoldBuildHook:
    """Populate the scaffold bundle from repo state."""

    repo_root: Path
    compat_versions: Sequence[str]

    @property
    def manifest_path(self) -> Path:
        return self.repo_root / "cli" / "scaffold_manifest.yaml"

    @property
    def templates_dir(self) -> Path:
        return self.repo_root / "cli" / "scaffold_templates"

    def populate(self, target: Path) -> Path:
        manifest = yaml.safe_load(self.manifest_path.read_text(encoding="utf-8"))
        includes = list(manifest.get("include", []))
        overlays = list(manifest.get("overlay", []))

        self._validate_includes(includes)
        self._validate_pipeline_version()

        if target.exists():
            shutil.rmtree(target)
        target.mkdir(parents=True)

        for rel in includes:
            self._copy_include(rel, target)

        for rel in overlays:
            self._copy_overlay(rel, target)

        return target

    def _validate_includes(self, includes: Sequence[str]) -> None:
        missing = [rel for rel in includes if not (self.repo_root / rel).exists()]
        if missing:
            raise ManifestDriftError(
                "scaffold manifest references paths that do not exist: " + ", ".join(missing)
            )

    def _validate_pipeline_version(self) -> None:
        pipeline = self.repo_root / "agentic" / "pipeline.yaml"
        data = yaml.safe_load(pipeline.read_text(encoding="utf-8"))
        version = (data or {}).get("pipeline", {}).get("version")
        if version is None:
            raise PipelineVersionMismatch("agentic/pipeline.yaml has no pipeline.version")
        if not _version_in_range(version, self.compat_versions):
            raise PipelineVersionMismatch(
                f"agentic/pipeline.yaml version {version!r} not in CLI compat {list(self.compat_versions)!r}"
            )

    def _copy_include(self, rel: str, target: Path) -> None:
        src = self.repo_root / rel
        dest = target / rel
        if src.is_dir():
            shutil.copytree(src, dest, symlinks=False, dirs_exist_ok=True)
        else:
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dest)

    def _copy_overlay(self, rel: str, target: Path) -> None:
        src = self.templates_dir / rel
        if not src.exists():
            raise ManifestDriftError(f"overlay template missing: {src}")
        dest = target / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest)


# --- Hatch plugin glue --------------------------------------------------------


class HatchScaffoldBuildHook(BuildHookInterface):  # type: ignore[misc]
    """Hatch entry point. Reads compat versions from the CLI package."""

    PLUGIN_NAME = "scaffold"

    def initialize(self, version: str, build_data: dict) -> None:  # noqa: ARG002 - hatch contract
        repo_root = Path(self.root).parent  # cli/ -> repo root
        compat = self._read_compat_versions(repo_root)
        target = Path(self.root) / "agentic" / "scaffold" / "_scaffold"
        ScaffoldBuildHook(repo_root=repo_root, compat_versions=compat).populate(target)
        build_data.setdefault("artifacts", []).append("agentic/scaffold/_scaffold/**")

    @staticmethod
    def _read_compat_versions(repo_root: Path) -> list[str]:
        # Avoid importing the CLI package during build; parse __init__.py directly.
        init_py = repo_root / "cli" / "agentic" / "__init__.py"
        text = init_py.read_text(encoding="utf-8")
        match = re.search(r"COMPATIBLE_PIPELINE_VERSIONS\s*:\s*list\[str\]\s*=\s*(\[[^\]]+\])", text)
        if match is None:
            raise RuntimeError("could not find COMPATIBLE_PIPELINE_VERSIONS in cli/agentic/__init__.py")
        # Safe eval: the matched literal is a Python list of string literals.
        return list(eval(match.group(1), {"__builtins__": {}}))  # noqa: S307
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd cli && uv run pytest tests/test_build_scaffold.py -v`
Expected: 6 passed.

- [ ] **Step 5: Commit**

```bash
git add cli/build_scaffold.py cli/tests/test_build_scaffold.py
git commit -m "feat(cli): scaffold build hook — copy + overlay + version guard (Task 2)

Hatch custom hook that reads cli/scaffold_manifest.yaml, copies the
allowlist from repo root, overlays cli/scaffold_templates/, validates
agentic/pipeline.yaml.version against COMPATIBLE_PIPELINE_VERSIONS,
and refuses to build on drift.
"
```

---

## Task 3: Register build hook in pyproject and verify wheel content

**Files:**
- Modify: `cli/pyproject.toml`

- [ ] **Step 1: Add the build hook + force-include block to `cli/pyproject.toml`**

Append after the existing `[tool.hatch.build.targets.wheel]` block:

```toml
[tool.hatch.build.targets.wheel.hooks.custom]
path = "build_scaffold.py"
```

Also add `pyyaml >= 6` to `[build-system].requires` so the hook can `import yaml` inside uv's PEP 517 build isolation.

> **Note (Task 3 retrospective)** — an earlier draft of this plan also included a `[tool.hatch.build.targets.wheel.force-include]` block mapping `"agentic/scaffold/_scaffold" = "agentic/scaffold/_scaffold"`. That block is redundant because `HatchScaffoldBuildHook.initialize` already appends `agentic/scaffold/_scaffold/**` to `build_data["artifacts"]`. Including both produces 283 "Duplicate name" warnings (every scaffold file written twice into the wheel zip). Do not re-add it.

Make sure `[tool.hatch.build.targets.wheel].packages` already includes `["agentic"]` (it does — confirm).

- [ ] **Step 2: Run a wheel build**

Run: `cd cli && uv build --wheel`
Expected: wheel produced under `cli/dist/`; build hook ran with no error.

- [ ] **Step 3: Verify the wheel contains the scaffold**

Run:
```bash
cd cli && uv run python -c "import zipfile, glob; w = glob.glob('dist/*.whl')[-1]; names = zipfile.ZipFile(w).namelist(); print([n for n in names if '_scaffold/' in n][:20])"
```
Expected: prints at least 10 paths under `agentic/scaffold/_scaffold/...`, including `agentic/scaffold/_scaffold/agentic/pipeline.yaml`.

- [ ] **Step 4: Commit**

```bash
git add cli/pyproject.toml
git commit -m "build(cli): wire scaffold build hook + force-include _scaffold (Task 3)

Hatch custom build hook now runs on wheel build and the populated
_scaffold/ tree is force-included into the wheel.
"
```

---

## Task 4: Scaffold accessor module

**Files:**
- Create: `cli/agentic/scaffold/__init__.py`
- Modify: `cli/tests/test_build_scaffold.py` (add resource-access tests)

- [ ] **Step 1: Add failing tests to `cli/tests/test_build_scaffold.py`**

Append:

```python
def test_scaffold_iter_resources_lists_bundled_files(tmp_path, monkeypatch):
    # Materialize a fake _scaffold under the package and check iter_resources
    # walks every relative path under it.
    from agentic import scaffold as scaffold_pkg

    fake_root = tmp_path / "pkg" / "_scaffold"
    (fake_root / "agentic").mkdir(parents=True)
    (fake_root / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    (fake_root / "scripts").mkdir()
    (fake_root / "scripts" / "demo.sh").write_text("#!/usr/bin/env bash\n")
    (fake_root / "scripts" / "demo.sh").chmod(0o755)

    monkeypatch.setattr(scaffold_pkg, "_resource_root", lambda: fake_root)

    rels = sorted(scaffold_pkg.iter_resource_paths())
    assert "agentic/pipeline.yaml" in rels
    assert "scripts/demo.sh" in rels


def test_scaffold_read_bytes_returns_file_bytes(tmp_path, monkeypatch):
    from agentic import scaffold as scaffold_pkg

    fake_root = tmp_path / "pkg" / "_scaffold"
    fake_root.mkdir(parents=True)
    (fake_root / "marker.txt").write_bytes(b"hello\n")

    monkeypatch.setattr(scaffold_pkg, "_resource_root", lambda: fake_root)

    assert scaffold_pkg.read_resource_bytes("marker.txt") == b"hello\n"


def test_scaffold_resource_mode(tmp_path, monkeypatch):
    from agentic import scaffold as scaffold_pkg

    fake_root = tmp_path / "pkg" / "_scaffold"
    fake_root.mkdir(parents=True)
    sh = fake_root / "scripts" / "demo.sh"
    sh.parent.mkdir()
    sh.write_text("#!/usr/bin/env bash\n")
    sh.chmod(0o755)

    monkeypatch.setattr(scaffold_pkg, "_resource_root", lambda: fake_root)

    import stat as _stat
    assert scaffold_pkg.resource_mode("scripts/demo.sh") & _stat.S_IXUSR
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd cli && uv run pytest tests/test_build_scaffold.py -v -k scaffold`
Expected: ImportError / AttributeError on `agentic.scaffold`.

- [ ] **Step 3: Write `cli/agentic/scaffold/__init__.py`**

```python
"""Accessor over the bundled scaffold tree at ``agentic/scaffold/_scaffold/``.

Provides three primitives that the ``agentic new`` command uses:

- :func:`iter_resource_paths` — relative paths of every file in the bundle
- :func:`read_resource_bytes` — raw bytes of one file
- :func:`resource_mode` — POSIX mode of one file (so executable bits are
  preserved when copying into the target directory)

Tests monkeypatch ``_resource_root`` to swap in a fake bundle so they don't
need a built wheel.
"""
from __future__ import annotations

from pathlib import Path

from agentic.scaffold import _scaffold  # type: ignore[attr-defined] # populated at build time


class ScaffoldBundleMissing(RuntimeError):
    """Raised when the bundled scaffold tree is empty or absent."""


def _resource_root() -> Path:
    """Return the on-disk root of the bundled scaffold.

    The bundle ships as a regular package directory (not a zipfile), so
    ``Path(_scaffold.__file__).parent`` is a stable, sandboxed location.
    """
    root = Path(_scaffold.__file__).parent
    if not root.is_dir():  # pragma: no cover - defensive
        raise ScaffoldBundleMissing(f"scaffold bundle root is not a directory: {root}")
    return root


def iter_resource_paths() -> list[str]:
    """Walk the bundle and return every file path relative to the bundle root.

    Paths are POSIX-style with forward slashes so they're stable across platforms.
    """
    root = _resource_root()
    files: list[str] = []
    for path in root.rglob("*"):
        if path.is_file():
            files.append(path.relative_to(root).as_posix())
    if not files:
        raise ScaffoldBundleMissing(
            f"scaffold bundle at {root} is empty — reinstall the CLI"
        )
    return files


def read_resource_bytes(relpath: str) -> bytes:
    return (_resource_root() / relpath).read_bytes()


def resource_mode(relpath: str) -> int:
    return (_resource_root() / relpath).stat().st_mode
```

Also create the package marker `cli/agentic/scaffold/_scaffold/__init__.py` (empty file) so the bundle dir resolves as a package during tests when the build hook hasn't run. The real build will overwrite/clear it as part of `populate()`.

Wait — the build hook clears the target and re-populates it; we need `_scaffold` to be importable. Solution: make `_scaffold` a thin module via `__init__.py` placeholder that ALWAYS ships:

Add to `cli/agentic/scaffold/_scaffold/__init__.py`:

```python
"""Bundled scaffold tree — populated at wheel build time. Empty in source."""
```

And add to `cli/.gitignore` (already done in Task 1) so only this `__init__.py` is tracked but the rest of the dir is ignored:

```gitignore
agentic/scaffold/_scaffold/*
!agentic/scaffold/_scaffold/__init__.py
```

Update Step 4 of Task 1 to use that pattern instead of the broad ignore. Make a note here that Task 1 step 4 was insufficient: redo the .gitignore entry to be selective:

```bash
# In cli/.gitignore replace any prior agentic/scaffold/_scaffold/ line with:
agentic/scaffold/_scaffold/*
!agentic/scaffold/_scaffold/__init__.py
```

- [ ] **Step 4: Apply the .gitignore tightening AND create the placeholder `__init__.py`**

```bash
# Edit cli/.gitignore: drop "agentic/scaffold/_scaffold/" if present; add:
#   agentic/scaffold/_scaffold/*
#   !agentic/scaffold/_scaffold/__init__.py

mkdir -p cli/agentic/scaffold/_scaffold
echo '"""Bundled scaffold tree — populated at wheel build time. Empty in source."""' > cli/agentic/scaffold/_scaffold/__init__.py
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd cli && uv run pytest tests/test_build_scaffold.py -v`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add cli/agentic/scaffold/__init__.py cli/agentic/scaffold/_scaffold/__init__.py cli/.gitignore cli/tests/test_build_scaffold.py
git commit -m "feat(cli): scaffold accessor + bundle placeholder (Task 4)

Three primitives over the bundled scaffold tree: iter_resource_paths,
read_resource_bytes, resource_mode. The _scaffold/__init__.py
placeholder makes the bundle importable in source checkouts; the
build hook overwrites it with the real bundle.
"
```

---

## Task 5: `agentic new` — name validation

**Files:**
- Create: `cli/agentic/commands/new.py`
- Create: `cli/tests/test_commands_new.py`

- [ ] **Step 1: Write the failing test `cli/tests/test_commands_new.py`**

```python
"""Tests for `agentic new` — the scaffold materialization command."""
from __future__ import annotations

import pytest
from typer.testing import CliRunner

from agentic.app import app


runner = CliRunner(mix_stderr=False)


@pytest.mark.parametrize("bad", ["", "foo/bar", "../escape", "a\x00b"])
def test_new_rejects_bad_name(bad):
    result = runner.invoke(app, ["new", bad])
    assert result.exit_code == 2, result.stderr
    assert "name must be a single path segment" in result.stderr
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd cli && uv run pytest tests/test_commands_new.py -v`
Expected: `No such command 'new'`.

- [ ] **Step 3: Write minimal `cli/agentic/commands/new.py` for name validation only**

```python
"""`agentic new <name>` — materialize a fresh agentic-delivery scaffold.

Reads the bundled scaffold tree (built into the wheel) and copies it into
``./<name>``, optionally initializing a git repo. Designed so that the
sequence ``pipx install agentic-delivery && agentic new my-project`` is
sufficient to get a validation-passing project on disk.

Spec: docs/superpowers/specs/2026-05-29-agentic-new-scaffold-bootstrap-design.md
"""
from __future__ import annotations

from pathlib import Path
from typing import Annotated

import typer

from agentic.ui.errors import AgenticError


def _validate_name(name: str) -> None:
    if not name or "/" in name or ".." in name or "\x00" in name:
        raise AgenticError(
            category="misuse",
            message=f"name must be a single path segment, got {name!r}",
            hints=["use letters, digits, dashes, underscores"],
        )


def new_command(
    name: Annotated[str, typer.Argument(help="Project directory name")],
    path: Annotated[
        Path,
        typer.Option("--path", "-p", help="Parent directory (default: cwd)"),
    ] = Path("."),
    no_git: Annotated[bool, typer.Option("--no-git", help="Skip git init")] = False,
    force: Annotated[
        bool, typer.Option("--force", help="Allow target dir if it exists and is empty")
    ] = False,
) -> None:
    """Scaffold a fresh agentic-delivery project at ``<path>/<name>``."""
    _validate_name(name)
    raise NotImplementedError("populate / git / banner happen in later tasks")
```

- [ ] **Step 4: Register the command on the app (temp; will be re-checked in Task 10)**

In `cli/agentic/app.py`, alongside the existing `app.command(name="init")(init_cmd.init_command)` line, add:

```python
from agentic.commands import new as new_cmd
app.command(name="new")(new_cmd.new_command)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd cli && uv run pytest tests/test_commands_new.py -v`
Expected: 4 parametrized cases pass.

- [ ] **Step 6: Commit**

```bash
git add cli/agentic/commands/new.py cli/agentic/app.py cli/tests/test_commands_new.py
git commit -m "feat(cli): agentic new — name validation (Task 5)

Bare-bones command that validates <name> and exits 2 on bad input.
Real materialization arrives in subsequent tasks.
"
```

---

## Task 6: Add the three new exit-code categories

**Files:**
- Modify: `cli/agentic/ui/errors.py`
- Modify: `cli/tests/test_errors.py`

- [ ] **Step 1: Add failing tests to `cli/tests/test_errors.py`**

Append:

```python
def test_new_scaffold_exit_codes():
    from agentic.ui.errors import EXIT_CODES

    assert EXIT_CODES["scaffold_target_exists"] == 9
    assert EXIT_CODES["scaffold_git_failed"] == 10
    assert EXIT_CODES["scaffold_bundle_missing"] == 11
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd cli && uv run pytest tests/test_errors.py::test_new_scaffold_exit_codes -v`
Expected: KeyError on `scaffold_target_exists`.

- [ ] **Step 3: Extend `EXIT_CODES` in `cli/agentic/ui/errors.py`**

In `EXIT_CODES`, add three new entries below `"script_failed": 64,`:

```python
    "scaffold_target_exists": 9,
    "scaffold_git_failed": 10,
    "scaffold_bundle_missing": 11,
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd cli && uv run pytest tests/test_errors.py -v`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add cli/agentic/ui/errors.py cli/tests/test_errors.py
git commit -m "feat(cli): add scaffold_target_exists / _git_failed / _bundle_missing (Task 6)

New exit-code categories for the agentic new command, picked above the
existing slots to avoid colliding with compat_failed (5) and no_repo (6).
"
```

---

## Task 7: `agentic new` — target-state checks

**Files:**
- Modify: `cli/agentic/commands/new.py`
- Modify: `cli/tests/test_commands_new.py`

- [ ] **Step 1: Add failing tests to `cli/tests/test_commands_new.py`**

```python
def test_new_target_does_not_exist_proceeds(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    # We're not yet copying — assert we got past name+state checks (NotImplementedError)
    result = runner.invoke(app, ["new", "proj"])
    assert "populate" in str(result.exception) or "populate" in (result.stderr or "")


def test_new_target_existing_empty_without_force_fails(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / "proj").mkdir()
    result = runner.invoke(app, ["new", "proj"])
    assert result.exit_code == 9, result.stderr
    assert "rerun with `--force`" in result.stderr


def test_new_target_existing_empty_with_force_proceeds(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / "proj").mkdir()
    result = runner.invoke(app, ["new", "proj", "--force"])
    # past state checks — falls into NotImplementedError
    assert "populate" in str(result.exception) or "populate" in (result.stderr or "")


def test_new_target_existing_nonempty_fails(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / "proj").mkdir()
    (tmp_path / "proj" / "stray.txt").write_text("x")
    result = runner.invoke(app, ["new", "proj"])
    assert result.exit_code == 9, result.stderr
    assert "target exists and is non-empty" in result.stderr
    assert "stray.txt" in result.stderr


def test_new_target_existing_nonempty_with_force_still_fails(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / "proj").mkdir()
    (tmp_path / "proj" / "stray.txt").write_text("x")
    result = runner.invoke(app, ["new", "proj", "--force"])
    assert result.exit_code == 9
    assert "non-empty" in result.stderr
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd cli && uv run pytest tests/test_commands_new.py -v -k target`
Expected: 5 failures (current command exits via `NotImplementedError` before checking).

- [ ] **Step 3: Add target-state branching to `cli/agentic/commands/new.py`**

Add inside `new_command`, after `_validate_name(name)`:

```python
    target = (path / name).resolve()
    _check_target_state(target, force=force)
```

Add helper at module level:

```python
def _check_target_state(target: Path, *, force: bool) -> None:
    if not target.exists():
        target.mkdir(parents=True)
        return
    entries = sorted(p.name for p in target.iterdir())
    if entries:
        sample = ", ".join(entries[:5])
        raise AgenticError(
            category="scaffold_target_exists",
            message=f"target {target} exists and is non-empty (contains: {sample})",
            hints=["choose a new <name>", "remove the existing files first"],
        )
    if not force:
        raise AgenticError(
            category="scaffold_target_exists",
            message=f"target {target} exists; rerun with `--force` to materialize into it",
            hints=["pass --force", "or choose a new <name>"],
        )
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd cli && uv run pytest tests/test_commands_new.py -v`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add cli/agentic/commands/new.py cli/tests/test_commands_new.py
git commit -m "feat(cli): agentic new — target-state branching (Task 7)

Default: target must not exist. --force: allows empty existing. A
non-empty target always fails and lists up to 5 blocking entries.
"
```

---

## Task 8: `agentic new` — copy tree + template render

**Files:**
- Modify: `cli/agentic/commands/new.py`
- Modify: `cli/tests/test_commands_new.py`

- [ ] **Step 1: Add failing tests**

```python
def test_new_copies_bundle_into_target(tmp_path, monkeypatch):
    from agentic import scaffold as scaffold_pkg

    fake_root = tmp_path / "bundle"
    (fake_root / "agentic").mkdir(parents=True)
    (fake_root / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    (fake_root / "scripts").mkdir()
    sh = fake_root / "scripts" / "demo.sh"
    sh.write_text("#!/usr/bin/env bash\n")
    sh.chmod(0o755)
    (fake_root / "README.md").write_text("# {{PROJECT_NAME}}\nCLI v{{CLI_VERSION}}\n")

    monkeypatch.setattr(scaffold_pkg, "_resource_root", lambda: fake_root)
    monkeypatch.chdir(tmp_path)

    result = runner.invoke(app, ["new", "proj", "--no-git"])
    assert result.exit_code == 0, result.stderr + (result.stdout or "")

    target = tmp_path / "proj"
    assert (target / "agentic" / "pipeline.yaml").read_text().startswith("pipeline:")
    assert (target / "scripts" / "demo.sh").exists()

    import stat as _stat
    assert (target / "scripts" / "demo.sh").stat().st_mode & _stat.S_IXUSR

    readme = (target / "README.md").read_text()
    assert "# proj" in readme
    assert "{{PROJECT_NAME}}" not in readme
    assert "{{CLI_VERSION}}" not in readme


def test_new_raises_bundle_missing_when_empty(tmp_path, monkeypatch):
    from agentic import scaffold as scaffold_pkg

    empty = tmp_path / "empty"
    empty.mkdir()
    monkeypatch.setattr(scaffold_pkg, "_resource_root", lambda: empty)
    monkeypatch.chdir(tmp_path)

    result = runner.invoke(app, ["new", "proj", "--no-git"])
    assert result.exit_code == 11
    assert "scaffold bundle" in result.stderr
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd cli && uv run pytest tests/test_commands_new.py -v -k "copies_bundle or bundle_missing"`
Expected: failures (NotImplementedError or wrong code).

- [ ] **Step 3: Wire copy + render into `new_command`**

Replace `raise NotImplementedError(...)` with:

```python
    _materialize_scaffold(target, project_name=name)
```

Add module-level helpers:

```python
import shutil
import stat
from agentic import __version__ as _cli_version
from agentic import scaffold as _scaffold_pkg


_TEMPLATE_FILES = {"README.md"}


def _materialize_scaffold(target: Path, *, project_name: str) -> None:
    try:
        rels = _scaffold_pkg.iter_resource_paths()
    except _scaffold_pkg.ScaffoldBundleMissing as exc:
        raise AgenticError(
            category="scaffold_bundle_missing",
            message=str(exc),
            hints=["reinstall the CLI: pipx reinstall agentic-delivery"],
        ) from exc

    for rel in rels:
        dest = target / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        data = _scaffold_pkg.read_resource_bytes(rel)
        if rel in _TEMPLATE_FILES:
            text = data.decode("utf-8")
            text = text.replace("{{PROJECT_NAME}}", project_name)
            text = text.replace("{{CLI_VERSION}}", _cli_version)
            dest.write_text(text, encoding="utf-8")
        else:
            dest.write_bytes(data)
        mode = _scaffold_pkg.resource_mode(rel)
        if mode & stat.S_IXUSR:
            dest.chmod(dest.stat().st_mode | 0o111)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd cli && uv run pytest tests/test_commands_new.py -v`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add cli/agentic/commands/new.py cli/tests/test_commands_new.py
git commit -m "feat(cli): agentic new — copy bundle + render README template (Task 8)

Walks importlib.resources, copies bytes, preserves executable bit,
substitutes {{PROJECT_NAME}} / {{CLI_VERSION}} in README. Raises
scaffold_bundle_missing (exit 11) on an empty bundle.
"
```

---

## Task 9: `agentic new` — git init

**Files:**
- Modify: `cli/agentic/commands/new.py`
- Modify: `cli/tests/test_commands_new.py`

- [ ] **Step 1: Add failing tests**

```python
def test_new_initializes_git_repo_by_default(tmp_path, monkeypatch):
    _patch_bundle(monkeypatch, tmp_path)
    monkeypatch.chdir(tmp_path)

    result = runner.invoke(app, ["new", "proj"])
    assert result.exit_code == 0, result.stderr + result.stdout

    target = tmp_path / "proj"
    assert (target / ".git").is_dir()
    # exactly one commit
    import subprocess
    log = subprocess.run(
        ["git", "-C", str(target), "log", "--oneline"],
        check=True, capture_output=True, text=True,
    ).stdout.strip().splitlines()
    assert len(log) == 1
    assert "bootstrap agentic-delivery scaffold" in log[0]


def test_new_no_git_skips_repo(tmp_path, monkeypatch):
    _patch_bundle(monkeypatch, tmp_path)
    monkeypatch.chdir(tmp_path)

    result = runner.invoke(app, ["new", "proj", "--no-git"])
    assert result.exit_code == 0
    assert not (tmp_path / "proj" / ".git").exists()


def test_new_reports_git_failure(tmp_path, monkeypatch):
    _patch_bundle(monkeypatch, tmp_path)
    monkeypatch.chdir(tmp_path)

    # Make git resolve to a non-existent path so subprocess.run fails with FileNotFoundError
    monkeypatch.setenv("PATH", "/nonexistent")

    result = runner.invoke(app, ["new", "proj"])
    assert result.exit_code == 10
    assert "git" in result.stderr.lower()
```

And add the shared helper `_patch_bundle` near the top of the test file:

```python
def _patch_bundle(monkeypatch, tmp_path):
    from agentic import scaffold as scaffold_pkg

    fake_root = tmp_path / "bundle"
    (fake_root / "agentic").mkdir(parents=True)
    (fake_root / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    (fake_root / "README.md").write_text("# {{PROJECT_NAME}}\n")
    monkeypatch.setattr(scaffold_pkg, "_resource_root", lambda: fake_root)
```

(Replace earlier inline bundle-creation in `test_new_copies_bundle_into_target` with a call to `_patch_bundle(monkeypatch, tmp_path)`. Re-add the executable `scripts/demo.sh` inside that test only.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd cli && uv run pytest tests/test_commands_new.py -v -k git`
Expected: failures — no git logic yet.

- [ ] **Step 3: Add git logic to `new_command`**

In `new_command`, after `_materialize_scaffold(target, project_name=name)`, add:

```python
    if not no_git:
        _git_init_and_commit(target, cli_version=_cli_version)
```

Add module-level helper:

```python
import subprocess


def _git_init_and_commit(target: Path, *, cli_version: str) -> None:
    commit_msg = f"chore: bootstrap agentic-delivery scaffold (CLI v{cli_version})"
    try:
        subprocess.run(["git", "-C", str(target), "init", "-b", "main"], check=True, capture_output=True, text=True)
        subprocess.run(["git", "-C", str(target), "add", "."], check=True, capture_output=True, text=True)
        subprocess.run(
            ["git", "-C", str(target), "commit", "-m", commit_msg],
            check=True, capture_output=True, text=True,
            env={**_clean_git_env(), "GIT_AUTHOR_NAME": "agentic", "GIT_AUTHOR_EMAIL": "agentic@local",
                 "GIT_COMMITTER_NAME": "agentic", "GIT_COMMITTER_EMAIL": "agentic@local"},
        )
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        detail = getattr(exc, "stderr", "") or str(exc)
        raise AgenticError(
            category="scaffold_git_failed",
            message=f"git initialization failed: {detail.strip()}",
            hints=[
                "rerun `agentic new <name> --no-git` to skip git",
                "or fix the git environment and `git init` manually in the target dir",
            ],
        ) from exc


def _clean_git_env() -> dict[str, str]:
    import os as _os
    # Pass through PATH and HOME so git can find itself and resolve global config;
    # strip GIT_DIR / GIT_WORK_TREE which would override `-C target`.
    keep = {k: v for k, v in _os.environ.items() if not k.startswith("GIT_")}
    return keep
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd cli && uv run pytest tests/test_commands_new.py -v`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add cli/agentic/commands/new.py cli/tests/test_commands_new.py
git commit -m "feat(cli): agentic new — git init + initial commit (Task 9)

Default: git init -b main, add, commit with bootstrap message and a
local agentic author. --no-git skips. Git failures raise
scaffold_git_failed (exit 10) with hints.
"
```

---

## Task 10: `agentic new` — success banner and JSON mode

**Files:**
- Modify: `cli/agentic/commands/new.py`
- Modify: `cli/tests/test_commands_new.py`

- [ ] **Step 1: Add failing tests**

```python
def test_new_prints_success_banner(tmp_path, monkeypatch):
    _patch_bundle(monkeypatch, tmp_path)
    monkeypatch.chdir(tmp_path)

    result = runner.invoke(app, ["new", "proj", "--no-git"])
    assert result.exit_code == 0
    assert "Scaffolded proj" in result.stdout
    assert "scripts/validate-agentic-system.sh" in result.stdout
    assert "agentic init" in result.stdout
    assert "agentic next" in result.stdout


def test_new_json_mode_emits_envelope(tmp_path, monkeypatch):
    _patch_bundle(monkeypatch, tmp_path)
    monkeypatch.chdir(tmp_path)

    result = runner.invoke(app, ["--json", "new", "proj", "--no-git"])
    assert result.exit_code == 0, result.stderr
    import json
    payload = json.loads(result.stdout)
    assert payload["status"] == "ok"
    assert payload["command"] == "new"
    assert payload["target"].endswith("/proj")
    assert payload["files_written"] >= 1
    assert payload["git_initialized"] is False
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd cli && uv run pytest tests/test_commands_new.py -v -k "banner or json"`
Expected: missing-output failures.

- [ ] **Step 3: Add banner + JSON to `new_command`**

Imports at top:

```python
import json as _json
from agentic.ui.errors import get_json_mode
```

At end of `new_command`, before returning, replace the bare implicit return with:

```python
    files_written = len(_scaffold_pkg.iter_resource_paths())
    if get_json_mode():
        typer.echo(_json.dumps({
            "status": "ok",
            "command": "new",
            "target": str(target),
            "project_name": name,
            "cli_version": _cli_version,
            "files_written": files_written,
            "git_initialized": not no_git,
        }))
        return
    typer.echo(_render_banner(target=target, project_name=name, git=not no_git))


def _render_banner(*, target: Path, project_name: str, git: bool) -> str:
    git_line = "  • Initialized git repo with one commit." if git else "  • Skipped git init (--no-git)."
    return (
        f"✅ Scaffolded {project_name} (default-delivery, boss-idea-response).\n"
        f"   Path: {target}\n"
        f"{git_line}\n"
        f"\n"
        f"Next steps:\n"
        f"  cd {project_name}\n"
        f"  scripts/validate-agentic-system.sh\n"
        f"  agentic init \"Your first delivery goal\"\n"
        f"  agentic next\n"
    )
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd cli && uv run pytest tests/test_commands_new.py -v`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add cli/agentic/commands/new.py cli/tests/test_commands_new.py
git commit -m "feat(cli): agentic new — success banner + --json envelope (Task 10)

Text mode prints the next-steps banner; --json mode emits the
agentic.cli/v1-style envelope with target, files_written, and
git_initialized fields.
"
```

---

## Task 11: Update `RepoNotFound` message + cover doctor

**Files:**
- Modify: `cli/agentic/context.py`
- Modify: `cli/tests/test_context.py`
- Modify: `cli/agentic/commands/doctor.py` (only if it duplicates the message)
- Modify: `cli/tests/test_doctor.py` (mirror message change if doctor renders it)

- [ ] **Step 1: Add failing tests in `cli/tests/test_context.py`**

```python
def test_repo_not_found_mentions_agentic_new(tmp_path, monkeypatch):
    monkeypatch.delenv("AGENTIC_HOME", raising=False)
    monkeypatch.chdir(tmp_path)
    with pytest.raises(RepoNotFound) as exc:
        resolve_repo()
    assert "agentic new" in str(exc.value)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd cli && uv run pytest tests/test_context.py::test_repo_not_found_mentions_agentic_new -v`
Expected: AssertionError — current message doesn't mention `agentic new`.

- [ ] **Step 3: Update `cli/agentic/context.py:65-67`**

Replace:

```python
    raise RepoNotFound(
        "no agentic-delivery repo found. Pass --repo, set AGENTIC_HOME, or cd into a repo."
    )
```

with:

```python
    raise RepoNotFound(
        "no agentic-delivery repo found. Pass --repo, set AGENTIC_HOME, "
        "cd into a repo, or run `agentic new <name>` to scaffold a new project here."
    )
```

- [ ] **Step 4: Check whether `doctor.py` re-renders the message**

Run: `cd cli && grep -n "no agentic-delivery repo\|RepoNotFound" agentic/commands/doctor.py tests/test_doctor.py`

- If doctor only catches `RepoNotFound` and re-raises (or lets it propagate via `AgenticError`), no doctor change is needed beyond what `context.py` already does. Move to Step 5.
- If doctor has its own hard-coded copy of the wording, update it to either reuse `context.py`'s message or duplicate it verbatim, and update any matching test.

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd cli && uv run pytest tests/test_context.py tests/test_doctor.py -v`
Expected: all pass; any prior test asserting the old wording is updated.

- [ ] **Step 6: Commit**

```bash
git add cli/agentic/context.py cli/tests/test_context.py
# include cli/agentic/commands/doctor.py and cli/tests/test_doctor.py if Step 4 required changes
git commit -m "feat(cli): point no-repo error at agentic new (Task 11)

RepoNotFound now offers `agentic new <name>` as the fourth remedy
alongside --repo, AGENTIC_HOME, and walk-up. Doctor surfaces the
same wording (single source of truth: context.py).
"
```

---

## Task 12: Integration test — scaffolded project passes validate-agentic-system.sh

**Files:**
- Create: `cli/tests/test_integration_new_validates.py`

- [ ] **Step 1: Write the failing test**

```python
"""Integration: a scaffolded project must pass validate-agentic-system.sh.

Skipped on non-POSIX. Requires `bash`, `yq`-free `validate-agentic-system.sh`
runs (already true), and a real built wheel so the bundled scaffold is
present. Uses `uv build` once per session.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

import pytest

pytestmark = pytest.mark.skipif(
    os.name != "posix" or not shutil.which("bash"),
    reason="POSIX shell required",
)


@pytest.fixture(scope="session")
def installed_cli(tmp_path_factory):
    """Build the wheel, install it into a fresh venv, return that venv's `agentic` path."""
    cli_root = Path(__file__).resolve().parents[1]
    out = tmp_path_factory.mktemp("install")
    venv = out / "venv"
    subprocess.run([sys.executable, "-m", "venv", str(venv)], check=True)
    subprocess.run(
        [str(venv / "bin" / "pip"), "install", "--upgrade", "pip", "wheel", "build"],
        check=True,
    )
    subprocess.run([str(venv / "bin" / "pip"), "install", str(cli_root)], check=True)
    return venv / "bin" / "agentic"


def test_scaffolded_project_validates(installed_cli, tmp_path):
    subprocess.run(
        [str(installed_cli), "new", "demo", "--no-git", "--path", str(tmp_path)],
        check=True,
    )
    target = tmp_path / "demo"
    result = subprocess.run(
        ["bash", "scripts/validate-agentic-system.sh"],
        cwd=target, capture_output=True, text=True,
    )
    assert result.returncode == 0, (
        "validate-agentic-system.sh failed in scaffolded project\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
```

- [ ] **Step 2: Run test**

Run: `cd cli && uv run pytest tests/test_integration_new_validates.py -v -s`
Expected: PASS. (First run will be slow — wheel build + venv install.)

If it fails because the venv doesn't see `bash` or the script needs additional binaries, surface the missing dependency in the error and stop — don't paper over it.

- [ ] **Step 3: Commit**

```bash
git add cli/tests/test_integration_new_validates.py
git commit -m "test(cli): end-to-end — agentic new project passes validate-agentic-system.sh (Task 12)

Builds the wheel, installs into a fresh venv, runs `agentic new demo`,
runs scripts/validate-agentic-system.sh inside the scaffolded project,
asserts exit 0.
"
```

---

## Self-Review

| Spec requirement | Covered by |
|------------------|------------|
| `agentic new <name>` command exists | Task 5, 7-10 |
| Name validation (`/`, `..`, empty) → exit 2 | Task 5 |
| Target-state branches (none/empty/empty+force/non-empty) | Task 7 |
| Scaffold scope (Full: default + boss-idea + fixtures + ADRs + standards + runbooks) | Task 1 manifest |
| Bundle ships inside wheel via Hatch build hook | Tasks 2, 3 |
| `importlib.resources` accessor | Task 4 |
| `{{PROJECT_NAME}}` / `{{CLI_VERSION}}` substitution in scaffold README | Tasks 1, 8 |
| Executable bit preserved on `scripts/*.sh` | Tasks 2, 4, 8 |
| `git init` default; `--no-git` skips | Task 9 |
| Success banner + JSON envelope | Task 10 |
| `RepoNotFound` mentions `agentic new` | Task 11 |
| Doctor renderer references same wording | Task 11 Step 4 |
| New exit codes 9/10/11 added to `EXIT_CODES` | Task 6 |
| Build hook validates `pipeline.yaml.version` against compat range | Task 2 |
| Allowlist single source of truth in `cli/scaffold_manifest.yaml` | Task 1 |
| Integration: scaffolded project passes `validate-agentic-system.sh` | Task 12 |
| Bundled scaffold path gitignored in CLI source | Tasks 1, 4 |

Spec coverage: complete. No placeholders detected.

Cross-task type/name consistency:
- `ScaffoldBuildHook` (Task 2), `HatchScaffoldBuildHook` (Task 2), `iter_resource_paths` / `read_resource_bytes` / `resource_mode` (Task 4) — used consistently in Tasks 8 + 12.
- `_materialize_scaffold(target, project_name=...)` (Task 8) — single call site in `new_command`.
- `_git_init_and_commit(target, cli_version=...)` (Task 9) — single call site.
- Exit codes 9/10/11 (Task 6) — referenced in Tasks 7/8/9 test assertions.

Plan ready for execution.
