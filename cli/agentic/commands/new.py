"""`agentic new <name>` — materialize a fresh agentic-delivery scaffold.

Reads the bundled scaffold tree (built into the wheel) and copies it into
``./<name>``, optionally initializing a git repo. Designed so that the
sequence ``pipx install agentic-delivery && agentic new my-project`` is
sufficient to get a validation-passing project on disk.

Spec: docs/superpowers/specs/2026-05-29-agentic-new-scaffold-bootstrap-design.md
"""
from __future__ import annotations

from pathlib import Path
from typing import Annotated

import typer

from agentic.ui.errors import AgenticError


def _validate_name(name: str) -> None:
    if not name or "/" in name or ".." in name or "\x00" in name:
        raise AgenticError(
            category="misuse",
            message=f"name must be a single path segment, got {name!r}",
            hints=["use letters, digits, dashes, underscores"],
        )


def new_command(
    name: Annotated[str, typer.Argument(help="Project directory name")],
    path: Annotated[
        Path,
        typer.Option("--path", "-p", help="Parent directory (default: cwd)"),
    ] = Path("."),
    no_git: Annotated[bool, typer.Option("--no-git", help="Skip git init")] = False,
    force: Annotated[
        bool, typer.Option("--force", help="Allow target dir if it exists and is empty")
    ] = False,
) -> None:
    """Scaffold a fresh agentic-delivery project at ``<path>/<name>``."""
    _validate_name(name)
    # Task 7 replaces this body with target-state branching; Tasks 8-10 fill in
    # the rest (copy, git, banner). The AgenticError here ensures that even a
    # mid-build branch keeps the CLI's structured-error contract.
    raise AgenticError(
        category="generic",
        message="agentic new is not yet implemented on this revision",
        hints=["check out a revision with Tasks 6-10 landed"],
    )
