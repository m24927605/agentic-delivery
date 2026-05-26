# Boss Idea No-Paid Market Search Runbook

## Purpose

This runbook explains how to run Boss Idea market discovery without paid search
APIs. The preferred path is a self-hosted SearXNG endpoint for query-to-URL
discovery and Crawl4AI for approved page crawling.

## Provider Priority

Use providers in this order:

1. `searxng`: default no-paid provider through a self-hosted endpoint.
2. `duckduckgo_html`: no-paid fallback when SearXNG is unavailable and policy
   allows HTML result extraction.
3. `local_browser_search`: no-paid fallback using isolated local Chrome or
   Chromium browser automation.
4. `brave`: optional paid provider only.
5. `fixture` or `seed_replay`: deterministic tests and emergency replay only.

## SearXNG Prerequisites

Operator responsibilities:

- provide a self-hosted SearXNG endpoint that supports JSON output;
- confirm the endpoint uses no-paid engines by default;
- keep the endpoint URL in environment variables, not tracked files;
- configure SearXNG engines and rate limits outside this repository;
- record a public-safe endpoint label such as `local-searxng` or
  `team-searxng`;
- verify that the endpoint is intended for internal research automation.

This repository does not run the SearXNG service. The operating standard is
self-hosted SearXNG, either on the operator workstation at `127.0.0.1` or on a
team-owned internal host. Public SearXNG instances are not the production
default because their enabled formats, engines, rate limits, and availability
are outside team control.

The self-hosted instance must satisfy these checks before live Boss Idea runs:

- `/search` accepts `q=<query>` and `format=json`;
- JSON output is enabled in SearXNG `settings.yml` under the `search` section;
- default engines are no-paid engines approved by Staff Security Engineer and
  Market Research Lead;
- limiter, rate, and outbound policy are configured outside this repository;
- endpoint logs do not persist sensitive boss idea text beyond the team's
  approved retention policy;
- endpoint is reachable only from approved operator or internal team networks.

## Environment

Required for live no-paid search:

```bash
export BOSS_IDEA_LIVE_CRAWL=1
export BOSS_IDEA_SEARCH_SEARXNG_BASE_URL="http://127.0.0.1:8080/search"
export BOSS_IDEA_SEARCH_SEARXNG_ENDPOINT_LABEL="local-searxng"
export BOSS_IDEA_SEARCH_SEARXNG_NO_PAID_ENGINES=1
```

Optional:

```bash
export BOSS_IDEA_SEARCH_SEARXNG_TIMEOUT_SECONDS=10
export BOSS_IDEA_SEARCH_SEARXNG_RESULTS_PER_QUERY=5
export BOSS_IDEA_SEARCH_SEARXNG_LOCALE="en-US"
export BOSS_IDEA_SEARCH_SEARXNG_CATEGORY="general"
```

Do not export paid provider keys unless explicitly using a paid provider.

## Preflight

Before a live crawl, run the standalone SearXNG preflight against the
self-hosted endpoint:

```bash
BOSS_IDEA_SEARCH_SEARXNG_BASE_URL="http://127.0.0.1:8080/search" \
BOSS_IDEA_SEARCH_SEARXNG_ENDPOINT_LABEL="local-searxng" \
BOSS_IDEA_SEARCH_SEARXNG_NO_PAID_ENGINES=1 \
scripts/boss-idea-searxng-preflight.sh \
  --evidence agentic/runs/<run-id>/searxng-preflight.yaml
```

The preflight verifies the base URL, endpoint label, no-paid-engine operator
confirmation, and JSON output from `q=<probe>&format=json`. It does not store
raw SearXNG JSON or raw page bodies. Evidence is public-safe, advisory-only,
and must stay under ignored `agentic/runs/` or `agentic/reviews/` paths.

Do not put userinfo or credential-like query parameters in the SearXNG URL.
The preflight rejects those URLs and redacts them in stdout and evidence.

## Live Smoke Wrapper

For the BIR-11C live smoke, use the wrapper so the same run records preflight,
market discovery, quality validation, and research validation phases:

```bash
BOSS_IDEA_LIVE_CRAWL=1 \
BOSS_IDEA_SEARCH_SEARXNG_BASE_URL="http://127.0.0.1:8080/search" \
BOSS_IDEA_SEARCH_SEARXNG_ENDPOINT_LABEL="local-searxng" \
BOSS_IDEA_SEARCH_SEARXNG_NO_PAID_ENGINES=1 \
scripts/run-boss-idea-live-smoke.sh --live --force <run-id>
```

The wrapper supports only `--search-provider searxng` in this slice because the
preflight is SearXNG-specific. It rejects `--search-provider fixture` and
`BOSS_IDEA_SEARCH_SEARXNG_FIXTURE`, requires `BOSS_IDEA_LIVE_CRAWL=1`, and
writes the summary to ignored
`agentic/reviews/boss-idea-response/live-smoke/<run-id>/summary.yaml` by
default. The summary stores phase status, artifact paths, and validation
outcomes; it does not store raw SearXNG JSON or raw page bodies.

## Hermes Manual Action

BIR-11D exposes the same wrapper through an optional Hermes action. It is
manual-only and requires explicit operator identity:

```bash
scripts/run-hermes-action.sh --dry-run run_boss_idea_live_smoke \
  run_id=<run-id> \
  live_crawl=1 \
  searxng_base_url="http://127.0.0.1:8080/search" \
  searxng_endpoint_label="local-searxng" \
  searxng_no_paid_engines=1 \
  actor=local-operator \
  role=operator
```

Remove `--dry-run` only for an intentional live smoke. The action is not
scheduled and cannot approve artifacts, decisions, roadmap, budget,
implementation, PR publishing, or deployment.

## Run

Generate or confirm the query pack:

```bash
scripts/collect-boss-idea-research.sh --dry-run <run-id>
```

Run no-paid discovery and crawl:

```bash
BOSS_IDEA_LIVE_CRAWL=1 \
BOSS_IDEA_SEARCH_SEARXNG_BASE_URL="http://127.0.0.1:8080/search" \
BOSS_IDEA_SEARCH_SEARXNG_ENDPOINT_LABEL="local-searxng" \
BOSS_IDEA_SEARCH_SEARXNG_NO_PAID_ENGINES=1 \
scripts/crawl-boss-idea-market.sh <run-id> \
  --live \
  --from-query-pack \
  --search-provider searxng \
  --output agentic/runs/<run-id>/market-search-results.yaml
```

Validate the resulting research:

```bash
scripts/validate-boss-idea-research.sh agentic/runs/<run-id>/market-research.md
scripts/validate-boss-idea-market-discovery-quality.sh agentic/runs/<run-id>/market-discovery-quality.yaml
```

## Evidence To Inspect

Review these ignored run paths:

- `agentic/runs/<run-id>/market-candidate-urls.yaml`
- `agentic/runs/<run-id>/market-search-results.yaml`
- `agentic/runs/<run-id>/market-discovery-quality.yaml`
- `agentic/runs/<run-id>/crawl4ai/crawl-log.yaml`
- `agentic/runs/<run-id>/crawl4ai/raw/`

Tracked summaries must cite sources and stay public-safe. Do not copy raw page
content or raw provider JSON into tracked docs.

## Fallback Handling

Use `duckduckgo_html` only when:

- SearXNG is unavailable;
- operator policy allows public non-JavaScript search result extraction;
- the run records `fallback_from: searxng`;
- artifacts label the provider as lower reproducibility than SearXNG.

Use `local_browser_search` only when:

- SearXNG and HTML search are insufficient;
- the browser runs in an isolated no-login profile;
- locale, region, safe-search state, search URL, and timestamp are recorded;
- captcha or bot-detection stops the run rather than being bypassed.

The local browser provider uses `scripts/lib/boss_idea_local_browser_search.py`
and requires an operator-provided Playwright/Chrome runtime for live smoke.
Default validation uses `BOSS_IDEA_SEARCH_LOCAL_BROWSER_FIXTURE` and does not
launch Chrome.

Use `seed_replay` when:

- live search is unavailable;
- a Staff+ reviewer accepts the replay scope;
- candidate URLs are public and pass BIR-10 URL safety checks.

Use optional paid `brave` only when:

- no-paid providers cannot satisfy the research request in the timebox;
- Staff+ explicitly accepts the paid provider for the run;
- the run records why no-paid search was insufficient;
- credentials stay in `BOSS_IDEA_SEARCH_BRAVE_*` environment variables;
- artifacts label Brave as optional paid fallback, not the default path.

## Provider Health

Market discovery records provider-health event evidence under ignored run paths:

```text
agentic/runs/<run-id>/provider-health-events.yaml
```

Summarize those events only through the scrubbed summary command:

```bash
scripts/summarize-boss-idea-provider-health.sh --output agentic/runs/<run-id>/provider-health.yaml <run-id>
```

Fallback guidance must be advisory-only:

```bash
scripts/recommend-boss-idea-provider-fallback.sh --output agentic/runs/<run-id>/provider-fallback-advisory.yaml agentic/runs/<run-id>/provider-health.yaml
```

Provider-health event logs and raw crawl/search evidence remain ignored. Tracked
provider-health summaries or advisory examples must be scrubbed, schema-valid,
and free of raw URLs, hosts, IPs, queries, provider responses, crawl bodies, and
credentials. Advisory output cannot approve provider selection or fallback
execution; it must require a human decision and forbid automatic execution.

## Failure Triage

Missing SearXNG base URL:

- set `BOSS_IDEA_SEARCH_SEARXNG_BASE_URL`;
- rerun with `--live` and `BOSS_IDEA_LIVE_CRAWL=1`.

Empty result set:

- inspect query pack wording;
- lower category restrictions;
- retry with a different locale;
- record an evidence gap if the market appears immature.

Private or blocked result URLs:

- do not bypass URL safety;
- let the provider filter the result;
- use public official docs, pricing pages, changelogs, or product pages instead.

Captcha or bot detection:

- do not automate captcha solving;
- switch back to SearXNG or seed replay;
- record the fallback reason.

SearXNG unavailable:

- retry after confirming the endpoint is reachable;
- use `duckduckgo_html` or `local_browser_search` only with fallback labeling;
- use optional paid Brave only after Staff+ explicitly selects that fallback;
- record a Staff+ waiver if production-grade discovery cannot run.

Paid engine detected in SearXNG path:

- stop the no-paid run;
- switch the SearXNG endpoint to no-paid engines;
- or explicitly select an optional paid provider path with Staff+ approval.

## Review Checklist

Before using the output in a boss decision memo, confirm:

- provider is no-paid unless a paid provider was explicitly approved;
- `market-discovery-quality.yaml` is present, validates, and is treated as
  advisory-only evidence;
- candidate URLs are public and policy-approved;
- Crawl4AI evidence is stored only in ignored run paths;
- market-search results include competitor and mainstream-practice signals;
- source metadata includes provider, query id, rank, retrieval time, access
  date, and fallback state if any;
- quality evidence gaps are reflected in memo caveats or follow-up actions;
- provider-health summaries or fallback advisory artifacts are schema-valid,
  public-safe, and advisory-only when included in review evidence;
- market research separates facts, inferences, and unknowns;
- no search or crawl output is treated as implementation approval.

## References

- No-paid search ADR: `docs/adr/007-boss-idea-no-paid-search-provider.md`
- SearXNG provider design: `docs/architecture/boss-idea-modules/searxng-market-discovery-provider.md`
- Crawl4AI adapter design: `docs/architecture/boss-idea-modules/crawl4ai-market-discovery-adapter.md`
- SearXNG container installation: https://docs.searxng.org/admin/installation-docker.html
- SearXNG Search API: https://docs.searxng.org/dev/search_api.html
