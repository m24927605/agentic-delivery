# CLI-15: PyPI Publish Workflow + v0.1.0 Release Implementation Plan

> **For agentic-delivery pipeline:** Implementer = agency-agents Staff+. Reviewer = Claude Code CLI via AIT (security focus). Write scope: `.github/workflows/cli-publish.yml`, `cli/CHANGELOG.md`, the GitHub release tag `cli-v0.1.0`.

**Goal:** Publish `agentic-delivery 0.1.0` to PyPI via a tag-driven GitHub Actions workflow, with TestPyPI dry-run gate.

**Architecture:** Workflow uses PyPA's `pypi-publish` action with OIDC trusted publishing (no API token in CI secrets). TestPyPI publish triggers on `cli-v*-rc*` tags; production PyPI on `cli-v*` non-rc tags. Artifacts: wheel + sdist, both signed with PEP 740 attestations.

**Tech Stack:** GitHub Actions, hatchling build, `pypa/gh-action-pypi-publish`, `pypa/gh-action-pythonpublish-build`.

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `.github/workflows/cli-publish.yml` | Create | Tag-driven build + publish. |
| `cli/CHANGELOG.md` | Modify | Fill `[0.1.0]` entry. |
| (PyPI trusted-publisher config) | External | Set up on pypi.org via web UI. |

---

## Task 1: PyPI trusted publisher setup (operator-only, not implementer)

**Operator (Michael) action — not part of the implementer's diff:**

- [ ] **Step 1: On pypi.org**, create `agentic-delivery` project, then under Trusted Publishers add:
  - Repository: `m24927605/agentic-delivery`
  - Workflow: `cli-publish.yml`
  - Environment: `pypi`
- [ ] **Step 2: Same on test.pypi.org**, environment `testpypi`.
- [ ] **Step 3: Add GitHub Environments** `pypi` and `testpypi` to the repo (Settings → Environments). No secrets needed (OIDC handles auth).

(This is documented for traceability. The implementer waits for the operator to confirm before the workflow can succeed.)

---

## Task 2: Publish workflow

**Files:**
- Create: `.github/workflows/cli-publish.yml`

- [ ] **Step 1: Write `.github/workflows/cli-publish.yml`**

```yaml
name: cli-publish

on:
  push:
    tags:
      - "cli-v*"

permissions:
  contents: read
  id-token: write   # required for OIDC trusted publishing

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - name: Install build tooling
        run: pip install --upgrade pip build
      - name: Build wheel + sdist
        run: |
          cd cli
          python -m build
      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: dist
          path: cli/dist/*

  testpypi:
    if: contains(github.ref, '-rc')
    needs: build
    runs-on: ubuntu-latest
    environment: testpypi
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: dist
          path: dist
      - uses: pypa/gh-action-pypi-publish@release/v1
        with:
          repository-url: https://test.pypi.org/legacy/
          attestations: true

  pypi:
    if: ${{ !contains(github.ref, '-rc') }}
    needs: build
    runs-on: ubuntu-latest
    environment: pypi
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: dist
          path: dist
      - uses: pypa/gh-action-pypi-publish@release/v1
        with:
          attestations: true

  github-release:
    needs: pypi
    if: ${{ !contains(github.ref, '-rc') }}
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with:
          name: dist
          path: dist
      - uses: softprops/action-gh-release@v2
        with:
          files: dist/*
          name: ${{ github.ref_name }}
          generate_release_notes: true
```

- [ ] **Step 2: Validate workflow YAML**

```bash
python -c 'import yaml; yaml.safe_load(open(".github/workflows/cli-publish.yml"))'
```

Expected: no error.

- [ ] **Step 3: Local build dry-run**

```bash
cd cli && python -m build
ls dist/
```

Expected: `agentic_delivery-0.1.0-py3-none-any.whl` and `agentic_delivery-0.1.0.tar.gz`.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/cli-publish.yml
git commit -m "ci(cli): tag-driven PyPI publish via OIDC trusted publisher"
```

---

## Task 3: Fill `[0.1.0]` CHANGELOG entry

**Files:**
- Modify: `cli/CHANGELOG.md`

- [ ] **Step 1: Replace the unreleased header with a dated entry**

```markdown
# Changelog

All notable changes to the `agentic-delivery` CLI.

## [0.1.0] — 2026-05-27

### Added
- `agentic` CLI scaffold: Typer root, `--help`, `version`.
- Global flags: `--repo`, `--run-id`, `--actor`, `--role`, `--json`, `--no-compat-check`, `-v`, `-vv`, `--no-color`.
- Repo discovery (flag > env > walk-up > config).
- Pipeline compatibility check.
- Run-context resolution (flag > env > file) and `agentic run list/use/show/clear`.
- Read-only `Manifest` loader and `agentic status` (text + JSON).
- Declarative state engine and `agentic next` (suggest-only).
- Namespaces wrapping the full scripts/ catalog: `plan`, `impl`, `boss`, `hermes`, `identity`, `evidence`, `fixtures`, `manifest`, `validate`.
- `agentic raw <script.sh>` escape hatch with name validation.
- `--json` envelope `_schema: agentic.cli/v1` with snapshot-locked schema.
- Structured errors (`AgenticError`) with text + JSON renderers.
- `agentic doctor` batching the four core validators.
- Tab completion via `agentic --install-completion`.

### Notes
- Wraps `scripts/*.sh`; does not mutate manifests.
- `agency-agents` Staff+ implementers, AIT + Claude Code CLI adversarial review.
```

- [ ] **Step 2: Commit**

```bash
git add cli/CHANGELOG.md
git commit -m "docs(cli): finalize 0.1.0 changelog"
```

---

## Task 4: Tag and release

**Files:** none (operator action).

- [ ] **Step 1: Verify clean working tree**

```bash
git status -s
```

Expected: empty (everything from CLI-01..14 already committed).

- [ ] **Step 2: Dry-run via release candidate first**

```bash
git tag cli-v0.1.0-rc1
git push origin cli-v0.1.0-rc1
```

Expected:
- `cli-publish.yml` runs `build` then `testpypi` (because tag contains `-rc`).
- Package appears on test.pypi.org.
- `pip install --index-url https://test.pypi.org/simple/ agentic-delivery==0.1.0rc1` works in a fresh venv.

- [ ] **Step 3: Real release**

```bash
git tag cli-v0.1.0
git push origin cli-v0.1.0
```

Expected:
- `build` + `pypi` + `github-release` jobs green.
- Package installable via `pipx install agentic-delivery`.
- GitHub Release created with `dist/*` attached.

- [ ] **Step 4: Verify install**

```bash
pipx install agentic-delivery
agentic version
```

Expected: prints `agentic-delivery CLI  0.1.0`.

---

## Acceptance Criteria (from spec §13 CLI-15)

- TestPyPI publish via `cli-v0.1.0-rc1` succeeds.
- PyPI publish via `cli-v0.1.0` succeeds.
- `pipx install agentic-delivery` installs and runs.
- GitHub Release attached with wheel + sdist + PEP 740 attestations.
- CHANGELOG `[0.1.0]` finalised with date.

## Implementer / Reviewer

- **Implementer:** agency-agents Staff+ — `staff-software-engineer` (workflow + changelog).
- **Reviewer:** Claude Code CLI via AIT — `engineering-software-architect`, **`engineering-security-engineer` (mandatory — supply-chain surface)**, `engineering-code-reviewer`.

```bash
unset ANTHROPIC_API_KEY
ait run --adapter claude-code --stdin none --apply never --review never --format json -- \
  "$(command -v claude)" \
  --agent engineering-security-engineer \
  --add-dir "$PWD" \
  -p "Adversarial review of .github/workflows/cli-publish.yml for supply-chain risk: OIDC scope, permissions, attestation, environment gating, secret handling, build provenance. Output JSON: {findings: [{severity, file, line?, issue, recommendation}]}."
```

Evidence under `agentic/reviews/agentic-cli/CLI-15/`.

## Rollback

- Pre-publish: `git revert` the workflow + changelog commits.
- Post-publish: `pypi.org` yank (`pip install agentic-delivery==0.1.0` keeps working for already-installed users, but new installs warn). Cut a 0.1.1 patch with the fix; do not delete the 0.1.0 tag.
