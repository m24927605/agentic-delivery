"""Closed set of condition primitives the state engine knows.

The rule loader is forbidden from invoking anything outside :data:`REGISTRY`
(spec §6.3). New primitives require a registry entry and a unit test in the
same patch — and the user override at
``$XDG_CONFIG_HOME/agentic/state_rules.yaml`` can only reference names that
already exist here.
"""

from __future__ import annotations

import fnmatch
from typing import Any, Callable

from agentic.manifest import Manifest

Primitive = Callable[[Manifest, Any], bool]
REGISTRY: dict[str, Primitive] = {}

_TERMINAL_ARTIFACT_STATUSES: frozenset[str] = frozenset(
    {"approved", "rejected", "deferred"}
)
_REVIEWED_TASK_STATUSES: frozenset[str] = frozenset({"reviewed", "approved"})


def _register(name: str) -> Callable[[Primitive], Primitive]:
    def deco(fn: Primitive) -> Primitive:
        REGISTRY[name] = fn
        return fn

    return deco


@_register("state_matches")
def _state_matches(m: Manifest, glob: Any) -> bool:
    return fnmatch.fnmatch(m.state, str(glob))


@_register("mode_is")
def _mode_is(m: Manifest, mode: Any) -> bool:
    return bool(m.mode == mode)


@_register("has_artifact_with_status")
def _has_artifact_with_status(m: Manifest, status: Any) -> bool:
    return m.count_artifacts(status=str(status)) >= 1


@_register("not_has_artifact_with_status")
def _not_has_artifact_with_status(m: Manifest, status: Any) -> bool:
    return m.count_artifacts(status=str(status)) == 0


@_register("count_artifacts_with_status")
def _count_artifacts_with_status(m: Manifest, spec: Any) -> bool:
    if not isinstance(spec, dict):
        raise ValueError(
            "count_artifacts_with_status requires a mapping with 'status' and "
            "optional 'min'/'max'"
        )
    status = spec.get("status")
    if not isinstance(status, str):
        raise ValueError("count_artifacts_with_status: 'status' must be a string")
    n = m.count_artifacts(status=status)
    lo = spec.get("min")
    hi = spec.get("max")
    if lo is not None and n < int(lo):
        return False
    if hi is not None and n > int(hi):
        return False
    return True


@_register("all_artifacts_terminal")
def _all_artifacts_terminal(m: Manifest, _: Any) -> bool:
    if not m.artifacts:
        return False
    return all(a.status in _TERMINAL_ARTIFACT_STATUSES for a in m.artifacts)


@_register("has_task_with_status")
def _has_task_with_status(m: Manifest, status: Any) -> bool:
    return m.count_tasks(status=str(status)) >= 1


@_register("task_graph_exists")
def _task_graph_exists(m: Manifest, want: Any) -> bool:
    return bool(m.tasks) == bool(want)


@_register("all_tasks_reviewed")
def _all_tasks_reviewed(m: Manifest, _: Any) -> bool:
    if not m.tasks:
        return False
    return all(t.status in _REVIEWED_TASK_STATUSES for t in m.tasks)


@_register("has_artifact_at")
def _has_artifact_at(m: Manifest, rel: Any) -> bool:
    rel_s = str(rel)
    return any(a.path.endswith(rel_s) for a in m.artifacts)


@_register("not_has_artifact_at")
def _not_has_artifact_at(m: Manifest, rel: Any) -> bool:
    rel_s = str(rel)
    return not any(a.path.endswith(rel_s) for a in m.artifacts)
