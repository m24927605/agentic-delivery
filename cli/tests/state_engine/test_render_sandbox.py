"""Sandbox tests for the restricted template renderer (spec §6.4.1).

The renderer must reject anything except simple ``{<identifier>}`` substitution
against a flat dict. A hostile ``state_rules.yaml`` override must not be able
to reach Python object internals such as ``__class__`` walks. These tests
encode that contract.
"""

from __future__ import annotations

import pytest

from agentic.state_engine.render import (
    AllowedKeys,
    RenderError,
    is_template_safe,
    render,
)


_CTX: dict[str, str] = {"name": "demo", "path": "a.md"}
_ALLOWED: AllowedKeys = frozenset(_CTX.keys())


class TestUnsafeTemplatesAreRejected:
    """Templates that try to reach beyond flat-dict substitution must fail."""

    @pytest.mark.parametrize(
        "template",
        [
            "{x.__class__}",            # attribute walk to a dunder
            "{x.attr}",                 # ordinary attribute walk
            "{x[0]}",                   # subscript
            "{x!r}",                    # conversion flag
            "{x:0}",                    # format spec
            "{x:>10}",                  # format spec (alignment)
            "{ x }",                    # whitespace inside braces
            "{x.__init__.__globals__}", # known exploit pattern
            "{0}",                      # positional reference
            "{}",                       # empty
            "{1name}",                  # identifier may not start with digit
            "{-name}",                  # leading dash
            "{name__}",                 # dunder suffix
            "{__name}",                 # dunder prefix
        ],
    )
    def test_is_template_safe_rejects(self, template: str) -> None:
        assert is_template_safe(template) is False

    @pytest.mark.parametrize(
        "template",
        ["{x.__class__}", "{x[0]}", "{x!r}", "{x:0}"],
    )
    def test_render_rejects_unsafe(self, template: str) -> None:
        with pytest.raises(RenderError):
            render(template, _CTX, allowed=_ALLOWED)


class TestSafeTemplatesRender:
    def test_plain_substitution(self) -> None:
        assert render("hello {name}", _CTX, allowed=_ALLOWED) == "hello demo"

    def test_no_placeholders(self) -> None:
        assert render("no placeholders", _CTX, allowed=_ALLOWED) == "no placeholders"

    def test_multiple_placeholders(self) -> None:
        assert (
            render("{name} -> {path}", _CTX, allowed=_ALLOWED) == "demo -> a.md"
        )

    def test_unknown_identifier_raises(self) -> None:
        with pytest.raises(RenderError):
            render("hello {missing}", _CTX, allowed=_ALLOWED)

    def test_identifier_with_underscore(self) -> None:
        ctx = {"first_drafted_path": "doc.md"}
        allowed: AllowedKeys = frozenset(ctx.keys())
        assert (
            render("artifact {first_drafted_path}", ctx, allowed=allowed)
            == "artifact doc.md"
        )

    def test_no_format_escape_semantics(self) -> None:
        # Unlike ``str.format``, ``{{`` and ``}}`` are NOT format-style
        # escapes here — they are emitted literally and the inner placeholder
        # still substitutes. The renderer does not implement ``format``.
        assert (
            render("literal {{name}}", _CTX, allowed=_ALLOWED) == "literal {demo}"
        )

    def test_lone_brace_is_literal(self) -> None:
        # A stray ``{`` with no matching ``}`` is not a placeholder.
        assert render("note { here", _CTX, allowed=_ALLOWED) == "note { here"
