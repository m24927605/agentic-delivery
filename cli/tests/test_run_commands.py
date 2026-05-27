from pathlib import Path

from agentic.app import app


def _seed(tmp_path: Path, runs: list[str]) -> Path:
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    for r in runs:
        d = tmp_path / "agentic" / "runs" / r
        d.mkdir(parents=True)
        (d / "manifest.yaml").write_text("run:\n  id: " + r + "\n")
    return tmp_path


def test_run_use_writes_file(cli, tmp_path, monkeypatch):
    repo = _seed(tmp_path, ["alpha", "beta"])
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["run", "use", "alpha"])
    assert result.exit_code == 0
    assert (repo / ".agentic" / "current-run").read_text().strip() == "alpha"


def test_run_use_rejects_unknown(cli, tmp_path, monkeypatch):
    repo = _seed(tmp_path, ["alpha"])
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["run", "use", "ghost"])
    assert result.exit_code != 0
    assert "does not exist" in result.stderr.lower() or "does not exist" in result.stdout.lower()


def test_run_show_prints_source(cli, tmp_path, monkeypatch):
    repo = _seed(tmp_path, ["alpha"])
    (repo / ".agentic").mkdir()
    (repo / ".agentic" / "current-run").write_text("alpha\n")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["run", "show"])
    assert result.exit_code == 0
    assert "alpha" in result.stdout
    assert "file:.agentic/current-run" in result.stdout


def test_run_clear_deletes_file(cli, tmp_path, monkeypatch):
    repo = _seed(tmp_path, ["alpha"])
    (repo / ".agentic").mkdir()
    (repo / ".agentic" / "current-run").write_text("alpha\n")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["run", "clear"])
    assert result.exit_code == 0
    assert not (repo / ".agentic" / "current-run").exists()


def test_run_list_marks_current(cli, tmp_path, monkeypatch):
    repo = _seed(tmp_path, ["alpha", "beta"])
    (repo / ".agentic").mkdir()
    (repo / ".agentic" / "current-run").write_text("beta\n")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["run", "list"])
    assert result.exit_code == 0
    assert "alpha" in result.stdout
    assert "beta" in result.stdout
    # beta is current; should be marked with *
    line_with_beta = next(line for line in result.stdout.splitlines() if "beta" in line)
    assert "*" in line_with_beta
