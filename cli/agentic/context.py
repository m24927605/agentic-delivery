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
        "no agentic-delivery repo found. Pass --repo, set AGENTIC_HOME, "
        "cd into a repo, or run `agentic new <name>` to scaffold a new project here."
    )


@dataclass(frozen=True)
class Run:
    id: str
    source: str


class RunNotFound(Exception):
    """Raised when a run id cannot be resolved or does not exist on disk."""

    exit_code = 6


# Per spec §7.1.1: run ids must be ASCII alphanumeric, with optional `_`/`-` after
# the first char, length 1-128. The leading-char restriction blocks leading dashes
# (argv parsing confusion) and the character class blocks path traversal, command
# substitution, NUL/newline injection, and Unicode-confusable lookalikes.
_VALID_RUN_ID = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}$")


def _validate_run_id(value: str, source: str) -> None:
    """Refuse a run id that fails the regex. Raises RunNotFound (exit_code=6)."""
    if not _VALID_RUN_ID.fullmatch(value):
        raise RunNotFound(
            f"invalid run id from {source}: {value!r}. "
            f"Run ids must match {_VALID_RUN_ID.pattern} "
            f"(ASCII letters/digits, optional underscore/hyphen, 1-128 chars, "
            f"no leading dash, no whitespace, no path separators)."
        )


def _run_exists(repo: Path, run_id: str) -> bool:
    return (
        (repo / "agentic" / "runs" / run_id / "manifest.yaml").is_file()
        or (repo / "agentic" / "runs" / run_id / "implementation-manifest.yaml").is_file()
    )


def _read_current_run_file(current_file: Path) -> str | None:
    """Read .agentic/current-run, refusing multi-line content.

    Returns the raw single non-blank line (no strip), or None if the file is
    empty/whitespace-only (per §7.5: "treat as unset, fall through").
    Raises RunNotFound when the file has >1 non-blank line (§7.5 tightening).
    """
    lines = current_file.read_text().splitlines()
    nonblank = [ln for ln in lines if ln.strip()]
    if not nonblank:
        return None
    if len(nonblank) > 1:
        raise RunNotFound(
            ".agentic/current-run has multiple non-blank lines; refuse per spec §7.1.1. "
            "Run 'agentic run clear' then 'agentic run use <id>'."
        )
    # Return raw (no strip) so the validator regex catches any leading whitespace.
    return nonblank[0]


def resolve_run_id(*, repo: Path, flag: str | None) -> Run:
    if flag:
        _validate_run_id(flag, source="--run-id")
        if not _run_exists(repo, flag):
            raise RunNotFound(f"run {flag!r} does not exist under {repo}/agentic/runs/")
        return Run(id=flag, source="--run-id")

    env = os.environ.get("AIT_RUN_ID")
    if env:
        _validate_run_id(env, source="AIT_RUN_ID")
        if not _run_exists(repo, env):
            raise RunNotFound(f"AIT_RUN_ID={env!r} does not exist under {repo}/agentic/runs/")
        return Run(id=env, source="AIT_RUN_ID")

    current_file = repo / ".agentic" / "current-run"
    if current_file.is_file():
        candidate = _read_current_run_file(current_file)
        if candidate is not None:
            _validate_run_id(candidate, source="file:.agentic/current-run")
            if not _run_exists(repo, candidate):
                raise RunNotFound(
                    f"run {candidate!r} from .agentic/current-run does not exist under "
                    f"{repo}/agentic/runs/. Run 'agentic run clear' or 'agentic run use <id>'."
                )
            return Run(id=candidate, source="file:.agentic/current-run")

    raise RunNotFound(
        "no run context. Use --run-id, set AIT_RUN_ID, or 'agentic run use <id>'."
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
