"""`agentic manifest ...` subcommands (spec §5.5).

Module is named ``manifest_cmd`` to avoid shadowing ``agentic/manifest.py``.

Wraps three scripts, all of which take their target via positional/flag
args (not ``RUN_ID`` env), so the wrappers use ``invoke_no_run``:
- ``validate-manifest-schema.sh [--all|<run-id>|<manifest-path>]``
- ``validate-artifact-templates.sh <planning-run-id> [--artifact <path>]``
- ``privacy-scan-tracked.sh [--cached]``
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

app = typer.Typer(name="manifest", help="Manifest validators + privacy scan.")


def _runner_factory(repo: Path) -> ScriptRunner:
    """Indirection so tests can monkeypatch ``manifest_cmd._runner_factory``."""
    return default_factory(repo)


def _factory() -> RunnerFactory:
    return _runner_factory


@app.command("validate")
def validate(
    ctx: typer.Context,
    all_runs: Annotated[
        bool, typer.Option("--all", help="Validate every run's manifest.")
    ] = False,
    run_id: Annotated[
        Optional[str],
        typer.Option("--run-id", help="Validate a single run id (mutually exclusive with --all)."),
    ] = None,
) -> None:
    """Validate one or all run manifests against the schema."""
    if all_runs and run_id:
        typer.echo("x  --all and --run-id are mutually exclusive", err=True)
        raise typer.Exit(code=2)
    args: list[str] = []
    if all_runs:
        args = ["--all"]
    elif run_id:
        args = [run_id]
    invoke_no_run(
        ctx,
        name="validate-manifest-schema.sh",
        args=args,
        factory=_factory(),
    )


@app.command("templates")
def templates(
    ctx: typer.Context,
    run_id: Annotated[str, typer.Option("--run-id", help="Planning run id to validate.")],
) -> None:
    """Validate artifact templates for a planning run."""
    invoke_no_run(
        ctx,
        name="validate-artifact-templates.sh",
        args=[run_id],
        factory=_factory(),
    )


@app.command("scan")
def scan(ctx: typer.Context) -> None:
    """Scan tracked files for public-safety / secret patterns."""
    invoke_no_run(
        ctx,
        name="privacy-scan-tracked.sh",
        args=[],
        factory=_factory(),
    )
