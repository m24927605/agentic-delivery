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
