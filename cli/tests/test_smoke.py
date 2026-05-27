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
