"""Tests for cli/agentic/shell.py ScriptRunner."""

from __future__ import annotations

from pathlib import Path

import pytest

from agentic.shell import ScriptError, ScriptRunner


def _stub_repo(tmp_path: Path) -> Path:
    scripts = tmp_path / "scripts"
    scripts.mkdir()
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    return tmp_path


def _write_script(repo: Path, name: str, body: str) -> Path:
    p = repo / "scripts" / name
    p.write_text(body)
    p.chmod(0o755)
    return p


def test_runner_propagates_run_id_and_actor(tmp_path: Path) -> None:
    repo = _stub_repo(tmp_path)
    _write_script(
        repo,
        "echo-env.sh",
        "#!/bin/sh\necho RUN_ID=$RUN_ID AIT_ACTOR=$AIT_ACTOR AIT_ACTOR_ROLE=$AIT_ACTOR_ROLE\n",
    )
    runner = ScriptRunner(repo=repo)
    result = runner.run(
        name="echo-env.sh",
        args=[],
        env_overrides={"RUN_ID": "demo", "AIT_ACTOR": "alice", "AIT_ACTOR_ROLE": "approver"},
    )
    assert result.exit_code == 0
    assert "RUN_ID=demo" in result.stdout
    assert "AIT_ACTOR=alice" in result.stdout
    assert "AIT_ACTOR_ROLE=approver" in result.stdout


def test_runner_maps_nonzero_exit(tmp_path: Path) -> None:
    repo = _stub_repo(tmp_path)
    _write_script(repo, "fail.sh", "#!/bin/sh\necho oops >&2\nexit 7\n")
    runner = ScriptRunner(repo=repo)
    result = runner.run(name="fail.sh", args=[], env_overrides={})
    assert result.exit_code == 7
    assert "oops" in result.stderr


def test_runner_refuses_path_traversal(tmp_path: Path) -> None:
    repo = _stub_repo(tmp_path)
    runner = ScriptRunner(repo=repo)
    with pytest.raises(ScriptError):
        runner.run(name="../etc/passwd", args=[], env_overrides={})


def test_runner_refuses_unknown_script(tmp_path: Path) -> None:
    repo = _stub_repo(tmp_path)
    runner = ScriptRunner(repo=repo)
    with pytest.raises(ScriptError):
        runner.run(name="nonexistent.sh", args=[], env_overrides={})


def test_runner_refuses_leading_dash(tmp_path: Path) -> None:
    """Per spec §11.5: leading dash forbidden to prevent argv parsing confusion."""
    repo = _stub_repo(tmp_path)
    runner = ScriptRunner(repo=repo)
    with pytest.raises(ScriptError):
        runner.run(name="-rf.sh", args=[], env_overrides={})


def test_runner_refuses_non_sh_extension(tmp_path: Path) -> None:
    repo = _stub_repo(tmp_path)
    _write_script(repo, "foo.sh", "#!/bin/sh\nexit 0\n")
    runner = ScriptRunner(repo=repo)
    with pytest.raises(ScriptError):
        runner.run(name="foo.py", args=[], env_overrides={})


def test_runner_forwards_args(tmp_path: Path) -> None:
    repo = _stub_repo(tmp_path)
    _write_script(repo, "args.sh", '#!/bin/sh\necho "got:$1:$2"\n')
    runner = ScriptRunner(repo=repo)
    result = runner.run(name="args.sh", args=["alpha", "beta"], env_overrides={})
    assert result.exit_code == 0
    assert "got:alpha:beta" in result.stdout


def test_runner_can_unset_inherited_env(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """Passing a None value clears an inherited env var before exec."""
    repo = _stub_repo(tmp_path)
    _write_script(repo, "checkenv.sh", "#!/bin/sh\necho FOO=${FOO-unset}\n")
    monkeypatch.setenv("FOO", "from-parent")
    runner = ScriptRunner(repo=repo)
    result = runner.run(name="checkenv.sh", args=[], env_overrides={"FOO": None})  # type: ignore[dict-item]
    assert "FOO=unset" in result.stdout
