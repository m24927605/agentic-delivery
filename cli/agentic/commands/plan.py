"""`agentic plan ...` subcommands (spec §5.2)."""

from __future__ import annotations

from pathlib import Path
from typing import Annotated

import typer

from agentic.commands._shell_helpers import (
    RunnerFactory,
    default_factory,
    invoke,
    invoke_no_run,
)
from agentic.shell import ScriptRunner

app = typer.Typer(name="plan", help="Planning artifacts (generate, review, approve).")
agency = typer.Typer(help="Agency review.")
app.add_typer(agency, name="agency")


# Re-exported so tests can monkeypatch ``plan._runner_factory`` to swap in a
# RecordingRunner. ``_factory()`` returns this attribute at call time so the
# monkeypatch takes effect even after the command has been registered.
def _runner_factory(repo: Path) -> ScriptRunner:
    return default_factory(repo)


def _factory() -> RunnerFactory:
    return _runner_factory


_SUGAR_VERBS = {
    "approve": "approved",
    "reject": "rejected",
    "defer": "deferred",
}
_VALID_STATUS = {
    "drafted",
    "reviewed",
    "changes_requested",
    "approved",
    "rejected",
    "deferred",
}


@app.command("generate")
def generate(
    ctx: typer.Context,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    """Generate planning artifacts for the current run."""
    invoke(
        ctx,
        name="generate-artifacts.sh",
        args=lambda rid: [rid],
        run_id_flag=run_id,
        factory=_factory(),
    )


@app.command("generate-agent")
def generate_agent(
    ctx: typer.Context,
    dry_run: Annotated[bool, typer.Option("--dry-run/--execute")] = True,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    """Run the artifact-generation agent (defaults to --dry-run)."""
    flag = "--dry-run" if dry_run else "--execute"
    invoke(
        ctx,
        name="run-artifact-generation-agent.sh",
        args=lambda rid: [flag, rid],
        run_id_flag=run_id,
        factory=_factory(),
    )


@app.command("review")
def review(
    ctx: typer.Context,
    artifact: Annotated[str, typer.Option("--artifact")],
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    """Review an artifact via the artifact review loop."""
    invoke(
        ctx,
        name="run-artifact-review-loop.sh",
        args=lambda rid: [rid, "--artifact", artifact],
        run_id_flag=run_id,
        factory=_factory(),
    )


@app.command("revisions")
def revisions(
    ctx: typer.Context,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    """Create revision tasks for artifacts requiring changes."""
    invoke(
        ctx,
        name="create-artifact-revision-tasks.sh",
        args=lambda rid: [rid],
        run_id_flag=run_id,
        factory=_factory(),
    )


@app.command("strategy-gate")
def strategy_gate(ctx: typer.Context) -> None:
    """Run the strategy gate check (no run context required)."""
    invoke_no_run(
        ctx,
        name="strategy-gate-check.sh",
        args=[],
        factory=_factory(),
    )


@app.command("state")
def state(
    ctx: typer.Context,
    new_state: str,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    """Update the run state."""
    invoke(
        ctx,
        name="update-run-state.sh",
        args=lambda rid: [rid, new_state],
        run_id_flag=run_id,
        factory=_factory(),
    )


@agency.command("review")
def agency_review(
    ctx: typer.Context,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    """Run the agency review across approved artifacts."""
    # run-agency-review.sh reads RUN_ID from env (set by resolve()), no positional.
    invoke(
        ctx,
        name="run-agency-review.sh",
        args=[],
        run_id_flag=run_id,
        factory=_factory(),
    )


@agency.command("summarize")
def agency_summarize(
    ctx: typer.Context,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    """Summarize agency review output for the current run."""
    invoke(
        ctx,
        name="summarize-agency-review.sh",
        args=lambda rid: [rid],
        run_id_flag=run_id,
        factory=_factory(),
    )


@app.command("artifact")
def artifact(
    ctx: typer.Context,
    path: str,
    status: str,
    reason: Annotated[str, typer.Option("--reason")],
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    """Update artifact status.

    Sugar verbs ``approve``/``reject``/``defer`` map to past-tense canonical
    statuses (``approved``/``rejected``/``deferred``). The literal canonical
    statuses ``drafted``/``reviewed``/``changes_requested`` pass through.
    """
    target = _SUGAR_VERBS.get(status, status)
    if target not in _VALID_STATUS:
        typer.echo(
            f"x  unknown status {status!r}; valid: {sorted(_VALID_STATUS | _SUGAR_VERBS.keys())}",
            err=True,
        )
        raise typer.Exit(code=2)
    extra: list[str] = []
    if ctx.obj and ctx.obj.get("actor"):
        extra += ["--actor", ctx.obj["actor"]]
    if ctx.obj and ctx.obj.get("role"):
        extra += ["--role", ctx.obj["role"]]
    invoke(
        ctx,
        name="update-artifact-status.sh",
        args=lambda rid: [rid, path, target, "--reason", reason, *extra],
        run_id_flag=run_id,
        factory=_factory(),
    )
