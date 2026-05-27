# CLI-00: Bootstrap Slice Tracking Implementation Plan

> **For agentic-delivery pipeline:** Implementer = agency-agents (msitarzewski) Staff+. Reviewer = Claude Code CLI via AIT (read-only, `--apply never`). Execution runs through `scripts/dispatch-implementation-task.sh` → `scripts/execute-implementation-task.sh` → `scripts/run-implementation-review-loop.sh`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the agentic-delivery planning + implementation runs that will own CLI-01 … CLI-15, with the slice backlog tracked under `docs/backlog/agentic-cli-slices.md`.

**Architecture:** This slice is operational, not code. It reuses the existing `scripts/init-agentic-run.sh` → review-fix loop → approval → `scripts/init-implementation-run.sh` pipeline. The CLI design spec and the new slice backlog become the two approved planning artifacts that seed the implementation run.

**Tech Stack:** existing `scripts/*.sh`, `agentic/profiles/default-delivery.yaml`, YAML.

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `docs/backlog/agentic-cli-slices.md` | Create | Tracked slice backlog for CLI-01 … CLI-15. Mirrors the per-slice records from spec §13. |
| `agentic/runs/<planning-run-id>/manifest.yaml` | Create via script | Planning run owning the spec + backlog as artifacts. |
| `agentic/runs/<implementation-run-id>/implementation-manifest.yaml` | Create via script | Implementation run that the remaining slices dispatch against. |

No `cli/` files are created in this slice.

---

## Task 1: Author the slice backlog

**Files:**
- Create: `docs/backlog/agentic-cli-slices.md`

- [ ] **Step 1: Write `docs/backlog/agentic-cli-slices.md`** as a tracked summary that references each slice's detailed plan file. Public-safe only — no client identifiers, no secrets, no private strategy.

```markdown
# Agentic CLI Implementation Slices

Source spec: `docs/superpowers/specs/2026-05-27-agentic-cli-design.md`
Per-slice plans: `docs/superpowers/plans/2026-05-27-agentic-cli/CLI-NN-*.md`
Authority: planning-run manifest only. Hermes memory is execution context only.

## CLI-01 — Scaffold `cli/` package
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-01-scaffold-package.md
- write_scope: cli/**
- dependencies: []
- implementer: agency-agents/staff-software-engineer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-code-reviewer]
- evidence: agentic/reviews/agentic-cli/CLI-01/

## CLI-02 — Repo discovery + compat check
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-02-repo-discovery-compat.md
- write_scope: cli/**
- dependencies: [CLI-01]
- implementer: agency-agents/staff-software-engineer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-security-engineer, engineering-code-reviewer]
- evidence: agentic/reviews/agentic-cli/CLI-02/

## CLI-03 — Run-context resolution + agentic run commands
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-03-run-context-resolution.md
- write_scope: cli/**, .gitignore (one line)
- dependencies: [CLI-02]
- implementer: agency-agents/staff-software-engineer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-security-engineer, engineering-code-reviewer]
- evidence: agentic/reviews/agentic-cli/CLI-03/

## CLI-04 — manifest.py reader + agentic status
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-04-manifest-reader-status.md
- write_scope: cli/**
- dependencies: [CLI-03]
- implementer: agency-agents/staff-software-engineer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-code-reviewer, engineering-technical-writer]
- evidence: agentic/reviews/agentic-cli/CLI-04/

## CLI-05 — State engine v1 + agentic next
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-05-state-engine-next.md
- write_scope: cli/**
- dependencies: [CLI-04]
- implementer: agency-agents/staff-software-engineer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-code-reviewer, product-manager]
- evidence: agentic/reviews/agentic-cli/CLI-05/

## CLI-06 — shell.py + agentic plan namespace
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-06-shell-plan-namespace.md
- write_scope: cli/**
- dependencies: [CLI-05]
- implementer: agency-agents/staff-software-engineer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-security-engineer, engineering-code-reviewer]
- evidence: agentic/reviews/agentic-cli/CLI-06/

## CLI-07 — agentic impl namespace
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-07-impl-namespace.md
- write_scope: cli/**
- dependencies: [CLI-06]
- implementer: agency-agents/staff-software-engineer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-security-engineer, engineering-code-reviewer]
- evidence: agentic/reviews/agentic-cli/CLI-07/

## CLI-08 — agentic boss namespace
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-08-boss-namespace.md
- write_scope: cli/**
- dependencies: [CLI-06]
- implementer: agency-agents/staff-software-engineer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-code-reviewer]
- evidence: agentic/reviews/agentic-cli/CLI-08/

## CLI-09 — Remaining namespaces (hermes, identity, evidence, fixtures, manifest, validate)
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-09-remaining-namespaces.md
- write_scope: cli/**
- dependencies: [CLI-06]
- implementer: agency-agents/staff-software-engineer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-security-engineer, engineering-code-reviewer]
- evidence: agentic/reviews/agentic-cli/CLI-09/

## CLI-10 — agentic raw escape hatch
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-10-raw-escape-hatch.md
- write_scope: cli/**
- dependencies: [CLI-06]
- implementer: agency-agents/staff-software-engineer
- reviewer: claude-code-cli-via-ait [engineering-security-engineer, engineering-code-reviewer]
- evidence: agentic/reviews/agentic-cli/CLI-10/

## CLI-11 — --json mode + structured errors
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-11-json-mode-structured-errors.md
- write_scope: cli/**
- dependencies: [CLI-07, CLI-08, CLI-09, CLI-10]
- implementer: agency-agents/staff-software-engineer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-code-reviewer, engineering-technical-writer, product-manager]
- evidence: agentic/reviews/agentic-cli/CLI-11/

## CLI-12 — Tab completion + agentic doctor
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-12-completion-and-doctor.md
- write_scope: cli/**
- dependencies: [CLI-11]
- implementer: agency-agents/staff-software-engineer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-code-reviewer]
- evidence: agentic/reviews/agentic-cli/CLI-12/

## CLI-13 — CI workflow + e2e smoke
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-13-ci-and-smoke.md
- write_scope: .github/workflows/cli.yml, cli/tests/smoke/**, cli/pyproject.toml (cov config)
- dependencies: [CLI-12]
- implementer: agency-agents/staff-software-engineer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-code-reviewer]
- evidence: agentic/reviews/agentic-cli/CLI-13/

## CLI-14 — README + goal-prompt footnotes
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-14-readme-and-goal-prompt-footnotes.md
- write_scope: agentic/README.md, docs/auto-docs-to-implementation-goal-prompt.md, docs/hermes-adapter-slices-goal-prompt.md (if tracked)
- dependencies: [CLI-12]
- implementer: agency-agents/staff-software-engineer
- reviewer: claude-code-cli-via-ait [engineering-technical-writer, product-manager, engineering-software-architect]
- evidence: agentic/reviews/agentic-cli/CLI-14/

## CLI-15 — PyPI publish workflow + v0.1.0 release
- plan: docs/superpowers/plans/2026-05-27-agentic-cli/CLI-15-pypi-publish-release.md
- write_scope: .github/workflows/cli-publish.yml, cli/CHANGELOG.md
- dependencies: [CLI-13, CLI-14]
- implementer: agency-agents/staff-software-engineer
- reviewer: claude-code-cli-via-ait [engineering-software-architect, engineering-security-engineer, engineering-code-reviewer]
- evidence: agentic/reviews/agentic-cli/CLI-15/
```

The implementer writes this file verbatim. No expansion needed beyond the literal block above.

- [ ] **Step 2: Confirm public-safe.** Run

```bash
scripts/privacy-scan-tracked.sh
```

Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add docs/backlog/agentic-cli-slices.md
git commit -m "docs: track agentic CLI implementation slices"
```

---

## Task 2: Initialise the planning run

**Files:**
- Created by script: `agentic/runs/<planning-run-id>/manifest.yaml`

- [ ] **Step 1: Author the planning goal file** (kept under `agentic/runs/` which is ignored)

```bash
mkdir -p agentic/runs/.tmp
cat > agentic/runs/.tmp/agentic-cli-planning-goal.md <<'EOF'
---
artifacts:
  - path: docs/superpowers/specs/2026-05-27-agentic-cli-design.md
    kind: architecture
    purpose: Approved CLI v0.1 design spec.
    agent: existing
  - path: docs/backlog/agentic-cli-slices.md
    kind: backlog
    purpose: Tracked slice backlog for CLI-01 .. CLI-15.
    agent: existing
---

# Goal

Plan and approve the agentic CLI v0.1 design and slice backlog. Implementation
slices CLI-01 .. CLI-15 will be dispatched against the implementation run
seeded from this planning run.
EOF
```

- [ ] **Step 2: Initialise the planning run**

```bash
RUN_ID=agentic-cli-v0.1-planning \
  scripts/init-agentic-run.sh --goal-file agentic/runs/.tmp/agentic-cli-planning-goal.md
```

Expected: `agentic/runs/agentic-cli-v0.1-planning/manifest.yaml` created, both artifacts listed with `status: planned`.

- [ ] **Step 3: Validate the manifest**

```bash
scripts/validate-manifest-schema.sh agentic-cli-v0.1-planning
```

Expected: exit 0.

---

## Task 3: Move spec + backlog to `approved`

**Files:**
- Modified by script: `agentic/runs/agentic-cli-v0.1-planning/manifest.yaml`

- [ ] **Step 1: Mark both artifacts `drafted`** — files already exist in tracked locations.

```bash
RUN_ID=agentic-cli-v0.1-planning \
scripts/update-artifact-status.sh agentic-cli-v0.1-planning \
  docs/superpowers/specs/2026-05-27-agentic-cli-design.md drafted \
  --reason "Spec authored and committed" \
  --actor local-operator --role drafter

RUN_ID=agentic-cli-v0.1-planning \
scripts/update-artifact-status.sh agentic-cli-v0.1-planning \
  docs/backlog/agentic-cli-slices.md drafted \
  --reason "Backlog authored and committed" \
  --actor local-operator --role drafter
```

- [ ] **Step 2: Run the artifact review loop** against each (max 5 rounds per the pipeline rule)

```bash
unset ANTHROPIC_API_KEY
RUN_ID=agentic-cli-v0.1-planning \
scripts/run-artifact-review-loop.sh agentic-cli-v0.1-planning \
  --artifact docs/superpowers/specs/2026-05-27-agentic-cli-design.md

RUN_ID=agentic-cli-v0.1-planning \
scripts/run-artifact-review-loop.sh agentic-cli-v0.1-planning \
  --artifact docs/backlog/agentic-cli-slices.md
```

Expected: review evidence written under `agentic/reviews/`, both artifacts move to `reviewed`. Round count ≤ 5 per artifact.

- [ ] **Step 3: Approve both artifacts**

```bash
RUN_ID=agentic-cli-v0.1-planning \
scripts/update-artifact-status.sh agentic-cli-v0.1-planning \
  docs/superpowers/specs/2026-05-27-agentic-cli-design.md approved \
  --reason "Approved for agentic CLI v0.1 implementation" \
  --actor local-operator --role approver

RUN_ID=agentic-cli-v0.1-planning \
scripts/update-artifact-status.sh agentic-cli-v0.1-planning \
  docs/backlog/agentic-cli-slices.md approved \
  --reason "Approved for agentic CLI v0.1 implementation" \
  --actor local-operator --role approver
```

- [ ] **Step 4: Confirm**

```bash
scripts/report-run-status.sh agentic-cli-v0.1-planning
```

Expected: `artifacts_approved == 2`, `artifacts_pending == 0`.

---

## Task 4: Initialise the implementation run

**Files:**
- Created by script: `agentic/runs/<implementation-run-id>/implementation-manifest.yaml`

- [ ] **Step 1: Initialise from the planning run**

```bash
RUN_ID=agentic-cli-v0.1-impl \
scripts/init-implementation-run.sh --planning-run agentic-cli-v0.1-planning
```

Expected: implementation manifest created listing both approved artifacts under `approved_inputs`.

- [ ] **Step 2: Generate the implementation task graph**

```bash
scripts/generate-implementation-task-graph.sh agentic-cli-v0.1-impl
```

Expected: tasks CLI-01 … CLI-15 appear in the manifest with dependency metadata matching spec §13.x sequencing.

- [ ] **Step 3: Validate**

```bash
scripts/validate-implementation-run.sh agentic-cli-v0.1-impl
scripts/validate-manifest-schema.sh agentic-cli-v0.1-impl
```

Expected: both exit 0.

- [ ] **Step 4: Persist current run for the rest of CLI-01 .. CLI-15**

```bash
mkdir -p .agentic
echo agentic-cli-v0.1-impl > .agentic/current-run
```

(`.agentic/` is gitignored. This is for operator convenience between slices.)

---

## Acceptance Criteria (from spec §13 CLI-00)

- Planning run `agentic-cli-v0.1-planning` exists with two approved artifacts.
- Implementation run `agentic-cli-v0.1-impl` exists with task graph CLI-01 … CLI-15.
- `scripts/report-run-status.sh agentic-cli-v0.1-impl` reports `artifacts_approved == 2`.
- `agentic/reviews/agentic-cli/CLI-00/` contains the round JSON traces.

## Implementer / Reviewer

- **Implementer:** agency-agents Staff+ — `staff-software-engineer` is sufficient (operational slice, no code).
- **Reviewer:** Claude Code CLI via AIT — `engineering-software-architect`, `engineering-technical-writer`.

```bash
unset ANTHROPIC_API_KEY
ait run --adapter claude-code --stdin none --apply never --review never --format json -- \
  "$(command -v claude)" \
  --agent engineering-software-architect \
  --add-dir "$PWD" \
  -p "Review docs/backlog/agentic-cli-slices.md and the planning run manifest at agentic/runs/agentic-cli-v0.1-planning/manifest.yaml for completeness against docs/superpowers/specs/2026-05-27-agentic-cli-design.md §13. Output JSON with findings keyed by slice id."
```

Repeat with `--agent engineering-technical-writer`. Trace ids recorded in `agentic-cli-v0.1-planning` manifest history.

## Execution Handoff

This slice is operational, not code. The remaining 15 slices dispatch through the agentic-delivery pipeline:

```bash
scripts/dispatch-implementation-task.sh agentic-cli-v0.1-impl CLI-01
scripts/execute-implementation-task.sh  agentic-cli-v0.1-impl CLI-01
scripts/run-implementation-review-loop.sh agentic-cli-v0.1-impl CLI-01
```

Each slice's per-file plan (CLI-01 … CLI-15) lives alongside this file.
