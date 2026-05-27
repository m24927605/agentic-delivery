"""Routing tests for `agentic boss ...` via the RecordingRunner."""

from __future__ import annotations

from pathlib import Path

import pytest
from typer.testing import CliRunner

from agentic.app import app
from agentic.commands import boss as boss_cmd
from tests._recording import RecordingRunner


def _seed_boss(tmp_path: Path, run_id: str = "boss-run") -> Path:
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    d = tmp_path / "agentic" / "runs" / run_id
    d.mkdir(parents=True)
    (d / "manifest.yaml").write_text(
        "run:\n  id: " + run_id + "\n  mode: planning\n  profile: boss-idea-response\n"
    )
    return tmp_path


@pytest.fixture
def runner(monkeypatch: pytest.MonkeyPatch) -> RecordingRunner:
    rr = RecordingRunner()
    monkeypatch.setattr(boss_cmd, "_runner_factory", lambda repo: rr)
    return rr


def test_boss_init(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_boss(tmp_path)
    monkeypatch.chdir(repo)
    (repo / "idea.md").write_text("# idea\n")
    result = cli.invoke(app, ["boss", "init", "idea.md", "--run-id", "boss-run"])
    assert result.exit_code == 0, result.output
    assert runner.calls[-1].name == "init-boss-idea-run.sh"
    assert "idea.md" in runner.calls[-1].args


def test_boss_research_collect_forwards_args(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_boss(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app,
        [
            "boss", "research", "collect",
            "--search-results", "agentic/fixtures/boss-idea-response/valid-market-search-results.yaml",
            "--output", "agentic/runs/boss-run/market-research.md",
            "--run-id", "boss-run",
        ],
    )
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "collect-boss-idea-research.sh"
    assert "--search-results" in call.args
    assert "--output" in call.args


def test_boss_research_crawl(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_boss(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app,
        ["boss", "research", "crawl", "--force", "--run-id", "boss-run"],
    )
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "crawl-boss-idea-market.sh"
    assert "--force" in call.args
    assert "--from-query-pack" in call.args
    assert "--search-provider" in call.args


def test_boss_research_brief(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_boss(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["boss", "research", "brief", "--run-id", "boss-run"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "generate-boss-idea-competitor-brief.sh"
    assert "boss-run" in call.args


def test_boss_research_preflight(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_boss(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["boss", "research", "preflight", "--run-id", "boss-run"])
    assert result.exit_code == 0, result.output
    assert runner.calls[-1].name == "boss-idea-searxng-preflight.sh"


def test_boss_research_live_smoke(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_boss(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["boss", "research", "live-smoke", "--run-id", "boss-run"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "run-boss-idea-live-smoke.sh"
    assert "--live" in call.args
    assert "--force" in call.args
    assert "boss-run" in call.args


def test_boss_score_dry_run(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_boss(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["boss", "score", "--dry-run", "--run-id", "boss-run"])
    assert result.exit_code == 0, result.output
    assert runner.calls[-1].name == "score-boss-idea-feasibility.sh"
    assert "--dry-run" in runner.calls[-1].args


def test_boss_memo_generate(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_boss(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["boss", "memo", "generate", "--run-id", "boss-run"])
    assert result.exit_code == 0, result.output
    assert runner.calls[-1].name == "generate-boss-decision-memo.sh"


def test_boss_poc_plan(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_boss(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["boss", "poc", "plan", "--run-id", "boss-run"])
    assert result.exit_code == 0, result.output
    assert runner.calls[-1].name == "plan-boss-idea-poc-mvp.sh"


def test_boss_decision_record(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_boss(tmp_path)
    monkeypatch.chdir(repo)
    (repo / "decision.yaml").write_text("decision:\n")
    result = cli.invoke(
        app,
        ["boss", "decision", "record", "decision.yaml", "--run-id", "boss-run"],
    )
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "record-boss-idea-decision.sh"
    assert "decision.yaml" in call.args
    assert "--run-id" in call.args
    assert "boss-run" in call.args


def test_boss_provider_health(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_boss(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app,
        [
            "boss", "provider", "health",
            "--output", "agentic/runs/boss-run/provider-health.yaml",
            "--run-id", "boss-run",
        ],
    )
    assert result.exit_code == 0, result.output
    assert runner.calls[-1].name == "summarize-boss-idea-provider-health.sh"


def test_boss_provider_fallback(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_boss(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app,
        [
            "boss", "provider", "fallback", "health.yaml",
            "--output", "advisory.yaml",
            "--run-id", "boss-run",
        ],
    )
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "recommend-boss-idea-provider-fallback.sh"
    assert "health.yaml" in call.args
    assert "--output" in call.args
    assert "advisory.yaml" in call.args


def test_boss_validate_unknown_kind_exits_2(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_boss(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["boss", "validate", "nope", "thing", "--run-id", "boss-run"])
    assert result.exit_code == 2


def test_boss_validate_missing_kind_exits_2(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_boss(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["boss", "validate"])
    assert result.exit_code == 2


@pytest.mark.parametrize(
    "kind,script",
    [
        ("research", "validate-boss-idea-research.sh"),
        ("competitor", "validate-boss-idea-competitor-brief.sh"),
        ("crawl", "validate-boss-idea-crawl-log.sh"),
        ("quality", "validate-boss-idea-market-discovery-quality.sh"),
        ("poc-mvp", "validate-boss-idea-poc-mvp.sh"),
        ("metrics", "validate-boss-idea-success-metrics.sh"),
        ("memo", "validate-boss-decision-memo.sh"),
        ("decision", "validate-boss-idea-decision.sh"),
        ("provider-health", "validate-boss-idea-provider-health.sh"),
        ("provider-events", "validate-boss-idea-provider-health-events.sh"),
        ("fallback-advisory", "validate-boss-idea-provider-fallback-advisory.sh"),
    ],
)
def test_boss_validate_dispatch(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
    kind: str,
    script: str,
) -> None:
    repo = _seed_boss(tmp_path)
    monkeypatch.chdir(repo)
    (repo / "thing").write_text("x")
    result = cli.invoke(app, ["boss", "validate", kind, "thing", "--run-id", "boss-run"])
    assert result.exit_code == 0, result.output
    assert runner.calls[-1].name == script
    assert "thing" in runner.calls[-1].args


def test_boss_validate_run_competitor_kind(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_boss(tmp_path)
    monkeypatch.chdir(repo)
    (repo / "thing").write_text("x")
    result = cli.invoke(
        app, ["boss", "validate", "run-competitor", "thing", "--run-id", "boss-run"]
    )
    assert result.exit_code == 0, result.output
    assert runner.calls[-1].name == "validate-boss-idea-run-competitor-brief.sh"


def test_boss_init_with_actor_role(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_boss(tmp_path)
    monkeypatch.chdir(repo)
    (repo / "idea.md").write_text("# idea\n")
    result = cli.invoke(
        app,
        [
            "--actor", "alice", "--role", "operator",
            "boss", "init", "idea.md", "--run-id", "boss-run",
        ],
    )
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.env["AIT_ACTOR"] == "alice"
    assert call.env["AIT_ACTOR_ROLE"] == "operator"
