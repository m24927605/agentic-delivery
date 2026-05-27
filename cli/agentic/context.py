"""Repo discovery and CLI context resolution."""

from __future__ import annotations

import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

import yaml  # type: ignore[import-untyped]

from agentic import COMPATIBLE_PIPELINE_VERSIONS


RepoSource = Literal["--repo", "AGENTIC_HOME", "walk-up", "config-file"]


class RepoNotFound(Exception):
    """Raised when no agentic-delivery repo can be located."""

    exit_code = 6


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

CompatStatus = Literal["compatible", "patch-mismatch", "minor-mismatch", "skipped"]


class CompatError(Exception):
    """Raised when pipeline.yaml.version differs from the CLI's compat range by a major bump."""

    exit_code = 5

    def __init__(self, message: str, *, actual: str = "?", ranges: list[str] | None = None):
        super().__init__(message)
        self.actual = actual
        self.ranges = list(ranges or [])


@dataclass(frozen=True)
class CompatResult:
    actual: str
    ranges: tuple[str, ...]
    status: CompatStatus

    @property
    def display(self) -> str:
        if self.status == "compatible":
            return f"compatible: {','.join(self.ranges)} ✓"
        if self.status == "skipped":
            return "compat check disabled"
        kind = self.status.split("-")[0]
        return f"{kind} mismatch: {','.join(self.ranges)} ⚠"


def _parse_version(raw: str) -> tuple[int, int, int]:
    m = _VERSION_RE.match(raw.strip())
    if not m:
        raise CompatError(f"unrecognised version string: {raw!r}", actual=raw)
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


def _ranges() -> list[str]:
    if not COMPATIBLE_PIPELINE_VERSIONS:
        raise RuntimeError("CLI is misconfigured: COMPATIBLE_PIPELINE_VERSIONS empty")
    return list(COMPATIBLE_PIPELINE_VERSIONS)


_SEVERITY: dict[str, int] = {"major": 0, "minor": 1, "patch": 2, "compatible": 3}


def _classify_single(
    actual: tuple[int, int, int],
    lo: tuple[int, int, int] | None,
    hi: tuple[int, int, int] | None,
) -> str:
    lo_eff = lo if lo is not None else (0, 0, 0)
    if (hi is None or actual < hi) and lo_eff <= actual:
        return "compatible"

    if actual < lo_eff:
        if actual[0] != lo_eff[0]:
            return "major"
        if actual[1] != lo_eff[1]:
            return "minor"
        return "patch"

    # actual >= hi (hi is exclusive). hi cannot be None here.
    assert hi is not None
    if actual[0] != hi[0]:
        return "major"
    # If hi.patch == 0, then minor hi.minor is entirely excluded at this major,
    # so reaching minor==hi.minor is a minor-level bump, not a patch one.
    if hi[2] == 0:
        return "minor"
    if actual[1] != hi[1]:
        return "minor"
    return "patch"


def _classify(actual: tuple[int, int, int], ranges: list[str]) -> str:
    best = "major"
    for spec in ranges:
        lo, hi = _parse_range(spec)
        status = _classify_single(actual, lo, hi)
        if _SEVERITY[status] > _SEVERITY[best]:
            best = status
        if best == "compatible":
            return best
    return best


def check_compat(*, repo: Path, enabled: bool = True) -> CompatResult | None:
    """Verify the repo's pipeline.yaml version against CLI compat ranges.

    Returns None when disabled. Returns a CompatResult for compatible/patch/minor cases.
    Raises CompatError on major mismatch.
    Tiered behaviour per spec §8.4: patch/minor mismatches warn on stderr and continue.
    """
    if not enabled:
        return None
    pipeline = repo / "agentic" / "pipeline.yaml"
    data = yaml.safe_load(pipeline.read_text())
    actual_raw = data["pipeline"]["version"]
    actual = _parse_version(actual_raw)
    ranges = _ranges()
    status = _classify(actual, ranges)

    if status == "compatible":
        return CompatResult(actual=actual_raw, ranges=tuple(ranges), status="compatible")
    if status == "major":
        raise CompatError(
            f"pipeline {actual_raw} major mismatch with CLI compat {ranges}. "
            f"Upgrade CLI or pass --no-compat-check.",
            actual=actual_raw,
            ranges=ranges,
        )
    # patch or minor: warn and continue.
    msg = f"pipeline {status} mismatch: pipeline.yaml.version={actual_raw} vs CLI {ranges}"
    print(msg, file=sys.stderr)
    return CompatResult(
        actual=actual_raw,
        ranges=tuple(ranges),
        status="patch-mismatch" if status == "patch" else "minor-mismatch",
    )
