"""`agentic hermes ...` subcommands (spec §5.5).

Wraps the Hermes adapter scripts under a single namespace:
``validate-hermes-actions.sh``, ``run-hermes-action.sh``,
``hermes-memory-sync.sh``, ``hermes-scheduler-dry-run.sh``,
``hermes-gateway-dry-run.sh``. All commands run against the repo
without a run-id requirement: Hermes operations are system-level
(actions listing, memory sync, scheduler/gateway dry-runs) and the
``run`` action receives any per-call ``key=value`` args positionally.
"""

from __future__ import annotations

from pathlib import Path
from typing import Annotated, Optional

import typer

from agentic.commands._shell_helpers import (
    RunnerFactory,
    default_factory,
    invoke_no_run,
)
from agentic.shell import ScriptRunner

app = typer.Typer(name="hermes", help="Hermes adapter actions.")
actions = typer.Typer(help="Hermes actions list / validate.")
app.add_typer(actions, name="actions")


def _runner_factory(repo: Path) -> ScriptRunner:
    """Indirection so tests can monkeypatch ``hermes._runner_factory``."""
    return default_factory(repo)


def _factory() -> RunnerFactory:
    return _runner_factory


@actions.command("list")
def actions_list(ctx: typer.Context) -> None:
    """List the actions exposed by the Hermes adapter."""
    invoke_no_run(
        ctx,
        name="validate-hermes-actions.sh",
        args=[],
        factory=_factory(),
    )


@actions.command("validate")
def actions_validate(ctx: typer.Context) -> None:
    """Validate the Hermes actions manifest."""
    invoke_no_run(
        ctx,
        name="validate-hermes-actions.sh",
        args=[],
        factory=_factory(),
    )


@app.command("run")
def hermes_run(
    ctx: typer.Context,
    action: Annotated[str, typer.Argument(help="Hermes action name.")],
    kv_args: Annotated[
        Optional[list[str]],
        typer.Argument(help="Optional ``key=value`` arguments forwarded to the action."),
    ] = None,
) -> None:
    """Run a Hermes action — ``agentic hermes run <action> [k=v ...]``."""
    args: list[str] = [action, *(kv_args or [])]
    invoke_no_run(
        ctx,
        name="run-hermes-action.sh",
        args=args,
        factory=_factory(),
    )


@app.command("memory-sync")
def memory_sync(
    ctx: typer.Context,
    dry_run: Annotated[
        bool, typer.Option("--dry-run/--no-dry-run")
    ] = True,
) -> None:
    """Sync the Hermes memory store (default: dry-run)."""
    args = ["--dry-run"] if dry_run else []
    invoke_no_run(
        ctx,
        name="hermes-memory-sync.sh",
        args=args,
        factory=_factory(),
    )


@app.command("scheduler")
def scheduler(
    ctx: typer.Context,
    dry_run: Annotated[
        bool, typer.Option("--dry-run/--no-dry-run")
    ] = True,
) -> None:
    """Run the Hermes scheduler dry-run."""
    args = ["--dry-run"] if dry_run else []
    invoke_no_run(
        ctx,
        name="hermes-scheduler-dry-run.sh",
        args=args,
        factory=_factory(),
    )


@app.command("gateway")
def gateway(
    ctx: typer.Context,
    dry_run: Annotated[
        bool, typer.Option("--dry-run/--no-dry-run")
    ] = True,
) -> None:
    """Run the Hermes gateway dry-run."""
    args = ["--dry-run"] if dry_run else []
    invoke_no_run(
        ctx,
        name="hermes-gateway-dry-run.sh",
        args=args,
        factory=_factory(),
    )
