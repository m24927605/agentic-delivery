# CLI-12: Tab Completion + `agentic doctor` Implementation Plan

> **For agentic-delivery pipeline:** Implementer = agency-agents Staff+. Reviewer = Claude Code CLI via AIT. Write scope `cli/**`.

**Goal:** Expose Typer's built-in shell completion via `agentic --install-completion`, and implement `agentic doctor` to batch-run validators with structured exit semantics.

**Architecture:** Completion is enabled by `add_completion=True` already on the Typer app (set in CLI-01). `doctor` is a new command that calls four scripts in sequence: `validate-agentic-system.sh`, `validate-manifest-schema.sh --all`, `privacy-scan-tracked.sh`, `validate-identity-policy.sh`. Each is run via `ScriptRunner`; failures aggregated into a single `AgenticError` with hints.

**Tech Stack:** typer, rich (for the summary table), `AgenticError` from CLI-11.

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `cli/agentic/commands/doctor.py` | Create | `agentic doctor`. |
| `cli/agentic/app.py` | Modify | Register `doctor`. |
| `cli/tests/test_doctor.py` | Create | Pass + fail behavior tests. |

---

## Task 1: TDD — `agentic doctor`

**Files:**
- Create: `cli/agentic/commands/doctor.py`
- Modify: `cli/agentic/app.py`
- Create: `cli/tests/test_doctor.py`

- [ ] **Step 1: Write failing tests `cli/tests/test_doctor.py`**

```python
import json
from pathlib import Path

import pytest

from agentic.app import app
from agentic.commands import doctor as doctor_cmd
from agentic.shell import ShellResult
from tests._recording import RecordingRunner


def _seed(tmp_path: Path) -> Path:
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    return tmp_path


@pytest.fixture
def runner(monkeypatch):
    rr = RecordingRunner()
    monkeypatch.setattr(doctor_cmd, "_runner_factory", lambda repo: rr)
    return rr


def test_doctor_all_pass(cli, tmp_path, monkeypatch, runner):
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    runner.next_result = ShellResult(exit_code=0, stdout="", stderr="")
    result = cli.invoke(app, ["doctor"])
    assert result.exit_code == 0
    names = [c.name for c in runner.calls]
    assert "validate-agentic-system.sh" in names
    assert "validate-manifest-schema.sh" in names
    assert "privacy-scan-tracked.sh" in names
    assert "validate-identity-policy.sh" in names


def test_doctor_aggregates_failure(cli, tmp_path, monkeypatch):
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)

    class _FailingRunner:
        def __init__(self) -> None:
            self.calls = []

        def run(self, *, name, args, env_overrides):
            self.calls.append(name)
            return ShellResult(exit_code=0 if name == "privacy-scan-tracked.sh" else 1, stdout="", stderr="boom")

    fr = _FailingRunner()
    monkeypatch.setattr(doctor_cmd, "_runner_factory", lambda repo: fr)
    result = cli.invoke(app, ["doctor"])
    assert result.exit_code != 0
    assert "FAIL" in result.stdout or "fail" in result.stdout.lower()


def test_doctor_json_envelope(cli, tmp_path, monkeypatch, runner):
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    runner.next_result = ShellResult(exit_code=0, stdout="", stderr="")
    result = cli.invoke(app, ["--json", "doctor"])
    assert result.exit_code == 0
    payload = json.loads(result.stdout)
    assert payload["_schema"] == "agentic.cli/v1"
    assert "checks" in payload
    assert isinstance(payload["checks"], list)
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd cli && pytest tests/test_doctor.py -q
```

- [ ] **Step 3: Implement `cli/agentic/commands/doctor.py`**

```python
"""`agentic doctor` — batch validators."""

from __future__ import annotations

import json as _json
from dataclasses import dataclass
from typing import Annotated

import typer
from rich.console import Console
from rich.table import Table

from agentic.commands._shell_helpers import default_factory as _runner_factory
from agentic.context import RepoNotFound, resolve_repo
from agentic.shell import ScriptError
from agentic.ui.errors import AgenticError

app = typer.Typer()
_console = Console()


@dataclass
class _Check:
    name: str
    script: str
    args: list[str]
    status: str = "pending"
    exit_code: int = -1
    stderr: str = ""


_DOCTOR_CHECKS = [
    _Check("system", "validate-agentic-system.sh", []),
    _Check("manifest", "validate-manifest-schema.sh", ["--all"]),
    _Check("privacy", "privacy-scan-tracked.sh", []),
    _Check("identity", "validate-identity-policy.sh", []),
]


@app.callback(invoke_without_command=True)
def doctor(ctx: typer.Context) -> None:
    """Run all validators and report aggregated status."""
    try:
        repo = resolve_repo(repo_flag=ctx.obj.get("repo_flag") if ctx.obj else None).path
    except RepoNotFound as e:
        raise AgenticError(category="no_repo", message=str(e),
                           hints=["agentic --repo <path> doctor"])
    runner = _runner_factory(repo)
    checks = [
        _Check(c.name, c.script, list(c.args)) for c in _DOCTOR_CHECKS
    ]
    for c in checks:
        try:
            r = runner.run(name=c.script, args=c.args, env_overrides={})
        except ScriptError as e:
            c.status = "ERROR"
            c.stderr = str(e)
            continue
        c.exit_code = r.exit_code
        c.status = "PASS" if r.exit_code == 0 else "FAIL"
        c.stderr = r.stderr

    if ctx.obj and ctx.obj.get("json"):
        typer.echo(_json.dumps({
            "_schema": "agentic.cli/v1",
            "checks": [
                {"name": c.name, "script": c.script, "status": c.status, "exit_code": c.exit_code}
                for c in checks
            ],
        }, indent=2))
    else:
        table = Table(show_header=True, title="agentic doctor")
        table.add_column("status")
        table.add_column("name")
        table.add_column("script")
        for c in checks:
            table.add_row(c.status, c.name, c.script)
        _console.print(table)

    failing = [c for c in checks if c.status != "PASS"]
    if failing:
        raise AgenticError(
            category="validation_failed",
            message=f"{len(failing)}/{len(checks)} doctor checks failed",
            hints=[f"agentic raw {c.script}  # rerun individually" for c in failing],
        )
```

- [ ] **Step 4: Register in `cli/agentic/app.py`**

```python
from agentic.commands import doctor as doctor_cmd
app.add_typer(doctor_cmd.app, name="doctor")
```

- [ ] **Step 5: Run — expect PASS**

```bash
cd cli && pytest tests/test_doctor.py -q
```

- [ ] **Step 6: Manual completion smoke**

```bash
cd cli && agentic --install-completion bash
# Tab completion should now suggest subcommands in a new shell.
```

(Not testable in CI; document in CHANGELOG.)

- [ ] **Step 7: Lint + type**

```bash
cd cli && ruff check agentic tests && mypy --strict agentic
```

- [ ] **Step 8: Update `cli/CHANGELOG.md`**

```markdown
## [0.1.0] — unreleased

- ...prior entries...
- Added `agentic doctor` aggregating validate-* scripts.
- Tab completion available via `agentic --install-completion <shell>`.
```

- [ ] **Step 9: Commit**

```bash
git add cli/agentic/commands/doctor.py cli/agentic/app.py cli/tests/test_doctor.py cli/CHANGELOG.md
git commit -m "feat(cli): agentic doctor + completion smoke"
```

---

## Acceptance Criteria (from spec §13 CLI-12)

- `agentic doctor` calls four validators; aggregates result.
- Non-zero overall when ≥ 1 check fails; exit code 3 via `AgenticError("validation_failed")`.
- `--json` produces `_schema: agentic.cli/v1` with `checks: [...]`.
- `agentic --install-completion bash|zsh|fish` works.

## Implementer / Reviewer

- **Implementer:** agency-agents Staff+ — `staff-software-engineer`.
- **Reviewer:** Claude Code CLI via AIT — `engineering-software-architect`, `engineering-code-reviewer`.

Evidence under `agentic/reviews/agentic-cli/CLI-12/`.

## Rollback

```bash
git revert <CLI-12 commits>
```
