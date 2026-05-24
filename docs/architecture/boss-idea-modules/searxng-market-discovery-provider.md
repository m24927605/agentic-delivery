# SearXNG Market Discovery Provider Module

## Purpose

SearXNG Market Discovery Provider turns a Boss Idea market research query pack
into candidate public URLs without requiring a paid search API.

It is a query-to-URL provider only. Crawl4AI remains responsible for crawling
approved candidate pages and producing markdown evidence. Market research
artifacts still need citations, confidence labels, and public-safe summaries.
SearXNG result snippets are discovery hints, not page-content evidence.

## Scope

Active scope:

- consume `agentic/runs/<run-id>/market-research-query-pack.yaml`;
- query an operator-approved SearXNG endpoint that supports JSON output;
- require the operator-approved endpoint to use no-paid engines by default;
- map SearXNG results into the BIR-10 candidate URL schema;
- record provider, endpoint label, query string, result rank, locale, category,
  fallback state, and retrieval time;
- enforce the same public URL safety policy before Crawl4AI receives URLs;
- cap results per query and per run;
- support deterministic fixture JSON for golden validation;
- feed candidate URLs into `scripts/crawl-boss-idea-market.sh`;
- keep live endpoint responses and raw crawl evidence in ignored run paths.

Deferred scope:

- hosting SearXNG inside this repository;
- bypassing SearXNG engine rate limits;
- accepting paid SearXNG engines as the default provider configuration;
- authenticated, customer-internal, or paywalled search;
- scraping search result pages as the default provider;
- local Chrome fallback implementation;
- provider arbitration beyond the priority order defined in ADR 007;
- automatic approval of market research or implementation.

## Workflow

```text
boss idea run
  -> market-research-query-pack.yaml
  -> searxng provider
  -> SearXNG /search?format=json
  -> candidate URL list
  -> BIR-10 URL safety validation
  -> Crawl4AI markdown crawl
  -> market-search-results.yaml
  -> market-research.md
```

The provider does not decide which competitor matters most. It supplies ranked
candidate sources that Market Research Lead and Staff+ reviewers can evaluate.

## Artifact Schema

Provider input:

- `agentic/runs/<run-id>/market-research-query-pack.yaml`
- required fields per query: `id`, `query`, `purpose`

Candidate output:

- `agentic/runs/<run-id>/market-candidate-urls.yaml`
- schema: `agentic/schemas/boss-idea-market-candidate-urls.schema.yaml`

Each `searxng` candidate must include:

- `id`;
- `query_id`;
- `url`;
- `title`;
- `snippet`;
- `provider: searxng`;
- `source_type`;
- `signal`;
- `rank`;
- `retrieved_at`;
- `live_approved: true` after provider approval;
- `provider_metadata`.

`provider_metadata` must include:

```yaml
provider: searxng
endpoint_label: <public-safe endpoint label, not a secret>
query: <query string>
search_url: <public-safe SearXNG search URL without credentials>
locale: <locale or default>
category: <SearXNG category or default>
engine_names:
  - <engine names if returned and public-safe>
fallback_from: <provider id or empty>
result_rank: <integer>
no_paid_engine_policy: <operator-confirmed | unknown>
```

The provider must not write credentials, private endpoint tokens, cookies,
browser profile paths, or raw search response bodies to tracked files.
The provider must use SearXNG URL, title, and snippet fields only for discovery
metadata. It must not treat SearXNG snippets as crawled page content and must
not bypass Crawl4AI URL safety, robots, TLS, rate, redirect, or content-size
policy.
`no_paid_engine_policy: unknown` is allowed only for fixture-mode or
non-production validation metadata and must never appear in evidence used for a
boss decision memo.

## CLI / Manifest / Pipeline Contract

Command shape:

```bash
BOSS_IDEA_LIVE_CRAWL=1 \
BOSS_IDEA_SEARCH_SEARXNG_BASE_URL=http://127.0.0.1:8080/search \
scripts/crawl-boss-idea-market.sh <run-id> \
  --live \
  --from-query-pack \
  --search-provider searxng \
  --output agentic/runs/<run-id>/market-search-results.yaml
```

Environment variables:

- `BOSS_IDEA_SEARCH_SEARXNG_BASE_URL`: required for live SearXNG runs.
- `BOSS_IDEA_SEARCH_SEARXNG_API_KEY`: optional only when an operator-approved
  self-hosted gateway requires a private access token; never required by this
  repository and never written to tracked files. This token is for gateway
  authentication only and must not be used to enable paid SearXNG engines.
- `BOSS_IDEA_SEARCH_SEARXNG_ENDPOINT_LABEL`: public-safe label recorded in
  manifests and candidate metadata.
- `BOSS_IDEA_SEARCH_SEARXNG_TIMEOUT_SECONDS`: optional, default 10, hard cap 30.
- `BOSS_IDEA_SEARCH_SEARXNG_RESULTS_PER_QUERY`: optional, default 5, hard cap
  5 to match the BIR-10 per-query crawl cap.
- `BOSS_IDEA_SEARCH_SEARXNG_LOCALE`: optional locale parameter.
- `BOSS_IDEA_SEARCH_SEARXNG_CATEGORY`: optional category parameter.
- `BOSS_IDEA_SEARCH_SEARXNG_FIXTURE`: deterministic fixture JSON path for
  no-network tests.
- `BOSS_IDEA_SEARCH_SEARXNG_NO_PAID_ENGINES`: must be `1` for production live
  runs to record that the selected SearXNG endpoint is not configured to use
  paid engines as the default provider path.

Manifest metadata must record:

```yaml
boss_idea_market_crawl:
  provider: searxng
  mode: searxng
  no_paid_provider: true
  provider_priority: 1
  provider_endpoint_label: <label>
  candidate_urls_path: agentic/runs/<run-id>/market-candidate-urls.yaml
  results_path: agentic/runs/<run-id>/market-search-results.yaml
  raw_evidence_path: agentic/runs/<run-id>/crawl4ai/raw/
  crawl_log_path: agentic/runs/<run-id>/crawl4ai/crawl-log.yaml
```

The Crawl4AI adapter manifest contract still applies. This example shows the
SearXNG-specific keys and changed values; implementation must preserve common
fields such as `crawl4ai_version`, `live_smoke_evidence_path` when applicable,
and any valid Staff+ `waiver`.

The command must fail if `searxng` is selected without both `--live` and
`BOSS_IDEA_LIVE_CRAWL=1`, except when `BOSS_IDEA_SEARCH_SEARXNG_FIXTURE` is
used by deterministic validation.

The deterministic fixture path records `provider: searxng`, `mode: fixture`,
and `no_paid_provider: true`. It is validation evidence only and does not
satisfy production-grade live discovery.

Default-provider rule: if `--from-query-pack` and `--live` are set and
`--search-provider` is omitted, the command resolves to `searxng` only when the
required `BOSS_IDEA_SEARCH_SEARXNG_*` environment is present. Omitted
`--search-provider` still fails when the SearXNG environment is absent.

## Failure Behavior

Block provider completion when:

- the query pack is missing or malformed;
- SearXNG base URL is missing for a live run;
- production live run does not set
  `BOSS_IDEA_SEARCH_SEARXNG_NO_PAID_ENGINES=1`;
- SearXNG base URL is not `http` or `https`;
- SearXNG endpoint resolves to a blocked IP class unless the endpoint is an
  explicit local operator endpoint used only to reach the self-hosted search
  service, not as a crawl candidate;
- provider response is not valid JSON;
- provider response content type is not JSON;
- response does not contain a results array;
- response or operator metadata indicates a paid engine is being used as the
  default no-paid provider path;
- result URL is missing, malformed, non-http(s), private, link-local,
  localhost, metadata-service, or otherwise blocked by BIR-10 policy;
- result count exceeds configured caps;
- all results are filtered by URL policy;
- candidate metadata lacks query id, provider id, rank, or retrieval time;
- fallback provider output is not labeled;
- raw provider response would be tracked.

Escalate rather than block when:

- SearXNG returns too few relevant sources but at least one public source
  remains;
- SearXNG engines disagree or return duplicate domains;
- the provider is unavailable and the operator wants to use
  `duckduckgo_html`, `local_browser_search`, or manual `seed_replay`.

## Validation Strategy

Validation must include:

- shell syntax for the wrapper command;
- fixture SearXNG JSON parsed without public internet;
- candidate schema validation;
- provider metadata validation;
- no-paid engine policy validation;
- URL safety negative paths before Crawl4AI invocation;
- fixture Crawl4AI helper path that proves provider candidates feed downstream
  market research;
- privacy scan proving fixture and metadata contain no credentials;
- AIT plus Claude Code review.

Default validation must not require a running SearXNG instance.

Live smoke validation is manual and opt-in:

```bash
BOSS_IDEA_LIVE_CRAWL=1 \
BOSS_IDEA_SEARCH_SEARXNG_BASE_URL=http://127.0.0.1:8080/search \
BOSS_IDEA_SEARCH_SEARXNG_ENDPOINT_LABEL=local-searxng \
scripts/crawl-boss-idea-market.sh <run-id> \
  --live \
  --from-query-pack \
  --search-provider searxng \
  --output agentic/runs/<run-id>/market-search-results.yaml
```

## Test Cases

Positive tests:

- fixture JSON with public result URLs becomes candidate URLs;
- duplicate domains are retained only within configured caps;
- candidate URLs feed Crawl4AI fixture helper and produce market-search
  results;
- manifest records `provider: searxng` and `no_paid_provider: true`.

Negative tests:

- missing base URL fails;
- missing no-paid-engine confirmation fails in production live mode;
- malformed JSON fails;
- missing `results` fails;
- paid engine marker fails unless a Staff+ waiver explicitly selects a paid
  provider;
- non-http result URL fails;
- private or metadata-service result URL fails before Crawl4AI;
- more than the hard cap of results fails;
- missing query id fails;
- tracked raw provider response fails privacy validation.
- `no_paid_engine_policy: unknown` appears in evidence used for a boss decision
  memo fails.

## Acceptance Criteria

- Boss Idea market discovery has a no-paid live provider path.
- Brave is no longer required for production competitor discovery.
- SearXNG candidate URLs can feed the existing Crawl4AI adapter without manual
  editing.
- Default golden fixtures remain deterministic and no-network.
- Live provider evidence records enough metadata for reviewers to reproduce or
  challenge the source set.
- No provider output can approve artifacts, roadmap, budget, or implementation.

## Doc Review Standard

Claude Code review must verify that the provider is no-paid by default,
separates search from crawling, records reproducibility metadata, preserves URL
safety, and keeps paid providers optional.

## Code Review Standard

Implementation review must verify endpoint validation, fixture coverage,
candidate schema mapping, URL safety before Crawl4AI, manifest metadata, no
credential leakage, no-network golden tests, no-paid engine confirmation, and
negative paths for malformed provider output.

Implementation review must also require a boundary test proving that any
local-IP exception for the SearXNG base URL does not extend to candidate URLs
passed to Crawl4AI.

## Rollback

Remove the `searxng` provider branch, fixture JSON, Hermes/pipeline references,
and live smoke runbook entries. Keep BIR-10A/B/C because fixture, live seed,
and optional Brave behavior remain valid.

## References

- SearXNG documentation: https://docs.searxng.org/
- SearXNG search API: https://docs.searxng.org/dev/search_api.html
- Boss Idea Crawl4AI adapter: `docs/architecture/boss-idea-modules/crawl4ai-market-discovery-adapter.md`
- No-paid provider ADR: `docs/adr/007-boss-idea-no-paid-search-provider.md`
- Fixture JSON: `agentic/fixtures/boss-idea-response/searxng-search-fixture.json`
