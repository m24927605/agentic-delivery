"""CLI tests for `agentic status` (text + --json)."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from agentic.app import app


FIXTURES = Path(__file__).parent / "fixtures" / "manifests"


def _seed(
    tmp_path: Path,
    fixture: str,
    run_id: str,
    *,
    impl: bool = False,
) -> Path:
    src = FIXTURES / fixture
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    d = tmp_path / "agentic" / "runs" / run_id
    d.mkdir(parents=True)
    name = "implementation-manifest.yaml" if impl else "manifest.yaml"
    (d / name).write_text(src.read_text())
    return tmp_path


def test_status_text_for_planning(
    cli: pytest.FixtureRequest, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    repo = _seed(tmp_path, "planning_fresh.yaml", "demo-planning")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["status", "--run-id", "demo-planning"])  # type: ignore[attr-defined]
    assert result.exit_code == 0, result.output
    assert "demo-planning" in result.stdout
    assert "planning" in result.stdout
    assert "artifact_plan_created" in result.stdout
    assert "approved" in result.stdout  # artifact status appears in the table


def test_status_text_for_implementation_shows_tasks(
    cli: pytest.FixtureRequest, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    repo = _seed(tmp_path, "impl_mid_dispatch.yaml", "demo-impl", impl=True)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["status", "--run-id", "demo-impl"])  # type: ignore[attr-defined]
    assert result.exit_code == 0, result.output
    assert "demo-impl" in result.stdout
    assert "implementation" in result.stdout
    assert "implementation_planned" in result.stdout
    # task ids appear in the Tasks table
    assert "T1" in result.stdout
    assert "T2" in result.stdout
    # dispatched/pending task statuses are visible
    assert "dispatched" in result.stdout
    assert "pending" in result.stdout


def test_status_no_run_context_exit_6(
    cli: pytest.FixtureRequest, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    monkeypatch.chdir(tmp_path)
    result = cli.invoke(app, ["status"])  # type: ignore[attr-defined]
    assert result.exit_code == 6


def test_status_json_envelope(
    cli: pytest.FixtureRequest, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Spec §9.5: --json output starts with `_schema: agentic.cli/v1`."""
    repo = _seed(tmp_path, "planning_fresh.yaml", "demo-planning")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["--json", "status", "--run-id", "demo-planning"])  # type: ignore[attr-defined]
    assert result.exit_code == 0, result.output
    payload = json.loads(result.stdout)
    assert payload["_schema"] == "agentic.cli/v1"
    assert payload["run"]["id"] == "demo-planning"
    assert payload["run"]["mode"] == "planning"
    assert payload["run"]["profile"] == "default-delivery"
    assert payload["run"]["state"] == "artifact_plan_created"
    assert payload["run"]["source"] == "--run-id"
    assert payload["artifacts"]["total"] == 3
    assert payload["artifacts"]["approved"] == 1
    # planned + drafted are "pending" (not yet approved/rejected/deferred)
    assert payload["artifacts"]["pending"] == 2
    assert payload["artifacts"]["rejected"] == 0
    assert payload["artifacts"]["deferred"] == 0
    assert payload["tasks"] == []


def test_status_json_envelope_implementation(
    cli: pytest.FixtureRequest, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    repo = _seed(tmp_path, "impl_mid_dispatch.yaml", "demo-impl", impl=True)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["--json", "status", "--run-id", "demo-impl"])  # type: ignore[attr-defined]
    assert result.exit_code == 0, result.output
    payload = json.loads(result.stdout)
    assert payload["_schema"] == "agentic.cli/v1"
    assert payload["run"]["mode"] == "implementation"
    assert payload["artifacts"]["total"] == 1
    assert payload["artifacts"]["approved"] == 1
    assert payload["tasks"] == [
        {"id": "T1", "status": "dispatched"},
        {"id": "T2", "status": "pending"},
    ]


def test_status_json_schema_is_first_key(
    cli: pytest.FixtureRequest, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Spec §9.5: the envelope keeps `_schema` as the first key (insertion order)."""
    repo = _seed(tmp_path, "planning_fresh.yaml", "demo-planning")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["--json", "status", "--run-id", "demo-planning"])  # type: ignore[attr-defined]
    assert result.exit_code == 0
    # First non-whitespace JSON content line after `{` should reference _schema.
    body = result.stdout.strip()
    assert body.startswith("{")
    # The first key in the dumped JSON is _schema (because we set sort_keys=False).
    payload = json.loads(body)
    assert next(iter(payload.keys())) == "_schema"
