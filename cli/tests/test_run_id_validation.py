"""Tests for run-id regex validation per spec §7.1.1.

Every resolved run id — from --run-id flag, $AIT_RUN_ID, or .agentic/current-run —
must be matched against ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}$ before any filesystem
path join. Failures exit 6.
"""

from __future__ import annotations

from pathlib import Path

import pytest
from typer.testing import CliRunner

from agentic.app import app
from agentic.context import RunNotFound, _validate_run_id


# Payload classes enumerated in spec §7.1.1.
INVALID_PAYLOADS: list[tuple[str, str]] = [
    ("path_traversal", "../../etc"),
    ("command_substitution", "$(rm -rf .)"),
    ("leading_dash", "-foo"),
    ("embedded_newline", "abc\ndef"),
    ("nul_byte", "abc\x00def"),
    ("empty_string", ""),
    ("too_long", "a" * 200),
    ("unicode_lookalike", "аbc"),  # Cyrillic 'а' (U+0430) — looks like Latin 'a'
]


def _seed_repo(tmp_path: Path) -> Path:
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    valid = tmp_path / "agentic" / "runs" / "valid-run"
    valid.mkdir(parents=True)
    (valid / "manifest.yaml").write_text("run:\n  id: valid-run\n")
    return tmp_path


@pytest.mark.parametrize(
    "label,bad", INVALID_PAYLOADS, ids=[label for label, _ in INVALID_PAYLOADS]
)
def test_validator_rejects_payload(label: str, bad: str) -> None:
    """_validate_run_id raises RunNotFound with exit_code=6 for every payload class."""
    with pytest.raises(RunNotFound) as exc:
        _validate_run_id(bad, source="--run-id")
    assert exc.value.exit_code == 6


@pytest.mark.parametrize(
    "label,bad", INVALID_PAYLOADS, ids=[label for label, _ in INVALID_PAYLOADS]
)
def test_flag_source_rejects_invalid(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, label: str, bad: str
) -> None:
    """`agentic run use <bad>` exits 6 for any payload reachable via argv."""
    repo = _seed_repo(tmp_path)
    monkeypatch.chdir(repo)
    monkeypatch.delenv("AIT_RUN_ID", raising=False)

    # argv cannot carry leading-dash (typer interprets as flag) or empty positional;
    # for those, regex validation is exercised by test_validator_rejects_payload above.
    if label in {"leading_dash", "empty_string"}:
        pytest.skip(f"{label} cannot be transmitted as a Typer positional argument")

    runner = CliRunner()
    result = runner.invoke(app, ["run", "use", bad])
    assert result.exit_code == 6, (
        f"{label!r}: expected exit 6, got {result.exit_code}; stdout={result.stdout!r}"
    )


@pytest.mark.parametrize(
    "label,bad", INVALID_PAYLOADS, ids=[label for label, _ in INVALID_PAYLOADS]
)
def test_env_source_rejects_invalid(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, label: str, bad: str
) -> None:
    """`AIT_RUN_ID=<bad> agentic run show` exits 6 for payloads the env layer can carry."""
    repo = _seed_repo(tmp_path)
    monkeypatch.chdir(repo)

    # CPython rejects NUL bytes via putenv(); empty env values are falsy and fall through.
    if label == "nul_byte":
        pytest.skip("CPython os.environ rejects NUL bytes; not reachable via env")
    if label == "empty_string":
        pytest.skip("Empty AIT_RUN_ID is treated as unset by design (falls through)")

    monkeypatch.setenv("AIT_RUN_ID", bad)
    runner = CliRunner()
    result = runner.invoke(app, ["run", "show"])
    assert result.exit_code == 6, (
        f"{label!r}: expected exit 6, got {result.exit_code}; stdout={result.stdout!r}"
    )


@pytest.mark.parametrize(
    "label,bad", INVALID_PAYLOADS, ids=[label for label, _ in INVALID_PAYLOADS]
)
def test_file_source_rejects_invalid(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, label: str, bad: str
) -> None:
    """`.agentic/current-run` containing a bad payload exits 6 on resolution."""
    repo = _seed_repo(tmp_path)
    monkeypatch.chdir(repo)
    monkeypatch.delenv("AIT_RUN_ID", raising=False)

    # An empty file is "treated as unset" per §7.5; covered by existing test_empty_file_falls_through.
    if label == "empty_string":
        pytest.skip("Empty file falls through to next source per §7.5")

    (repo / ".agentic").mkdir()
    (repo / ".agentic" / "current-run").write_bytes((bad + "\n").encode("utf-8"))

    runner = CliRunner()
    result = runner.invoke(app, ["run", "show"])
    assert result.exit_code == 6, (
        f"{label!r}: expected exit 6, got {result.exit_code}; stdout={result.stdout!r}"
    )


def test_multiline_file_refused(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """Per §7.5: multi-line .agentic/current-run is refused with exit 6 (was 'use first line')."""
    repo = _seed_repo(tmp_path)
    monkeypatch.chdir(repo)
    monkeypatch.delenv("AIT_RUN_ID", raising=False)
    (repo / ".agentic").mkdir()
    # Both lines reference a real run; the multi-line shape itself is the refusal trigger.
    (repo / ".agentic" / "current-run").write_text("valid-run\nvalid-run\n")

    runner = CliRunner()
    result = runner.invoke(app, ["run", "show"])
    assert result.exit_code == 6


def test_leading_whitespace_in_file_rejected(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A single line with leading whitespace fails regex (not silently stripped)."""
    repo = _seed_repo(tmp_path)
    monkeypatch.chdir(repo)
    monkeypatch.delenv("AIT_RUN_ID", raising=False)
    (repo / ".agentic").mkdir()
    (repo / ".agentic" / "current-run").write_text("  valid-run\n")

    runner = CliRunner()
    result = runner.invoke(app, ["run", "show"])
    assert result.exit_code == 6


def test_valid_run_id_still_accepted(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Sanity check: an id that matches the regex resolves normally."""
    repo = _seed_repo(tmp_path)
    monkeypatch.chdir(repo)
    monkeypatch.delenv("AIT_RUN_ID", raising=False)
    (repo / ".agentic").mkdir()
    (repo / ".agentic" / "current-run").write_text("valid-run\n")

    runner = CliRunner()
    result = runner.invoke(app, ["run", "show"])
    assert result.exit_code == 0
    assert "valid-run" in result.stdout
