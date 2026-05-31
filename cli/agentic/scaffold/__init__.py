"""Accessor over the bundled scaffold tree at ``agentic/scaffold/_scaffold/``.

Provides three primitives that the ``agentic new`` command uses:

- :func:`iter_resource_paths` — relative paths of every file in the bundle
- :func:`read_resource_bytes` — raw bytes of one file
- :func:`resource_mode` — POSIX mode of one file (so executable bits are
  preserved when copying into the target directory)

Tests monkeypatch ``_resource_root`` to swap in a fake bundle so they don't
need a built wheel.
"""
from __future__ import annotations

from pathlib import Path

from agentic.scaffold import _scaffold  # type: ignore[attr-defined] # populated at build time


class ScaffoldBundleMissing(RuntimeError):
    """Raised when the bundled scaffold tree is empty or absent."""


def _resource_root() -> Path:
    """Return the on-disk root of the bundled scaffold.

    The bundle ships as a regular package directory (not a zipfile), so
    ``Path(_scaffold.__file__).parent`` is a stable, sandboxed location.
    """
    root = Path(_scaffold.__file__).parent
    if not root.is_dir():  # pragma: no cover - defensive
        raise ScaffoldBundleMissing(f"scaffold bundle root is not a directory: {root}")
    return root


def iter_resource_paths() -> list[str]:
    """Walk the bundle and return every file path relative to the bundle root.

    Paths are POSIX-style with forward slashes so they're stable across platforms.
    """
    root = _resource_root()
    files: list[str] = []
    for path in root.rglob("*"):
        if path.is_file():
            files.append(path.relative_to(root).as_posix())
    if not files:
        raise ScaffoldBundleMissing(
            f"scaffold bundle at {root} is empty — reinstall the CLI"
        )
    return files


def read_resource_bytes(relpath: str) -> bytes:
    return (_resource_root() / relpath).read_bytes()


def resource_mode(relpath: str) -> int:
    return (_resource_root() / relpath).stat().st_mode
