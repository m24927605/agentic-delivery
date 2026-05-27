"""Routing tests for `agentic identity ...` via the RecordingRunner."""

from __future__ import annotations

from pathlib import Path

import pytest
from typer.testing import CliRunner

from agentic.app import app
from agentic.commands import identity as identity_cmd
from tests._recording import RecordingRunner


def _seed(tmp_path: Path, run_id: str = "demo") -> Path:
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    d = tmp_path / "agentic" / "runs" / run_id
    d.mkdir(parents=True)
    (d / "manifest.yaml").write_text("run:\n  id: " + run_id + "\n  mode: planning\n")
    return tmp_path


@pytest.fixture
def runner(monkeypatch: pytest.MonkeyPatch) -> RecordingRunner:
    rr = RecordingRunner()
    monkeypatch.setattr(identity_cmd, "_runner_factory", lambda repo: rr)
    return rr


def test_identity_validate(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["identity", "validate"])
    assert result.exit_code == 0, result.output
    assert runner.calls[-1].name == "validate-identity-policy.sh"


def test_identity_authorize(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["identity", "authorize", "--action", "artifact.approve"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "authorize-agentic-action.sh"
    assert "--action" in call.args
    assert "artifact.approve" in call.args


def test_identity_authorize_requires_action(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["identity", "authorize"])
    assert result.exit_code != 0
    assert not runner.calls
