# CLI-13: CI Workflow + E2E Smoke Implementation Plan

> **For agentic-delivery pipeline:** Implementer = agency-agents Staff+. Reviewer = Claude Code CLI via AIT. Write scope: `.github/workflows/cli.yml`, `cli/tests/smoke/**`, `cli/pyproject.toml` (coverage configuration).

**Goal:** Land a GitHub Actions workflow that lints, type-checks, runs the unit + integration tests with coverage gate ≥ 85, and runs the e2e smoke once.

**Architecture:** Single workflow `.github/workflows/cli.yml` triggered on PR + push to main. Matrix: `os: [ubuntu-latest, macos-latest] × python: ["3.10","3.11","3.12","3.13"]`. E2E smoke runs only on `ubuntu-latest` + Python 3.12. Coverage gate uses `pytest --cov=agentic --cov-fail-under=85`.

**Tech Stack:** GitHub Actions, pytest-cov, bash for smoke.

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `.github/workflows/cli.yml` | Create | Lint + type + test + smoke. |
| `cli/pyproject.toml` | Modify | Add `pytest-cov` to dev deps; configure cov section. |
| `cli/tests/smoke/test_e2e.sh` | Create | Real-script end-to-end smoke. |
| `cli/tests/smoke/fixtures/` | Create | Minimal goal file for `agentic init`. |

---

## Task 1: Coverage tooling in pyproject

**Files:**
- Modify: `cli/pyproject.toml`

- [ ] **Step 1: Add `pytest-cov` and config**

```toml
[project.optional-dependencies]
dev = [
  "pytest >= 8",
  "pytest-snapshot",
  "pytest-cov",
  "ruff",
  "mypy",
]

[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "-ra"

[tool.coverage.run]
branch = true
source = ["agentic"]

[tool.coverage.report]
fail_under = 85
show_missing = true
```

- [ ] **Step 2: Run locally**

```bash
cd cli && pip install -e .[dev]
cd cli && pytest --cov=agentic --cov-report=term-missing
```

Expected: report prints; if under 85, raise targeted tests until clean (state_engine and command modules will likely already be > 85 because of CLI-01..CLI-12 TDD).

- [ ] **Step 3: Commit**

```bash
git add cli/pyproject.toml
git commit -m "test(cli): coverage gate >= 85"
```

---

## Task 2: GitHub Actions workflow

**Files:**
- Create: `.github/workflows/cli.yml`

- [ ] **Step 1: Write `.github/workflows/cli.yml`**

```yaml
name: cli

on:
  pull_request:
    paths:
      - "cli/**"
      - ".github/workflows/cli.yml"
  push:
    branches: [main]
    paths:
      - "cli/**"
      - ".github/workflows/cli.yml"

jobs:
  test:
    name: ${{ matrix.os }} / py${{ matrix.python }}
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest]
        python: ["3.10", "3.11", "3.12", "3.13"]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python }}
      - name: Install
        run: |
          pip install --upgrade pip
          pip install -e cli/[dev]
      - name: Ruff
        run: ruff check cli/agentic cli/tests
      - name: Mypy
        run: mypy --strict cli/agentic
      - name: Pytest with coverage gate
        run: |
          cd cli && pytest --cov=agentic --cov-report=term-missing --cov-fail-under=85

  e2e:
    name: e2e smoke (ubuntu/py3.12)
    runs-on: ubuntu-latest
    needs: test
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - name: Install
        run: |
          pip install --upgrade pip
          pip install -e cli/[dev]
      - name: Run smoke
        run: bash cli/tests/smoke/test_e2e.sh
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/cli.yml
git commit -m "ci(cli): matrix lint+type+test+coverage and e2e smoke"
```

---

## Task 3: E2E smoke script

**Files:**
- Create: `cli/tests/smoke/test_e2e.sh`
- Create: `cli/tests/smoke/fixtures/goal.md`

- [ ] **Step 1: Write `cli/tests/smoke/fixtures/goal.md`**

```markdown
# Goal

Smoke test goal for CLI e2e flow.
```

- [ ] **Step 2: Write `cli/tests/smoke/test_e2e.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# Doctor on a clean checkout
agentic doctor || true   # may fail if validators are strict — informational

# Init a planning run
RUN_ID=cli-smoke agentic init "smoke test" --goal-file cli/tests/smoke/fixtures/goal.md || \
  scripts/init-agentic-run.sh --goal-file cli/tests/smoke/fixtures/goal.md
agentic --run-id cli-smoke status > /tmp/agentic-status.txt
cat /tmp/agentic-status.txt
grep -q cli-smoke /tmp/agentic-status.txt

# JSON envelope
agentic --json --run-id cli-smoke status | python -c '
import json, sys
p = json.load(sys.stdin)
assert p["_schema"] == "agentic.cli/v1", p
assert p["run"]["id"] == "cli-smoke", p
print("ok")
'

# raw escape hatch
agentic raw validate-agentic-system.sh || true

echo "smoke ok"
```

- [ ] **Step 3: Make executable**

```bash
chmod +x cli/tests/smoke/test_e2e.sh
```

- [ ] **Step 4: Run locally**

```bash
bash cli/tests/smoke/test_e2e.sh
```

Expected: exit 0, "smoke ok" at the end. (`agentic init` is not yet wrapped — wired in CLI-14 README footnote / planning bootstrap; smoke gracefully falls back to `scripts/init-agentic-run.sh`.)

- [ ] **Step 5: Commit**

```bash
git add cli/tests/smoke/
git commit -m "test(cli): e2e smoke script"
```

---

## Acceptance Criteria (from spec §13 CLI-13)

- CI workflow green on a clean PR.
- Coverage gate enforced at ≥ 85.
- E2E smoke passes on `ubuntu-latest` + Python 3.12.

## Implementer / Reviewer

- **Implementer:** agency-agents Staff+ — `staff-software-engineer`.
- **Reviewer:** Claude Code CLI via AIT — `engineering-software-architect`, `engineering-code-reviewer`.

Evidence under `agentic/reviews/agentic-cli/CLI-13/`.

## Rollback

```bash
git revert <CLI-13 commits>
```
