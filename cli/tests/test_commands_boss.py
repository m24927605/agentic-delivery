"""Routing tests for `agentic boss ...` via the RecordingRunner."""

from __future__ import annotations

from pathlib import Path

import pytest
from typer.testing import CliRunner

from agentic.app import app
from agentic.commands import boss as boss_cmd
from tests._recording import RecordingRunner


def _seed_repo_only(tmp_path: Path) -> Path:
    """Seed only the repo marker (pipeline.yaml). No run directory.

    Used by commands that must work without a pre-existing run — ``init``
    (which CREATES a run), ``research preflight`` (env-only), validators
    (artifact paths only), ``score`` / ``poc plan`` / ``provider fallback``
    (positional artifact args).
    """
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    return tmp_path


def _seed_boss(tmp_path: Path, run_id: str = "boss-run") -> Path:
    _seed_repo_only(tmp_path)
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
    repo = _seed_repo_only(tmp_path)
    monkeypatch.chdir(repo)
    (repo / "idea.md").write_text("# idea\n")
    result = cli.invoke(app, ["boss", "init", "idea.md"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "init-boss-idea-run.sh"
    # init CREATES the run; the script accepts the idea path as positional
    # without --run-id (the script's "--goal-file" form is not required).
    assert call.args == ("idea.md",)


def test_boss_init_works_without_existing_run(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    """Regression: init must work in a fresh repo with no agentic/runs/."""
    repo = _seed_repo_only(tmp_path)
    monkeypatch.chdir(repo)
    (repo / "idea.md").write_text("# idea\n")
    assert not (repo / "agentic" / "runs").exists()
    result = cli.invoke(app, ["boss", "init", "idea.md"])
    assert result.exit_code == 0, result.output


def test_boss_init_dry_run_forwards_flag(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_repo_only(tmp_path)
    monkeypatch.chdir(repo)
    (repo / "idea.md").write_text("# idea\n")
    result = cli.invoke(app, ["boss", "init", "--dry-run", "idea.md"])
    assert result.exit_code == 0, result.output
    assert runner.calls[-1].args == ("--dry-run", "idea.md")


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


def test_boss_research_preflight_no_run_required(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    """preflight is env-only; it must work in a repo with no runs."""
    repo = _seed_repo_only(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["boss", "research", "preflight"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "boss-idea-searxng-preflight.sh"
    assert call.args == ()
    # invoke_no_run does not export RUN_ID
    assert "RUN_ID" not in call.env


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


def test_boss_score_forwards_scorecard_positional(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    """score takes <scorecard.yaml> positional, not a run id."""
    repo = _seed_repo_only(tmp_path)
    monkeypatch.chdir(repo)
    (repo / "scorecard.yaml").write_text("scorecard: {}\n")
    result = cli.invoke(app, ["boss", "score", "--scorecard", "scorecard.yaml"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "score-boss-idea-feasibility.sh"
    assert call.args == ("scorecard.yaml",)


def test_boss_score_dry_run_orders_args_correctly(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_repo_only(tmp_path)
    monkeypatch.chdir(repo)
    (repo / "scorecard.yaml").write_text("scorecard: {}\n")
    result = cli.invoke(
        app, ["boss", "score", "--dry-run", "--scorecard", "scorecard.yaml"]
    )
    assert result.exit_code == 0, result.output
    # Script accepts: [--dry-run] <scorecard.yaml>
    assert runner.calls[-1].args == ("--dry-run", "scorecard.yaml")


def test_boss_score_requires_scorecard(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_repo_only(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["boss", "score"])
    # typer raises a usage error (exit code 2) when --scorecard is missing.
    assert result.exit_code == 2


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


@pytest.mark.parametrize("work_type", ["poc", "mvp"])
def test_boss_poc_plan_forwards_work_type(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
    work_type: str,
) -> None:
    """plan-boss-idea-poc-mvp.sh takes [poc|mvp] positional, not a run id."""
    repo = _seed_repo_only(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["boss", "poc", "plan", "--work-type", work_type])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "plan-boss-idea-poc-mvp.sh"
    assert call.args == (work_type,)


def test_boss_poc_plan_defaults_to_poc(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_repo_only(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["boss", "poc", "plan"])
    assert result.exit_code == 0, result.output
    assert runner.calls[-1].args == ("poc",)


def test_boss_poc_plan_rejects_unknown_work_type(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_repo_only(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["boss", "poc", "plan", "--work-type", "spike"])
    assert result.exit_code == 2
    assert not runner.calls


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


def test_boss_provider_fallback_no_run_required(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    """fallback takes only a health-input path (and optional --output); no run id."""
    repo = _seed_repo_only(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app,
        [
            "boss", "provider", "fallback", "health.yaml",
            "--output", "advisory.yaml",
        ],
    )
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "recommend-boss-idea-provider-fallback.sh"
    # Script's documented usage: --output <advisory> <health.yaml>
    assert call.args == ("--output", "advisory.yaml", "health.yaml")
    assert "RUN_ID" not in call.env


def test_boss_provider_fallback_without_output(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_repo_only(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["boss", "provider", "fallback", "health.yaml"])
    assert result.exit_code == 0, result.output
    assert runner.calls[-1].args == ("health.yaml",)


def test_boss_validate_unknown_kind_exits_2(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_repo_only(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["boss", "validate", "nope", "thing"])
    assert result.exit_code == 2


def test_boss_validate_missing_kind_exits_2(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_repo_only(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["boss", "validate"])
    assert result.exit_code == 2


def test_boss_validate_missing_target_exits_2(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    """validators always need at least one positional artifact path."""
    repo = _seed_repo_only(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["boss", "validate", "research"])
    assert result.exit_code == 2
    assert not runner.calls


@pytest.mark.parametrize(
    "kind,script",
    [
        ("research", "validate-boss-idea-research.sh"),
        ("competitor", "validate-boss-idea-competitor-brief.sh"),
        ("run-competitor", "validate-boss-idea-run-competitor-brief.sh"),
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
    """Validators take artifact path(s) only — they must dispatch without a run."""
    repo = _seed_repo_only(tmp_path)
    monkeypatch.chdir(repo)
    (repo / "thing").write_text("x")
    result = cli.invoke(app, ["boss", "validate", kind, "thing"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == script
    assert call.args == ("thing",)
    # Validators don't take RUN_ID; invoke_no_run must not export it.
    assert "RUN_ID" not in call.env


def test_boss_validate_run_competitor_two_positionals(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    """run-competitor validator takes <run-id> <brief-file> per script usage."""
    repo = _seed_repo_only(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app, ["boss", "validate", "run-competitor", "boss-run", "brief.md"]
    )
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "validate-boss-idea-run-competitor-brief.sh"
    assert call.args == ("boss-run", "brief.md")


def test_boss_init_with_actor_role(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed_repo_only(tmp_path)
    monkeypatch.chdir(repo)
    (repo / "idea.md").write_text("# idea\n")
    result = cli.invoke(
        app,
        [
            "--actor", "alice", "--role", "operator",
            "boss", "init", "idea.md",
        ],
    )
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.env["AIT_ACTOR"] == "alice"
    assert call.env["AIT_ACTOR_ROLE"] == "operator"
