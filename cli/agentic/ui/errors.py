"""Structured errors for the agentic CLI.

Design (spec §9.3 / §9.5.1):

- :class:`AgenticError` is a :class:`typer.Exit` subclass — raising it lets
  click's standalone-mode handling exit the process with the correct code,
  without typer's Rich error panel wrapping our structured output.
- Constructing an ``AgenticError`` is **side-effecting**: it renders the
  ``x  <message>`` text or ``{"_schema": "agentic.cli/v1", "error": ...}``
  JSON envelope to stderr immediately. The json-mode flag is captured from
  a :class:`contextvars.ContextVar` populated by the root ``--json`` callback.
- :func:`render_error` is still exposed so callers (e.g. the ``main()``
  fallback hook) can render errors that did not go through the constructor.

Exit-code mapping (spec §9.3):

- 0   success
- 1   generic
- 2   misuse
- 3   validation_failed
- 4   authorization_denied
- 5   compat_failed
- 6   no_repo / no_run_context
- 64..79  forwarded script (``64 + min(child_exit, 15)``, set via ``exit_code=``)
"""

from __future__ import annotations

import contextvars
import json as _json
from typing import Any

import typer

EXIT_CODES: dict[str, int] = {
    "generic": 1,
    "misuse": 2,
    "validation_failed": 3,
    "authorization_denied": 4,
    "compat_failed": 5,
    "no_repo": 6,
    "no_run_context": 6,
    "script_failed": 64,
    "scaffold_target_exists": 9,
    "scaffold_git_failed": 10,
    "scaffold_bundle_missing": 11,
}


_json_mode_var: contextvars.ContextVar[bool] = contextvars.ContextVar(
    "_agentic_json_mode", default=False
)


def set_json_mode(value: bool) -> None:
    """Capture ``--json`` for the current invocation.

    Called from the root Typer callback once flag parsing is complete so any
    downstream ``raise AgenticError(...)`` can pick the right stderr format
    without having to thread ``ctx`` everywhere.
    """
    _json_mode_var.set(value)


def get_json_mode() -> bool:
    """Read back the json-mode flag set by :func:`set_json_mode`."""
    return _json_mode_var.get()


def render_error(err: AgenticError, *, json_mode: bool) -> int:
    """Print a structured error to stderr and return its exit code.

    Two render modes:

    - **text** — ``x  <message>`` followed by a blank line and ``Try:`` block
      enumerating each hint.
    - **json** — pretty-printed ``agentic.cli/v1`` envelope.

    Always returns ``err.exit_code`` so callers using ``render_error`` outside
    the constructor path (e.g. :func:`agentic.app.main`'s fallback) can pass
    it straight to ``sys.exit``.
    """
    if json_mode:
        typer.echo(_json.dumps(err.to_dict(), indent=2), err=True)
    else:
        typer.echo(f"x  {err.message}", err=True)
        if err.hints:
            typer.echo("", err=True)
            typer.echo("Try:", err=True)
            for hint in err.hints:
                typer.echo(f"  {hint}", err=True)
    return err.exit_code


class AgenticError(typer.Exit):
    """Structured CLI failure carrying category, message, hints, and exit code.

    Inherits :class:`typer.Exit` so that raising one terminates the command
    via click's standard exit path — no Rich panel, no typer pretty-print —
    with the exit code chosen from :data:`EXIT_CODES` (or an explicit
    ``exit_code=`` override for forwarded-script failures).

    Construction renders the structured stderr immediately, honouring the
    json-mode flag captured by :func:`set_json_mode`. This keeps call sites
    simple (``raise AgenticError(...)``) and avoids having to plumb ``ctx``
    through every helper.
    """

    def __init__(
        self,
        *,
        category: str,
        message: str,
        hints: list[str] | None = None,
        exit_code: int | None = None,
    ) -> None:
        self.category = category
        self.message = message
        self.hints: list[str] = list(hints or [])
        code = exit_code if exit_code is not None else EXIT_CODES.get(category, 1)
        super().__init__(code=code)
        render_error(self, json_mode=_json_mode_var.get())

    def to_dict(self) -> dict[str, Any]:
        return {
            "_schema": "agentic.cli/v1",
            "error": {
                "category": self.category,
                "message": self.message,
                "hints": list(self.hints),
            },
        }
