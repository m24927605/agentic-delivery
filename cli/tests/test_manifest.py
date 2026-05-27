"""Unit tests for the read-only Manifest loader (spec §4.2.1)."""

from __future__ import annotations

from pathlib import Path

import pytest

from agentic.manifest import Artifact, Task, load_manifest


FIXTURES = Path(__file__).parent / "fixtures" / "manifests"


def _seed_repo(
    tmp_path: Path,
    run_id: str,
    fixture_name: str,
    *,
    impl: bool = False,
) -> Path:
    src = FIXTURES / fixture_name
    target_dir = tmp_path / "agentic" / "runs" / run_id
    target_dir.mkdir(parents=True)
    target_name = "implementation-manifest.yaml" if impl else "manifest.yaml"
    (target_dir / target_name).write_text(src.read_text())
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    return tmp_path


def test_load_planning_manifest(tmp_path: Path) -> None:
    repo = _seed_repo(tmp_path, "demo-planning", "planning_fresh.yaml")
    m = load_manifest(repo=repo, run_id="demo-planning")
    assert m.id == "demo-planning"
    assert m.mode == "planning"
    assert m.profile == "default-delivery"
    assert m.state == "artifact_plan_created"
    assert len(m.artifacts) == 3
    assert m.artifacts[0] == Artifact(
        path="docs/architecture/x.md",
        status="planned",
        updated_at="2026-05-27T09:00:00Z",
    )


def test_load_implementation_manifest(tmp_path: Path) -> None:
    repo = _seed_repo(tmp_path, "demo-impl", "impl_mid_dispatch.yaml", impl=True)
    m = load_manifest(repo=repo, run_id="demo-impl")
    assert m.mode == "implementation"
    # implementation manifests synthesise artifacts from approved_inputs.
    assert len(m.artifacts) == 1
    assert m.artifacts[0].status == "approved"
    assert m.artifacts[0].path == "docs/architecture/z.md"
    assert len(m.tasks) == 2
    assert m.tasks[0] == Task(
        id="T1", status="dispatched", updated_at="2026-05-27T10:30:00Z"
    )


def test_load_unknown_run_raises(tmp_path: Path) -> None:
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    with pytest.raises(FileNotFoundError):
        load_manifest(repo=tmp_path, run_id="ghost")


def test_artifact_status_counts(tmp_path: Path) -> None:
    repo = _seed_repo(tmp_path, "demo-planning", "planning_fresh.yaml")
    m = load_manifest(repo=repo, run_id="demo-planning")
    assert m.count_artifacts(status="planned") == 1
    assert m.count_artifacts(status="drafted") == 1
    assert m.count_artifacts(status="approved") == 1
    first_drafted = m.first_artifact(status="drafted")
    assert first_drafted is not None
    assert first_drafted.path == "docs/architecture/y.md"


def test_task_status_counts(tmp_path: Path) -> None:
    repo = _seed_repo(tmp_path, "demo-impl", "impl_mid_dispatch.yaml", impl=True)
    m = load_manifest(repo=repo, run_id="demo-impl")
    assert m.count_tasks(status="dispatched") == 1
    assert m.count_tasks(status="pending") == 1
    first_pending = m.first_task(status="pending")
    assert first_pending is not None
    assert first_pending.id == "T2"


def test_manifest_collections_are_immutable_tuples(tmp_path: Path) -> None:
    """Spec §4.2.1: Manifest is immutable; artifacts/tasks are tuples, not lists."""
    repo = _seed_repo(tmp_path, "demo-impl", "impl_mid_dispatch.yaml", impl=True)
    m = load_manifest(repo=repo, run_id="demo-impl")
    # Type-level guarantee: collections are tuples.
    assert isinstance(m.artifacts, tuple)
    assert isinstance(m.tasks, tuple)
    # Runtime-level guarantee: tuples reject .append (no such method).
    with pytest.raises(AttributeError):
        m.artifacts.append(Artifact(path="bad.md", status="planned"))  # type: ignore[attr-defined]
    with pytest.raises(AttributeError):
        m.tasks.append(Task(id="Tx", status="pending"))  # type: ignore[attr-defined]
    # frozen=True guarantee: top-level fields can't be reassigned.
    with pytest.raises(Exception):  # dataclasses.FrozenInstanceError subclasses AttributeError
        m.id = "mutated"  # type: ignore[misc]


def test_artifact_and_task_are_frozen() -> None:
    a = Artifact(path="x.md", status="planned")
    t = Task(id="T1", status="pending")
    with pytest.raises(Exception):
        a.path = "y.md"  # type: ignore[misc]
    with pytest.raises(Exception):
        t.id = "T2"  # type: ignore[misc]
