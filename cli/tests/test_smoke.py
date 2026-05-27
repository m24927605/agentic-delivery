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
    # compat line is printed when repo resolves
    assert "pipeline:" in result.stdout
    assert "compatible" in result.stdout


def test_version_handles_missing_repo(cli, tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    monkeypatch.delenv("AGENTIC_HOME", raising=False)

    result = cli.invoke(app, ["version"])

    assert result.exit_code == 0  # version itself must not fail
    assert "repo:" in result.stdout
    assert "not found" in result.stdout.lower()


def test_version_warn_continues_on_minor_mismatch(cli, tmp_path, monkeypatch):
    # v0.9 is a minor mismatch against the declared >=0.6,<0.8 band.
    # version must continue (exit 0) but emit the mismatch line.
    (tmp_path / "agentic").mkdir(parents=True)
    (tmp_path / "agentic" / "pipeline.yaml").write_text(
        "pipeline:\n  version: v0.9\n"
    )
    monkeypatch.chdir(tmp_path)
    monkeypatch.delenv("AGENTIC_HOME", raising=False)

    result = cli.invoke(app, ["version"])

    assert result.exit_code == 0
    assert "pipeline:" in result.stdout
    # The minor-mismatch line is printed both to stdout (version line) and to
    # stderr (check_compat's warning). CliRunner mixes streams by default.
    assert "minor mismatch" in result.stdout


def test_version_exits_5_on_major_mismatch(cli, tmp_path, monkeypatch):
    (tmp_path / "agentic").mkdir(parents=True)
    (tmp_path / "agentic" / "pipeline.yaml").write_text(
        "pipeline:\n  version: v2.0\n"
    )
    monkeypatch.chdir(tmp_path)
    monkeypatch.delenv("AGENTIC_HOME", raising=False)

    result = cli.invoke(app, ["version"])

    assert result.exit_code == 5
    assert "major mismatch" in result.stdout


def test_version_no_compat_check_skips(cli, tmp_path, monkeypatch):
    # With --no-compat-check, an otherwise incompatible pipeline.yaml must not fail.
    (tmp_path / "agentic").mkdir(parents=True)
    (tmp_path / "agentic" / "pipeline.yaml").write_text(
        "pipeline:\n  version: v9.9\n"
    )
    monkeypatch.chdir(tmp_path)
    monkeypatch.delenv("AGENTIC_HOME", raising=False)

    result = cli.invoke(app, ["--no-compat-check", "version"])

    assert result.exit_code == 0
