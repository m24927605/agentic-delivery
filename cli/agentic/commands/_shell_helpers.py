"""Shared helpers for command sub-apps that shell out to scripts/*.sh.

Both ``plan`` and the top-level ``init`` use these to resolve the
``(repo, run_id, env)`` triple and forward to ``ScriptRunner``. Tests inject a
fake runner via the ``factory`` parameter (see ``tests/_recording.py``).

Spec references:
- §9.3 — exit-code mapping (``64 + min(child_exit, 15)``).
- §9.4 — ``--actor``/``--role`` propagate to ``AIT_ACTOR``/``AIT_ACTOR_ROLE``.
"""

from __future__ import annotations

from pathlib import Path
from typing import Callable, Union

import typer

from agentic.context import RepoNotFound, RunNotFound, resolve_repo, resolve_run_id
from agentic.shell import ScriptError, ScriptRunner

RunnerFactory = Callable[[Path], ScriptRunner]
ArgsSpec = Union[list[str], Callable[[str], list[str]]]


def default_factory(repo: Path) -> ScriptRunner:
    return ScriptRunner(repo=repo)


def _resolve_repo_or_exit(ctx: typer.Context) -> Path:
    repo_flag = ctx.obj.get("repo_flag") if ctx.obj else None
    try:
        return resolve_repo(repo_flag=repo_flag).path
    except RepoNotFound as e:
        typer.echo(f"x  {e}", err=True)
        raise typer.Exit(code=6) from e


def resolve(
    ctx: typer.Context, run_id_flag: str | None
) -> tuple[Path, str, dict[str, str | None]]:
    """Resolve (repo, run id, env overrides) for a command needing run context.

    Raises ``RepoNotFound`` / ``RunNotFound`` — callers should prefer the
    higher-level ``invoke()`` that catches these and maps them to exit 6.
    """
    flag = run_id_flag or (ctx.obj.get("run_id_flag") if ctx.obj else None)
    repo = resolve_repo(repo_flag=ctx.obj.get("repo_flag") if ctx.obj else None).path
    run = resolve_run_id(repo=repo, flag=flag)
    env: dict[str, str | None] = {"RUN_ID": run.id}
    if ctx.obj:
        actor = ctx.obj.get("actor")
        role = ctx.obj.get("role")
        if actor:
            env["AIT_ACTOR"] = actor
        if role:
            env["AIT_ACTOR_ROLE"] = role
    return repo, run.id, env


def invoke(
    ctx: typer.Context,
    *,
    name: str,
    args: ArgsSpec,
    run_id_flag: str | None,
    factory: RunnerFactory = default_factory,
) -> None:
    """Resolve run context, build args, run the script, map exit code.

    ``args`` may be either a static ``list[str]`` or a callable
    ``Callable[[str], list[str]]`` that receives the resolved run id. The
    callable form lets commands inject the run id positionally without
    duplicating the resolution call outside the error-mapped block.
    """
    try:
        repo, run_id, env = resolve(ctx, run_id_flag)
    except (RepoNotFound, RunNotFound) as e:
        typer.echo(f"x  {e}", err=True)
        raise typer.Exit(code=6) from e
    final_args = args(run_id) if callable(args) else list(args)
    _execute(repo=repo, name=name, args=final_args, env=env, factory=factory)


def invoke_no_run(
    ctx: typer.Context,
    *,
    name: str,
    args: list[str],
    factory: RunnerFactory = default_factory,
) -> None:
    """For scripts that need a repo but no run context (e.g. strategy-gate-check)."""
    repo = _resolve_repo_or_exit(ctx)
    env: dict[str, str | None] = {}
    if ctx.obj:
        actor = ctx.obj.get("actor")
        role = ctx.obj.get("role")
        if actor:
            env["AIT_ACTOR"] = actor
        if role:
            env["AIT_ACTOR_ROLE"] = role
    _execute(repo=repo, name=name, args=list(args), env=env, factory=factory)


def invoke_without_run(
    ctx: typer.Context,
    *,
    name: str,
    args: list[str],
    env: dict[str, str | None] | None = None,
    factory: RunnerFactory = default_factory,
) -> None:
    """Variant used by ``init`` where no run context exists yet (run gets created)."""
    repo = _resolve_repo_or_exit(ctx)
    env_full: dict[str, str | None] = dict(env or {})
    if ctx.obj:
        actor = ctx.obj.get("actor")
        role = ctx.obj.get("role")
        if actor and "AIT_ACTOR" not in env_full:
            env_full["AIT_ACTOR"] = actor
        if role and "AIT_ACTOR_ROLE" not in env_full:
            env_full["AIT_ACTOR_ROLE"] = role
    _execute(repo=repo, name=name, args=args, env=env_full, factory=factory)


def _execute(
    *,
    repo: Path,
    name: str,
    args: list[str],
    env: dict[str, str | None],
    factory: RunnerFactory,
) -> None:
    runner = factory(repo)
    try:
        result = runner.run(name=name, args=args, env_overrides=env)
    except ScriptError as e:
        typer.echo(f"x  {e}", err=True)
        raise typer.Exit(code=1) from e
    if result.stdout:
        typer.echo(result.stdout, nl=False)
    if result.stderr:
        typer.echo(result.stderr, err=True, nl=False)
    if result.exit_code != 0:
        # Spec §9.3: forwarded script exit codes occupy 64..79.
        raise typer.Exit(code=64 + min(result.exit_code, 15))
