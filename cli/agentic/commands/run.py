"""`agentic run` subcommands."""

from __future__ import annotations

from pathlib import Path

import typer
from rich.console import Console
from rich.table import Table

from agentic.context import RepoNotFound, RunNotFound, resolve_repo, resolve_run_id
from agentic.ui.errors import AgenticError

app = typer.Typer(name="run", help="Manage current run context.")

_console = Console()


_REPO_HINTS = (
    "agentic --repo <path> run ...",
    "export AGENTIC_HOME=<path>",
    "cd into a directory under an agentic-delivery repo",
)

_RUN_HINTS = (
    "agentic run list",
    "agentic run use <id>",
    "agentic --run-id <id> <cmd>",
)


def _current_file(repo: Path) -> Path:
    return repo / ".agentic" / "current-run"


def _get_repo(ctx: typer.Context) -> Path:
    flag = ctx.obj.get("repo_flag") if ctx.obj else None
    try:
        return resolve_repo(repo_flag=flag).path
    except RepoNotFound as e:
        raise AgenticError(
            category="no_repo",
            message=str(e),
            hints=list(_REPO_HINTS),
        ) from e


@app.command("use")
def use(ctx: typer.Context, run_id: str) -> None:
    """Set <run-id> as the current run for this repo."""
    repo = _get_repo(ctx)
    try:
        run = resolve_run_id(repo=repo, flag=run_id)
    except RunNotFound as e:
        raise AgenticError(
            category="no_run_context",
            message=str(e),
            hints=list(_RUN_HINTS),
        ) from e
    target = _current_file(repo)
    target.parent.mkdir(exist_ok=True)
    target.write_text(run.id + "\n")
    typer.echo(f"current run -> {run.id}")


@app.command("show")
def show(ctx: typer.Context) -> None:
    """Print the resolved current run and its source."""
    repo = _get_repo(ctx)
    try:
        run = resolve_run_id(repo=repo, flag=None)
    except RunNotFound as e:
        raise AgenticError(
            category="no_run_context",
            message=str(e),
            hints=list(_RUN_HINTS),
        ) from e
    typer.echo(run.id)
    typer.echo(f"  source: {run.source}")


@app.command("clear")
def clear(ctx: typer.Context) -> None:
    """Delete the .agentic/current-run file."""
    repo = _get_repo(ctx)
    target = _current_file(repo)
    if target.exists():
        target.unlink()
        typer.echo("cleared")
    else:
        typer.echo("nothing to clear")


@app.command("list")
def list_(ctx: typer.Context) -> None:
    """List runs under agentic/runs/."""
    repo = _get_repo(ctx)
    runs_dir = repo / "agentic" / "runs"
    try:
        current: str | None = resolve_run_id(repo=repo, flag=None).id
    except RunNotFound:
        current = None
    table = Table(show_header=True)
    table.add_column("")
    table.add_column("run id")
    table.add_column("kind")
    if runs_dir.is_dir():
        for entry in sorted(runs_dir.iterdir()):
            if not entry.is_dir():
                continue
            kind = (
                "implementation"
                if (entry / "implementation-manifest.yaml").is_file()
                else "planning"
            )
            mark = "*" if entry.name == current else ""
            table.add_row(mark, entry.name, kind)
    _console.print(table)
