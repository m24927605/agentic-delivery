"""User-facing rendering helpers (text + JSON) for the agentic CLI.

Public entry points:

- :class:`agentic.ui.errors.AgenticError` and :func:`render_error` for
  structured failure paths (spec §9.3 exit codes, §9.5.1 error envelope).
- :func:`agentic.ui.render.render` for command results (spec §9.5).
"""

from agentic.ui.errors import (
    EXIT_CODES,
    AgenticError,
    get_json_mode,
    render_error,
    set_json_mode,
)
from agentic.ui.render import render

__all__ = [
    "AgenticError",
    "EXIT_CODES",
    "get_json_mode",
    "render",
    "render_error",
    "set_json_mode",
]
