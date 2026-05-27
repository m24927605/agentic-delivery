"""Restricted template renderer (spec §6.4.1).

``str.format`` walks attribute and item accesses, conversion flags
(``{x!r}``), and format specs (``{x:0}``). Any of those is an attack surface
once a user-supplied YAML override at ``$XDG_CONFIG_HOME/agentic/state_rules.yaml``
is permitted: a hostile template like ``{x.__class__.__init__.__globals__[...]}``
can reach into Python object internals.

This module replaces ``str.format`` with a single-purpose substitution:

* Validate every ``{...}`` group with a strict whitelist regex
  (``^[a-z_][a-z0-9_]*$``).
* Reject any placeholder containing ``.``, ``[``, ``]``, ``:``, ``!``,
  whitespace, or ``__``.
* Look every identifier up in a flat context dict; never call ``getattr``,
  ``__getitem__``, ``format``, or ``__format__`` on user objects.

Bare ``{`` or ``}`` characters (without a matching, syntactically valid
counterpart) are emitted literally — they have no special meaning here.
"""

from __future__ import annotations

import re
from typing import Mapping

AllowedKeys = frozenset[str] | set[str]

# Capture the inside of every brace group, including unsafe content, so we can
# report what was rejected. The renderer rejects the whole template the moment
# any group fails validation.
_PLACEHOLDER_RE = re.compile(r"\{([^{}]*)\}")
_SAFE_IDENT_RE = re.compile(r"^[a-z_][a-z0-9_]*$")


class RenderError(ValueError):
    """Raised when a template is unsafe or references an unknown identifier."""


def _scan_groups(template: str) -> list[str]:
    """Return every ``{...}`` group in ``template`` (may be empty)."""
    return _PLACEHOLDER_RE.findall(template)


def _is_safe_identifier(name: str) -> bool:
    if not _SAFE_IDENT_RE.fullmatch(name):
        return False
    # ``__`` is forbidden anywhere in the name — blocks ``__class__`` etc.
    if "__" in name:
        return False
    return True


def is_template_safe(template: str) -> bool:
    """Return ``True`` only if every ``{...}`` group is a safe identifier.

    A template with zero ``{...}`` groups is trivially safe. A ``{`` with no
    closing brace is not a placeholder and is also safe (rendered literally).
    """
    for group in _scan_groups(template):
        if not _is_safe_identifier(group):
            return False
    return True


def render(
    template: str,
    ctx: Mapping[str, object],
    *,
    allowed: AllowedKeys | None = None,
) -> str:
    """Render ``template`` against ``ctx``.

    Substitutes ``{name}`` for ``ctx[name]`` when ``name`` is a safe
    identifier and present in ``allowed`` (defaults to ``ctx.keys()``).
    Raises :class:`RenderError` if any placeholder is unsafe or unknown.
    The caller decides whether to fall back to the literal template.
    """
    keys: AllowedKeys = (
        allowed if allowed is not None else frozenset(ctx.keys())
    )

    def _replace(match: re.Match[str]) -> str:
        name = match.group(1)
        if not _is_safe_identifier(name):
            raise RenderError(
                f"unsafe template placeholder: {{{name}}} "
                f"(allowed: ^[a-z_][a-z0-9_]*$ with no '__')"
            )
        if name not in keys:
            raise RenderError(
                f"unknown template identifier: {{{name}}}; "
                f"allowed keys are {sorted(keys)!r}"
            )
        value = ctx.get(name)
        return "" if value is None else str(value)

    return _PLACEHOLDER_RE.sub(_replace, template)
