# CLI-08: `agentic boss` Namespace Implementation Plan

> **For agentic-delivery pipeline:** Implementer = agency-agents Staff+. Reviewer = Claude Code CLI via AIT. Write scope `cli/**`.

**Goal:** Cover all 28 boss-idea-response scripts under the `agentic boss` Typer sub-app per spec §5.4, including the consolidated `boss validate <kind>` group that absorbs 11 validators.

**Architecture:** `cli/agentic/commands/boss.py` declares `boss` as the namespace with sub-apps `research`, `memo`, `poc`, `decision`, `provider`, `validate`. Each leaf shells out via the shared helpers from CLI-07. The validate sub-app routes by `<kind>` argument so the user types `agentic boss validate research <md>` instead of `agentic boss validate-research <md>`.

**Tech Stack:** typer, shared helpers from `cli/agentic/commands/_shell_helpers.py`.

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `cli/agentic/commands/boss.py` | Create | `boss` sub-app + sub-sub-apps. |
| `cli/agentic/app.py` | Modify | Register `boss`. |
| `cli/tests/test_commands_boss.py` | Create | Routing tests for all 28 scripts. |

---

## Task 1: TDD — research / memo / poc / decision / provider

**Files:**
- Create: `cli/agentic/commands/boss.py`
- Modify: `cli/agentic/app.py`
- Create: `cli/tests/test_commands_boss.py`

- [ ] **Step 1: Write failing tests `cli/tests/test_commands_boss.py`**

```python
from pathlib import Path

import pytest

from agentic.app import app
from agentic.commands import boss as boss_cmd
from tests._recording import RecordingRunner


def _seed_boss(tmp_path: Path, run_id: str = "boss-run") -> Path:
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    d = tmp_path / "agentic" / "runs" / run_id
    d.mkdir(parents=True)
    (d / "manifest.yaml").write_text("run:\n  id: " + run_id + "\n  mode: planning\n  profile: boss-idea-response\n")
    return tmp_path


@pytest.fixture
def runner(monkeypatch):
    rr = RecordingRunner()
    monkeypatch.setattr(boss_cmd, "_runner_factory", lambda repo: rr)
    return rr


def test_boss_init(cli, tmp_path, monkeypatch, runner):
    repo = _seed_boss(tmp_path)
    monkeypatch.chdir(repo)
    (repo / "idea.md").write_text("# idea\n")
    result = cli.invoke(app, ["boss", "init", "idea.md", "--run-id", "boss-run"])
    assert result.exit_code == 0
    assert runner.calls[-1].name == "init-boss-idea-run.sh"
    assert "idea.md" in runner.calls[-1].args


def test_boss_research_collect_forwards_args(cli, tmp_path, monkeypatch, runner):
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
    assert result.exit_code == 0
    call = runner.calls[-1]
    assert call.name == "collect-boss-idea-research.sh"
    assert "--search-results" in call.args
    assert "--output" in call.args


def test_boss_score_dry_run(cli, tmp_path, monkeypatch, runner):
    repo = _seed_boss(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["boss", "score", "--dry-run", "--run-id", "boss-run"])
    assert result.exit_code == 0
    assert runner.calls[-1].name == "score-boss-idea-feasibility.sh"
    assert "--dry-run" in runner.calls[-1].args


def test_boss_memo_generate(cli, tmp_path, monkeypatch, runner):
    repo = _seed_boss(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["boss", "memo", "generate", "--run-id", "boss-run"])
    assert result.exit_code == 0
    assert runner.calls[-1].name == "generate-boss-decision-memo.sh"


def test_boss_decision_record(cli, tmp_path, monkeypatch, runner):
    repo = _seed_boss(tmp_path)
    monkeypatch.chdir(repo)
    (repo / "decision.yaml").write_text("decision:\n")
    result = cli.invoke(
        app,
        ["boss", "decision", "record", "decision.yaml", "--run-id", "boss-run"],
    )
    assert result.exit_code == 0
    call = runner.calls[-1]
    assert call.name == "record-boss-idea-decision.sh"
    assert "decision.yaml" in call.args
    assert "--run-id" in call.args
    assert "boss-run" in call.args


def test_boss_provider_health(cli, tmp_path, monkeypatch, runner):
    repo = _seed_boss(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app,
        ["boss", "provider", "health", "--output", "agentic/runs/boss-run/provider-health.yaml",
         "--run-id", "boss-run"],
    )
    assert result.exit_code == 0
    assert runner.calls[-1].name == "summarize-boss-idea-provider-health.sh"


@pytest.mark.parametrize("kind,script", [
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
])
def test_boss_validate_dispatch(cli, tmp_path, monkeypatch, runner, kind, script):
    repo = _seed_boss(tmp_path)
    monkeypatch.chdir(repo)
    (repo / "thing").write_text("x")
    result = cli.invoke(app, ["boss", "validate", kind, "thing", "--run-id", "boss-run"])
    assert result.exit_code == 0
    assert runner.calls[-1].name == script
    assert "thing" in runner.calls[-1].args
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd cli && pytest tests/test_commands_boss.py -q
```

- [ ] **Step 3: Implement `cli/agentic/commands/boss.py`**

```python
"""`agentic boss ...` subcommands (boss-idea-response profile)."""

from __future__ import annotations

from typing import Annotated

import typer

from agentic.commands._shell_helpers import default_factory as _runner_factory
from agentic.commands._shell_helpers import invoke as _invoke
from agentic.commands._shell_helpers import resolve as _resolve

app = typer.Typer(name="boss", help="Boss-idea-response profile.")

research = typer.Typer(help="Market research operations.")
app.add_typer(research, name="research")

memo = typer.Typer(help="Decision memo.")
app.add_typer(memo, name="memo")

poc = typer.Typer(help="POC / MVP planning.")
app.add_typer(poc, name="poc")

decision = typer.Typer(help="Decision recording.")
app.add_typer(decision, name="decision")

provider = typer.Typer(help="Provider health + fallback advisory.")
app.add_typer(provider, name="provider")

validate = typer.Typer(help="Boss-idea artifact validators.")
app.add_typer(validate, name="validate")


@app.command("init")
def boss_init(
    ctx: typer.Context,
    idea_file: str,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    _invoke(ctx, name="init-boss-idea-run.sh", args=[idea_file],
            run_id_flag=run_id, factory=_runner_factory)


@app.command("score")
def boss_score(
    ctx: typer.Context,
    dry_run: Annotated[bool, typer.Option("--dry-run")] = False,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    _, rid, _ = _resolve(ctx, run_id)
    args = ["--dry-run"] if dry_run else []
    args.append(rid)
    _invoke(ctx, name="score-boss-idea-feasibility.sh", args=args,
            run_id_flag=run_id, factory=_runner_factory)


@research.command("collect")
def research_collect(
    ctx: typer.Context,
    search_results: Annotated[str, typer.Option("--search-results")],
    output: Annotated[str, typer.Option("--output")],
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    _, rid, _ = _resolve(ctx, run_id)
    _invoke(ctx, name="collect-boss-idea-research.sh",
            args=[rid, "--search-results", search_results, "--output", output],
            run_id_flag=run_id, factory=_runner_factory)


@research.command("crawl")
def research_crawl(
    ctx: typer.Context,
    from_query_pack: Annotated[bool, typer.Option("--from-query-pack")] = True,
    search_provider: Annotated[str, typer.Option("--search-provider")] = "fixture",
    output: Annotated[str | None, typer.Option("--output")] = None,
    force: Annotated[bool, typer.Option("--force")] = False,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    _, rid, _ = _resolve(ctx, run_id)
    args = []
    if force:
        args.append("--force")
    args.append(rid)
    if from_query_pack:
        args.append("--from-query-pack")
    args.extend(["--search-provider", search_provider])
    if output:
        args.extend(["--output", output])
    _invoke(ctx, name="crawl-boss-idea-market.sh", args=args,
            run_id_flag=run_id, factory=_runner_factory)


@research.command("brief")
def research_brief(
    ctx: typer.Context,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    _, rid, _ = _resolve(ctx, run_id)
    _invoke(ctx, name="generate-boss-idea-competitor-brief.sh", args=[rid],
            run_id_flag=run_id, factory=_runner_factory)


@research.command("preflight")
def research_preflight(
    ctx: typer.Context,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    _invoke(ctx, name="boss-idea-searxng-preflight.sh", args=[],
            run_id_flag=run_id, factory=_runner_factory)


@research.command("live-smoke")
def research_live_smoke(
    ctx: typer.Context,
    live: Annotated[bool, typer.Option("--live")] = True,
    force: Annotated[bool, typer.Option("--force")] = True,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    _, rid, _ = _resolve(ctx, run_id)
    args = []
    if live:
        args.append("--live")
    if force:
        args.append("--force")
    args.append(rid)
    _invoke(ctx, name="run-boss-idea-live-smoke.sh", args=args,
            run_id_flag=run_id, factory=_runner_factory)


@memo.command("generate")
def memo_generate(
    ctx: typer.Context,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    _, rid, _ = _resolve(ctx, run_id)
    _invoke(ctx, name="generate-boss-decision-memo.sh", args=[rid],
            run_id_flag=run_id, factory=_runner_factory)


@poc.command("plan")
def poc_plan(
    ctx: typer.Context,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    _, rid, _ = _resolve(ctx, run_id)
    _invoke(ctx, name="plan-boss-idea-poc-mvp.sh", args=[rid],
            run_id_flag=run_id, factory=_runner_factory)


@decision.command("record")
def decision_record(
    ctx: typer.Context,
    decision_yaml: str,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    _, rid, _ = _resolve(ctx, run_id)
    _invoke(ctx, name="record-boss-idea-decision.sh",
            args=[decision_yaml, "--run-id", rid],
            run_id_flag=run_id, factory=_runner_factory)


@provider.command("health")
def provider_health(
    ctx: typer.Context,
    output: Annotated[str | None, typer.Option("--output")] = None,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    _, rid, _ = _resolve(ctx, run_id)
    args = []
    if output:
        args.extend(["--output", output])
    args.append(rid)
    _invoke(ctx, name="summarize-boss-idea-provider-health.sh", args=args,
            run_id_flag=run_id, factory=_runner_factory)


@provider.command("fallback")
def provider_fallback(
    ctx: typer.Context,
    health_input: Annotated[str, typer.Argument()],
    output: Annotated[str | None, typer.Option("--output")] = None,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    args = []
    if output:
        args.extend(["--output", output])
    args.append(health_input)
    _invoke(ctx, name="recommend-boss-idea-provider-fallback.sh", args=args,
            run_id_flag=run_id, factory=_runner_factory)


_VALIDATE_MAP = {
    "research": "validate-boss-idea-research.sh",
    "competitor": "validate-boss-idea-competitor-brief.sh",
    "run-competitor": "validate-boss-idea-run-competitor-brief.sh",
    "crawl": "validate-boss-idea-crawl-log.sh",
    "quality": "validate-boss-idea-market-discovery-quality.sh",
    "poc-mvp": "validate-boss-idea-poc-mvp.sh",
    "metrics": "validate-boss-idea-success-metrics.sh",
    "memo": "validate-boss-decision-memo.sh",
    "decision": "validate-boss-idea-decision.sh",
    "provider-health": "validate-boss-idea-provider-health.sh",
    "provider-events": "validate-boss-idea-provider-health-events.sh",
    "fallback-advisory": "validate-boss-idea-provider-fallback-advisory.sh",
}


@validate.callback(invoke_without_command=True)
def validate_dispatch(
    ctx: typer.Context,
    kind: Annotated[str | None, typer.Argument()] = None,
    target: Annotated[str | None, typer.Argument()] = None,
    second: Annotated[str | None, typer.Argument()] = None,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    """boss validate <kind> <target> [<second>] — dispatch to the underlying validator."""
    if kind is None:
        typer.echo("usage: agentic boss validate <kind> <target> [<second>]", err=True)
        raise typer.Exit(code=2)
    script = _VALIDATE_MAP.get(kind)
    if script is None:
        typer.echo(f"x  unknown validate kind {kind!r}; known: {sorted(_VALIDATE_MAP)}", err=True)
        raise typer.Exit(code=2)
    args = [a for a in (target, second) if a is not None]
    _invoke(ctx, name=script, args=args, run_id_flag=run_id, factory=_runner_factory)
```

- [ ] **Step 4: Register in `cli/agentic/app.py`**

```python
from agentic.commands import boss as boss_cmd
app.add_typer(boss_cmd.app, name="boss")
```

- [ ] **Step 5: Run — expect PASS**

```bash
cd cli && pytest tests/test_commands_boss.py -q
```

Expected: 6 baseline tests + 11 validate parametrize = 17 passing.

- [ ] **Step 6: Lint + type**

```bash
cd cli && ruff check agentic tests && mypy --strict agentic
```

- [ ] **Step 7: Commit**

```bash
git add cli/agentic/commands/boss.py cli/agentic/app.py cli/tests/test_commands_boss.py
git commit -m "feat(cli): agentic boss namespace (28 scripts)"
```

---

## Acceptance Criteria (from spec §13 CLI-08)

- All 28 boss-idea scripts reachable through `agentic boss …`.
- `boss validate <kind>` dispatches 11 validators.
- `--actor`/`--role` propagated for any subcommand that needs them.

## Implementer / Reviewer

- **Implementer:** agency-agents Staff+ — `staff-software-engineer`.
- **Reviewer:** Claude Code CLI via AIT — `engineering-software-architect`, `engineering-code-reviewer`.

Evidence under `agentic/reviews/agentic-cli/CLI-08/`.

## Rollback

```bash
git revert <CLI-08 commits>
```
