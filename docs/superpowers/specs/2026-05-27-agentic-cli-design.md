# Agentic CLI Design

- **Status:** Draft (design review pending)
- **Date:** 2026-05-27
- **Owner:** michael.chen
- **Target component:** `cli/` (new top-level package in `agentic-delivery` repo)
- **Target install:** `pipx install agentic-delivery` → `agentic` binary
- **Initial CLI version:** `0.1.0` (semver, independent from repo)

---

## 1. Context & Motivation

`agentic-delivery` exposes its pipeline as 55 `scripts/*.sh` plus a Hermes action runner.

**Lifecycles.** The pipeline supports two implementation lifecycles plus a third research-track lifecycle:

- *Planning + implementation* (default-delivery profile): produces approved planning artifacts and dispatches implementation tasks against them. This is what most CLI commands serve.
- *Boss-idea response* (boss-idea-response profile): a research/feasibility track for triaging executive ideas into market research, competitor briefs, feasibility scoring, decision memos, POC/MVP plans, and explicit go/no-go decisions. It uses the same approval gate but its artifact set differs. The `agentic boss` namespace (§5.4) wraps the 24 scripts that drive it.

**AIT.** Throughout this spec, *AIT* means the Agentic Invocation Toolkit — the local adapter runner (`ait run --adapter <name>`) used to invoke external LLM CLIs (Claude Code, Codex) under isolated-worktree / read-only-sandbox constraints. AIT is what makes adversarial code review reproducible: each invocation produces a trace, an attempt id, and machine-classifiable evidence.

Documented use looks like:

```bash
RUN_ID=<id> scripts/init-agentic-run.sh "goal"
scripts/generate-artifacts.sh <run-id>
scripts/run-artifact-review-loop.sh <run-id> --artifact <path>
scripts/update-artifact-status.sh <run-id> <artifact> approved --reason "..." --actor local-operator --role approver
scripts/init-implementation-run.sh --planning-run <planning-run-id>
...
```

The biggest UX pain is not "there is no CLI" — it is that users must memorise the script catalogue, remember the pipeline order encoded in `agentic/pipeline.yaml`, manage `RUN_ID` themselves, and reconstruct "what is the next step?" by reading `report-run-status.sh` output.

`pipeline.yaml` already declares a state machine. The CLI's job is to surface that state machine to humans through a state-aware wrapper that:

1. Holds run context so commands stop needing `RUN_ID=…`.
2. Reads the manifest and tells the user the next action.
3. Routes every existing script to a discoverable subcommand.
4. Stays a thin wrapper — never replaces `scripts/*.sh` as authoritative.

This spec defines that wrapper.

---

## 2. Goals / Non-goals

### Goals
- Provide an `agentic` CLI that is the primary interface to the delivery pipeline.
- Cover all 55 existing `scripts/*.sh` either via named subcommands or `agentic raw`.
- Surface the pipeline state machine through `agentic status` and `agentic next`.
- Install with `pipx install agentic-delivery`; cross-platform (macOS + Linux).
- Independent semver from the repo; declared compatibility matrix against `pipeline.yaml.version`.
- Zero behavioural change for users who keep calling `scripts/*.sh` directly.

### Non-goals
- Rewrite scripts in Python. Scripts remain single source of truth.
- Replace `agentic/hermes-actions.yaml`. Hermes still routes through `scripts/run-hermes-action.sh`.
- Telemetry, phone-home, automated upgrade checks. Honour the repo's "no egress" stance.
- Hide the underlying scripts. `agentic raw <script>` is a permanent escape hatch.
- Decide authorization. The CLI propagates `AIT_ACTOR` / `AIT_ACTOR_ROLE`; `agentic/identity-policy.yaml` remains the enforcement boundary.

---

## 3. Locked Decisions (from brainstorm Q&A)

| # | Question | Decision |
|---|----------|----------|
| Q1 | Audience | Product's primary interface. Polish, install flow, error UX matter. |
| Q2 | Language / distribution | Python 3.10+, `pipx`/`uvx` install. |
| Q3 | MVP scope | Wrap all 55 scripts at once. |
| Q4 | Run-context priority | **flag > env > file** (revised from original env-first answer to the conventional ordering). |
| Q5 | `agentic next` behaviour | Suggest only; never auto-execute. |
| Q6 | Layout | `cli/` subdirectory inside this repo; `scripts/*.sh` keep single-source-of-truth status. |
| B  | Wrapper thickness | Hybrid — most commands shell-out; `status` / `next` / `doctor` read `manifest.yaml` directly in Python. |
| B  | State engine form | Declarative YAML rule table (`cli/agentic/state_engine/rules.yaml`) with a small condition-primitive set. |

---

## 4. Architecture

### 4.1 Repository layout after CLI lands

```
agentic-delivery/
├── cli/                              ← new top-level package
│   ├── pyproject.toml
│   ├── CHANGELOG.md
│   ├── README.md
│   ├── agentic/
│   │   ├── __init__.py
│   │   ├── app.py                    Typer root + global options
│   │   ├── context.py                run-id resolution + repo discovery
│   │   ├── manifest.py               PyYAML loader for read-only access
│   │   ├── shell.py                  subprocess wrapper; env propagation
│   │   ├── state_engine/
│   │   │   ├── __init__.py
│   │   │   ├── engine.py             rule evaluator
│   │   │   ├── primitives.py         condition primitives (~10 total)
│   │   │   └── rules.yaml            default declarative rule table
│   │   ├── ui/
│   │   │   ├── render.py             Rich tables / panels / fallback layouts
│   │   │   └── errors.py             structured error formatter
│   │   └── commands/
│   │       ├── __init__.py           command discovery + registration
│   │       ├── plan.py
│   │       ├── impl.py
│   │       ├── boss.py
│   │       ├── hermes.py
│   │       ├── identity.py
│   │       ├── evidence.py
│   │       ├── manifest_cmd.py       (manifest is reserved name)
│   │       ├── run.py                run list/use/show/clear
│   │       └── raw.py                escape hatch
│   └── tests/
│       ├── state_engine/
│       │   ├── fixtures/
│       │   └── test_engine.py
│       ├── shell_fixtures/
│       ├── test_context.py
│       ├── test_compat.py
│       ├── test_commands_plan.py
│       ├── test_commands_impl.py
│       ├── test_commands_boss.py
│       ├── snapshots/                pytest-snapshot for help / --json
│       ├── conftest.py
│       └── smoke/
│           └── test_e2e.sh
│
├── scripts/                          ← unchanged; still authoritative
├── agentic/                          ← unchanged
├── docs/                             ← unchanged (this spec lives here)
└── .github/workflows/cli.yml         ← new CI workflow
```

### 4.2 Core contracts

- CLI **never writes** to `agentic/runs/<id>/manifest.yaml` directly. All writes go through `scripts/update-*.sh`, preserving `identity-policy.yaml` enforcement.
- CLI **reads** `manifest.yaml` directly only for `status` / `next` / `doctor` / `run list`. Reads use a read-only `Manifest` dataclass; mutation goes nowhere.
- CLI falls back to printing the underlying `scripts/<name>.sh` command line whenever something fails — users always have a recovery path.
- Python ≥ 3.10. Runtime dependencies kept minimal: `typer`, `rich`, `pyyaml`. No optional heavy deps in v1.

#### 4.2.1 Read-only enforcement gate (machine-checkable)

The "CLI never writes manifests" rule is enforced by a unit test, not by naming convention:

1. **AST scan test** (`cli/tests/test_no_manifest_writes.py`) parses every module under `cli/agentic/` with `ast` and asserts that no `open(...)` call with mode `'w'` / `'a'` / `'x'` / `'wb'` / `'r+'` / `'w+'` targets a path matching `*manifest*.yaml`, and that no `yaml.dump` / `yaml.safe_dump` / `Path.write_text` / `Path.write_bytes` call sites take a manifest path as their target. The test fails the build on any new write path that bypasses `scripts/update-*.sh`.
2. **`Manifest` dataclass is `frozen=True`**; tests assert that attempting `manifest.artifacts.append(...)` or `dataclasses.replace()` on tuples raises.
3. **CI ruff rule**: `pyproject.toml` `[tool.ruff.lint.per-file-ignores]` does not silence ruff's `T201`/`T100`/etc. on the `manifest.py` module, and a custom ruff plugin (or alternatively a grep gate in CI) refuses commits that introduce `yaml.dump` inside `cli/agentic/`.

The same gate stands behind the §7.7 and §11.2 invariants — without it, the three red lines are aspirational. CLI-04 lands the test fixture; CLI-13 wires it into CI.

---

## 5. Command Tree (covers all 55 scripts)

### 5.1 Hot-path top-level

```
agentic init "goal" [--goal-file <f>] [--profile <id>]   → scripts/init-agentic-run.sh
agentic status [--run-id <id>]                            → read manifest.yaml
agentic next   [--run-id <id>]                            → read manifest + state_engine
agentic doctor                                            → batch validators
agentic version                                           → CLI/python/repo/pipeline/git info
agentic run    list | use <id> | show | clear             → manage .agentic/current-run
agentic raw    <script.sh> [args...]                      → escape hatch into scripts/
```

### 5.2 `plan` — planning phase
```
agentic plan generate                                     → generate-artifacts.sh
agentic plan generate-agent  --dry-run | --execute        → run-artifact-generation-agent.sh
agentic plan review          --artifact <path>            → run-artifact-review-loop.sh
agentic plan revisions                                    → create-artifact-revision-tasks.sh
agentic plan agency review                                → run-agency-review.sh
agentic plan agency summarize                             → summarize-agency-review.sh
agentic plan strategy-gate                                → strategy-gate-check.sh
agentic plan state <state>                                → update-run-state.sh
agentic plan artifact <path> approve|reject|defer|reviewed|drafted|changes_requested
                              --reason "..." [--actor ...] → update-artifact-status.sh
```

### 5.3 `impl` — implementation phase
```
agentic impl init     --from <planning-run-id>            → init-implementation-run.sh
agentic impl tasks    [--dry-run]                         → generate-implementation-task-graph.sh
agentic impl dispatch <task-id> [--dry-run] [--actor ...] → dispatch-implementation-task.sh
agentic impl execute  <task-id> [--dry-run] [--actor ...] → execute-implementation-task.sh
agentic impl review   <task-id> [--actor ...]             → run-implementation-review-loop.sh
agentic impl validate                                     → validate-implementation-run.sh
```

### 5.4 `boss` — boss-idea response profile (24 scripts)
```
agentic boss init <idea-file>                             → init-boss-idea-run.sh
agentic boss research collect [--search-results] [--output]   → collect-boss-idea-research.sh
agentic boss research crawl   [--from-query-pack] [--search-provider]  → crawl-boss-idea-market.sh
agentic boss research brief                                   → generate-boss-idea-competitor-brief.sh
agentic boss research preflight                               → boss-idea-searxng-preflight.sh
agentic boss research live-smoke --live --force               → run-boss-idea-live-smoke.sh
agentic boss score [--dry-run]                                → score-boss-idea-feasibility.sh
agentic boss memo generate                                    → generate-boss-decision-memo.sh
agentic boss poc plan                                         → plan-boss-idea-poc-mvp.sh
agentic boss decision record <yaml>                           → record-boss-idea-decision.sh
agentic boss provider health   [--output]                     → summarize-boss-idea-provider-health.sh
agentic boss provider fallback [--output]                     → recommend-boss-idea-provider-fallback.sh
agentic boss validate research        <md>                    → validate-boss-idea-research.sh
agentic boss validate competitor      <md>                    → validate-boss-idea-competitor-brief.sh
agentic boss validate run-competitor  <run> <md>              → validate-boss-idea-run-competitor-brief.sh
agentic boss validate crawl           <log>                   → validate-boss-idea-crawl-log.sh
agentic boss validate quality         <yaml>                  → validate-boss-idea-market-discovery-quality.sh
agentic boss validate poc-mvp         <md>                    → validate-boss-idea-poc-mvp.sh
agentic boss validate metrics         <yaml>                  → validate-boss-idea-success-metrics.sh
agentic boss validate memo            <md>                    → validate-boss-decision-memo.sh
agentic boss validate decision        <yaml>                  → validate-boss-idea-decision.sh
agentic boss validate provider-health <yaml>                  → validate-boss-idea-provider-health.sh
agentic boss validate provider-events <yaml>                  → validate-boss-idea-provider-health-events.sh
agentic boss validate fallback-advisory <yaml>                → validate-boss-idea-provider-fallback-advisory.sh
```

### 5.5 `hermes`, `identity`, `evidence`, `fixtures`, `manifest`, `validate`
```
agentic hermes actions [list|validate]                    → validate-hermes-actions.sh
agentic hermes run <action> [k=v ...]                     → run-hermes-action.sh
agentic hermes memory-sync   [--dry-run]                  → hermes-memory-sync.sh
agentic hermes scheduler     [--dry-run]                  → hermes-scheduler-dry-run.sh
agentic hermes gateway       [--dry-run]                  → hermes-gateway-dry-run.sh

agentic identity validate                                 → validate-identity-policy.sh
agentic identity authorize --action <action>              → authorize-agentic-action.sh

agentic evidence record                                   → record-validation-evidence.sh
agentic evidence redact                                   → redact-local-evidence.sh
agentic fixtures run                                      → run-golden-fixtures.sh

agentic manifest validate [--all] [<run-id>]              → validate-manifest-schema.sh
agentic manifest templates <run-id>                       → validate-artifact-templates.sh
agentic manifest scan                                     → privacy-scan-tracked.sh

agentic validate system                                   → validate-agentic-system.sh
```

### 5.6 Coverage check

All 55 scripts mapped:
- 1 script (`update-artifact-status.sh`) is special-cased and reached via **6 sugar verbs** under `plan artifact … <verb>`: `approve|reject|defer|reviewed|drafted|changes_requested`. The literal canonical statuses are `drafted | reviewed | changes_requested | approved | rejected | deferred`; the verbs `approve / reject / defer` are CLI-side syntactic sugar that map to the past-tense canonical status before invoking the script.
- **12 validators are collapsed under `boss validate <kind>`**: 11 `validate-boss-idea-*.sh` plus `validate-boss-decision-memo.sh` (which lacks the `-idea` infix in its filename but belongs to the same boss-idea lifecycle).
- `report-run-status.sh` is consumed by `agentic status` (not exposed as a separate named command — `status` reads `manifest.yaml` directly and uses the report logic as a reference for what counts as "next action").
- 1 top-level command (`agentic init "goal"` per §5.1) routes to `scripts/init-agentic-run.sh`.
- 53 named subcommands across the namespaces + the 1 sugar group + `agentic raw` cover the remaining 53 scripts and any future additions.

A canonical 1-row-per-`.sh` mapping table lives next to the code at `cli/agentic/commands/_coverage.py` (one Python literal dict) and is asserted by `cli/tests/test_script_coverage.py` against `ls scripts/*.sh`. If a script is added under `scripts/` without an entry, the test fails until a wrapper or an `agentic raw` route is documented.

### 5.7 Design rules
- Verbs at the first sublevel (`init`, `dispatch`, `validate`) for ergonomic tab completion.
- `plan` / `impl` / `boss` are mutually exclusive lifecycle namespaces.
- All validators collapse under either `boss validate` or `manifest validate` to keep top-level shallow.
- `agentic raw` is **always available** so missing wrapper coverage never blocks a user.

---

## 6. State Engine (declarative)

### 6.1 Rule file locations

- Default ships with the package: `cli/agentic/state_engine/rules.yaml`.
- User override: `$XDG_CONFIG_HOME/agentic/state_rules.yaml` (merged on top; same `id` overrides).

### 6.2 DSL shape

```yaml
schema_version: v1

rules:
  - id: blocked-state
    priority: 0
    when:
      - state_matches: "blocked_*"
    suggest: "agentic doctor"
    reason: "Run is blocked ({state}). Resolve before continuing."

  - id: planning-need-drafts
    priority: 100
    applies_to: planning
    when:
      - has_artifact_with_status: planned
      - not_has_artifact_with_status: drafted
    suggest: "agentic plan generate"
    reason: |
      {count_planned} artifact(s) still 'planned':
      {list_planned_paths}

  - id: planning-need-review
    priority: 200
    applies_to: planning
    when:
      - has_artifact_with_status: drafted
    suggest: "agentic plan review --artifact {first_drafted.path}"
    reason: "Draft awaiting review: {first_drafted.path}"

  - id: planning-need-approval
    priority: 300
    applies_to: planning
    when:
      - has_artifact_with_status: reviewed
    suggest: 'agentic plan artifact {first_reviewed.path} approve --reason "..."'
    reason: "Reviewed artifact ready for approval: {first_reviewed.path}"

  - id: planning-changes-requested
    priority: 400
    applies_to: planning
    when:
      - has_artifact_with_status: changes_requested
    suggest: "agentic plan revisions"
    reason: "Artifact returned with changes_requested: {first_changes_requested.path}"

  - id: planning-ready-for-impl
    priority: 500
    applies_to: planning
    when:
      - all_artifacts_terminal: true
      - count_artifacts_with_status: { status: approved, min: 1 }
    suggest: "agentic impl init --from {run_id}"
    reason: "All artifacts settled, {count_approved} approved — ready for implementation."

  - id: impl-need-task-graph
    priority: 600
    applies_to: implementation
    when:
      - task_graph_exists: false
    suggest: "agentic impl tasks"
    reason: "Implementation run has no task graph yet."

  - id: impl-dispatch
    priority: 700
    applies_to: implementation
    when:
      - has_task_with_status: pending
    suggest: "agentic impl dispatch {first_pending_task.id}"
    reason: "Pending task ready for dispatch: {first_pending_task.id}"

  - id: impl-execute
    priority: 800
    applies_to: implementation
    when:
      - has_task_with_status: dispatched
    suggest: "agentic impl execute {first_dispatched_task.id}"
    reason: "Dispatched task awaiting execution: {first_dispatched_task.id}"

  - id: impl-review
    priority: 900
    applies_to: implementation
    when:
      - has_task_with_status: executed
    suggest: "agentic impl review {first_executed_task.id}"
    reason: "Executed task awaiting code review: {first_executed_task.id}"

  - id: impl-validate
    priority: 1000
    applies_to: implementation
    when:
      - all_tasks_reviewed: true
    suggest: "agentic impl validate"
    reason: "All tasks reviewed — run final validation."

  - id: boss-need-research
    priority: 1100
    applies_to: boss-idea
    when:
      - not_has_artifact_at: market-research.md
    suggest: 'agentic boss research collect --search-results <yaml> --output market-research.md'
    reason: "Market research evidence missing."

  - id: boss-need-brief
    priority: 1200
    applies_to: boss-idea
    when:
      - has_artifact_at: market-research.md
      - not_has_artifact_at: competitor-brief.md
    suggest: "agentic boss research brief"
    reason: "Competitor brief not yet generated."

  # Additional boss-idea rules (score, memo, poc, decision) follow the same pattern.
  # See cli/agentic/state_engine/rules.yaml for full table.

  - id: fallback
    priority: 9999
    when: []
    suggest: "agentic status"
    reason: "No rule matched. Inspect run state manually."
```

### 6.3 Condition primitives (closed set)

| Primitive | Meaning |
|-----------|---------|
| `state_matches: <glob>` | `fnmatch(manifest.state, glob)` |
| `mode_is: <mode>` | equality |
| `has_artifact_with_status: <s>` | count ≥ 1 |
| `not_has_artifact_with_status: <s>` | count == 0 |
| `count_artifacts_with_status: {status, min?, max?}` | range |
| `all_artifacts_terminal: true` | all in {approved, rejected, deferred} |
| `has_task_with_status: <s>` | impl runs |
| `task_graph_exists: bool` | |
| `all_tasks_reviewed: bool` | impl runs |
| `has_artifact_at: <relpath>` | boss-idea file existence |
| `not_has_artifact_at: <relpath>` | |

Adding a new primitive: register in `cli/agentic/state_engine/primitives.py` and add a unit test.

### 6.4 Template variables

Templates render against a **flat, whitelisted dict of pre-built scalar/string values** — never against arbitrary Python objects. Allowed identifiers (no `.`, no `[`, no attribute walks):

- `{run_id}`, `{state}`, `{mode}`
- `{count_planned}`, `{count_drafted}`, `{count_approved}`, `{count_reviewed}`, `{count_rejected}`, `{count_deferred}`, `{count_changes_requested}`
- `{first_drafted_path}`, `{first_reviewed_path}`, `{first_changes_requested_path}` (string paths, **not** dotted attribute access)
- `{first_pending_task_id}`, `{first_dispatched_task_id}`, `{first_executed_task_id}`
- `{list_planned_paths}` (newline-joined bullet list)

#### 6.4.1 Restricted rendering (no `str.format` on raw objects)

`str.format()` is **not** used directly. Instead, `cli/agentic/state_engine/render.py::render(template, ctx)`:

1. Validates the template by regex-scanning for `{<identifier>}` patterns where `<identifier>` matches `^[a-z_][a-z0-9_]*$`. Any template containing `.`, `[`, `]`, `:`, `!`, `__`, or whitespace inside the braces is rejected and the rule falls back to its literal `reason` string.
2. Validates that every referenced identifier exists in the allowed key set above. Unknown keys cause the rule to be skipped (with structured warning) — never to crash or to expose object internals.
3. Renders by simple substitution against the flat ctx dict, with no Python expression evaluation.

This closes the `str.format` attack surface — a hostile `$XDG_CONFIG_HOME/agentic/state_rules.yaml` override cannot reach `{x.__class__.__init__.__globals__[...]}` or any other Python-object walk. Security tests (`cli/tests/state_engine/test_render_sandbox.py`) prove that `"{x.__class__}"`, `"{x[0]}"`, `"{x!r}"`, and `"{x:0}"` all fail to render and are logged as rejected.

Missing template variable → CLI logs a structured warning and falls back to the rule's literal template (no crash, no leak).

### 6.5 Invariants
- Engine is read-only against the manifest.
- A `fallback` rule (`when: []`, `priority: 9999`) must exist; CI fails the package if absent.
- New rules require a fixture in `cli/tests/state_engine/fixtures/`.

---

## 7. Run-Context Resolution

### 7.1 Resolution order (revised to conventional flag > env > file)

```
1. --run-id <id>                  per-command flag (immediate)
2. $AIT_RUN_ID                    shell session ambient
3. .agentic/current-run           repo-local persistent file
4. error: "no run context"        with hints
```

#### 7.1.1 Run-id validation (mandatory, applied to every source)

Every resolved run id — regardless of source — is matched against:

```
^[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}$
```

Sources that fail (multi-line `.agentic/current-run`, leading whitespace, NUL, newline, command-substitution metacharacters, path-traversal segments, env values containing `$(...)` / `\`...\`` / `;` / `&&`) are **rejected with exit 6** before any filesystem path join or subprocess invocation. The `.agentic/current-run` file rule from §7.5 ("warn on multi-line") is tightened: multi-line files now refuse the value entirely instead of warning-and-using.

Tests in `cli/tests/test_run_id_validation.py` cover `../../etc`, `$(rm -rf .)`, leading dash, embedded newline, NUL byte, empty string, 200-char string, and Unicode-confusable lookalikes. CLI-03 lands this regex; CLI-13 keeps it gated by snapshot diff.

### 7.2 File format

```
# .agentic/current-run  — plain text, single line, no YAML
agentic-h27-cli-design
```

`.agentic/` directory is git-ignored (added to top-level `.gitignore` as part of CLI rollout).

### 7.3 Source disclosure

- Verbose (`-v`) prepends `[run] <id>  (source: <source>)` to every command that resolves a run.
- `agentic run show` always prints the source — no `-v` required.
- `--json` mode includes `"source"` in run context.

### 7.4 Run-management commands

| Command | Behaviour |
|---------|-----------|
| `agentic run list` | Enumerate `agentic/runs/*/manifest.yaml`; columns: id, mode, state, updated_at; mark current with `*`. |
| `agentic run use <id>` | Write `.agentic/current-run`. Refuse if `agentic/runs/<id>` does not exist. |
| `agentic run show` | Print resolved id + source. |
| `agentic run clear` | Remove `.agentic/current-run`. |

### 7.5 Edge cases

| Condition | Behaviour |
|-----------|-----------|
| All three sources empty | Exit 6 with hint `agentic run use <id>` or `agentic run list`. |
| `current-run` references missing run dir | Exit 6 with hint `agentic run clear && agentic run use <valid>`. |
| `--run-id` references missing run | Exit 6 with hint `agentic run list`. |
| flag and env both set | Flag wins; no warning (flag is the explicit override). |
| File empty or whitespace | Treat as unset, fall through to next source. |
| File has multiple lines | Use first non-empty trimmed line; warn. |

### 7.6 Subprocess propagation

When CLI shells out, resolved id is set into the child's `RUN_ID` env var so existing `scripts/*.sh` need zero changes.

### 7.7 Invariants
- Never silently swallow an unknown run id.
- `-v` always reveals the source.
- CLI never writes to the manifest as a side effect of resolution.

---

## 8. Packaging & Install

### 8.1 `cli/pyproject.toml`

```toml
[project]
name = "agentic-delivery"
version = "0.1.0"
description = "Agentic Delivery CLI — wrapper over the scripts/* pipeline"
requires-python = ">=3.10"
license = { text = "Apache-2.0" }
authors = [{ name = "Michael Chen" }]
dependencies = [
  "typer >= 0.12",
  "rich  >= 13",
  "pyyaml >= 6",
]

[project.scripts]
agentic = "agentic.app:main"

[project.optional-dependencies]
dev = ["pytest >= 8", "pytest-snapshot", "ruff", "mypy"]

[tool.agentic]
compatible_pipeline_versions = [">=0.6,<0.7"]
```

PyPI package name is `agentic-delivery` because `agentic` is already taken on PyPI. Binary name is `agentic`.

### 8.2 Install paths

```bash
# End users
pipx install agentic-delivery
# or
uvx agentic-delivery

# Developers, inside the repo
pip install -e cli/
# or
uvx --from ./cli agentic status
```

### 8.3 Repo discovery

```
1. --repo <path>                   global flag (immediate)
2. $AGENTIC_HOME                   shell env
3. walk up from cwd                find a directory containing agentic/pipeline.yaml
4. ~/.config/agentic/config.toml   key: repo_path
5. error: "no agentic-delivery repo found"
```

Walk-up is bounded at the filesystem root; symlink loops are not followed.

### 8.4 Compatibility check

On every CLI invocation that resolves a repo, read `<repo>/agentic/pipeline.yaml`'s `version`, compare against `tool.agentic.compatible_pipeline_versions`, and additionally read the optional `<repo>/agentic/runs/<id>/manifest.yaml::manifest_schema_version` field where applicable.

| Result | Behaviour |
|--------|-----------|
| Compatible | Silent. |
| Patch mismatch | Warn on stderr, continue. |
| **Minor mismatch** | **Warn on stderr, continue with best-effort read.** The CLI's `Manifest` reader is schema-aware (§4.2) and tolerates additive minor-version changes. |
| Major mismatch | Hard fail with exit 5 and upgrade hint. `--no-compat-check` overrides. |

The strict-on-minor behaviour from the v0.1 draft was rejected because §11.4 explicitly requires CLI 0.2.x to read both `v0.6` and `v0.7`. Minor bumps are warn-and-continue; the supporting machinery is:

1. `Manifest.from_dict()` uses `manifest_schema_version` (default `1` for legacy manifests without the field) and the per-version field readers in `cli/agentic/manifest_schema/v1.py`, `v2.py`, etc.
2. Adding a new minor version requires landing both (a) a new schema reader and (b) golden fixture(s) under `cli/tests/manifest_schema/fixtures/`. CI test `test_schema_compatibility.py` asserts every declared `compatible_pipeline_versions` range has a matching reader.
3. The schema-version field is also persisted in artifacts the CLI produces (e.g., `cli/.coveragerc`-style markers), so downstream tools can verify what was assumed.

### 8.5 `agentic version` output

```
agentic-delivery CLI  0.1.0
  python:        3.12.2
  install:       /Users/michael.chen/.local/bin/agentic  (pipx)
  repo:          /Users/michael.chen/products/agentic-delivery
  repo source:   walk-up from cwd
  pipeline:      v0.6  (compatible: >=0.6,<0.7 ✓)
  git:           f2440e4 main
```

### 8.6 Release flow
- `cd cli && hatch version <part>` (or equivalent).
- Tag `cli-v0.1.1`.
- GitHub Actions workflow publishes to PyPI on the tag.
- Build artefacts (wheel + sdist) attached to the tag's GitHub Release.

### 8.7 Distribution channels (priority)
1. **PyPI** — primary, from v0.1.
2. **GitHub Release** — auto-attached on tag.
3. **Homebrew tap** — evaluated at v0.5+.
4. **PEX / shiv single-file** — evaluated at v1.0+ for air-gapped environments.

No `curl … | sh` installer. No telemetry. No upgrade nag.

---

## 9. Error & Help UX

### 9.1 Help structure

- `agentic` with no args prints a curated quick-reference (hot-path + namespaces + 3 examples).
- `agentic <namespace> --help` shows subcommands plus `Examples:` section (mandatory, not optional).
- Every leaf command's `--help` ends with `See also:` cross-references to logically related commands.

### 9.2 Error format

Every error includes **what / why / what-to-do-next**:

```
✗ no run context

  No run is set as current, and no --run-id / $AIT_RUN_ID was provided.

  Set a current run:
    agentic run list
    agentic run use <run-id>

  Or pass --run-id one-off:
    agentic --run-id <id> status
```

```
✗ authorization denied

  Action 'artifact.approve' is not authorized for:
    actor: local-operator
    role:  operator        ← needs role 'approver'

  Policy: agentic/identity-policy.yaml

  Retry:
    agentic --actor local-operator --role approver \
            plan artifact <path> approve --reason "..."
```

```
✗ underlying script failed (exit 3)

  scripts/update-artifact-status.sh exited 3 (validation).
  Output captured: agentic/runs/<id>/logs/update-artifact-status-<ts>.log

  Likely cause: status transition not permitted.

  Retry path:
    agentic plan artifact <path> reviewed --reason "..."
    agentic plan artifact <path> approve  --reason "..."
```

### 9.3 Exit codes

| Code | Meaning |
|------|---------|
| 0 | success |
| 1 | generic error |
| 2 | misuse (bad args / unknown command — typer default) |
| 3 | validation failure |
| 4 | authorization denied |
| 5 | compat check failed |
| 6 | no run context / no repo found |
| 64–79 | forwarded script exit codes (sysexits.h style) |

### 9.4 Global flags

| Flag | Env / config | Behaviour |
|------|--------------|-----------|
| `--run-id <id>` | `AIT_RUN_ID` | Set run context. |
| `--repo <path>` | `AGENTIC_HOME` | Specify repo. |
| `--actor <a>` | `AIT_ACTOR` | Propagate actor to scripts. |
| `--role <r>` | `AIT_ACTOR_ROLE` | Propagate role to scripts. |
| `--json` | `AGENTIC_JSON=1` | Structured output to stdout, structured errors to stderr. |
| `-q / --quiet` | | Errors only. |
| `-v / --verbose` | `AGENTIC_VERBOSE=1` | Show resolution sources and high-level traces. |
| `-vv / --debug` | `AGENTIC_DEBUG=1` | Show full subprocess argv + stream child stderr through. |
| `--no-color` | `NO_COLOR=1` | Disable ANSI. |
| `--no-compat-check` | | Skip pipeline version check. |
| `--dry-run` | | Forward to supporting underlying scripts. |

### 9.5 `--json` mode

```json
{
  "_schema": "agentic.cli/v1",
  "run": {
    "id": "agentic-h27-cli-design",
    "mode": "planning",
    "profile": "default-delivery",
    "state": "artifact_plan_created",
    "updated_at": "2026-05-27T14:30:00Z",
    "source": "file:.agentic/current-run"
  },
  "artifacts": { "total": 3, "approved": 0, "pending": 3, "rejected": 0, "deferred": 0 },
  "next": {
    "rule_id": "planning-need-drafts",
    "suggest": "agentic plan generate",
    "reason": "3 artifacts still 'planned'"
  }
}
```

Schema versioned via `_schema` field. v1 may add fields; renames or deletions require a CLI major bump.

#### 9.5.1 Machine-checkable schema gate

`pytest-snapshot` strict mode alone is insufficient — a PR that renames a field can also rebaseline the snapshot in the same commit. The locked envelope lives at `cli/agentic/schemas/cli_v1.schema.json` (JSON Schema draft 2020-12). CI enforces:

1. **Produced JSON validates against the schema.** `cli/tests/test_json_schema_conformance.py` runs every command's `--json` output through `jsonschema.validate(..., schema=v1)`. Failure means the code drifted from the schema.
2. **Schema file diff-stability.** The CI job `cli-schema-stability` runs `git diff origin/main -- cli/agentic/schemas/cli_v1.schema.json` and fails the PR if any non-additive change appears (any property removed, renamed, or having `type`/`enum` narrowed) unless the same PR also bumps the CLI major version in `cli/pyproject.toml` or introduces `cli_v2.schema.json`.
3. **State-rule fixture coverage.** A parallel CI job diff-asserts that every rule id in `cli/agentic/state_engine/rules.yaml` has a matching fixture under `cli/tests/state_engine/fixtures/`.

Without these three gates the §10.8 invariants are aspirational. CLI-11 ships `cli_v1.schema.json` and the conformance test; CLI-13 wires the stability gate into CI.

### 9.6 Accessibility
- Colour is never the only signal — glyphs (`✗ ▲ ✓`) and explicit labels always present.
- Honour `NO_COLOR` (https://no-color.org/).
- Rich tables degrade to vertical layout when terminal width < 80.
- ASCII-only glyphs (no emoji).

### 9.7 Tab completion
- Typer/click built-in via `agentic --install-completion`.
- `agentic doctor` detects missing completion and offers to install.

### 9.8 Invariants
- Every error includes a next-step command.
- TTY vs pipe auto-detected; piped output is colourless by default.
- `--json` schema is stable within v1.x.
- Underlying script stderr is preserved in verbose modes; the wrapper never hides root-cause hints.

---

## 10. Testing Strategy

### 10.1 Coverage targets

| Module | Target | Notes |
|--------|--------|-------|
| `state_engine/` | ≥ 95 % | Every rule: one positive + one negative fixture. |
| `context.py` | ≥ 90 % | Three-source priority; missing / invalid runs. |
| `manifest.py` | ≥ 90 % | Missing fields, legacy schema, broken YAML. |
| `shell.py` | ≥ 80 % | Env propagation, exit-code mapping, log path. |
| `commands/*` | ≥ 70 % | Each leaf: happy path + one error. |
| `ui/render.py` | snapshot | Wide / narrow terminal fallback. |

### 10.2 State engine tests

Fixtures cover every rule plus the fallback case:

```
cli/tests/state_engine/fixtures/
├── planning_fresh_init.yaml              → planning-need-drafts
├── planning_mixed_drafts.yaml            → planning-need-review
├── planning_one_reviewed.yaml            → planning-need-approval
├── planning_changes_requested.yaml       → planning-changes-requested
├── planning_all_terminal_approved.yaml   → planning-ready-for-impl
├── planning_all_terminal_rejected.yaml   → fallback
├── impl_no_task_graph.yaml               → impl-need-task-graph
├── impl_pending_task.yaml                → impl-dispatch
├── impl_dispatched_task.yaml             → impl-execute
├── impl_executed_task.yaml               → impl-review
├── impl_all_reviewed.yaml                → impl-validate
├── boss_no_research.yaml                 → boss-need-research
├── boss_research_no_brief.yaml           → boss-need-brief
├── blocked_strategy_conflict.yaml        → blocked-state
└── terminal_unknown.yaml                 → fallback
```

`pytest.parametrize` walks every fixture and asserts both `rule.id` and the rendered suggest template.

### 10.3 Integration tests

Use Typer's `CliRunner` against a `tmp_repo` fixture (a minimal `agentic/` skeleton in `tmp_path`). Subprocess calls are replaced with a `RecordingRunner` that captures argv + env. Real script invocations are reserved for the smoke layer.

### 10.4 Snapshot tests (`pytest-snapshot`)

- All `--help` text per namespace.
- `agentic --json status` (one snapshot per mode: planning / implementation / boss-idea).
- `agentic next` output across 3 representative manifests.

Snapshot strict mode: field additions update fixtures; renames and deletions fail until acknowledged.

### 10.5 E2E smoke

`cli/tests/smoke/test_e2e.sh` runs against a fresh checkout of the public repo with the CLI installed editable. Steps:

```
agentic doctor
RUN_ID=smoke agentic init "smoke test goal" --goal-file <fixture>
agentic status
agentic --json status | jq -e '.run.id == "smoke"'
agentic next
agentic raw validate-agentic-system.sh
```

Runs only on Ubuntu/Python 3.12 in CI as the final gate.

### 10.6 CI

```
.github/workflows/cli.yml
matrix: { os: [ubuntu-latest, macos-latest], python: ["3.10","3.11","3.12","3.13"] }
jobs:
  - ruff check
  - mypy --strict cli/agentic
  - pytest cli/tests --cov=agentic --cov-fail-under=85
  - cli/tests/smoke/test_e2e.sh  (ubuntu + 3.12 only)
```

PR-triggered. Coverage drop below 85 blocks merge.

### 10.7 Out of scope
- Re-testing `scripts/*.sh` themselves — they remain covered by `scripts/run-golden-fixtures.sh`.
- Colourised output snapshots (terminal-dependent).
- PyPI publish flow (manually smoke-tested per release).

### 10.8 Invariants
- New rule in `state_rules.yaml` requires a same-PR fixture and parametrised assertion.
- `--json` schema additions must update snapshot tests; renames/deletions require a major CLI version bump.
- Subprocess in unit tests is always mocked; anything that genuinely needs subprocess belongs in integration/e2e.

---

## 11. Migration & Coexistence

### 11.1 Repo changes when CLI lands

| Target | Change |
|--------|--------|
| `scripts/*.sh` | No change. |
| `agentic/pipeline.yaml` / profiles / identity-policy | No change. |
| `.gitignore` | Add `.agentic/`. |
| `agentic/README.md` | Add a "Quick start (CLI)" section; preserve all existing `scripts/*.sh` examples. |
| `cli/` | New directory, independent versioning. |
| `.github/workflows/cli.yml` | New CI workflow. |
| `docs/auto-docs-to-implementation-goal-prompt.md` | Add one footnote: "All `scripts/<x>.sh` references may also be invoked via `agentic <cmd>`." |
| `docs/hermes-adapter-slices-goal-prompt.md` | Same footnote. |

### 11.2 Three red lines
1. `scripts/*.sh` remain the single source of truth. CLI is a router.
2. Existing automation that calls `scripts/*.sh` directly must keep working unchanged.
3. CLI never silently mutates schema (`manifest.yaml`, `pipeline.yaml`). All writes go through scripts.

### 11.3 Rollout phases

| Phase | CLI version | Repo changes |
|-------|-------------|--------------|
| 0 | 0.1 (experimental) | `cli/` lands; README adds a single line "Optional: agentic CLI (see cli/)". CI runs CLI tests but does not block merges. |
| 1 | 0.5 (feature complete) | All 55 scripts wrapped; e2e smoke green. README adds a "Quick start (CLI)" section that lists the CLI form first. CI blocks merge on CLI tests. |
| 2 | 1.0 (stable) | PyPI release. Main README leads with CLI; scripts written up as "Advanced / scripting". Command tree frozen — renames go through deprecation cycle. |
| 3 | future | Possible Homebrew tap; possible Hermes adapter integration. |

### 11.4 Compatibility matrix (illustrative)

| CLI | Compatible `pipeline.yaml.version` | Notes |
|-----|------------------------------------|-------|
| 0.1.x | v0.6 | initial |
| 0.2.x | v0.6 – v0.7 | new state added; no manifest schema change |
| 0.3.x | v0.7 | new artifact status |
| 1.0.x | v0.7 – v1.0 | stable |

Schema changes affecting manifest fields require a CLI minor that reads both old and new before the major that removes old reads.

### 11.5 `agentic raw` scope lock

```python
raw(name) → run(realpath(repo/"scripts"/name), *args_after_dashdash)
```

Hardened validation (all four checks must pass before exec):

1. **Name regex**: `name` must match `^[a-z0-9][a-z0-9-]*\.sh$` — *leading dash forbidden* to prevent argv parsing confusion in downstream subprocess shells.
2. **Realpath containment**: `os.path.realpath(scripts/name)` must be a regular file whose `os.path.commonpath([realpath, scripts_realpath])` equals `scripts_realpath`. Symlinks that escape `<repo>/scripts/` (out-of-repo, parent traversal, dangling) are refused. Symlinks where the resolved file is itself a symlink are refused.
3. **Argument delimiter**: arguments after `<name>` are only forwarded if the user supplied them after a literal `--` token (e.g., `agentic raw foo.sh -- --verbose --flag value`). Typer's context passthrough enforces this; without `--`, args are parsed by Typer and rejected as unknown flags. Documented in `--help` and CLI-10 acceptance tests.
4. **TOCTOU closure**: the realpath computed at validation time is the exact path passed to `subprocess.run([...])`; the original constructed path is not re-resolved before exec.

Tests in `cli/tests/test_commands_raw.py` cover: leading-dash name (`-rf.sh`), absolute path, `..` traversal, symlink to `/etc/passwd`, symlink loop, symlink to outside-repo file, missing file, non-`.sh` extension, the `--` boundary requirement, and that `subprocess.run` receives the realpath-resolved string.

### 11.6 Deprecation policy (post v1.0)

| Change | Process |
|--------|---------|
| CLI command rename | Old name remains for 2 minor versions; stderr warning; docs marked deprecated. |
| CLI flag rename | Same. |
| `--json` field added | No deprecation needed. |
| `--json` field renamed / removed | Major bump; old field deprecated one major prior. |
| Script added | Next CLI minor adds command; `agentic raw <name>` works in the meantime. |
| Script removed | CLI removes command in the same release; deprecation cycle applies. |
| pipeline.yaml minor bump | Extend compat matrix; fixtures cover both versions. |
| pipeline.yaml major bump | CLI major bump. |

### 11.7 Risks

| Risk | Mitigation |
|------|------------|
| CLI / scripts drift | `agentic raw` escape hatch; compat check; e2e smoke runs against real scripts. |
| Manifest schema changes blindside CLI | State-engine fixtures span multiple schema versions; CI runs compat tests on pipeline bumps. |
| Users mistake CLI for source of truth | `agentic version`, `--help`, README all explicitly label "wrapper". |
| `--json` schema drift | `_schema` field + snapshot strict mode + version policy. |
| New script merged without CLI command | `agentic raw <name>` works immediately; next CLI release adds named command. |
| Hermes flows bypass CLI | Intentional — Hermes runs `scripts/run-hermes-action.sh` directly. |

### 11.8 What we explicitly do not do
- Do not rewrite scripts in Python.
- Do not add business logic to the CLI — only wrappers, routing, and read-only state introspection.
- Do not change Hermes routing — Hermes keeps calling scripts directly through Phase 2.
- Do not add telemetry, opt-in upgrade checks, or any phone-home behaviour.
- Do not ship Homebrew or single-file binaries before v1.0.

### 11.9 Invariants
- `scripts/` remains the bottom-truth layer. CLI dying / PyPI outage does not break the pipeline.
- The CLI's existence does not change any existing automation behaviour.
- The three red lines (§11.2) hold from v0.1 through v1.0. Any change to them requires a design-doc amendment.

---

## 12. Implementation Methodology

### 12.1 Mandatory pipeline per slice

Every slice in §13 follows the existing agentic-delivery delivery boundary:

```
slice doc (this design § 13 + per-slice file under docs/backlog/agentic-cli-slices.md)
   ↓
agency-agents Staff+ implementation worker  (https://github.com/msitarzewski/agency-agents)
   ↓
slice code change (cli/ only — never touches scripts/, agentic/, identity-policy)
   ↓
adversarial review via AIT + Claude Code CLI  (review-only; no auto-apply)
   ↓
review evidence under agentic/reviews/  (ignored, public-safe summary in slice record)
   ↓
slice marked complete only after the review gate passes
```

**No slice ships without passing the review gate.** The gate is recorded against the implementation manifest, exactly like every other slice in this repo.

### 12.2 Implementation worker contract

| Property | Value |
|---|---|
| Source | https://github.com/msitarzewski/agency-agents (locally installed) |
| Minimum agent level | **Staff** or above |
| Selection per slice | Chosen by the slice's `implementer.agent` field (see §13 template) |
| Allowed write scope | Strictly `cli/**` (plus `.gitignore` and the documented README footnote in CLI-14) |
| Forbidden write scope | `scripts/`, `agentic/`, `docs/architecture/`, `docs/adr/`, `docs/standards/` (any change there is a separate ADR + design pass) |
| Test discipline | Slice does not land until its own tests pass and overall coverage gate (§10.6) holds |

The agentic-delivery scaffold already encodes the "write scope" concept via `scripts/dispatch-implementation-task.sh`; the CLI slices reuse the same enforcement.

### 12.3 Adversarial code review contract

| Property | Value |
|---|---|
| Reviewer runtime | **Claude Code CLI only** (`claude` binary). **Direct calls to the Claude / Anthropic API are forbidden.** |
| Invocation transport | **AIT only** — `ait run --adapter claude-code …` |
| Apply mode | `--apply never` (review is evidence; never mutates files) |
| Review mode | `--review never` (no AIT auto-review on top of the review itself) |
| Sandbox | `--sandbox read-only` (when the underlying adapter exposes it) |
| Output format | `--format json` for machine-parseable evidence |
| Working directory | Current workspace via `--cd "$PWD"`; extra dirs via `--add-dir` only when the review must read files outside the worktree |
| Per-loop cap | 5 review rounds, matching the existing rule in `agentic/README.md` |
| Round 5 unresolved | Records `blocked_human_decision_required` and pauses for Staff-level decision |
| Authority | Review output is **evidence only**; it cannot approve artifacts or bypass `agentic/identity-policy.yaml` |
| Forbidden | Codex-based review for CLI slices; direct Anthropic API calls; simulated reviewer output; Claude Code Desktop / web |

Concrete invocation pattern (copy of the rule recorded in `agentic/README.md`, adapted to `--adapter claude-code`):

```bash
unset ANTHROPIC_API_KEY    # never required; prevent accidental API usage
ait run --adapter claude-code --stdin none --apply never --review never --format json -- \
  "$(command -v claude)" \
  --agent <agency-agent-name> \
  --add-dir "$PWD" \
  -p "<review prompt referencing cli/<slice>/** and the slice's acceptance criteria>"
```

`<agency-agent-name>` is drawn from the locally installed agency-agents catalog and recorded against each slice (see §13 template field `reviewer.agents`). At minimum each slice runs the following adversarial agents (named after the existing agentic-delivery review board where applicable):

- `engineering-software-architect`
- `engineering-security-engineer`
- `engineering-code-reviewer`
- `engineering-technical-writer` (only for slices touching user-visible help / docs)
- `product-manager` (only for slices that change CLI behaviour visible in `--help`)

Each agent's run produces a JSON trace under `agentic/reviews/agentic-cli/<slice-id>/round-<n>.json`. The slice record cites the trace ids in the implementation manifest.

### 12.4 Boundaries the review may not cross

- Review may **read** `scripts/`, `agentic/`, `docs/`, and other tracked context, but its findings must not request edits outside `cli/**`. Any cross-boundary finding becomes a separate ADR ticket.
- Review must not invoke external services beyond what AIT permits for `claude-code` adapter runs in read-only sandbox mode.
- Review must not embed customer identifiers, secrets, or private strategy in evidence files. Public-safe summary lines only.

### 12.5 Slice acceptance gate

A slice is marked complete only when **all** of the following hold:

1. Acceptance criteria in §13 are met and demonstrated by tests in `cli/tests/`.
2. Coverage and lint thresholds in §10.6 hold for the combined CLI package.
3. At least one round of AIT + Claude Code CLI adversarial review has been recorded with `status: approved` in the implementation manifest (or rounds 2-5 with documented resolutions of earlier findings).
4. `agentic/runs/<impl-run-id>/implementation-manifest.yaml` records actor, role, authorization action, policy path, and trace ids for both the implementation and the review.

These are the same rules `agentic/README.md` already enforces for every other implementation slice in the repo.

---

## 13. Slice Plan

Each slice is a single PR-sized unit. Slice records live in `docs/backlog/agentic-cli-slices.md` (created in CLI-00) and are tracked in an implementation run initialised from this approved spec. Field semantics match the existing `docs/backlog/agentic-delivery-automation-slices.md` format.

### Slice template

```yaml
id: CLI-NN
title: <short imperative>
scope: <one paragraph>
write_scope:
  - cli/**         # always
  # (other paths only when documented and explicitly justified)
files_touched:
  - <relative path>
  - ...
acceptance_criteria:
  - <observable criterion 1>
  - <observable criterion 2>
validation_command: |
  pytest cli/tests/<area> -q
  ruff check cli/agentic
  mypy --strict cli/agentic
rollback_notes: <how to revert in one PR if needed>
dependencies: [<prior slice ids>]
implementer:
  source: agency-agents (msitarzewski)
  agent: <agency-agent-name, Staff+>
reviewer:
  runtime: claude-code-cli-via-ait
  agents: [engineering-software-architect, engineering-security-engineer, engineering-code-reviewer, ...]
  evidence_dir: agentic/reviews/agentic-cli/CLI-NN/
```

### CLI-00 — Bootstrap slice tracking

- **Scope:** Create `docs/backlog/agentic-cli-slices.md` listing CLI-01 … CLI-15 with the template above; create the agentic-delivery planning run that will own the implementation manifest.
- **Files:** `docs/backlog/agentic-cli-slices.md`, `agentic/runs/<id>/manifest.yaml` (via `scripts/init-agentic-run.sh`).
- **Acceptance:** Planning run initialised with this design and the slice backlog as approved artifacts; implementation run not yet started.
- **Reviewer agents:** `engineering-software-architect`, `engineering-technical-writer`.

### CLI-01 — Scaffold `cli/` package

- **Scope:** Create `cli/pyproject.toml`, `cli/agentic/__init__.py`, `cli/agentic/app.py` with `agentic` + `agentic version` + `--help`; add `cli/README.md` and `cli/CHANGELOG.md`; configure ruff + mypy.
- **Files:** `cli/pyproject.toml`, `cli/agentic/app.py`, `cli/agentic/__init__.py`, `cli/README.md`, `cli/CHANGELOG.md`, `cli/tests/test_smoke.py`.
- **Acceptance:** `pip install -e cli/`, `agentic --help`, `agentic version` all succeed locally; mypy + ruff clean.
- **Dependencies:** none.
- **Reviewer agents:** `engineering-software-architect`, `engineering-code-reviewer`.

### CLI-02 — Repo discovery + compat check

- **Scope:** Implement `cli/agentic/context.py` repo resolver (flag > env > walk-up > config); read `pipeline.yaml.version`; enforce `tool.agentic.compatible_pipeline_versions`.
- **Files:** `cli/agentic/context.py`, `cli/tests/test_context.py`, `cli/tests/test_compat.py`.
- **Acceptance:** Exit 5 on incompatible pipeline; exit 6 on missing repo; `agentic version` prints resolved repo + source.
- **Dependencies:** CLI-01.
- **Reviewer agents:** `engineering-software-architect`, `engineering-security-engineer`, `engineering-code-reviewer`.

### CLI-03 — Run-context resolution + `agentic run` commands

- **Scope:** `.agentic/current-run` read/write; flag > env > file priority; `agentic run list/use/show/clear`; add `.agentic/` to top-level `.gitignore`.
- **Files:** `cli/agentic/context.py`, `cli/agentic/commands/run.py`, `cli/tests/test_run_commands.py`, `.gitignore`.
- **Acceptance:** Priority validated by tests; `agentic run show` always discloses source; refuses unknown run ids.
- **Dependencies:** CLI-02.
- **Reviewer agents:** `engineering-software-architect`, `engineering-security-engineer`, `engineering-code-reviewer`.

### CLI-04 — `manifest.py` reader + `agentic status`

- **Scope:** Read-only `Manifest` dataclass over `agentic/runs/<id>/manifest.yaml` (planning + implementation variants); implement `agentic status` text + `--json` outputs.
- **Files:** `cli/agentic/manifest.py`, `cli/agentic/commands/status.py`, `cli/tests/test_manifest.py`, `cli/tests/snapshots/status_*.txt`.
- **Acceptance:** `agentic status` works on real `agentic/runs/<id>/manifest.yaml`; `--json` matches `_schema: agentic.cli/v1`.
- **Dependencies:** CLI-03.
- **Reviewer agents:** `engineering-software-architect`, `engineering-code-reviewer`, `engineering-technical-writer`.

### CLI-05 — State engine v1 + `agentic next`

- **Scope:** `cli/agentic/state_engine/` (engine, primitives, default `rules.yaml`); `agentic next`; full fixture coverage per §10.2.
- **Files:** `cli/agentic/state_engine/*.py`, `cli/agentic/state_engine/rules.yaml`, `cli/agentic/commands/next.py`, `cli/tests/state_engine/**`.
- **Acceptance:** All 15+ fixtures pass; fallback rule fires when expected; user override via XDG path supported.
- **Dependencies:** CLI-04.
- **Reviewer agents:** `engineering-software-architect`, `engineering-code-reviewer`, `product-manager`.

### CLI-06 — `shell.py` + `agentic plan` namespace + `agentic init`

- **Scope:** Subprocess wrapper with env propagation (`RUN_ID`, `AIT_ACTOR`, `AIT_ACTOR_ROLE`), exit-code mapping (§9.3), log capture; all `plan` subcommands routed to scripts. **Also wires the top-level `agentic init "goal" [--goal-file <f>] [--profile <id>]` command per §5.1**, routing to `scripts/init-agentic-run.sh`. This closes the §5.1 hot-path coverage gap that earlier draft sequencing left to CLI-13's smoke test.
- **Files:** `cli/agentic/shell.py`, `cli/agentic/commands/plan.py`, `cli/agentic/commands/init.py`, `cli/tests/test_shell.py`, `cli/tests/test_commands_plan.py`, `cli/tests/test_commands_init.py`.
- **Acceptance:** `RecordingRunner` tests prove argv + env; real call to `scripts/generate-artifacts.sh` works in smoke; `plan artifact … approve` sugar verbs work; `agentic init "goal"` creates a run via `scripts/init-agentic-run.sh` and the run id round-trips through `agentic status`.
- **Dependencies:** CLI-05.
- **Reviewer agents:** `engineering-software-architect`, `engineering-security-engineer`, `engineering-code-reviewer`.

### CLI-07 — `agentic impl` namespace

- **Scope:** All `impl` subcommands (init/tasks/dispatch/execute/review/validate); forward `--actor` / `--role`.
- **Files:** `cli/agentic/commands/impl.py`, `cli/tests/test_commands_impl.py`.
- **Acceptance:** Each subcommand maps to its script; tests assert env passthrough and exit-code mapping.
- **Dependencies:** CLI-10.
- **Reviewer agents:** `engineering-software-architect`, `engineering-security-engineer`, `engineering-code-reviewer`.

### CLI-08 — `agentic boss` namespace

- **Scope:** All **24** boss-idea subcommands per §5.4; `boss validate <kind>` consolidates **12 validators** (11 `validate-boss-idea-*.sh` + `validate-boss-decision-memo.sh`).
- **Files:** `cli/agentic/commands/boss.py`, `cli/tests/test_commands_boss.py`.
- **Acceptance:** 100 % of the 24 boss-idea scripts reachable via CLI; fixtures cover happy path + at least one error per subcommand group. The script→command mapping table at `cli/agentic/commands/_coverage.py` (per §5.6) accurately reflects this slice's deliveries.
- **Dependencies:** CLI-10.
- **Reviewer agents:** `engineering-software-architect`, `engineering-security-engineer` (boss-idea scripts perform outbound HTTP via crawl / live-smoke / provider-health), `engineering-code-reviewer`.

### CLI-09a — Security-heavy namespaces (hermes + identity)

- **Scope:** `hermes` and `identity` namespaces per §5.5. These handle outbound action invocation (`run-hermes-action.sh`, `hermes-gateway-dry-run.sh`) and authorization (`authorize-agentic-action.sh`, `validate-identity-policy.sh`) — both flow trust into `agentic/identity-policy.yaml` boundary.
- **Files:** `cli/agentic/commands/hermes.py`, `cli/agentic/commands/identity.py`, matching tests.
- **Acceptance:** Both namespaces cover every script listed under hermes/identity in §5.5 with named subcommands. Tests assert authorization env (`AIT_ACTOR`, `AIT_ACTOR_ROLE`) propagates and that hermes scripts receive `RUN_ID` when needed.
- **Dependencies:** CLI-10.
- **Reviewer agents:** `engineering-software-architect`, **`engineering-security-engineer` (mandatory)**, `engineering-code-reviewer`.

### CLI-09b — Lower-risk namespaces (evidence + fixtures + manifest + validate)

- **Scope:** `evidence`, `fixtures`, `manifest`, `validate` namespaces per §5.5.
- **Files:** `cli/agentic/commands/{evidence,fixtures,manifest_cmd,validate}.py`, matching tests.
- **Acceptance:** Coverage check — every remaining `scripts/*.sh` is reachable via a named command (or explicitly routed to `agentic raw`).
- **Dependencies:** CLI-10.
- **Reviewer agents:** `engineering-software-architect`, `engineering-code-reviewer`.

### CLI-10 — `agentic raw` escape hatch

- **Scope:** Validate `name ^[a-z0-9][a-z0-9-]*\.sh$` (leading-dash forbidden per §11.5); refuse path traversal, absolute paths, non-`.sh`, non-existent scripts; resolve via `realpath` and refuse if the resolved path leaves `<repo>/scripts/`; refuse symlinks-to-symlinks; require `--` boundary before forwarding extra args. Acts as the floor of wrapper coverage — landed immediately after CLI-06 so §5.7's "always available" guarantee holds for the rest of the rollout.
- **Files:** `cli/agentic/commands/raw.py`, `cli/tests/test_commands_raw.py` (tests for: leading dash, absolute path, `..` traversal, symlink-out-of-repo, symlink-loop, symlink-to-symlink, missing file, non-`.sh`, `--` boundary, realpath-vs-constructed-path passed to subprocess).
- **Acceptance:** All security tests pass; happy path forwards exit code through the §9.3 mapping; running `agentic raw foo.sh -- --verbose` invokes `scripts/foo.sh --verbose` with no Typer interception.
- **Dependencies:** CLI-06.
- **Reviewer agents:** `engineering-software-architect`, **`engineering-security-engineer` (mandatory)**, `engineering-code-reviewer`.

### CLI-11 — `--json` mode + structured errors

- **Scope:** Global `--json` flag; structured stderr errors (§9.2); `_schema: agentic.cli/v1` envelope codified at `cli/agentic/schemas/cli_v1.schema.json` (per §9.5.1); snapshot tests strict mode; CI schema-stability gate.
- **Files:** `cli/agentic/ui/render.py`, `cli/agentic/ui/errors.py`, `cli/agentic/schemas/cli_v1.schema.json`, `cli/tests/test_json_schema_conformance.py`, snapshot updates.
- **Acceptance:** Every public command supports `--json`; `cli_v1.schema.json` validates every command's output; CI schema-stability gate detects non-additive changes.
- **Dependencies:** CLI-07, CLI-08, CLI-09a, CLI-09b.
- **Reviewer agents:** `engineering-software-architect`, `engineering-code-reviewer`, `engineering-technical-writer`, `product-manager`.

### CLI-12 — Tab completion + `agentic doctor`

- **Scope:** `agentic --install-completion`; `agentic doctor` batches `validate-agentic-system` + `validate-manifest-schema` + `privacy-scan-tracked` + `validate-identity-policy`; suggests fixes.
- **Files:** `cli/agentic/commands/doctor.py`, `cli/tests/test_doctor.py`.
- **Acceptance:** Doctor returns non-zero only when at least one underlying check fails; doctor's output is JSON-able.
- **Dependencies:** CLI-11.
- **Reviewer agents:** `engineering-software-architect`, `engineering-code-reviewer`.

### CLI-13 — CI workflow + e2e smoke

- **Scope:** `.github/workflows/cli.yml` with matrix; `cli/tests/smoke/test_e2e.sh`; coverage gate ≥ 85.
- **Files:** `.github/workflows/cli.yml`, `cli/tests/smoke/test_e2e.sh`.
- **Acceptance:** CI green on a fresh PR; coverage threshold enforced.
- **Dependencies:** CLI-12.
- **Reviewer agents:** `engineering-software-architect`, `engineering-code-reviewer`.

### CLI-14 — README + goal-prompt footnotes

- **Scope:** Add "Quick start (CLI)" section to `agentic/README.md`; append CLI-equivalent footnote to `docs/auto-docs-to-implementation-goal-prompt.md` and `docs/hermes-adapter-slices-goal-prompt.md`. **Out-of-scope edits beyond these footnotes are not allowed in this slice.**
- **Files:** `agentic/README.md`, `docs/auto-docs-to-implementation-goal-prompt.md`, `docs/hermes-adapter-slices-goal-prompt.md`.
- **Acceptance:** README still public-safe (privacy scan passes); diff against base is the documented additions only.
- **Dependencies:** CLI-12.
- **Reviewer agents:** `engineering-technical-writer`, `product-manager`, `engineering-software-architect` (for accuracy of CLI claims).

### CLI-15 — PyPI publish workflow + v0.1.0 release

- **Scope:** `.github/workflows/cli-publish.yml`; tag-driven; ensure wheel + sdist + checksums; first 0.1.0 release.
- **Files:** `.github/workflows/cli-publish.yml`.
- **Acceptance:** Dry-run publish to TestPyPI succeeds; tag `cli-v0.1.0` produces published artefacts.
- **Dependencies:** CLI-13, CLI-14.
- **Reviewer agents:** `engineering-software-architect`, `engineering-security-engineer`, `engineering-code-reviewer`.

### 13.x Sequencing summary

```
CLI-00 → CLI-01 → CLI-02 → CLI-03 → CLI-04 → CLI-05
                                     │
                                     └─→ CLI-06 → CLI-10 ─┬─→ CLI-07
                                                          ├─→ CLI-08
                                                          ├─→ CLI-09a (hermes + identity, security-heavy)
                                                          └─→ CLI-09b (evidence + fixtures + manifest + validate)
                                                                  │
                                                                  └─→ CLI-11 → CLI-12 → CLI-13 → CLI-14 → CLI-15
```

**CLI-10 lands immediately after CLI-06** — not in the parallel fan-out — because §5.7 promises `agentic raw` is "always available so missing wrapper coverage never blocks a user." Until CLI-10 ships, that floor does not exist; landing it before CLI-07/08/09 makes the promise true throughout the rest of the rollout.

**CLI-09 is split** into CLI-09a (hermes + identity — outbound action invocation and authorization; mandatory security review) and CLI-09b (evidence + fixtures + manifest + validate — lower risk). The two halves are independent after CLI-10 and may run in parallel.

CLI-07 / CLI-08 / CLI-09a / CLI-09b are independent after CLI-10 and may run in parallel (separate agency-agents workers, separate review rounds, separate PRs).

---

## 14. Open Questions / Future Work

- **Profile-aware help.** Should `agentic --help` only show namespaces that apply to the active profile? Leaning no — discoverability beats noise — but revisit at v0.5.
- **`agentic next --run` (auto-execute)** is intentionally out of scope at v1. Reconsider only if user feedback strongly demands it.
- **State-rule extension by users.** v1 supports override but not merge; if user demand appears, design a structured merge later.
- **Hermes adapter integration.** Phase 3 may have Hermes call the CLI instead of `scripts/run-hermes-action.sh`. Decision deferred.
- **Brew formula vs. PEX.** Both possible; defer to v1.0+.
- **i18n.** CLI strings in English only at v1. Localisation deferred.
- **Review board composition.** If agency-agents catalog gains roles more relevant to CLI work (e.g. `cli-ux-reviewer`), add them to the reviewer roster for the relevant slices.

---

## Purpose

Define the v0.1 design of the `agentic` CLI: a state-aware Python wrapper over `scripts/*.sh` that becomes the primary user interface for the agentic-delivery pipeline while leaving the shell scripts as authoritative.

## Scope

In scope: a `cli/` package inside this repo (Python 3.10+, Typer + Rich + PyYAML); a state engine reading `agentic/runs/<id>/manifest.yaml`; full coverage of the 55 existing `scripts/*.sh` (named subcommands + `agentic raw` escape hatch); install via `pipx install agentic-delivery`; compatibility matrix against `agentic/pipeline.yaml::pipeline.version`; CI workflow and PyPI publish flow. Out of scope: rewriting any script in Python, Hermes adapter changes, telemetry, brew/PEX distribution before v1.0. The full goal/non-goal list is in §2.

## Acceptance Criteria

The spec is accepted when, taken together: (1) the locked decisions in §3 reflect user confirmation; (2) the command tree in §5 covers all 55 scripts (verified via the coverage check at §5.6); (3) §6 contains the full declarative rule table and primitive set; (4) §10 commits to coverage ≥ 85 with state-engine ≥ 95 and snapshot-locked `--json` schema; (5) §11 preserves the three red lines (scripts authoritative, automation unaffected, no silent schema mutation); (6) §12 mandates AIT + Claude Code CLI adversarial review for every slice, with no direct Anthropic API calls allowed; and (7) §13 decomposes the work into CLI-00 .. CLI-15 implementation slices.

## Validation

Spec validation runs at three levels. (a) Repo-local: `scripts/validate-manifest-schema.sh`, `scripts/validate-artifact-templates.sh`, and `scripts/privacy-scan-tracked.sh` must pass against the planning run that owns this artifact. (b) Adversarial review: AIT + Claude Code CLI rounds with `engineering-software-architect`, `engineering-security-engineer`, `engineering-code-reviewer`, `engineering-technical-writer`, and `product-manager` agents must record approving evidence under `agentic/reviews/agentic-cli/`. (c) Implementation reality check: each CLI-NN slice's tests, coverage gate, and adversarial review must pass as defined in its per-slice plan under `docs/superpowers/plans/2026-05-27-agentic-cli/`.

## Rollback

If this spec needs to be retracted before any slice ships: mark its artifact entry `rejected` (with public-safe reason) in the planning manifest, then delete `cli/` if any scaffold has landed. Because the spec touches no production code on its own, rollback is a documentation revert. If a downstream slice has already landed and needs reversal, follow that slice's own Rollback section in its plan file; reverts are per-slice and isolated to `cli/**` plus the documented coexistence touchpoints in §11.

## Review Expectations

Every slice CLI-00 .. CLI-15 goes through AIT + Claude Code CLI adversarial review per §12.3 — no exceptions, no direct Anthropic API calls, `--apply never --review never --sandbox read-only --format json`. Review evidence lives under `agentic/reviews/agentic-cli/CLI-NN/round-N.json`. The review board for each slice is fixed in its plan file's "Reviewer agents" section. The spec itself is reviewed with the agents listed under §12.3 (architect, security, code reviewer, tech writer, PM); review findings either revise this spec or are deferred to a follow-up ADR.
