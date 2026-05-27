from pathlib import Path

import pytest

from agentic.context import RunNotFound, resolve_run_id


def _seed_repo(tmp_path: Path, *, runs: list[str], current: str | None = None) -> Path:
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    for r in runs:
        (tmp_path / "agentic" / "runs" / r).mkdir(parents=True)
        (tmp_path / "agentic" / "runs" / r / "manifest.yaml").write_text("run:\n  id: " + r + "\n")
    if current is not None:
        (tmp_path / ".agentic").mkdir()
        (tmp_path / ".agentic" / "current-run").write_text(current + "\n")
    return tmp_path


def test_flag_beats_env_beats_file(tmp_path, monkeypatch):
    repo = _seed_repo(tmp_path, runs=["a", "b", "c"], current="a")
    monkeypatch.setenv("AIT_RUN_ID", "b")
    run = resolve_run_id(repo=repo, flag="c")
    assert run.id == "c"
    assert run.source == "--run-id"


def test_env_beats_file_when_no_flag(tmp_path, monkeypatch):
    repo = _seed_repo(tmp_path, runs=["a", "b"], current="a")
    monkeypatch.setenv("AIT_RUN_ID", "b")
    run = resolve_run_id(repo=repo, flag=None)
    assert run.id == "b"
    assert run.source == "AIT_RUN_ID"


def test_file_used_when_no_flag_no_env(tmp_path, monkeypatch):
    repo = _seed_repo(tmp_path, runs=["a"], current="a")
    monkeypatch.delenv("AIT_RUN_ID", raising=False)
    run = resolve_run_id(repo=repo, flag=None)
    assert run.id == "a"
    assert run.source == "file:.agentic/current-run"


def test_missing_raises(tmp_path, monkeypatch):
    repo = _seed_repo(tmp_path, runs=["a"])
    monkeypatch.delenv("AIT_RUN_ID", raising=False)
    with pytest.raises(RunNotFound):
        resolve_run_id(repo=repo, flag=None)


def test_unknown_run_rejected(tmp_path, monkeypatch):
    repo = _seed_repo(tmp_path, runs=["a"])
    monkeypatch.delenv("AIT_RUN_ID", raising=False)
    with pytest.raises(RunNotFound):
        resolve_run_id(repo=repo, flag="ghost")


def test_empty_file_falls_through(tmp_path, monkeypatch):
    repo = _seed_repo(tmp_path, runs=["a"], current="")
    monkeypatch.setenv("AIT_RUN_ID", "a")
    run = resolve_run_id(repo=repo, flag=None)
    assert run.id == "a"
    assert run.source == "AIT_RUN_ID"
