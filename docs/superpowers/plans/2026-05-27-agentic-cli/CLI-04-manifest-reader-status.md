# CLI-04: `manifest.py` Reader + `agentic status` Implementation Plan

> **For agentic-delivery pipeline:** Implementer = agency-agents Staff+. Reviewer = Claude Code CLI via AIT. Write scope `cli/**`. Read-only against `agentic/runs/<id>/`.

**Goal:** Provide a read-only `Manifest` dataclass over `agentic/runs/<run-id>/manifest.yaml` (planning) and `implementation-manifest.yaml` (implementation), and implement `agentic status` in both text and `--json` forms.

**Architecture:** `cli/agentic/manifest.py` exposes `load_manifest(repo, run_id) -> Manifest`. `Manifest` is an immutable dataclass with normalised view: `id`, `mode`, `profile`, `state`, `updated_at`, `artifacts: list[Artifact]`, `tasks: list[Task]`. `cli/agentic/commands/status.py` formats it. `--json` envelope `{"_schema": "agentic.cli/v1", ...}`.

**Tech Stack:** pyyaml, dataclasses, Rich table, json (stdlib).

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `cli/agentic/manifest.py` | Create | Read-only manifest loader + Manifest/Artifact/Task dataclasses. |
| `cli/agentic/commands/status.py` | Create | `agentic status` command. |
| `cli/agentic/app.py` | Modify | Register `status`. |
| `cli/tests/test_manifest.py` | Create | Loader unit tests. |
| `cli/tests/test_status_command.py` | Create | CLI tests. |
| `cli/tests/fixtures/manifests/planning_fresh.yaml` | Create | Sample manifest. |
| `cli/tests/fixtures/manifests/impl_mid_dispatch.yaml` | Create | Sample manifest. |
| `cli/tests/snapshots/` | Create dir | Snapshot output for `--json` and text. |

---

## Task 1: TDD — manifest dataclasses + loader

**Files:**
- Create: `cli/agentic/manifest.py`
- Create: `cli/tests/test_manifest.py`
- Create: `cli/tests/fixtures/manifests/planning_fresh.yaml`
- Create: `cli/tests/fixtures/manifests/impl_mid_dispatch.yaml`

- [ ] **Step 1: Write planning fixture `cli/tests/fixtures/manifests/planning_fresh.yaml`**

```yaml
run:
  id: demo-planning
  mode: planning
  profile: default-delivery
  state: artifact_plan_created
  updated_at: "2026-05-27T10:00:00Z"
artifacts:
  - path: docs/architecture/x.md
    status: planned
    updated_at: "2026-05-27T09:00:00Z"
  - path: docs/architecture/y.md
    status: drafted
    updated_at: "2026-05-27T09:30:00Z"
  - path: docs/architecture/z.md
    status: approved
    updated_at: "2026-05-27T09:45:00Z"
```

- [ ] **Step 2: Write impl fixture `cli/tests/fixtures/manifests/impl_mid_dispatch.yaml`**

```yaml
run:
  id: demo-impl
  mode: implementation
  profile: default-delivery
  state: implementation_planned
  updated_at: "2026-05-27T11:00:00Z"
approved_inputs:
  - docs/architecture/z.md
tasks:
  - id: T1
    status: dispatched
    updated_at: "2026-05-27T10:30:00Z"
  - id: T2
    status: pending
    updated_at: "2026-05-27T10:30:00Z"
```

- [ ] **Step 3: Write failing tests `cli/tests/test_manifest.py`**

```python
from pathlib import Path

import pytest

from agentic.manifest import Artifact, Manifest, Task, load_manifest


FIXTURES = Path(__file__).parent / "fixtures" / "manifests"


def _seed_repo(tmp_path: Path, run_id: str, fixture_name: str, *, impl: bool = False) -> Path:
    src = FIXTURES / fixture_name
    target_dir = tmp_path / "agentic" / "runs" / run_id
    target_dir.mkdir(parents=True)
    target_name = "implementation-manifest.yaml" if impl else "manifest.yaml"
    (target_dir / target_name).write_text(src.read_text())
    (tmp_path / "agentic").mkdir(exist_ok=True)
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    return tmp_path


def test_load_planning_manifest(tmp_path):
    repo = _seed_repo(tmp_path, "demo-planning", "planning_fresh.yaml")
    m = load_manifest(repo=repo, run_id="demo-planning")
    assert m.id == "demo-planning"
    assert m.mode == "planning"
    assert m.profile == "default-delivery"
    assert m.state == "artifact_plan_created"
    assert len(m.artifacts) == 3
    assert m.artifacts[0] == Artifact(
        path="docs/architecture/x.md", status="planned", updated_at="2026-05-27T09:00:00Z"
    )


def test_load_implementation_manifest(tmp_path):
    repo = _seed_repo(tmp_path, "demo-impl", "impl_mid_dispatch.yaml", impl=True)
    m = load_manifest(repo=repo, run_id="demo-impl")
    assert m.mode == "implementation"
    assert len(m.artifacts) == 1  # synthesised from approved_inputs
    assert m.artifacts[0].status == "approved"
    assert len(m.tasks) == 2
    assert m.tasks[0] == Task(id="T1", status="dispatched", updated_at="2026-05-27T10:30:00Z")


def test_load_unknown_run_raises(tmp_path):
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    with pytest.raises(FileNotFoundError):
        load_manifest(repo=tmp_path, run_id="ghost")


def test_artifact_status_counts(tmp_path):
    repo = _seed_repo(tmp_path, "demo-planning", "planning_fresh.yaml")
    m = load_manifest(repo=repo, run_id="demo-planning")
    assert m.count_artifacts(status="planned") == 1
    assert m.count_artifacts(status="drafted") == 1
    assert m.count_artifacts(status="approved") == 1
    assert m.first_artifact(status="drafted").path == "docs/architecture/y.md"
```

- [ ] **Step 4: Run — expect FAIL**

```bash
cd cli && pytest tests/test_manifest.py -q
```

- [ ] **Step 5: Implement `cli/agentic/manifest.py`**

```python
"""Read-only access to agentic-delivery run manifests."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal

import yaml

Mode = Literal["planning", "implementation"]
ArtifactStatus = Literal[
    "planned", "drafted", "reviewed", "changes_requested",
    "approved", "rejected", "deferred",
]
TaskStatus = Literal["pending", "dispatched", "executed", "reviewed", "approved"]


@dataclass(frozen=True)
class Artifact:
    path: str
    status: str
    updated_at: str | None = None


@dataclass(frozen=True)
class Task:
    id: str
    status: str
    updated_at: str | None = None


@dataclass(frozen=True)
class Manifest:
    id: str
    mode: Mode
    profile: str
    state: str
    updated_at: str | None
    artifacts: tuple[Artifact, ...] = field(default_factory=tuple)
    tasks: tuple[Task, ...] = field(default_factory=tuple)

    def count_artifacts(self, *, status: str) -> int:
        return sum(1 for a in self.artifacts if a.status == status)

    def first_artifact(self, *, status: str) -> Artifact | None:
        for a in self.artifacts:
            if a.status == status:
                return a
        return None

    def count_tasks(self, *, status: str) -> int:
        return sum(1 for t in self.tasks if t.status == status)

    def first_task(self, *, status: str) -> Task | None:
        for t in self.tasks:
            if t.status == status:
                return t
        return None


def _find_manifest_file(repo: Path, run_id: str) -> Path:
    base = repo / "agentic" / "runs" / run_id
    for name in ("implementation-manifest.yaml", "manifest.yaml"):
        candidate = base / name
        if candidate.is_file():
            return candidate
    raise FileNotFoundError(f"no manifest for run {run_id!r} under {base}")


def load_manifest(*, repo: Path, run_id: str) -> Manifest:
    path = _find_manifest_file(repo, run_id)
    data = yaml.safe_load(path.read_text())
    run = data.get("run", {})
    mode: Mode = run.get("mode", "planning")
    artifacts_raw = data.get("artifacts", [])
    if mode == "implementation" and not artifacts_raw:
        artifacts_raw = [
            {"path": p, "status": "approved"} for p in data.get("approved_inputs", [])
        ]
    artifacts = tuple(
        Artifact(path=a["path"], status=a["status"], updated_at=a.get("updated_at"))
        for a in artifacts_raw
    )
    tasks = tuple(
        Task(id=t["id"], status=t["status"], updated_at=t.get("updated_at"))
        for t in data.get("tasks", [])
    )
    return Manifest(
        id=run.get("id", run_id),
        mode=mode,
        profile=run.get("profile", "unknown"),
        state=run.get("state", "unknown"),
        updated_at=run.get("updated_at"),
        artifacts=artifacts,
        tasks=tasks,
    )
```

- [ ] **Step 6: Run — expect PASS**

```bash
cd cli && pytest tests/test_manifest.py -q
```

Expected: 4 passed.

- [ ] **Step 7: Commit**

```bash
git add cli/agentic/manifest.py cli/tests/test_manifest.py cli/tests/fixtures/
git commit -m "feat(cli): read-only Manifest loader"
```

---

## Task 2: TDD — `agentic status` (text)

**Files:**
- Create: `cli/agentic/commands/status.py`
- Modify: `cli/agentic/app.py`
- Create: `cli/tests/test_status_command.py`

- [ ] **Step 1: Write failing tests `cli/tests/test_status_command.py`**

```python
from pathlib import Path

from agentic.app import app


def _seed(tmp_path: Path, fixture: str, run_id: str, impl: bool = False) -> Path:
    src = Path(__file__).parent / "fixtures" / "manifests" / fixture
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    d = tmp_path / "agentic" / "runs" / run_id
    d.mkdir(parents=True)
    name = "implementation-manifest.yaml" if impl else "manifest.yaml"
    (d / name).write_text(src.read_text())
    return tmp_path


def test_status_text_for_planning(cli, tmp_path, monkeypatch):
    repo = _seed(tmp_path, "planning_fresh.yaml", "demo-planning")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["status", "--run-id", "demo-planning"])
    assert result.exit_code == 0
    assert "demo-planning" in result.stdout
    assert "planning" in result.stdout
    assert "artifact_plan_created" in result.stdout
    assert "approved" in result.stdout  # status table mentions
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd cli && pytest tests/test_status_command.py -q
```

- [ ] **Step 3: Implement `cli/agentic/commands/status.py`**

```python
"""`agentic status` — read manifest, render summary."""

from __future__ import annotations

from typing import Annotated

import typer
from rich.console import Console
from rich.table import Table

from agentic.context import RepoNotFound, RunNotFound, resolve_repo, resolve_run_id
from agentic.manifest import load_manifest

app = typer.Typer()
_console = Console()


@app.callback(invoke_without_command=True)
def status(
    ctx: typer.Context,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    """Show current run state, artifacts, and tasks."""
    try:
        flag = run_id or (ctx.obj.get("run_id_flag") if ctx.obj else None)
        repo = resolve_repo(repo_flag=ctx.obj.get("repo_flag") if ctx.obj else None).path
        run = resolve_run_id(repo=repo, flag=flag)
    except (RepoNotFound, RunNotFound) as e:
        typer.echo(f"x  {e}", err=True)
        raise typer.Exit(code=6)
    manifest = load_manifest(repo=repo, run_id=run.id)

    typer.echo(f"Run:     {manifest.id}  ({manifest.mode} - {manifest.profile})")
    typer.echo(f"State:   {manifest.state}")
    typer.echo(f"Updated: {manifest.updated_at or '-'}")
    typer.echo(f"Source:  {run.source}")
    typer.echo("")

    if manifest.artifacts:
        table = Table(title="Artifacts", show_header=True)
        table.add_column("status")
        table.add_column("path")
        for a in manifest.artifacts:
            table.add_row(a.status, a.path)
        _console.print(table)

    if manifest.tasks:
        table = Table(title="Tasks", show_header=True)
        table.add_column("status")
        table.add_column("id")
        for t in manifest.tasks:
            table.add_row(t.status, t.id)
        _console.print(table)
```

- [ ] **Step 4: Register in `cli/agentic/app.py`**

```python
from agentic.commands import status as status_cmd

# after add_typer for run:
app.add_typer(status_cmd.app, name="status")
```

- [ ] **Step 5: Run — expect PASS**

```bash
cd cli && pytest tests/test_status_command.py -q
```

- [ ] **Step 6: Commit**

```bash
git add cli/agentic/commands/status.py cli/agentic/app.py cli/tests/test_status_command.py
git commit -m "feat(cli): agentic status (text)"
```

---

## Task 3: TDD — `agentic --json status`

**Files:**
- Modify: `cli/agentic/commands/status.py`
- Modify: `cli/agentic/app.py` (add `--json` global)
- Modify: `cli/tests/test_status_command.py`

- [ ] **Step 1: Add `--json` to root callback in `cli/agentic/app.py`**

```python
@app.callback()
def _root(
    ctx: typer.Context,
    repo: Annotated[Path | None, typer.Option("--repo")] = None,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
    json_mode: Annotated[bool, typer.Option("--json", help="Structured output.")] = False,
    no_compat_check: Annotated[bool, typer.Option("--no-compat-check")] = False,
) -> None:
    ctx.obj = {
        "repo_flag": repo,
        "run_id_flag": run_id,
        "json": json_mode,
        "compat_check": not no_compat_check,
    }
```

- [ ] **Step 2: Extend `cli/agentic/commands/status.py`**

```python
import json as _json

# inside status() after manifest = load_manifest(...)
if ctx.obj and ctx.obj.get("json"):
    payload = {
        "_schema": "agentic.cli/v1",
        "run": {
            "id": manifest.id,
            "mode": manifest.mode,
            "profile": manifest.profile,
            "state": manifest.state,
            "updated_at": manifest.updated_at,
            "source": run.source,
        },
        "artifacts": {
            "total": len(manifest.artifacts),
            "approved": manifest.count_artifacts(status="approved"),
            "pending": sum(
                1 for a in manifest.artifacts
                if a.status not in ("approved", "rejected", "deferred")
            ),
            "rejected": manifest.count_artifacts(status="rejected"),
            "deferred": manifest.count_artifacts(status="deferred"),
        },
        "tasks": [{"id": t.id, "status": t.status} for t in manifest.tasks],
    }
    typer.echo(_json.dumps(payload, indent=2, sort_keys=False))
    return
```

(Keep the existing text branch under an `else`.)

- [ ] **Step 3: Append test in `cli/tests/test_status_command.py`**

```python
import json


def test_status_json_envelope(cli, tmp_path, monkeypatch):
    repo = _seed(tmp_path, "planning_fresh.yaml", "demo-planning")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["--json", "status", "--run-id", "demo-planning"])
    assert result.exit_code == 0
    payload = json.loads(result.stdout)
    assert payload["_schema"] == "agentic.cli/v1"
    assert payload["run"]["id"] == "demo-planning"
    assert payload["artifacts"]["total"] == 3
    assert payload["artifacts"]["approved"] == 1
```

- [ ] **Step 4: Run — expect PASS**

```bash
cd cli && pytest tests/test_status_command.py -q
```

- [ ] **Step 5: Lint + type**

```bash
cd cli && ruff check agentic tests && mypy --strict agentic
```

- [ ] **Step 6: Commit**

```bash
git add cli/agentic/app.py cli/agentic/commands/status.py cli/tests/test_status_command.py
git commit -m "feat(cli): agentic status --json with _schema envelope"
```

---

## Acceptance Criteria (from spec §13 CLI-04)

- `load_manifest()` returns immutable `Manifest` with normalised artifacts/tasks.
- `agentic status` text output covers run id, mode/profile, state, artifact + task tables.
- `agentic --json status` emits `_schema: agentic.cli/v1` envelope with run + artifacts counters + tasks list.

## Implementer / Reviewer

- **Implementer:** agency-agents Staff+ — `staff-software-engineer`.
- **Reviewer:** Claude Code CLI via AIT — `engineering-software-architect`, `engineering-code-reviewer`, `engineering-technical-writer` (output legibility).

Evidence under `agentic/reviews/agentic-cli/CLI-04/`.

## Rollback

```bash
git revert <CLI-04 commits>
```
