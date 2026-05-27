from pathlib import Path

import pytest

from agentic.context import CompatError, check_compat


def _write_pipeline(path: Path, version: str) -> None:
    (path / "agentic").mkdir(parents=True, exist_ok=True)
    (path / "agentic" / "pipeline.yaml").write_text(f"pipeline:\n  version: {version}\n")


def test_compat_pass(tmp_path):
    _write_pipeline(tmp_path, "v0.6")
    result = check_compat(repo=tmp_path)
    assert result is not None
    assert result.status == "compatible"


def test_compat_fail_too_new(tmp_path):
    # v2.0 is a major-version mismatch against the declared >=0.6,<0.8 range
    # and therefore raises CompatError (tier per spec §8.4).
    _write_pipeline(tmp_path, "v2.0")
    with pytest.raises(CompatError) as exc:
        check_compat(repo=tmp_path)
    assert "v2.0" in str(exc.value)


def test_compat_skipped_when_disabled(tmp_path):
    _write_pipeline(tmp_path, "v9.9")
    assert check_compat(repo=tmp_path, enabled=False) is None  # must not raise


def test_compat_patch_mismatch_warns(tmp_path, monkeypatch, capsys):
    _write_pipeline(tmp_path, "v0.6.9")
    monkeypatch.setattr(
        "agentic.context.COMPATIBLE_PIPELINE_VERSIONS", [">=0.6.0,<0.6.5"]
    )
    result = check_compat(repo=tmp_path)
    assert result is not None
    assert result.status == "patch-mismatch"
    captured = capsys.readouterr()
    assert "patch mismatch" in captured.err
    assert "v0.6.9" in captured.err


def test_compat_minor_mismatch_warns(tmp_path, capsys):
    # v0.9 is two minor bumps past the declared >=0.6,<0.8 band — still same major.
    _write_pipeline(tmp_path, "v0.9")
    result = check_compat(repo=tmp_path)
    assert result is not None
    assert result.status == "minor-mismatch"
    captured = capsys.readouterr()
    assert "minor mismatch" in captured.err
    assert "v0.9" in captured.err


def test_compat_major_mismatch_raises(tmp_path):
    _write_pipeline(tmp_path, "v1.0")
    with pytest.raises(CompatError) as exc:
        check_compat(repo=tmp_path)
    assert exc.value.exit_code == 5
    assert exc.value.actual == "v1.0"
    assert exc.value.ranges == [">=0.6,<0.8"]


def test_compat_empty_constant_is_misconfig(tmp_path, monkeypatch):
    _write_pipeline(tmp_path, "v0.6")
    monkeypatch.setattr("agentic.context.COMPATIBLE_PIPELINE_VERSIONS", [])
    with pytest.raises(RuntimeError, match="COMPATIBLE_PIPELINE_VERSIONS empty"):
        check_compat(repo=tmp_path)
