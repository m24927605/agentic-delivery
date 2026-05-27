"""Rule evaluator + template-render tests for the state engine.

Every rule id in ``rules.yaml`` has a fixture under ``fixtures/``. The
parametrised assertion locks the rule selection in place. Adding a new rule
without a fixture (and an entry here) will fail CI per spec §6.5.
"""

from __future__ import annotations

from pathlib import Path

import pytest
import yaml

from agentic.manifest import Artifact, Manifest, Task
from agentic.state_engine.engine import evaluate, load_rules


FIXTURES = Path(__file__).parent / "fixtures"


def _manifest_from_fixture(name: str) -> Manifest:
    data = yaml.safe_load((FIXTURES / name).read_text())
    run = data.get("run", {})
    arts = tuple(
        Artifact(path=a["path"], status=a["status"], updated_at=a.get("updated_at"))
        for a in data.get("artifacts", []) or []
    )
    tasks = tuple(
        Task(id=t["id"], status=t["status"], updated_at=t.get("updated_at"))
        for t in data.get("tasks", []) or []
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


@pytest.mark.parametrize(
    "fixture,expected_rule",
    [
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
    ],
)
def test_rule_matches(fixture: str, expected_rule: str) -> None:
    rules = load_rules()
    result = evaluate(rules, _manifest_from_fixture(fixture))
    assert result.rule_id == expected_rule


def test_fallback_rule_is_present() -> None:
    """Spec §6.5: a ``when: []`` rule at priority 9999 must always exist.

    CI fails the package if absent; this test enforces that invariant.
    """
    rules = load_rules()
    fallback = [r for r in rules if r.id == "fallback"]
    assert len(fallback) == 1, "rules.yaml must define exactly one 'fallback' rule"
    assert fallback[0].when == [], "fallback must have an empty `when` clause"
    assert fallback[0].priority == 9999


def test_suggest_template_renders() -> None:
    """The selected rule's `suggest` resolves to a no-brace string."""
    rules = load_rules()
    m = _manifest_from_fixture("planning_mixed_drafts.yaml")
    result = evaluate(rules, m)
    assert "{" not in result.suggest, (
        f"unresolved template var in suggest: {result.suggest!r}"
    )
    assert "a.md" in result.suggest


def test_reason_template_renders() -> None:
    rules = load_rules()
    m = _manifest_from_fixture("planning_mixed_drafts.yaml")
    result = evaluate(rules, m)
    assert "{" not in result.reason
    assert "a.md" in result.reason


def test_list_planned_paths_renders_multiline() -> None:
    rules = load_rules()
    m = _manifest_from_fixture("planning_fresh_init.yaml")
    result = evaluate(rules, m)
    assert "- a.md" in result.reason
    assert "- b.md" in result.reason


def test_user_override_replaces_existing_rule(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """An override file with a matching `id` replaces the default rule."""
    override = tmp_path / "agentic" / "state_rules.yaml"
    override.parent.mkdir(parents=True)
    override.write_text(
        "rules:\n"
        "  - id: planning-need-drafts\n"
        "    priority: 100\n"
        "    applies_to: planning\n"
        "    when:\n"
        "      - has_artifact_with_status: planned\n"
        "      - not_has_artifact_with_status: drafted\n"
        "    suggest: OVERRIDE\n"
        "    reason: overridden\n"
    )
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path))
    rules = load_rules()
    m = _manifest_from_fixture("planning_fresh_init.yaml")
    result = evaluate(rules, m)
    assert result.rule_id == "planning-need-drafts"
    assert result.suggest == "OVERRIDE"


def test_unsafe_override_falls_back_to_literal(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A hostile override template must NOT walk Python object internals.

    Per spec §6.4.1, an unsafe template falls back to the literal string
    rather than crashing or leaking interpreter state.
    """
    override = tmp_path / "agentic" / "state_rules.yaml"
    override.parent.mkdir(parents=True)
    override.write_text(
        "rules:\n"
        "  - id: planning-need-drafts\n"
        "    priority: 100\n"
        "    applies_to: planning\n"
        "    when:\n"
        "      - has_artifact_with_status: planned\n"
        "      - not_has_artifact_with_status: drafted\n"
        "    suggest: 'pwn {state.__class__}'\n"
        "    reason: 'reason {state.__class__}'\n"
    )
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path))
    rules = load_rules()
    m = _manifest_from_fixture("planning_fresh_init.yaml")
    result = evaluate(rules, m)
    # Literal template returned — no attribute walk performed.
    assert result.suggest == "pwn {state.__class__}"
    assert "class" in result.reason  # literal kept


def test_unknown_primitive_raises() -> None:
    """Any primitive name not in REGISTRY must hard-fail the loader."""
    from agentic.state_engine.engine import Rule, _match  # type: ignore[attr-defined]

    bogus = Rule(
        id="bogus",
        priority=1,
        applies_to=None,
        when=[{"never_registered_primitive": True}],
        suggest="",
        reason="",
    )
    m = _manifest_from_fixture("planning_fresh_init.yaml")
    with pytest.raises(ValueError, match="unknown primitive"):
        _match(bogus, m)
