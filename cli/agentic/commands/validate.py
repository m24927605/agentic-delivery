"""`agentic validate ...` subcommand (spec §5.5).

Wraps ``validate-agentic-system.sh`` — repo-scoped, reads no ``RUN_ID``.
"""

from __future__ import annotations

from pathlib import Path

import typer

from agentic.commands._shell_helpers import (
    RunnerFactory,
    default_factory,
    invoke_no_run,
)
from agentic.shell import ScriptRunner

app = typer.Typer(name="validate", help="Top-level validators.")


def _runner_factory(repo: Path) -> ScriptRunner:
    """Indirection so tests can monkeypatch ``validate._runner_factory``."""
    return default_factory(repo)


def _factory() -> RunnerFactory:
    return _runner_factory


@app.command("system")
def system(ctx: typer.Context) -> None:
    """Run the full agentic-system structural validator."""
    invoke_no_run(
        ctx,
        name="validate-agentic-system.sh",
        args=[],
        factory=_factory(),
    )
