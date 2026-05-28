"""Command-result rendering helpers (spec §9.5).

A command computes its result as a tuple of:

- a JSON-serialisable ``payload`` (the ``agentic.cli/v1`` envelope), and
- a ``text_fn`` that prints the human-readable form to stdout.

The :func:`render` switch routes between the two based on ``--json`` and
guarantees ``_schema`` is the first key in the dumped JSON (spec §9.5.1).
"""

from __future__ import annotations

import json as _json
from typing import Any, Callable

import typer


def render(
    payload: dict[str, Any] | None,
    *,
    json_mode: bool,
    text_fn: Callable[[], None] | None = None,
) -> None:
    """Render ``payload`` as JSON (``--json``) or via ``text_fn`` (text mode).

    Both branches print to stdout. Stderr is reserved for structured errors via
    :func:`agentic.ui.errors.render_error`. ``_schema`` must already be the
    first key of ``payload`` (we preserve insertion order via
    ``sort_keys=False``).
    """
    if json_mode:
        if payload is None:
            return
        typer.echo(_json.dumps(payload, indent=2, sort_keys=False))
        return
    if text_fn is not None:
        text_fn()
