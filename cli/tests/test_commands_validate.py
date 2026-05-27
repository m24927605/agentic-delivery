"""Routing tests for `agentic validate ...` via the RecordingRunner.

``validate-agentic-system.sh`` is repo-scoped and reads no RUN_ID — the
wrapper uses ``invoke_no_run`` and the tests pin RUN_ID isn't exported.
"""

from __future__ import annotations

from pathlib import Path

import pytest
from typer.testing import CliRunner

from agentic.app import app
from agentic.commands import validate as validate_cmd
from tests._recording import RecordingRunner


def _seed_repo_only(tmp_path: Path) -> Path:
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    (tmp_path / "agentic" / "runs").mkdir()
    return tmp_path


@pytest.fixture
def runner(monkeypatch: pytest.MonkeyPatch) -> RecordingRunner:
    rr = RecordingRunner()
    monkeypatch.setattr(validate_cmd, "_runner_factory", lambda repo: rr)
    return rr


def test_validate_system(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_repo_only(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["validate", "system"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "validate-agentic-system.sh"
    assert call.args == ()
    assert "RUN_ID" not in call.env
