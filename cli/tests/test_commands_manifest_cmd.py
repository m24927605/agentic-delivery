"""Routing tests for `agentic manifest ...` via the RecordingRunner.

All three manifest scripts (``validate-manifest-schema.sh``,
``validate-artifact-templates.sh``, ``privacy-scan-tracked.sh``) accept
their target via positional/flag args, not via ``RUN_ID``. So the wrappers
use ``invoke_no_run`` and the tests pin that RUN_ID isn't exported.
"""

from __future__ import annotations

from pathlib import Path

import pytest
from typer.testing import CliRunner

from agentic.app import app
from agentic.commands import manifest_cmd
from tests._recording import RecordingRunner


def _seed_repo_only(tmp_path: Path) -> Path:
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    (tmp_path / "agentic" / "runs").mkdir()
    return tmp_path


@pytest.fixture
def runner(monkeypatch: pytest.MonkeyPatch) -> RecordingRunner:
    rr = RecordingRunner()
    monkeypatch.setattr(manifest_cmd, "_runner_factory", lambda repo: rr)
    return rr


def test_manifest_validate_all(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_repo_only(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["manifest", "validate", "--all"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "validate-manifest-schema.sh"
    assert call.args == ("--all",)
    assert "RUN_ID" not in call.env


def test_manifest_validate_run_id(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_repo_only(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["manifest", "validate", "--run-id", "demo"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "validate-manifest-schema.sh"
    assert call.args == ("demo",)
    assert "RUN_ID" not in call.env


def test_manifest_validate_default_all(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    """No flag → script default kicks in (passes nothing; script defaults to --all)."""
    repo = _seed_repo_only(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["manifest", "validate"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "validate-manifest-schema.sh"
    assert call.args == ()


def test_manifest_templates(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_repo_only(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["manifest", "templates", "--run-id", "demo"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "validate-artifact-templates.sh"
    assert call.args == ("demo",)
    assert "RUN_ID" not in call.env


def test_manifest_templates_requires_run_id(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_repo_only(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["manifest", "templates"])
    assert result.exit_code != 0
    assert not runner.calls


def test_manifest_scan(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_repo_only(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["manifest", "scan"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "privacy-scan-tracked.sh"
    assert call.args == ()
    assert "RUN_ID" not in call.env
