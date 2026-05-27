"""CLI tests for ``agentic next`` (text + --json)."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from agentic.app import app

STATE_FIXTURES = Path(__file__).parent / "state_engine" / "fixtures"


def _seed(
    tmp_path: Path,
    fixture: str,
    run_id: str,
    *,
    impl: bool = False,
) -> Path:
    src = STATE_FIXTURES / fixture
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    d = tmp_path / "agentic" / "runs" / run_id
    d.mkdir(parents=True)
    name = "implementation-manifest.yaml" if impl else "manifest.yaml"
    (d / name).write_text(src.read_text())
    return tmp_path


def test_next_text_for_planning_drafts(
    cli: pytest.FixtureRequest, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    repo = _seed(tmp_path, "planning_fresh_init.yaml", "demo")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["next", "--run-id", "demo"])  # type: ignore[attr-defined]
    assert result.exit_code == 0, result.output
    assert "agentic plan generate" in result.stdout
    assert "planning-need-drafts" in result.stdout
    # Reason mentions the unresolved planned artifacts
    assert "a.md" in result.stdout
    assert "b.md" in result.stdout


def test_next_text_for_impl_dispatch(
    cli: pytest.FixtureRequest, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    repo = _seed(tmp_path, "impl_pending_task.yaml", "demo-impl", impl=True)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["next", "--run-id", "demo-impl"])  # type: ignore[attr-defined]
    assert result.exit_code == 0, result.output
    assert "agentic impl dispatch T-1" in result.stdout
    assert "impl-dispatch" in result.stdout


def test_next_json(
    cli: pytest.FixtureRequest, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    repo = _seed(tmp_path, "planning_fresh_init.yaml", "demo")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["--json", "next", "--run-id", "demo"])  # type: ignore[attr-defined]
    assert result.exit_code == 0, result.output
    payload = json.loads(result.stdout)
    assert payload["_schema"] == "agentic.cli/v1"
    # The fixture's manifest carries run.id == "x"; the on-disk dir was "demo".
    # Per spec §4.2 the loader trusts the manifest as the source of truth.
    assert payload["run"]["id"] == "x"
    assert payload["run"]["mode"] == "planning"
    assert payload["run"]["source"] == "--run-id"
    assert payload["next"]["rule_id"] == "planning-need-drafts"
    assert "agentic plan generate" in payload["next"]["suggest"]
    assert "{" not in payload["next"]["suggest"]


def test_next_json_envelope_schema_first(
    cli: pytest.FixtureRequest, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    repo = _seed(tmp_path, "planning_fresh_init.yaml", "demo")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["--json", "next", "--run-id", "demo"])  # type: ignore[attr-defined]
    payload = json.loads(result.stdout)
    assert next(iter(payload.keys())) == "_schema"


def test_next_no_run_context_exit_6(
    cli: pytest.FixtureRequest, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    monkeypatch.chdir(tmp_path)
    result = cli.invoke(app, ["next"])  # type: ignore[attr-defined]
    assert result.exit_code == 6


def test_next_does_not_modify_repo(
    cli: pytest.FixtureRequest, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """``agentic next`` is read-only — fixtures on disk must not change."""
    repo = _seed(tmp_path, "planning_fresh_init.yaml", "demo")
    monkeypatch.chdir(repo)
    before = (
        repo / "agentic" / "runs" / "demo" / "manifest.yaml"
    ).read_text()
    cli.invoke(app, ["next", "--run-id", "demo"])  # type: ignore[attr-defined]
    after = (
        repo / "agentic" / "runs" / "demo" / "manifest.yaml"
    ).read_text()
    assert before == after
