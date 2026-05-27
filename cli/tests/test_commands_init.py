"""Routing tests for top-level `agentic init`."""

from __future__ import annotations

from pathlib import Path

import pytest
from typer.testing import CliRunner

from agentic.app import app
from agentic.commands import init as init_cmd
from tests._recording import RecordingRunner


def _seed_repo(tmp_path: Path) -> Path:
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    return tmp_path


@pytest.fixture
def runner(monkeypatch: pytest.MonkeyPatch) -> RecordingRunner:
    rr = RecordingRunner()
    monkeypatch.setattr(init_cmd, "_runner_factory", lambda repo: rr)
    return rr


def test_init_with_goal_string(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_repo(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["init", "build a thing"])
    assert result.exit_code == 0, result.output
    assert len(runner.calls) == 1
    call = runner.calls[0]
    assert call.name == "init-agentic-run.sh"
    assert call.args == ("build a thing",)


def test_init_with_goal_file(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_repo(tmp_path)
    goal = repo / "goal.md"
    goal.write_text("# Goal\n")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["init", "--goal-file", str(goal)])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.args == ("--goal-file", str(goal))


def test_init_with_profile_sets_env(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_repo(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["init", "the goal", "--profile", "boss-idea"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.env["PROFILE"] == "boss-idea"
    assert "the goal" in call.args


def test_init_propagates_actor_role(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_repo(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app,
        ["--actor", "alice", "--role", "founder", "init", "the goal"],
    )
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.env["AIT_ACTOR"] == "alice"
    assert call.env["AIT_ACTOR_ROLE"] == "founder"


def test_init_requires_goal_or_goal_file(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_repo(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["init"])
    assert result.exit_code == 2
    assert "goal" in result.output


def test_init_without_repo_exits_6(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    # Run from a directory with no agentic/pipeline.yaml.
    monkeypatch.chdir(tmp_path)
    monkeypatch.delenv("AGENTIC_HOME", raising=False)
    result = cli.invoke(app, ["init", "goal"])
    assert result.exit_code == 6
