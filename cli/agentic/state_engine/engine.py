"""Rule loader and evaluator for the agentic CLI state engine (spec §6).

Loading order (spec §6.1):

1. ``rules.yaml`` shipped beside this module.
2. ``$XDG_CONFIG_HOME/agentic/state_rules.yaml`` (optional). Rules with the
   same ``id`` replace the default; new ids extend the list.

The evaluator is read-only against the manifest, sorts rules by priority
(ascending), and returns the first match. Templates render through the
restricted renderer in :mod:`agentic.state_engine.render` — never through
``str.format`` on raw objects.
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml  # type: ignore[import-untyped]

from agentic.manifest import Manifest
from agentic.state_engine.primitives import REGISTRY
from agentic.state_engine.render import RenderError, render

_log = logging.getLogger(__name__)

DEFAULT_RULES: Path = Path(__file__).resolve().parent / "rules.yaml"


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


# Whitelisted template identifiers (spec §6.4). Templates may only reference
# these — anything else falls back to the literal template per §6.4.1.
_ALLOWED_TEMPLATE_KEYS: frozenset[str] = frozenset(
    {
        "run_id",
        "state",
        "mode",
        "count_planned",
        "count_drafted",
        "count_reviewed",
        "count_changes_requested",
        "count_approved",
        "count_rejected",
        "count_deferred",
        "first_drafted_path",
        "first_reviewed_path",
        "first_changes_requested_path",
        "first_approved_path",
        "first_rejected_path",
        "first_deferred_path",
        "first_planned_path",
        "count_task_pending",
        "count_task_dispatched",
        "count_task_executed",
        "count_task_reviewed",
        "first_pending_task_id",
        "first_dispatched_task_id",
        "first_executed_task_id",
        "first_reviewed_task_id",
        "list_planned_paths",
    }
)


def _xdg_override_path() -> Path | None:
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    candidate = Path(base) / "agentic" / "state_rules.yaml"
    return candidate if candidate.is_file() else None


def _coerce_rule(raw: dict[str, Any]) -> Rule:
    return Rule(
        id=str(raw["id"]),
        priority=int(raw.get("priority", 1000)),
        applies_to=raw.get("applies_to"),
        when=list(raw.get("when") or []),
        suggest=str(raw["suggest"]),
        reason=str(raw.get("reason", "")),
    )


def load_rules() -> list[Rule]:
    """Load default rules and merge any XDG override on top.

    Returns rules sorted by ascending priority. The fallback rule
    (priority 9999) is enforced to exist — its absence is a programming
    error.
    """
    data: dict[str, Any] = yaml.safe_load(DEFAULT_RULES.read_text()) or {}
    raw_rules: list[dict[str, Any]] = list(data.get("rules", []) or [])
    override = _xdg_override_path()
    if override is not None:
        extra: dict[str, Any] = yaml.safe_load(override.read_text()) or {}
        by_id = {r["id"]: i for i, r in enumerate(raw_rules)}
        for r in extra.get("rules", []) or []:
            if r["id"] in by_id:
                raw_rules[by_id[r["id"]]] = r
            else:
                raw_rules.append(r)
    rules = [_coerce_rule(r) for r in raw_rules]
    rules.sort(key=lambda r: r.priority)
    if not any(r.id == "fallback" and r.when == [] for r in rules):
        raise RuntimeError(
            "rules.yaml is missing the mandatory `fallback` rule "
            "(when: [], priority: 9999) — spec §6.5"
        )
    return rules


_PROFILE_CATEGORIES: frozenset[str] = frozenset({"boss-idea"})


def _rule_category(m: Manifest) -> str:
    """Derive the ``applies_to`` category for ``m``.

    A specialised profile (e.g. ``boss-idea``) takes precedence over the
    underlying mode: a boss-idea run is a planning-mode run, but its rules
    are scoped by profile, not mode. Otherwise the mode is the category.
    """
    if m.profile in _PROFILE_CATEGORIES:
        return m.profile
    return m.mode


def _applies_to_matches(rule: Rule, m: Manifest) -> bool:
    if rule.applies_to is None:
        return True
    return rule.applies_to == _rule_category(m)


def _match(rule: Rule, m: Manifest) -> bool:
    if not _applies_to_matches(rule, m):
        return False
    for clause in rule.when:
        if not isinstance(clause, dict) or len(clause) != 1:
            raise ValueError(
                f"rule {rule.id}: each `when` clause must have exactly one key"
            )
        ((key, value),) = clause.items()
        primitive = REGISTRY.get(key)
        if primitive is None:
            raise ValueError(f"rule {rule.id}: unknown primitive {key!r}")
        if not primitive(m, value):
            return False
    return True


def _first_path(m: Manifest, status: str) -> str | None:
    a = m.first_artifact(status=status)
    return a.path if a is not None else None


def _first_task_id(m: Manifest, status: str) -> str | None:
    t = m.first_task(status=status)
    return t.id if t is not None else None


def _build_context(m: Manifest) -> dict[str, object]:
    """Build the flat, whitelisted render context (spec §6.4)."""
    ctx: dict[str, object] = {
        "run_id": m.id,
        "state": m.state,
        "mode": m.mode,
    }
    for s in (
        "planned",
        "drafted",
        "reviewed",
        "changes_requested",
        "approved",
        "rejected",
        "deferred",
    ):
        ctx[f"count_{s}"] = m.count_artifacts(status=s)
        p = _first_path(m, s)
        if p is not None:
            ctx[f"first_{s}_path"] = p
    for s in ("pending", "dispatched", "executed", "reviewed"):
        ctx[f"count_task_{s}"] = m.count_tasks(status=s)
        tid = _first_task_id(m, s)
        if tid is not None:
            ctx[f"first_{s}_task_id"] = tid
    ctx["list_planned_paths"] = "\n".join(
        f"  - {a.path}" for a in m.artifacts if a.status == "planned"
    )
    return ctx


def _safe_render(template: str, ctx: dict[str, object], *, rule_id: str) -> str:
    """Render a template; on any RenderError, return the literal template.

    Per spec §6.4.1, missing/unsafe variables must not crash and must not
    leak object internals. A structured warning is logged; the caller sees
    the literal template string.
    """
    try:
        return render(template, ctx, allowed=_ALLOWED_TEMPLATE_KEYS)
    except RenderError as e:
        _log.warning(
            "state_engine.render_fallback rule=%s error=%s template=%r",
            rule_id,
            e,
            template,
        )
        return template


def evaluate(rules: list[Rule], m: Manifest) -> Decision:
    """Return the first matching :class:`Decision` for ``m``.

    Rules are scanned in priority order. Because the fallback rule is
    invariant-checked at load time, this function never returns ``None``.
    """
    ctx = _build_context(m)
    for rule in rules:
        if _match(rule, m):
            return Decision(
                rule_id=rule.id,
                suggest=_safe_render(rule.suggest, ctx, rule_id=rule.id),
                reason=_safe_render(rule.reason, ctx, rule_id=rule.id),
            )
    # _load_rules guarantees the fallback rule exists, so this branch is
    # only reachable if someone hand-built a rules list. Treat as a bug.
    raise RuntimeError("no rule matched and no fallback present — fix rules.yaml")


__all__ = ["Rule", "Decision", "evaluate", "load_rules", "DEFAULT_RULES"]
