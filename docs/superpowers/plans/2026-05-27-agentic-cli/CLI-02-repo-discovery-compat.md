# CLI-02: Repo Discovery + Compat Check Implementation Plan

> **For agentic-delivery pipeline:** Implementer = agency-agents Staff+. Reviewer = Claude Code CLI via AIT. Write scope `cli/**`.

**Goal:** Resolve which `agentic-delivery` repo the CLI is operating against, and verify the repo's `pipeline.yaml.version` falls inside the CLI's declared compatibility range.

**Architecture:** A single `Context` dataclass produced by `cli/agentic/context.py::resolve_context()`. Resolution priority `--repo` flag > `$AGENTIC_HOME` > walk-up from cwd > `~/.config/agentic/config.toml`. Compat range read from `cli/pyproject.toml` `[tool.agentic].compatible_pipeline_versions`; checked against `<repo>/agentic/pipeline.yaml::pipeline.version`.

**Tech Stack:** pyyaml, tomllib (stdlib 3.11+; use `tomli` for 3.10 backport — already a transitive of typer? No, add `tomli ; python_version < "3.11"` to dependencies).

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `cli/pyproject.toml` | Modify | Add `tomli` conditional dep. |
| `cli/agentic/context.py` | Create | `Context`, `resolve_context`, `check_compat`. |
| `cli/agentic/app.py` | Modify | Wire `--repo` global option; extend `version` output. |
| `cli/tests/test_context.py` | Create | Resolution + compat tests. |
| `cli/tests/test_compat.py` | Create | Pipeline version checks. |
| `cli/tests/fixtures/repos/minimal/agentic/pipeline.yaml` | Create | Minimal repo for tests. |

---

## Task 1: TDD — walk-up repo discovery

**Files:**
- Create: `cli/agentic/context.py`
- Create: `cli/tests/test_context.py`
- Create: `cli/tests/fixtures/repos/minimal/agentic/pipeline.yaml`

- [ ] **Step 1: Write the minimal repo fixture `cli/tests/fixtures/repos/minimal/agentic/pipeline.yaml`**

```yaml
pipeline:
  id: agentic-delivery-system
  version: v0.6
  purpose: test fixture
  default_profile: default-delivery
  profile_dir: agentic/profiles
modes: [planning, implementation]
```

- [ ] **Step 2: Write failing tests `cli/tests/test_context.py`**

```python
from pathlib import Path

import pytest

from agentic.context import RepoNotFound, resolve_repo


def test_walk_up_finds_repo(tmp_path, monkeypatch):
    repo = tmp_path / "repo"
    (repo / "agentic").mkdir(parents=True)
    (repo / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    deep = repo / "a" / "b" / "c"
    deep.mkdir(parents=True)
    monkeypatch.chdir(deep)

    found = resolve_repo()

    assert found.path == repo
    assert found.source == "walk-up"


def test_env_overrides_walk_up(tmp_path, monkeypatch):
    repo = tmp_path / "explicit"
    (repo / "agentic").mkdir(parents=True)
    (repo / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    monkeypatch.setenv("AGENTIC_HOME", str(repo))
    monkeypatch.chdir(tmp_path)

    found = resolve_repo()

    assert found.path == repo
    assert found.source == "AGENTIC_HOME"


def test_flag_overrides_env(tmp_path, monkeypatch):
    other = tmp_path / "other"
    (other / "agentic").mkdir(parents=True)
    (other / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    monkeypatch.setenv("AGENTIC_HOME", "/nonexistent")

    found = resolve_repo(repo_flag=other)

    assert found.path == other
    assert found.source == "--repo"


def test_missing_repo_raises(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    monkeypatch.delenv("AGENTIC_HOME", raising=False)
    with pytest.raises(RepoNotFound):
        resolve_repo()
```

- [ ] **Step 3: Run — expect FAIL** (`agentic.context` missing)

```bash
cd cli && pytest tests/test_context.py -q
```

- [ ] **Step 4: Implement `cli/agentic/context.py`**

```python
"""Repo discovery and CLI context resolution."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Literal


RepoSource = Literal["--repo", "AGENTIC_HOME", "walk-up", "config-file"]


class RepoNotFound(Exception):
    """Raised when no agentic-delivery repo can be located."""


@dataclass(frozen=True)
class Repo:
    path: Path
    source: RepoSource


def _is_repo(path: Path) -> bool:
    return (path / "agentic" / "pipeline.yaml").is_file()


def _walk_up(start: Path) -> Path | None:
    current = start.resolve()
    while True:
        if _is_repo(current):
            return current
        parent = current.parent
        if parent == current:
            return None
        current = parent


def resolve_repo(repo_flag: Path | None = None) -> Repo:
    if repo_flag is not None:
        flag = Path(repo_flag).resolve()
        if not _is_repo(flag):
            raise RepoNotFound(f"--repo {flag} is not an agentic-delivery repo")
        return Repo(path=flag, source="--repo")

    env = os.environ.get("AGENTIC_HOME")
    if env:
        envp = Path(env).resolve()
        if not _is_repo(envp):
            raise RepoNotFound(f"AGENTIC_HOME={env} is not an agentic-delivery repo")
        return Repo(path=envp, source="AGENTIC_HOME")

    walked = _walk_up(Path.cwd())
    if walked is not None:
        return Repo(path=walked, source="walk-up")

    raise RepoNotFound(
        "no agentic-delivery repo found. Pass --repo, set AGENTIC_HOME, or cd into a repo."
    )
```

- [ ] **Step 5: Run — expect PASS**

```bash
cd cli && pytest tests/test_context.py -q
```

Expected: 4 passed.

- [ ] **Step 6: Commit**

```bash
git add cli/agentic/context.py cli/tests/test_context.py cli/tests/fixtures/repos/minimal/agentic/pipeline.yaml
git commit -m "feat(cli): repo discovery (flag > env > walk-up)"
```

---

## Task 2: TDD — pipeline compat check

**Files:**
- Modify: `cli/pyproject.toml`
- Modify: `cli/agentic/context.py`
- Create: `cli/tests/test_compat.py`

- [ ] **Step 1: Add `tomli` to `cli/pyproject.toml` dependencies**

```toml
dependencies = [
  "typer >= 0.12",
  "rich  >= 13",
  "pyyaml >= 6",
  "tomli >= 2 ; python_version < '3.11'",
]
```

- [ ] **Step 2: Write failing tests `cli/tests/test_compat.py`**

```python
from pathlib import Path

import pytest

from agentic.context import CompatError, check_compat


def _write_pipeline(path: Path, version: str) -> None:
    (path / "agentic").mkdir(parents=True, exist_ok=True)
    (path / "agentic" / "pipeline.yaml").write_text(f"pipeline:\n  version: {version}\n")


def test_compat_pass(tmp_path):
    _write_pipeline(tmp_path, "v0.6")
    # ranges loaded from packaged pyproject.toml
    check_compat(repo=tmp_path)


def test_compat_fail_too_new(tmp_path):
    _write_pipeline(tmp_path, "v0.9")
    with pytest.raises(CompatError) as exc:
        check_compat(repo=tmp_path)
    assert "v0.9" in str(exc.value)


def test_compat_skipped_when_disabled(tmp_path):
    _write_pipeline(tmp_path, "v9.9")
    check_compat(repo=tmp_path, enabled=False)  # must not raise
```

- [ ] **Step 3: Run — expect FAIL** (`check_compat` missing)

```bash
cd cli && pytest tests/test_compat.py -q
```

- [ ] **Step 4: Extend `cli/agentic/context.py`**

```python
from __future__ import annotations

import re
import sys
from pathlib import Path

try:
    import tomllib  # type: ignore[import-not-found]
except ModuleNotFoundError:  # 3.10
    import tomli as tomllib  # type: ignore[import-not-found,no-redef]

import yaml


_VERSION_RE = re.compile(r"^v?(\d+)\.(\d+)(?:\.(\d+))?$")


class CompatError(Exception):
    """Raised when pipeline.yaml.version is outside the CLI's compat range."""


def _parse_version(raw: str) -> tuple[int, int, int]:
    m = _VERSION_RE.match(raw.strip())
    if not m:
        raise CompatError(f"unrecognised version string: {raw!r}")
    major, minor, patch = m.group(1), m.group(2), m.group(3) or "0"
    return int(major), int(minor), int(patch)


def _parse_range(spec: str) -> tuple[tuple[int, int, int] | None, tuple[int, int, int] | None]:
    lo: tuple[int, int, int] | None = None
    hi: tuple[int, int, int] | None = None
    for part in (p.strip() for p in spec.split(",")):
        if part.startswith(">="):
            lo = _parse_version(part[2:])
        elif part.startswith("<"):
            hi = _parse_version(part[1:])
    return lo, hi


def _compat_ranges_from_pyproject() -> list[str]:
    pyproject = Path(__file__).resolve().parents[1] / "pyproject.toml"
    if not pyproject.is_file():
        return []
    data = tomllib.loads(pyproject.read_text())
    tool = data.get("tool", {}).get("agentic", {})
    return list(tool.get("compatible_pipeline_versions", []))


def check_compat(*, repo: Path, enabled: bool = True) -> None:
    if not enabled:
        return
    pipeline = repo / "agentic" / "pipeline.yaml"
    data = yaml.safe_load(pipeline.read_text())
    actual_raw = data["pipeline"]["version"]
    actual = _parse_version(actual_raw)
    ranges = _compat_ranges_from_pyproject() or [">=0.0,<99.0"]
    for spec in ranges:
        lo, hi = _parse_range(spec)
        if lo is not None and actual < lo:
            continue
        if hi is not None and actual >= hi:
            continue
        return  # within at least one range
    raise CompatError(
        f"pipeline {actual_raw} is outside CLI compat: {ranges}. "
        f"Upgrade CLI or pass --no-compat-check."
    )
```

- [ ] **Step 5: Run — expect PASS**

```bash
cd cli && pytest tests/test_compat.py -q
```

Expected: 3 passed.

- [ ] **Step 6: Commit**

```bash
git add cli/pyproject.toml cli/agentic/context.py cli/tests/test_compat.py
git commit -m "feat(cli): pipeline.yaml.version compat check"
```

---

## Task 3: Wire `--repo` global flag + `version` extension

**Files:**
- Modify: `cli/agentic/app.py`
- Modify: `cli/tests/test_smoke.py`

- [ ] **Step 1: Update test `cli/tests/test_smoke.py`** (extend existing file)

```python
import os

import pytest

from agentic.app import app


def test_version_includes_repo_when_resolvable(cli, tmp_path, monkeypatch):
    (tmp_path / "agentic").mkdir(parents=True)
    (tmp_path / "agentic" / "pipeline.yaml").write_text(
        "pipeline:\n  version: v0.6\n"
    )
    monkeypatch.chdir(tmp_path)
    monkeypatch.delenv("AGENTIC_HOME", raising=False)

    result = cli.invoke(app, ["version"])

    assert result.exit_code == 0
    assert "repo:" in result.stdout
    assert str(tmp_path) in result.stdout


def test_version_handles_missing_repo(cli, tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    monkeypatch.delenv("AGENTIC_HOME", raising=False)

    result = cli.invoke(app, ["version"])

    assert result.exit_code == 0  # version itself must not fail
    assert "repo:" in result.stdout
    assert "not found" in result.stdout.lower()
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd cli && pytest tests/test_smoke.py::test_version_includes_repo_when_resolvable -q
```

- [ ] **Step 3: Update `cli/agentic/app.py`**

```python
"""Agentic CLI root."""

from __future__ import annotations

import platform
import sys
from pathlib import Path
from typing import Annotated

import typer

from agentic import __version__
from agentic.context import RepoNotFound, resolve_repo

app = typer.Typer(
    name="agentic",
    help="Agentic Delivery — plan → review → approve → implement.",
    no_args_is_help=True,
    add_completion=True,
)


@app.callback()
def _root(
    ctx: typer.Context,
    repo: Annotated[
        Path | None,
        typer.Option("--repo", help="Path to agentic-delivery repo.", show_default=False),
    ] = None,
    no_compat_check: Annotated[
        bool, typer.Option("--no-compat-check", help="Skip pipeline.yaml compatibility check.")
    ] = False,
) -> None:
    ctx.obj = {"repo_flag": repo, "compat_check": not no_compat_check}


@app.command()
def version(ctx: typer.Context) -> None:
    """Print CLI, python, repo, and compat info."""
    typer.echo(f"agentic-delivery CLI  {__version__}")
    typer.echo(f"  python:   {platform.python_version()}")
    typer.echo(f"  platform: {sys.platform}")
    try:
        repo = resolve_repo(repo_flag=ctx.obj.get("repo_flag") if ctx.obj else None)
        typer.echo(f"  repo:     {repo.path}  (source: {repo.source})")
    except RepoNotFound as e:
        typer.echo(f"  repo:     not found ({e})")


def main() -> None:
    app()


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run — expect PASS**

```bash
cd cli && pytest -q
```

Expected: all tests green.

- [ ] **Step 5: Lint + type clean**

```bash
cd cli && ruff check agentic tests && mypy --strict agentic
```

Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
git add cli/agentic/app.py cli/tests/test_smoke.py
git commit -m "feat(cli): --repo + version repo disclosure"
```

---

## Acceptance Criteria (from spec §13 CLI-02)

- `resolve_repo()` honours priority `--repo` > `AGENTIC_HOME` > walk-up; raises `RepoNotFound` otherwise.
- `check_compat()` raises `CompatError` on out-of-range pipeline.yaml.version; respects `enabled=False`.
- `agentic version` discloses repo path + source.
- All tests pass; ruff + mypy clean.

## Implementer / Reviewer

- **Implementer:** agency-agents Staff+ — `staff-software-engineer`.
- **Reviewer:** Claude Code CLI via AIT — `engineering-software-architect`, `engineering-security-engineer`, `engineering-code-reviewer`.

Evidence under `agentic/reviews/agentic-cli/CLI-02/`.

## Rollback

```bash
git revert <CLI-02 commits>
```

`cli/agentic/context.py` deletion does not touch other files.
