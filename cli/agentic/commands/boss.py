"""`agentic boss ...` subcommands (boss-idea-response profile, spec §5.4).

Exposes 24 boss-idea pipeline scripts under a single `agentic boss` namespace
with sub-apps `research`, `memo`, `poc`, `decision`, `provider`, `validate`.
The `validate` sub-app routes by `<kind>` argument so the user types
`agentic boss validate research <md>` rather than a per-kind subcommand.
"""

from __future__ import annotations

from pathlib import Path
from typing import Annotated

import typer

from agentic.commands._shell_helpers import (
    RunnerFactory,
    default_factory,
    invoke,
    invoke_no_run,
    invoke_without_run,
)
from agentic.shell import ScriptRunner

app = typer.Typer(name="boss", help="Boss-idea-response profile.")

research = typer.Typer(help="Market research operations.")
app.add_typer(research, name="research")

memo = typer.Typer(help="Decision memo.")
app.add_typer(memo, name="memo")

poc = typer.Typer(help="POC / MVP planning.")
app.add_typer(poc, name="poc")

decision = typer.Typer(help="Decision recording.")
app.add_typer(decision, name="decision")

provider = typer.Typer(help="Provider health + fallback advisory.")
app.add_typer(provider, name="provider")


def _runner_factory(repo: Path) -> ScriptRunner:
    """Indirection so tests can monkeypatch ``boss._runner_factory``."""
    return default_factory(repo)


def _factory() -> RunnerFactory:
    return _runner_factory


@app.command("init")
def boss_init(
    ctx: typer.Context,
    idea_file: Annotated[str, typer.Argument(help="Path to the boss-idea markdown file.")],
    dry_run: Annotated[bool, typer.Option("--dry-run")] = False,
) -> None:
    """Initialize a boss-idea-response run from an idea markdown file.

    The underlying ``init-boss-idea-run.sh`` script CREATES the run from the
    idea file, so no pre-existing run context is required (and forcing one
    would make a fresh repo unreachable).
    """
    args: list[str] = []
    if dry_run:
        args.append("--dry-run")
    args.append(idea_file)
    invoke_without_run(
        ctx,
        name="init-boss-idea-run.sh",
        args=args,
        factory=_factory(),
    )


@app.command("score")
def boss_score(
    ctx: typer.Context,
    scorecard: Annotated[
        str,
        typer.Option("--scorecard", help="Path to the boss-idea scorecard YAML."),
    ],
    dry_run: Annotated[bool, typer.Option("--dry-run")] = False,
) -> None:
    """Score boss-idea feasibility from a scorecard YAML.

    ``score-boss-idea-feasibility.sh`` takes ``[--dry-run] <scorecard.yaml>``
    as its positional, not a run id.
    """
    args: list[str] = []
    if dry_run:
        args.append("--dry-run")
    args.append(scorecard)
    invoke_no_run(
        ctx,
        name="score-boss-idea-feasibility.sh",
        args=args,
        factory=_factory(),
    )


@research.command("collect")
def research_collect(
    ctx: typer.Context,
    search_results: Annotated[str, typer.Option("--search-results")],
    output: Annotated[str, typer.Option("--output")],
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    """Collect boss-idea market research from a search-results fixture/file."""
    invoke(
        ctx,
        name="collect-boss-idea-research.sh",
        args=lambda rid: [rid, "--search-results", search_results, "--output", output],
        run_id_flag=run_id,
        factory=_factory(),
    )


@research.command("crawl")
def research_crawl(
    ctx: typer.Context,
    from_query_pack: Annotated[bool, typer.Option("--from-query-pack/--no-from-query-pack")] = True,
    search_provider: Annotated[str, typer.Option("--search-provider")] = "fixture",
    output: Annotated[str | None, typer.Option("--output")] = None,
    force: Annotated[bool, typer.Option("--force")] = False,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    """Crawl the live market via the configured search provider."""
    def _args(rid: str) -> list[str]:
        out: list[str] = []
        if force:
            out.append("--force")
        out.append(rid)
        if from_query_pack:
            out.append("--from-query-pack")
        out.extend(["--search-provider", search_provider])
        if output:
            out.extend(["--output", output])
        return out

    invoke(
        ctx,
        name="crawl-boss-idea-market.sh",
        args=_args,
        run_id_flag=run_id,
        factory=_factory(),
    )


@research.command("brief")
def research_brief(
    ctx: typer.Context,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    """Generate the boss-idea competitor brief."""
    invoke(
        ctx,
        name="generate-boss-idea-competitor-brief.sh",
        args=lambda rid: [rid],
        run_id_flag=run_id,
        factory=_factory(),
    )


@research.command("preflight")
def research_preflight(ctx: typer.Context) -> None:
    """Run the SearXNG preflight check (no run context required).

    ``boss-idea-searxng-preflight.sh`` reads BOSS_IDEA_SEARCH_SEARXNG_* env
    vars; it does not consume RUN_ID. Resolving a run here would surface a
    spurious exit-6 in repos with no runs.
    """
    invoke_no_run(
        ctx,
        name="boss-idea-searxng-preflight.sh",
        args=[],
        factory=_factory(),
    )


@research.command("live-smoke")
def research_live_smoke(
    ctx: typer.Context,
    live: Annotated[bool, typer.Option("--live/--no-live")] = True,
    force: Annotated[bool, typer.Option("--force/--no-force")] = True,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    """Run the boss-idea live-smoke flow."""
    def _args(rid: str) -> list[str]:
        out: list[str] = []
        if live:
            out.append("--live")
        if force:
            out.append("--force")
        out.append(rid)
        return out

    invoke(
        ctx,
        name="run-boss-idea-live-smoke.sh",
        args=_args,
        run_id_flag=run_id,
        factory=_factory(),
    )


@memo.command("generate")
def memo_generate(
    ctx: typer.Context,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    """Generate the boss-idea decision memo."""
    invoke(
        ctx,
        name="generate-boss-decision-memo.sh",
        args=lambda rid: [rid],
        run_id_flag=run_id,
        factory=_factory(),
    )


@poc.command("plan")
def poc_plan(
    ctx: typer.Context,
    work_type: Annotated[
        str,
        typer.Option(
            "--work-type",
            help="Work-type enum forwarded to plan-boss-idea-poc-mvp.sh (poc or mvp).",
        ),
    ] = "poc",
) -> None:
    """Plan the boss-idea POC / MVP for the given work type.

    ``plan-boss-idea-poc-mvp.sh`` takes ``[poc|mvp]`` as its positional, not
    a run id. The script itself validates the value against the schema's
    ``allowed_work_types``; the CLI keeps the surface narrow to {poc, mvp}.
    """
    if work_type not in {"poc", "mvp"}:
        typer.echo(
            f"x  --work-type must be 'poc' or 'mvp', got {work_type!r}",
            err=True,
        )
        raise typer.Exit(code=2)
    invoke_no_run(
        ctx,
        name="plan-boss-idea-poc-mvp.sh",
        args=[work_type],
        factory=_factory(),
    )


@decision.command("record")
def decision_record(
    ctx: typer.Context,
    decision_yaml: Annotated[str, typer.Argument(help="Path to the decision YAML to record.")],
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    """Record the boss-idea decision outcome from a decision YAML."""
    invoke(
        ctx,
        name="record-boss-idea-decision.sh",
        args=lambda rid: [decision_yaml, "--run-id", rid],
        run_id_flag=run_id,
        factory=_factory(),
    )


@provider.command("health")
def provider_health(
    ctx: typer.Context,
    output: Annotated[str | None, typer.Option("--output")] = None,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    """Summarise boss-idea provider health into an artifact."""
    def _args(rid: str) -> list[str]:
        out: list[str] = []
        if output:
            out.extend(["--output", output])
        out.append(rid)
        return out

    invoke(
        ctx,
        name="summarize-boss-idea-provider-health.sh",
        args=_args,
        run_id_flag=run_id,
        factory=_factory(),
    )


@provider.command("fallback")
def provider_fallback(
    ctx: typer.Context,
    health_input: Annotated[str, typer.Argument(help="Path to the provider-health summary input.")],
    output: Annotated[str | None, typer.Option("--output")] = None,
) -> None:
    """Recommend a boss-idea provider fallback advisory.

    ``recommend-boss-idea-provider-fallback.sh`` takes
    ``--output <advisory.yaml> <provider-health.yaml>`` only; no run id.
    """
    args: list[str] = []
    if output:
        args.extend(["--output", output])
    args.append(health_input)
    invoke_no_run(
        ctx,
        name="recommend-boss-idea-provider-fallback.sh",
        args=args,
        factory=_factory(),
    )


# `boss validate <kind> <target> [<second>]` — dispatch table for the 12 validators.
_VALIDATE_MAP: dict[str, str] = {
    "research": "validate-boss-idea-research.sh",
    "competitor": "validate-boss-idea-competitor-brief.sh",
    "run-competitor": "validate-boss-idea-run-competitor-brief.sh",
    "crawl": "validate-boss-idea-crawl-log.sh",
    "quality": "validate-boss-idea-market-discovery-quality.sh",
    "poc-mvp": "validate-boss-idea-poc-mvp.sh",
    "metrics": "validate-boss-idea-success-metrics.sh",
    "memo": "validate-boss-decision-memo.sh",
    "decision": "validate-boss-idea-decision.sh",
    "provider-health": "validate-boss-idea-provider-health.sh",
    "provider-events": "validate-boss-idea-provider-health-events.sh",
    "fallback-advisory": "validate-boss-idea-provider-fallback-advisory.sh",
}


@app.command("validate")
def validate_dispatch(
    ctx: typer.Context,
    kind: Annotated[
        str | None,
        typer.Argument(help=f"Validator kind. One of: {', '.join(sorted(_VALIDATE_MAP))}"),
    ] = None,
    target: Annotated[
        str | None,
        typer.Argument(help="Primary artifact path passed to the validator."),
    ] = None,
    second: Annotated[
        str | None,
        typer.Argument(help="Optional second positional arg (used by a few validators)."),
    ] = None,
) -> None:
    """Dispatch `boss validate <kind> <target> [<second>]` to the underlying script.

    Consolidates the 12 boss-idea validators (11 ``validate-boss-idea-*`` plus
    ``validate-boss-decision-memo``) under a single command so callers type
    ``agentic boss validate research <md>`` instead of a per-kind subcommand.

    Validators take artifact paths as positionals (not a run id), so this
    dispatcher uses ``invoke_no_run`` — a user can lint an artifact without
    needing a run to exist.
    """
    if kind is None:
        typer.echo(
            "usage: agentic boss validate <kind> <target> [<second>]\n"
            f"known kinds: {sorted(_VALIDATE_MAP)}",
            err=True,
        )
        raise typer.Exit(code=2)
    script = _VALIDATE_MAP.get(kind)
    if script is None:
        typer.echo(
            f"x  unknown validate kind {kind!r}; known: {sorted(_VALIDATE_MAP)}",
            err=True,
        )
        raise typer.Exit(code=2)
    if target is None:
        typer.echo(
            f"x  validate {kind} requires a target artifact path",
            err=True,
        )
        raise typer.Exit(code=2)
    args: list[str] = [a for a in (target, second) if a is not None]
    invoke_no_run(
        ctx,
        name=script,
        args=args,
        factory=_factory(),
    )
