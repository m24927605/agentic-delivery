"""Agentic CLI root."""

from __future__ import annotations

import platform
import sys
from pathlib import Path
from typing import Annotated

import typer

from agentic import __version__
from agentic.commands import next as next_cmd
from agentic.commands import run as run_cmd
from agentic.commands import status as status_cmd
from agentic.context import CompatError, RepoNotFound, RunNotFound, check_compat, resolve_repo

app = typer.Typer(
    name="agentic",
    help="Agentic Delivery — plan → review → approve → implement.",
    no_args_is_help=True,
    add_completion=True,
)

app.add_typer(run_cmd.app, name="run")
app.add_typer(status_cmd.app, name="status")
app.add_typer(next_cmd.app, name="next")


@app.callback()
def _root(
    ctx: typer.Context,
    repo: Annotated[
        Path | None,
        typer.Option("--repo", help="Path to agentic-delivery repo.", show_default=False),
    ] = None,
    run_id: Annotated[
        str | None,
        typer.Option("--run-id", help="Run id for this invocation.", show_default=False),
    ] = None,
    json_mode: Annotated[
        bool,
        typer.Option("--json", help="Emit structured JSON (envelope per spec §9.5)."),
    ] = False,
    no_compat_check: Annotated[
        bool, typer.Option("--no-compat-check", help="Skip pipeline.yaml compatibility check.")
    ] = False,
) -> None:
    ctx.obj = {
        "repo_flag": repo,
        "run_id_flag": run_id,
        "json": json_mode,
        "compat_check": not no_compat_check,
    }


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
        return
    try:
        result = check_compat(
            repo=repo.path, enabled=bool(ctx.obj.get("compat_check", True))
        )
    except CompatError as e:
        typer.echo(f"  pipeline: {e.actual}  (major mismatch: {','.join(e.ranges)} ✗)")
        raise typer.Exit(code=e.exit_code) from e
    if result is not None:
        typer.echo(f"  pipeline: {result.actual}  ({result.display})")


def main() -> None:
    try:
        app()
    except CompatError as e:
        sys.exit(e.exit_code)
    except RepoNotFound as e:
        sys.exit(e.exit_code)
    except RunNotFound as e:
        sys.exit(e.exit_code)


if __name__ == "__main__":
    main()
