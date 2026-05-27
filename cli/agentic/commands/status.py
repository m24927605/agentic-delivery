"""`agentic status` — read the current run's manifest and print a summary.

Per spec §9.5, the `--json` form emits a `_schema: agentic.cli/v1` envelope.
"""

from __future__ import annotations

import json as _json
from pathlib import Path
from typing import Annotated, Any

import typer
from rich.console import Console
from rich.table import Table

from agentic.context import RepoNotFound, RunNotFound, resolve_repo, resolve_run_id
from agentic.manifest import Manifest, load_manifest

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
        run = resolve_run_id(repo=repo, flag=run_id_flag)
    except (RepoNotFound, RunNotFound) as e:
        typer.echo(f"x  {e}", err=True)
        raise typer.Exit(code=6) from e

    manifest = load_manifest(repo=repo, run_id=run.id)

    if json_mode:
        typer.echo(_json.dumps(_json_payload(manifest, run.source), indent=2, sort_keys=False))
        return

    _render_text(manifest, run.source)
