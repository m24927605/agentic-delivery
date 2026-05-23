# Market Research Evidence Module

## Purpose

Market Research Evidence creates a source-backed market and competitor view for
an executive idea.

## Scope

Active scope:

- define research questions;
- collect public sources and citation metadata;
- summarize competitor and mainstream approaches;
- distinguish facts, inferences, and unknowns;
- record confidence and freshness;
- produce public-safe summaries.

## Deferred Scope

- automated paid database access;
- unpublished analyst reports;
- private customer interviews;
- source scraping beyond allowed public access;
- storing raw copyrighted source content in tracked files.

## Workflow

```text
research questions
  -> source collection
  -> citation metadata
  -> competitor matrix
  -> mainstream practice summary
  -> evidence confidence
  -> research review
```

## Artifact Schema

Markdown frontmatter fields:

- `sources`
- `claims`
- `inferences`
- `raw_evidence_path`

Generated markdown sections:

- `Search Questions`
- `Competitor Signals`
- `Mainstream Practices`
- `Implementation Patterns`
- `Differentiation Notes`
- `Evidence Gaps`
- `Recommended Follow Up`

Each claim must include:

- claim text;
- source reference;
- access date;
- source type;
- confidence: `high`, `medium`, or `low`;
- whether the statement is fact, inference, or hypothesis.

## CLI / Manifest / Pipeline Contract

```bash
scripts/collect-boss-idea-research.sh --dry-run <run-id>
scripts/collect-boss-idea-research.sh <run-id> --search-results <results.yaml> --output <research.md>
```

Contract:

- derives a market search query pack from `boss_idea_intake`;
- consumes public-safe search results from a provider adapter or curated source
  inventory;
- records query metadata in ignored run evidence;
- writes only summarized public-safe research artifacts;
- validates the generated artifact with `scripts/validate-boss-idea-research.sh`;
- records artifact and evidence paths in the planning manifest;
- refuses to collect research if required citation fields, required market
  signals, or source dates are missing;
- does not approve artifacts or implementation.

## Failure Behavior

Block research completion when:

- a key claim has no source;
- access date is missing;
- source type is missing;
- competitor comparison lacks evidence;
- raw source text is copied into tracked files beyond short excerpts;
- evidence freshness is older than the artifact's configured threshold without
  an explicit caveat.

## Validation Strategy

Validation checks:

- every source has title or label, URL or stable reference, access date, and
  source type;
- every key claim maps to at least one source;
- unsupported inferences are labeled;
- tracked files pass privacy scan;
- raw evidence remains ignored.

## Test Cases

- cited competitor matrix passes;
- missing source URL or stable reference fails;
- missing access date fails;
- unsupported claim fails;
- raw evidence under tracked docs fails privacy or evidence validation;
- stale source with caveat passes only when explicitly labeled.

## Acceptance Criteria

- The research artifact can answer "who does this today", "what is mainstream",
  "what is differentiated", and "what do we still not know".
- Claims are traceable to source metadata.
- The artifact can be reviewed without accessing raw local transcripts.

## Doc Review Standard

Claude Code review must check source traceability, claim confidence, separation
of facts and inferences, and whether the summary is executive-readable.

## Code Review Standard

Implementation review must check citation validation, evidence storage paths,
copyright-safe summarization behavior, and negative-path tests for missing
sources.

## Rollback

Revert research validators and artifact templates. Remove ignored source
metadata collected during smoke tests.

## Review Expectations

Review must confirm that market research informs decisions but does not become
approval authority or roadmap commitment.
