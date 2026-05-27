"""`agentic fixtures ...` subcommand (spec §5.5).

Wraps ``run-golden-fixtures.sh``. The script is repo-scoped and accepts no
arguments (it reads ``RUN_PREFIX`` from env), so the wrapper uses
``invoke_no_run`` and forwards no arguments.
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

app = typer.Typer(name="fixtures", help="Golden fixtures runner.")


def _runner_factory(repo: Path) -> ScriptRunner:
    """Indirection so tests can monkeypatch ``fixtures._runner_factory``."""
    return default_factory(repo)


def _factory() -> RunnerFactory:
    return _runner_factory


@app.command("run")
def run(ctx: typer.Context) -> None:
    """Run the golden fixtures regression suite."""
    invoke_no_run(
        ctx,
        name="run-golden-fixtures.sh",
        args=[],
        factory=_factory(),
    )
