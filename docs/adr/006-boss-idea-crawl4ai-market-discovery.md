# ADR 006: Require Crawl4AI-Compatible Market Discovery For Boss Idea Response

## Status

Accepted.

## Context

Boss Idea Response exists to help the engineering team answer executive ideas
quickly with evidence, competitor context, solution options, and bounded POC or
MVP recommendations.

BIR-09 created the provider-neutral market research ingestion path:

```text
search-results.yaml -> collect-boss-idea-research.sh -> market-research.md
```

That path is not enough by itself. It still requires someone or something to
find candidate public sources. For executive brainstorming, the team needs a
strong crawler/search capability so competitor analysis and solution planning
can happen quickly without turning every idea into manual research.

## Decision

Boss Idea Response requires a controlled Crawl4AI-compatible market discovery
adapter.

The adapter must provide both:

- query-to-URL discovery through an approved public search provider contract;
- Crawl4AI-backed public page crawling and markdown capture for policy-approved
  URLs.

Crawl4AI is the default local-first crawler. A better crawler/search tool may
replace or supplement it only if it preserves the same safety and evidence
contract:

- public-source only;
- local evidence control;
- no hosted LLM extraction by default;
- URL safety before network access and after redirects;
- deterministic no-network golden fixtures;
- normalized results that feed `collect-boss-idea-research.sh`.

ADR 007 further constrains the query-to-URL provider choice: no-paid providers
are preferred, SearXNG is the default no-paid provider once implemented, and
paid search APIs such as Brave are optional fallback only.

## Consequences

This moves public market crawl/search from deferred scope into required Boss
Idea capability. Paid market databases, authenticated crawling, private
customer/internal docs, and hosted crawler fallback remain out of scope unless a
new ADR changes that boundary.

The adapter introduces network and copyright risk. Therefore implementation
must enforce:

- deny-by-default per-run host allowlist;
- DNS/IP safety checks against loopback, private, link-local, multicast, and
  metadata-service targets;
- redirect-chain validation with the same URL policy;
- TLS verification enabled;
- robots.txt or site-policy handling;
- max pages, max redirects, timeout, content length, and per-host rate limits;
- short summarized claims that satisfy the BIR-09 market-search result schema;
- ignored raw evidence paths only;
- manifest metadata that records evidence without approving artifacts.

## Alternatives Considered

### Keep Crawl/Search Deferred

Rejected. It leaves the system unable to satisfy rapid executive competitor
research without manual seed URLs.

### Use Hosted Firecrawl First

Rejected for this phase. Hosted crawler APIs add API-key handling, external
service dependency, data governance review, and possible product-boundary
confusion.

### Manual Search Results Only

Rejected as the default. Manual search results remain useful for emergency
override or fixture replay, but not as the primary capability.

## Validation

The BIR-10 implementation must include:

- deterministic local fixture crawl;
- search-provider fixture mode;
- URL safety tests for blocked IP classes, redirects, and DNS rebinding;
- robots and rate-limit tests;
- user-agent, redirect-chain DNS rebinding, content-truncation log,
  markdown-only output, circuit-breaker, and raw-evidence ignored-path tests
  required by the BIR-10 module validation strategy;
- generated `market-search-results.yaml` validation;
- downstream `collect-boss-idea-research.sh` validation;
- AIT plus Codex CLI Staff+ review.

Live web smoke tests must require explicit opt-in and must not run in default
golden fixtures.
