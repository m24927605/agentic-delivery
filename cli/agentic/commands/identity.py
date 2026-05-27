"""`agentic identity ...` subcommands (spec §5.5).

Wraps the identity policy + authorization scripts:
``validate-identity-policy.sh`` and ``authorize-agentic-action.sh``.
Both run at repo scope; no run-id required.
"""

from __future__ import annotations

from pathlib import Path
from typing import Annotated

import typer

from agentic.commands._shell_helpers import (
    RunnerFactory,
    default_factory,
    invoke_no_run,
)
from agentic.shell import ScriptRunner

app = typer.Typer(name="identity", help="Identity policy + authorization.")


def _runner_factory(repo: Path) -> ScriptRunner:
    """Indirection so tests can monkeypatch ``identity._runner_factory``."""
    return default_factory(repo)


def _factory() -> RunnerFactory:
    return _runner_factory


@app.command("validate")
def validate(ctx: typer.Context) -> None:
    """Validate the agentic identity policy."""
    invoke_no_run(
        ctx,
        name="validate-identity-policy.sh",
        args=[],
        factory=_factory(),
    )


@app.command("authorize")
def authorize(
    ctx: typer.Context,
    action: Annotated[str, typer.Option("--action", help="Action id to authorize.")],
) -> None:
    """Authorize a specific agentic action against the identity policy."""
    invoke_no_run(
        ctx,
        name="authorize-agentic-action.sh",
        args=["--action", action],
        factory=_factory(),
    )
