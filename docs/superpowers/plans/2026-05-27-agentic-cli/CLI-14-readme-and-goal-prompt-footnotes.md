# CLI-14: README + Goal-Prompt Footnotes Implementation Plan

> **For agentic-delivery pipeline:** Implementer = agency-agents Staff+. Reviewer = Claude Code CLI via AIT. Write scope: `agentic/README.md`, `docs/auto-docs-to-implementation-goal-prompt.md`, `docs/hermes-adapter-slices-goal-prompt.md`. **No other files may be modified in this slice.**

**Goal:** Surface the CLI from the public-safe scaffold README; add CLI-equivalent footnotes to the two tracked goal-prompt docs. Preserve every existing `scripts/*.sh` example unchanged.

**Architecture:** Pure documentation slice. The "Quick start" section in `agentic/README.md` lists CLI form first, scripts form second. Goal-prompt files get a single footnote sentence — they remain LLM-readable and the underlying instructions still reference scripts.

**Tech Stack:** Markdown.

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `agentic/README.md` | Modify | Insert "Quick start (CLI)" between intro and "Validate" sections. |
| `docs/auto-docs-to-implementation-goal-prompt.md` | Modify | Append one footnote sentence. |
| `docs/hermes-adapter-slices-goal-prompt.md` | Modify | Append one footnote sentence. **Caveat:** this file is `docs/*goal-prompt.md` and currently gitignored. Implementer must `git add -f` if it has not been tracked yet, or skip this file if the repo policy keeps it private. Check status with `git ls-files docs/hermes-adapter-slices-goal-prompt.md`. |

---

## Task 1: README "Quick start (CLI)" section

**Files:**
- Modify: `agentic/README.md`

- [ ] **Step 1: Identify insertion point**

The current README has its first usage block under `## Validate`. Insert a new `## Quick start (CLI)` section **immediately above** `## Validate`.

- [ ] **Step 2: Insert this block verbatim**

```markdown
## Quick start (CLI)

The `agentic` CLI is a state-aware wrapper over the `scripts/*.sh` pipeline.

Install:

```bash
pipx install agentic-delivery
```

In any clone of this repo:

```bash
agentic init "Your delivery goal"
agentic next                                                # see what to do next
agentic status                                              # inspect current run
agentic plan artifact docs/adr/008-xyz.md approve --reason "..."
```

The CLI shells out to the same scripts documented below; both forms remain valid.
See `cli/README.md` for the full command reference.
```

- [ ] **Step 3: Confirm the existing scripts examples remain intact**

```bash
git diff agentic/README.md | grep -E "^-scripts/" || echo "no scripts removed (good)"
```

Expected output: `no scripts removed (good)`.

- [ ] **Step 4: Privacy scan**

```bash
scripts/privacy-scan-tracked.sh
```

Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add agentic/README.md
git commit -m "docs(agentic): quick start section for the CLI"
```

---

## Task 2: Goal-prompt footnotes

**Files:**
- Modify: `docs/auto-docs-to-implementation-goal-prompt.md`
- Modify: `docs/hermes-adapter-slices-goal-prompt.md` (only if tracked; check first)

- [ ] **Step 1: Append to `docs/auto-docs-to-implementation-goal-prompt.md`**

Add this paragraph at the very end of the file (after any existing content), preceded by a blank line:

```markdown
> **CLI equivalence note:** every `scripts/<x>.sh` reference in this prompt may also be invoked via the `agentic` CLI (see `agentic/README.md` "Quick start (CLI)"). The shell form remains canonical; the CLI is a thin wrapper.
```

- [ ] **Step 2: Check tracking status of the hermes goal-prompt file**

```bash
git ls-files docs/hermes-adapter-slices-goal-prompt.md
```

If the path is printed, proceed to Step 3. If empty, the file is gitignored per `.gitignore` rule `docs/*goal-prompt.md` — **skip** Step 3 (do not `git add -f`; respect existing policy).

- [ ] **Step 3 (conditional): Append the same footnote to `docs/hermes-adapter-slices-goal-prompt.md`**

Same text as Step 1.

- [ ] **Step 4: Privacy scan**

```bash
scripts/privacy-scan-tracked.sh
```

Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add docs/auto-docs-to-implementation-goal-prompt.md
# (and docs/hermes-adapter-slices-goal-prompt.md only if Step 3 applied)
git commit -m "docs: CLI equivalence footnotes in tracked goal prompts"
```

---

## Acceptance Criteria (from spec §13 CLI-14)

- `agentic/README.md` has a "Quick start (CLI)" section above "Validate".
- All previously documented `scripts/*.sh` examples remain intact (no diff lines removed under `scripts/`).
- `docs/auto-docs-to-implementation-goal-prompt.md` ends with the CLI-equivalence footnote.
- `docs/hermes-adapter-slices-goal-prompt.md` has the footnote **iff** it was already tracked.
- `scripts/privacy-scan-tracked.sh` exits 0.
- Diff against base touches only the three documented files.

## Implementer / Reviewer

- **Implementer:** agency-agents Staff+ — `staff-software-engineer` (mostly editorial; could also be a Staff+ tech writer if catalog includes one).
- **Reviewer:** Claude Code CLI via AIT — `engineering-technical-writer`, `product-manager`, `engineering-software-architect` (verify CLI claims are accurate against CLI-01..CLI-12 behaviour).

Evidence under `agentic/reviews/agentic-cli/CLI-14/`.

## Rollback

```bash
git revert <CLI-14 commits>
```
