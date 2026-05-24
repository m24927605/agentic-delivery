# Boss Idea Response Implementation Slices

## Purpose

This backlog splits Boss Idea Response System implementation into small,
reviewable slices. Each slice can be designed, implemented, tested, accepted,
and reviewed independently.

## Scope

Active scope:

- implement idea-to-decision workflow on top of the existing Agentic Delivery
  System;
- keep implementation local, public-safe, and manifest-backed;
- provide a controlled Crawl4AI-compatible public web crawl/search path for
  rapid competitor and solution discovery;
- preserve the approval gate for implementation;
- require AIT plus Claude Code review for every slice.

Deferred scope:

- paid market databases;
- authenticated or private website crawling;
- external dashboard;
- PR publishing;
- production deployment automation;
- external identity provider integration.

## Slice Rules

Every slice must include:

- owner role;
- source artifact;
- files touched;
- write scope;
- dependencies;
- acceptance criteria;
- validation command;
- negative-path tests;
- rollback notes;
- AIT review evidence path;
- maximum 5 review rounds;
- Staff+ escalation path.

## BIR-00: Documentation And Profile Baseline

Status: completed.

Owner role: Staff Software Architect.

Source artifact: `docs/architecture/boss-idea-response-system.md`.

Files touched:

- `docs/architecture/boss-idea-response-system.md`
- `docs/architecture/boss-idea-modules/*.md`
- `docs/standards/boss-idea-response-quality-standard.md`
- `docs/backlog/boss-idea-response-slices.md`
- `agentic/profiles/boss-idea-response.yaml`

Acceptance criteria:

- Staff+ roles are defined;
- all seven module design docs exist;
- quality standard defines doc review and code review rules;
- implementation slices are small and independently reviewable;
- each module doc is manually audited against the required section contract
  until a structural linter exists;
- profile validation passes;
- AIT plus Claude Code doc review passes.

Validation command:

```bash
scripts/validate-agentic-system.sh
scripts/validate-hermes-actions.sh
scripts/privacy-scan-tracked.sh
scripts/validate-manifest-schema.sh --all
PROFILE=boss-idea-response scripts/validate-agentic-system.sh
```

Rollback notes: revert BIR documentation and profile files.

AIT review evidence path:

```text
agentic/reviews/boss-idea-response/bir-00/round-<n>.json
agentic/reviews/boss-idea-response/bir-00/decision-log.md
```

Maximum review rounds: 5.

Staff+ escalation path: if round 5 fails, the board chooses whether to split
module docs, reduce scope, or accept a documented documentation risk.

## BIR-01: Idea Intake Command

Status: completed.

Owner role: Staff Platform Engineer.

Source artifact: `docs/architecture/boss-idea-modules/idea-intake.md`.

Files touched:

- `scripts/init-boss-idea-run.sh`
- `agentic/hermes-actions.yaml`
- `agentic/pipeline.yaml`
- `agentic/README.md`
- `agentic/fixtures/boss-idea-response/`

Acceptance criteria:

- valid goal file initializes a planning manifest;
- missing owner, deadline, or response class fails;
- run id and path validation match existing safety rules;
- initialized artifacts are `planned`;
- no artifact is drafted or approved.

Validation command:

```bash
scripts/validate-agentic-system.sh
PROFILE=boss-idea-response scripts/validate-agentic-system.sh
scripts/init-boss-idea-run.sh --dry-run agentic/fixtures/boss-idea-response/valid-idea.md
```

Rollback notes: remove the command, Hermes action, pipeline registration, and
fixtures for this slice.

AIT review evidence path: `agentic/reviews/boss-idea-response/bir-01/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: simplify intake fields or split goal-file parsing from
manifest initialization.

## BIR-02: Market Research Evidence Validator

Status: completed.

Owner role: Market Research Lead.

Source artifact: `docs/architecture/boss-idea-modules/market-research-evidence.md`.

Files touched:

- `scripts/validate-boss-idea-research.sh`
- `agentic/schemas/boss-idea-research.schema.yaml`
- `agentic/hermes-actions.yaml`
- `agentic/README.md`
- `agentic/fixtures/boss-idea-response/`

Acceptance criteria:

- source inventory requires stable reference, access date, and source type;
- key claims require source mapping;
- unsupported inferences must be labeled;
- raw evidence paths stay ignored;
- missing citation negative test fails.

Validation command:

```bash
scripts/validate-agentic-system.sh
scripts/validate-boss-idea-research.sh agentic/fixtures/boss-idea-response/valid-research.md
```

Rollback notes: remove research validator, schema, Hermes action, and fixtures.

AIT review evidence path: `agentic/reviews/boss-idea-response/bir-02/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: reduce citation schema, split source inventory and claim
mapping, or defer automated validation.

## BIR-03: Feasibility Scorecard Validator

Status: completed.

Owner role: Staff QA Architect.

Source artifact: `docs/architecture/boss-idea-modules/feasibility-scoring.md`.

Files touched:

- `scripts/score-boss-idea-feasibility.sh`
- `agentic/schemas/boss-idea-scorecard.schema.yaml`
- `agentic/hermes-actions.yaml`
- `agentic/README.md`
- `agentic/fixtures/boss-idea-response/`

Acceptance criteria:

- score dimensions are required;
- scores must be integers from 1 to 5;
- high risk requires mitigation;
- low confidence requires unknowns or follow-up questions;
- scoring cannot approve implementation.

Validation command:

```bash
scripts/validate-agentic-system.sh
scripts/score-boss-idea-feasibility.sh --dry-run agentic/fixtures/boss-idea-response/valid-scorecard.yaml
```

Rollback notes: remove scorecard command, schema, Hermes action, and fixtures.

AIT review evidence path: `agentic/reviews/boss-idea-response/bir-03/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: simplify scoring dimensions or split score validation
from recommendation mapping.

## BIR-04: Decision Memo Generator And Validator

Status: completed.

Owner role: Staff Technical Writer.

Source artifact: `docs/architecture/boss-idea-modules/boss-decision-memo.md`.

Files touched:

- `scripts/generate-boss-decision-memo.sh`
- `scripts/validate-boss-decision-memo.sh`
- `agentic/schemas/boss-decision-memo.schema.yaml`
- `agentic/hermes-actions.yaml`
- `agentic/README.md`

Acceptance criteria:

- memo includes recommendation, evidence summary, options, risks, time and
  staffing, and next step;
- POC/MVP recommendations require timebox and staffing assumptions;
- memo cannot claim approval unless artifact status is approved;
- missing options negative test fails.

Validation command:

```bash
scripts/validate-agentic-system.sh
scripts/validate-boss-decision-memo.sh agentic/fixtures/boss-idea-response/valid-memo.md
```

Rollback notes: remove memo generator, validator, schema, Hermes action, and fixtures.

AIT review evidence path: `agentic/reviews/boss-idea-response/bir-04/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: keep validator only, defer generation, or simplify memo
template.

## BIR-05: POC/MVP Timebox Planner

Status: completed.

Owner role: Engineering Manager.

Source artifact: `docs/architecture/boss-idea-modules/poc-mvp-timebox.md`.

Files touched:

- `scripts/plan-boss-idea-poc-mvp.sh`
- `scripts/validate-boss-idea-poc-mvp.sh`
- `agentic/hermes-actions.yaml`
- `agentic/README.md`

Acceptance criteria:

- POC/MVP work type is required;
- timebox, scope-in, scope-out, demo path, validation command, and rollback
  notes are required;
- validation command must be repo-local;
- implementation task graph requires approved plan artifact.

Validation command:

```bash
scripts/validate-agentic-system.sh
scripts/validate-boss-idea-poc-mvp.sh agentic/fixtures/boss-idea-response/valid-poc-plan.md
```

Rollback notes: remove planner, validator, Hermes action, and fixtures.

AIT review evidence path: `agentic/reviews/boss-idea-response/bir-05/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: split POC and MVP validators or defer planner
generation.

## BIR-06: Success Metrics Validator

Status: completed.

Owner role: Staff QA Architect.

Source artifact: `docs/architecture/boss-idea-modules/success-metrics.md`.

Files touched:

- `scripts/validate-boss-idea-success-metrics.sh`
- `agentic/schemas/boss-idea-success-metrics.schema.yaml`
- `agentic/hermes-actions.yaml`
- `agentic/README.md`

Acceptance criteria:

- every metric has method, threshold, owner role, and decision mapping;
- evidence path is ignored or public-safe;
- metric must fit the selected timebox;
- metric output cannot automatically record go/no-go.

Validation command:

```bash
scripts/validate-agentic-system.sh
scripts/validate-boss-idea-success-metrics.sh agentic/fixtures/boss-idea-response/valid-metrics.yaml
```

Rollback notes: remove metric validator, schema, Hermes action, and fixtures.

AIT review evidence path: `agentic/reviews/boss-idea-response/bir-06/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: reduce metric fields or split metric schema from
manifest integration.

## BIR-07: Go/No-Go Decision Recorder

Status: completed.

Owner role: Product Strategy Lead.

Source artifact: `docs/architecture/boss-idea-modules/go-no-go-decision.md`.

Files touched:

- `scripts/record-boss-idea-decision.sh`
- `scripts/validate-boss-idea-decision.sh`
- `agentic/hermes-actions.yaml`
- `agentic/identity-policy.yaml`
- `agentic/README.md`

Acceptance criteria:

- valid decisions are go, no-go, defer, pivot, or research-more;
- decision reason and evidence artifacts are required;
- go decision requires metric result;
- mutating action records repo-local actor authorization;
- implementation remains blocked without approved artifacts.

Validation command:

```bash
scripts/validate-agentic-system.sh
scripts/validate-boss-idea-decision.sh agentic/fixtures/boss-idea-response/valid-decision.yaml
```

Rollback notes: remove decision recorder, validator, authorization additions,
Hermes action, and fixtures.

AIT review evidence path: `agentic/reviews/boss-idea-response/bir-07/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: split decision validation and manifest mutation, or keep
decision recording manual through `update-artifact-status.sh`.

## BIR-08: Integrated Golden Fixture

Status: completed.

Owner role: Staff Platform Engineer.

Source artifact: all boss idea response module docs.

Files touched:

- `scripts/run-golden-fixtures.sh`
- `agentic/fixtures/boss-idea-response/`
- `agentic/README.md`

Acceptance criteria:

- fixture covers idea intake through no-go path;
- fixture covers idea intake through POC-approved path;
- fixture covers generated template paths and static valid fixtures;
- negative checks include missing citation, missing timebox, missing metric
  threshold, unknown decision value, unapproved go or implementation input,
  authorization failure, bad evidence or path input, and manifest authority
  failure;
- no-go records cleanly without approved implementation artifacts;
- go cannot record until manifest artifacts are approved;
- approved boss idea artifacts can seed an implementation manifest;
- privacy scan remains clean;
- fixture is deterministic, cleans up generated repo-local and temporary
  output, and does not rely on external network access.

Validation command:

```bash
scripts/validate-agentic-system.sh
scripts/run-golden-fixtures.sh
scripts/privacy-scan-tracked.sh
```

Rollback notes: remove fixture updates and ignored run output.

AIT review evidence path: `agentic/reviews/boss-idea-response/bir-08/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: split fixtures by module or defer integrated fixture
until BIR-01 through BIR-07 are complete.

## BIR-09: Market Competitor Search Automation

Status: completed.

Owner role: Market Research Lead.

Source artifact: `docs/architecture/boss-idea-modules/market-research-evidence.md`.

Files touched:

- `scripts/collect-boss-idea-research.sh`
- `scripts/run-golden-fixtures.sh`
- `scripts/validate-agentic-system.sh`
- `agentic/schemas/boss-idea-market-search.schema.yaml`
- `agentic/fixtures/boss-idea-response/`
- `agentic/hermes-actions.yaml`
- `agentic/pipeline.yaml`
- `agentic/README.md`
- `docs/architecture/boss-idea-modules/market-research-evidence.md`
- `docs/backlog/boss-idea-response-slices.md`

Acceptance criteria:

- command derives a market search query pack from boss idea intake;
- command consumes public-safe search results from a provider adapter contract;
- generated research artifact passes `validate-boss-idea-research.sh`;
- search results require competitor and mainstream-practice signals;
- missing reference, missing required signal, bad query id, bad source type,
  future access date, unsafe output path, oversized claim, multiline claim, or
  unsafe URL scheme fails;
- existing generated research cannot be overwritten without `--force`;
- generated raw evidence path stays under ignored run evidence;
- command updates the planning manifest with research artifact and evidence
  metadata without approving artifacts;
- Hermes and pipeline contracts expose the command.

Validation command:

```bash
scripts/collect-boss-idea-research.sh --dry-run <run-id>
scripts/collect-boss-idea-research.sh <run-id> --search-results agentic/fixtures/boss-idea-response/valid-market-search-results.yaml --output agentic/runs/<run-id>/market-research.md
scripts/validate-boss-idea-research.sh agentic/runs/<run-id>/market-research.md
scripts/run-golden-fixtures.sh
```

Rollback notes: remove the collector command, search schema, fixtures, Hermes
action, pipeline references, and generated golden fixture coverage.

AIT review evidence path: `agentic/reviews/boss-idea-response/bir-09/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: if round 5 fails, split query-pack generation from
research artifact generation or keep only the provider contract while deferring
artifact generation.

## BIR-10: Crawl4AI Market Discovery Adapter

Status: planned.

Owner role: Market Research Lead.

Source artifact: `docs/architecture/boss-idea-modules/crawl4ai-market-discovery-adapter.md`.

Files touched:

- `docs/architecture/boss-idea-modules/crawl4ai-market-discovery-adapter.md`
- `docs/adr/006-boss-idea-crawl4ai-market-discovery.md`
- `docs/adr/007-boss-idea-no-paid-search-provider.md`
- `docs/architecture/boss-idea-modules/searxng-market-discovery-provider.md`
- `docs/runbooks/boss-idea-no-paid-market-search.md`
- `docs/architecture/boss-idea-response-system.md`
- `agentic/profiles/boss-idea-response.yaml`
- `docs/backlog/boss-idea-response-slices.md`
- `scripts/crawl-boss-idea-market.sh`
- `agentic/schemas/boss-idea-market-candidate-urls.schema.yaml`
- Crawl4AI adapter helper files and fixtures
- `agentic/hermes-actions.yaml`
- `agentic/pipeline.yaml`
- `agentic/README.md`

Acceptance criteria:

- command consumes a Boss Idea market query pack;
- command supports query-to-URL discovery through an approved public search
  provider contract;
- command supports Crawl4AI-backed public page crawling;
- command can normalize crawled public pages into
  `boss-idea-market-search` results;
- normalized results can feed `collect-boss-idea-research.sh` without manual
  editing;
- crawler blocks localhost, private IP ranges, link-local addresses,
  metadata-service targets, DNS rebinding, unsafe redirects, TLS bypass,
  non-http(s) schemes, and output path traversal;
- crawler enforces robots policy, per-host rate limits, max redirects, max
  pages, timeout, content length, and raw evidence path limits;
- crawler records provider, mode, pinned Crawl4AI version, evidence paths, and
  any Staff+ waiver in `boss_idea_market_crawl` manifest metadata;
- live search providers require Staff Security Engineer and Staff Software
  Architect approval before implementation release;
- default production discovery prefers no-paid providers; Brave and other paid
  search APIs are optional fallback only;
- SearXNG provider implementation can convert query pack entries into
  candidate URLs without paid API credentials;
- default golden fixtures use local HTML or controlled fixture inputs and do
  not require live internet;
- live crawl smoke tests are opt-in and run before enabling or upgrading a live
  provider;
- production-grade competitor discovery requires live crawl/search evidence or
  a manifest-recorded Staff+ waiver;
- no crawl output can approve artifacts, decisions, roadmap, budget, or
  implementation.

Validation command:

```bash
scripts/crawl-boss-idea-market.sh --dry-run <run-id>
BOSS_IDEA_LIVE_CRAWL=1 scripts/crawl-boss-idea-market.sh <run-id> --from-query-pack --search-provider <provider> --output agentic/runs/<run-id>/market-search-results.yaml
scripts/crawl-boss-idea-market.sh <run-id> --seeds agentic/fixtures/boss-idea-response/market-crawl-seeds.yaml --output agentic/runs/<run-id>/market-search-results.yaml
scripts/collect-boss-idea-research.sh <run-id> --search-results agentic/runs/<run-id>/market-search-results.yaml --output agentic/runs/<run-id>/market-research.md
scripts/run-golden-fixtures.sh
```

The live command must use an approved live provider, not `fixture` or `--seeds`.
Fixture and seed replay commands must run without `BOSS_IDEA_LIVE_CRAWL=1`.

Negative-path tests:

- missing query pack fails;
- missing search provider or seeds fail;
- unsupported URL scheme fails;
- localhost, private IP, link-local, and metadata-service URLs fail;
- DNS rebinding and redirect-to-private targets fail;
- redirect-chain DNS rebinding fails;
- robots disallow, TLS verification failure, and per-host rate violations fail;
- user-agent format mismatch fails;
- content truncation without a crawl-log record fails;
- Crawl4AI DOM, JavaScript, schema, or LLM extraction output fails;
- consecutive policy-block and total-failure circuit breakers fail fast;
- output outside the run directory fails;
- oversized page or page count fails;
- raw crawl evidence path not ignored by git fails;
- generated result missing competitor or mainstream-practice signal fails.

Rollback notes: remove the Crawl4AI adapter command, helper files, fixtures,
Hermes action, pipeline references, README updates, and ignored crawl output.
Keep BIR-09 collector and validators because they remain provider-neutral.

AIT review evidence path: `agentic/reviews/boss-idea-response/bir-10/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: if round 5 fails, keep the BIR-09 provider contract and
decide whether to split URL safety, Crawl4AI execution, and result
normalization into separate implementation slices.

Implementation sub-slices:

- BIR-10A deterministic adapter foundation: completed. Adds the repo-local
  command, candidate URL schema, fixture seed provider, URL safety checks,
  ignored raw evidence, normalized market-search output, Hermes registration,
  and golden fixture coverage without live internet. Operator note: `--force`
  removes prior ignored files under `agentic/runs/<run-id>/crawl4ai/raw/`; do
  not place manual evidence in that raw directory.
- BIR-10B live Crawl4AI execution: completed. Adds approved live Crawl4AI
  runtime execution behind `--live` and `BOSS_IDEA_LIVE_CRAWL=1`, with version
  pinning, live smoke evidence, and no default golden internet dependency.
  Until BIR-10C ships, live execution accepts only explicit `live_seed`
  candidate files whose entries set `live_approved: true`; production-grade
  competitor discovery still requires the BIR-10C query-to-URL provider. The
  wrapper performs pre/post DNS checks around the Crawl4AI subprocess; exact
  connect-time IP observation remains a BIR-10C hardening item. The live helper
  enforces byte caps on returned markdown because Crawl4AI does not expose raw
  response bytes through this helper boundary.
- BIR-10C approved query-to-URL provider: completed. Adds Brave Search as the
  first Staff Security Engineer and Staff Software Architect approved live
  search provider using `BOSS_IDEA_SEARCH_BRAVE_API_KEY` and the
  `BOSS_IDEA_SEARCH_<PROVIDER>_*` credential contract. Default golden coverage
  uses tracked fixture JSON and a fake Crawl4AI helper, not public internet.
  Brave candidates are `live_approved` at the provider level after the provider
  itself is approved; future providers must document whether approval is
  provider-level or per-URL.
- BIR-10D SearXNG no-paid provider design: completed for documentation.
  Adds ADR 007, the SearXNG provider design, the no-paid market search runbook,
  and updates the Boss Idea adapter/profile/research contracts so Brave is not
  the required live search path. Implementation remains a separate slice that
  must add fixture JSON, provider parsing, candidate schema validation,
  manifest metadata, Hermes/pipeline coverage, validation, and AIT review.
- BIR-10E SearXNG no-paid provider implementation: completed. Adds
  `--search-provider searxng` to `scripts/crawl-boss-idea-market.sh`, supports
  `BOSS_IDEA_SEARCH_SEARXNG_*` environment variables, maps JSON results to
  candidate URLs, supports deterministic fixture JSON without public internet,
  records no-paid manifest metadata, and runs Crawl4AI through the existing
  live crawl path for live candidates.
- BIR-10F local browser and HTML search fallback implementation: completed.
  Adds `duckduckgo_html` and `local_browser_search` fallback providers, fixture
  coverage without public internet, lower-trust metadata, local browser helper
  integration for operator-provided Chrome/Playwright live smoke, and negative
  tests for missing live gates and malformed provider output.
- BIR-10G provider arbitration and evidence quality scoring: planned. Defines
  how provider priority, duplicate domains, source diversity, freshness,
  fallback state, and evidence gaps are surfaced to Market Research Lead and
  Staff+ reviewers without approving decisions automatically.

## BIR-10D: SearXNG No-Paid Provider Design

Status: documentation completed, implementation planned in BIR-10E.

Owner role: Market Research Lead.

Dependencies: BIR-10A deterministic adapter foundation, BIR-10B live Crawl4AI
execution, and BIR-10C optional Brave provider.

Source artifacts:

- `docs/adr/007-boss-idea-no-paid-search-provider.md`
- `docs/architecture/boss-idea-modules/searxng-market-discovery-provider.md`
- `docs/runbooks/boss-idea-no-paid-market-search.md`

Files touched:

- `docs/adr/007-boss-idea-no-paid-search-provider.md`
- `docs/architecture/boss-idea-modules/searxng-market-discovery-provider.md`
- `docs/runbooks/boss-idea-no-paid-market-search.md`
- `docs/architecture/boss-idea-modules/crawl4ai-market-discovery-adapter.md`
- `docs/architecture/boss-idea-modules/market-research-evidence.md`
- `docs/architecture/boss-idea-response-system.md`
- `docs/adr/006-boss-idea-crawl4ai-market-discovery.md`
- `agentic/profiles/boss-idea-response.yaml`
- `docs/backlog/boss-idea-response-slices.md`

Acceptance criteria:

- ADR 007 states that no-paid providers are preferred before paid search APIs.
- SearXNG is documented as the default no-paid query-to-URL provider for the
  next implementation slice.
- Brave remains approved as optional paid fallback, not required default.
- SearXNG is bound to query-to-URL discovery only; Crawl4AI remains the crawler
  for approved candidate pages.
- The SearXNG design defines purpose, scope, deferred scope, workflow, artifact
  schema, CLI/env/manifest contract, failure behavior, validation strategy,
  test cases, acceptance criteria, doc review standard, code review standard,
  rollback notes, references, and review expectations.
- The runbook explains no-paid setup, live command shape, evidence inspection,
  fallback handling, and failure triage.
- The Boss Idea profile, system doc, market evidence doc, and Crawl4AI adapter
  all reference the no-paid provider decision.
- Follow-on implementation remains split into small slices rather than mixing
  design, implementation, local browser fallback, and arbitration in one change.

Validation command:

```bash
git diff --check
scripts/validate-agentic-system.sh
PROFILE=boss-idea-response scripts/validate-agentic-system.sh
scripts/privacy-scan-tracked.sh
```

Negative-path tests required for BIR-10E implementation:

- SearXNG live run without `BOSS_IDEA_SEARCH_SEARXNG_BASE_URL` fails;
- SearXNG live run without
  `BOSS_IDEA_SEARCH_SEARXNG_NO_PAID_ENGINES=1` fails;
- malformed SearXNG JSON fails;
- missing `results` array fails;
- paid engine marker in the no-paid path fails unless a Staff+ waiver selects a
  paid provider;
- local SearXNG base-URL IP exceptions do not extend to candidate URLs passed
  to Crawl4AI;
- `no_paid_engine_policy: unknown` in evidence used for a boss decision memo
  fails;
- empty result set fails with an actionable provider error;
- private, localhost, link-local, metadata-service, non-http(s), or malformed
  result URLs fail before Crawl4AI;
- result count above hard caps fails;
- credentials or raw provider response in tracked files fail privacy scan;
- fallback provider output without fallback metadata fails.

Rollback notes: remove ADR 007, the SearXNG provider design, the no-paid
runbook, and cross-references from the Boss Idea profile/system/market/adapter
docs. Keep BIR-10A/B/C because deterministic crawl, live seed crawl, and
optional Brave remain valid.

AIT review evidence path:
`agentic/reviews/boss-idea-response/bir-10d/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: if round 5 fails, keep Brave optional, defer SearXNG
implementation, and record whether the default no-paid requirement is satisfied
through `duckduckgo_html`, `local_browser_search`, self-hosted SearXNG, or a
temporary Staff+ waiver.

## BIR-10E: SearXNG No-Paid Provider Implementation

Status: completed.

Owner role: Staff Platform Engineer.

Dependencies: BIR-10D SearXNG No-Paid Provider Design.

Source artifacts:

- `docs/adr/007-boss-idea-no-paid-search-provider.md`
- `docs/architecture/boss-idea-modules/searxng-market-discovery-provider.md`
- `docs/architecture/boss-idea-modules/crawl4ai-market-discovery-adapter.md`

Files touched:

- `scripts/crawl-boss-idea-market.sh`
- `scripts/run-golden-fixtures.sh`
- `scripts/validate-agentic-system.sh`
- `agentic/schemas/boss-idea-market-candidate-urls.schema.yaml`
- `agentic/fixtures/boss-idea-response/searxng-search-fixture.json`
- `agentic/hermes-actions.yaml`
- `docs/architecture/boss-idea-modules/crawl4ai-market-discovery-adapter.md`
- `docs/architecture/boss-idea-modules/searxng-market-discovery-provider.md`
- `docs/backlog/boss-idea-response-slices.md`

Acceptance criteria:

- `scripts/crawl-boss-idea-market.sh` accepts `--search-provider searxng`.
- SearXNG fixture JSON can convert query pack entries into candidate URLs
  without live internet.
- Live SearXNG runs require `--live`, `BOSS_IDEA_LIVE_CRAWL=1`,
  `BOSS_IDEA_SEARCH_SEARXNG_BASE_URL`, and
  `BOSS_IDEA_SEARCH_SEARXNG_NO_PAID_ENGINES=1`.
- `--live --from-query-pack` can default to `searxng` when the required
  SearXNG environment is present.
- SearXNG candidates preserve provider metadata: endpoint label, query, public
  search URL or fixture marker, locale, category, engine names, fallback state,
  rank, and no-paid engine policy.
- Candidate URLs still pass BIR-10 URL safety before Crawl4AI or fixture crawl.
- Deterministic golden fixtures do not call public internet.
- Manifest metadata records `provider: searxng`, `no_paid_provider: true`,
  `provider_priority: 1`, endpoint label, source count, and evidence paths.
- Optional gateway auth token is never written to tracked files.
- Brave remains optional paid fallback.

Validation command:

```bash
bash -n scripts/crawl-boss-idea-market.sh scripts/run-golden-fixtures.sh
ruby -rjson -e 'JSON.parse(File.read("agentic/fixtures/boss-idea-response/searxng-search-fixture.json"))'
scripts/run-golden-fixtures.sh
scripts/validate-agentic-system.sh
PROFILE=boss-idea-response scripts/validate-agentic-system.sh
scripts/validate-hermes-actions.sh
scripts/privacy-scan-tracked.sh
git diff --check
```

Negative-path tests:

- SearXNG without live flags or fixture fails before public network search.
- Live SearXNG without base URL fails.
- Live SearXNG without no-paid engine confirmation fails.
- Malformed SearXNG fixture JSON fails.
- Missing `results` array fails.
- Paid engine marker fails in the no-paid provider path.
- Private, metadata-service, localhost, non-http(s), and malformed result URLs
  are filtered before Crawl4AI; a fully filtered result set fails.
- SearXNG fixture candidates retain metadata and do not satisfy production
  live discovery.

Rollback notes: remove the `searxng` provider branch, fixture JSON, schema
provider entry, golden fixture coverage, Hermes fixture reference, and BIR-10E
contract updates. Keep BIR-10D because the no-paid decision remains valid.

AIT review evidence path:
`agentic/reviews/boss-idea-response/bir-10e/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: if round 5 fails, keep BIR-10D as design authority,
leave Brave optional, and choose whether to retry SearXNG implementation,
advance BIR-10F fallback design, or record a temporary Staff+ waiver.

## BIR-10F: HTML And Local Browser Search Fallback Implementation

Status: completed.

Owner role: Staff Platform Engineer.

Dependencies: BIR-10E SearXNG No-Paid Provider Implementation.

Source artifacts:

- `docs/adr/007-boss-idea-no-paid-search-provider.md`
- `docs/runbooks/boss-idea-no-paid-market-search.md`
- `docs/architecture/boss-idea-modules/crawl4ai-market-discovery-adapter.md`

Files touched:

- `scripts/crawl-boss-idea-market.sh`
- `scripts/lib/boss_idea_local_browser_search.py`
- `scripts/run-golden-fixtures.sh`
- `scripts/validate-agentic-system.sh`
- `agentic/schemas/boss-idea-market-candidate-urls.schema.yaml`
- `agentic/fixtures/boss-idea-response/duckduckgo-html-fixtures/`
- `agentic/fixtures/boss-idea-response/local-browser-search-fixture.json`
- `agentic/hermes-actions.yaml`
- `docs/runbooks/boss-idea-no-paid-market-search.md`
- `docs/architecture/boss-idea-modules/crawl4ai-market-discovery-adapter.md`
- `docs/backlog/boss-idea-response-slices.md`

Acceptance criteria:

- `scripts/crawl-boss-idea-market.sh` accepts `--search-provider
  duckduckgo_html` and `--search-provider local_browser_search`.
- Both providers require `--live` and `BOSS_IDEA_LIVE_CRAWL=1` unless a
  deterministic fixture is supplied.
- DuckDuckGo HTML fixture pages parse result anchors into candidate URLs
  without public internet.
- Local browser fixture JSON can produce candidate URLs without launching
  Chrome.
- Live local browser search is delegated to
  `scripts/lib/boss_idea_local_browser_search.py`, which uses an isolated
  Playwright browser context when the operator provides a compatible runtime.
- Both providers write lower-trust provider metadata with
  `fallback_from: searxng` and `lower_trust_fallback: true`.
- Candidate URLs still pass BIR-10 URL safety before Crawl4AI or fixture crawl.
- Captcha or bot-detection is not bypassed; the run must stop or use another
  approved provider.
- Default golden fixtures remain no-network and no-Chrome.

Validation command:

```bash
bash -n scripts/crawl-boss-idea-market.sh scripts/run-golden-fixtures.sh
python3 -m py_compile scripts/lib/boss_idea_local_browser_search.py
scripts/run-golden-fixtures.sh
scripts/validate-agentic-system.sh
PROFILE=boss-idea-response scripts/validate-agentic-system.sh
scripts/validate-hermes-actions.sh
scripts/privacy-scan-tracked.sh
git diff --check
```

Negative-path tests:

- `duckduckgo_html` without live flags or fixture fails.
- Empty DuckDuckGo HTML fixture fails with no parseable results.
- DuckDuckGo HTML challenge markers fail instead of being bypassed.
- `local_browser_search` without live flags or fixture fails.
- Local browser custom search URL pointing at private or loopback hosts fails
  before the browser helper starts.
- Local browser fixture missing `results` fails.
- Oversized local browser helper stdout fails before parsing.
- Fallback provider candidate metadata must label lower trust and fallback
  source.

Rollback notes: remove the two fallback providers, helper script, fixtures,
schema provider entries, golden tests, and runbook/backlog updates. Keep
BIR-10E because SearXNG remains the default no-paid provider.

AIT review evidence path:
`agentic/reviews/boss-idea-response/bir-10f/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: if round 5 fails, keep SearXNG as the only no-paid
production provider and defer fallback providers until the boundary can be
reviewed safely.

## Review Expectations

Each slice must pass validation and AIT plus Claude Code review before the next
dependent slice starts. If a review fails, fix the finding and rerun. If round 5
fails, the Staff+ board records a decision and continues through the selected
path rather than leaving the delivery blocked indefinitely.
