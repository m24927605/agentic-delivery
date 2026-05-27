from agentic import __version__
from agentic.app import app


def test_help_exits_zero(cli):
    result = cli.invoke(app, ["--help"])
    assert result.exit_code == 0
    assert "Agentic Delivery" in result.stdout


def test_help_lists_version_command(cli):
    result = cli.invoke(app, ["--help"])
    assert result.exit_code == 0
    assert "version" in result.stdout


def test_version_command_prints_version(cli):
    result = cli.invoke(app, ["version"])
    assert result.exit_code == 0
    assert __version__ in result.stdout


def test_version_command_prints_python(cli):
    result = cli.invoke(app, ["version"])
    assert result.exit_code == 0
    assert "python" in result.stdout.lower()


def test_version_includes_repo_when_resolvable(cli, tmp_path, monkeypatch):
    (tmp_path / "agentic").mkdir(parents=True)
    (tmp_path / "agentic" / "pipeline.yaml").write_text(
        "pipeline:\n  version: v0.6\n"
    )
    monkeypatch.chdir(tmp_path)
    monkeypatch.delenv("AGENTIC_HOME", raising=False)

    result = cli.invoke(app, ["version"])

    assert result.exit_code == 0
    assert "repo:" in result.stdout
    assert str(tmp_path) in result.stdout


def test_version_handles_missing_repo(cli, tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    monkeypatch.delenv("AGENTIC_HOME", raising=False)

    result = cli.invoke(app, ["version"])

    assert result.exit_code == 0  # version itself must not fail
    assert "repo:" in result.stdout
    assert "not found" in result.stdout.lower()
