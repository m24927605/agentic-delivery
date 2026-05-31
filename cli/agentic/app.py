"""Agentic CLI root."""

from __future__ import annotations

import platform
import sys
from pathlib import Path
from typing import Annotated

import typer

from agentic import __version__
from agentic.commands import boss as boss_cmd
from agentic.commands import doctor as doctor_cmd
from agentic.commands import evidence as evidence_cmd
from agentic.commands import fixtures as fixtures_cmd
from agentic.commands import hermes as hermes_cmd
from agentic.commands import identity as identity_cmd
from agentic.commands import impl as impl_cmd
from agentic.commands import init as init_cmd
from agentic.commands import manifest_cmd
from agentic.commands import new as new_cmd
from agentic.commands import next as next_cmd
from agentic.commands import plan as plan_cmd
from agentic.commands import raw as raw_cmd
from agentic.commands import run as run_cmd
from agentic.commands import status as status_cmd
from agentic.commands import validate as validate_cmd
from agentic.context import CompatError, RepoNotFound, RunNotFound, check_compat, resolve_repo
from agentic.ui.errors import AgenticError, set_json_mode

app = typer.Typer(
    name="agentic",
    help="Agentic Delivery — plan → review → approve → implement.",
    no_args_is_help=True,
    add_completion=True,
)

app.add_typer(run_cmd.app, name="run")
app.add_typer(status_cmd.app, name="status")
app.add_typer(next_cmd.app, name="next")
app.add_typer(plan_cmd.app, name="plan")
app.add_typer(impl_cmd.app, name="impl")
app.add_typer(boss_cmd.app, name="boss")
app.add_typer(hermes_cmd.app, name="hermes")
app.add_typer(identity_cmd.app, name="identity")
app.add_typer(evidence_cmd.app, name="evidence")
app.add_typer(fixtures_cmd.app, name="fixtures")
app.add_typer(manifest_cmd.app, name="manifest")
app.add_typer(validate_cmd.app, name="validate")
app.add_typer(doctor_cmd.app, name="doctor")
app.add_typer(raw_cmd.app, name="raw")
app.command(name="init", help=init_cmd.init_command.__doc__)(init_cmd.init_command)
app.command(name="new", help=new_cmd.new_command.__doc__)(new_cmd.new_command)


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
    actor: Annotated[
        str | None,
        typer.Option("--actor", help="Actor id propagated to scripts as AIT_ACTOR."),
    ] = None,
    role: Annotated[
        str | None,
        typer.Option("--role", help="Actor role propagated to scripts as AIT_ACTOR_ROLE."),
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
        "actor": actor,
        "role": role,
        "json": json_mode,
        "compat_check": not no_compat_check,
    }
    # Capture json_mode in the contextvar so any AgenticError raised downstream
    # renders with the correct stderr format without needing ctx threaded through.
    set_json_mode(json_mode)


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
    """CLI entry point.

    Normal failures inside command callbacks raise :class:`AgenticError`,
    which itself extends :class:`typer.Exit` — click's standalone-mode
    handler catches it and exits with the right code, after the
    constructor has already written the structured stderr.

    The ``except`` blocks below are defensive fallbacks for the small number
    of code paths that still surface raw :class:`CompatError` /
    :class:`RepoNotFound` / :class:`RunNotFound` (e.g. the ``version``
    command's compat probe) or for a bare ``AgenticError`` that somehow
    escapes the click boundary — in both cases we render via
    :func:`render_error` and exit.
    """
    try:
        app()
    except AgenticError as e:
        # Click normally swallows typer.Exit subclasses; this catches the
        # rare case where the error bubbles past standalone mode (e.g.
        # raised during typer's own setup, before invocation).
        sys.exit(e.exit_code)
    except CompatError as e:
        sys.exit(e.exit_code)
    except RepoNotFound as e:
        sys.exit(e.exit_code)
    except RunNotFound as e:
        sys.exit(e.exit_code)


__all__ = ["app", "main"]


if __name__ == "__main__":
    main()
