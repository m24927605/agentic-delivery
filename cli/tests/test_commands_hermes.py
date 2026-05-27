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
        [
            "hermes",
            "run",
            "update_artifact_status",
            "--",
            "run_id=demo",
            "artifact_path=x.md",
        ],
    )
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "run-hermes-action.sh"
    assert call.args[0] == "update_artifact_status"
    assert "run_id=demo" in call.args
    assert "artifact_path=x.md" in call.args
    # `--` must NOT be forwarded to the script as an argv token.
    assert "--" not in call.args


def test_hermes_run_refuses_kv_without_double_dash(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    """kv args must be preceded by literal '--' (argv-injection boundary)."""
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app,
        ["hermes", "run", "update_artifact_status", "run_id=demo"],
    )
    assert result.exit_code == 2
    assert runner.calls == []


def test_hermes_run_refuses_flag_shaped_kv(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    """`--evil=1` after '--' must still fail the kv shape check (key not identifier)."""
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app,
        ["hermes", "run", "update_artifact_status", "--", "--evil=1"],
    )
    assert result.exit_code == 2
    assert runner.calls == []


def test_hermes_run_refuses_non_kv_positional(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    """Tokens without '=' are not key=value and must be refused."""
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app,
        ["hermes", "run", "update_artifact_status", "--", "junk"],
    )
    assert result.exit_code == 2
    assert runner.calls == []


def test_hermes_run_refuses_newline_in_kv(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    """kv args containing newline bytes must be refused (log-injection / parser smuggling)."""
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app,
        ["hermes", "run", "update_artifact_status", "--", "key=value\nrogue"],
    )
    assert result.exit_code == 2
    assert runner.calls == []


def test_hermes_run_refuses_nul_in_kv(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    """kv args containing NUL bytes must be refused."""
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app,
        ["hermes", "run", "update_artifact_status", "--", "key=value\x00rogue"],
    )
    assert result.exit_code == 2
    assert runner.calls == []


def test_hermes_run_refuses_invalid_action_name(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    """Action names not matching snake_case identifier must be refused."""
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    # Use `--` so Click doesn't parse the leading-dash action as a flag.
    result = cli.invoke(app, ["hermes", "run", "--", "Bad-Action"])
    assert result.exit_code == 2
    assert runner.calls == []


def test_hermes_run_refuses_dotted_action_name(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    """Dotted names (identity-style) are not the Hermes convention; must be refused."""
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["hermes", "run", "artifact.approve"])
    assert result.exit_code == 2
    assert runner.calls == []


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


# --------------------------------------------------------------------------- #
# Env propagation — spec §9.4 / §13 CLI-09a acceptance: --actor / --role at
# the root callback MUST reach call.env as AIT_ACTOR / AIT_ACTOR_ROLE for
# every hermes subcommand.
# --------------------------------------------------------------------------- #


def test_hermes_run_propagates_actor_and_role_env(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app,
        [
            "--actor",
            "alice",
            "--role",
            "operator",
            "hermes",
            "run",
            "update_artifact_status",
            "--",
            "run_id=demo",
        ],
    )
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.env["AIT_ACTOR"] == "alice"
    assert call.env["AIT_ACTOR_ROLE"] == "operator"


def test_hermes_actions_list_propagates_actor_and_role_env(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app,
        ["--actor", "alice", "--role", "reviewer", "hermes", "actions", "list"],
    )
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.env["AIT_ACTOR"] == "alice"
    assert call.env["AIT_ACTOR_ROLE"] == "reviewer"


def test_hermes_memory_sync_propagates_actor_and_role_env(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app,
        ["--actor", "alice", "--role", "operator", "hermes", "memory-sync"],
    )
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.env["AIT_ACTOR"] == "alice"
    assert call.env["AIT_ACTOR_ROLE"] == "operator"


def test_hermes_run_no_actor_means_no_env(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    """Without --actor/--role at the root, env must not contain AIT_ACTOR*."""
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["hermes", "run", "update_artifact_status"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert "AIT_ACTOR" not in call.env
    assert "AIT_ACTOR_ROLE" not in call.env
