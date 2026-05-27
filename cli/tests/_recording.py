"""Shared test helper: a fake ScriptRunner that records calls without spawning subprocesses."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from agentic.shell import ShellResult


@dataclass
class _Call:
    name: str
    args: tuple[str, ...]
    env: dict[str, str]
    script_path: Path | None = None


@dataclass
class RecordingRunner:
    calls: list[_Call] = field(default_factory=list)
    next_result: ShellResult = field(
        default_factory=lambda: ShellResult(exit_code=0, stdout="", stderr="")
    )

    def run(
        self,
        *,
        name: str,
        args: list[str],
        env_overrides: dict[str, str],
        script_path: Path | None = None,
    ) -> ShellResult:
        self.calls.append(
            _Call(
                name=name,
                args=tuple(args),
                env=dict(env_overrides),
                script_path=script_path,
            )
        )
        return self.next_result
