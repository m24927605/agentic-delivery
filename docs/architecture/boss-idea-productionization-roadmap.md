# Boss Idea Productionization Roadmap

## Purpose

Boss Idea Response already has the core market discovery pipeline: idea intake,
query pack generation, no-paid search providers, Crawl4AI-compatible evidence
collection, research synthesis, feasibility scoring, decision memo generation,
POC/MVP planning, success metrics, go/no-go recording, and evidence quality
scoring.

This roadmap defines the remaining productionization work required to make the
system reliable for day-to-day executive brainstorming support.

## Operating Decision

The default live search provider is self-hosted SearXNG.

Public SearXNG instances are not the default production dependency. Brave stays
an optional paid fallback, and `duckduckgo_html` plus `local_browser_search`
stay lower-trust no-paid fallbacks.

## Remaining Workstreams

### 1. Live Smoke Evidence

Goal: prove that the implemented pipeline works against a real self-hosted
SearXNG endpoint and real public pages without weakening deterministic golden
fixtures.

Needed output:

- live smoke runbook;
- public-safe evidence record under `agentic/reviews/boss-idea-response/`;
- preflight command that confirms endpoint, no-paid policy, and JSON output;
- validation that live smoke evidence never becomes an approval artifact.

Implementation slices:

- BIR-11A: document live smoke runbook and evidence template.
- BIR-11B: add a self-hosted SearXNG preflight command.
- BIR-11C: add a live smoke wrapper that records public-safe evidence.
- BIR-11D: add optional Hermes action wiring for live smoke execution.

### 2. One-Command Boss Idea Workflow

Goal: reduce operator friction when a boss idea arrives. One command should run
the standard planning path without hiding intermediate artifacts or approvals.

Needed output:

- orchestration command;
- manifest state updates for every generated artifact;
- resumable step boundaries;
- failure states that tell the operator which artifact needs attention.

Implementation slices:

- BIR-12A: define the orchestration contract and state machine.
- BIR-12B: implement dry-run workflow planning.
- BIR-12C: implement execute mode for deterministic no-network path.
- BIR-12D: add live SearXNG mode behind existing live gates.
- BIR-12E: add Hermes action contract and golden fixture coverage.

### 3. Executive Competitor Brief

Goal: generate a concise boss-facing artifact that turns raw research into a
comparison, options, unknowns, and recommended next action.

Needed output:

- competitor matrix;
- build / buy / partner / defer option set;
- engineering effort estimate band;
- risks and unknowns;
- next experiment and timebox;
- clear citation mapping to market research sources.

Implementation slices:

- BIR-13A: design artifact schema and Markdown template.
- BIR-13B: implement validator for the brief.
- BIR-13C: implement generator from market research, feasibility, metrics, and
  decision memo inputs.
- BIR-13D: add golden fixtures and negative tests.
- BIR-13E: add Hermes action and profile references.

### 4. Live Crawler Safety Hardening

Goal: improve live network safety beyond current URL policy and pre/post DNS
checks.

Needed output:

- explicit connect-time IP evidence where available;
- redirect chain capture;
- crawler helper contract for observed final URL and IP metadata;
- fail-closed behavior when observed metadata is missing in live mode.

Implementation slices:

- BIR-14A: document observed-network metadata contract.
- BIR-14B: extend Crawl4AI helper output schema for observed URL/IP metadata.
- BIR-14C: enforce observed metadata in live mode.
- BIR-14D: add redirect and DNS rebinding negative fixtures.
- BIR-14E: record safety evidence in crawl log and quality artifact.

### 5. Provider Health And Fallback Operations

Goal: make provider selection explainable over time, not only per run.

Needed output:

- provider health artifact;
- recent success/failure counters;
- captcha/challenge counters for fallback providers;
- fallback reason taxonomy;
- operator guidance for when to retry, switch, or escalate.

Implementation slices:

- BIR-15A: define provider health schema and retention policy.
- BIR-15B: record provider health events from market discovery runs.
- BIR-15C: summarize provider health into a public-safe report.
- BIR-15D: add fallback recommendation rules without automatic approval.
- BIR-15E: add golden fixtures and privacy scan coverage.

### 6. Documentation State Cleanup

Status: completed by this roadmap update.

Goal: remove confusing stale status labels now that BIR-10A through BIR-10G are
complete.

Needed output:

- BIR-10 parent status matches completed sub-slices;
- all remaining work is moved into BIR-11 and later;
- no document implies paid search is required;
- no document implies public SearXNG is the production default.

Completed slices:

- BIR-16A: updated BIR-10 parent status and acceptance notes.
- BIR-16B: added cross-reference from Boss Idea system overview to this
  roadmap.
- BIR-16C: added profile/source-of-truth references for this roadmap and
  productionization backlog.

### 7. Hermes CI/PR Publishing

Goal: decide whether deferred Hermes CI/PR publishing should remain out of
scope or become a controlled execution feature.

Needed output:

- ADR for continue-deferring vs implementing;
- authorization and identity model;
- dry-run payload contract;
- safeguards that keep repo manifests authoritative.

Implementation slices if implemented:

- H12A: ADR and threat model.
- H12B: dry-run PR publishing payload.
- H12C: CI status ingestion without write access.
- H12D: gated PR creation with identity policy and manual approval.
- H12E: golden fixtures and rollback tests.

## Quality Bar

Each implementation slice must:

- stay small enough for one focused code review;
- define purpose, scope, deferred scope, workflow, schema/contract, failure
  behavior, validation strategy, tests, acceptance criteria, rollback notes,
  doc review standard, and code review standard;
- run local validation before review;
- run AIT with Claude Code CLI reviewer;
- fix review findings and rerun, up to 5 rounds;
- escalate to Staff+ decision if round 5 still fails.
