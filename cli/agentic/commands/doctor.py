"""`agentic doctor` — batch validators with aggregated structured exit.

Runs four repo-level validators in sequence, captures each result, and:

- prints a Rich summary table (text mode) or an ``agentic.cli/v1`` envelope
  with ``checks: [...]`` (json mode) to stdout;
- exits 0 only when every check returned 0;
- otherwise raises ``AgenticError(validation_failed)`` (exit 3) so callers
  see the same structured stderr the rest of the CLI uses.

The checks themselves invoke the same scripts the individual subcommands
do — ``agentic validate system``, ``agentic manifest validate --all``,
``agentic manifest scan``, ``agentic identity validate`` — so doctor is a
batched convenience over capabilities the user already has.

Tests monkeypatch ``doctor._runner_factory`` with a ``RecordingRunner`` so
no subprocesses are spawned.
"""

from __future__ import annotations

import json as _json
from dataclasses import dataclass
from pathlib import Path

import typer
from rich.console import Console
from rich.table import Table

from agentic.commands._shell_helpers import default_factory
from agentic.context import RepoNotFound, resolve_repo
from agentic.shell import ScriptError, ScriptRunner
from agentic.ui.errors import AgenticError

app = typer.Typer(name="doctor", help="Run all validators and report aggregated status.")

# Per-process console; tests use CliRunner so this writes to the captured stdout.
_console = Console()


def _runner_factory(repo: Path) -> ScriptRunner:
    """Indirection so tests can monkeypatch ``doctor._runner_factory``."""
    return default_factory(repo)


@dataclass
class _Check:
    name: str
    script: str
    args: tuple[str, ...]
    status: str = "pending"
    exit_code: int = -1
    stderr: str = ""


# Order matters: report rows follow this sequence. The scripts run repo-scoped
# (no RUN_ID), matching their individual subcommand wrappers.
_DOCTOR_CHECKS: tuple[_Check, ...] = (
    _Check(name="system", script="validate-agentic-system.sh", args=()),
    _Check(name="manifest", script="validate-manifest-schema.sh", args=("--all",)),
    _Check(name="privacy", script="privacy-scan-tracked.sh", args=()),
    _Check(name="identity", script="validate-identity-policy.sh", args=()),
)


@app.callback(invoke_without_command=True)
def doctor(ctx: typer.Context) -> None:
    """Run all validators and report aggregated status."""
    repo_flag = ctx.obj.get("repo_flag") if ctx.obj else None
    try:
        repo = resolve_repo(repo_flag=repo_flag).path
    except RepoNotFound as e:
        raise AgenticError(
            category="no_repo",
            message=str(e),
            hints=[
                "agentic --repo <path> doctor",
                "export AGENTIC_HOME=<path>",
                "cd into a directory under an agentic-delivery repo",
            ],
        ) from e

    runner = _runner_factory(repo)
    # Fresh copies so command invocations are idempotent across tests.
    checks: list[_Check] = [
        _Check(name=c.name, script=c.script, args=tuple(c.args))
        for c in _DOCTOR_CHECKS
    ]

    for c in checks:
        try:
            r = runner.run(name=c.script, args=list(c.args), env_overrides={})
        except ScriptError as e:
            # Missing script / invalid name — record but keep going so the
            # operator gets the full status table.
            c.status = "ERROR"
            c.stderr = str(e)
            continue
        c.exit_code = r.exit_code
        c.status = "PASS" if r.exit_code == 0 else "FAIL"
        c.stderr = r.stderr

    json_mode = bool(ctx.obj.get("json")) if ctx.obj else False
    if json_mode:
        typer.echo(
            _json.dumps(
                {
                    "_schema": "agentic.cli/v1",
                    "checks": [
                        {
                            "name": c.name,
                            "script": c.script,
                            "status": c.status,
                            "exit_code": c.exit_code,
                        }
                        for c in checks
                    ],
                },
                indent=2,
            )
        )
    else:
        table = Table(show_header=True, title="agentic doctor")
        table.add_column("status")
        table.add_column("name")
        table.add_column("script")
        for c in checks:
            table.add_row(c.status, c.name, c.script)
        _console.print(table)

    failing = [c for c in checks if c.status != "PASS"]
    if failing:
        raise AgenticError(
            category="validation_failed",
            message=f"{len(failing)}/{len(checks)} doctor checks failed",
            hints=[f"agentic raw {c.script}  # rerun individually" for c in failing],
        )
