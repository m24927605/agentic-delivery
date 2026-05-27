"""`agentic hermes ...` subcommands (spec §5.5).

Wraps the Hermes adapter scripts under a single namespace:
``validate-hermes-actions.sh``, ``run-hermes-action.sh``,
``hermes-memory-sync.sh``, ``hermes-scheduler-dry-run.sh``,
``hermes-gateway-dry-run.sh``. All commands run against the repo
without a run-id requirement: Hermes operations are system-level
(actions listing, memory sync, scheduler/gateway dry-runs) and the
``run`` action receives any per-call ``key=value`` args positionally.

Security: ``hermes run`` validates its argv before forwarding to
``run-hermes-action.sh``. Same discipline as ``raw.py`` (§11.5):

  1. Action name must match the snake_case Hermes convention.
  2. Per-call kv args must be preceded by a literal ``--`` boundary
     token. The Typer command uses the context-passthrough pattern
     (``allow_extra_args + ignore_unknown_options +
     allow_interspersed_args=False``) so the ``--`` is preserved in
     ``ctx.args`` and the wrapper can refuse callers who forget it.
  3. Each kv token must match ``key=value`` where ``key`` is a Python
     identifier; ``value`` is anything (subprocess.run uses
     ``shell=False``, so the value is exec argv, not a shell string).
  4. NUL and newline bytes are refused outright (log-injection,
     downstream argv-parser confusion).

Refusals exit with code 2 before the script is invoked.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Annotated

import typer

from agentic.commands._shell_helpers import (
    RunnerFactory,
    default_factory,
    invoke_no_run,
)
from agentic.shell import ScriptRunner

app = typer.Typer(name="hermes", help="Hermes adapter actions.")
actions = typer.Typer(help="Hermes actions list / validate.")
app.add_typer(actions, name="actions")

# Hermes action names are snake_case identifiers per agentic/hermes-actions.yaml.
_ACTION_NAME_RE = re.compile(r"^[a-z_][a-z0-9_]*$")
# kv args: key is a Python-style identifier; value is anything (NUL/newline
# refused separately). subprocess.run(..., shell=False) handles shell escaping.
_KV_ARG_RE = re.compile(r"^[a-zA-Z_][a-zA-Z0-9_]*=")


def _runner_factory(repo: Path) -> ScriptRunner:
    """Indirection so tests can monkeypatch ``hermes._runner_factory``."""
    return default_factory(repo)


def _factory() -> RunnerFactory:
    return _runner_factory


def _refuse(msg: str, code: int = 2) -> None:
    typer.echo(f"x  {msg}", err=True)
    raise typer.Exit(code=code)


@actions.command("list")
def actions_list(ctx: typer.Context) -> None:
    """List the actions exposed by the Hermes adapter."""
    invoke_no_run(
        ctx,
        name="validate-hermes-actions.sh",
        args=[],
        factory=_factory(),
    )


@actions.command("validate")
def actions_validate(ctx: typer.Context) -> None:
    """Validate the Hermes actions manifest."""
    invoke_no_run(
        ctx,
        name="validate-hermes-actions.sh",
        args=[],
        factory=_factory(),
    )


@app.command(
    "run",
    context_settings={
        # Context-passthrough pattern: collect all post-`action` tokens into
        # ``ctx.args`` verbatim (including a leading-dash kv after ``--``),
        # while preserving the literal ``--`` boundary so we can refuse
        # callers who forget it. ``allow_interspersed_args=False`` is what
        # keeps ``--`` from being silently consumed by Click.
        "allow_extra_args": True,
        "ignore_unknown_options": True,
        "allow_interspersed_args": False,
    },
)
def hermes_run(
    ctx: typer.Context,
    action: Annotated[str, typer.Argument(help="Hermes action name (snake_case).")],
) -> None:
    """Run a Hermes action — ``agentic hermes run <action> [-- k=v ...]``.

    Security boundary: argv into ``run-hermes-action.sh`` is validated here
    (see module docstring). Refusals exit with code 2 before the script runs.
    """
    if not _ACTION_NAME_RE.match(action):
        _refuse(
            f"refused action {action!r}: must match {_ACTION_NAME_RE.pattern}"
        )

    extras = list(ctx.args)
    if extras:
        if extras[0] != "--":
            _refuse(
                f"refused: kv args must come after literal '--' "
                f"(try: agentic hermes run {action} -- {' '.join(extras)})"
            )
        extras = extras[1:]

    for token in extras:
        if "\x00" in token or "\n" in token:
            _refuse("refused kv arg: contains NUL or newline byte")
        if not _KV_ARG_RE.match(token):
            _refuse(
                f"refused kv arg {token!r}: must match key=value where key is "
                f"a Python identifier"
            )

    invoke_no_run(
        ctx,
        name="run-hermes-action.sh",
        args=[action, *extras],
        factory=_factory(),
    )


@app.command("memory-sync")
def memory_sync(
    ctx: typer.Context,
    dry_run: Annotated[
        bool, typer.Option("--dry-run/--no-dry-run")
    ] = True,
) -> None:
    """Sync the Hermes memory store (default: dry-run)."""
    args = ["--dry-run"] if dry_run else []
    invoke_no_run(
        ctx,
        name="hermes-memory-sync.sh",
        args=args,
        factory=_factory(),
    )


@app.command("scheduler")
def scheduler(
    ctx: typer.Context,
    dry_run: Annotated[
        bool, typer.Option("--dry-run/--no-dry-run")
    ] = True,
) -> None:
    """Run the Hermes scheduler dry-run."""
    args = ["--dry-run"] if dry_run else []
    invoke_no_run(
        ctx,
        name="hermes-scheduler-dry-run.sh",
        args=args,
        factory=_factory(),
    )


@app.command("gateway")
def gateway(
    ctx: typer.Context,
    dry_run: Annotated[
        bool, typer.Option("--dry-run/--no-dry-run")
    ] = True,
) -> None:
    """Run the Hermes gateway dry-run."""
    args = ["--dry-run"] if dry_run else []
    invoke_no_run(
        ctx,
        name="hermes-gateway-dry-run.sh",
        args=args,
        factory=_factory(),
    )
