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


_SKIP_RELPATHS: frozenset[str] = frozenset({"__init__.py"})
_SKIP_DIR_NAMES: frozenset[str] = frozenset({"__pycache__"})


def iter_resource_paths() -> list[str]:
    """Walk the bundle and return every file path relative to the bundle root.

    Paths are POSIX-style with forward slashes so they're stable across platforms.
    Filters out the bundle placeholder (`__init__.py` at root) and any
    `__pycache__/...` entries so callers receive only real scaffold resources.
    """
    root = _resource_root()
    files: list[str] = []
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        rel_parts = path.relative_to(root).parts
        rel = path.relative_to(root).as_posix()
        if rel in _SKIP_RELPATHS:
            continue
        if any(part in _SKIP_DIR_NAMES for part in rel_parts):
            continue
        files.append(rel)
    if not files:
        raise ScaffoldBundleMissing(
            f"scaffold bundle at {root} is empty — reinstall the CLI"
        )
    return files


def read_resource_bytes(relpath: str) -> bytes:
    """Return the raw bytes of ``relpath`` within the bundle."""
    return (_resource_root() / relpath).read_bytes()


def resource_mode(relpath: str) -> int:
    """Return the POSIX mode bits of ``relpath`` within the bundle.

    Returns only the permission portion (``stat.S_IMODE``) so future callers
    that compare against literal mode constants (e.g., ``0o644``) aren't
    surprised by file-type bits.
    """
    import stat as _stat
    return _stat.S_IMODE((_resource_root() / relpath).stat().st_mode)
