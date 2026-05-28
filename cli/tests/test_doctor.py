"""Behavioral tests for ``agentic doctor`` (CLI-12).

The doctor command batches four validators and aggregates their results.
We exercise three paths:

- all checks pass → exit 0, scripts called in order.
- ≥1 check fails → exit 3 (validation_failed) with FAIL surfaced in stdout
  and a structured stderr envelope.
- ``--json`` produces the ``agentic.cli/v1`` envelope with a ``checks`` array.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from typer.testing import CliRunner

from agentic.app import app
from agentic.commands import doctor as doctor_cmd
from agentic.shell import ShellResult
from tests._recording import RecordingRunner


_DOCTOR_SCRIPT_NAMES = {
    "validate-agentic-system.sh",
    "validate-manifest-schema.sh",
    "privacy-scan-tracked.sh",
    "validate-identity-policy.sh",
}


def _seed(tmp_path: Path) -> Path:
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    return tmp_path


@pytest.fixture
def runner(monkeypatch: pytest.MonkeyPatch) -> RecordingRunner:
    rr = RecordingRunner()
    monkeypatch.setattr(doctor_cmd, "_runner_factory", lambda repo: rr)
    return rr


def test_doctor_all_pass_invokes_each_script(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    monkeypatch.delenv("AGENTIC_HOME", raising=False)
    runner.next_result = ShellResult(exit_code=0, stdout="", stderr="")
    result = cli.invoke(app, ["doctor"])
    assert result.exit_code == 0, result.output
    names = [c.name for c in runner.calls]
    for script in _DOCTOR_SCRIPT_NAMES:
        assert script in names, f"missing {script} in {names}"


def test_doctor_passes_manifest_all_flag(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    monkeypatch.delenv("AGENTIC_HOME", raising=False)
    runner.next_result = ShellResult(exit_code=0, stdout="", stderr="")
    result = cli.invoke(app, ["doctor"])
    assert result.exit_code == 0, result.output
    manifest_call = next(
        c for c in runner.calls if c.name == "validate-manifest-schema.sh"
    )
    assert manifest_call.args == ("--all",)


def test_doctor_aggregates_failure_exits_3(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """≥1 check failing surfaces as validation_failed (exit 3)."""
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    monkeypatch.delenv("AGENTIC_HOME", raising=False)

    class _FailingRunner:
        def __init__(self) -> None:
            self.calls: list[str] = []

        def run(
            self,
            *,
            name: str,
            args: list[str],
            env_overrides: dict[str, str],
        ) -> ShellResult:
            self.calls.append(name)
            return ShellResult(
                exit_code=0 if name == "privacy-scan-tracked.sh" else 1,
                stdout="",
                stderr="boom",
            )

    fr = _FailingRunner()
    monkeypatch.setattr(doctor_cmd, "_runner_factory", lambda repo: fr)
    result = cli.invoke(app, ["doctor"])
    # validation_failed → exit 3, even though one check passed.
    assert result.exit_code == 3, result.output
    # The text-mode table writes status cells to stdout.
    assert "FAIL" in result.stdout
    # Structured stderr leads with the "x  " sentinel from render_error.
    assert result.stderr.startswith("x  ")


def test_doctor_json_envelope(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    monkeypatch.delenv("AGENTIC_HOME", raising=False)
    runner.next_result = ShellResult(exit_code=0, stdout="", stderr="")
    result = cli.invoke(app, ["--json", "doctor"])
    assert result.exit_code == 0, result.output
    payload = json.loads(result.stdout)
    assert payload["_schema"] == "agentic.cli/v1"
    assert isinstance(payload["checks"], list)
    assert len(payload["checks"]) == 4
    for entry in payload["checks"]:
        assert entry["status"] == "PASS"
        assert entry["exit_code"] == 0
        assert entry["script"] in _DOCTOR_SCRIPT_NAMES


def test_doctor_json_envelope_on_failure(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    monkeypatch.delenv("AGENTIC_HOME", raising=False)

    rr = RecordingRunner(
        next_result=ShellResult(exit_code=2, stdout="", stderr="bad")
    )
    monkeypatch.setattr(doctor_cmd, "_runner_factory", lambda repo: rr)
    result = cli.invoke(app, ["--json", "doctor"])
    assert result.exit_code == 3
    # Structured stdout envelope is the per-check report.
    report = json.loads(result.stdout)
    assert report["_schema"] == "agentic.cli/v1"
    assert all(c["status"] == "FAIL" for c in report["checks"])
    # Structured stderr is the AgenticError envelope.
    err_payload = json.loads(result.stderr)
    assert err_payload["error"]["category"] == "validation_failed"


def test_doctor_no_repo_exits_6(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.chdir(tmp_path)
    monkeypatch.delenv("AGENTIC_HOME", raising=False)
    result = cli.invoke(app, ["doctor"])
    assert result.exit_code == 6
    assert result.stderr.startswith("x  ")
