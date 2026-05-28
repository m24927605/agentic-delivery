"""Snapshot tests locking the ``--json`` envelope (spec §9.5.1).

Snapshots are stored under ``tests/snapshots/`` and re-generated only when the
caller passes ``--snapshot-update``. Any drift in the shape of ``run`` /
``artifacts`` / ``tasks`` / ``next`` / ``error`` shows up as a strict diff —
the same drift would also fail
:mod:`tests.test_json_schema_conformance`, but snapshots additionally pin
the exact values for the canonical fixtures.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from pytest_snapshot.plugin import Snapshot
from typer.testing import CliRunner

from agentic.app import app


STATUS_FIXTURES = Path(__file__).parent / "fixtures" / "manifests"
STATE_FIXTURES = Path(__file__).parent / "state_engine" / "fixtures"
SNAPSHOTS = Path(__file__).parent / "snapshots"


def _seed(
    tmp_path: Path,
    *,
    fixture_path: Path,
    run_id: str,
    impl: bool = False,
) -> Path:
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    d = tmp_path / "agentic" / "runs" / run_id
    d.mkdir(parents=True)
    name = "implementation-manifest.yaml" if impl else "manifest.yaml"
    (d / name).write_text(fixture_path.read_text())
    return tmp_path


def _normalise(payload: dict[str, object]) -> str:
    """Sort keys deterministically and serialise with stable formatting."""
    return json.dumps(payload, indent=2, sort_keys=True) + "\n"


@pytest.mark.parametrize(
    "fixture, run_id, impl, command, snapshot_name",
    [
        (
            STATUS_FIXTURES / "planning_fresh.yaml",
            "demo-planning",
            False,
            "status",
            "status_planning_fresh.json",
        ),
        (
            STATUS_FIXTURES / "impl_mid_dispatch.yaml",
            "demo-impl",
            True,
            "status",
            "status_impl_mid_dispatch.json",
        ),
        (
            STATE_FIXTURES / "planning_fresh_init.yaml",
            "demo",
            False,
            "next",
            "next_planning_fresh_init.json",
        ),
        (
            STATE_FIXTURES / "planning_mixed_drafts.yaml",
            "demo",
            False,
            "next",
            "next_planning_mixed_drafts.json",
        ),
        (
            STATE_FIXTURES / "impl_pending_task.yaml",
            "demo-impl",
            True,
            "next",
            "next_impl_pending_task.json",
        ),
    ],
)
def test_json_envelope_snapshot(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    snapshot: Snapshot,
    fixture: Path,
    run_id: str,
    impl: bool,
    command: str,
    snapshot_name: str,
) -> None:
    repo = _seed(tmp_path, fixture_path=fixture, run_id=run_id, impl=impl)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["--json", command, "--run-id", run_id])
    assert result.exit_code == 0, result.output
    payload = json.loads(result.stdout)
    assert payload["_schema"] == "agentic.cli/v1"
    snapshot.snapshot_dir = str(SNAPSHOTS)
    snapshot.assert_match(_normalise(payload), snapshot_name)


def test_error_envelope_snapshot_no_repo(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    snapshot: Snapshot,
) -> None:
    monkeypatch.chdir(tmp_path)
    monkeypatch.delenv("AGENTIC_HOME", raising=False)
    result = cli.invoke(app, ["--json", "status"])
    assert result.exit_code == 6
    payload = json.loads(result.stderr)
    # The message embeds tmp_path which is non-deterministic; normalise it.
    payload["error"]["message"] = "<tmp>"
    snapshot.snapshot_dir = str(SNAPSHOTS)
    snapshot.assert_match(_normalise(payload), "error_no_repo.json")


def test_error_envelope_snapshot_no_run_context(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    snapshot: Snapshot,
) -> None:
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    monkeypatch.chdir(tmp_path)
    monkeypatch.delenv("AGENTIC_HOME", raising=False)
    monkeypatch.delenv("AIT_RUN_ID", raising=False)
    result = cli.invoke(app, ["--json", "next"])
    assert result.exit_code == 6
    payload = json.loads(result.stderr)
    snapshot.snapshot_dir = str(SNAPSHOTS)
    snapshot.assert_match(_normalise(payload), "error_no_run_context.json")
