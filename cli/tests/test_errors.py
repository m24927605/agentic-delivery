"""Structured error rendering — text + JSON envelope (spec §9.3, §9.5.1).

These tests run against the live ``status`` command in a workspace with no
agentic-delivery repo on disk, which forces the ``no_repo`` branch through
``_shell_helpers``/the command callback. The shape of the error envelope is
the contract — exit code 6, structured ``x  ... / Try:`` text, and the
``agentic.cli/v1`` JSON.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from typer.testing import CliRunner

from agentic.app import app
from agentic.ui.errors import EXIT_CODES, AgenticError, set_json_mode


def test_text_error_format(
    cli: CliRunner, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.chdir(tmp_path)
    monkeypatch.delenv("AGENTIC_HOME", raising=False)
    result = cli.invoke(app, ["status"])
    assert result.exit_code == 6
    # Structured stderr leads with the "x  " sentinel.
    assert result.stderr.startswith("x  "), result.stderr
    lower = result.stderr.lower()
    # Hints surface under a "Try:" header (or include "next"/"hint" wording).
    assert "try" in lower or "next" in lower or "hint" in lower, result.stderr


def test_json_error_format(
    cli: CliRunner, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.chdir(tmp_path)
    monkeypatch.delenv("AGENTIC_HOME", raising=False)
    result = cli.invoke(app, ["--json", "status"])
    assert result.exit_code == 6
    payload = json.loads(result.stderr)
    assert payload["_schema"] == "agentic.cli/v1"
    assert payload["error"]["category"] in {"no_repo", "no_run_context"}
    assert isinstance(payload["error"]["message"], str)
    assert payload["error"]["message"]
    assert isinstance(payload["error"]["hints"], list)
    assert payload["error"]["hints"]
    # Stdout stays clean — structured errors go to stderr only.
    assert result.stdout == ""


def test_json_error_envelope_schema_first(
    cli: CliRunner, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """The JSON error envelope keeps ``_schema`` as the first key (spec §9.5.1)."""
    monkeypatch.chdir(tmp_path)
    monkeypatch.delenv("AGENTIC_HOME", raising=False)
    result = cli.invoke(app, ["--json", "status"])
    payload = json.loads(result.stderr)
    assert next(iter(payload.keys())) == "_schema"
    assert next(iter(payload["error"].keys())) == "category"


def test_exit_codes_match_spec() -> None:
    """Locked exit-code mapping per spec §9.3."""
    assert EXIT_CODES["generic"] == 1
    assert EXIT_CODES["misuse"] == 2
    assert EXIT_CODES["validation_failed"] == 3
    assert EXIT_CODES["authorization_denied"] == 4
    assert EXIT_CODES["compat_failed"] == 5
    assert EXIT_CODES["no_repo"] == 6
    assert EXIT_CODES["no_run_context"] == 6
    assert EXIT_CODES["script_failed"] == 64


def test_agentic_error_to_dict_shape(
    capsys: pytest.CaptureFixture[str],
) -> None:
    """``AgenticError.to_dict`` produces the canonical envelope."""
    set_json_mode(False)  # avoid emitting JSON during constructor
    err = AgenticError(
        category="no_run_context",
        message="no run context",
        hints=["agentic run use <id>"],
    )
    capsys.readouterr()  # drain stderr side-effect
    d = err.to_dict()
    assert d["_schema"] == "agentic.cli/v1"
    assert d["error"]["category"] == "no_run_context"
    assert d["error"]["message"] == "no run context"
    assert d["error"]["hints"] == ["agentic run use <id>"]


def test_agentic_error_exit_code_override(
    capsys: pytest.CaptureFixture[str],
) -> None:
    """``exit_code=`` overrides the category mapping (forwarded-script case)."""
    set_json_mode(False)
    err = AgenticError(
        category="script_failed",
        message="scripts/foo.sh exited 7",
        hints=[],
        exit_code=64 + 7,
    )
    capsys.readouterr()
    assert err.exit_code == 71


def test_new_scaffold_exit_codes():
    from agentic.ui.errors import EXIT_CODES

    assert EXIT_CODES["scaffold_target_exists"] == 9
    assert EXIT_CODES["scaffold_git_failed"] == 10
    assert EXIT_CODES["scaffold_bundle_missing"] == 11
