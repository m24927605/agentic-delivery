"""Routing tests for `agentic impl ...` via the RecordingRunner."""

from __future__ import annotations

from pathlib import Path

import pytest
from typer.testing import CliRunner

from agentic.app import app
from agentic.commands import impl as impl_cmd
from tests._recording import RecordingRunner


def _seed_impl(tmp_path: Path, run_id: str) -> Path:
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    d = tmp_path / "agentic" / "runs" / run_id
    d.mkdir(parents=True)
    (d / "implementation-manifest.yaml").write_text(
        "run:\n  id: " + run_id + "\n  mode: implementation\n"
    )
    return tmp_path


@pytest.fixture
def runner(monkeypatch: pytest.MonkeyPatch) -> RecordingRunner:
    rr = RecordingRunner()
    monkeypatch.setattr(impl_cmd, "_runner_factory", lambda repo: rr)
    return rr


def test_impl_init_from_planning_run(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_impl(tmp_path, "impl-run")
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app,
        ["impl", "init", "--from", "planning-run", "--run-id", "impl-run"],
    )
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "init-implementation-run.sh"
    assert "--planning-run" in call.args
    assert "planning-run" in call.args
    assert call.env["RUN_ID"] == "impl-run"


def test_impl_tasks_dry_run_forwards_flag(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_impl(tmp_path, "impl-run")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["impl", "tasks", "--dry-run", "--run-id", "impl-run"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "generate-implementation-task-graph.sh"
    assert "--dry-run" in call.args


def test_impl_tasks_without_dry_run(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_impl(tmp_path, "impl-run")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["impl", "tasks", "--run-id", "impl-run"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "generate-implementation-task-graph.sh"
    assert "--dry-run" not in call.args
    assert "impl-run" in call.args


def test_impl_dispatch_with_actor_role(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_impl(tmp_path, "impl-run")
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app,
        [
            "--actor", "alice", "--role", "operator",
            "impl", "dispatch", "T1", "--run-id", "impl-run",
        ],
    )
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "dispatch-implementation-task.sh"
    assert "T1" in call.args
    assert call.env["AIT_ACTOR"] == "alice"
    assert call.env["AIT_ACTOR_ROLE"] == "operator"


def test_impl_dispatch_dry_run(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_impl(tmp_path, "impl-run")
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app,
        ["impl", "dispatch", "T1", "--dry-run", "--run-id", "impl-run"],
    )
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "dispatch-implementation-task.sh"
    assert "--dry-run" in call.args
    assert "T1" in call.args


def test_impl_execute_dry_run(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_impl(tmp_path, "impl-run")
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app,
        ["impl", "execute", "T1", "--dry-run", "--run-id", "impl-run"],
    )
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "execute-implementation-task.sh"
    assert "--dry-run" in call.args
    assert "T1" in call.args


def test_impl_execute_without_dry_run(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_impl(tmp_path, "impl-run")
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app,
        ["impl", "execute", "T1", "--run-id", "impl-run"],
    )
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "execute-implementation-task.sh"
    assert "--dry-run" not in call.args
    assert "T1" in call.args


def test_impl_review_forwards_task_id(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_impl(tmp_path, "impl-run")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["impl", "review", "T2", "--run-id", "impl-run"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "run-implementation-review-loop.sh"
    assert "T2" in call.args


def test_impl_review_with_actor(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_impl(tmp_path, "impl-run")
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app,
        [
            "--actor", "alice", "--role", "reviewer",
            "impl", "review", "T2", "--run-id", "impl-run",
        ],
    )
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.env["AIT_ACTOR"] == "alice"
    assert call.env["AIT_ACTOR_ROLE"] == "reviewer"


def test_impl_validate(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_impl(tmp_path, "impl-run")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["impl", "validate", "--run-id", "impl-run"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "validate-implementation-run.sh"
    assert "impl-run" in call.args


def test_impl_missing_run_id_exits_6(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_impl(tmp_path, "impl-run")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["impl", "tasks"])
    assert result.exit_code == 6
    assert "no run context" in result.output
