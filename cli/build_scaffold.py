"""Hatch custom build hook that materializes the agentic-delivery scaffold
into ``cli/agentic/scaffold/_scaffold/`` before the wheel is packaged.

The hook reads ``cli/scaffold_manifest.yaml`` for the allowlist of paths to
copy from the repo root, overlays the templates in ``cli/scaffold_templates/``
on top, and refuses to build if the bundled pipeline version drifts out of
the CLI's compatibility range.

Tested via ``cli/tests/test_build_scaffold.py``.
"""
from __future__ import annotations

import ast
import re
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

import yaml

try:
    # Hatch is only present at build time; tests use the class directly.
    from hatchling.builders.hooks.plugin.interface import BuildHookInterface
except ImportError:  # pragma: no cover - test-only path
    BuildHookInterface = object  # type: ignore[misc,assignment]


class ManifestDriftError(RuntimeError):
    """Raised when an allowlisted path does not exist at repo root."""


class PipelineVersionMismatch(RuntimeError):
    """Raised when bundled pipeline.yaml.version is outside CLI compat range."""


_VERSION_RANGE_RE = re.compile(r"^>=\s*([0-9.]+)\s*,\s*<\s*([0-9.]+)\s*$")


def _parse_version(raw: str) -> tuple[int, ...]:
    # Accept "v0.6", "0.6", "0.6.0"
    s = raw.strip()
    if s.startswith("v"):
        s = s[1:]
    return tuple(int(part) for part in s.split("."))


def _version_in_range(version: str, ranges: Sequence[str]) -> bool:
    v = _parse_version(version)
    for r in ranges:
        m = _VERSION_RANGE_RE.match(r)
        if not m:
            raise ValueError(f"unsupported compat range: {r!r}")
        lo, hi = _parse_version(m.group(1)), _parse_version(m.group(2))
        if lo <= v < hi:
            return True
    return False


@dataclass
class ScaffoldBuildHook:
    """Populate the scaffold bundle from repo state."""

    repo_root: Path
    compat_versions: Sequence[str]

    @property
    def manifest_path(self) -> Path:
        return self.repo_root / "cli" / "scaffold_manifest.yaml"

    @property
    def templates_dir(self) -> Path:
        return self.repo_root / "cli" / "scaffold_templates"

    def populate(self, target: Path) -> Path:
        manifest = yaml.safe_load(self.manifest_path.read_text(encoding="utf-8"))
        includes = list(manifest.get("include", []))
        overlays = list(manifest.get("overlay", []))

        self._validate_includes(includes)
        self._validate_pipeline_version()

        if target.exists():
            shutil.rmtree(target)
        target.mkdir(parents=True)

        for rel in includes:
            self._copy_include(rel, target)

        for rel in overlays:
            self._copy_overlay(rel, target)

        return target

    def _validate_includes(self, includes: Sequence[str]) -> None:
        missing = [rel for rel in includes if not (self.repo_root / rel).exists()]
        if missing:
            raise ManifestDriftError(
                "scaffold manifest references paths that do not exist: " + ", ".join(missing)
            )

    def _validate_pipeline_version(self) -> None:
        pipeline = self.repo_root / "agentic" / "pipeline.yaml"
        data = yaml.safe_load(pipeline.read_text(encoding="utf-8"))
        version = (data or {}).get("pipeline", {}).get("version")
        if version is None:
            raise PipelineVersionMismatch("agentic/pipeline.yaml has no pipeline.version")
        if not _version_in_range(version, self.compat_versions):
            raise PipelineVersionMismatch(
                f"agentic/pipeline.yaml version {version!r} not in CLI compat "
                f"{list(self.compat_versions)!r}"
            )

    def _copy_include(self, rel: str, target: Path) -> None:
        src = self.repo_root / rel
        dest = target / rel
        if src.is_dir():
            shutil.copytree(src, dest, symlinks=False, dirs_exist_ok=True)
        else:
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dest)

    def _copy_overlay(self, rel: str, target: Path) -> None:
        src = self.templates_dir / rel
        if not src.exists():
            raise ManifestDriftError(f"overlay template missing: {src}")
        dest = target / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest)


# --- Hatch plugin glue --------------------------------------------------------


class HatchScaffoldBuildHook(BuildHookInterface):  # type: ignore[misc]
    """Hatch entry point. Reads compat versions from the CLI package."""

    PLUGIN_NAME = "scaffold"

    def initialize(self, version: str, build_data: dict) -> None:  # noqa: ARG002 - hatch contract
        repo_root = Path(self.root).parent  # cli/ -> repo root
        compat = self._read_compat_versions(repo_root)
        target = Path(self.root) / "agentic" / "scaffold" / "_scaffold"
        ScaffoldBuildHook(repo_root=repo_root, compat_versions=compat).populate(target)
        build_data.setdefault("artifacts", []).append("agentic/scaffold/_scaffold/**")

    @staticmethod
    def _read_compat_versions(repo_root: Path) -> list[str]:
        # Avoid importing the CLI package during build; parse __init__.py directly.
        init_py = repo_root / "cli" / "agentic" / "__init__.py"
        text = init_py.read_text(encoding="utf-8")
        match = re.search(
            r"COMPATIBLE_PIPELINE_VERSIONS\s*:\s*list\[str\]\s*=\s*(\[[^\]]+\])",
            text,
        )
        if match is None:
            raise RuntimeError(
                "could not find COMPATIBLE_PIPELINE_VERSIONS in cli/agentic/__init__.py"
            )
        # ast.literal_eval safely parses the matched list-of-strings literal.
        return list(ast.literal_eval(match.group(1)))
