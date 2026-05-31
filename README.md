# 🚚 Agentic Delivery: A Pipeline That Turns Goals Into Approved, Implementable Work

> **A public-safe delivery pipeline for AI-orchestrated teams** — plan, review, approve, implement, and validate with manifest authority you can audit. From an executive's half-formed idea to a worker-dispatched implementation slice, every step leaves evidence and every transition has an owner.

[![PyPI](https://img.shields.io/pypi/v/agentic-delivery.svg)](https://pypi.org/project/agentic-delivery/)
[![Python](https://img.shields.io/pypi/pyversions/agentic-delivery.svg)](https://pypi.org/project/agentic-delivery/)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://makeapullrequest.com)

---

## 🚀 What Is This?

Agentic Delivery is the **public-safe scaffold of an internal delivery pipeline**. It takes a profile + a goal and turns them into manifest-backed planning artifacts, review evidence, explicit approval decisions, implementation tasks, validation records, and PR/release preparation — without ever letting agent memory, raw LLM output, or executive intuition become the source of truth.

Each stage of the pipeline is:

- **🧾 Manifest-Backed**: Repo-local YAML manifests are authoritative. Hermes memory, agent transcripts, and review chat are execution context only.
- **🚦 Gated**: Implementation consumes only `approved` artifacts. Drafts, reviewed-but-undecided, and rejected work cannot leak across the boundary.
- **🕵️ Evidence-First**: Every transition records who decided what, why, under which authorization, against which policy.
- **🔒 Public-Safe**: Tracked files cannot contain customer identifiers, secrets, raw review traces, or non-public strategy.
- **🤖 Hermes-Friendly, Hermes-Independent**: Every Hermes action maps 1:1 to a repo-local command. The repo runs identically with Hermes off.

**Think of it as**: A delivery org's lifecycle — strategy gate → research → review-fix loop → approval → task graph → worker dispatch → review-fix → validation → PR — rendered as a small, inspectable set of YAML manifests and Bash scripts you can read in an afternoon.

---

## ⚡ Quick Start

### Option 1: Install the CLI (Recommended)

```bash
# Install the state-aware CLI wrapper
pipx install agentic-delivery

# Inside any clone of an agentic-delivery repo
agentic doctor                                # health-check the scaffold
agentic init "Your delivery goal"             # start a planning run
agentic next                                  # what should I do next?
agentic status                                # inspect current run state
agentic plan artifact docs/adr/008-xyz.md approve --reason "..."
```

The `agentic` CLI is a thin, state-aware wrapper over the same `scripts/*.sh` pipeline — both forms remain valid.

### Option 2: Use the Scripts Directly

```bash
# Validate the scaffold and default profile
scripts/validate-agentic-system.sh

# Initialize a planning run from a goal
scripts/init-agentic-run.sh "Next delivery goal"

# Run AIT-backed multi-agent planning deliberation
RUN_ID=<run-id> scripts/run-agency-review.sh
scripts/summarize-agency-review.sh <run-id>

# Generate drafts, run review loops, transition artifact status
scripts/generate-artifacts.sh <run-id>
scripts/run-artifact-review-loop.sh <run-id> --artifact <path>
scripts/update-artifact-status.sh <run-id> <path> approved --reason "..." --actor local-operator --role approver
```

### Option 3: Drive It from Hermes

```bash
# Every Hermes action is dry-runnable and maps to a script
scripts/run-hermes-action.sh --dry-run validate_scaffold
scripts/run-hermes-action.sh update_artifact_status \
  run_id=<run-id> artifact_path=<path> status=approved \
  reason="Approved for implementation" \
  actor=local-operator role=approver
```

See [`agentic/README.md`](agentic/README.md) for the full pipeline reference and [`cli/README.md`](cli/README.md) for the CLI command reference.

---

## 🧭 The Delivery Pipeline

The pipeline has two **modes** (`planning`, `implementation`), 23 success states, and 10 explicit failure states. Every transition is a recorded decision.

```text
profile + goal
  → planning run
  → AIT multi-agent planning deliberation
  → generated drafts
  → review-fix loop
  → reviewed and approved artifacts
  → implementation run
  → implementation task graph
  → worker dispatch + execution
  → implementation review-fix
  → validation + PR/release preparation
  → Hermes-native dry-run integration
```

### 📐 Planning Stage

Turns a goal into a manifest of planned artifacts, generates drafts, runs review loops, and records explicit approval decisions.

| Step | Command | Output |
|------|---------|--------|
| 🗂️ Initialize run | `scripts/init-agentic-run.sh "<goal>"` | `agentic/runs/<run-id>/manifest.yaml` |
| 🧠 Planning deliberation | `scripts/run-agency-review.sh` | Review evidence (ignored, local) |
| ✍️ Generate drafts | `scripts/generate-artifacts.sh <run-id>` | Drafts marked `drafted` in manifest |
| 🤖 Optional AI generation | `scripts/run-artifact-generation-agent.sh --execute <run-id>` | Edits requested artifact files |
| 🔁 Review-fix loop | `scripts/run-artifact-review-loop.sh <run-id> --artifact <path>` | Bounded review round (max 5) |
| ✅ Approval | `scripts/update-artifact-status.sh <run-id> <path> approved --reason "..."` | Status transition recorded with actor/role |

### 🚦 Approval Gate

Implementation consumes only `approved` artifacts. Status flow:

| Status | Meaning | Implementation Consumable |
|--------|---------|---------------------------|
| `planned` | Manifest expects it | ❌ |
| `drafted` | Content exists, can enter review | ❌ |
| `reviewed` | Review done, awaits decision | ❌ |
| `changes_requested` | Blocking findings; revise required | ❌ |
| `approved` | Accepted for implementation | ✅ |
| `rejected` | Must not be implemented | ❌ |
| `deferred` | Intentionally out of scope | ❌ |

Approval, rejection, deferral, and change requests all require a public-safe reason. Authorization is enforced by [`agentic/identity-policy.yaml`](agentic/identity-policy.yaml) and propagated to scripts via `AIT_ACTOR` and `AIT_ACTOR_ROLE`.

### 🛠️ Implementation Stage

Filters approved artifacts into an implementation run, builds a task graph, dispatches bounded workers, runs review-fix loops, and prepares PR/release records.

| Step | Command | Output |
|------|---------|--------|
| 🏗️ Initialize impl run | `scripts/init-implementation-run.sh --planning-run <planning-id>` | `implementation-manifest.yaml` |
| 🕸️ Build task graph | `scripts/generate-implementation-task-graph.sh <impl-id>` | Tasks with scope, writes, validation, rollback, dependencies |
| 📦 Dispatch task | `scripts/dispatch-implementation-task.sh <impl-id> <task-id>` | Worker instructions, write-scope conflict check |
| ⚙️ Execute task | `scripts/execute-implementation-task.sh <impl-id> <task-id>` | Worker evidence recorded |
| 👀 Implementation review | `scripts/run-implementation-review-loop.sh <impl-id> <task-id>` | Codex CLI Staff+ review evidence |
| 🧪 Validate run | `scripts/validate-implementation-run.sh <impl-id>` | Schema + contract validation |

### 🧪 Validation Stage

| Command | Validates |
|---------|-----------|
| `scripts/validate-agentic-system.sh` | Scaffold + default profile |
| `scripts/validate-manifest-schema.sh --all` | All run manifests against `manifest.schema.yaml` |
| `scripts/validate-artifact-templates.sh <run-id>` | Generated artifact templates |
| `scripts/validate-hermes-actions.sh` | Hermes action contracts |
| `scripts/validate-identity-policy.sh` | Repo-local actor/role policy |
| `scripts/privacy-scan-tracked.sh` | Public-safety of tracked files |
| `scripts/run-golden-fixtures.sh` | End-to-end golden fixture replay |

---

## 🎭 Profiles

A profile defines the source of truth, required artifacts, review board, strategy gate, and rejected directions for a class of delivery work. The scaffold ships with **two public-safe profiles**:

| Profile | Purpose | When to Use |
|---------|---------|-------------|
| 🧱 [default-delivery](agentic/profiles/default-delivery.yaml) | Public-safe scaffold profile for the Agentic Delivery System itself | Any planning + implementation run that targets the delivery pipeline scaffold, its docs, schemas, or scripts |
| 🧨 [boss-idea-response](agentic/profiles/boss-idea-response.yaml) | Triage executive ideas into research, recommendation, POC, MVP, or no-go | When an exec idea arrives and you need source-backed research, feasibility scoring, a decision memo, POC/MVP timeboxing, and a recorded go/no-go — without turning the raw idea into implementation work |

Add a new profile by writing `agentic/profiles/<id>.yaml` and pointing `PROFILE=<id>` at it. Profiles are public-safe; private profiles must never become tracked sources of truth.

---

## 🧰 The Toolkit

### 💻 `agentic` CLI

A Typer-based, state-aware wrapper. Sub-apps:

| Command | Purpose |
|---------|---------|
| `agentic init` | Start a planning run from a goal |
| `agentic next` | What should I do next on this run? |
| `agentic status` | Inspect current run state |
| `agentic plan` | Planning-stage operations (artifact status, review loop, etc.) |
| `agentic impl` | Implementation-stage operations (task graph, dispatch, execute) |
| `agentic boss` | Boss-idea-response workflow (intake, research, decision) |
| `agentic hermes` | Hermes action dry-runs and execution |
| `agentic identity` | Inspect and validate repo-local identity policy |
| `agentic evidence` | Review/worker evidence operations |
| `agentic fixtures` | Golden fixture replay |
| `agentic manifest` | Manifest schema validation |
| `agentic validate` | Scaffold and contract validation |
| `agentic doctor` | Health-check the repo + scaffold |
| `agentic raw` | Drop down to raw `scripts/*.sh` invocations |

See [`cli/README.md`](cli/README.md) for the full command reference and [`docs/superpowers/specs/2026-05-27-agentic-cli-design.md`](docs/superpowers/) for the design.

### 🧾 Schemas

Versioned, machine-checkable contracts under [`agentic/schemas/`](agentic/schemas/). 18 schemas cover:

| Schema | Covers |
|--------|--------|
| `manifest.schema.yaml` | Planning + implementation run manifests, status transitions, schema_version migration |
| `artifact-template.schema.yaml` | Generated artifact template structure |
| `identity-policy.schema.yaml` | Repo-local actors, roles, authorization actions, separation of duty |
| `boss-idea-intake.schema.yaml` | Structured idea intake records |
| `boss-idea-market-search.schema.yaml` | Source-backed market search inputs |
| `boss-idea-market-discovery-quality.schema.yaml` | Market discovery evidence quality scoring |
| `boss-idea-research.schema.yaml` | Source-backed research documents |
| `boss-idea-competitor-brief.schema.yaml` | Competitor brief contracts |
| `boss-idea-scorecard.schema.yaml` | Feasibility scoring |
| `boss-decision-memo.schema.yaml` | Decision memo structure |
| `boss-idea-poc-mvp.schema.yaml` | POC/MVP timebox records |
| `boss-idea-success-metrics.schema.yaml` | Success metric definitions |
| `boss-idea-decision.schema.yaml` | Recorded go/no-go decisions |
| `boss-idea-provider-health.schema.yaml` | Search provider health snapshots |
| `boss-idea-provider-health-events.schema.yaml` | Provider health event streams |
| `boss-idea-provider-fallback-advisory.schema.yaml` | Provider fallback advisories |
| `boss-idea-crawl-log.schema.yaml` | Market crawl evidence |
| `boss-idea-market-candidate-urls.schema.yaml` | Candidate URL packs |

### 📜 Prompt Templates

Reusable, role-bounded prompts under [`agentic/prompts/`](agentic/prompts/):

| Prompt | Role |
|--------|------|
| `review-agent.md` | Generic artifact reviewer |
| `code-review-agent.md` | Implementation slice reviewer |
| `slice-code-review.md` | Per-slice code review protocol |
| `implementation-agent.md` | Implementation worker |
| `document-builder-agent.md` | Public-safe document drafter |
| `schema-validation-agent.md` | Manifest/schema validator |
| `connector-research-agent.md` | Connector research and gap analysis |
| `integration-agent.md` | Cross-system integration |
| `strategy-gate.md` | Strategy gate enforcement |
| `hermes-orchestrator.md` | Hermes-side orchestrator |

### 📚 Architecture & Standards

| Doc | What It Defines |
|-----|-----------------|
| [`docs/architecture/agentic-delivery-system.md`](docs/architecture/agentic-delivery-system.md) | The pipeline itself |
| [`docs/architecture/agentic-delivery-automation-roadmap.md`](docs/architecture/agentic-delivery-automation-roadmap.md) | Slice-by-slice automation roadmap |
| [`docs/architecture/hermes-orchestration-adapter.md`](docs/architecture/hermes-orchestration-adapter.md) | Hermes orchestration boundary |
| [`docs/architecture/agentic-identity-authorization.md`](docs/architecture/agentic-identity-authorization.md) | Repo-local identity and authorization design |
| [`docs/architecture/boss-idea-response-system.md`](docs/architecture/boss-idea-response-system.md) | Boss-idea-response system design |
| [`docs/standards/agentic-delivery-quality-standard.md`](docs/standards/agentic-delivery-quality-standard.md) | Per-slice quality bar |
| [`docs/standards/boss-idea-response-quality-standard.md`](docs/standards/boss-idea-response-quality-standard.md) | Boss-idea quality bar |
| [`docs/adr/003-agentic-delivery-boundary.md`](docs/adr/003-agentic-delivery-boundary.md) | Delivery / runtime boundary |
| [`docs/adr/004-hermes-orchestration-adapter.md`](docs/adr/004-hermes-orchestration-adapter.md) | Hermes adapter decision |
| [`docs/adr/005-artifact-approval-gate.md`](docs/adr/005-artifact-approval-gate.md) | Approval gate decision |
| [`docs/adr/006-boss-idea-crawl4ai-market-discovery.md`](docs/adr/006-boss-idea-crawl4ai-market-discovery.md) | Market discovery adapter decision |
| [`docs/adr/007-boss-idea-no-paid-search-provider.md`](docs/adr/007-boss-idea-no-paid-search-provider.md) | No-paid search provider decision |

---

## 🎯 Real-World Scenarios

### Scenario 1: A New Architecture Decision Needs to Ship

**Your Path**:

1. 🧱 Pick the **default-delivery** profile
2. 🗂️ `agentic init "Land ADR for X"` — manifest expects the ADR + roadmap touch
3. 🧠 Run **planning deliberation** — multi-agent brainstorm of gaps, risks, slices, validation
4. ✍️ Generate drafts; iterate inside the bounded review-fix loop
5. ✅ Record explicit approval with actor + role + reason
6. 🏗️ Spin an **implementation run**; build the task graph
7. 📦 Dispatch + execute bounded slices; **Codex CLI Staff+** runs review-only against each
8. 🧪 Validate the implementation manifest; prepare PR record

**Result**: An ADR + supporting changes shipped with every transition auditable, no agent memory holding authoritative state, and review-only enforcement on the Staff+ reviewer.

---

### Scenario 2: An Exec Throws You An Idea

**Your Path**: Switch to the **boss-idea-response** profile.

1. 🧨 `scripts/init-boss-idea-run.sh <idea.md>` — structured idea intake, validated against schema
2. 🌐 `scripts/crawl-boss-idea-market.sh` + `collect-boss-idea-research.sh` — source-backed market research and provider-health-aware discovery (free providers preferred per ADR-007)
3. 🥊 `scripts/generate-boss-idea-competitor-brief.sh` — public competitor and solution discovery
4. 📊 `scripts/score-boss-idea-feasibility.sh` — advisory scorecard
5. 📝 `scripts/generate-boss-decision-memo.sh` — public-safe decision memo
6. 🧪 `scripts/validate-boss-idea-poc-mvp.sh` + `validate-boss-idea-success-metrics.sh` — POC/MVP plan + metrics
7. 🚦 `scripts/record-boss-idea-decision.sh` — recorded go / hold / no-go

**Result**: Raw exec idea triaged into source-backed research, advisory scoring, a recorded decision, and either a timeboxed POC/MVP plan or a clean no-go — without the idea jumping the approval gate into implementation.

---

### Scenario 3: You Want Hermes to Orchestrate, But You Want Authority Local

**Your Path**:

1. 🤖 Hermes calls `scripts/run-hermes-action.sh --dry-run <action>` to plan
2. ✅ A repo-local operator (with role and authorization checked against `identity-policy.yaml`) signs off
3. 🔁 Hermes executes the action; the script runs the same way it would by hand
4. 🧾 Manifest, evidence, and identity attribution land in the repo, not in Hermes memory

**Result**: Hermes drives cadence; the repo keeps authority. Turn Hermes off and the pipeline still runs identically.

---

## 🔌 Hermes Integration

Hermes orchestrates; the repo decides. Every Hermes action maps 1:1 to a repo-local command, every executable mutating action declares an `authorization.action`, and every action is dry-runnable first.

| Hermes Action | Repo-Local Command |
|---------------|--------------------|
| `validate_scaffold` | `scripts/validate-agentic-system.sh` |
| `start_planning_run` | `scripts/init-agentic-run.sh` |
| `update_artifact_status` | `scripts/update-artifact-status.sh` |
| `generate_artifacts` | `scripts/generate-artifacts.sh` |
| `run_artifact_review_loop` | `scripts/run-artifact-review-loop.sh` |
| `run_agency_review` | `scripts/run-agency-review.sh` |
| `start_boss_idea_run` | `scripts/init-boss-idea-run.sh` |
| `collect_boss_idea_research` | `scripts/collect-boss-idea-research.sh` |
| `generate_boss_idea_competitor_brief` | `scripts/generate-boss-idea-competitor-brief.sh` |
| `run_boss_idea_live_smoke` | `scripts/run-boss-idea-live-smoke.sh` |
| `start_implementation_run` | `scripts/init-implementation-run.sh` |
| `generate_implementation_task_graph` | `scripts/generate-implementation-task-graph.sh` |
| `dispatch_implementation_task` | `scripts/dispatch-implementation-task.sh` |
| `execute_implementation_task` | `scripts/execute-implementation-task.sh` |
| `run_implementation_review_loop` | `scripts/run-implementation-review-loop.sh` |
| `validate_implementation_run` | `scripts/validate-implementation-run.sh` |
| `report_run_status` | `scripts/report-run-status.sh` |
| `hermes_memory_sync` | `scripts/hermes-memory-sync.sh --dry-run` |
| `hermes_scheduler_dry_run` | `scripts/hermes-scheduler-dry-run.sh` |
| `hermes_gateway_dry_run` | `scripts/hermes-gateway-dry-run.sh` |

See [`agentic/hermes-actions.yaml`](agentic/hermes-actions.yaml) for the full contract.

---

## 📖 Design Philosophy

Every piece of the pipeline is designed around five rules:

1. **🧾 Manifest Authority**: Repo-local YAML is the source of truth. Agent memory, transcripts, and chat are execution context only.
2. **🚦 Explicit Approval**: No work crosses into implementation without an `approved` status transition with actor, role, reason, and policy citation.
3. **🕵️ Evidence Stays Local**: Review evidence and run outputs live under ignored `agentic/reviews/` and `agentic/runs/<run-id>/` paths. Tracked files stay public-safe.
4. **🔁 Bounded Loops**: Review-fix loops cap at 5 rounds, then block with `blocked_human_decision_required` for a Staff-level decision.
5. **🤝 Separation of Duty**: Workers can't review their own task; reviewers can't approve their own artifact. Identity policy enforces it.

---

## 🎁 What Makes This Different?

### Unlike Hand-Wave "AI Agent Workflows":

- ❌ Whatever the LLM remembers is the state.
- ✅ A YAML manifest, a status, an actor, a role, a reason, and a status-history entry.

### Unlike Black-Box Orchestrators:

- ❌ The orchestrator owns the data and the decisions.
- ✅ The orchestrator schedules; the repo decides. Turn the orchestrator off, the pipeline still runs.

### Unlike "Reviewer Agents Approve Things":

- ❌ A reviewer LLM rubber-stamps and merges.
- ✅ Reviews are evidence only. A human (or explicitly authorized actor) records the approval status transition.

### Unlike "Boss Says Build, So We Build":

- ❌ Raw exec ideas become implementation tickets.
- ✅ Ideas go through structured intake → research → advisory scoring → decision memo → POC/MVP timebox → recorded go/no-go.

---

## 📊 At A Glance

- 🧾 **18** versioned YAML schemas
- 🛠️ **55+** Bash pipeline scripts
- 📜 **10** prompt templates
- 🏛️ **7** ADRs documenting boundary, adapter, and approval-gate decisions
- 🎭 **2** public-safe profiles (`default-delivery`, `boss-idea-response`)
- 🚦 **23** success states and **10** explicit failure states
- 🤖 **20+** Hermes actions, every one dry-runnable and mapped to a repo-local command
- 💻 **`agentic` CLI** (Python ≥3.10, Typer-based) shipped to PyPI as `agentic-delivery`

---

## 🗺️ Roadmap

Active and upcoming slices live in:

- [`docs/backlog/agentic-delivery-automation-slices.md`](docs/backlog/agentic-delivery-automation-slices.md)
- [`docs/backlog/agentic-delivery-system-roadmap.md`](docs/backlog/agentic-delivery-system-roadmap.md)
- [`docs/backlog/hermes-adapter-implementation-slices.md`](docs/backlog/hermes-adapter-implementation-slices.md)
- [`docs/backlog/agentic-identity-authorization-slices.md`](docs/backlog/agentic-identity-authorization-slices.md)
- [`docs/backlog/boss-idea-response-slices.md`](docs/backlog/boss-idea-response-slices.md)
- [`docs/backlog/boss-idea-productionization-slices.md`](docs/backlog/boss-idea-productionization-slices.md)
- [`docs/backlog/agentic-cli-slices.md`](docs/backlog/agentic-cli-slices.md)

Highlights:

- [x] Planning + implementation manifest authority
- [x] Bounded artifact and implementation review-fix loops
- [x] Repo-local identity and authorization policy
- [x] Hermes action contracts + dry-run runner
- [x] Golden fixture replay with local validation evidence
- [x] Boss-idea-response profile end-to-end
- [x] `agentic` CLI shipped to PyPI
- [ ] CI feedback ingestion
- [ ] Automated PR publishing
- [ ] Productionized boss-idea provider matrix

---

## 🤝 Contributing

Contributions welcome — especially:

- **New profiles** under `agentic/profiles/<id>.yaml` (must be public-safe, must declare source of truth, required artifacts, review board, and rejected directions)
- **New schemas** under `agentic/schemas/` with versioning and migration rules
- **New scripts** that map cleanly to a Hermes action and a dry-run path
- **New ADRs** that defend a boundary, an adapter, or an approval-gate change
- **Quality-bar tightening** in `docs/standards/agentic-delivery-quality-standard.md`

Before opening a PR:

```bash
scripts/validate-agentic-system.sh
scripts/validate-hermes-actions.sh
scripts/validate-identity-policy.sh
scripts/privacy-scan-tracked.sh
scripts/run-golden-fixtures.sh
```

Tracked files must stay public-safe: no customer identifiers, secrets, tokens, reviewer trace identifiers, private profiles, or raw review evidence.

---

## 🔒 Privacy & Public-Safety Boundary

This repo is the **public-safe scaffold**. Review evidence, run state, and private profiles stay local and ignored:

```text
agentic/reviews/
agentic/runs/<run-id>/
.agentic/
```

Run `scripts/privacy-scan-tracked.sh` before every commit. The default profile and ADRs explicitly reject:

- Storing authoritative state in Hermes memory
- Simulating agency or Staff+ review instead of running it through AIT + Codex CLI
- Committing private strategy or raw review evidence
- Allowing unapproved artifacts to drive implementation
- Introducing customer-facing runtime behavior into the delivery scaffold

---

## 📜 License

Apache-2.0. Use freely, commercially or personally. See [`LICENSE`](LICENSE) (and the `license` field of [`cli/pyproject.toml`](cli/pyproject.toml)).

---

## 🙏 Acknowledgments

Agentic Delivery exists because too many AI-orchestrated workflows let the model hold the keys to the kingdom — and then quietly forgot which keys they were holding. This scaffold is the opposite bet: **a small, inspectable pipeline, with manifest authority, evidence-only review, explicit approval, and a Hermes adapter that can be turned off without losing a thing.**

Thanks to everyone who has stress-tested a profile, written an ADR, broken a golden fixture, or argued a status transition.

---

## 💬 Community

- **Issues**: open one if a script's dry-run output disagrees with its real run
- **Discussions**: share your profile, your schema, your war story
- **PRs**: please run the validation suite before opening

---

## 🚀 Get Started

1. **Install** the CLI: `pipx install agentic-delivery`
2. **Validate** the scaffold: `scripts/validate-agentic-system.sh`
3. **Pick** a profile: `default-delivery` or `boss-idea-response`
4. **Initialize** a run: `agentic init "Your delivery goal"`
5. **Iterate** through the pipeline; let the manifest tell you what's next: `agentic next`

---

<div align="center">

**🚚 Agentic Delivery: Plan → Review → Approve → Implement → Validate 🚚**

[⭐ Star this repo](#) • [🍴 Fork it](#) • [🐛 Open an issue](#) • [📖 Read the architecture](docs/architecture/agentic-delivery-system.md)

Authority lives in the manifest. Evidence lives in the repo. Decisions belong to people.

</div>
