"""Subprocess wrapper for scripts/*.sh.

Spec references:
- §11.5: script name regex must reject leading-dash names (argv parsing trap).
- §9.3: callers translate ScriptError/exit codes to typer exits separately.
"""

from __future__ import annotations

import os
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

_SCRIPT_NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]*\.sh$")


class ScriptError(Exception):
    """Raised for invalid script names or missing scripts before exec."""

    exit_code = 1


@dataclass(frozen=True)
class ShellResult:
    exit_code: int
    stdout: str
    stderr: str


@dataclass
class ScriptRunner:
    """Run scripts/<name>.sh from <repo> with env propagation."""

    repo: Path

    def run(
        self,
        *,
        name: str,
        args: list[str],
        env_overrides: dict[str, str | None],
        script_path: Path | None = None,
    ) -> ShellResult:
        if not _SCRIPT_NAME_RE.match(name):
            raise ScriptError(
                f"refused script name {name!r}: must match {_SCRIPT_NAME_RE.pattern}"
            )
        # When ``script_path`` is supplied the caller has already resolved and
        # validated it (see ``agentic raw`` — spec §11.5 TOCTOU closure). Trust
        # that path verbatim so the exec'd file is the same one that was
        # checked, rather than re-resolving via ``self.repo / "scripts" / name``
        # which would reopen the swap window.
        if script_path is not None:
            script = script_path
        else:
            script = self.repo / "scripts" / name
            if not script.is_file():
                raise ScriptError(f"no such script: scripts/{name}")

        env = os.environ.copy()
        for k, v in env_overrides.items():
            if v is None:
                env.pop(k, None)
            else:
                env[k] = v

        proc = subprocess.run(
            [str(script), *args],
            cwd=self.repo,
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
        return ShellResult(
            exit_code=proc.returncode,
            stdout=proc.stdout,
            stderr=proc.stderr,
        )
