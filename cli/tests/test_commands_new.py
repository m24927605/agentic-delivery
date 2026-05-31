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


def test_new_target_does_not_exist_proceeds(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    # We're not yet copying — assert we got past name+state checks (Task-8 placeholder).
    result = runner.invoke(app, ["new", "proj"])
    assert result.exit_code == 1, result.stderr
    assert "populate" in result.stderr


def test_new_target_existing_empty_without_force_fails(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / "proj").mkdir()
    result = runner.invoke(app, ["new", "proj"])
    assert result.exit_code == 9, result.stderr
    assert "rerun with `--force`" in result.stderr


def test_new_target_existing_empty_with_force_proceeds(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / "proj").mkdir()
    result = runner.invoke(app, ["new", "proj", "--force"])
    # past state checks — falls into the Task-8 AgenticError placeholder
    assert result.exit_code == 1, result.stderr
    assert "populate" in result.stderr


def test_new_target_existing_nonempty_fails(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / "proj").mkdir()
    (tmp_path / "proj" / "stray.txt").write_text("x")
    result = runner.invoke(app, ["new", "proj"])
    assert result.exit_code == 9, result.stderr
    assert "target exists and is non-empty" in result.stderr
    assert "stray.txt" in result.stderr


def test_new_target_existing_nonempty_with_force_still_fails(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / "proj").mkdir()
    (tmp_path / "proj" / "stray.txt").write_text("x")
    result = runner.invoke(app, ["new", "proj", "--force"])
    assert result.exit_code == 9
    assert "non-empty" in result.stderr


def test_new_target_existing_nonempty_truncates_entries_with_ellipsis(tmp_path, monkeypatch):
    """When more than 5 entries exist, the error message lists 5 + 'X more'."""
    monkeypatch.chdir(tmp_path)
    (tmp_path / "proj").mkdir()
    for i in range(8):
        (tmp_path / "proj" / f"file_{i:02d}.txt").write_text("x")
    result = runner.invoke(app, ["new", "proj"])
    assert result.exit_code == 9
    assert "non-empty" in result.stderr
    assert "... (3 more)" in result.stderr
