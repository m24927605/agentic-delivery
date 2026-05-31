"""`agentic new <name>` — materialize a fresh agentic-delivery scaffold.

Reads the bundled scaffold tree (built into the wheel) and copies it into
``./<name>``, optionally initializing a git repo. Designed so that the
sequence ``pipx install agentic-delivery && agentic new my-project`` is
sufficient to get a validation-passing project on disk.

Spec: docs/superpowers/specs/2026-05-29-agentic-new-scaffold-bootstrap-design.md
"""
from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import Annotated

import typer

from agentic import __version__ as _cli_version
from agentic import scaffold as _scaffold_pkg
from agentic.ui.errors import AgenticError


# Files that get ``{{PROJECT_NAME}}`` / ``{{CLI_VERSION}}`` substitution at
# materialize time. Kept tiny on purpose — every entry here is a contract that
# the bundle file is utf-8 text and will round-trip through ``str.replace``.
_TEMPLATE_FILES: frozenset[str] = frozenset({"README.md"})


def _validate_name(name: str) -> None:
    if not name or "/" in name or ".." in name or "\x00" in name:
        raise AgenticError(
            category="misuse",
            message=f"name must be a single path segment, got {name!r}",
            hints=["use letters, digits, dashes, underscores"],
        )


def _check_target_state(target: Path, *, force: bool) -> None:
    """Pure predicate: validate that ``target`` is OK to materialize into.

    Does NOT create the directory — that's the materialize step's job. This
    keeps the check/act split clean (Task 7 review M-3).
    """
    if not target.exists():
        return  # _materialize_scaffold will create it
    entries = sorted(p.name for p in target.iterdir())
    if entries:
        sample = ", ".join(entries[:5])
        if len(entries) > 5:
            sample += f", ... ({len(entries) - 5} more)"
        raise AgenticError(
            category="scaffold_target_exists",
            message=(
                f"target exists and is non-empty: {target} "
                f"(contains: {sample})"
            ),
            hints=["choose a new <name>", "remove the existing files first"],
        )
    if not force:
        raise AgenticError(
            category="scaffold_target_exists",
            message=f"target {target} exists; rerun with `--force` to materialize into it",
            hints=["pass --force", "choose a new <name>"],
        )


def _materialize_scaffold(target: Path, *, project_name: str) -> None:
    """Copy the bundled scaffold tree into ``target``.

    - Resolves the bundle BEFORE creating ``target`` so a missing bundle
      doesn't leak an empty directory on disk (review I-1).
    - Walks every file from the bundle, preserving the source mode bits
      verbatim (``resource_mode`` already returns S_IMODE-masked bits).
    - Substitutes ``{{PROJECT_NAME}}`` / ``{{CLI_VERSION}}`` only in
      :data:`_TEMPLATE_FILES`. All other files are copied as raw bytes.
    """
    try:
        rels = _scaffold_pkg.iter_resource_paths()
    except _scaffold_pkg.ScaffoldBundleMissing as exc:
        raise AgenticError(
            category="scaffold_bundle_missing",
            message=str(exc),
            hints=["reinstall the CLI: pipx reinstall agentic-delivery"],
        ) from exc

    target.mkdir(parents=True, exist_ok=True)
    for rel in rels:
        dest = target / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        data = _scaffold_pkg.read_resource_bytes(rel)
        if rel in _TEMPLATE_FILES:
            text = data.decode("utf-8")
            text = text.replace("{{PROJECT_NAME}}", project_name)
            text = text.replace("{{CLI_VERSION}}", _cli_version)
            dest.write_text(text, encoding="utf-8")
        else:
            dest.write_bytes(data)
        # Preserve source mode verbatim (owner/group/world). ``resource_mode``
        # already returns S_IMODE-masked permission bits, so a literal chmod
        # round-trips the source's exact bits — not just coerce to 0o755.
        dest.chmod(_scaffold_pkg.resource_mode(rel))


def _clean_git_env() -> dict[str, str]:
    """Build an env for ``git`` subprocess calls.

    Passes through PATH and HOME so git can find itself and resolve global
    config, but strips any ``GIT_*`` variables that would override the ``-C
    target`` directory (e.g. ``GIT_DIR``, ``GIT_WORK_TREE``).
    """
    return {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}


def _git_init_and_commit(target: Path, *, cli_version: str) -> None:
    """Initialize ``target`` as a git repo with a single bootstrap commit.

    On any failure (``git`` not on PATH, or any of init/add/commit returning
    non-zero), raises :class:`AgenticError` with category
    ``scaffold_git_failed`` (exit 10) and actionable hints.
    """
    commit_msg = f"chore: bootstrap agentic-delivery scaffold (CLI v{cli_version})"
    base_env = _clean_git_env()
    commit_env = {
        **base_env,
        "GIT_AUTHOR_NAME": "agentic",
        "GIT_AUTHOR_EMAIL": "agentic@local",
        "GIT_COMMITTER_NAME": "agentic",
        "GIT_COMMITTER_EMAIL": "agentic@local",
    }
    try:
        subprocess.run(
            ["git", "-C", str(target), "init", "-b", "main"],
            check=True, capture_output=True, text=True, env=base_env,
        )
        subprocess.run(
            ["git", "-C", str(target), "add", "."],
            check=True, capture_output=True, text=True, env=base_env,
        )
        subprocess.run(
            ["git", "-C", str(target), "commit", "-m", commit_msg],
            check=True, capture_output=True, text=True, env=commit_env,
        )
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        detail = getattr(exc, "stderr", "") or str(exc)
        raise AgenticError(
            category="scaffold_git_failed",
            message=f"git initialization failed: {detail.strip()}",
            hints=[
                "rerun `agentic new <name> --no-git` to skip git",
                "or fix the git environment and `git init` manually in the target dir",
            ],
        ) from exc


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
    target = (path / name).resolve()
    _check_target_state(target, force=force)
    _materialize_scaffold(target, project_name=name)
    if not no_git:
        _git_init_and_commit(target, cli_version=_cli_version)
    # Task 10 adds the success banner here.
