"""Routing tests for `agentic plan ...` via the RecordingRunner."""

from __future__ import annotations

from pathlib import Path

import pytest
from typer.testing import CliRunner

from agentic.app import app
from agentic.commands import plan as plan_cmd
from tests._recording import RecordingRunner


def _seed(tmp_path: Path, run_id: str) -> Path:
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    d = tmp_path / "agentic" / "runs" / run_id
    d.mkdir(parents=True)
    (d / "manifest.yaml").write_text("run:\n  id: " + run_id + "\n  mode: planning\n")
    return tmp_path


@pytest.fixture
def runner(monkeypatch: pytest.MonkeyPatch) -> RecordingRunner:
    rr = RecordingRunner()
    monkeypatch.setattr(plan_cmd, "_runner_factory", lambda repo: rr)
    return rr


def test_plan_generate_routes_to_script(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path, "demo")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["plan", "generate", "--run-id", "demo"])
    assert result.exit_code == 0, result.output
    assert len(runner.calls) == 1
    call = runner.calls[0]
    assert call.name == "generate-artifacts.sh"
    assert call.args == ("demo",)
    assert call.env["RUN_ID"] == "demo"


def test_plan_generate_agent_dry_run_default(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path, "demo")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["plan", "generate-agent", "--run-id", "demo"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "run-artifact-generation-agent.sh"
    assert call.args == ("--dry-run", "demo")


def test_plan_generate_agent_execute_flag(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path, "demo")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["plan", "generate-agent", "--execute", "--run-id", "demo"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.args == ("--execute", "demo")


def test_plan_review_routes_with_artifact_flag(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path, "demo")
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app, ["plan", "review", "--artifact", "docs/x.md", "--run-id", "demo"]
    )
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "run-artifact-review-loop.sh"
    assert call.args == ("demo", "--artifact", "docs/x.md")


def test_plan_revisions_routes_to_script(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path, "demo")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["plan", "revisions", "--run-id", "demo"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "create-artifact-revision-tasks.sh"
    assert call.args == ("demo",)


def test_plan_strategy_gate_routes_to_script(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path, "demo")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["--run-id", "demo", "plan", "strategy-gate"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "strategy-gate-check.sh"
    assert call.args == ()


def test_plan_state_routes_to_script(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path, "demo")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["plan", "state", "reviewing", "--run-id", "demo"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "update-run-state.sh"
    assert call.args == ("demo", "reviewing")


def test_plan_agency_review_routes_to_script(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path, "demo")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["plan", "agency", "review", "--run-id", "demo"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "run-agency-review.sh"
    assert call.args == ()


def test_plan_agency_summarize_routes_to_script(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path, "demo")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["plan", "agency", "summarize", "--run-id", "demo"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "summarize-agency-review.sh"
    assert call.args == ("demo",)


def test_plan_artifact_approve_uses_sugar(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path, "demo")
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app,
        [
            "--actor",
            "alice",
            "--role",
            "approver",
            "plan",
            "artifact",
            "docs/x.md",
            "approve",
            "--reason",
            "ship",
            "--run-id",
            "demo",
        ],
    )
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "update-artifact-status.sh"
    assert "approved" in call.args
    assert "docs/x.md" in call.args
    assert "--reason" in call.args and "ship" in call.args
    assert "--actor" in call.args and "alice" in call.args
    assert "--role" in call.args and "approver" in call.args
    assert call.env["AIT_ACTOR"] == "alice"
    assert call.env["AIT_ACTOR_ROLE"] == "approver"


def test_plan_artifact_canonical_status_passes_through(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path, "demo")
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app,
        [
            "plan",
            "artifact",
            "docs/x.md",
            "changes_requested",
            "--reason",
            "needs work",
            "--run-id",
            "demo",
        ],
    )
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert "changes_requested" in call.args


def test_plan_artifact_unknown_status_exits_2(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path, "demo")
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app,
        [
            "plan",
            "artifact",
            "docs/x.md",
            "bogus",
            "--reason",
            "n/a",
            "--run-id",
            "demo",
        ],
    )
    assert result.exit_code == 2
    assert "unknown status" in result.output


def test_plan_artifact_reject_and_defer_sugar(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path, "demo")
    monkeypatch.chdir(repo)
    for verb, expected in [("reject", "rejected"), ("defer", "deferred")]:
        result = cli.invoke(
            app,
            [
                "plan",
                "artifact",
                "docs/x.md",
                verb,
                "--reason",
                "r",
                "--run-id",
                "demo",
            ],
        )
        assert result.exit_code == 0, result.output
        assert expected in runner.calls[-1].args


def test_plan_missing_run_id_exits_6(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path, "demo")
    monkeypatch.chdir(repo)
    # Don't pass --run-id; nothing in env or .agentic/current-run.
    result = cli.invoke(app, ["plan", "generate"])
    assert result.exit_code == 6
    assert "no run context" in result.output


def test_plan_script_failure_maps_to_64_plus(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Spec §9.3: forwarded script exit codes occupy 64..79."""
    from agentic.shell import ShellResult

    rr = RecordingRunner(next_result=ShellResult(exit_code=3, stdout="", stderr="boom"))
    monkeypatch.setattr(plan_cmd, "_runner_factory", lambda repo: rr)
    repo = _seed(tmp_path, "demo")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["plan", "generate", "--run-id", "demo"])
    assert result.exit_code == 64 + 3


def test_plan_script_failure_clamps_exit_15(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from agentic.shell import ShellResult

    rr = RecordingRunner(next_result=ShellResult(exit_code=200, stdout="", stderr=""))
    monkeypatch.setattr(plan_cmd, "_runner_factory", lambda repo: rr)
    repo = _seed(tmp_path, "demo")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["plan", "generate", "--run-id", "demo"])
    assert result.exit_code == 79  # 64 + min(200, 15) = 79


def test_plan_script_failure_emits_agentic_error_envelope(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """CLI-11/CLI-12: a shelled-out non-zero exit produces a structured
    ``script_failed`` envelope on stderr — not a bare ``typer.Exit``.

    Without this the only signal on non-zero script exit is the exit code,
    which is too narrow to distinguish ``invoke()`` raising AgenticError
    from a pre-CLI-11-era ``typer.echo + Exit`` regression.
    """
    import json as _json

    from agentic.shell import ShellResult

    # Empty script stderr so the JSON envelope is the only thing on stderr —
    # _execute() echoes child stderr verbatim before raising AgenticError, and
    # mixing it with the envelope would break json.loads. The script_failed
    # behaviour itself doesn't depend on the child producing stderr text.
    rr = RecordingRunner(next_result=ShellResult(exit_code=2, stdout="", stderr=""))
    monkeypatch.setattr(plan_cmd, "_runner_factory", lambda repo: rr)
    repo = _seed(tmp_path, "demo")
    monkeypatch.chdir(repo)
    monkeypatch.delenv("AGENTIC_HOME", raising=False)
    result = cli.invoke(app, ["--json", "plan", "generate", "--run-id", "demo"])
    assert result.exit_code == 66  # 64 + 2
    payload = _json.loads(result.stderr)
    assert payload["_schema"] == "agentic.cli/v1"
    assert payload["error"]["category"] == "script_failed"
    assert "generate-artifacts.sh" in payload["error"]["message"]
