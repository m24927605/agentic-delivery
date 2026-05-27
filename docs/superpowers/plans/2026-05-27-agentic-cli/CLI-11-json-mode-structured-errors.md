# CLI-11: `--json` Mode + Structured Errors Implementation Plan

> **For agentic-delivery pipeline:** Implementer = agency-agents Staff+. Reviewer = Claude Code CLI via AIT. Write scope `cli/**`.

**Goal:** Make every public command emit a `_schema: agentic.cli/v1` JSON envelope under `--json`, and route all error messages through a structured formatter (`✗ what / why / what-to-do-next`).

**Architecture:** Introduce `cli/agentic/ui/render.py` (text + json rendering) and `cli/agentic/ui/errors.py` (`AgenticError` exception base + `render_error()`). Each existing command refactored to:
1. Build a result object.
2. Render via `ui.render(payload, json_mode)`.
3. Raise `AgenticError(category, message, hints=...)` for failures, with the global exception hook turning them into structured stderr.

`--json` schema versioning enforced by snapshot tests with strict mode.

**Tech Stack:** typer, rich, json, pytest-snapshot.

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `cli/agentic/ui/__init__.py` | Create | Empty. |
| `cli/agentic/ui/errors.py` | Create | `AgenticError`, exit-code mapping, JSON / text renderer. |
| `cli/agentic/ui/render.py` | Create | `render(payload, json_mode)` for command results. |
| `cli/agentic/app.py` | Modify | Install global exception hook. |
| `cli/agentic/commands/_shell_helpers.py` | Modify | Raise `AgenticError` instead of typer.echo + Exit. |
| `cli/agentic/commands/status.py` | Modify | Use `ui.render`. |
| `cli/agentic/commands/next.py` | Modify | Use `ui.render`. |
| `cli/agentic/commands/run.py` | Modify | Use `ui.render`. |
| `cli/tests/test_errors.py` | Create | Structured error tests. |
| `cli/tests/snapshots/` | Create | Snapshots for `--json` outputs of every command group. |
| `cli/tests/test_json_schema.py` | Create | Strict snapshot comparisons. |

---

## Task 1: TDD — `AgenticError` + exception hook

**Files:**
- Create: `cli/agentic/ui/__init__.py` (empty)
- Create: `cli/agentic/ui/errors.py`
- Modify: `cli/agentic/app.py`
- Create: `cli/tests/test_errors.py`

- [ ] **Step 1: Write failing tests `cli/tests/test_errors.py`**

```python
import json

from agentic.app import app


def test_text_error_format(cli, tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    monkeypatch.delenv("AGENTIC_HOME", raising=False)
    result = cli.invoke(app, ["status"])
    assert result.exit_code == 6
    assert result.stderr.startswith("x  ") or result.stderr.startswith("✗ ")
    assert "next" in result.stderr.lower() or "hint" in result.stderr.lower() or "try" in result.stderr.lower()


def test_json_error_format(cli, tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    monkeypatch.delenv("AGENTIC_HOME", raising=False)
    result = cli.invoke(app, ["--json", "status"])
    assert result.exit_code == 6
    payload = json.loads(result.stderr)
    assert payload["_schema"] == "agentic.cli/v1"
    assert payload["error"]["category"] == "no_repo" or payload["error"]["category"] == "no_run_context"
    assert isinstance(payload["error"]["hints"], list)
    assert payload["error"]["hints"]
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd cli && pytest tests/test_errors.py -q
```

- [ ] **Step 3: Implement `cli/agentic/ui/errors.py`**

```python
"""Structured errors for the agentic CLI."""

from __future__ import annotations

import json as _json
import sys
from dataclasses import dataclass, field

import typer

EXIT_CODES = {
    "generic": 1,
    "misuse": 2,
    "validation_failed": 3,
    "authorization_denied": 4,
    "compat_failed": 5,
    "no_repo": 6,
    "no_run_context": 6,
    "script_failed": 64,  # base; actual = 64 + min(child_exit, 15)
}


@dataclass
class AgenticError(Exception):
    category: str
    message: str
    hints: list[str] = field(default_factory=list)
    exit_code: int | None = None

    def to_dict(self) -> dict:
        return {
            "_schema": "agentic.cli/v1",
            "error": {
                "category": self.category,
                "message": self.message,
                "hints": self.hints,
            },
        }


def render_error(err: AgenticError, *, json_mode: bool) -> int:
    """Print a structured error and return the exit code."""
    exit_code = err.exit_code or EXIT_CODES.get(err.category, 1)
    if json_mode:
        typer.echo(_json.dumps(err.to_dict(), indent=2), err=True)
    else:
        typer.echo(f"x  {err.message}", err=True)
        if err.hints:
            typer.echo("", err=True)
            for hint in err.hints:
                typer.echo(f"  {hint}", err=True)
    return exit_code


def install_global_handler(app: typer.Typer) -> None:
    """Wrap the Typer app so AgenticError becomes structured exit."""

    real_callback = app.callback

    # Typer doesn't expose a generic exception hook, so we intercept via sys.excepthook
    # only for AgenticError. main() handles it.
```

- [ ] **Step 4: Update `cli/agentic/app.py::main`**

```python
def main() -> None:
    from agentic.ui.errors import AgenticError, render_error
    import sys

    try:
        app()
    except AgenticError as e:
        # Determine json mode by re-parsing argv (Typer's ctx is gone here).
        json_mode = "--json" in sys.argv
        sys.exit(render_error(e, json_mode=json_mode))
```

- [ ] **Step 5: Refactor `cli/agentic/commands/_shell_helpers.py`** to raise `AgenticError`

Replace the typer.echo + Exit pattern in `invoke()`:

```python
from agentic.ui.errors import AgenticError

# inside invoke(), replacing previous error branches:
try:
    repo, _run_id, env = resolve(ctx, run_id_flag)
except RepoNotFound as e:
    raise AgenticError(
        category="no_repo",
        message=str(e),
        hints=["agentic --repo <path> <cmd>", "export AGENTIC_HOME=<path>"],
    )
except RunNotFound as e:
    raise AgenticError(
        category="no_run_context",
        message=str(e),
        hints=["agentic run list", "agentic run use <id>", "agentic --run-id <id> <cmd>"],
    )

runner = factory(repo)
try:
    result = runner.run(name=name, args=args, env_overrides=env)
except ScriptError as e:
    raise AgenticError(
        category="generic",
        message=str(e),
        hints=[f"agentic raw {name} ...  # if this script exists but isn't wrapped"],
    )

# emit stdout/stderr as before, but on non-zero:
if result.exit_code != 0:
    raise AgenticError(
        category="script_failed",
        message=f"scripts/{name} exited {result.exit_code}",
        hints=["Use -vv to stream the child stderr"],
        exit_code=64 + min(result.exit_code, 15),
    )
```

- [ ] **Step 6: Refactor `cli/agentic/commands/status.py`, `next.py`, `run.py`** likewise — replace inline `typer.echo(..., err=True); raise typer.Exit(6)` with `raise AgenticError(...)`.

- [ ] **Step 7: Run — expect PASS**

```bash
cd cli && pytest tests/test_errors.py -q
```

- [ ] **Step 8: Commit**

```bash
git add cli/agentic/ui/ cli/agentic/app.py cli/agentic/commands/
git commit -m "feat(cli): AgenticError + structured stderr (text + json)"
```

---

## Task 2: Snapshot tests for `--json` schema

**Files:**
- Create: `cli/tests/test_json_schema.py`
- Create: `cli/tests/snapshots/` (committed snapshot files appear after first run)

- [ ] **Step 1: Write `cli/tests/test_json_schema.py`**

```python
import json
from pathlib import Path

import pytest

from agentic.app import app


FIXTURES = Path(__file__).parent / "state_engine" / "fixtures"


def _seed(tmp_path: Path, fixture: str, run_id: str) -> Path:
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    d = tmp_path / "agentic" / "runs" / run_id
    d.mkdir(parents=True)
    (d / "manifest.yaml").write_text((FIXTURES / fixture).read_text())
    return tmp_path


@pytest.mark.parametrize("fixture,name", [
    ("planning_fresh_init.yaml", "status_planning"),
    ("planning_mixed_drafts.yaml", "next_planning_drafts"),
    ("impl_pending_task.yaml", "next_impl_dispatch"),
])
def test_json_schema_snapshot(cli, tmp_path, monkeypatch, snapshot, fixture, name):
    repo = _seed(tmp_path, fixture, "demo")
    monkeypatch.chdir(repo)
    cmd = ["--json", "next" if "next_" in name else "status", "--run-id", "demo"]
    result = cli.invoke(app, cmd)
    assert result.exit_code == 0
    payload = json.loads(result.stdout)
    assert payload["_schema"] == "agentic.cli/v1"
    snapshot.snapshot_dir = str(Path(__file__).parent / "snapshots")
    snapshot.assert_match(json.dumps(payload, indent=2, sort_keys=True), f"{name}.json")
```

- [ ] **Step 2: Run snapshots — first time records, subsequent times asserts**

```bash
cd cli && pytest tests/test_json_schema.py -q --snapshot-update
git add cli/tests/snapshots/
cd cli && pytest tests/test_json_schema.py -q
```

Expected: 3 passed.

- [ ] **Step 3: Lint + type**

```bash
cd cli && ruff check agentic tests && mypy --strict agentic
```

- [ ] **Step 4: Commit**

```bash
git add cli/tests/test_json_schema.py cli/tests/snapshots/
git commit -m "test(cli): --json schema snapshots (agentic.cli/v1)"
```

---

## Acceptance Criteria (from spec §13 CLI-11)

- `AgenticError` carries category, message, hints, and optional exit_code.
- Text errors render as `x  <message>\n\n  <hints>`.
- JSON errors render as `{"_schema": "agentic.cli/v1", "error": {...}}`.
- `--json` schema snapshot-locked for `status` and `next` per fixture.
- Coverage threshold maintained.

## Implementer / Reviewer

- **Implementer:** agency-agents Staff+ — `staff-software-engineer`.
- **Reviewer:** Claude Code CLI via AIT — `engineering-software-architect`, `engineering-code-reviewer`, `engineering-technical-writer`, `product-manager` (error UX is user-facing).

Evidence under `agentic/reviews/agentic-cli/CLI-11/`.

## Rollback

```bash
git revert <CLI-11 commits>
```
