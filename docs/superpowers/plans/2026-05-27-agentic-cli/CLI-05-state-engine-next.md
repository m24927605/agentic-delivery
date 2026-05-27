# CLI-05: State Engine v1 + `agentic next` Implementation Plan

> **For agentic-delivery pipeline:** Implementer = agency-agents Staff+. Reviewer = Claude Code CLI via AIT. Write scope `cli/**`.

**Goal:** Build a declarative rule-driven state engine that, given a Manifest, suggests the next CLI command, and expose it via `agentic next`. Read-only against manifests.

**Architecture:** Per spec §6. Rules in `cli/agentic/state_engine/rules.yaml` (packaged) + optional user override at `$XDG_CONFIG_HOME/agentic/state_rules.yaml`. Conditions are a closed set of primitives. Templates rendered with `str.format`.

**Tech Stack:** pyyaml, fnmatch, standard library.

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `cli/agentic/state_engine/__init__.py` | Create | Public API: `evaluate`. |
| `cli/agentic/state_engine/primitives.py` | Create | Closed set of condition primitives. |
| `cli/agentic/state_engine/engine.py` | Create | Rule loader, evaluator, template renderer. |
| `cli/agentic/state_engine/rules.yaml` | Create | Default rule table. |
| `cli/agentic/commands/next.py` | Create | `agentic next` command. |
| `cli/agentic/app.py` | Modify | Register `next`. |
| `cli/tests/state_engine/__init__.py` | Create | Empty. |
| `cli/tests/state_engine/test_primitives.py` | Create | Primitive unit tests. |
| `cli/tests/state_engine/test_engine.py` | Create | Rule eval + template render. |
| `cli/tests/state_engine/fixtures/` | Create | 15+ Manifest fixtures matching spec §10.2. |
| `cli/tests/test_next_command.py` | Create | CLI tests. |

---

## Task 1: TDD — primitives

**Files:**
- Create: `cli/agentic/state_engine/__init__.py` (empty)
- Create: `cli/agentic/state_engine/primitives.py`
- Create: `cli/tests/state_engine/__init__.py` (empty)
- Create: `cli/tests/state_engine/test_primitives.py`

- [ ] **Step 1: Write failing primitive tests `cli/tests/state_engine/test_primitives.py`**

```python
from agentic.manifest import Artifact, Manifest, Task
from agentic.state_engine.primitives import REGISTRY


def _planning(state: str, artifacts: list[tuple[str, str]]) -> Manifest:
    return Manifest(
        id="x", mode="planning", profile="default-delivery",
        state=state, updated_at=None,
        artifacts=tuple(Artifact(path=p, status=s) for p, s in artifacts),
    )


def test_state_matches_glob():
    m = _planning("blocked_strategy_conflict", [])
    fn = REGISTRY["state_matches"]
    assert fn(m, "blocked_*") is True
    assert fn(m, "ready_*") is False


def test_has_artifact_with_status():
    m = _planning("any", [("a.md", "drafted")])
    fn = REGISTRY["has_artifact_with_status"]
    assert fn(m, "drafted") is True
    assert fn(m, "approved") is False


def test_not_has_artifact_with_status():
    m = _planning("any", [("a.md", "drafted")])
    fn = REGISTRY["not_has_artifact_with_status"]
    assert fn(m, "approved") is True
    assert fn(m, "drafted") is False


def test_count_artifacts_with_status_min():
    m = _planning("any", [("a.md", "approved"), ("b.md", "approved")])
    fn = REGISTRY["count_artifacts_with_status"]
    assert fn(m, {"status": "approved", "min": 1}) is True
    assert fn(m, {"status": "approved", "min": 3}) is False


def test_all_artifacts_terminal():
    m_yes = _planning(
        "any",
        [("a.md", "approved"), ("b.md", "rejected"), ("c.md", "deferred")],
    )
    m_no = _planning("any", [("a.md", "approved"), ("b.md", "drafted")])
    fn = REGISTRY["all_artifacts_terminal"]
    assert fn(m_yes, True) is True
    assert fn(m_no, True) is False
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd cli && pytest tests/state_engine/test_primitives.py -q
```

- [ ] **Step 3: Implement `cli/agentic/state_engine/primitives.py`**

```python
"""Closed set of condition primitives the state engine knows."""

from __future__ import annotations

import fnmatch
from typing import Any, Callable

from agentic.manifest import Manifest

Primitive = Callable[[Manifest, Any], bool]
REGISTRY: dict[str, Primitive] = {}


def _register(name: str) -> Callable[[Primitive], Primitive]:
    def deco(fn: Primitive) -> Primitive:
        REGISTRY[name] = fn
        return fn
    return deco


@_register("state_matches")
def _state_matches(m: Manifest, glob: str) -> bool:
    return fnmatch.fnmatch(m.state, glob)


@_register("mode_is")
def _mode_is(m: Manifest, mode: str) -> bool:
    return m.mode == mode


@_register("has_artifact_with_status")
def _has_artifact_with_status(m: Manifest, status: str) -> bool:
    return m.count_artifacts(status=status) >= 1


@_register("not_has_artifact_with_status")
def _not_has_artifact_with_status(m: Manifest, status: str) -> bool:
    return m.count_artifacts(status=status) == 0


@_register("count_artifacts_with_status")
def _count_artifacts_with_status(m: Manifest, spec: dict[str, Any]) -> bool:
    n = m.count_artifacts(status=spec["status"])
    lo = spec.get("min")
    hi = spec.get("max")
    if lo is not None and n < lo:
        return False
    if hi is not None and n > hi:
        return False
    return True


TERMINAL = {"approved", "rejected", "deferred"}


@_register("all_artifacts_terminal")
def _all_artifacts_terminal(m: Manifest, _: Any) -> bool:
    if not m.artifacts:
        return False
    return all(a.status in TERMINAL for a in m.artifacts)


@_register("has_task_with_status")
def _has_task_with_status(m: Manifest, status: str) -> bool:
    return m.count_tasks(status=status) >= 1


@_register("task_graph_exists")
def _task_graph_exists(m: Manifest, want: bool) -> bool:
    return bool(m.tasks) == want


@_register("all_tasks_reviewed")
def _all_tasks_reviewed(m: Manifest, _: Any) -> bool:
    if not m.tasks:
        return False
    return all(t.status in ("reviewed", "approved") for t in m.tasks)


@_register("has_artifact_at")
def _has_artifact_at(m: Manifest, rel: str) -> bool:
    return any(a.path.endswith(rel) for a in m.artifacts)


@_register("not_has_artifact_at")
def _not_has_artifact_at(m: Manifest, rel: str) -> bool:
    return not any(a.path.endswith(rel) for a in m.artifacts)
```

- [ ] **Step 4: Run — expect PASS**

```bash
cd cli && pytest tests/state_engine/test_primitives.py -q
```

Expected: 5 passed.

- [ ] **Step 5: Commit**

```bash
git add cli/agentic/state_engine/__init__.py cli/agentic/state_engine/primitives.py cli/tests/state_engine/
git commit -m "feat(cli): state-engine condition primitives"
```

---

## Task 2: TDD — rule engine + template render

**Files:**
- Create: `cli/agentic/state_engine/engine.py`
- Create: `cli/agentic/state_engine/rules.yaml`
- Create: `cli/tests/state_engine/test_engine.py`
- Create: 15 fixtures under `cli/tests/state_engine/fixtures/`

- [ ] **Step 1: Write `cli/agentic/state_engine/rules.yaml`** with the full table from spec §6.2 (verbatim). The implementer copies that block exactly — do not paraphrase, do not condense.

- [ ] **Step 2: Write all 15 manifest fixtures** under `cli/tests/state_engine/fixtures/` matching the table in spec §10.2.

Example — `cli/tests/state_engine/fixtures/planning_fresh_init.yaml`:

```yaml
run:
  id: x
  mode: planning
  profile: default-delivery
  state: artifact_plan_created
artifacts:
  - { path: a.md, status: planned }
  - { path: b.md, status: planned }
```

(Each fixture is small. Implementer writes one for every rule id listed in `rules.yaml` plus `terminal_unknown.yaml` for fallback.)

- [ ] **Step 3: Write failing tests `cli/tests/state_engine/test_engine.py`**

```python
from pathlib import Path

import pytest
import yaml

from agentic.manifest import Manifest, Artifact, Task
from agentic.state_engine.engine import evaluate, load_rules


FIXTURES = Path(__file__).parent / "fixtures"


def _manifest_from_fixture(name: str) -> Manifest:
    data = yaml.safe_load((FIXTURES / name).read_text())
    run = data.get("run", {})
    arts = tuple(
        Artifact(path=a["path"], status=a["status"], updated_at=a.get("updated_at"))
        for a in data.get("artifacts", [])
    )
    tasks = tuple(
        Task(id=t["id"], status=t["status"], updated_at=t.get("updated_at"))
        for t in data.get("tasks", [])
    )
    return Manifest(
        id=run.get("id", "x"),
        mode=run.get("mode", "planning"),
        profile=run.get("profile", "default-delivery"),
        state=run.get("state", "unknown"),
        updated_at=run.get("updated_at"),
        artifacts=arts,
        tasks=tasks,
    )


@pytest.mark.parametrize("fixture,expected_rule", [
    ("planning_fresh_init.yaml", "planning-need-drafts"),
    ("planning_mixed_drafts.yaml", "planning-need-review"),
    ("planning_one_reviewed.yaml", "planning-need-approval"),
    ("planning_changes_requested.yaml", "planning-changes-requested"),
    ("planning_all_terminal_approved.yaml", "planning-ready-for-impl"),
    ("planning_all_terminal_rejected.yaml", "fallback"),
    ("impl_no_task_graph.yaml", "impl-need-task-graph"),
    ("impl_pending_task.yaml", "impl-dispatch"),
    ("impl_dispatched_task.yaml", "impl-execute"),
    ("impl_executed_task.yaml", "impl-review"),
    ("impl_all_reviewed.yaml", "impl-validate"),
    ("boss_no_research.yaml", "boss-need-research"),
    ("boss_research_no_brief.yaml", "boss-need-brief"),
    ("blocked_strategy_conflict.yaml", "blocked-state"),
    ("terminal_unknown.yaml", "fallback"),
])
def test_rule_matches(fixture, expected_rule):
    rules = load_rules()
    result = evaluate(rules, _manifest_from_fixture(fixture))
    assert result.rule_id == expected_rule


def test_suggest_template_renders():
    rules = load_rules()
    m = _manifest_from_fixture("planning_mixed_drafts.yaml")
    result = evaluate(rules, m)
    assert "{" not in result.suggest, f"unresolved template var: {result.suggest!r}"
```

- [ ] **Step 4: Run — expect FAIL**

```bash
cd cli && pytest tests/state_engine/test_engine.py -q
```

- [ ] **Step 5: Implement `cli/agentic/state_engine/engine.py`**

```python
"""Rule loader and evaluator for the agentic CLI state engine."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

from agentic.manifest import Manifest
from agentic.state_engine.primitives import REGISTRY

DEFAULT_RULES = Path(__file__).resolve().parent / "rules.yaml"


@dataclass(frozen=True)
class Rule:
    id: str
    priority: int
    applies_to: str | None
    when: list[dict[str, Any]]
    suggest: str
    reason: str


@dataclass(frozen=True)
class Decision:
    rule_id: str
    suggest: str
    reason: str


def _xdg_override() -> Path | None:
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    candidate = Path(base) / "agentic" / "state_rules.yaml"
    return candidate if candidate.is_file() else None


def load_rules() -> list[Rule]:
    data = yaml.safe_load(DEFAULT_RULES.read_text())
    rules = list(data.get("rules", []))
    override = _xdg_override()
    if override is not None:
        extra = yaml.safe_load(override.read_text()) or {}
        by_id = {r["id"]: i for i, r in enumerate(rules)}
        for r in extra.get("rules", []):
            if r["id"] in by_id:
                rules[by_id[r["id"]]] = r
            else:
                rules.append(r)
    parsed = [
        Rule(
            id=r["id"],
            priority=r.get("priority", 1000),
            applies_to=r.get("applies_to"),
            when=list(r.get("when", [])),
            suggest=r["suggest"],
            reason=r.get("reason", ""),
        )
        for r in rules
    ]
    parsed.sort(key=lambda r: r.priority)
    return parsed


def _match(rule: Rule, m: Manifest) -> bool:
    if rule.applies_to and rule.applies_to != m.mode:
        return False
    for clause in rule.when:
        if len(clause) != 1:
            raise ValueError(f"rule {rule.id}: each `when` clause must have one key")
        (key, value), = clause.items()
        if key not in REGISTRY:
            raise ValueError(f"rule {rule.id}: unknown primitive {key!r}")
        if not REGISTRY[key](m, value):
            return False
    return True


def _context(m: Manifest) -> dict[str, Any]:
    ctx: dict[str, Any] = {
        "run_id": m.id,
        "state": m.state,
        "mode": m.mode,
    }
    for s in ("planned", "drafted", "reviewed", "changes_requested", "approved", "rejected", "deferred"):
        ctx[f"count_{s}"] = m.count_artifacts(status=s)
        first = m.first_artifact(status=s)
        if first is not None:
            ctx[f"first_{s}"] = _Attr(path=first.path)
    for s in ("pending", "dispatched", "executed", "reviewed"):
        ctx[f"count_task_{s}"] = m.count_tasks(status=s)
        ft = m.first_task(status=s)
        if ft is not None:
            ctx[f"first_{s}_task"] = _Attr(id=ft.id)
    ctx["list_planned_paths"] = "\n".join(
        f"  - {a.path}" for a in m.artifacts if a.status == "planned"
    )
    return ctx


class _Attr:
    """Simple attribute holder so templates can do {first_drafted.path}."""

    def __init__(self, **kw: Any) -> None:
        self.__dict__.update(kw)


def _render(template: str, ctx: dict[str, Any]) -> str:
    try:
        return template.format(**ctx)
    except (KeyError, AttributeError):
        return template


def evaluate(rules: list[Rule], m: Manifest) -> Decision:
    ctx = _context(m)
    for rule in rules:
        if _match(rule, m):
            return Decision(
                rule_id=rule.id,
                suggest=_render(rule.suggest, ctx),
                reason=_render(rule.reason, ctx),
            )
    raise RuntimeError("no rule matched and no fallback present — fix rules.yaml")
```

- [ ] **Step 6: Run — expect PASS**

```bash
cd cli && pytest tests/state_engine/ -q
```

Expected: 15+ rule fixtures + template test all pass.

- [ ] **Step 7: Commit**

```bash
git add cli/agentic/state_engine/ cli/tests/state_engine/
git commit -m "feat(cli): declarative state engine v1"
```

---

## Task 3: `agentic next` command

**Files:**
- Create: `cli/agentic/commands/next.py`
- Modify: `cli/agentic/app.py`
- Create: `cli/tests/test_next_command.py`

- [ ] **Step 1: Write failing tests `cli/tests/test_next_command.py`**

```python
from pathlib import Path

from agentic.app import app


def _seed(tmp_path: Path, fixture: str, run_id: str, impl: bool = False) -> Path:
    src = Path(__file__).parent / "state_engine" / "fixtures" / fixture
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    d = tmp_path / "agentic" / "runs" / run_id
    d.mkdir(parents=True)
    name = "implementation-manifest.yaml" if impl else "manifest.yaml"
    (d / name).write_text(src.read_text())
    return tmp_path


def test_next_text_for_planning_drafts(cli, tmp_path, monkeypatch):
    repo = _seed(tmp_path, "planning_fresh_init.yaml", "demo")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["next", "--run-id", "demo"])
    assert result.exit_code == 0
    assert "agentic plan generate" in result.stdout
    assert "planning-need-drafts" in result.stdout


def test_next_json(cli, tmp_path, monkeypatch):
    import json
    repo = _seed(tmp_path, "planning_fresh_init.yaml", "demo")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["--json", "next", "--run-id", "demo"])
    assert result.exit_code == 0
    payload = json.loads(result.stdout)
    assert payload["next"]["rule_id"] == "planning-need-drafts"
    assert "agentic plan generate" in payload["next"]["suggest"]
```

- [ ] **Step 2: Implement `cli/agentic/commands/next.py`**

```python
"""`agentic next` — suggest the next command."""

from __future__ import annotations

import json as _json
from typing import Annotated

import typer

from agentic.context import RepoNotFound, RunNotFound, resolve_repo, resolve_run_id
from agentic.manifest import load_manifest
from agentic.state_engine.engine import evaluate, load_rules

app = typer.Typer()


@app.callback(invoke_without_command=True)
def next_cmd(
    ctx: typer.Context,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    """Suggest the next command based on manifest state. Never executes."""
    try:
        flag = run_id or (ctx.obj.get("run_id_flag") if ctx.obj else None)
        repo = resolve_repo(repo_flag=ctx.obj.get("repo_flag") if ctx.obj else None).path
        run = resolve_run_id(repo=repo, flag=flag)
    except (RepoNotFound, RunNotFound) as e:
        typer.echo(f"x  {e}", err=True)
        raise typer.Exit(code=6)
    manifest = load_manifest(repo=repo, run_id=run.id)
    decision = evaluate(load_rules(), manifest)

    if ctx.obj and ctx.obj.get("json"):
        typer.echo(_json.dumps({
            "_schema": "agentic.cli/v1",
            "run": {"id": manifest.id, "mode": manifest.mode, "state": manifest.state},
            "next": {
                "rule_id": decision.rule_id,
                "suggest": decision.suggest,
                "reason": decision.reason,
            },
        }, indent=2))
        return

    typer.echo(f"Run:    {manifest.id}  ({manifest.mode})")
    typer.echo(f"State:  {manifest.state}")
    typer.echo("")
    typer.echo(f"Next:   {decision.suggest}")
    typer.echo(f"Why:    {decision.reason}")
    typer.echo(f"Rule:   {decision.rule_id}")
```

- [ ] **Step 3: Register in `cli/agentic/app.py`**

```python
from agentic.commands import next as next_cmd
app.add_typer(next_cmd.app, name="next")
```

- [ ] **Step 4: Run — expect PASS**

```bash
cd cli && pytest tests/test_next_command.py -q
```

- [ ] **Step 5: Lint + type**

```bash
cd cli && ruff check agentic tests && mypy --strict agentic
```

- [ ] **Step 6: Commit**

```bash
git add cli/agentic/commands/next.py cli/agentic/app.py cli/tests/test_next_command.py
git commit -m "feat(cli): agentic next (read-only suggestion)"
```

---

## Acceptance Criteria (from spec §13 CLI-05)

- `rules.yaml` matches spec §6.2 verbatim.
- Every rule has a fixture; engine selects the expected rule for each.
- Template variables resolve (no `{...}` placeholders left in `decision.suggest`).
- `agentic next` text + `--json` both work; rule id is exposed.
- Fallback rule always present.

## Implementer / Reviewer

- **Implementer:** agency-agents Staff+ — `staff-software-engineer`.
- **Reviewer:** Claude Code CLI via AIT — `engineering-software-architect`, `engineering-code-reviewer`, `product-manager` (suggested commands actually map to actions a user would take next).

Evidence under `agentic/reviews/agentic-cli/CLI-05/`.

## Rollback

```bash
git revert <CLI-05 commits>
```
