"""`agentic raw <script.sh> [-- args...]` — escape hatch to any scripts/*.sh.

Spec §11.5 — four mandatory pre-exec checks (all happen here, not in
``ScriptRunner``, so we can refuse before any process is spawned):

  1. Name regex ``^[a-z0-9][a-z0-9-]*\\.sh$`` — rejects leading dashes (argv
     parsing trap), absolute paths, ``..`` traversal, non-``.sh`` strings.
  2. Realpath containment — ``os.path.realpath(scripts/<name>)`` must live
     under ``os.path.realpath(scripts/)``. Also refuses symlink-to-symlink
     chains so the exec path is auditable as either a regular file or a
     single-hop link.
  3. Argument delimiter — extras are forwarded to the script ONLY after the
     literal ``--``. Without it, Click parses unknown options on the raw
     command itself and rejects them, preventing accidental CLI-flag leakage
     into script argv. This is the default Click behaviour; we intentionally
     do NOT enable ``allow_extra_args`` / ``ignore_unknown_options``.
  4. TOCTOU closure — the resolved ``realpath`` is the exact path passed to
     ``subprocess.run``. We do not re-derive the path inside ``ScriptRunner``;
     that would reopen the symlink-swap window between validation and exec.
"""

from __future__ import annotations

import os
import re
from pathlib import Path
from typing import Annotated, NoReturn

import typer

from agentic.commands._shell_helpers import default_factory
from agentic.context import RepoNotFound, resolve_repo
from agentic.shell import ScriptError, ScriptRunner
from agentic.ui.errors import AgenticError

app = typer.Typer()

_SCRIPT_NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]*\.sh$")

# Repo / run hints reused by the raw refusals so the structured error envelope
# matches the rest of the CLI (`agentic plan` / `agentic init` / etc.).
_RAW_REFUSE_HINTS = (
    "agentic raw <script>.sh -- <args>",
    "see agentic --help for first-class wrappers",
)


def _runner_factory(repo: Path) -> ScriptRunner:
    """Indirection so tests can monkeypatch in a RecordingRunner."""
    return default_factory(repo)


def _refuse(msg: str, *, category: str = "misuse", exit_code: int | None = None) -> NoReturn:
    """Raise a structured refusal — never returns."""
    raise AgenticError(
        category=category,
        message=msg,
        hints=list(_RAW_REFUSE_HINTS),
        exit_code=exit_code,
    )


@app.callback(invoke_without_command=True)
def raw(
    ctx: typer.Context,
    script: Annotated[
        str,
        typer.Argument(help="Script under scripts/ matching ^[a-z0-9][a-z0-9-]*\\.sh$."),
    ],
    args: Annotated[
        list[str] | None,
        typer.Argument(
            help="Args forwarded to the script. Place after '--' for any flag-shaped args."
        ),
    ] = None,
) -> None:
    """Forward to scripts/<script>. Use '--' before any flag-shaped argument."""
    # Check 1 — name regex.
    if not _SCRIPT_NAME_RE.match(script):
        _refuse(
            f"refused script name {script!r}: must match {_SCRIPT_NAME_RE.pattern}"
        )

    # Resolve repo.
    try:
        repo = resolve_repo(repo_flag=ctx.obj.get("repo_flag") if ctx.obj else None).path
    except RepoNotFound as e:
        raise AgenticError(
            category="no_repo",
            message=str(e),
            hints=[
                "agentic --repo <path> raw <script>.sh",
                "export AGENTIC_HOME=<path>",
                "cd into a directory under an agentic-delivery repo",
            ],
        ) from e

    # Check 2 — realpath containment.
    scripts_dir = repo / "scripts"
    try:
        scripts_realpath = os.path.realpath(scripts_dir)
    except OSError as e:
        _refuse(f"cannot resolve scripts/ under {repo}: {e}")

    candidate = scripts_dir / script
    try:
        resolved = os.path.realpath(candidate, strict=True)
    except OSError as e:
        # strict=True raises for missing files AND symlink loops (ELOOP).
        _refuse(f"refused {script!r}: {e}")

    try:
        common = os.path.commonpath([resolved, scripts_realpath])
    except ValueError as e:
        # Different drives on Windows, or one path empty — treat as refusal.
        _refuse(f"refused {script!r}: {e}")

    if common != scripts_realpath:
        _refuse(f"refused {script!r}: resolves outside scripts/ ({resolved})")

    # Spec §11.5: refuse symlink-to-symlink. A direct symlink to a regular
    # file is fine; chained symlinks add audit indirection we do not allow.
    if candidate.is_symlink():
        target = os.readlink(candidate)
        first_hop = Path(target) if os.path.isabs(target) else (scripts_dir / target)
        if first_hop.is_symlink():
            _refuse(f"refused {script!r}: symlink target is itself a symlink")

    resolved_path = Path(resolved)
    if not resolved_path.is_file():
        # Realpath landed on a directory, socket, fifo, etc.
        _refuse(
            f"refused {script!r}: not a regular file",
            category="generic",
        )

    # Check 3 — '--' boundary. Click's variadic positional happily eats
    # unknown options and the literal ``--`` itself, so we enforce the boundary
    # by hand: any extras at all must begin with ``--``. This refuses
    # ``agentic raw foo.sh --verbose`` (flag without delimiter) and
    # ``agentic raw foo.sh hello`` (positional without delimiter), while
    # accepting ``agentic raw foo.sh -- --verbose hello``.
    extras = list(args or [])
    if extras:
        if extras[0] != "--":
            _refuse(
                f"refused: extras must come after literal '--' "
                f"(try: agentic raw {script} -- {' '.join(extras)})"
            )
        extras = extras[1:]

    # Check 4 — exec the resolved path. ScriptRunner accepts ``script_path``
    # to skip its internal ``repo/scripts/name`` reconstruction, closing the
    # TOCTOU window between validation and exec.
    runner = _runner_factory(repo)
    try:
        result = runner.run(
            name=script,
            args=extras,
            env_overrides={},
            script_path=resolved_path,
        )
    except ScriptError as e:
        raise AgenticError(
            category="generic",
            message=str(e),
            hints=[f"verify scripts/{script} exists and matches the name regex"],
        ) from e

    if result.stdout:
        typer.echo(result.stdout, nl=False)
    if result.stderr:
        typer.echo(result.stderr, err=True, nl=False)
    if result.exit_code != 0:
        # Spec §9.3: forwarded script exits occupy 64..79.
        raise AgenticError(
            category="script_failed",
            message=f"scripts/{script} exited {result.exit_code}",
            hints=[f"agentic raw {script} -- ...  # rerun with -vv for child stderr"],
            exit_code=64 + min(result.exit_code, 15),
        )
