"""Routing tests for `agentic evidence ...` via the RecordingRunner.

The underlying scripts (``record-validation-evidence.sh`` and
``redact-local-evidence.sh``) do NOT consume the ``RUN_ID`` env var — they
take their own positional/named args. Per the CLI-08 lesson we therefore use
``invoke_no_run`` and never force run-context resolution. These tests pin
that contract: they pass without a seeded run, and assert ``RUN_ID`` is not
exported to the script.
"""

from __future__ import annotations

from pathlib import Path

import pytest
from typer.testing import CliRunner

from agentic.app import app
from agentic.commands import evidence as evidence_cmd
from tests._recording import RecordingRunner


def _seed_repo_only(tmp_path: Path) -> Path:
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    (tmp_path / "agentic" / "runs").mkdir()
    return tmp_path


@pytest.fixture
def runner(monkeypatch: pytest.MonkeyPatch) -> RecordingRunner:
    rr = RecordingRunner()
    monkeypatch.setattr(evidence_cmd, "_runner_factory", lambda repo: rr)
    return rr


def test_evidence_record_routes(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_repo_only(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["evidence", "record"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "record-validation-evidence.sh"
    assert "RUN_ID" not in call.env


def test_evidence_record_no_run_required(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    """Wrapper must NOT require a seeded run (CLI-08 lesson)."""
    repo = _seed_repo_only(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["evidence", "record"])
    assert result.exit_code == 0, result.output


def test_evidence_redact_routes(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_repo_only(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["evidence", "redact"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "redact-local-evidence.sh"
    assert "RUN_ID" not in call.env


def test_evidence_redact_no_run_required(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_repo_only(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["evidence", "redact"])
    assert result.exit_code == 0, result.output
