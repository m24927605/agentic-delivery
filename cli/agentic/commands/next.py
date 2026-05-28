"""`agentic next` — suggest the next command based on manifest state.

Read-only. The command never invokes the suggestion, executes the pipeline,
or modifies the repository. Per spec §9.5, the ``--json`` form emits a
``_schema: agentic.cli/v1`` envelope identical in shape to ``agentic status``.
"""

from __future__ import annotations

from pathlib import Path
from typing import Annotated, Any

import typer

from agentic.context import RepoNotFound, RunNotFound, resolve_repo, resolve_run_id
from agentic.manifest import Manifest, load_manifest
from agentic.state_engine.engine import Decision, evaluate, load_rules
from agentic.ui import render
from agentic.ui.errors import AgenticError

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


_REPO_HINTS = (
    "agentic --repo <path> next",
    "export AGENTIC_HOME=<path>",
    "cd into a directory under an agentic-delivery repo",
)

_RUN_HINTS = (
    "agentic run list",
    "agentic run use <id>",
    "agentic --run-id <id> next",
)


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
    decision = evaluate(load_rules(), manifest)

    payload = _json_payload(manifest, decision, run.source)
    render(payload, json_mode=json_mode, text_fn=lambda: _render_text(manifest, decision))
