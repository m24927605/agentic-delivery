import pytest

from agentic.context import RepoNotFound, resolve_repo


def test_walk_up_finds_repo(tmp_path, monkeypatch):
    repo = tmp_path / "repo"
    (repo / "agentic").mkdir(parents=True)
    (repo / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    deep = repo / "a" / "b" / "c"
    deep.mkdir(parents=True)
    monkeypatch.chdir(deep)

    found = resolve_repo()

    assert found.path == repo
    assert found.source == "walk-up"


def test_env_overrides_walk_up(tmp_path, monkeypatch):
    repo = tmp_path / "explicit"
    (repo / "agentic").mkdir(parents=True)
    (repo / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    monkeypatch.setenv("AGENTIC_HOME", str(repo))
    monkeypatch.chdir(tmp_path)

    found = resolve_repo()

    assert found.path == repo
    assert found.source == "AGENTIC_HOME"


def test_flag_overrides_env(tmp_path, monkeypatch):
    other = tmp_path / "other"
    (other / "agentic").mkdir(parents=True)
    (other / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    monkeypatch.setenv("AGENTIC_HOME", "/nonexistent")

    found = resolve_repo(repo_flag=other)

    assert found.path == other
    assert found.source == "--repo"


def test_missing_repo_raises(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    monkeypatch.delenv("AGENTIC_HOME", raising=False)
    with pytest.raises(RepoNotFound):
        resolve_repo()
