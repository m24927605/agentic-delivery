# Boss Idea Productionization Slices

## Scope

These slices convert the completed Boss Idea market discovery foundation into a
repeatable production workflow for responding to executive brainstorming
requests. The core search/crawl pipeline remains BIR-10. This backlog starts
after BIR-10G.

## Review Rule

Every documentation or implementation slice must run AIT with Claude Code CLI
review. Implementation slices may run up to 5 review/fix rounds. If round 5
does not pass, the Staff+ expert board records a decision and chooses a smaller
slice, deferral, or alternate implementation path.

## BIR-11: Self-Hosted SearXNG Live Smoke

Status: completed by the productionization documentation update.

Owner role: Staff Platform Engineer.

Purpose: prove a real self-hosted SearXNG endpoint can drive the Boss Idea
market discovery pipeline without making live internet part of default golden
validation.

### BIR-11A: Live Smoke Runbook And Evidence Template

Scope:

- document setup for a self-hosted SearXNG endpoint;
- define public-safe live smoke evidence format;
- define operator preconditions and rollback.

Deferred scope:

- implementing commands;
- storing raw SearXNG responses in tracked files.

Acceptance criteria:

- runbook names self-hosted SearXNG as the only default live provider;
- evidence template excludes secrets and raw page bodies;
- doc review confirms public instances are not the production default.

Validation:

```bash
git diff --check
scripts/validate-agentic-system.sh
PROFILE=boss-idea-response scripts/validate-agentic-system.sh
scripts/privacy-scan-tracked.sh
```

AIT review path:
`agentic/reviews/boss-idea-response/bir-11a/round-<n>.json`.

### BIR-11B: SearXNG Preflight Command

Scope:

- add a repo-local command that checks base URL, JSON output, endpoint label,
  and `BOSS_IDEA_SEARCH_SEARXNG_NO_PAID_ENGINES=1`;
- verify `/search?q=<probe>&format=json` returns parseable JSON;
- record public-safe preflight evidence under ignored run/review paths.

Deferred scope:

- running a full market discovery crawl;
- managing SearXNG installation.

Acceptance criteria:

- missing base URL fails;
- non-JSON response fails;
- missing no-paid confirmation fails;
- preflight output redacts query credentials and userinfo.

Validation:

```bash
bash -n scripts/boss-idea-searxng-preflight.sh scripts/run-golden-fixtures.sh
scripts/run-golden-fixtures.sh
scripts/validate-agentic-system.sh
scripts/privacy-scan-tracked.sh
git diff --check
```

AIT review path:
`agentic/reviews/boss-idea-response/bir-11b/round-<n>.json`.

### BIR-11C: Live Smoke Wrapper

Scope:

- add a wrapper that runs preflight, market discovery, quality validation, and
  research validation for a provided run id;
- require `--live` and `BOSS_IDEA_LIVE_CRAWL=1`;
- write public-safe live smoke summary under ignored review evidence.

Deferred scope:

- automatic scheduling;
- Hermes execution.

Acceptance criteria:

- deterministic fixtures remain no-network;
- live smoke cannot run with `fixture` provider;
- failures identify the exact failed phase.

AIT review path:
`agentic/reviews/boss-idea-response/bir-11c/round-<n>.json`.

### BIR-11D: Hermes Live Smoke Action

Scope:

- add optional Hermes action contract for the live smoke wrapper;
- keep live smoke out of default validation;
- require explicit operator identity and live gates.

Deferred scope:

- scheduled unattended live runs.

Acceptance criteria:

- Hermes memory is non-authoritative;
- action is manually rerunnable;
- action cannot approve artifacts or decisions.

AIT review path:
`agentic/reviews/boss-idea-response/bir-11d/round-<n>.json`.

## BIR-12: One-Command Boss Idea Workflow

Status: planned.

Owner role: Engineering Manager.

Purpose: provide a single operator command for the normal boss idea response
workflow while preserving manifest authority and review gates.

Slices:

- BIR-12A workflow contract and state machine;
- BIR-12B dry-run plan rendering;
- BIR-12C deterministic execute mode;
- BIR-12D live self-hosted SearXNG execute mode;
- BIR-12E Hermes action and golden fixtures.

Acceptance criteria:

- every step remains independently rerunnable;
- command writes no approval state by itself;
- partial failures leave actionable manifest status;
- default mode is deterministic unless live gates are explicit.

AIT review path:
`agentic/reviews/boss-idea-response/bir-12*/round-<n>.json`.

## BIR-13: Executive Competitor Brief

Status: planned.

Owner role: Product Strategy Lead.

Purpose: generate a boss-facing brief from validated evidence without asking
the reader to inspect raw research artifacts.

Slices:

- BIR-13A artifact schema and Markdown template;
- BIR-13B validator;
- BIR-13C generator;
- BIR-13D golden and negative fixtures;
- BIR-13E Hermes/profile wiring.

Required sections:

- competitor matrix;
- mainstream practice summary;
- build / buy / partner / defer options;
- estimated engineering effort band;
- risks, assumptions, and unknowns;
- next experiment and timebox;
- source mapping to market research evidence.

Acceptance criteria:

- every competitor claim cites a source id;
- recommendation does not bypass go/no-go decision;
- no raw provider text is copied into tracked files.

AIT review path:
`agentic/reviews/boss-idea-response/bir-13*/round-<n>.json`.

## BIR-14: Live Crawler Safety Hardening

Status: planned.

Owner role: Staff Security Engineer.

Purpose: strengthen live crawl safety by recording observed network metadata
and failing closed when live evidence cannot be proven safe.

Slices:

- BIR-14A observed network metadata contract;
- BIR-14B Crawl4AI helper output extension;
- BIR-14C live-mode enforcement;
- BIR-14D redirect/DNS rebinding negative fixtures;
- BIR-14E crawl-log and quality artifact integration.

Acceptance criteria:

- live crawls record final URL and observed IP metadata when available;
- missing observed metadata fails in strict live mode;
- fixture mode remains deterministic;
- URL safety still runs before provider/crawler execution.

AIT review path:
`agentic/reviews/boss-idea-response/bir-14*/round-<n>.json`.

## BIR-15: Provider Health And Fallback Operations

Status: planned.

Owner role: QA Lead.

Purpose: track provider reliability and fallback reasons over time without
letting provider health automatically approve decisions.

Slices:

- BIR-15A provider health schema and retention policy;
- BIR-15B event recording from discovery runs;
- BIR-15C health summary report;
- BIR-15D fallback recommendation rules;
- BIR-15E fixtures, privacy scan, and docs.

Acceptance criteria:

- challenge/captcha events are counted;
- fallback reason taxonomy is consistent;
- provider health is advisory only;
- reports are public-safe and tracked only when scrubbed.

AIT review path:
`agentic/reviews/boss-idea-response/bir-15*/round-<n>.json`.

## BIR-16: Documentation State Cleanup

Status: planned.

Owner role: Tech Writer.

Purpose: remove stale status labels and align source-of-truth docs with the
completed BIR-10A through BIR-10G work.

Completed slices:

- BIR-16A marked BIR-10 parent completed.
- BIR-16B linked Boss Idea overview to the productionization roadmap.
- BIR-16C added profile/source-of-truth references.

Acceptance criteria:

- no document says BIR-10 is planned while all sub-slices are complete;
- no document implies paid search is required;
- no document implies public SearXNG is the production default.

AIT review path:
`agentic/reviews/boss-idea-response/bir-productionization-docs/round-<n>.json`.

## H12: Hermes CI/PR Publishing Decision

Status: deferred pending ADR.

Owner role: Engineering Manager with Staff Security Engineer review.

Purpose: decide whether deferred Hermes CI/PR publishing remains out of scope
or becomes an identity-gated execution feature.

Slices if implemented:

- H12A ADR and threat model;
- H12B dry-run PR publishing payload;
- H12C CI status ingestion;
- H12D identity-gated PR creation;
- H12E golden fixtures and rollback tests.

Acceptance criteria:

- manifests remain authoritative;
- Hermes memory cannot approve or publish by itself;
- PR creation requires explicit identity policy authorization;
- dry-run output is public-safe.

AIT review path:
`agentic/reviews/hermes-adapter/h12*/round-<n>.json`.
