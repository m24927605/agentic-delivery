"""Routing tests for `agentic hermes ...` via the RecordingRunner."""

from __future__ import annotations

from pathlib import Path

import pytest
from typer.testing import CliRunner

from agentic.app import app
from agentic.commands import hermes as hermes_cmd
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
    monkeypatch.setattr(hermes_cmd, "_runner_factory", lambda repo: rr)
    return rr


def test_hermes_actions_list(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["hermes", "actions", "list"])
    assert result.exit_code == 0, result.output
    assert runner.calls[-1].name == "validate-hermes-actions.sh"


def test_hermes_actions_validate(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["hermes", "actions", "validate"])
    assert result.exit_code == 0, result.output
    assert runner.calls[-1].name == "validate-hermes-actions.sh"


def test_hermes_run_with_kv(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app,
        ["hermes", "run", "update_artifact_status", "run_id=demo", "artifact_path=x.md"],
    )
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "run-hermes-action.sh"
    assert call.args[0] == "update_artifact_status"
    assert "run_id=demo" in call.args
    assert "artifact_path=x.md" in call.args


def test_hermes_run_without_kv(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["hermes", "run", "noop_action"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "run-hermes-action.sh"
    assert call.args == ("noop_action",)


def test_hermes_memory_sync_dry_run(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["hermes", "memory-sync", "--dry-run"])
    assert result.exit_code == 0, result.output
    assert runner.calls[-1].name == "hermes-memory-sync.sh"
    assert "--dry-run" in runner.calls[-1].args


def test_hermes_memory_sync_no_dry_run(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["hermes", "memory-sync", "--no-dry-run"])
    assert result.exit_code == 0, result.output
    assert runner.calls[-1].name == "hermes-memory-sync.sh"
    assert "--dry-run" not in runner.calls[-1].args


def test_hermes_scheduler_dry_run(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["hermes", "scheduler", "--dry-run"])
    assert result.exit_code == 0, result.output
    assert runner.calls[-1].name == "hermes-scheduler-dry-run.sh"
    assert "--dry-run" in runner.calls[-1].args


def test_hermes_gateway_dry_run(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["hermes", "gateway", "--dry-run"])
    assert result.exit_code == 0, result.output
    assert runner.calls[-1].name == "hermes-gateway-dry-run.sh"
    assert "--dry-run" in runner.calls[-1].args
