# CLI-10: `agentic raw` Escape Hatch Implementation Plan

> **For agentic-delivery pipeline:** Implementer = agency-agents Staff+. Reviewer = Claude Code CLI via AIT (security focus). Write scope `cli/**`.

**Goal:** Provide `agentic raw <script.sh> [args...]` so any script under `scripts/` — including future additions — is reachable without waiting for a CLI release.

**Architecture:** A single-command sub-app. Reuses `ScriptRunner`'s name validator + `_shell_helpers.resolve`. Args after the script name are forwarded unchanged. Security: `^[a-z0-9][a-z0-9-]*\.sh$` already enforced in `ScriptRunner`; this command re-checks for early UX feedback.

**Tech Stack:** typer.

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `cli/agentic/commands/raw.py` | Create | `agentic raw` command. |
| `cli/agentic/app.py` | Modify | Register `raw`. |
| `cli/tests/test_commands_raw.py` | Create | Security + happy path tests. |

---

## Task 1: TDD — security + happy path

**Files:**
- Create: `cli/agentic/commands/raw.py`
- Modify: `cli/agentic/app.py`
- Create: `cli/tests/test_commands_raw.py`

- [ ] **Step 1: Write failing tests `cli/tests/test_commands_raw.py`**

```python
from pathlib import Path

import pytest

from agentic.app import app
from agentic.commands import raw as raw_cmd
from tests._recording import RecordingRunner


def _seed(tmp_path: Path, scripts: dict[str, str]) -> Path:
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    (tmp_path / "scripts").mkdir()
    for name, body in scripts.items():
        p = tmp_path / "scripts" / name
        p.write_text(body)
        p.chmod(0o755)
    return tmp_path


@pytest.fixture
def runner(monkeypatch):
    rr = RecordingRunner()
    monkeypatch.setattr(raw_cmd, "_runner_factory", lambda repo: rr)
    return rr


def test_raw_routes_to_named_script(cli, tmp_path, monkeypatch, runner):
    repo = _seed(tmp_path, {"validate-agentic-system.sh": "#!/bin/sh\nexit 0\n"})
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["raw", "validate-agentic-system.sh", "--verbose"])
    assert result.exit_code == 0
    call = runner.calls[-1]
    assert call.name == "validate-agentic-system.sh"
    assert "--verbose" in call.args


def test_raw_refuses_path_traversal(cli, tmp_path, monkeypatch):
    repo = _seed(tmp_path, {"a.sh": "#!/bin/sh\nexit 0\n"})
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["raw", "../etc/passwd"])
    assert result.exit_code != 0
    assert "refused" in (result.stdout + result.stderr).lower() or "name" in (result.stdout + result.stderr).lower()


def test_raw_refuses_non_sh(cli, tmp_path, monkeypatch):
    repo = _seed(tmp_path, {"a.sh": "#!/bin/sh\nexit 0\n"})
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["raw", "evil"])
    assert result.exit_code != 0


def test_raw_refuses_absolute(cli, tmp_path, monkeypatch):
    repo = _seed(tmp_path, {"a.sh": "#!/bin/sh\nexit 0\n"})
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["raw", "/bin/sh"])
    assert result.exit_code != 0


def test_raw_refuses_missing(cli, tmp_path, monkeypatch):
    repo = _seed(tmp_path, {"a.sh": "#!/bin/sh\nexit 0\n"})
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["raw", "nonexistent.sh"])
    assert result.exit_code != 0


def test_raw_forwards_exit_code(cli, tmp_path, monkeypatch):
    """E2E (no RecordingRunner) — checks ScriptError + exit mapping."""
    repo = _seed(tmp_path, {"fail.sh": "#!/bin/sh\nexit 7\n"})
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["raw", "fail.sh"])
    assert result.exit_code == 64 + 7
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd cli && pytest tests/test_commands_raw.py -q
```

- [ ] **Step 3: Implement `cli/agentic/commands/raw.py`**

```python
"""`agentic raw <script.sh> [args...]` — escape hatch to any scripts/*.sh."""

from __future__ import annotations

import re
from typing import Annotated

import typer

from agentic.commands._shell_helpers import default_factory as _runner_factory
from agentic.context import RepoNotFound, resolve_repo
from agentic.shell import ScriptError

app = typer.Typer()


_SCRIPT_NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]*\.sh$")


@app.callback(invoke_without_command=True, context_settings={"allow_extra_args": True, "ignore_unknown_options": True})
def raw(
    ctx: typer.Context,
    script: str,
    args: Annotated[list[str] | None, typer.Argument()] = None,
) -> None:
    """Forward to scripts/<script> — name must match ^[a-z0-9][a-z0-9-]*\\.sh$."""
    if not _SCRIPT_NAME_RE.match(script):
        typer.echo(f"x  refused script name {script!r}: must match {_SCRIPT_NAME_RE.pattern}", err=True)
        raise typer.Exit(code=2)
    try:
        repo = resolve_repo(repo_flag=ctx.obj.get("repo_flag") if ctx.obj else None).path
    except RepoNotFound as e:
        typer.echo(f"x  {e}", err=True)
        raise typer.Exit(code=6)
    extra = list(ctx.args) + list(args or [])
    runner = _runner_factory(repo)
    try:
        result = runner.run(name=script, args=extra, env_overrides={})
    except ScriptError as e:
        typer.echo(f"x  {e}", err=True)
        raise typer.Exit(code=1)
    if result.stdout:
        typer.echo(result.stdout, nl=False)
    if result.stderr:
        typer.echo(result.stderr, err=True, nl=False)
    if result.exit_code != 0:
        raise typer.Exit(code=64 + min(result.exit_code, 15))
```

- [ ] **Step 4: Register in `cli/agentic/app.py`**

```python
from agentic.commands import raw as raw_cmd
app.add_typer(raw_cmd.app, name="raw")
```

- [ ] **Step 5: Run — expect PASS**

```bash
cd cli && pytest tests/test_commands_raw.py -q
```

Expected: 6 passed.

- [ ] **Step 6: Lint + type**

```bash
cd cli && ruff check agentic tests && mypy --strict agentic
```

- [ ] **Step 7: Commit**

```bash
git add cli/agentic/commands/raw.py cli/agentic/app.py cli/tests/test_commands_raw.py
git commit -m "feat(cli): agentic raw escape hatch with name validation"
```

---

## Acceptance Criteria (from spec §13 CLI-10)

- `agentic raw <name>` only accepts `^[a-z0-9][a-z0-9-]*\.sh$`.
- Refuses `..`, absolute paths, non-`.sh` strings, missing files.
- Forwards args verbatim.
- Forwards exit code via the 64+N mapping.

## Implementer / Reviewer

- **Implementer:** agency-agents Staff+ — `staff-software-engineer`.
- **Reviewer:** Claude Code CLI via AIT — `engineering-security-engineer` (mandatory — this is the security-critical surface), `engineering-code-reviewer`.

Evidence under `agentic/reviews/agentic-cli/CLI-10/`.

## Rollback

```bash
git revert <CLI-10 commits>
```
