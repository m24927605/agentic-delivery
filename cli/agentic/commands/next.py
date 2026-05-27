"""`agentic next` — suggest the next command based on manifest state.

Read-only. The command never invokes the suggestion, executes the pipeline,
or modifies the repository. Per spec §9.5, the ``--json`` form emits a
``_schema: agentic.cli/v1`` envelope identical in shape to ``agentic status``.
"""

from __future__ import annotations

import json as _json
from pathlib import Path
from typing import Annotated, Any

import typer

from agentic.context import RepoNotFound, RunNotFound, resolve_repo, resolve_run_id
from agentic.manifest import Manifest, load_manifest
from agentic.state_engine.engine import Decision, evaluate, load_rules

app = typer.Typer(
    name="next",
    help="Suggest the next command for the current run. Never executes.",
)


def _json_payload(manifest: Manifest, decision: Decision, source: str) -> dict[str, Any]:
    return {
        "_schema": "agentic.cli/v1",
        "run": {
            "id": manifest.id,
            "mode": manifest.mode,
            "profile": manifest.profile,
            "state": manifest.state,
            "source": source,
        },
        "next": {
            "rule_id": decision.rule_id,
            "suggest": decision.suggest,
            "reason": decision.reason,
        },
    }


def _render_text(manifest: Manifest, decision: Decision) -> None:
    typer.echo(f"Run:    {manifest.id}  ({manifest.mode})")
    typer.echo(f"State:  {manifest.state}")
    typer.echo("")
    typer.echo(f"Next:   {decision.suggest}")
    if decision.reason:
        typer.echo(f"Why:    {decision.reason}")
    typer.echo(f"Rule:   {decision.rule_id}")


@app.callback(invoke_without_command=True)
def next_cmd(
    ctx: typer.Context,
    run_id: Annotated[
        str | None,
        typer.Option("--run-id", help="Run id override for this invocation."),
    ] = None,
) -> None:
    """Suggest the next command based on manifest state. Never executes."""
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
    decision = evaluate(load_rules(), manifest)

    if json_mode:
        typer.echo(
            _json.dumps(
                _json_payload(manifest, decision, run.source),
                indent=2,
                sort_keys=False,
            )
        )
        return

    _render_text(manifest, decision)
