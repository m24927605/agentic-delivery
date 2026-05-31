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


def test_version_in_range_lower_bound_inclusive():
    from build_scaffold import _version_in_range

    assert _version_in_range("v0.6", [">=0.6,<0.8"]) is True
    assert _version_in_range("v0.6.0", [">=0.6,<0.8"]) is True


def test_version_in_range_upper_bound_exclusive():
    from build_scaffold import _version_in_range

    assert _version_in_range("v0.8", [">=0.6,<0.8"]) is False
    assert _version_in_range("v0.7.99", [">=0.6,<0.8"]) is True


def test_version_in_range_multiple_ranges_or_semantics():
    from build_scaffold import _version_in_range

    assert _version_in_range("v1.2", [">=0.6,<0.8", ">=1.0,<2.0"]) is True
    assert _version_in_range("v0.9", [">=0.6,<0.8", ">=1.0,<2.0"]) is False


def test_version_in_range_rejects_unsupported_range_syntax():
    from build_scaffold import _version_in_range

    with pytest.raises(ValueError, match="unsupported compat range"):
        _version_in_range("v0.6", ["==0.6"])


def test_read_compat_versions_against_real_init():
    """Lock in that _read_compat_versions can parse the actual cli/agentic/__init__.py
    no matter how the COMPATIBLE_PIPELINE_VERSIONS assignment is formatted."""
    from build_scaffold import HatchScaffoldBuildHook

    repo_root = Path(__file__).resolve().parents[2]
    assert HatchScaffoldBuildHook._read_compat_versions(repo_root) == [">=0.6,<0.8"]


def test_hatch_glue_initialize_populates_and_registers_artifact(tmp_path):
    """HatchScaffoldBuildHook.initialize must:
    1. derive repo_root from self.root (cli/ -> repo root),
    2. read compat versions via _read_compat_versions,
    3. populate the scaffold bundle into self.root/agentic/scaffold/_scaffold,
    4. register agentic/scaffold/_scaffold/** in build_data["artifacts"].
    """
    from build_scaffold import HatchScaffoldBuildHook

    repo = _make_repo(tmp_path)
    cli_dir = repo / "cli"
    # _make_repo creates cli/scaffold_manifest.yaml etc.; also need cli/agentic/__init__.py
    (cli_dir / "agentic").mkdir(parents=True, exist_ok=True)
    (cli_dir / "agentic" / "__init__.py").write_text(
        'COMPATIBLE_PIPELINE_VERSIONS: list[str] = [">=0.6,<0.8"]\n', encoding="utf-8"
    )

    class _FakeHook:
        # _read_compat_versions is invoked as self._read_compat_versions(...) in
        # production, so the stub forwards it to the real staticmethod.
        _read_compat_versions = staticmethod(HatchScaffoldBuildHook._read_compat_versions)
        root = str(cli_dir)

    build_data: dict = {}
    HatchScaffoldBuildHook.initialize(  # type: ignore[arg-type]
        _FakeHook(), version="standard", build_data=build_data
    )

    bundle = cli_dir / "agentic" / "scaffold" / "_scaffold"
    assert (bundle / "agentic" / "pipeline.yaml").exists()
    assert "agentic/scaffold/_scaffold/**" in build_data["artifacts"]


def test_build_scaffold_loads_under_hatchling_style_import(tmp_path):
    """Hatchling loads custom build hooks via importlib.util.spec_from_file_location +
    exec_module, WITHOUT registering the module in sys.modules. CPython 3.12's
    @dataclass crashes under this loader. This regression test re-exercises the
    Hatchling path so a future @dataclass / @attrs / similar regression fails fast.
    """
    import importlib.util
    from pathlib import Path

    src = Path(__file__).resolve().parents[1] / "build_scaffold.py"
    spec = importlib.util.spec_from_file_location("hatch_build_under_test", src)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    # Deliberately NOT inserting into sys.modules — this mirrors Hatchling.
    spec.loader.exec_module(module)

    assert hasattr(module, "ScaffoldBuildHook")
    assert hasattr(module, "HatchScaffoldBuildHook")
    inst = module.ScaffoldBuildHook(repo_root=tmp_path, compat_versions=[">=0.6,<0.8"])
    assert inst.repo_root == tmp_path
    assert inst.compat_versions == [">=0.6,<0.8"]


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


def test_scaffold_iter_resources_lists_bundled_files(tmp_path, monkeypatch):
    # Materialize a fake _scaffold under the package and check iter_resources
    # walks every relative path under it.
    from agentic import scaffold as scaffold_pkg

    fake_root = tmp_path / "pkg" / "_scaffold"
    (fake_root / "agentic").mkdir(parents=True)
    (fake_root / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    (fake_root / "scripts").mkdir()
    (fake_root / "scripts" / "demo.sh").write_text("#!/usr/bin/env bash\n")
    (fake_root / "scripts" / "demo.sh").chmod(0o755)

    monkeypatch.setattr(scaffold_pkg, "_resource_root", lambda: fake_root)

    rels = sorted(scaffold_pkg.iter_resource_paths())
    assert "agentic/pipeline.yaml" in rels
    assert "scripts/demo.sh" in rels


def test_scaffold_read_bytes_returns_file_bytes(tmp_path, monkeypatch):
    from agentic import scaffold as scaffold_pkg

    fake_root = tmp_path / "pkg" / "_scaffold"
    fake_root.mkdir(parents=True)
    (fake_root / "marker.txt").write_bytes(b"hello\n")

    monkeypatch.setattr(scaffold_pkg, "_resource_root", lambda: fake_root)

    assert scaffold_pkg.read_resource_bytes("marker.txt") == b"hello\n"


def test_scaffold_resource_mode(tmp_path, monkeypatch):
    from agentic import scaffold as scaffold_pkg

    fake_root = tmp_path / "pkg" / "_scaffold"
    fake_root.mkdir(parents=True)
    sh = fake_root / "scripts" / "demo.sh"
    sh.parent.mkdir()
    sh.write_text("#!/usr/bin/env bash\n")
    sh.chmod(0o755)

    monkeypatch.setattr(scaffold_pkg, "_resource_root", lambda: fake_root)

    import stat as _stat
    assert scaffold_pkg.resource_mode("scripts/demo.sh") & _stat.S_IXUSR


def test_scaffold_iter_resources_raises_when_bundle_empty(tmp_path, monkeypatch):
    """An empty bundle dir (no real resources, no placeholder) must raise
    ScaffoldBundleMissing — this is the contract Task 8 relies on to tell
    a user 'reinstall the CLI'."""
    from agentic import scaffold as scaffold_pkg
    fake_root = tmp_path / "empty"
    fake_root.mkdir()
    monkeypatch.setattr(scaffold_pkg, "_resource_root", lambda: fake_root)
    with pytest.raises(scaffold_pkg.ScaffoldBundleMissing, match="empty"):
        scaffold_pkg.iter_resource_paths()


def test_scaffold_iter_resources_treats_placeholder_only_as_empty(tmp_path, monkeypatch):
    """A bundle containing ONLY the placeholder __init__.py (i.e., a fresh
    source checkout where the build hook never ran) must also raise
    ScaffoldBundleMissing — the placeholder is an implementation detail of
    the packaging strategy, not a real resource."""
    from agentic import scaffold as scaffold_pkg
    fake_root = tmp_path / "placeholder_only"
    fake_root.mkdir()
    (fake_root / "__init__.py").write_text('"""placeholder."""')
    monkeypatch.setattr(scaffold_pkg, "_resource_root", lambda: fake_root)
    with pytest.raises(scaffold_pkg.ScaffoldBundleMissing, match="empty"):
        scaffold_pkg.iter_resource_paths()


def test_scaffold_iter_resources_skips_pycache(tmp_path, monkeypatch):
    """`__pycache__/` is universally not-a-resource. The accessor must filter
    it out at every depth."""
    from agentic import scaffold as scaffold_pkg
    fake_root = tmp_path / "with_cache"
    (fake_root / "agentic").mkdir(parents=True)
    (fake_root / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    (fake_root / "agentic" / "__pycache__").mkdir()
    (fake_root / "agentic" / "__pycache__" / "stale.cpython-312.pyc").write_bytes(b"\x00")
    monkeypatch.setattr(scaffold_pkg, "_resource_root", lambda: fake_root)

    rels = scaffold_pkg.iter_resource_paths()
    assert "agentic/pipeline.yaml" in rels
    assert not any("__pycache__" in r for r in rels)


def test_scaffold_works_under_namespace_package_layout(tmp_path, monkeypatch):
    """The shipped wheel layout has _scaffold/ WITHOUT an __init__.py (the
    build hook wipes the placeholder). _resource_root must still work in
    that namespace-package case — uses __path__, not __file__."""
    from agentic import scaffold as scaffold_pkg

    # Build a fake namespace-package-style root (no __init__.py at the root).
    fake_root = tmp_path / "ns_root"
    (fake_root / "agentic").mkdir(parents=True)
    (fake_root / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")

    # Mock the _scaffold module's __path__ to point at the fake root and
    # explicitly set __file__ to None to simulate a namespace package.
    fake_module = type(scaffold_pkg._scaffold)(scaffold_pkg._scaffold.__name__)
    fake_module.__path__ = [str(fake_root)]  # namespace packages keep __path__
    fake_module.__file__ = None  # regular packages have __file__; namespace packages don't

    monkeypatch.setattr(scaffold_pkg, "_scaffold", fake_module)

    root = scaffold_pkg._resource_root()
    assert root == fake_root
    assert "agentic/pipeline.yaml" in scaffold_pkg.iter_resource_paths()
