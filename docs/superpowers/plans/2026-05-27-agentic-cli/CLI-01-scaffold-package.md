# CLI-01: Scaffold `cli/` Package Implementation Plan

> **For agentic-delivery pipeline:** Implementer = agency-agents (msitarzewski) Staff+. Reviewer = Claude Code CLI via AIT. Write scope strictly `cli/**`. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Create the `cli/` Python package skeleton with `agentic --help` and `agentic version` working through `pipx install -e cli/`.

**Architecture:** Typer app rooted at `cli/agentic/app.py`. Entry point `agentic = "agentic.app:main"`. Version sourced from `cli/agentic/__init__.py::__version__`. No external repo discovery yet — that's CLI-02.

**Tech Stack:** Python ≥ 3.10, Typer ≥ 0.12, Rich ≥ 13, pyyaml ≥ 6, pytest ≥ 8, ruff, mypy.

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `cli/pyproject.toml` | Create | Package metadata, deps, entry point. |
| `cli/agentic/__init__.py` | Create | Package marker; `__version__ = "0.1.0"`. |
| `cli/agentic/app.py` | Create | Typer app + `version` command + `main()`. |
| `cli/README.md` | Create | Install + quickstart (≤ 30 lines). |
| `cli/CHANGELOG.md` | Create | Empty `0.1.0` entry. |
| `cli/tests/__init__.py` | Create | Empty. |
| `cli/tests/test_smoke.py` | Create | `--help`, `version` smoke. |
| `cli/tests/conftest.py` | Create | Shared fixtures (CliRunner). |

---

## Task 1: pyproject + package skeleton + README/CHANGELOG stubs

> **Staff-level amendment 2026-05-27** (recorded in commit message): README.md + CHANGELOG.md must exist before Task 2's `pip install -e cli/[dev]` because hatchling validates `readme = "README.md"` at build time. The original plan deferred them to Task 4; this amendment moves them to Task 1 so the install resolves. Task 4 keeps its lint/type/test verification but no longer creates the docs.

**Files:**
- Create: `cli/pyproject.toml`
- Create: `cli/agentic/__init__.py`
- Create: `cli/README.md`
- Create: `cli/CHANGELOG.md`

- [ ] **Step 1: Write `cli/pyproject.toml`**

```toml
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[project]
name = "agentic-delivery"
version = "0.1.0"
description = "Agentic Delivery CLI — wrapper over the scripts/* pipeline"
readme = "README.md"
requires-python = ">=3.10"
license = { text = "Apache-2.0" }
authors = [{ name = "Michael Chen" }]
classifiers = [
  "Development Status :: 3 - Alpha",
  "License :: OSI Approved :: Apache Software License",
  "Programming Language :: Python :: 3 :: Only",
  "Programming Language :: Python :: 3.10",
  "Programming Language :: Python :: 3.11",
  "Programming Language :: Python :: 3.12",
  "Programming Language :: Python :: 3.13",
]
dependencies = [
  "typer >= 0.12",
  "rich  >= 13",
  "pyyaml >= 6",
]

[project.scripts]
agentic = "agentic.app:main"

[project.optional-dependencies]
dev = [
  "pytest >= 8",
  "pytest-snapshot",
  "ruff",
  "mypy",
]

[tool.agentic]
compatible_pipeline_versions = [">=0.6,<0.7"]

[tool.hatch.build.targets.wheel]
packages = ["agentic"]

[tool.ruff]
target-version = "py310"
line-length = 100

[tool.mypy]
python_version = "3.10"
strict = true
```

- [ ] **Step 2: Write `cli/agentic/__init__.py`**

```python
"""Agentic Delivery CLI."""

__version__ = "0.1.0"
```

- [ ] **Step 3: Write `cli/README.md`** (the final content; Task 4 will no longer touch this file)

```markdown
# agentic-delivery CLI

A state-aware wrapper over the `scripts/*.sh` pipeline of the
[agentic-delivery](../README.md) repo.

## Install

    pipx install agentic-delivery

Or, in this repo:

    pip install -e cli/

## Usage

    agentic --help
    agentic version

Run inside (or anywhere under) a checked-out `agentic-delivery` repo.

See `docs/superpowers/specs/2026-05-27-agentic-cli-design.md` for the design.
```

- [ ] **Step 4: Write `cli/CHANGELOG.md`** (Task 4 will append more entries as features land in later slices)

```markdown
# Changelog

All notable changes to the `agentic-delivery` CLI.

## [0.1.0] — unreleased

- Initial scaffold: Typer root, `version`, `--help`.
```

- [ ] **Step 5: Commit**

```bash
git add cli/pyproject.toml cli/agentic/__init__.py cli/README.md cli/CHANGELOG.md
git commit -m "feat(cli): pyproject + package marker + readme/changelog stubs"
```

---

## Task 2: TDD — `agentic --help` works

**Files:**
- Create: `cli/tests/__init__.py` (empty)
- Create: `cli/tests/conftest.py`
- Create: `cli/tests/test_smoke.py`
- Create: `cli/agentic/app.py`

- [ ] **Step 1: Write `cli/tests/__init__.py`** (empty file)

```python
```

- [ ] **Step 2: Write `cli/tests/conftest.py`**

> **Staff-level amendment 2026-05-27:** typer 0.26+ (Click 8.2+) removed the `mix_stderr` kwarg from `CliRunner`. Separated stderr is now the default, so dropping the kwarg is behavior-preserving.

```python
import pytest
from typer.testing import CliRunner


@pytest.fixture
def cli():
    return CliRunner()
```

- [ ] **Step 3: Write the failing test `cli/tests/test_smoke.py`**

```python
from agentic.app import app


def test_help_exits_zero(cli):
    result = cli.invoke(app, ["--help"])
    assert result.exit_code == 0
    assert "Agentic Delivery" in result.stdout


def test_help_lists_version_command(cli):
    result = cli.invoke(app, ["--help"])
    assert result.exit_code == 0
    assert "version" in result.stdout
```

- [ ] **Step 4: Run — expect FAIL**

```bash
cd cli && pip install -e .[dev] && pytest tests/test_smoke.py -q
```

Expected: ImportError because `agentic.app` does not exist yet.

- [ ] **Step 5: Implement `cli/agentic/app.py` minimally**

> **Staff-level amendment 2026-05-27:** Typer collapses single-command apps so `agentic --help` would show only the `version` command's help, breaking the multi-command UX promised in §5.1. The minimal fix is an empty `@app.callback()` that forces the multi-command form; later slices extend the callback with global flags.

```python
"""Agentic CLI root."""

import typer

app = typer.Typer(
    name="agentic",
    help="Agentic Delivery — plan → review → approve → implement.",
    no_args_is_help=True,
    add_completion=True,
)


@app.callback()
def _root() -> None:
    """Root callback. Forces multi-command app structure even with a single command.

    Later slices (CLI-02 onward) extend this with global flags like
    --repo, --run-id, --actor, --role, --json, --no-compat-check.
    """


def main() -> None:
    app()


if __name__ == "__main__":
    main()
```

- [ ] **Step 6: Run — expect PASS**

```bash
cd cli && pytest tests/test_smoke.py -q
```

Expected: 2 passed.

- [ ] **Step 7: Commit**

```bash
git add cli/agentic/app.py cli/tests/__init__.py cli/tests/conftest.py cli/tests/test_smoke.py
git commit -m "feat(cli): Typer root with --help"
```

---

## Task 3: TDD — `agentic version`

**Files:**
- Modify: `cli/agentic/app.py`
- Modify: `cli/tests/test_smoke.py`

- [ ] **Step 1: Append failing test to `cli/tests/test_smoke.py`**

```python
def test_version_command_prints_version(cli):
    result = cli.invoke(app, ["version"])
    assert result.exit_code == 0
    assert "0.1.0" in result.stdout


def test_version_command_prints_python(cli):
    result = cli.invoke(app, ["version"])
    assert result.exit_code == 0
    assert "python" in result.stdout.lower()
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd cli && pytest tests/test_smoke.py -q
```

Expected: 2 failures (`version` is not a registered command yet).

- [ ] **Step 3: Implement `version` in `cli/agentic/app.py`**

```python
"""Agentic CLI root."""

import platform
import sys

import typer

from agentic import __version__

app = typer.Typer(
    name="agentic",
    help="Agentic Delivery — plan → review → approve → implement.",
    no_args_is_help=True,
    add_completion=True,
)


@app.command()
def version() -> None:
    """Print CLI, python, and platform info."""
    typer.echo(f"agentic-delivery CLI  {__version__}")
    typer.echo(f"  python:   {platform.python_version()}")
    typer.echo(f"  platform: {sys.platform}")


def main() -> None:
    app()


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run — expect PASS**

```bash
cd cli && pytest tests/test_smoke.py -q
```

Expected: 4 passed.

- [ ] **Step 5: Commit**

```bash
git add cli/agentic/app.py cli/tests/test_smoke.py
git commit -m "feat(cli): agentic version command"
```

---

## Task 4: Final validation (lint + type + tests)

> README.md and CHANGELOG.md were already created in Task 1 (Staff-level amendment 2026-05-27). This task is verification-only.

**Files:** none modified — only verification commands.

- [ ] **Step 1: Lint clean**

```bash
cd cli && ruff check agentic tests
```

Expected: exit 0.

- [ ] **Step 2: Type clean**

```bash
cd cli && mypy --strict agentic
```

Expected: exit 0. Fix any complaints inline (likely `typer.echo` and `app` annotations).

- [ ] **Step 3: Final test pass**

```bash
cd cli && pytest -q
```

Expected: 4 passed.

No commit for this task — Task 1 already committed the scaffold; Tasks 2/3 committed the Typer root and version command; if Tasks 2/3 produced lint/type fixups, those go in a separate `chore(cli): lint fixups` commit only if there are file changes.

---

## Acceptance Criteria (from spec §13 CLI-01)

- `pip install -e cli/[dev]` succeeds.
- `agentic --help` exit 0; output mentions `Agentic Delivery` and `version`.
- `agentic version` exit 0; output contains `0.1.0` and python version.
- `ruff check cli/agentic cli/tests` exit 0.
- `mypy --strict cli/agentic` exit 0.
- `pytest cli/tests -q` ≥ 4 tests pass.

## Implementer / Reviewer

- **Implementer:** agency-agents Staff+ — `staff-software-engineer`.
- **Reviewer:** Claude Code CLI via AIT — `engineering-software-architect`, `engineering-code-reviewer`.

```bash
unset ANTHROPIC_API_KEY
for agent in engineering-software-architect engineering-code-reviewer; do
  ait run --adapter claude-code --stdin none --apply never --review never --format json -- \
    "$(command -v claude)" --agent "$agent" --add-dir "$PWD" \
    -p "Adversarial review of CLI-01 in cli/. Check pyproject metadata, package layout, Typer wiring, version exposure, and TDD coverage. Output JSON: {findings: [{severity, file, line?, issue, recommendation}]}."
done
```

Evidence written under `agentic/reviews/agentic-cli/CLI-01/round-N.json`.

## Rollback

```bash
git rm -r cli/
git commit -m "revert: roll back CLI-01"
```

No other files touched; no risk to existing scripts/agentic flows.
