"""Repo discovery and CLI context resolution."""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

try:
    import tomllib  # type: ignore[import-not-found, import-untyped, unused-ignore]
except ModuleNotFoundError:  # 3.10
    import tomli as tomllib  # type: ignore[import-not-found, import-untyped, unused-ignore]

import yaml  # type: ignore[import-untyped]


RepoSource = Literal["--repo", "AGENTIC_HOME", "walk-up", "config-file"]


class RepoNotFound(Exception):
    """Raised when no agentic-delivery repo can be located."""


@dataclass(frozen=True)
class Repo:
    path: Path
    source: RepoSource


def _is_repo(path: Path) -> bool:
    return (path / "agentic" / "pipeline.yaml").is_file()


def _walk_up(start: Path) -> Path | None:
    current = start.resolve()
    while True:
        if _is_repo(current):
            return current
        parent = current.parent
        if parent == current:
            return None
        current = parent


def resolve_repo(repo_flag: Path | None = None) -> Repo:
    if repo_flag is not None:
        flag = Path(repo_flag).resolve()
        if not _is_repo(flag):
            raise RepoNotFound(f"--repo {flag} is not an agentic-delivery repo")
        return Repo(path=flag, source="--repo")

    env = os.environ.get("AGENTIC_HOME")
    if env:
        envp = Path(env).resolve()
        if not _is_repo(envp):
            raise RepoNotFound(f"AGENTIC_HOME={env} is not an agentic-delivery repo")
        return Repo(path=envp, source="AGENTIC_HOME")

    walked = _walk_up(Path.cwd())
    if walked is not None:
        return Repo(path=walked, source="walk-up")

    raise RepoNotFound(
        "no agentic-delivery repo found. Pass --repo, set AGENTIC_HOME, or cd into a repo."
    )


_VERSION_RE = re.compile(r"^v?(\d+)\.(\d+)(?:\.(\d+))?$")


class CompatError(Exception):
    """Raised when pipeline.yaml.version is outside the CLI's compat range."""


def _parse_version(raw: str) -> tuple[int, int, int]:
    m = _VERSION_RE.match(raw.strip())
    if not m:
        raise CompatError(f"unrecognised version string: {raw!r}")
    major, minor, patch = m.group(1), m.group(2), m.group(3) or "0"
    return int(major), int(minor), int(patch)


def _parse_range(spec: str) -> tuple[tuple[int, int, int] | None, tuple[int, int, int] | None]:
    lo: tuple[int, int, int] | None = None
    hi: tuple[int, int, int] | None = None
    for part in (p.strip() for p in spec.split(",")):
        if part.startswith(">="):
            lo = _parse_version(part[2:])
        elif part.startswith("<"):
            hi = _parse_version(part[1:])
    return lo, hi


def _compat_ranges_from_pyproject() -> list[str]:
    pyproject = Path(__file__).resolve().parents[1] / "pyproject.toml"
    if not pyproject.is_file():
        return []
    data = tomllib.loads(pyproject.read_text())
    tool = data.get("tool", {}).get("agentic", {})
    return list(tool.get("compatible_pipeline_versions", []))


def check_compat(*, repo: Path, enabled: bool = True) -> None:
    if not enabled:
        return
    pipeline = repo / "agentic" / "pipeline.yaml"
    data = yaml.safe_load(pipeline.read_text())
    actual_raw = data["pipeline"]["version"]
    actual = _parse_version(actual_raw)
    ranges = _compat_ranges_from_pyproject() or [">=0.0,<99.0"]
    for spec in ranges:
        lo, hi = _parse_range(spec)
        if lo is not None and actual < lo:
            continue
        if hi is not None and actual >= hi:
            continue
        return  # within at least one range
    raise CompatError(
        f"pipeline {actual_raw} is outside CLI compat: {ranges}. "
        f"Upgrade CLI or pass --no-compat-check."
    )
