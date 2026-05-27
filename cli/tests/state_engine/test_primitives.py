"""Unit tests for the state engine condition primitives.

These cover every primitive registered in
:mod:`agentic.state_engine.primitives` — both the positive and the negative
branch — so that the rule evaluator can rely on a stable, closed set.
"""

from __future__ import annotations

from agentic.manifest import Artifact, Manifest, Task
from agentic.state_engine.primitives import REGISTRY


def _planning(state: str, artifacts: list[tuple[str, str]]) -> Manifest:
    return Manifest(
        id="x",
        mode="planning",
        profile="default-delivery",
        state=state,
        updated_at=None,
        artifacts=tuple(Artifact(path=p, status=s) for p, s in artifacts),
    )


def _impl(state: str, tasks: list[tuple[str, str]]) -> Manifest:
    return Manifest(
        id="x",
        mode="implementation",
        profile="default-delivery",
        state=state,
        updated_at=None,
        tasks=tuple(Task(id=tid, status=s) for tid, s in tasks),
    )


def test_state_matches_glob() -> None:
    m = _planning("blocked_strategy_conflict", [])
    fn = REGISTRY["state_matches"]
    assert fn(m, "blocked_*") is True
    assert fn(m, "ready_*") is False


def test_mode_is() -> None:
    m = _planning("any", [])
    fn = REGISTRY["mode_is"]
    assert fn(m, "planning") is True
    assert fn(m, "implementation") is False


def test_has_artifact_with_status() -> None:
    m = _planning("any", [("a.md", "drafted")])
    fn = REGISTRY["has_artifact_with_status"]
    assert fn(m, "drafted") is True
    assert fn(m, "approved") is False


def test_not_has_artifact_with_status() -> None:
    m = _planning("any", [("a.md", "drafted")])
    fn = REGISTRY["not_has_artifact_with_status"]
    assert fn(m, "approved") is True
    assert fn(m, "drafted") is False


def test_count_artifacts_with_status_min() -> None:
    m = _planning("any", [("a.md", "approved"), ("b.md", "approved")])
    fn = REGISTRY["count_artifacts_with_status"]
    assert fn(m, {"status": "approved", "min": 1}) is True
    assert fn(m, {"status": "approved", "min": 3}) is False


def test_count_artifacts_with_status_max() -> None:
    m = _planning("any", [("a.md", "approved"), ("b.md", "approved")])
    fn = REGISTRY["count_artifacts_with_status"]
    assert fn(m, {"status": "approved", "max": 5}) is True
    assert fn(m, {"status": "approved", "max": 1}) is False


def test_all_artifacts_terminal() -> None:
    m_yes = _planning(
        "any",
        [("a.md", "approved"), ("b.md", "rejected"), ("c.md", "deferred")],
    )
    m_no = _planning("any", [("a.md", "approved"), ("b.md", "drafted")])
    fn = REGISTRY["all_artifacts_terminal"]
    assert fn(m_yes, True) is True
    assert fn(m_no, True) is False


def test_all_artifacts_terminal_empty_is_false() -> None:
    # Empty artifact list cannot satisfy "all terminal" — otherwise vacuous
    # truth would let the rule fire on a freshly-created run.
    fn = REGISTRY["all_artifacts_terminal"]
    assert fn(_planning("any", []), True) is False


def test_has_task_with_status() -> None:
    m = _impl("any", [("T-1", "pending")])
    fn = REGISTRY["has_task_with_status"]
    assert fn(m, "pending") is True
    assert fn(m, "executed") is False


def test_task_graph_exists() -> None:
    m_yes = _impl("any", [("T-1", "pending")])
    m_no = _impl("any", [])
    fn = REGISTRY["task_graph_exists"]
    assert fn(m_yes, True) is True
    assert fn(m_no, True) is False
    assert fn(m_no, False) is True


def test_all_tasks_reviewed() -> None:
    m_yes = _impl("any", [("T-1", "reviewed"), ("T-2", "approved")])
    m_no = _impl("any", [("T-1", "reviewed"), ("T-2", "executed")])
    fn = REGISTRY["all_tasks_reviewed"]
    assert fn(m_yes, True) is True
    assert fn(m_no, True) is False
    assert fn(_impl("any", []), True) is False


def test_has_artifact_at() -> None:
    m = _planning("any", [("boss/market-research.md", "drafted")])
    fn = REGISTRY["has_artifact_at"]
    assert fn(m, "market-research.md") is True
    assert fn(m, "competitor-brief.md") is False


def test_not_has_artifact_at() -> None:
    m = _planning("any", [("boss/market-research.md", "drafted")])
    fn = REGISTRY["not_has_artifact_at"]
    assert fn(m, "competitor-brief.md") is True
    assert fn(m, "market-research.md") is False
