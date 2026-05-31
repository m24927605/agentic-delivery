"""Integration: a scaffolded project must pass validate-agentic-system.sh.

Skipped on non-POSIX. Requires ``bash``, ``yq``-free
``validate-agentic-system.sh`` runs (already true), and a real built wheel so
the bundled scaffold is present. Uses ``pip install <cli_root>`` once per
session — this triggers the Hatch build hook that populates
``cli/agentic/scaffold/_scaffold/`` in an isolated build, so the source
tree's placeholder ``__init__.py`` is not affected.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

pytestmark = pytest.mark.skipif(
    os.name != "posix" or not shutil.which("bash"),
    reason="POSIX shell required",
)


@pytest.fixture(scope="session")
def installed_cli(tmp_path_factory):
    """Build the wheel, install it into a fresh venv, return that venv's ``agentic`` path."""
    cli_root = Path(__file__).resolve().parents[1]
    out = tmp_path_factory.mktemp("install")
    venv = out / "venv"
    subprocess.run([sys.executable, "-m", "venv", str(venv)], check=True)
    subprocess.run(
        [str(venv / "bin" / "pip"), "install", "--upgrade", "pip", "wheel", "build"],
        check=True,
        capture_output=True,
        text=True,
    )
    # Install the CLI from source — this triggers the Hatch build hook in
    # an isolated build directory, so the repo's
    # ``cli/agentic/scaffold/_scaffold/__init__.py`` placeholder is not
    # mutated.
    result = subprocess.run(
        [str(venv / "bin" / "pip"), "install", str(cli_root)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"pip install failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return venv / "bin" / "agentic"


def test_scaffolded_project_validates(installed_cli, tmp_path):
    subprocess.run(
        [str(installed_cli), "new", "demo", "--no-git", "--path", str(tmp_path)],
        check=True,
    )
    target = tmp_path / "demo"
    result = subprocess.run(
        ["bash", "scripts/validate-agentic-system.sh"],
        cwd=target,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        "validate-agentic-system.sh failed in scaffolded project\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
