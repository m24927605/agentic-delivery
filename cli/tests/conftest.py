import pytest
from typer.testing import CliRunner


@pytest.fixture
def cli():
    return CliRunner()
