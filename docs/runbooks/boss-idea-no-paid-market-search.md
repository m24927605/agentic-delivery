# Boss Idea No-Paid Market Search Runbook

## Purpose

This runbook explains how to run Boss Idea market discovery without paid search
APIs. The preferred path is SearXNG for query-to-URL discovery and Crawl4AI for
approved page crawling.

## Provider Priority

Use providers in this order:

1. `searxng`: default no-paid provider.
2. `duckduckgo_html`: no-paid fallback when SearXNG is unavailable and policy
   allows HTML result extraction.
3. `local_browser_search`: no-paid fallback using isolated local Chrome or
   Chromium browser automation.
4. `brave`: optional paid provider only.
5. `fixture` or `seed_replay`: deterministic tests and emergency replay only.

## SearXNG Prerequisites

Operator responsibilities:

- provide a SearXNG endpoint that supports JSON output;
- confirm the endpoint uses no-paid engines by default;
- keep the endpoint URL in environment variables, not tracked files;
- configure SearXNG engines and rate limits outside this repository;
- record a public-safe endpoint label such as `local-searxng` or
  `team-searxng`;
- verify that the endpoint is intended for internal research automation.

This repository does not host or manage SearXNG.

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
```

## Evidence To Inspect

Review these ignored run paths:

- `agentic/runs/<run-id>/market-candidate-urls.yaml`
- `agentic/runs/<run-id>/market-search-results.yaml`
- `agentic/runs/<run-id>/crawl4ai/crawl-log.yaml`
- `agentic/runs/<run-id>/crawl4ai/raw/`

Tracked summaries must cite sources and stay public-safe. Do not copy raw page
content or raw provider JSON into tracked docs.

## Fallback Handling

`duckduckgo_html` is design-deferred to BIR-10F and is not available until that
slice ships. Once available, use it only when:

- SearXNG is unavailable;
- operator policy allows public non-JavaScript search result extraction;
- the run records `fallback_from: searxng`;
- artifacts label the provider as lower reproducibility than SearXNG.

`local_browser_search` is design-deferred to BIR-10F and is not available until
that slice ships. Once available, use it only when:

- SearXNG and HTML search are insufficient;
- the browser runs in an isolated no-login profile;
- locale, region, safe-search state, search URL, and timestamp are recorded;
- captcha or bot-detection stops the run rather than being bypassed.

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
- candidate URLs are public and policy-approved;
- Crawl4AI evidence is stored only in ignored run paths;
- market-search results include competitor and mainstream-practice signals;
- source metadata includes provider, query id, rank, retrieval time, access
  date, and fallback state if any;
- market research separates facts, inferences, and unknowns;
- no search or crawl output is treated as implementation approval.

## References

- No-paid search ADR: `docs/adr/007-boss-idea-no-paid-search-provider.md`
- SearXNG provider design: `docs/architecture/boss-idea-modules/searxng-market-discovery-provider.md`
- Crawl4AI adapter design: `docs/architecture/boss-idea-modules/crawl4ai-market-discovery-adapter.md`
