"""`agentic init "goal" [--goal-file <f>] [--profile <id>]` — wraps scripts/init-agentic-run.sh.

Spec §5.1 / §5.6 — closes the top-level hot-path coverage gap so the planning
lifecycle is reachable end-to-end from the CLI.

Registered on the root via ``app.command("init")(init_command)`` in
``agentic/app.py`` (not via ``add_typer``) because typer treats single-callback
sub-apps as needing a ``COMMAND`` positional, which conflicts with the
``[GOAL]`` argument here.
"""

from __future__ import annotations

from pathlib import Path
from typing import Annotated

import typer

from agentic.commands._shell_helpers import RunnerFactory, default_factory, invoke_without_run
from agentic.shell import ScriptRunner


def _runner_factory(repo: Path) -> ScriptRunner:
    return default_factory(repo)


def _factory() -> RunnerFactory:
    """Indirect lookup so tests can monkeypatch ``init._runner_factory``."""
    return _runner_factory


def init_command(
    ctx: typer.Context,
    goal: Annotated[
        str | None,
        typer.Argument(help="Free-text goal description (optional if --goal-file is given)."),
    ] = None,
    goal_file: Annotated[
        Path | None,
        typer.Option(
            "--goal-file",
            help="Path to a goal markdown file (optional YAML frontmatter).",
        ),
    ] = None,
    profile: Annotated[
        str | None,
        typer.Option(
            "--profile",
            help="Profile id; defaults to pipeline.yaml default_profile.",
        ),
    ] = None,
) -> None:
    """Initialize a new agentic run from a goal string and/or goal file."""
    if goal is None and goal_file is None:
        typer.echo(
            "x  agentic init requires either a goal string or --goal-file <path>",
            err=True,
        )
        raise typer.Exit(code=2)

    args: list[str] = []
    if goal_file is not None:
        args += ["--goal-file", str(goal_file)]
    if goal is not None:
        args.append(goal)

    env: dict[str, str | None] = {}
    if profile is not None:
        env["PROFILE"] = profile

    invoke_without_run(
        ctx,
        name="init-agentic-run.sh",
        args=args,
        env=env,
        factory=_factory(),
    )
