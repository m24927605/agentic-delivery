# CLI-07: `agentic impl` Namespace Implementation Plan

> **For agentic-delivery pipeline:** Implementer = agency-agents Staff+. Reviewer = Claude Code CLI via AIT. Write scope `cli/**`.

**Goal:** Wrap the six implementation-phase scripts under `agentic impl` per spec §5.3, reusing `ScriptRunner` from CLI-06.

**Architecture:** New Typer sub-app `cli/agentic/commands/impl.py`. Each subcommand resolves run id via `_resolve()` helper (mirrors CLI-06 plan.py), feeds positional + actor/role to `update-…` / `dispatch-…` / `execute-…` / `run-…-review-loop` scripts.

**Tech Stack:** typer, reusable `ScriptRunner` + `RecordingRunner`.

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `cli/agentic/commands/impl.py` | Create | `agentic impl` sub-app. |
| `cli/agentic/commands/_shell_helpers.py` | Create | DRY: extract `_resolve` + `_invoke` from plan.py for reuse. |
| `cli/agentic/commands/plan.py` | Modify | Import the helpers from `_shell_helpers`. |
| `cli/agentic/app.py` | Modify | Register `impl`. |
| `cli/tests/test_commands_impl.py` | Create | Routing tests via `RecordingRunner`. |

---

## Task 1: Extract reusable command helpers (DRY refactor)

**Files:**
- Create: `cli/agentic/commands/_shell_helpers.py`
- Modify: `cli/agentic/commands/plan.py`

- [ ] **Step 1: Create `cli/agentic/commands/_shell_helpers.py`**

```python
"""Shared helpers for command sub-apps that shell out to scripts/*.sh."""

from __future__ import annotations

from pathlib import Path
from typing import Callable

import typer

from agentic.context import RepoNotFound, RunNotFound, resolve_repo, resolve_run_id
from agentic.shell import ScriptError, ScriptRunner

RunnerFactory = Callable[[Path], ScriptRunner]


def default_factory(repo: Path) -> ScriptRunner:
    return ScriptRunner(repo=repo)


def resolve(ctx: typer.Context, run_id_flag: str | None) -> tuple[Path, str, dict[str, str]]:
    flag = run_id_flag or (ctx.obj.get("run_id_flag") if ctx.obj else None)
    repo = resolve_repo(repo_flag=ctx.obj.get("repo_flag") if ctx.obj else None).path
    run = resolve_run_id(repo=repo, flag=flag)
    env: dict[str, str] = {"RUN_ID": run.id}
    if ctx.obj:
        if ctx.obj.get("actor"):
            env["AIT_ACTOR"] = ctx.obj["actor"]
        if ctx.obj.get("role"):
            env["AIT_ACTOR_ROLE"] = ctx.obj["role"]
    return repo, run.id, env


def invoke(
    ctx: typer.Context,
    *,
    name: str,
    args: list[str],
    run_id_flag: str | None,
    factory: RunnerFactory = default_factory,
) -> None:
    try:
        repo, _run_id, env = resolve(ctx, run_id_flag)
    except (RepoNotFound, RunNotFound) as e:
        typer.echo(f"x  {e}", err=True)
        raise typer.Exit(code=6)
    runner = factory(repo)
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
```

- [ ] **Step 2: Refactor `cli/agentic/commands/plan.py`** — replace `_runner_factory`, `_resolve`, `_invoke` with imports from `_shell_helpers`. Keep existing test contract: `plan_cmd._runner_factory` is monkeypatched in tests, so re-export it:

```python
# at top of plan.py
from agentic.commands._shell_helpers import default_factory as _runner_factory
from agentic.commands._shell_helpers import resolve as _resolve
from agentic.commands._shell_helpers import invoke as _invoke
```

Adjust each `@app.command()` to call `_invoke(ctx, name=..., args=..., run_id_flag=run_id, factory=_runner_factory)` — same arguments, just routed through the imported helper.

- [ ] **Step 3: Run existing plan tests — expect PASS**

```bash
cd cli && pytest tests/test_commands_plan.py -q
```

(`monkeypatch.setattr(plan_cmd, "_runner_factory", ...)` still works because we re-exported the name on the module.)

- [ ] **Step 4: Commit**

```bash
git add cli/agentic/commands/_shell_helpers.py cli/agentic/commands/plan.py
git commit -m "refactor(cli): extract shared shell-out helpers"
```

---

## Task 2: TDD — `agentic impl` namespace

**Files:**
- Create: `cli/agentic/commands/impl.py`
- Modify: `cli/agentic/app.py`
- Create: `cli/tests/test_commands_impl.py`

- [ ] **Step 1: Write failing tests `cli/tests/test_commands_impl.py`**

```python
from pathlib import Path

import pytest

from agentic.app import app
from agentic.commands import impl as impl_cmd
from tests._recording import RecordingRunner


def _seed_impl(tmp_path: Path, run_id: str) -> Path:
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    d = tmp_path / "agentic" / "runs" / run_id
    d.mkdir(parents=True)
    (d / "implementation-manifest.yaml").write_text(
        "run:\n  id: " + run_id + "\n  mode: implementation\n"
    )
    return tmp_path


@pytest.fixture
def runner(monkeypatch):
    rr = RecordingRunner()
    monkeypatch.setattr(impl_cmd, "_runner_factory", lambda repo: rr)
    return rr


def test_impl_init_from_planning_run(cli, tmp_path, monkeypatch, runner):
    repo = _seed_impl(tmp_path, "impl-run")
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app,
        ["impl", "init", "--from", "planning-run", "--run-id", "impl-run"],
    )
    assert result.exit_code == 0
    call = runner.calls[-1]
    assert call.name == "init-implementation-run.sh"
    assert "--planning-run" in call.args
    assert "planning-run" in call.args
    assert call.env["RUN_ID"] == "impl-run"


def test_impl_tasks_dry_run_forwards_flag(cli, tmp_path, monkeypatch, runner):
    repo = _seed_impl(tmp_path, "impl-run")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["impl", "tasks", "--dry-run", "--run-id", "impl-run"])
    assert result.exit_code == 0
    call = runner.calls[-1]
    assert call.name == "generate-implementation-task-graph.sh"
    assert "--dry-run" in call.args


def test_impl_dispatch_with_actor_role(cli, tmp_path, monkeypatch, runner):
    repo = _seed_impl(tmp_path, "impl-run")
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app,
        [
            "--actor", "alice", "--role", "operator",
            "impl", "dispatch", "T1", "--run-id", "impl-run",
        ],
    )
    assert result.exit_code == 0
    call = runner.calls[-1]
    assert call.name == "dispatch-implementation-task.sh"
    assert "T1" in call.args
    assert call.env["AIT_ACTOR"] == "alice"
    assert call.env["AIT_ACTOR_ROLE"] == "operator"


def test_impl_execute_dry_run(cli, tmp_path, monkeypatch, runner):
    repo = _seed_impl(tmp_path, "impl-run")
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app,
        ["impl", "execute", "T1", "--dry-run", "--run-id", "impl-run"],
    )
    assert result.exit_code == 0
    call = runner.calls[-1]
    assert call.name == "execute-implementation-task.sh"
    assert "--dry-run" in call.args
    assert "T1" in call.args


def test_impl_review_forwards_task_id(cli, tmp_path, monkeypatch, runner):
    repo = _seed_impl(tmp_path, "impl-run")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["impl", "review", "T2", "--run-id", "impl-run"])
    assert result.exit_code == 0
    call = runner.calls[-1]
    assert call.name == "run-implementation-review-loop.sh"
    assert "T2" in call.args


def test_impl_validate(cli, tmp_path, monkeypatch, runner):
    repo = _seed_impl(tmp_path, "impl-run")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["impl", "validate", "--run-id", "impl-run"])
    assert result.exit_code == 0
    call = runner.calls[-1]
    assert call.name == "validate-implementation-run.sh"
    assert "impl-run" in call.args
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd cli && pytest tests/test_commands_impl.py -q
```

- [ ] **Step 3: Implement `cli/agentic/commands/impl.py`**

```python
"""`agentic impl ...` subcommands."""

from __future__ import annotations

from typing import Annotated

import typer

from agentic.commands._shell_helpers import default_factory as _runner_factory
from agentic.commands._shell_helpers import invoke as _invoke
from agentic.commands._shell_helpers import resolve as _resolve

app = typer.Typer(name="impl", help="Implementation tasks (dispatch, execute, review).")


@app.command("init")
def init(
    ctx: typer.Context,
    from_planning: Annotated[str, typer.Option("--from")],
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    _invoke(
        ctx,
        name="init-implementation-run.sh",
        args=["--planning-run", from_planning],
        run_id_flag=run_id,
        factory=_runner_factory,
    )


@app.command("tasks")
def tasks(
    ctx: typer.Context,
    dry_run: Annotated[bool, typer.Option("--dry-run")] = False,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    _, rid, _ = _resolve(ctx, run_id)
    args = ["--dry-run", rid] if dry_run else [rid]
    _invoke(ctx, name="generate-implementation-task-graph.sh",
            args=args, run_id_flag=run_id, factory=_runner_factory)


@app.command("dispatch")
def dispatch(
    ctx: typer.Context,
    task_id: str,
    dry_run: Annotated[bool, typer.Option("--dry-run")] = False,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    _, rid, _ = _resolve(ctx, run_id)
    args = []
    if dry_run:
        args.append("--dry-run")
    args.extend([rid, task_id])
    _invoke(ctx, name="dispatch-implementation-task.sh",
            args=args, run_id_flag=run_id, factory=_runner_factory)


@app.command("execute")
def execute(
    ctx: typer.Context,
    task_id: str,
    dry_run: Annotated[bool, typer.Option("--dry-run")] = False,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    _, rid, _ = _resolve(ctx, run_id)
    args = []
    if dry_run:
        args.append("--dry-run")
    args.extend([rid, task_id])
    _invoke(ctx, name="execute-implementation-task.sh",
            args=args, run_id_flag=run_id, factory=_runner_factory)


@app.command("review")
def review(
    ctx: typer.Context,
    task_id: str,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    _, rid, _ = _resolve(ctx, run_id)
    _invoke(ctx, name="run-implementation-review-loop.sh",
            args=[rid, task_id], run_id_flag=run_id, factory=_runner_factory)


@app.command("validate")
def validate(
    ctx: typer.Context,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    _, rid, _ = _resolve(ctx, run_id)
    _invoke(ctx, name="validate-implementation-run.sh",
            args=[rid], run_id_flag=run_id, factory=_runner_factory)
```

- [ ] **Step 4: Register in `cli/agentic/app.py`**

```python
from agentic.commands import impl as impl_cmd
app.add_typer(impl_cmd.app, name="impl")
```

- [ ] **Step 5: Run — expect PASS**

```bash
cd cli && pytest tests/test_commands_impl.py -q
```

- [ ] **Step 6: Lint + type**

```bash
cd cli && ruff check agentic tests && mypy --strict agentic
```

- [ ] **Step 7: Commit**

```bash
git add cli/agentic/commands/impl.py cli/agentic/app.py cli/tests/test_commands_impl.py
git commit -m "feat(cli): agentic impl namespace"
```

---

## Acceptance Criteria (from spec §13 CLI-07)

- `agentic impl init/tasks/dispatch/execute/review/validate` all route to their respective scripts.
- `--dry-run` forwarded to scripts that accept it (`tasks`, `dispatch`, `execute`).
- `--actor` / `--role` propagated via env.
- RecordingRunner-based tests assert argv + env, no real subprocess.

## Implementer / Reviewer

- **Implementer:** agency-agents Staff+ — `staff-software-engineer`.
- **Reviewer:** Claude Code CLI via AIT — `engineering-software-architect`, `engineering-security-engineer`, `engineering-code-reviewer`.

Evidence under `agentic/reviews/agentic-cli/CLI-07/`.

## Rollback

```bash
git revert <CLI-07 commits>
```
