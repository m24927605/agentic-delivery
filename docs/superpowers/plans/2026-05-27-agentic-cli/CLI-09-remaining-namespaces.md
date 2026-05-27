# CLI-09: Remaining Namespaces Implementation Plan

> **For agentic-delivery pipeline:** Implementer = agency-agents Staff+. Reviewer = Claude Code CLI via AIT. Write scope `cli/**`.

**Goal:** Cover the remaining script namespaces (`hermes`, `identity`, `evidence`, `fixtures`, `manifest`, `validate`) per spec §5.5.

**Architecture:** Six independent sub-apps, all built on `_shell_helpers`. The `manifest` Typer module is named `manifest_cmd.py` to avoid shadowing `agentic/manifest.py`.

**Tech Stack:** typer, shared helpers.

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `cli/agentic/commands/hermes.py` | Create | Hermes actions + dry-runs. |
| `cli/agentic/commands/identity.py` | Create | Identity policy validate + authorize. |
| `cli/agentic/commands/evidence.py` | Create | record + redact validation evidence. |
| `cli/agentic/commands/fixtures.py` | Create | Golden fixtures runner. |
| `cli/agentic/commands/manifest_cmd.py` | Create | Manifest schema validate / templates / scan. |
| `cli/agentic/commands/validate.py` | Create | `agentic validate system`. |
| `cli/agentic/app.py` | Modify | Register all six. |
| `cli/tests/test_commands_other.py` | Create | Routing tests for all six. |

---

## Task 1: TDD — all six namespaces in one batch

**Files:**
- Create: six modules above
- Modify: `cli/agentic/app.py`
- Create: `cli/tests/test_commands_other.py`

- [ ] **Step 1: Write failing tests `cli/tests/test_commands_other.py`**

```python
from pathlib import Path

import pytest

from agentic.app import app
from agentic.commands import evidence as evidence_cmd
from agentic.commands import fixtures as fixtures_cmd
from agentic.commands import hermes as hermes_cmd
from agentic.commands import identity as identity_cmd
from agentic.commands import manifest_cmd
from agentic.commands import validate as validate_cmd
from tests._recording import RecordingRunner


def _seed(tmp_path: Path, run_id: str = "demo") -> Path:
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    d = tmp_path / "agentic" / "runs" / run_id
    d.mkdir(parents=True)
    (d / "manifest.yaml").write_text("run:\n  id: " + run_id + "\n  mode: planning\n")
    return tmp_path


@pytest.fixture
def runner(monkeypatch):
    rr = RecordingRunner()
    for mod in (hermes_cmd, identity_cmd, evidence_cmd, fixtures_cmd, manifest_cmd, validate_cmd):
        monkeypatch.setattr(mod, "_runner_factory", lambda repo, rr=rr: rr)
    return rr


def test_hermes_actions_list(cli, tmp_path, monkeypatch, runner):
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["hermes", "actions", "list"])
    assert result.exit_code == 0
    assert runner.calls[-1].name == "validate-hermes-actions.sh"


def test_hermes_run_with_kv(cli, tmp_path, monkeypatch, runner):
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(
        app,
        ["hermes", "run", "update_artifact_status", "run_id=demo", "artifact_path=x.md"],
    )
    assert result.exit_code == 0
    call = runner.calls[-1]
    assert call.name == "run-hermes-action.sh"
    assert call.args[0] == "update_artifact_status"
    assert "run_id=demo" in call.args


def test_hermes_memory_sync_dry_run(cli, tmp_path, monkeypatch, runner):
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["hermes", "memory-sync", "--dry-run"])
    assert result.exit_code == 0
    assert runner.calls[-1].name == "hermes-memory-sync.sh"
    assert "--dry-run" in runner.calls[-1].args


def test_identity_validate(cli, tmp_path, monkeypatch, runner):
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["identity", "validate"])
    assert result.exit_code == 0
    assert runner.calls[-1].name == "validate-identity-policy.sh"


def test_identity_authorize(cli, tmp_path, monkeypatch, runner):
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["identity", "authorize", "--action", "artifact.approve"])
    assert result.exit_code == 0
    call = runner.calls[-1]
    assert call.name == "authorize-agentic-action.sh"
    assert "--action" in call.args
    assert "artifact.approve" in call.args


def test_evidence_record(cli, tmp_path, monkeypatch, runner):
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["evidence", "record", "--run-id", "demo"])
    assert result.exit_code == 0
    assert runner.calls[-1].name == "record-validation-evidence.sh"


def test_evidence_redact(cli, tmp_path, monkeypatch, runner):
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["evidence", "redact", "--run-id", "demo"])
    assert result.exit_code == 0
    assert runner.calls[-1].name == "redact-local-evidence.sh"


def test_fixtures_run(cli, tmp_path, monkeypatch, runner):
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["fixtures", "run"])
    assert result.exit_code == 0
    assert runner.calls[-1].name == "run-golden-fixtures.sh"


def test_manifest_validate_all(cli, tmp_path, monkeypatch, runner):
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["manifest", "validate", "--all"])
    assert result.exit_code == 0
    call = runner.calls[-1]
    assert call.name == "validate-manifest-schema.sh"
    assert "--all" in call.args


def test_manifest_templates(cli, tmp_path, monkeypatch, runner):
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["manifest", "templates", "--run-id", "demo"])
    assert result.exit_code == 0
    call = runner.calls[-1]
    assert call.name == "validate-artifact-templates.sh"
    assert "demo" in call.args


def test_manifest_scan(cli, tmp_path, monkeypatch, runner):
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["manifest", "scan"])
    assert result.exit_code == 0
    assert runner.calls[-1].name == "privacy-scan-tracked.sh"


def test_validate_system(cli, tmp_path, monkeypatch, runner):
    repo = _seed(tmp_path)
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["validate", "system"])
    assert result.exit_code == 0
    assert runner.calls[-1].name == "validate-agentic-system.sh"
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd cli && pytest tests/test_commands_other.py -q
```

- [ ] **Step 3: Implement `cli/agentic/commands/hermes.py`**

```python
"""`agentic hermes ...` subcommands."""

from __future__ import annotations

from typing import Annotated

import typer

from agentic.commands._shell_helpers import default_factory as _runner_factory
from agentic.commands._shell_helpers import invoke as _invoke

app = typer.Typer(name="hermes", help="Hermes adapter actions.")
actions = typer.Typer(help="Hermes actions list / validate.")
app.add_typer(actions, name="actions")


@actions.command("list")
def actions_list(ctx: typer.Context) -> None:
    _invoke(ctx, name="validate-hermes-actions.sh", args=[], run_id_flag=None, factory=_runner_factory)


@actions.command("validate")
def actions_validate(ctx: typer.Context) -> None:
    _invoke(ctx, name="validate-hermes-actions.sh", args=[], run_id_flag=None, factory=_runner_factory)


@app.command("run")
def hermes_run(
    ctx: typer.Context,
    action: str,
    kv_args: Annotated[list[str], typer.Argument()] = None,
) -> None:
    """agentic hermes run <action> [k=v ...]."""
    args = [action, *(kv_args or [])]
    _invoke(ctx, name="run-hermes-action.sh", args=args, run_id_flag=None, factory=_runner_factory)


@app.command("memory-sync")
def memory_sync(
    ctx: typer.Context,
    dry_run: Annotated[bool, typer.Option("--dry-run")] = True,
) -> None:
    args = ["--dry-run"] if dry_run else []
    _invoke(ctx, name="hermes-memory-sync.sh", args=args, run_id_flag=None, factory=_runner_factory)


@app.command("scheduler")
def scheduler(
    ctx: typer.Context,
    dry_run: Annotated[bool, typer.Option("--dry-run")] = True,
) -> None:
    args = ["--dry-run"] if dry_run else []
    _invoke(ctx, name="hermes-scheduler-dry-run.sh", args=args, run_id_flag=None, factory=_runner_factory)


@app.command("gateway")
def gateway(
    ctx: typer.Context,
    dry_run: Annotated[bool, typer.Option("--dry-run")] = True,
) -> None:
    args = ["--dry-run"] if dry_run else []
    _invoke(ctx, name="hermes-gateway-dry-run.sh", args=args, run_id_flag=None, factory=_runner_factory)
```

- [ ] **Step 4: Implement `cli/agentic/commands/identity.py`**

```python
"""`agentic identity ...` subcommands."""

from __future__ import annotations

from typing import Annotated

import typer

from agentic.commands._shell_helpers import default_factory as _runner_factory
from agentic.commands._shell_helpers import invoke as _invoke

app = typer.Typer(name="identity", help="Identity policy + authorization.")


@app.command("validate")
def validate(ctx: typer.Context) -> None:
    _invoke(ctx, name="validate-identity-policy.sh", args=[], run_id_flag=None, factory=_runner_factory)


@app.command("authorize")
def authorize(
    ctx: typer.Context,
    action: Annotated[str, typer.Option("--action")],
) -> None:
    _invoke(ctx, name="authorize-agentic-action.sh",
            args=["--action", action], run_id_flag=None, factory=_runner_factory)
```

- [ ] **Step 5: Implement `cli/agentic/commands/evidence.py`**

```python
"""`agentic evidence ...` subcommands."""

from __future__ import annotations

from typing import Annotated

import typer

from agentic.commands._shell_helpers import default_factory as _runner_factory
from agentic.commands._shell_helpers import invoke as _invoke

app = typer.Typer(name="evidence", help="Validation evidence record + redact.")


@app.command("record")
def record(
    ctx: typer.Context,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    _invoke(ctx, name="record-validation-evidence.sh", args=[], run_id_flag=run_id, factory=_runner_factory)


@app.command("redact")
def redact(
    ctx: typer.Context,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    _invoke(ctx, name="redact-local-evidence.sh", args=[], run_id_flag=run_id, factory=_runner_factory)
```

- [ ] **Step 6: Implement `cli/agentic/commands/fixtures.py`**

```python
"""`agentic fixtures ...`."""

from __future__ import annotations

import typer

from agentic.commands._shell_helpers import default_factory as _runner_factory
from agentic.commands._shell_helpers import invoke as _invoke

app = typer.Typer(name="fixtures", help="Golden fixtures runner.")


@app.command("run")
def run(ctx: typer.Context) -> None:
    _invoke(ctx, name="run-golden-fixtures.sh", args=[], run_id_flag=None, factory=_runner_factory)
```

- [ ] **Step 7: Implement `cli/agentic/commands/manifest_cmd.py`**

```python
"""`agentic manifest ...` subcommands (named manifest_cmd to avoid shadowing manifest.py)."""

from __future__ import annotations

from typing import Annotated

import typer

from agentic.commands._shell_helpers import default_factory as _runner_factory
from agentic.commands._shell_helpers import invoke as _invoke

app = typer.Typer(name="manifest", help="Manifest validators + privacy scan.")


@app.command("validate")
def validate(
    ctx: typer.Context,
    all_runs: Annotated[bool, typer.Option("--all")] = False,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
) -> None:
    args = ["--all"] if all_runs else ([run_id] if run_id else [])
    _invoke(ctx, name="validate-manifest-schema.sh", args=args,
            run_id_flag=run_id, factory=_runner_factory)


@app.command("templates")
def templates(
    ctx: typer.Context,
    run_id: Annotated[str, typer.Option("--run-id")],
) -> None:
    _invoke(ctx, name="validate-artifact-templates.sh", args=[run_id],
            run_id_flag=run_id, factory=_runner_factory)


@app.command("scan")
def scan(ctx: typer.Context) -> None:
    _invoke(ctx, name="privacy-scan-tracked.sh", args=[],
            run_id_flag=None, factory=_runner_factory)
```

- [ ] **Step 8: Implement `cli/agentic/commands/validate.py`**

```python
"""`agentic validate ...`."""

from __future__ import annotations

import typer

from agentic.commands._shell_helpers import default_factory as _runner_factory
from agentic.commands._shell_helpers import invoke as _invoke

app = typer.Typer(name="validate", help="Top-level validators.")


@app.command("system")
def system(ctx: typer.Context) -> None:
    _invoke(ctx, name="validate-agentic-system.sh", args=[],
            run_id_flag=None, factory=_runner_factory)
```

- [ ] **Step 9: Register all six in `cli/agentic/app.py`**

```python
from agentic.commands import evidence as evidence_cmd
from agentic.commands import fixtures as fixtures_cmd
from agentic.commands import hermes as hermes_cmd
from agentic.commands import identity as identity_cmd
from agentic.commands import manifest_cmd
from agentic.commands import validate as validate_cmd

app.add_typer(hermes_cmd.app, name="hermes")
app.add_typer(identity_cmd.app, name="identity")
app.add_typer(evidence_cmd.app, name="evidence")
app.add_typer(fixtures_cmd.app, name="fixtures")
app.add_typer(manifest_cmd.app, name="manifest")
app.add_typer(validate_cmd.app, name="validate")
```

- [ ] **Step 10: Run — expect PASS**

```bash
cd cli && pytest tests/test_commands_other.py -q
```

- [ ] **Step 11: Lint + type**

```bash
cd cli && ruff check agentic tests && mypy --strict agentic
```

- [ ] **Step 12: Commit**

```bash
git add cli/agentic/commands/hermes.py cli/agentic/commands/identity.py \
        cli/agentic/commands/evidence.py cli/agentic/commands/fixtures.py \
        cli/agentic/commands/manifest_cmd.py cli/agentic/commands/validate.py \
        cli/agentic/app.py cli/tests/test_commands_other.py
git commit -m "feat(cli): hermes/identity/evidence/fixtures/manifest/validate namespaces"
```

---

## Acceptance Criteria (from spec §13 CLI-09)

- Every remaining `scripts/*.sh` is reachable through a named subcommand (only `agentic raw` left for future / unknown scripts — covered in CLI-10).
- 12+ routing tests pass.

## Implementer / Reviewer

- **Implementer:** agency-agents Staff+ — `staff-software-engineer`.
- **Reviewer:** Claude Code CLI via AIT — `engineering-software-architect`, `engineering-security-engineer`, `engineering-code-reviewer`.

Evidence under `agentic/reviews/agentic-cli/CLI-09/`.

## Rollback

```bash
git revert <CLI-09 commits>
```
