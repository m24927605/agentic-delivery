# CLI-06: `shell.py` + `agentic plan` Namespace Implementation Plan

> **For agentic-delivery pipeline:** Implementer = agency-agents Staff+. Reviewer = Claude Code CLI via AIT. Write scope `cli/**`.

**Goal:** Provide a subprocess wrapper that propagates `RUN_ID`/`AIT_ACTOR`/`AIT_ACTOR_ROLE`, maps exit codes, and captures logs; then build the `agentic plan` Typer subcommand routing every planning script.

**Architecture:** `cli/agentic/shell.py::ScriptRunner` exposes `run(name, args, env_overrides)` returning a `ShellResult`. Tests inject a `RecordingRunner` via a `RUNNER_PROTOCOL` so command tests don't spawn processes. `cli/agentic/commands/plan.py` is a Typer sub-app per spec §5.2.

**Tech Stack:** subprocess, pathlib, typer.

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `cli/agentic/shell.py` | Create | ScriptRunner + ShellResult + ScriptError. |
| `cli/agentic/commands/plan.py` | Create | `agentic plan` sub-app. |
| `cli/agentic/app.py` | Modify | Register `plan`; add `--actor`/`--role`. |
| `cli/tests/test_shell.py` | Create | Subprocess wrapper unit tests. |
| `cli/tests/test_commands_plan.py` | Create | Command routing tests via RecordingRunner. |
| `cli/tests/_recording.py` | Create | Shared RecordingRunner test helper. |

---

## Task 1: TDD — `ScriptRunner`

**Files:**
- Create: `cli/agentic/shell.py`
- Create: `cli/tests/test_shell.py`
- Create: `cli/tests/_recording.py`

- [ ] **Step 1: Write helper `cli/tests/_recording.py`**

```python
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from agentic.shell import ShellResult


@dataclass
class _Call:
    name: str
    args: tuple[str, ...]
    env: dict[str, str]


@dataclass
class RecordingRunner:
    calls: list[_Call] = field(default_factory=list)
    next_result: ShellResult = field(default_factory=lambda: ShellResult(exit_code=0, stdout="", stderr=""))

    def run(self, name: str, args: list[str], env_overrides: dict[str, str]) -> ShellResult:
        self.calls.append(_Call(name=name, args=tuple(args), env=dict(env_overrides)))
        return self.next_result
```

- [ ] **Step 2: Write failing tests `cli/tests/test_shell.py`**

```python
import os
from pathlib import Path

import pytest

from agentic.shell import ScriptError, ScriptRunner, ShellResult


def _stub_repo(tmp_path: Path) -> Path:
    scripts = tmp_path / "scripts"
    scripts.mkdir()
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    return tmp_path


def _write_script(repo: Path, name: str, body: str) -> Path:
    p = repo / "scripts" / name
    p.write_text(body)
    p.chmod(0o755)
    return p


def test_runner_propagates_run_id_and_actor(tmp_path):
    repo = _stub_repo(tmp_path)
    _write_script(repo, "echo-env.sh", "#!/bin/sh\necho RUN_ID=$RUN_ID AIT_ACTOR=$AIT_ACTOR AIT_ACTOR_ROLE=$AIT_ACTOR_ROLE\n")
    runner = ScriptRunner(repo=repo)
    result = runner.run(
        name="echo-env.sh",
        args=[],
        env_overrides={"RUN_ID": "demo", "AIT_ACTOR": "alice", "AIT_ACTOR_ROLE": "approver"},
    )
    assert result.exit_code == 0
    assert "RUN_ID=demo" in result.stdout
    assert "AIT_ACTOR=alice" in result.stdout
    assert "AIT_ACTOR_ROLE=approver" in result.stdout


def test_runner_maps_nonzero_exit(tmp_path):
    repo = _stub_repo(tmp_path)
    _write_script(repo, "fail.sh", "#!/bin/sh\necho oops >&2\nexit 7\n")
    runner = ScriptRunner(repo=repo)
    result = runner.run(name="fail.sh", args=[], env_overrides={})
    assert result.exit_code == 7
    assert "oops" in result.stderr


def test_runner_refuses_path_traversal(tmp_path):
    repo = _stub_repo(tmp_path)
    runner = ScriptRunner(repo=repo)
    with pytest.raises(ScriptError):
        runner.run(name="../etc/passwd", args=[], env_overrides={})


def test_runner_refuses_unknown_script(tmp_path):
    repo = _stub_repo(tmp_path)
    runner = ScriptRunner(repo=repo)
    with pytest.raises(ScriptError):
        runner.run(name="nonexistent.sh", args=[], env_overrides={})
```

- [ ] **Step 3: Run — expect FAIL**

```bash
cd cli && pytest tests/test_shell.py -q
```

- [ ] **Step 4: Implement `cli/agentic/shell.py`**

```python
"""Subprocess wrapper for scripts/*.sh."""

from __future__ import annotations

import os
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

_SCRIPT_NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]*\.sh$")


class ScriptError(Exception):
    """Raised for invalid script names or missing scripts."""


@dataclass(frozen=True)
class ShellResult:
    exit_code: int
    stdout: str
    stderr: str


@dataclass
class ScriptRunner:
    repo: Path

    def run(self, *, name: str, args: list[str], env_overrides: dict[str, str]) -> ShellResult:
        if not _SCRIPT_NAME_RE.match(name):
            raise ScriptError(
                f"refused script name {name!r}: must match {_SCRIPT_NAME_RE.pattern}"
            )
        script = self.repo / "scripts" / name
        if not script.is_file():
            raise ScriptError(f"no such script: scripts/{name}")
        env = os.environ.copy()
        for k, v in env_overrides.items():
            if v is None:
                env.pop(k, None)
            else:
                env[k] = v
        proc = subprocess.run(
            [str(script), *args],
            cwd=self.repo,
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
        return ShellResult(exit_code=proc.returncode, stdout=proc.stdout, stderr=proc.stderr)
```

- [ ] **Step 5: Run — expect PASS**

```bash
cd cli && pytest tests/test_shell.py -q
```

- [ ] **Step 6: Commit**

```bash
git add cli/agentic/shell.py cli/tests/test_shell.py cli/tests/_recording.py
git commit -m "feat(cli): ScriptRunner with env propagation + name validation"
```

---

## Task 2: TDD — `agentic plan` namespace (RecordingRunner-based)

**Files:**
- Create: `cli/agentic/commands/plan.py`
- Modify: `cli/agentic/app.py`
- Create: `cli/tests/test_commands_plan.py`

- [ ] **Step 1: Add `--actor` / `--role` globals in `cli/agentic/app.py`**

```python
@app.callback()
def _root(
    ctx: typer.Context,
    repo: Annotated[Path | None, typer.Option("--repo")] = None,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
    actor: Annotated[str | None, typer.Option("--actor")] = None,
    role: Annotated[str | None, typer.Option("--role")] = None,
    json_mode: Annotated[bool, typer.Option("--json")] = False,
    no_compat_check: Annotated[bool, typer.Option("--no-compat-check")] = False,
) -> None:
    ctx.obj = {
        "repo_flag": repo,
        "run_id_flag": run_id,
        "actor": actor,
        "role": role,
        "json": json_mode,
        "compat_check": not no_compat_check,
    }
```

- [ ] **Step 2: Write failing tests `cli/tests/test_commands_plan.py`**

```python
from pathlib import Path

import pytest

from agentic.app import app
from agentic.commands import plan as plan_cmd
from agentic.shell import ShellResult
from tests._recording import RecordingRunner


def _seed(tmp_path: Path, run_id: str) -> Path:
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    d = tmp_path / "agentic" / "runs" / run_id
    d.mkdir(parents=True)
    (d / "manifest.yaml").write_text("run:\n  id: " + run_id + "\n  mode: planning\n")
    return tmp_path


@pytest.fixture
def runner(monkeypatch):
    rr = RecordingRunner()
    monkeypatch.setattr(plan_cmd, "_runner_factory", lambda repo: rr)
    return rr


def test_plan_generate_routes_to_script(cli, tmp_path, monkeypatch, runner):
    repo = _seed(tmp_path, "demo")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["plan", "generate", "--run-id", "demo"])
    assert result.exit_code == 0
    assert len(runner.calls) == 1
    call = runner.calls[0]
    assert call.name == "generate-artifacts.sh"
    assert call.args == ("demo",)
    assert call.env["RUN_ID"] == "demo"


def test_plan_artifact_approve_uses_sugar(cli, tmp_path, monkeypatch, runner):
    repo = _seed(tmp_path, "demo")
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app,
        [
            "--actor", "alice", "--role", "approver",
            "plan", "artifact", "docs/x.md", "approve", "--reason", "ship",
            "--run-id", "demo",
        ],
    )
    assert result.exit_code == 0
    call = runner.calls[-1]
    assert call.name == "update-artifact-status.sh"
    assert "approved" in call.args
    assert "docs/x.md" in call.args
    assert call.env["AIT_ACTOR"] == "alice"
    assert call.env["AIT_ACTOR_ROLE"] == "approver"
```

- [ ] **Step 3: Implement `cli/agentic/commands/plan.py`**

```python
"""`agentic plan ...` subcommands."""

from __future__ import annotations

from pathlib import Path
from typing import Annotated

import typer

from agentic.context import RepoNotFound, RunNotFound, resolve_repo, resolve_run_id
from agentic.shell import ScriptError, ScriptRunner

app = typer.Typer(name="plan", help="Planning artifacts (generate, review, approve).")


def _runner_factory(repo: Path) -> ScriptRunner:
    return ScriptRunner(repo=repo)


def _resolve(ctx: typer.Context, run_id_flag: str | None) -> tuple[Path, str, dict[str, str]]:
    flag = run_id_flag or (ctx.obj.get("run_id_flag") if ctx.obj else None)
    repo = resolve_repo(repo_flag=ctx.obj.get("repo_flag") if ctx.obj else None).path
    run = resolve_run_id(repo=repo, flag=flag)
    env: dict[str, str] = {"RUN_ID": run.id}
    actor = ctx.obj.get("actor") if ctx.obj else None
    role = ctx.obj.get("role") if ctx.obj else None
    if actor:
        env["AIT_ACTOR"] = actor
    if role:
        env["AIT_ACTOR_ROLE"] = role
    return repo, run.id, env


def _invoke(ctx: typer.Context, *, name: str, args: list[str], run_id_flag: str | None) -> None:
    try:
        repo, run_id, env = _resolve(ctx, run_id_flag)
    except (RepoNotFound, RunNotFound) as e:
        typer.echo(f"x  {e}", err=True)
        raise typer.Exit(code=6)
    runner = _runner_factory(repo)
    try:
        result = runner.run(name=name, args=args, env_overrides=env)
    except ScriptError as e:
        typer.echo(f"x  {e}", err=True)
        raise typer.Exit(code=1)
    if result.stdout:
        typer.echo(result.stdout, nl=False)
    if result.stderr:
        typer.echo(result.stderr, err=True, nl=False)
    if result.exit_code != 0:
        raise typer.Exit(code=64 + min(result.exit_code, 15))


@app.command("generate")
def generate(
    ctx: typer.Context,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    _invoke(ctx, name="generate-artifacts.sh", args=[_resolve(ctx, run_id)[1]], run_id_flag=run_id)


@app.command("generate-agent")
def generate_agent(
    ctx: typer.Context,
    dry_run: Annotated[bool, typer.Option("--dry-run/--execute")] = True,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    _, rid, _ = _resolve(ctx, run_id)
    args = ["--dry-run" if dry_run else "--execute", rid]
    _invoke(ctx, name="run-artifact-generation-agent.sh", args=args, run_id_flag=run_id)


@app.command("review")
def review(
    ctx: typer.Context,
    artifact: Annotated[str, typer.Option("--artifact")],
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    _, rid, _ = _resolve(ctx, run_id)
    _invoke(ctx, name="run-artifact-review-loop.sh",
            args=[rid, "--artifact", artifact], run_id_flag=run_id)


@app.command("revisions")
def revisions(
    ctx: typer.Context,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    _, rid, _ = _resolve(ctx, run_id)
    _invoke(ctx, name="create-artifact-revision-tasks.sh", args=[rid], run_id_flag=run_id)


@app.command("strategy-gate")
def strategy_gate(ctx: typer.Context) -> None:
    _invoke(ctx, name="strategy-gate-check.sh", args=[], run_id_flag=None)


@app.command("state")
def state(
    ctx: typer.Context,
    new_state: str,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    _, rid, _ = _resolve(ctx, run_id)
    _invoke(ctx, name="update-run-state.sh", args=[rid, new_state], run_id_flag=run_id)


agency = typer.Typer(help="Agency review.")
app.add_typer(agency, name="agency")


@agency.command("review")
def agency_review(
    ctx: typer.Context,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    _invoke(ctx, name="run-agency-review.sh", args=[], run_id_flag=run_id)


@agency.command("summarize")
def agency_summarize(
    ctx: typer.Context,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    _, rid, _ = _resolve(ctx, run_id)
    _invoke(ctx, name="summarize-agency-review.sh", args=[rid], run_id_flag=run_id)


@app.command("artifact")
def artifact(
    ctx: typer.Context,
    path: str,
    status: str,
    reason: Annotated[str, typer.Option("--reason")],
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    """Update artifact status. status ∈ {approve,reject,defer,reviewed,drafted,changes_requested,approved,rejected,deferred}."""
    sugar = {
        "approve": "approved", "reject": "rejected", "defer": "deferred",
    }
    target = sugar.get(status, status)
    valid = {"drafted", "reviewed", "changes_requested", "approved", "rejected", "deferred"}
    if target not in valid:
        typer.echo(f"x  unknown status {status!r}; valid: {sorted(valid)}", err=True)
        raise typer.Exit(code=2)
    _, rid, _ = _resolve(ctx, run_id)
    extra = ["--actor", ctx.obj.get("actor"), "--role", ctx.obj.get("role")] if (ctx.obj and ctx.obj.get("actor")) else []
    _invoke(
        ctx,
        name="update-artifact-status.sh",
        args=[rid, path, target, "--reason", reason, *extra],
        run_id_flag=run_id,
    )
```

- [ ] **Step 4: Register in `cli/agentic/app.py`**

```python
from agentic.commands import plan as plan_cmd
app.add_typer(plan_cmd.app, name="plan")
```

- [ ] **Step 5: Run — expect PASS**

```bash
cd cli && pytest tests/test_commands_plan.py -q
```

- [ ] **Step 6: Lint + type**

```bash
cd cli && ruff check agentic tests && mypy --strict agentic
```

- [ ] **Step 7: Commit**

```bash
git add cli/agentic/commands/plan.py cli/agentic/app.py cli/tests/test_commands_plan.py
git commit -m "feat(cli): agentic plan namespace"
```

---

## Acceptance Criteria (from spec §13 CLI-06)

- `ScriptRunner` propagates `RUN_ID`, `AIT_ACTOR`, `AIT_ACTOR_ROLE`; refuses invalid names.
- `agentic plan generate / review / revisions / strategy-gate / state / agency review / agency summarize / artifact` all route to their scripts.
- `--actor` / `--role` globals feed env passthrough.
- `agentic plan artifact <path> approve --reason ...` sugar maps to `update-artifact-status.sh ... approved`.
- Exit code mapping ≥ 64 for forwarded script failures.

## Implementer / Reviewer

- **Implementer:** agency-agents Staff+ — `staff-software-engineer`.
- **Reviewer:** Claude Code CLI via AIT — `engineering-software-architect`, `engineering-security-engineer`, `engineering-code-reviewer`.

Evidence under `agentic/reviews/agentic-cli/CLI-06/`.

## Rollback

```bash
git revert <CLI-06 commits>
```
