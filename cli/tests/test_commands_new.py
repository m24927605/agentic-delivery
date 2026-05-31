"""Tests for `agentic new` — the scaffold materialization command."""
from __future__ import annotations

import pytest
from typer.testing import CliRunner

from agentic.app import app


runner = CliRunner()


@pytest.mark.parametrize("bad", ["", "foo/bar", "../escape", "a\x00b"])
def test_new_rejects_bad_name(bad):
    result = runner.invoke(app, ["new", bad])
    assert result.exit_code == 2, result.stderr
    assert "name must be a single path segment" in result.stderr


# Task 7 replaces this test
def test_new_valid_name_currently_exits_with_structured_error():
    """Until Tasks 6-10 land, a valid name should still go through the CLI's
    structured-error path (exit 1, 'not yet implemented'), not raise an
    unhandled Python exception with a Rich traceback."""
    result = runner.invoke(app, ["new", "my-project"])
    assert result.exit_code == 1, result.stderr
    assert "not yet implemented" in result.stderr
