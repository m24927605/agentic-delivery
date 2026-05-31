"""Tests for `agentic new` — the scaffold materialization command."""
from __future__ import annotations

import stat as _stat
from pathlib import Path

import pytest
from typer.testing import CliRunner

from agentic.app import app


runner = CliRunner()


def _fake_bundle(tmp_path: Path) -> Path:
    """Build a minimal fake scaffold bundle for monkeypatching ``_resource_root``.

    Includes one nested data file, one executable script, and one templated
    README so individual tests can exercise all three copy paths without
    standing up a full bundle.
    """
    root = tmp_path / "bundle"
    (root / "agentic").mkdir(parents=True)
    (root / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    (root / "scripts").mkdir()
    sh = root / "scripts" / "demo.sh"
    sh.write_text("#!/usr/bin/env bash\n")
    sh.chmod(0o755)
    (root / "README.md").write_text("# {{PROJECT_NAME}}\nCLI v{{CLI_VERSION}}\n")
    return root


@pytest.mark.parametrize("bad", ["", "foo/bar", "../escape", "a\x00b"])
def test_new_rejects_bad_name(bad):
    result = runner.invoke(app, ["new", bad])
    assert result.exit_code == 2, result.stderr
    assert "name must be a single path segment" in result.stderr


def test_new_target_does_not_exist_creates_and_copies(tmp_path, monkeypatch):
    from agentic import scaffold as scaffold_pkg

    fake_root = _fake_bundle(tmp_path)
    monkeypatch.setattr(scaffold_pkg, "_resource_root", lambda: fake_root)
    monkeypatch.chdir(tmp_path)
    result = runner.invoke(app, ["new", "proj", "--no-git"])
    assert result.exit_code == 0, result.stderr + (result.stdout or "")
    target = tmp_path / "proj"
    assert target.is_dir()
    assert (target / "agentic" / "pipeline.yaml").exists()


def test_new_target_existing_empty_without_force_fails(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / "proj").mkdir()
    result = runner.invoke(app, ["new", "proj"])
    assert result.exit_code == 9, result.stderr
    assert "rerun with `--force`" in result.stderr


def test_new_target_existing_empty_with_force_copies(tmp_path, monkeypatch):
    from agentic import scaffold as scaffold_pkg

    fake_root = _fake_bundle(tmp_path)
    monkeypatch.setattr(scaffold_pkg, "_resource_root", lambda: fake_root)
    monkeypatch.chdir(tmp_path)
    (tmp_path / "proj").mkdir()
    result = runner.invoke(app, ["new", "proj", "--no-git", "--force"])
    assert result.exit_code == 0, result.stderr + (result.stdout or "")
    assert (tmp_path / "proj" / "agentic" / "pipeline.yaml").exists()


def test_new_target_existing_nonempty_fails(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / "proj").mkdir()
    (tmp_path / "proj" / "stray.txt").write_text("x")
    result = runner.invoke(app, ["new", "proj"])
    assert result.exit_code == 9, result.stderr
    assert "target exists and is non-empty" in result.stderr
    assert "stray.txt" in result.stderr


def test_new_target_existing_nonempty_with_force_still_fails(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / "proj").mkdir()
    (tmp_path / "proj" / "stray.txt").write_text("x")
    result = runner.invoke(app, ["new", "proj", "--force"])
    assert result.exit_code == 9
    assert "non-empty" in result.stderr


def test_new_target_existing_nonempty_truncates_entries_with_ellipsis(tmp_path, monkeypatch):
    """When more than 5 entries exist, the error message lists 5 + 'X more'."""
    monkeypatch.chdir(tmp_path)
    (tmp_path / "proj").mkdir()
    for i in range(8):
        (tmp_path / "proj" / f"file_{i:02d}.txt").write_text("x")
    result = runner.invoke(app, ["new", "proj"])
    assert result.exit_code == 9
    assert "non-empty" in result.stderr
    assert "... (3 more)" in result.stderr


def test_new_copies_bundle_into_target(tmp_path, monkeypatch):
    from agentic import scaffold as scaffold_pkg

    fake_root = _fake_bundle(tmp_path)
    monkeypatch.setattr(scaffold_pkg, "_resource_root", lambda: fake_root)
    monkeypatch.chdir(tmp_path)

    result = runner.invoke(app, ["new", "proj", "--no-git"])
    assert result.exit_code == 0, result.stderr + (result.stdout or "")

    target = tmp_path / "proj"
    assert (target / "agentic" / "pipeline.yaml").read_text().startswith("pipeline:")
    assert (target / "scripts" / "demo.sh").exists()

    assert (target / "scripts" / "demo.sh").stat().st_mode & _stat.S_IXUSR

    readme = (target / "README.md").read_text()
    assert "# proj" in readme
    assert "{{PROJECT_NAME}}" not in readme
    assert "{{CLI_VERSION}}" not in readme


def test_new_non_template_files_keep_placeholder_syntax_literally(tmp_path, monkeypatch):
    """Only ``_TEMPLATE_FILES`` should get placeholder substitution.

    A YAML file containing ``{{PROJECT_NAME}}`` must round-trip unchanged.
    """
    from agentic import scaffold as scaffold_pkg

    root = tmp_path / "bundle"
    (root / "agentic").mkdir(parents=True)
    (root / "agentic" / "data.yaml").write_text("note: {{PROJECT_NAME}} stays literal\n")
    (root / "README.md").write_text("# {{PROJECT_NAME}}\n")
    monkeypatch.setattr(scaffold_pkg, "_resource_root", lambda: root)
    monkeypatch.chdir(tmp_path)

    result = runner.invoke(app, ["new", "proj", "--no-git"])
    assert result.exit_code == 0, result.stderr + (result.stdout or "")

    yaml_text = (tmp_path / "proj" / "agentic" / "data.yaml").read_text()
    assert "{{PROJECT_NAME}}" in yaml_text  # NOT substituted
    readme = (tmp_path / "proj" / "README.md").read_text()
    assert "# proj" in readme  # substituted


def test_new_raises_bundle_missing_when_empty(tmp_path, monkeypatch):
    from agentic import scaffold as scaffold_pkg

    empty = tmp_path / "empty"
    empty.mkdir()
    monkeypatch.setattr(scaffold_pkg, "_resource_root", lambda: empty)
    monkeypatch.chdir(tmp_path)

    result = runner.invoke(app, ["new", "proj", "--no-git"])
    assert result.exit_code == 11
    assert "scaffold bundle" in result.stderr
    # I-1: target dir must NOT be created when the bundle is missing — otherwise
    # a retry trips the misleading scaffold_target_exists path.
    assert not (tmp_path / "proj").exists(), "target dir leaked on bundle-missing failure"


def test_new_initializes_git_repo_by_default(tmp_path, monkeypatch):
    from agentic import scaffold as scaffold_pkg

    fake_root = _fake_bundle(tmp_path)
    monkeypatch.setattr(scaffold_pkg, "_resource_root", lambda: fake_root)
    monkeypatch.chdir(tmp_path)

    result = runner.invoke(app, ["new", "proj"])
    assert result.exit_code == 0, result.stderr + (result.stdout or "")

    target = tmp_path / "proj"
    assert (target / ".git").is_dir()
    # exactly one commit
    import subprocess
    log = subprocess.run(
        ["git", "-C", str(target), "log", "--oneline"],
        check=True, capture_output=True, text=True,
    ).stdout.strip().splitlines()
    assert len(log) == 1
    assert "bootstrap agentic-delivery scaffold" in log[0]


def test_new_no_git_skips_repo(tmp_path, monkeypatch):
    from agentic import scaffold as scaffold_pkg

    fake_root = _fake_bundle(tmp_path)
    monkeypatch.setattr(scaffold_pkg, "_resource_root", lambda: fake_root)
    monkeypatch.chdir(tmp_path)

    result = runner.invoke(app, ["new", "proj", "--no-git"])
    assert result.exit_code == 0
    assert not (tmp_path / "proj" / ".git").exists()


def test_new_reports_git_failure(tmp_path, monkeypatch):
    from agentic import scaffold as scaffold_pkg

    fake_root = _fake_bundle(tmp_path)
    monkeypatch.setattr(scaffold_pkg, "_resource_root", lambda: fake_root)
    monkeypatch.chdir(tmp_path)

    # Make git resolve to a non-existent path so subprocess.run fails with FileNotFoundError
    monkeypatch.setenv("PATH", "/nonexistent")

    result = runner.invoke(app, ["new", "proj"])
    assert result.exit_code == 10
    assert "git" in result.stderr.lower()


def test_new_prints_success_banner(tmp_path, monkeypatch):
    from agentic import scaffold as scaffold_pkg

    fake_root = _fake_bundle(tmp_path)
    monkeypatch.setattr(scaffold_pkg, "_resource_root", lambda: fake_root)
    monkeypatch.chdir(tmp_path)

    result = runner.invoke(app, ["new", "proj", "--no-git"])
    assert result.exit_code == 0, result.stderr + (result.stdout or "")
    assert "Scaffolded proj" in result.stdout
    assert "scripts/validate-agentic-system.sh" in result.stdout
    assert "agentic init" in result.stdout
    assert "agentic next" in result.stdout


def test_new_banner_includes_amend_hint_when_git_initialized(tmp_path, monkeypatch):
    """When git=True, the banner should mention the hardcoded bootstrap author
    and the `git commit --amend --reset-author` claim instruction."""
    from agentic import scaffold as scaffold_pkg

    fake_root = _fake_bundle(tmp_path)
    monkeypatch.setattr(scaffold_pkg, "_resource_root", lambda: fake_root)
    monkeypatch.chdir(tmp_path)

    result = runner.invoke(app, ["new", "projg"])
    assert result.exit_code == 0, result.stderr + (result.stdout or "")
    assert "Initialized git repo" in result.stdout
    assert "amend --reset-author" in result.stdout
    assert "agentic@local" in result.stdout


def test_new_json_mode_emits_envelope(tmp_path, monkeypatch):
    from agentic import scaffold as scaffold_pkg

    fake_root = _fake_bundle(tmp_path)
    monkeypatch.setattr(scaffold_pkg, "_resource_root", lambda: fake_root)
    monkeypatch.chdir(tmp_path)

    result = runner.invoke(app, ["--json", "new", "proj", "--no-git"])
    assert result.exit_code == 0, result.stderr
    import json
    payload = json.loads(result.stdout)
    assert payload["status"] == "ok"
    assert payload["command"] == "new"
    assert payload["target"].endswith("/proj")
    assert payload["files_written"] >= 1
    assert payload["git_initialized"] is False


def test_new_bypasses_gpg_signing_for_bootstrap_commit(tmp_path, monkeypatch):
    """Users with commit.gpgsign=true globally should not have the bootstrap
    commit fail. The CLI passes -c commit.gpgsign=false to override.

    Approach: capture the actual ``subprocess.run`` argv for the commit call
    and assert the gpgsign-disabling -c flags are present BEFORE the -C flag.
    """
    from agentic import scaffold as scaffold_pkg
    import subprocess as _subprocess

    fake_root = _fake_bundle(tmp_path)
    monkeypatch.setattr(scaffold_pkg, "_resource_root", lambda: fake_root)
    monkeypatch.chdir(tmp_path)

    real_run = _subprocess.run
    captured: list[list[str]] = []

    def spy_run(argv, *args, **kwargs):
        captured.append(list(argv))
        return real_run(argv, *args, **kwargs)

    monkeypatch.setattr("agentic.commands.new.subprocess.run", spy_run)

    result = runner.invoke(app, ["new", "projgpg"])
    assert result.exit_code == 0, result.stderr + (result.stdout or "")
    assert (tmp_path / "projgpg" / ".git").is_dir()

    # Find the commit invocation; assert -c commit.gpgsign=false comes before -C
    commit_calls = [a for a in captured if "commit" in a and "-m" in a]
    assert commit_calls, f"no commit subprocess call recorded: {captured}"
    argv = commit_calls[0]
    assert "-c" in argv and "commit.gpgsign=false" in argv, argv
    assert "tag.gpgsign=false" in argv, argv
    # ordering check: first -c must come before the -C target flag
    first_dash_c = argv.index("-c")
    dash_big_c = argv.index("-C")
    assert first_dash_c < dash_big_c, f"-c must precede -C in {argv}"


def test_new_preserves_source_mode_literally(tmp_path, monkeypatch):
    """The destination's mode must match the source's mode bits, not be coerced
    to 0o755 for any file with the owner-exec bit set."""
    from agentic import scaffold as scaffold_pkg

    fake_root = tmp_path / "bundle"
    fake_root.mkdir()
    (fake_root / "agentic").mkdir()
    (fake_root / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")

    # A file with an unusual mode — owner-only exec, group/world read.
    weird = fake_root / "scripts"
    weird.mkdir()
    weird_sh = weird / "weird.sh"
    weird_sh.write_text("#!/usr/bin/env bash\n")
    weird_sh.chmod(0o744)

    monkeypatch.setattr(scaffold_pkg, "_resource_root", lambda: fake_root)
    monkeypatch.chdir(tmp_path)

    result = runner.invoke(app, ["new", "proj", "--no-git"])
    assert result.exit_code == 0

    actual_mode = _stat.S_IMODE((tmp_path / "proj" / "scripts" / "weird.sh").stat().st_mode)
    assert actual_mode == 0o744, f"expected 0o744, got {oct(actual_mode)}"
