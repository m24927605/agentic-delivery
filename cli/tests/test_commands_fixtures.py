"""Routing tests for `agentic fixtures ...` via the RecordingRunner.

``run-golden-fixtures.sh`` is a repo-scoped runner (no RUN_ID), so the
wrapper uses ``invoke_no_run`` and the tests do not seed a run.
"""

from __future__ import annotations

from pathlib import Path

import pytest
from typer.testing import CliRunner

from agentic.app import app
from agentic.commands import fixtures as fixtures_cmd
from tests._recording import RecordingRunner


def _seed_repo_only(tmp_path: Path) -> Path:
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    (tmp_path / "agentic" / "runs").mkdir()
    return tmp_path


@pytest.fixture
def runner(monkeypatch: pytest.MonkeyPatch) -> RecordingRunner:
    rr = RecordingRunner()
    monkeypatch.setattr(fixtures_cmd, "_runner_factory", lambda repo: rr)
    return rr


def test_fixtures_run_routes(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_repo_only(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["fixtures", "run"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "run-golden-fixtures.sh"
    assert call.args == ()
    assert "RUN_ID" not in call.env
