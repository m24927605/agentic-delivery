"""Read-only access to agentic-delivery run manifests.

Per spec §4.2.1, the Manifest type is immutable: the dataclass is frozen and
its `artifacts` / `tasks` collections are tuples — both of which reject
in-place mutation. Callers should always go through `load_manifest()`.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Literal, cast

import yaml  # type: ignore[import-untyped]

Mode = Literal["planning", "implementation"]
ArtifactStatus = Literal[
    "planned",
    "drafted",
    "reviewed",
    "changes_requested",
    "approved",
    "rejected",
    "deferred",
]
TaskStatus = Literal["pending", "dispatched", "executed", "reviewed", "approved"]


@dataclass(frozen=True)
class Artifact:
    path: str
    status: str
    updated_at: str | None = None


@dataclass(frozen=True)
class Task:
    id: str
    status: str
    updated_at: str | None = None


@dataclass(frozen=True)
class Manifest:
    id: str
    mode: Mode
    profile: str
    state: str
    updated_at: str | None
    artifacts: tuple[Artifact, ...] = field(default_factory=tuple)
    tasks: tuple[Task, ...] = field(default_factory=tuple)

    def count_artifacts(self, *, status: str) -> int:
        return sum(1 for a in self.artifacts if a.status == status)

    def first_artifact(self, *, status: str) -> Artifact | None:
        for a in self.artifacts:
            if a.status == status:
                return a
        return None

    def count_tasks(self, *, status: str) -> int:
        return sum(1 for t in self.tasks if t.status == status)

    def first_task(self, *, status: str) -> Task | None:
        for t in self.tasks:
            if t.status == status:
                return t
        return None


def _find_manifest_file(repo: Path, run_id: str) -> Path:
    base = repo / "agentic" / "runs" / run_id
    for name in ("implementation-manifest.yaml", "manifest.yaml"):
        candidate = base / name
        if candidate.is_file():
            return candidate
    raise FileNotFoundError(f"no manifest for run {run_id!r} under {base}")


def load_manifest(*, repo: Path, run_id: str) -> Manifest:
    """Load a Manifest for `run_id` under `repo/agentic/runs/`.

    Implementation manifests synthesise `artifacts` from `approved_inputs`
    when no explicit `artifacts:` list is present, marking each as approved.
    """
    path = _find_manifest_file(repo, run_id)
    data: dict[str, Any] = yaml.safe_load(path.read_text()) or {}
    run = cast(dict[str, Any], data.get("run", {}) or {})
    mode: Mode = cast(Mode, run.get("mode", "planning"))

    artifacts_raw = cast(list[dict[str, Any]], data.get("artifacts") or [])
    if mode == "implementation" and not artifacts_raw:
        # Real implementation manifests store approved_inputs as dicts carrying
        # artifact_status; legacy fixtures used plain path strings. Accept both.
        synthesised: list[dict[str, Any]] = []
        for entry in cast(list[Any], data.get("approved_inputs") or []):
            if isinstance(entry, str):
                synthesised.append({"path": entry, "status": "approved"})
            elif isinstance(entry, dict):
                synthesised.append(
                    {
                        "path": entry["path"],
                        "status": entry.get("artifact_status", "approved"),
                    }
                )
        artifacts_raw = synthesised
    artifacts = tuple(
        Artifact(
            path=str(a["path"]),
            status=str(a["status"]),
            updated_at=a.get("updated_at"),
        )
        for a in artifacts_raw
    )
    # Real implementation manifests use `implementation_tasks` with task_id/state;
    # planning fixtures use `tasks` with id/status. Prefer the real shape.
    tasks_raw = cast(
        list[dict[str, Any]],
        data.get("implementation_tasks") or data.get("tasks") or [],
    )
    tasks = tuple(
        Task(
            id=str(t.get("task_id", t.get("id"))),
            status=str(t.get("state", t.get("status"))),
            updated_at=t.get("updated_at"),
        )
        for t in tasks_raw
    )
    return Manifest(
        id=str(run.get("id", run_id)),
        mode=mode,
        profile=str(run.get("profile", "unknown")),
        state=str(run.get("state", "unknown")),
        updated_at=run.get("updated_at"),
        artifacts=artifacts,
        tasks=tasks,
    )
