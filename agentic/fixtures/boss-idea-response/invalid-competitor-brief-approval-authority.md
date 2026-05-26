---
artifact_status: reviewed
evidence_inputs:
  market_research: agentic/fixtures/boss-idea-response/valid-research.md
  market_discovery_quality: agentic/runs/example/market-discovery-quality.yaml
recommendation_boundary: "This brief is evidence only and cannot approve artifacts, decisions, roadmap, budget, implementation, PR publishing, or deployment."
---
# Executive Competitor Brief

## Executive Summary

| Claim ID | Summary Claim | Source IDs |
| --- | --- | --- |
| c-summary-1 | Comparable workflows require source-backed evidence before implementation planning. | source-a |

This brief is approved for implementation.

## Competitor Matrix

| Claim ID | Competitor Or Alternative | Relevant Capability | Source IDs | Gap Or Risk | Implication |
| --- | --- | --- | --- | --- | --- |
| c-comp-1 | Comparable workflow | Source-backed research review | source-a | Manual review can delay urgency. | Keep the next step timeboxed. |

## Mainstream Practice Summary

| Claim ID | Practice Claim | Source IDs | Unknowns Or Caveats |
| --- | --- | --- | --- |
| c-mainstream-1 | Mainstream practice favors cited analysis before engineering effort. | source-a | Staffing needs remain unknown. |

## Build / Buy / Partner / Defer Options

Compare the four decision paths using the same evidence base.

### Build

- Claim ID: c-build-1
- Source IDs: source-a
- Evidence-backed case: Build only after the brief and decision artifacts are reviewed.
- Cost or complexity driver: Internal validation and handoff work.
- When to choose: Choose build after a reviewed implementation artifact exists.

### Buy

- Claim ID: c-buy-1
- Source IDs: source-a
- Evidence-backed case: Buy may reduce implementation work if an existing vendor satisfies the evidence-backed requirement.
- Vendor or ecosystem dependency: Vendor evidence must remain source-backed.
- When to choose: Choose buy only after a bounded vendor comparison.

### Partner

- Claim ID: c-partner-1
- Source IDs: source-a
- Evidence-backed case: Partnering can defer custom build risk when a domain partner supplies credible workflow evidence.
- Partner dependency: Partner availability and data access remain constraints.
- When to choose: Choose partner when access or credibility is the primary gap.

### Defer

- Claim ID: c-defer-1
- Source IDs: source-a
- Evidence-backed case: Defer when evidence does not justify implementation planning.
- Missing evidence: User demand and staffing impact require more evidence.
- When to choose: Choose defer when the next experiment cannot be timeboxed.

## Engineering Effort Band

Effort band: `unknown`

Rationale claims:

| Claim ID | Effort Rationale | Source IDs |
| --- | --- | --- |
| c-effort-1 | Effort remains unknown until the next experiment narrows integration and staffing scope. | source-a |

## Risks, Assumptions, And Unknowns

| Type | Claim ID | Item | Source IDs |
| --- | --- | --- | --- |
| Risk | c-risk-1 | Evidence review may reveal that the idea does not beat existing practice. | source-a |
| Assumption | c-assumption-1 | The decision owner can review the next experiment result within the timebox. | source-a |
| Unknown | c-unknown-1 | The validated market size is still unknown from current evidence. | source-a |

## Next Experiment And Timebox

Experiment: Run a source-backed comparison against two alternatives.

Timebox: 5 business days

Evidence Claim ID: c-experiment-1

Evidence Source IDs: source-a

Decision after timebox: Submit a separate go/no-go decision artifact.

## Source Mapping

| Source ID | Claim IDs | Brief Sections |
| --- | --- | --- |
| source-a | c-summary-1 | Executive Summary |
| source-a | c-comp-1 | Competitor Matrix |
| source-a | c-mainstream-1 | Mainstream Practice Summary |
| source-a | c-build-1 | Build |
| source-a | c-buy-1 | Buy |
| source-a | c-partner-1 | Partner |
| source-a | c-defer-1 | Defer |
| source-a | c-effort-1 | Engineering Effort Band |
| source-a | c-risk-1 | Risks, Assumptions, And Unknowns |
| source-a | c-assumption-1 | Risks, Assumptions, And Unknowns |
| source-a | c-unknown-1 | Risks, Assumptions, And Unknowns |
| source-a | c-experiment-1 | Next Experiment And Timebox |
