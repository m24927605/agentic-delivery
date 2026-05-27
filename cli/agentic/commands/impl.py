"""`agentic impl ...` subcommands (spec §5.3).

Wraps the six implementation-phase scripts under a single namespace,
reusing the shared shell-out helpers and the same monkeypatch-friendly
``_runner_factory`` indirection used by ``plan`` / ``init``.
"""

from __future__ import annotations

from pathlib import Path
from typing import Annotated

import typer

from agentic.commands._shell_helpers import (
    RunnerFactory,
    default_factory,
    invoke,
)
from agentic.shell import ScriptRunner

app = typer.Typer(name="impl", help="Implementation tasks (dispatch, execute, review).")


def _runner_factory(repo: Path) -> ScriptRunner:
    """Indirection so tests can monkeypatch ``impl._runner_factory``."""
    return default_factory(repo)


def _factory() -> RunnerFactory:
    return _runner_factory


@app.command("init")
def init(
    ctx: typer.Context,
    from_planning: Annotated[
        str,
        typer.Option(
            "--from",
            help="Planning run id to initialize the implementation run from.",
        ),
    ],
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    """Initialize an implementation run from an approved planning run."""
    invoke(
        ctx,
        name="init-implementation-run.sh",
        args=["--planning-run", from_planning],
        run_id_flag=run_id,
        factory=_factory(),
    )


@app.command("tasks")
def tasks(
    ctx: typer.Context,
    dry_run: Annotated[bool, typer.Option("--dry-run")] = False,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    """Generate the implementation task graph."""
    invoke(
        ctx,
        name="generate-implementation-task-graph.sh",
        args=lambda rid: (["--dry-run", rid] if dry_run else [rid]),
        run_id_flag=run_id,
        factory=_factory(),
    )


@app.command("dispatch")
def dispatch(
    ctx: typer.Context,
    task_id: str,
    dry_run: Annotated[bool, typer.Option("--dry-run")] = False,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    """Dispatch a single implementation task to its actor."""
    def _args(rid: str) -> list[str]:
        out: list[str] = []
        if dry_run:
            out.append("--dry-run")
        out.extend([rid, task_id])
        return out

    invoke(
        ctx,
        name="dispatch-implementation-task.sh",
        args=_args,
        run_id_flag=run_id,
        factory=_factory(),
    )


@app.command("execute")
def execute(
    ctx: typer.Context,
    task_id: str,
    dry_run: Annotated[bool, typer.Option("--dry-run")] = False,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    """Execute a single implementation task end-to-end."""
    def _args(rid: str) -> list[str]:
        out: list[str] = []
        if dry_run:
            out.append("--dry-run")
        out.extend([rid, task_id])
        return out

    invoke(
        ctx,
        name="execute-implementation-task.sh",
        args=_args,
        run_id_flag=run_id,
        factory=_factory(),
    )


@app.command("review")
def review(
    ctx: typer.Context,
    task_id: str,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    """Run the implementation review loop for a task."""
    invoke(
        ctx,
        name="run-implementation-review-loop.sh",
        args=lambda rid: [rid, task_id],
        run_id_flag=run_id,
        factory=_factory(),
    )


@app.command("validate")
def validate(
    ctx: typer.Context,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    """Validate that an implementation run is complete and self-consistent."""
    invoke(
        ctx,
        name="validate-implementation-run.sh",
        args=lambda rid: [rid],
        run_id_flag=run_id,
        factory=_factory(),
    )
