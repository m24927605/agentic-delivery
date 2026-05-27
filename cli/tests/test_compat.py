from pathlib import Path

import pytest

from agentic.context import CompatError, check_compat


def _write_pipeline(path: Path, version: str) -> None:
    (path / "agentic").mkdir(parents=True, exist_ok=True)
    (path / "agentic" / "pipeline.yaml").write_text(f"pipeline:\n  version: {version}\n")


def test_compat_pass(tmp_path):
    _write_pipeline(tmp_path, "v0.6")
    # ranges loaded from packaged pyproject.toml
    check_compat(repo=tmp_path)


def test_compat_fail_too_new(tmp_path):
    _write_pipeline(tmp_path, "v0.9")
    with pytest.raises(CompatError) as exc:
        check_compat(repo=tmp_path)
    assert "v0.9" in str(exc.value)


def test_compat_skipped_when_disabled(tmp_path):
    _write_pipeline(tmp_path, "v9.9")
    check_compat(repo=tmp_path, enabled=False)  # must not raise
