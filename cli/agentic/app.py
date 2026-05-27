"""Agentic CLI root."""

from __future__ import annotations

import platform
import sys
from pathlib import Path
from typing import Annotated

import typer

from agentic import __version__
from agentic.context import RepoNotFound, resolve_repo

app = typer.Typer(
    name="agentic",
    help="Agentic Delivery — plan → review → approve → implement.",
    no_args_is_help=True,
    add_completion=True,
)


@app.callback()
def _root(
    ctx: typer.Context,
    repo: Annotated[
        Path | None,
        typer.Option("--repo", help="Path to agentic-delivery repo.", show_default=False),
    ] = None,
    no_compat_check: Annotated[
        bool, typer.Option("--no-compat-check", help="Skip pipeline.yaml compatibility check.")
    ] = False,
) -> None:
    ctx.obj = {"repo_flag": repo, "compat_check": not no_compat_check}


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


def main() -> None:
    app()


if __name__ == "__main__":
    main()
