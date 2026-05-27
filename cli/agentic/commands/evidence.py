"""`agentic evidence ...` subcommands (spec §5.5).

Wraps ``record-validation-evidence.sh`` and ``redact-local-evidence.sh``.
Both scripts take their targets via their own args (``--slice``/``--round``
and positional paths respectively) — neither consumes the ``RUN_ID`` env.
Per the CLI-08 lesson the wrapper therefore uses ``invoke_no_run`` and does
not require a run-id. The ``--run-id`` option is accepted for forward
compatibility with the original spec, but is not forwarded to the script.
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

app = typer.Typer(name="evidence", help="Validation evidence record + redact.")


def _runner_factory(repo: Path) -> ScriptRunner:
    """Indirection so tests can monkeypatch ``evidence._runner_factory``."""
    return default_factory(repo)


def _factory() -> RunnerFactory:
    return _runner_factory


@app.command("record")
def record(
    ctx: typer.Context,
    run_id: Annotated[  # noqa: ARG001 — accepted for spec parity, not forwarded
        Optional[str],
        typer.Option("--run-id", help="Run id (accepted but not forwarded — script is slice-scoped)."),
    ] = None,
) -> None:
    """Record validation evidence — wraps ``record-validation-evidence.sh``."""
    invoke_no_run(
        ctx,
        name="record-validation-evidence.sh",
        args=[],
        factory=_factory(),
    )


@app.command("redact")
def redact(
    ctx: typer.Context,
    run_id: Annotated[  # noqa: ARG001 — accepted for spec parity, not forwarded
        Optional[str],
        typer.Option("--run-id", help="Run id (accepted but not forwarded — script takes paths)."),
    ] = None,
) -> None:
    """Redact local evidence files — wraps ``redact-local-evidence.sh``."""
    invoke_no_run(
        ctx,
        name="redact-local-evidence.sh",
        args=[],
        factory=_factory(),
    )
