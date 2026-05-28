"""Conformance: every `--json` command + error envelope matches cli_v1.schema.json.

Spec §9.5.1 locks the ``agentic.cli/v1`` envelope. Adding new top-level keys
is allowed under v1, but the shapes inside (``run`` / ``artifacts`` / ``tasks``
/ ``next`` / ``checks`` / ``error``) cannot change without a major bump. This
file validates the live CLI output against the schema using ``jsonschema``.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from jsonschema import Draft202012Validator
from typer.testing import CliRunner

from agentic.app import app


SCHEMA_PATH = Path(__file__).resolve().parents[1] / "agentic" / "schemas" / "cli_v1.schema.json"
STATUS_FIXTURES = Path(__file__).parent / "fixtures" / "manifests"
STATE_FIXTURES = Path(__file__).parent / "state_engine" / "fixtures"


@pytest.fixture(scope="module")
def validator() -> Draft202012Validator:
    schema = json.loads(SCHEMA_PATH.read_text())
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema)


def _seed(
    tmp_path: Path,
    *,
    fixture_path: Path,
    run_id: str,
    impl: bool = False,
) -> Path:
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    d = tmp_path / "agentic" / "runs" / run_id
    d.mkdir(parents=True)
    name = "implementation-manifest.yaml" if impl else "manifest.yaml"
    (d / name).write_text(fixture_path.read_text())
    return tmp_path


def test_status_planning_json_conforms(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    validator: Draft202012Validator,
) -> None:
    repo = _seed(
        tmp_path, fixture_path=STATUS_FIXTURES / "planning_fresh.yaml", run_id="demo"
    )
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["--json", "status", "--run-id", "demo"])
    assert result.exit_code == 0, result.output
    payload = json.loads(result.stdout)
    errors = sorted(validator.iter_errors(payload), key=lambda e: list(e.absolute_path))
    assert not errors, "\n".join(f"{list(e.absolute_path)}: {e.message}" for e in errors)


def test_status_implementation_json_conforms(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    validator: Draft202012Validator,
) -> None:
    repo = _seed(
        tmp_path,
        fixture_path=STATUS_FIXTURES / "impl_mid_dispatch.yaml",
        run_id="demo-impl",
        impl=True,
    )
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["--json", "status", "--run-id", "demo-impl"])
    assert result.exit_code == 0, result.output
    payload = json.loads(result.stdout)
    errors = sorted(validator.iter_errors(payload), key=lambda e: list(e.absolute_path))
    assert not errors, "\n".join(f"{list(e.absolute_path)}: {e.message}" for e in errors)


def test_next_planning_json_conforms(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    validator: Draft202012Validator,
) -> None:
    repo = _seed(
        tmp_path, fixture_path=STATE_FIXTURES / "planning_fresh_init.yaml", run_id="demo"
    )
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["--json", "next", "--run-id", "demo"])
    assert result.exit_code == 0, result.output
    payload = json.loads(result.stdout)
    errors = sorted(validator.iter_errors(payload), key=lambda e: list(e.absolute_path))
    assert not errors, "\n".join(f"{list(e.absolute_path)}: {e.message}" for e in errors)


def test_next_implementation_json_conforms(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    validator: Draft202012Validator,
) -> None:
    repo = _seed(
        tmp_path,
        fixture_path=STATE_FIXTURES / "impl_pending_task.yaml",
        run_id="demo-impl",
        impl=True,
    )
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["--json", "next", "--run-id", "demo-impl"])
    assert result.exit_code == 0, result.output
    payload = json.loads(result.stdout)
    errors = sorted(validator.iter_errors(payload), key=lambda e: list(e.absolute_path))
    assert not errors, "\n".join(f"{list(e.absolute_path)}: {e.message}" for e in errors)


def test_no_repo_error_envelope_conforms(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    validator: Draft202012Validator,
) -> None:
    monkeypatch.chdir(tmp_path)
    monkeypatch.delenv("AGENTIC_HOME", raising=False)
    result = cli.invoke(app, ["--json", "status"])
    assert result.exit_code == 6
    payload = json.loads(result.stderr)
    errors = sorted(validator.iter_errors(payload), key=lambda e: list(e.absolute_path))
    assert not errors, "\n".join(f"{list(e.absolute_path)}: {e.message}" for e in errors)


def test_no_run_context_error_envelope_conforms(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    validator: Draft202012Validator,
) -> None:
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    monkeypatch.chdir(tmp_path)
    monkeypatch.delenv("AGENTIC_HOME", raising=False)
    monkeypatch.delenv("AIT_RUN_ID", raising=False)
    result = cli.invoke(app, ["--json", "next"])
    assert result.exit_code == 6
    payload = json.loads(result.stderr)
    errors = sorted(validator.iter_errors(payload), key=lambda e: list(e.absolute_path))
    assert not errors, "\n".join(f"{list(e.absolute_path)}: {e.message}" for e in errors)
    assert payload["error"]["category"] == "no_run_context"


def test_schema_itself_is_valid_draft_2020_12(validator: Draft202012Validator) -> None:
    """Sanity: the schema file parses and is itself a valid draft 2020-12 schema."""
    schema = json.loads(SCHEMA_PATH.read_text())
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["properties"]["_schema"]["const"] == "agentic.cli/v1"


def test_schema_rejects_unknown_top_level_key(validator: Draft202012Validator) -> None:
    """Unknown top-level keys are an error (additionalProperties: false)."""
    bad = {"_schema": "agentic.cli/v1", "not_a_real_key": 42}
    errors = list(validator.iter_errors(bad))
    assert errors, "expected schema to reject unknown top-level keys"


def test_schema_rejects_missing_run_field(validator: Draft202012Validator) -> None:
    """``run`` requires all five fields (id/mode/profile/state/source)."""
    bad = {"_schema": "agentic.cli/v1", "run": {"id": "x", "mode": "planning"}}
    errors = list(validator.iter_errors(bad))
    assert errors, "expected schema to reject incomplete run subobject"
