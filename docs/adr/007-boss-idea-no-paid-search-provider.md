# ADR 007: Prefer No-Paid Search Providers For Boss Idea Market Discovery

## Status

Accepted.

## Context

ADR 006 made Crawl4AI-compatible market discovery required for Boss Idea
Response. The first live query-to-URL implementation used Brave Search because
it has a stable API and is straightforward to validate.

That cannot be the default operating model. The engineering team needs to
answer executive brainstorming requests quickly without making paid search API
access a prerequisite for market research, competitor discovery, or solution
planning.

Crawl4AI remains the crawler. It can fetch and convert approved public pages,
but it is not a search engine. Boss Idea Response still needs a query-to-URL
provider that can turn the market research query pack into candidate public
URLs before Crawl4AI runs.

## Decision

Boss Idea Response must prefer a no-paid query-to-URL provider before any paid
search API.

Provider priority:

1. `searxng`: default no-paid provider through a self-hosted SearXNG endpoint
   with JSON output.
2. `duckduckgo_html`: no-paid fallback through the public non-JavaScript HTML
   search surface when SearXNG is unavailable and operator policy allows it.
3. `local_browser_search`: no-paid fallback that uses an isolated local
   Chrome or Chromium browser context to extract public search result links
   when HTML search endpoints are not sufficient.
4. `brave`: optional paid provider only, not the default.
5. `fixture` and `seed_replay`: deterministic validation and emergency replay
   providers only, not production discovery defaults.

`searxng` is the first no-paid implementation slice because it is open source,
can be self-hosted, exposes a JSON search API, and keeps the discovery path
operator-controlled. The default production path should be:

```text
market-research-query-pack.yaml
  -> searxng query-to-URL discovery
  -> candidate URL safety validation
  -> Crawl4AI markdown crawl
  -> market-search-results.yaml
  -> collect-boss-idea-research.sh
```

## Consequences

Paid search API access is no longer a required dependency for Boss Idea market
discovery. Brave remains useful when the team explicitly approves a paid,
stable, external search API, but it cannot be the only live provider.

The no-paid path introduces operational responsibilities:

- the team must run a self-hosted SearXNG instance;
- the approved SearXNG instance must use no-paid engines by default;
- the endpoint must be configured through environment variables, not tracked
  files;
- query/result metadata must record provider, endpoint label, query URL,
  rank, locale, freshness, fallback reason, and retrieval time;
- default golden fixtures must use local SearXNG-like JSON, not the public
  internet;
- live smoke tests must remain opt-in with `--live` and
  `BOSS_IDEA_LIVE_CRAWL=1`;
- fallback providers must be lower-trust and visibly labeled in artifacts.

Public SearXNG instances are not the default production dependency. They may be
used only as an explicitly labeled emergency fallback with Staff+ approval
because JSON formats, enabled engines, rate limits, and retention behavior are
not controlled by the team.

The Staff Security Engineer and Staff Platform Engineer must approve every
provider before release. Approval covers the provider adapter, not arbitrary
URLs; individual candidate URLs still pass the BIR-10 URL safety policy before
Crawl4AI receives them.

## Alternatives Considered

### Keep Brave As Required Live Provider

Rejected. It makes paid API access a prerequisite for the default Boss Idea
workflow.

### Use Local Chrome Against Public Search As The Default

Rejected as the first default. It can work, but search result pages change,
bot-detection and captcha can interrupt runs, and results are harder to
reproduce. It remains a fallback slice.

### Use DuckDuckGo HTML As The Default

Rejected as the first default. It is no-paid and useful as a fallback, but an
operator-controlled SearXNG endpoint gives the team a clearer service boundary,
JSON contract, and validation fixture shape.

### Manual Seed URLs Only

Rejected. Manual seeds are still useful for incident recovery and fixture
replay, but they do not satisfy the requirement to quickly search the market
from an executive idea.

## Validation

The no-paid provider implementation must include:

- deterministic SearXNG fixture JSON coverage;
- no-paid engine policy confirmation for live SearXNG runs;
- provider output validation for required URL, title, snippet, rank, query id,
  provider, and retrieval metadata;
- URL safety checks before Crawl4AI receives a candidate URL;
- fallback labeling when `duckduckgo_html` or `local_browser_search` is used;
- negative tests for missing endpoint, malformed JSON, unsupported URL scheme,
  private or metadata-service candidate URLs, empty result sets, missing query
  ids, excessive result count, and output path traversal;
- downstream `collect-boss-idea-research.sh` validation;
- privacy scan over tracked files;
- AIT plus Codex CLI Staff+ review.

Live SearXNG smoke tests must be opt-in and excluded from default golden
fixtures.

## References

- SearXNG documentation: https://docs.searxng.org/
- SearXNG search API: https://docs.searxng.org/dev/search_api.html
- DuckDuckGo non-JavaScript help: https://duckduckgo.com/duckduckgo-help-pages/features/non-javascript/
- Playwright browser contexts: https://playwright.dev/docs/browser-contexts
- Existing Crawl4AI discovery ADR: `docs/adr/006-boss-idea-crawl4ai-market-discovery.md`
