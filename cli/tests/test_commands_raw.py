"""Tests for `agentic raw <script.sh> [-- args...]` escape hatch.

Spec §11.5 mandates 4 pre-exec security checks; tests below cover each:
  1. Name regex (^[a-z0-9][a-z0-9-]*\\.sh$) — leading dash forbidden.
  2. Realpath containment in scripts/ — symlinks escaping are refused.
  3. Argument delimiter '--' — extras forwarded only after literal '--'.
  4. TOCTOU closure — validated realpath is what gets exec'd.
"""

from __future__ import annotations

import os
from pathlib import Path

import pytest
from typer.testing import CliRunner

from agentic.app import app
from agentic.commands import raw as raw_cmd
from agentic.shell import ShellResult
from tests._recording import RecordingRunner


def _seed(tmp_path: Path, scripts: dict[str, str] | None = None) -> Path:
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    (tmp_path / "scripts").mkdir()
    for name, body in (scripts or {}).items():
        p = tmp_path / "scripts" / name
        p.write_text(body)
        p.chmod(0o755)
    return tmp_path


@pytest.fixture
def runner(monkeypatch: pytest.MonkeyPatch) -> RecordingRunner:
    rr = RecordingRunner()
    monkeypatch.setattr(raw_cmd, "_runner_factory", lambda repo: rr)
    return rr


# --------------------------------------------------------------------------- #
# Happy path
# --------------------------------------------------------------------------- #


def test_raw_routes_to_named_script_no_extra_args(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path, {"validate-agentic-system.sh": "#!/bin/sh\nexit 0\n"})
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["raw", "validate-agentic-system.sh"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "validate-agentic-system.sh"
    assert call.args == ()


def test_raw_forwards_args_after_double_dash(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path, {"foo.sh": "#!/bin/sh\nexit 0\n"})
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["raw", "foo.sh", "--", "--verbose", "alpha"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    assert call.name == "foo.sh"
    assert call.args == ("--verbose", "alpha")


def test_raw_passes_resolved_path_to_runner(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    """Spec §11.5 check 4: the realpath result MUST be what is exec'd."""
    repo = _seed(tmp_path, {"foo.sh": "#!/bin/sh\nexit 0\n"})
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["raw", "foo.sh"])
    assert result.exit_code == 0, result.output
    call = runner.calls[-1]
    expected = Path(os.path.realpath(repo / "scripts" / "foo.sh"))
    assert call.script_path == expected


# --------------------------------------------------------------------------- #
# Security check 1: name regex
# --------------------------------------------------------------------------- #


def test_raw_refuses_leading_dash(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    """Spec §11.5 check 1: leading dash is the classic argv parsing trap."""
    repo = _seed(tmp_path, {"a.sh": "#!/bin/sh\nexit 0\n"})
    monkeypatch.chdir(repo)
    # Use `--` so Click doesn't parse '-rf.sh' as an option for the raw command.
    result = cli.invoke(app, ["raw", "--", "-rf.sh"])
    assert result.exit_code != 0
    assert runner.calls == []


def test_raw_refuses_non_sh_extension(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path, {"a.sh": "#!/bin/sh\nexit 0\n"})
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["raw", "evil"])
    assert result.exit_code != 0
    assert runner.calls == []


def test_raw_refuses_uppercase_name(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path, {"a.sh": "#!/bin/sh\nexit 0\n"})
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["raw", "FOO.sh"])
    assert result.exit_code != 0
    assert runner.calls == []


# --------------------------------------------------------------------------- #
# Security check 2: realpath containment
# --------------------------------------------------------------------------- #


def test_raw_refuses_absolute(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path, {"a.sh": "#!/bin/sh\nexit 0\n"})
    monkeypatch.chdir(repo)
    # Use `--` to ensure '/bin/sh' reaches the script argument rather than
    # being treated as something weird; the name-regex check should reject it.
    result = cli.invoke(app, ["raw", "--", "/bin/sh"])
    assert result.exit_code != 0
    assert runner.calls == []


def test_raw_refuses_path_traversal(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path, {"a.sh": "#!/bin/sh\nexit 0\n"})
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["raw", "../etc/passwd"])
    assert result.exit_code != 0
    assert runner.calls == []


def test_raw_refuses_symlink_out_of_repo(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    """Spec §11.5 check 2: symlink whose target is outside scripts/ is refused."""
    repo = _seed(tmp_path)
    outside = tmp_path / "outside.sh"
    outside.write_text("#!/bin/sh\necho pwned\n")
    outside.chmod(0o755)
    link = repo / "scripts" / "evil.sh"
    link.symlink_to(outside)

    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["raw", "evil.sh"])
    assert result.exit_code != 0, result.output
    assert runner.calls == []


def test_raw_refuses_symlink_loop(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    """Symlink loops trigger ELOOP — must be caught, not crash."""
    repo = _seed(tmp_path)
    a = repo / "scripts" / "a.sh"
    b = repo / "scripts" / "b.sh"
    a.symlink_to(b)
    b.symlink_to(a)

    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["raw", "a.sh"])
    assert result.exit_code != 0, result.output
    assert runner.calls == []


def test_raw_refuses_symlink_to_symlink(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    """Spec §11.5 check 2: chained symlinks (sym -> sym -> file) are refused.

    Realpath would resolve them and they might land inside scripts/, but the
    extra indirection violates the audit-friendly assumption that scripts/*.sh
    is either a regular file or a single-hop symlink.
    """
    repo = _seed(tmp_path, {"target.sh": "#!/bin/sh\nexit 0\n"})
    mid = repo / "scripts" / "mid.sh"
    head = repo / "scripts" / "head.sh"
    mid.symlink_to(repo / "scripts" / "target.sh")
    head.symlink_to(mid)

    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["raw", "head.sh"])
    assert result.exit_code != 0, result.output
    assert runner.calls == []


# --------------------------------------------------------------------------- #
# Security check 3: '--' boundary
# --------------------------------------------------------------------------- #


def test_raw_unknown_flag_without_double_dash_refused(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    """Spec §11.5 check 3: extras must come after literal '--'.

    Without '--', Click parses '--unknown' as an option for the raw command,
    fails (no such option), and never reaches the script — preventing accidental
    injection of CLI-level flags into the forwarded script invocation.
    """
    repo = _seed(tmp_path, {"foo.sh": "#!/bin/sh\nexit 0\n"})
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["raw", "foo.sh", "--unknown-flag"])
    assert result.exit_code != 0
    assert runner.calls == []


# --------------------------------------------------------------------------- #
# Missing-file / unhappy paths
# --------------------------------------------------------------------------- #


def test_raw_refuses_missing(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    runner: RecordingRunner,
) -> None:
    repo = _seed(tmp_path, {"a.sh": "#!/bin/sh\nexit 0\n"})
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["raw", "nonexistent.sh"])
    assert result.exit_code != 0
    assert runner.calls == []


# --------------------------------------------------------------------------- #
# Exit-code forwarding
# --------------------------------------------------------------------------- #


def test_raw_forwards_exit_code_64_plus_n(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """E2E (no RecordingRunner) — script exit 7 must map to 71 per spec §9.3."""
    repo = _seed(tmp_path, {"fail.sh": "#!/bin/sh\nexit 7\n"})
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["raw", "fail.sh"])
    assert result.exit_code == 64 + 7


def test_raw_clamps_high_exit_to_15(
    cli: CliRunner,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Spec §9.3: exits clamp at 64+15=79."""
    rr = RecordingRunner(next_result=ShellResult(exit_code=200, stdout="", stderr=""))
    monkeypatch.setattr(raw_cmd, "_runner_factory", lambda repo: rr)
    repo = _seed(tmp_path, {"foo.sh": "#!/bin/sh\nexit 0\n"})
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["raw", "foo.sh"])
    assert result.exit_code == 79
