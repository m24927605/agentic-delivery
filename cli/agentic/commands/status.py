"""`agentic status` — read the current run's manifest and print a summary.

Per spec §9.5, the `--json` form emits a `_schema: agentic.cli/v1` envelope.
"""

from __future__ import annotations

from pathlib import Path
from typing import Annotated, Any

import typer
from rich.console import Console
from rich.table import Table

from agentic.context import RepoNotFound, RunNotFound, resolve_repo, resolve_run_id
from agentic.manifest import Manifest, load_manifest
from agentic.ui import render
from agentic.ui.errors import AgenticError

app = typer.Typer(name="status", help="Show current run state, artifacts, and tasks.")
_console = Console()


_PENDING_ARTIFACT_STATUSES = {"approved", "rejected", "deferred"}


def _json_payload(manifest: Manifest, source: str) -> dict[str, Any]:
    pending = sum(
        1
        for a in manifest.artifacts
        if a.status not in _PENDING_ARTIFACT_STATUSES
    )
    return {
        "_schema": "agentic.cli/v1",
        "run": {
            "id": manifest.id,
            "mode": manifest.mode,
            "profile": manifest.profile,
            "state": manifest.state,
            "updated_at": manifest.updated_at,
            "source": source,
        },
        "artifacts": {
            "total": len(manifest.artifacts),
            "approved": manifest.count_artifacts(status="approved"),
            "pending": pending,
            "rejected": manifest.count_artifacts(status="rejected"),
            "deferred": manifest.count_artifacts(status="deferred"),
        },
        "tasks": [{"id": t.id, "status": t.status} for t in manifest.tasks],
    }


def _render_text(manifest: Manifest, source: str) -> None:
    typer.echo(f"Run:     {manifest.id}  ({manifest.mode} - {manifest.profile})")
    typer.echo(f"State:   {manifest.state}")
    typer.echo(f"Updated: {manifest.updated_at or '-'}")
    typer.echo(f"Source:  {source}")
    typer.echo("")

    if manifest.artifacts:
        table = Table(title="Artifacts", show_header=True)
        table.add_column("status")
        table.add_column("path")
        for a in manifest.artifacts:
            table.add_row(a.status, a.path)
        _console.print(table)

    if manifest.tasks:
        table = Table(title="Tasks", show_header=True)
        table.add_column("status")
        table.add_column("id")
        for t in manifest.tasks:
            table.add_row(t.status, t.id)
        _console.print(table)


_REPO_HINTS = (
    "agentic --repo <path> status",
    "export AGENTIC_HOME=<path>",
    "cd into a directory under an agentic-delivery repo",
)

_RUN_HINTS = (
    "agentic run list",
    "agentic run use <id>",
    "agentic --run-id <id> status",
)


@app.callback(invoke_without_command=True)
def status(
    ctx: typer.Context,
    run_id: Annotated[
        str | None,
        typer.Option("--run-id", help="Run id override for this invocation."),
    ] = None,
) -> None:
    """Show current run state, artifacts, and tasks."""
    obj: dict[str, Any] = ctx.obj or {}
    repo_flag: Path | None = obj.get("repo_flag")
    run_id_flag = run_id or obj.get("run_id_flag")
    json_mode = bool(obj.get("json"))

    try:
        repo = resolve_repo(repo_flag=repo_flag).path
    except RepoNotFound as e:
        raise AgenticError(
            category="no_repo",
            message=str(e),
            hints=list(_REPO_HINTS),
        ) from e

    try:
        run = resolve_run_id(repo=repo, flag=run_id_flag)
    except RunNotFound as e:
        raise AgenticError(
            category="no_run_context",
            message=str(e),
            hints=list(_RUN_HINTS),
        ) from e

    manifest = load_manifest(repo=repo, run_id=run.id)
    payload = _json_payload(manifest, run.source)
    render(payload, json_mode=json_mode, text_fn=lambda: _render_text(manifest, run.source))
