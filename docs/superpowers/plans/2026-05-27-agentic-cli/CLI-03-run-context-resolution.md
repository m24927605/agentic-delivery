# CLI-03: Run-Context Resolution + `agentic run` Implementation Plan

> **For agentic-delivery pipeline:** Implementer = agency-agents Staff+. Reviewer = Claude Code CLI via AIT. Write scope `cli/**` plus a single line addition to top-level `.gitignore`.

**Goal:** Provide flag > env > file run-id resolution and the `agentic run list / use / show / clear` commands.

**Architecture:** Extend `cli/agentic/context.py` with `resolve_run_id()` returning `(run_id, source)`. Persist current run in `<repo>/.agentic/current-run` (single plain-text line). `agentic run` subcommands in `cli/agentic/commands/run.py`.

**Tech Stack:** Typer subcommand, Rich table for `run list`.

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `cli/agentic/context.py` | Modify | Add `RunNotFound`, `Run`, `resolve_run_id`. |
| `cli/agentic/commands/__init__.py` | Create | Empty marker. |
| `cli/agentic/commands/run.py` | Create | `run` Typer sub-app. |
| `cli/agentic/app.py` | Modify | Register `run` sub-app + global `--run-id`. |
| `.gitignore` (repo top-level) | Modify | Add `.agentic/`. |
| `cli/tests/test_run_context.py` | Create | Resolution priority. |
| `cli/tests/test_run_commands.py` | Create | CLI subcommands. |

---

## Task 1: Top-level `.gitignore` adds `.agentic/`

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Append `.agentic/` to top-level `.gitignore` (under "Local private delivery artifacts")**

Patch:

```diff
 # Local private delivery artifacts.
+.agentic/
 docs/*goal-prompt.md
```

- [ ] **Step 2: Verify**

```bash
git check-ignore -v .agentic/current-run
```

Expected: `.gitignore` line matches.

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: gitignore .agentic/ for CLI run-context file"
```

---

## Task 2: TDD — `resolve_run_id` priority

**Files:**
- Modify: `cli/agentic/context.py`
- Create: `cli/tests/test_run_context.py`

- [ ] **Step 1: Write failing tests `cli/tests/test_run_context.py`**

```python
from pathlib import Path

import pytest

from agentic.context import RunNotFound, resolve_run_id


def _seed_repo(tmp_path: Path, *, runs: list[str], current: str | None = None) -> Path:
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    for r in runs:
        (tmp_path / "agentic" / "runs" / r).mkdir(parents=True)
        (tmp_path / "agentic" / "runs" / r / "manifest.yaml").write_text("run:\n  id: " + r + "\n")
    if current is not None:
        (tmp_path / ".agentic").mkdir()
        (tmp_path / ".agentic" / "current-run").write_text(current + "\n")
    return tmp_path


def test_flag_beats_env_beats_file(tmp_path, monkeypatch):
    repo = _seed_repo(tmp_path, runs=["a", "b", "c"], current="a")
    monkeypatch.setenv("AIT_RUN_ID", "b")
    run = resolve_run_id(repo=repo, flag="c")
    assert run.id == "c"
    assert run.source == "--run-id"


def test_env_beats_file_when_no_flag(tmp_path, monkeypatch):
    repo = _seed_repo(tmp_path, runs=["a", "b"], current="a")
    monkeypatch.setenv("AIT_RUN_ID", "b")
    run = resolve_run_id(repo=repo, flag=None)
    assert run.id == "b"
    assert run.source == "AIT_RUN_ID"


def test_file_used_when_no_flag_no_env(tmp_path, monkeypatch):
    repo = _seed_repo(tmp_path, runs=["a"], current="a")
    monkeypatch.delenv("AIT_RUN_ID", raising=False)
    run = resolve_run_id(repo=repo, flag=None)
    assert run.id == "a"
    assert run.source == "file:.agentic/current-run"


def test_missing_raises(tmp_path, monkeypatch):
    repo = _seed_repo(tmp_path, runs=["a"])
    monkeypatch.delenv("AIT_RUN_ID", raising=False)
    with pytest.raises(RunNotFound):
        resolve_run_id(repo=repo, flag=None)


def test_unknown_run_rejected(tmp_path, monkeypatch):
    repo = _seed_repo(tmp_path, runs=["a"])
    monkeypatch.delenv("AIT_RUN_ID", raising=False)
    with pytest.raises(RunNotFound):
        resolve_run_id(repo=repo, flag="ghost")


def test_empty_file_falls_through(tmp_path, monkeypatch):
    repo = _seed_repo(tmp_path, runs=["a"], current="")
    monkeypatch.setenv("AIT_RUN_ID", "a")
    run = resolve_run_id(repo=repo, flag=None)
    assert run.id == "a"
    assert run.source == "AIT_RUN_ID"
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd cli && pytest tests/test_run_context.py -q
```

- [ ] **Step 3: Extend `cli/agentic/context.py`**

```python
@dataclass(frozen=True)
class Run:
    id: str
    source: str


class RunNotFound(Exception):
    """Raised when a run id cannot be resolved or does not exist on disk."""


def _run_exists(repo: Path, run_id: str) -> bool:
    return (repo / "agentic" / "runs" / run_id / "manifest.yaml").is_file() or \
           (repo / "agentic" / "runs" / run_id / "implementation-manifest.yaml").is_file()


def resolve_run_id(*, repo: Path, flag: str | None) -> Run:
    if flag:
        if not _run_exists(repo, flag):
            raise RunNotFound(f"run {flag!r} does not exist under {repo}/agentic/runs/")
        return Run(id=flag, source="--run-id")

    env = os.environ.get("AIT_RUN_ID")
    if env:
        if not _run_exists(repo, env):
            raise RunNotFound(f"AIT_RUN_ID={env!r} does not exist under {repo}/agentic/runs/")
        return Run(id=env, source="AIT_RUN_ID")

    current_file = repo / ".agentic" / "current-run"
    if current_file.is_file():
        first = next(
            (line.strip() for line in current_file.read_text().splitlines() if line.strip()),
            None,
        )
        if first:
            if not _run_exists(repo, first):
                raise RunNotFound(
                    f"run {first!r} from .agentic/current-run does not exist under "
                    f"{repo}/agentic/runs/. Run 'agentic run clear' or 'agentic run use <id>'."
                )
            return Run(id=first, source="file:.agentic/current-run")

    raise RunNotFound(
        "no run context. Use --run-id, set AIT_RUN_ID, or 'agentic run use <id>'."
    )
```

- [ ] **Step 4: Run — expect PASS**

```bash
cd cli && pytest tests/test_run_context.py -q
```

Expected: 6 passed.

- [ ] **Step 5: Commit**

```bash
git add cli/agentic/context.py cli/tests/test_run_context.py
git commit -m "feat(cli): resolve_run_id with flag > env > file priority"
```

---

## Task 3: TDD — `agentic run list/use/show/clear`

**Files:**
- Create: `cli/agentic/commands/__init__.py` (empty)
- Create: `cli/agentic/commands/run.py`
- Modify: `cli/agentic/app.py`
- Create: `cli/tests/test_run_commands.py`

- [ ] **Step 1: Write `cli/agentic/commands/__init__.py`** (empty)

- [ ] **Step 2: Write failing tests `cli/tests/test_run_commands.py`**

```python
from pathlib import Path

from agentic.app import app


def _seed(tmp_path: Path, runs: list[str]) -> Path:
    (tmp_path / "agentic").mkdir()
    (tmp_path / "agentic" / "pipeline.yaml").write_text("pipeline:\n  version: v0.6\n")
    for r in runs:
        d = tmp_path / "agentic" / "runs" / r
        d.mkdir(parents=True)
        (d / "manifest.yaml").write_text("run:\n  id: " + r + "\n")
    return tmp_path


def test_run_use_writes_file(cli, tmp_path, monkeypatch):
    repo = _seed(tmp_path, ["alpha", "beta"])
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["run", "use", "alpha"])
    assert result.exit_code == 0
    assert (repo / ".agentic" / "current-run").read_text().strip() == "alpha"


def test_run_use_rejects_unknown(cli, tmp_path, monkeypatch):
    repo = _seed(tmp_path, ["alpha"])
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["run", "use", "ghost"])
    assert result.exit_code != 0
    assert "does not exist" in result.stderr.lower() or "does not exist" in result.stdout.lower()


def test_run_show_prints_source(cli, tmp_path, monkeypatch):
    repo = _seed(tmp_path, ["alpha"])
    (repo / ".agentic").mkdir()
    (repo / ".agentic" / "current-run").write_text("alpha\n")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["run", "show"])
    assert result.exit_code == 0
    assert "alpha" in result.stdout
    assert "file:.agentic/current-run" in result.stdout


def test_run_clear_deletes_file(cli, tmp_path, monkeypatch):
    repo = _seed(tmp_path, ["alpha"])
    (repo / ".agentic").mkdir()
    (repo / ".agentic" / "current-run").write_text("alpha\n")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["run", "clear"])
    assert result.exit_code == 0
    assert not (repo / ".agentic" / "current-run").exists()


def test_run_list_marks_current(cli, tmp_path, monkeypatch):
    repo = _seed(tmp_path, ["alpha", "beta"])
    (repo / ".agentic").mkdir()
    (repo / ".agentic" / "current-run").write_text("beta\n")
    monkeypatch.chdir(repo)
    result = cli.invoke(app, ["run", "list"])
    assert result.exit_code == 0
    assert "alpha" in result.stdout
    assert "beta" in result.stdout
    # beta is current; should be marked with *
    line_with_beta = next(l for l in result.stdout.splitlines() if "beta" in l)
    assert "*" in line_with_beta
```

- [ ] **Step 3: Run — expect FAIL**

```bash
cd cli && pytest tests/test_run_commands.py -q
```

- [ ] **Step 4: Implement `cli/agentic/commands/run.py`**

```python
"""`agentic run` subcommands."""

from __future__ import annotations

from pathlib import Path

import typer
from rich.console import Console
from rich.table import Table

from agentic.context import RepoNotFound, RunNotFound, resolve_repo, resolve_run_id

app = typer.Typer(name="run", help="Manage current run context.")

_console = Console()


def _current_file(repo: Path) -> Path:
    return repo / ".agentic" / "current-run"


def _get_repo(ctx: typer.Context) -> Path:
    flag = ctx.obj.get("repo_flag") if ctx.obj else None
    return resolve_repo(repo_flag=flag).path


@app.command("use")
def use(ctx: typer.Context, run_id: str) -> None:
    """Set <run-id> as the current run for this repo."""
    repo = _get_repo(ctx)
    try:
        run = resolve_run_id(repo=repo, flag=run_id)
    except RunNotFound as e:
        typer.echo(f"x  {e}", err=True)
        raise typer.Exit(code=6)
    target = _current_file(repo)
    target.parent.mkdir(exist_ok=True)
    target.write_text(run.id + "\n")
    typer.echo(f"current run -> {run.id}")


@app.command("show")
def show(ctx: typer.Context) -> None:
    """Print the resolved current run and its source."""
    repo = _get_repo(ctx)
    try:
        run = resolve_run_id(repo=repo, flag=None)
    except RunNotFound as e:
        typer.echo(f"x  {e}", err=True)
        raise typer.Exit(code=6)
    typer.echo(run.id)
    typer.echo(f"  source: {run.source}")


@app.command("clear")
def clear(ctx: typer.Context) -> None:
    """Delete the .agentic/current-run file."""
    repo = _get_repo(ctx)
    target = _current_file(repo)
    if target.exists():
        target.unlink()
        typer.echo("cleared")
    else:
        typer.echo("nothing to clear")


@app.command("list")
def list_(ctx: typer.Context) -> None:
    """List runs under agentic/runs/."""
    repo = _get_repo(ctx)
    runs_dir = repo / "agentic" / "runs"
    try:
        current = resolve_run_id(repo=repo, flag=None).id
    except RunNotFound:
        current = None
    table = Table(show_header=True)
    table.add_column("")
    table.add_column("run id")
    table.add_column("kind")
    if runs_dir.is_dir():
        for entry in sorted(runs_dir.iterdir()):
            if not entry.is_dir():
                continue
            kind = "implementation" if (entry / "implementation-manifest.yaml").is_file() else "planning"
            mark = "*" if entry.name == current else ""
            table.add_row(mark, entry.name, kind)
    _console.print(table)
```

- [ ] **Step 5: Wire into `cli/agentic/app.py`**

```python
# add near top
from agentic.commands import run as run_cmd

# after `app = typer.Typer(...)`:
app.add_typer(run_cmd.app, name="run")
```

Also extend the root callback to accept `--run-id` so it threads through `ctx.obj`:

```python
@app.callback()
def _root(
    ctx: typer.Context,
    repo: Annotated[Path | None, typer.Option("--repo")] = None,
    run_id: Annotated[str | None, typer.Option("--run-id")] = None,
    no_compat_check: Annotated[bool, typer.Option("--no-compat-check")] = False,
) -> None:
    ctx.obj = {
        "repo_flag": repo,
        "run_id_flag": run_id,
        "compat_check": not no_compat_check,
    }
```

- [ ] **Step 6: Run — expect PASS**

```bash
cd cli && pytest tests/test_run_commands.py -q
```

Expected: 5 passed.

- [ ] **Step 7: Lint + type clean**

```bash
cd cli && ruff check agentic tests && mypy --strict agentic
```

- [ ] **Step 8: Commit**

```bash
git add cli/agentic/commands/ cli/agentic/app.py cli/tests/test_run_commands.py
git commit -m "feat(cli): agentic run list/use/show/clear + --run-id"
```

---

## Acceptance Criteria (from spec §13 CLI-03)

- `.agentic/` gitignored at repo root.
- `resolve_run_id` honours flag > env > file priority; rejects unknown ids; ignores empty files.
- `agentic run use` writes file; refuses unknown id (exit 6).
- `agentic run show` prints id + source even without `-v`.
- `agentic run clear` removes the file idempotently.
- `agentic run list` marks current with `*`.

## Implementer / Reviewer

- **Implementer:** agency-agents Staff+ — `staff-software-engineer`.
- **Reviewer:** Claude Code CLI via AIT — `engineering-software-architect`, `engineering-security-engineer`, `engineering-code-reviewer`.

Evidence under `agentic/reviews/agentic-cli/CLI-03/`.

## Rollback

```bash
git revert <CLI-03 commits>
```
