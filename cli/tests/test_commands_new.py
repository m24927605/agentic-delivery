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
