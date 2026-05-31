"""Tests for cli/build_scaffold.py — the Hatch custom build hook."""
from __future__ import annotations

import copy
import stat
import textwrap
from pathlib import Path

import pytest
import yaml

from build_scaffold import ManifestDriftError, PipelineVersionMismatch, ScaffoldBuildHook


def _make_repo(tmp_path: Path) -> Path:
    """Build a minimal fake repo with the structure the hook needs."""
    repo = tmp_path / "repo"
    (repo / "agentic").mkdir(parents=True)
    (repo / "agentic" / "pipeline.yaml").write_text(
        "pipeline:\n  version: v0.6\n", encoding="utf-8"
    )
    (repo / "agentic" / "runs").mkdir()
    (repo / "agentic" / "runs" / ".gitkeep").write_text("", encoding="utf-8")
    (repo / "scripts").mkdir()
    sh = repo / "scripts" / "demo.sh"
    sh.write_text("#!/usr/bin/env bash\necho hi\n", encoding="utf-8")
    sh.chmod(0o755)
    (repo / "docs" / "adr").mkdir(parents=True)
    (repo / "docs" / "adr" / "003-agentic-delivery-boundary.md").write_text(
        "# ADR-003\n", encoding="utf-8"
    )

    (repo / "cli").mkdir()
    (repo / "cli" / "scaffold_templates").mkdir()
    (repo / "cli" / "scaffold_templates" / ".gitignore").write_text(
        ".ait/\n", encoding="utf-8"
    )
    (repo / "cli" / "scaffold_templates" / "README.md").write_text(
        "# {{PROJECT_NAME}}\nCLI v{{CLI_VERSION}}\n", encoding="utf-8"
    )

    (repo / "cli" / "scaffold_manifest.yaml").write_text(
        textwrap.dedent(
            """
            include:
              - agentic/pipeline.yaml
              - agentic/runs/.gitkeep
              - scripts/
              - docs/adr/003-agentic-delivery-boundary.md
            overlay:
              - .gitignore
              - README.md
            """
        ).lstrip(),
        encoding="utf-8",
    )
    return repo


def test_hook_copies_include_tree(tmp_path):
    repo = _make_repo(tmp_path)
    hook = ScaffoldBuildHook(repo_root=repo, compat_versions=[">=0.6,<0.8"])

    out = hook.populate(target=repo / "cli" / "agentic" / "scaffold" / "_scaffold")

    assert (out / "agentic" / "pipeline.yaml").read_text(encoding="utf-8").startswith("pipeline:")
    assert (out / "agentic" / "runs" / ".gitkeep").exists()
    assert (out / "scripts" / "demo.sh").exists()
    assert (out / "docs" / "adr" / "003-agentic-delivery-boundary.md").exists()


def test_hook_preserves_executable_bit(tmp_path):
    repo = _make_repo(tmp_path)
    hook = ScaffoldBuildHook(repo_root=repo, compat_versions=[">=0.6,<0.8"])

    out = hook.populate(target=repo / "out")

    mode = (out / "scripts" / "demo.sh").stat().st_mode
    assert mode & stat.S_IXUSR, f"expected executable bit on demo.sh, got {oct(mode)}"


def test_hook_applies_template_overlay(tmp_path):
    repo = _make_repo(tmp_path)
    hook = ScaffoldBuildHook(repo_root=repo, compat_versions=[">=0.6,<0.8"])

    out = hook.populate(target=repo / "out")

    # .gitignore came from cli/scaffold_templates/, not repo root (which has no .gitignore here)
    assert (out / ".gitignore").read_text(encoding="utf-8") == ".ait/\n"
    # README template ships with placeholders intact — substitution happens at `agentic new` time
    assert "{{PROJECT_NAME}}" in (out / "README.md").read_text(encoding="utf-8")


def test_hook_raises_when_include_missing(tmp_path):
    repo = _make_repo(tmp_path)
    (repo / "agentic" / "pipeline.yaml").unlink()
    hook = ScaffoldBuildHook(repo_root=repo, compat_versions=[">=0.6,<0.8"])

    with pytest.raises(ManifestDriftError) as exc:
        hook.populate(target=repo / "out")
    assert "agentic/pipeline.yaml" in str(exc.value)


def test_hook_rejects_pipeline_version_mismatch(tmp_path):
    repo = _make_repo(tmp_path)
    (repo / "agentic" / "pipeline.yaml").write_text(
        "pipeline:\n  version: v0.5\n", encoding="utf-8"
    )
    hook = ScaffoldBuildHook(repo_root=repo, compat_versions=[">=0.6,<0.8"])

    with pytest.raises(PipelineVersionMismatch):
        hook.populate(target=repo / "out")


def test_hook_clears_existing_target(tmp_path):
    repo = _make_repo(tmp_path)
    target = repo / "out"
    target.mkdir()
    (target / "stale.txt").write_text("old", encoding="utf-8")

    hook = ScaffoldBuildHook(repo_root=repo, compat_versions=[">=0.6,<0.8"])
    hook.populate(target=target)

    assert not (target / "stale.txt").exists()


def test_scaffold_overlay_profile_drift_against_reference():
    """The trimmed overlay profile must match the reference profile minus
    exactly the two backlog paths in required_artifacts.deliverables and
    review_prompt.required_files.

    If a new field is added to the reference profile and not mirrored in
    the overlay, this test fires.
    """
    # cli/tests/test_build_scaffold.py -> parents[2] is repo root
    repo_root = Path(__file__).resolve().parents[2]
    reference_path = repo_root / "agentic" / "profiles" / "default-delivery.yaml"
    overlay_path = (
        repo_root / "cli" / "scaffold_templates" / "agentic" / "profiles" / "default-delivery.yaml"
    )

    reference = yaml.safe_load(reference_path.read_text(encoding="utf-8"))
    overlay = yaml.safe_load(overlay_path.read_text(encoding="utf-8"))

    TRIMMED = {
        "docs/backlog/agentic-delivery-automation-slices.md",
        "docs/backlog/hermes-adapter-implementation-slices.md",
    }

    def strip(profile):
        p = copy.deepcopy(profile)
        deliverables = p.get("required_artifacts", {}).get("deliverables", [])
        if deliverables:
            p["required_artifacts"]["deliverables"] = [
                x for x in deliverables if x not in TRIMMED
            ]
        review_prompt = p.get("review_prompt") or {}
        required_files = review_prompt.get("required_files", [])
        if required_files:
            p["review_prompt"]["required_files"] = [
                x for x in required_files if x not in TRIMMED
            ]
        return p

    assert strip(reference) == overlay, (
        "Scaffold overlay default-delivery.yaml has drifted from the reference profile. "
        "Add the new field(s) to cli/scaffold_templates/agentic/profiles/default-delivery.yaml "
        "or update the TRIMMED set in this test if the policy changes."
    )
