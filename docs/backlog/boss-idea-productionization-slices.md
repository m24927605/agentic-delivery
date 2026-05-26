# Boss Idea Productionization Slices

## Scope

These slices convert the completed Boss Idea market discovery foundation into a
repeatable production workflow for responding to executive brainstorming
requests. The core search/crawl pipeline remains BIR-10. This backlog starts
after BIR-10G.

## Review Rule

Every documentation or implementation slice must run AIT with Codex CLI Staff+
review. Implementation slices may run up to 5 review/fix rounds. If round 5
does not pass, the Staff+ expert board records a decision and chooses a smaller
slice, deferral, or alternate implementation path.

## BIR-11: Self-Hosted SearXNG Live Smoke

Status: completed through BIR-15E.

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

Status: completed.

Owner role: Staff Platform Engineer.

Source artifacts:

- `docs/architecture/boss-idea-productionization-roadmap.md`
- `docs/architecture/boss-idea-modules/searxng-market-discovery-provider.md`
- `docs/runbooks/boss-idea-no-paid-market-search.md`

Dependencies: BIR-11A live smoke runbook and evidence template.

Scope:

- add a repo-local command that checks base URL, JSON output, endpoint label,
  and `BOSS_IDEA_SEARCH_SEARXNG_NO_PAID_ENGINES=1`;
- verify `/search?q=<probe>&format=json` returns parseable JSON;
- record public-safe preflight evidence under ignored run/review paths.

Files touched:

- `scripts/boss-idea-searxng-preflight.sh`
- `scripts/run-golden-fixtures.sh`
- `scripts/validate-agentic-system.sh`
- `docs/runbooks/boss-idea-no-paid-market-search.md`
- `docs/backlog/boss-idea-productionization-slices.md`

Write scope:

- add only the preflight command, deterministic fixture checks, and public-safe
  documentation for operator usage;
- write live preflight evidence only under ignored `agentic/reviews/` or
  `agentic/runs/` paths.

Deferred scope:

- running a full market discovery crawl;
- managing SearXNG installation.

Acceptance criteria:

- missing base URL fails;
- non-JSON response fails;
- missing no-paid confirmation fails;
- preflight output redacts query credentials and userinfo.

Validation command:

```bash
bash -n scripts/boss-idea-searxng-preflight.sh scripts/run-golden-fixtures.sh
scripts/run-golden-fixtures.sh
scripts/validate-agentic-system.sh
PROFILE=boss-idea-response scripts/validate-agentic-system.sh
scripts/validate-hermes-actions.sh
scripts/privacy-scan-tracked.sh
git diff --check
```

Negative-path tests:

- missing `BOSS_IDEA_SEARCH_SEARXNG_BASE_URL` fails before any network request;
- missing `BOSS_IDEA_SEARCH_SEARXNG_NO_PAID_ENGINES=1` fails;
- a preflight URL with userinfo or query credentials is redacted in stdout and
  ignored evidence;
- non-JSON response fails with an actionable provider error.

Rollback notes: remove the preflight command, fixture coverage, runbook updates,
and ignored preflight evidence. Keep BIR-10E because SearXNG remains the
default no-paid provider.

AIT review path:
`agentic/reviews/boss-idea-response/bir-11b/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: if round 5 fails, keep live smoke manual and decide
whether to simplify preflight to static environment checks or split endpoint
probing from evidence recording.

### BIR-11C: Live Smoke Wrapper

Status: completed.

Owner role: Staff Platform Engineer.

Source artifacts:

- `docs/architecture/boss-idea-productionization-roadmap.md`
- `docs/runbooks/boss-idea-no-paid-market-search.md`
- `docs/architecture/boss-idea-modules/crawl4ai-market-discovery-adapter.md`

Dependencies: BIR-11B SearXNG preflight command.

Scope:

- add a wrapper that runs preflight, market discovery, quality validation, and
  research validation for a provided run id;
- require `--live` and `BOSS_IDEA_LIVE_CRAWL=1`;
- write public-safe live smoke summary under ignored review evidence.

Files touched:

- `scripts/run-boss-idea-live-smoke.sh`
- `scripts/run-golden-fixtures.sh`
- `scripts/validate-agentic-system.sh`
- `docs/runbooks/boss-idea-no-paid-market-search.md`
- `docs/backlog/boss-idea-productionization-slices.md`

Write scope:

- add only a wrapper that orchestrates the existing SearXNG preflight,
  market-discovery command, and existing validators;
- keep live smoke evidence under ignored `agentic/reviews/` paths;
- do not change provider priority, parsing, artifact approval, or go/no-go
  authority.

Deferred scope:

- automatic scheduling;
- Hermes execution.

Acceptance criteria:

- deterministic fixtures remain no-network;
- live smoke cannot run with `fixture` provider;
- failures identify the exact failed phase.

Validation command:

```bash
bash -n scripts/run-boss-idea-live-smoke.sh scripts/boss-idea-searxng-preflight.sh scripts/run-golden-fixtures.sh
scripts/run-golden-fixtures.sh
scripts/validate-agentic-system.sh
PROFILE=boss-idea-response scripts/validate-agentic-system.sh
scripts/validate-hermes-actions.sh
scripts/privacy-scan-tracked.sh
git diff --check
```

Negative-path tests:

- missing `--live` fails before preflight;
- missing `BOSS_IDEA_LIVE_CRAWL=1` fails before preflight;
- `--search-provider fixture` is rejected in live smoke mode;
- `BOSS_IDEA_SEARCH_SEARXNG_FIXTURE` is rejected in live smoke mode;
- preflight failure records `failed_phase: preflight` and stops before market
  discovery;
- deterministic positive smoke uses a local SearXNG fixture server and does
  not use public internet.

Rollback notes: remove the live smoke wrapper, fixture assertions, runbook
updates, validation registration, and ignored live smoke evidence. Keep
BIR-11B.

AIT review path:
`agentic/reviews/boss-idea-response/bir-11c/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: if round 5 fails, keep preflight plus manual market
discovery documented and split the failing phase into a smaller follow-up slice.

### BIR-11D: Hermes Live Smoke Action

Status: completed.

Owner role: Staff Platform Engineer.

Source artifacts:

- `agentic/hermes-actions.yaml`
- `agentic/identity-policy.yaml`
- `docs/runbooks/boss-idea-no-paid-market-search.md`

Dependencies: BIR-11C live smoke wrapper.

Scope:

- add optional Hermes action contract for the live smoke wrapper;
- keep live smoke out of default validation;
- require explicit operator identity and live gates.

Files touched:

- `agentic/hermes-actions.yaml`
- `agentic/identity-policy.yaml`
- `agentic/README.md`
- `scripts/run-hermes-action.sh`
- `scripts/validate-hermes-actions.sh`
- `scripts/run-golden-fixtures.sh`
- `docs/runbooks/boss-idea-no-paid-market-search.md`
- `docs/backlog/boss-idea-productionization-slices.md`

Write scope:

- add only the optional manual Hermes action contract and identity gate;
- keep live execution routed through `scripts/run-boss-idea-live-smoke.sh`;
- do not add scheduling, Hermes memory authority, or approval authority.

Deferred scope:

- scheduled unattended live runs.

Acceptance criteria:

- Hermes memory is non-authoritative;
- action is manually rerunnable;
- action cannot approve artifacts or decisions.

Validation command:

```bash
bash -n scripts/run-hermes-action.sh scripts/run-golden-fixtures.sh scripts/validate-hermes-actions.sh
scripts/run-golden-fixtures.sh
scripts/validate-agentic-system.sh
PROFILE=boss-idea-response scripts/validate-agentic-system.sh
scripts/validate-hermes-actions.sh
scripts/validate-identity-policy.sh
scripts/privacy-scan-tracked.sh
git diff --check
```

Negative-path tests:

- dry-run renders the manual live smoke command without executing it;
- execution without explicit `actor=` and `role=` fails before wrapper launch;
- unauthorized identity fails authorization before wrapper launch;
- missing live gate input fails action rendering.

Rollback notes: remove the Hermes action, identity-policy action, runner guard,
fixture assertions, and documentation updates. Keep BIR-11B and BIR-11C.

AIT review path:
`agentic/reviews/boss-idea-response/bir-11d/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: if round 5 fails, keep the BIR-11C wrapper manual-only
and defer Hermes exposure until the action contract can be split smaller.

## BIR-12: One-Command Boss Idea Workflow

Status: planning completed by the productionization documentation update;
implementation slices BIR-12A through BIR-12E remain planned.

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

Status: completed; BIR-13A-E completed.

Owner role: Product Strategy Lead.

Purpose: generate a boss-facing brief from validated evidence without asking
the reader to inspect raw research artifacts.

Slices:

- BIR-13A artifact schema and Markdown template (completed);
- BIR-13B validator (completed by Staff+ resolution);
- BIR-13C generator (completed by Staff+ resolution);
- BIR-13D golden and negative fixtures (completed);
- BIR-13E Hermes/profile wiring (completed).

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

### BIR-13A: Artifact Schema And Markdown Template

Status: completed.

Owner role: Product Strategy Lead.

Source artifacts:

- `docs/backlog/boss-idea-productionization-slices.md`
- `docs/architecture/boss-idea-modules/market-research-evidence.md`
- `docs/architecture/boss-idea-modules/boss-decision-memo.md`

Dependencies: BIR-11 live smoke evidence foundation and existing validated
market research artifacts.

Scope:

- add a schema contract for the executive competitor brief artifact;
- add a public-safe Markdown template matching the required sections;
- register both files in scaffold validation and deterministic fixtures.

Files touched:

- `agentic/schemas/boss-idea-competitor-brief.schema.yaml`
- `agentic/fixtures/boss-idea-response/competitor-brief-template.md`
- `scripts/run-golden-fixtures.sh`
- `scripts/validate-agentic-system.sh`
- `docs/backlog/boss-idea-productionization-slices.md`

Write scope:

- schema and template only;
- no validator, generator, Hermes action, profile wiring, or memo behavior
  changes.

Deferred scope:

- BIR-13B validator;
- BIR-13C generator;
- BIR-13D golden and negative fixtures for generated briefs;
- BIR-13E Hermes/profile wiring.

Acceptance criteria:

- schema names the required executive brief sections and claim/source mapping
  contract;
- template includes competitor matrix, options, effort band, risk, experiment,
  and source mapping sections;
- template requires Claim ID and Source IDs in every claim-bearing section;
- template states evidence-only authority and cannot approve implementation;
- deterministic fixture check proves template headings, required columns, and
  claim references match the schema.

Validation command:

```bash
bash -n scripts/run-golden-fixtures.sh scripts/validate-agentic-system.sh
scripts/run-golden-fixtures.sh
scripts/validate-agentic-system.sh
PROFILE=boss-idea-response scripts/validate-agentic-system.sh
scripts/privacy-scan-tracked.sh
git diff --check
```

Rollback notes: remove the competitor brief schema, template fixture, validation
registration, fixture assertions, and this BIR-13A metadata. Keep BIR-11 and
BIR-12.

AIT review path:
`agentic/reviews/boss-idea-response/bir-13a/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: if round 5 fails, keep BIR-13 planned and split schema
from template alignment.

### BIR-13B: Competitor Brief Validator

Status: completed by Staff+ resolution after AIT round 5.

Owner role: Product Strategy Lead.

Source artifacts:

- `agentic/schemas/boss-idea-competitor-brief.schema.yaml`
- `agentic/fixtures/boss-idea-response/competitor-brief-template.md`
- existing Boss Idea Markdown validators in `scripts/`

Dependencies: BIR-13A schema and template.

Scope:

- add a deterministic validator for filled executive competitor brief Markdown;
- require claim IDs, source IDs, and Source Mapping consistency;
- reject no-source placeholders, unmapped claim/source pairs, forbidden authority
  wording, and raw provider text markers;
- add public-safe positive and negative fixtures.

Files touched:

- `scripts/validate-boss-idea-competitor-brief.sh`
- `agentic/fixtures/boss-idea-response/valid-competitor-brief.md`
- `agentic/fixtures/boss-idea-response/invalid-competitor-brief-source-none.md`
- `agentic/fixtures/boss-idea-response/invalid-competitor-brief-unmapped-source.md`
- `agentic/fixtures/boss-idea-response/invalid-competitor-brief-approval-authority.md`
- `agentic/schemas/boss-idea-competitor-brief.schema.yaml`
- `scripts/run-golden-fixtures.sh`
- `scripts/validate-agentic-system.sh`
- `agentic/pipeline.yaml`
- `agentic/README.md`
- `docs/backlog/boss-idea-productionization-slices.md`

Write scope:

- validator, schema metadata needed by the validator, deterministic fixtures, and
  validation registration only;
- no generator, Hermes action, profile wiring, or decision behavior changes.

Deferred scope:

- BIR-13C generator;
- BIR-13D generated brief golden/negative fixtures;
- BIR-13E Hermes/profile wiring.

Acceptance criteria:

- valid competitor brief fixture passes validation;
- missing or placeholder source IDs fail validation;
- claim/source pairs not represented in Source Mapping fail validation;
- forbidden authority wording, including modal permission, proceed/set/deploy
  variants, and mixed negated-plus-positive authority clauses, fails validation;
- malformed claim-bearing Markdown table rows fail validation;
- validator is deterministic and performs no network access.

Validation command:

```bash
bash -n scripts/validate-boss-idea-competitor-brief.sh scripts/run-golden-fixtures.sh scripts/validate-agentic-system.sh
scripts/validate-boss-idea-competitor-brief.sh agentic/fixtures/boss-idea-response/valid-competitor-brief.md
RUN_PREFIX=bir13b scripts/run-golden-fixtures.sh
scripts/validate-agentic-system.sh
PROFILE=boss-idea-response scripts/validate-agentic-system.sh
scripts/privacy-scan-tracked.sh
git diff --check
```

Rollback notes: remove the competitor brief validator, valid/invalid competitor
brief fixtures, schema metadata added for validation, validation registration,
README mention, and this BIR-13B metadata. Keep BIR-13A schema/template.

AIT review path:
`agentic/reviews/boss-idea-response/bir-13b/round-<n>.json`.

Maximum review rounds: 5.

Staff+ resolution: round 5 failed and the Staff+ board selected a validator
design change. Decision recorded at
`agentic/reviews/boss-idea-response/bir-13b/staff-escalation-decision.md`.

### BIR-13C: Competitor Brief Generator

Status: completed by Staff+ resolution after AIT round 5.

Owner role: Product Strategy Lead.

Source artifacts:

- `agentic/schemas/boss-idea-competitor-brief.schema.yaml`
- `scripts/validate-boss-idea-competitor-brief.sh`
- `scripts/collect-boss-idea-research.sh`
- `scripts/crawl-boss-idea-market.sh`
- existing Boss Idea generator patterns in `scripts/`

Dependencies: BIR-13A schema/template and BIR-13B validator.

Scope:

- generate a public-safe executive competitor brief from validated market
  research and market-discovery quality artifacts;
- validate generated output with the BIR-13B validator before moving it into
  place;
- record non-authoritative manifest metadata for the generated brief.

Files touched:

- `scripts/generate-boss-idea-competitor-brief.sh`
- `scripts/run-golden-fixtures.sh`
- `scripts/validate-agentic-system.sh`
- `agentic/pipeline.yaml`
- `agentic/README.md`
- `docs/backlog/boss-idea-productionization-slices.md`

Write scope:

- run-local generated brief and manifest metadata only;
- no Hermes action, profile wiring, decision behavior, or artifact approval
  status changes.

Deferred scope:

- BIR-13D generated brief fixture expansion;
- BIR-13E Hermes/profile wiring.

Acceptance criteria:

- generator refuses missing or invalid research/quality inputs;
- generated brief passes `scripts/validate-boss-idea-competitor-brief.sh`;
- output path stays under the run directory and does not overwrite without
  `--force`;
- reserved run artifacts, reserved evidence directories, and internal temp paths
  cannot be overwritten by final or temporary generator outputs;
- manifest metadata records evidence paths and remains non-authoritative;
- generator performs no network access.

Validation command:

```bash
bash -n scripts/generate-boss-idea-competitor-brief.sh scripts/validate-boss-idea-competitor-brief.sh scripts/run-golden-fixtures.sh scripts/validate-agentic-system.sh
RUN_PREFIX=bir13c scripts/run-golden-fixtures.sh
scripts/validate-agentic-system.sh
PROFILE=boss-idea-response scripts/validate-agentic-system.sh
scripts/privacy-scan-tracked.sh
git diff --check
```

Rollback notes: remove the competitor brief generator, validation registration,
golden fixture assertions, README mention, and this BIR-13C metadata. Keep
BIR-13A/B.

AIT review path:
`agentic/reviews/boss-idea-response/bir-13c/round-<n>.json`.

Maximum review rounds: 5.

Staff+ resolution: round 5 failed and the Staff+ board selected a generator
output-safety design change. Decision recorded at
`agentic/reviews/boss-idea-response/bir-13c/staff-escalation-decision.md`.

### BIR-13D: Generated Brief Golden And Negative Fixtures

Status: completed after AIT round 3.

Owner role: Staff QA Architect.

Dependencies: BIR-13C generator and BIR-13B validator.

Scope:

- add deterministic golden assertions over a generated competitor brief;
- add generated-brief negative fixtures derived from the generated artifact;
- keep fixture writes under ignored run directories.

Files touched:

- `scripts/run-golden-fixtures.sh`
- `docs/backlog/boss-idea-productionization-slices.md`

Write scope:

- fixture assertions only;
- no generator, validator, Hermes action, profile wiring, or decision behavior
  changes.

Deferred scope:

- BIR-13E Hermes/profile wiring.

Acceptance criteria:

- generated brief content has expected public-safe generated signals;
- generated brief does not copy raw research claim or inference text from the
  current generated research input;
- generated brief frontmatter exact evidence input paths and Source Mapping
  shape are asserted;
- generated-brief negatives fail for missing Source Mapping, `Source IDs: none`,
  and forbidden recommendation-boundary authority.

Validation command:

```bash
bash -n scripts/run-golden-fixtures.sh
RUN_PREFIX=bir13d-fix2 scripts/run-golden-fixtures.sh
scripts/validate-agentic-system.sh
PROFILE=boss-idea-response scripts/validate-agentic-system.sh
scripts/validate-hermes-actions.sh
scripts/validate-identity-policy.sh
scripts/privacy-scan-tracked.sh
git diff --check
```

Rollback notes: remove the generated competitor brief golden/negative assertions
and this BIR-13D metadata. Keep BIR-13A-C.

AIT review path:
`agentic/reviews/boss-idea-response/bir-13d/round-<n>.json`.

Maximum review rounds: 5.

AIT result: round 3 passed at
`agentic/reviews/boss-idea-response/bir-13d/round-3-review.yaml`.

Staff+ escalation path: if round 5 fails, keep BIR-13D planned and split golden
content assertions from generated-negative assertions.

### BIR-13E: Hermes/Profile Wiring

Status: completed after AIT round 5.

Owner role: Staff Platform Engineer.

Dependencies: BIR-13C generator and BIR-13D generated brief fixtures.

Scope:

- expose competitor brief generation and validation through Hermes action
  contracts;
- document the action commands in the profile README surface;
- add deterministic fixture checks for Hermes rendering, authorization, action
  execution, validation, and non-approval behavior.

Files touched:

- `agentic/hermes-actions.yaml`
- `agentic/README.md`
- `agentic/pipeline.yaml`
- `scripts/run-golden-fixtures.sh`
- `scripts/validate-agentic-system.sh`
- `scripts/validate-boss-idea-run-competitor-brief.sh`
- `docs/backlog/boss-idea-productionization-slices.md`

Write scope:

- Hermes/profile wiring and fixture assertions only;
- no generator, validator, schema, live smoke, decision, or artifact approval
  behavior changes.

Deferred scope:

- end-to-end one-command workflow orchestration outside Hermes action mapping.

Acceptance criteria:

- Hermes dry-run renders the competitor brief generator command with the
  provided run id and output path;
- unauthorized identity cannot execute the mutating generator action;
- authorized Hermes generator execution creates a valid competitor brief and
  records manifest metadata;
- Hermes validation action validates the generated brief through a run-scoped
  brief path and rejects parent traversal, dot-run collapse, symlink escapes,
  and symlinked run roots outside the run directory;
- Hermes generation does not approve planning artifacts.

Validation command:

```bash
bash -n scripts/run-golden-fixtures.sh scripts/run-hermes-action.sh scripts/validate-hermes-actions.sh scripts/validate-boss-idea-run-competitor-brief.sh
RUN_PREFIX=bir13e-fix4 scripts/run-golden-fixtures.sh
scripts/validate-agentic-system.sh
PROFILE=boss-idea-response scripts/validate-agentic-system.sh
scripts/validate-hermes-actions.sh
scripts/validate-identity-policy.sh
scripts/privacy-scan-tracked.sh
git diff --check
```

Rollback notes: remove the Hermes competitor brief actions, README action rows,
generated action fixture assertions, and this BIR-13E metadata. Keep BIR-13A-D.

AIT review path:
`agentic/reviews/boss-idea-response/bir-13e/round-<n>.json`.

Maximum review rounds: 5.

AIT result: round 5 passed at
`agentic/reviews/boss-idea-response/bir-13e/round-5-review.yaml`.

Staff+ escalation path: if round 5 fails, keep the generator command manual-only
and defer Hermes exposure.

## BIR-14: Live Crawler Safety Hardening

Status: completed.

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

### BIR-14A: Observed Network Metadata Contract

Status: completed by Staff+ resolution after AIT round 5.

Owner role: Staff Security Engineer.

Dependencies: BIR-11 live smoke foundation and BIR-13 competitor brief closure.

Scope:

- define a crawl-log schema contract for observed network metadata;
- add a run-local validator for crawl-log metadata shape;
- add deterministic valid/invalid fixtures for live and fixture-mode crawl logs;
- document that live success entries require final URL and public observed IP
  metadata while fixture modes remain deterministic.

Files touched:

- `agentic/schemas/boss-idea-crawl-log.schema.yaml`
- `agentic/fixtures/boss-idea-response/valid-crawl-log.yaml`
- `agentic/fixtures/boss-idea-response/valid-crawl-log-fixture-mode.yaml`
- `agentic/fixtures/boss-idea-response/invalid-crawl-log-live-missing-observed-network.yaml`
- `agentic/fixtures/boss-idea-response/invalid-crawl-log-private-observed-ip.yaml`
- `agentic/fixtures/boss-idea-response/invalid-crawl-log-*-observed-ip.yaml`
- `agentic/fixtures/boss-idea-response/invalid-crawl-log-authority-*.yaml`
- `scripts/validate-boss-idea-crawl-log.sh`
- `scripts/run-golden-fixtures.sh`
- `scripts/validate-agentic-system.sh`
- `agentic/pipeline.yaml`
- `docs/architecture/boss-idea-modules/crawl4ai-market-discovery-adapter.md`
- `docs/backlog/boss-idea-productionization-slices.md`

Write scope:

- schema, validator, deterministic fixtures, and docs only;
- no crawler behavior, helper output, live enforcement, Hermes action, quality
  artifact integration, or provider behavior changes.

Deferred scope:

- BIR-14B Crawl4AI helper output extension;
- BIR-14C live-mode enforcement;
- BIR-14D redirect/DNS rebinding negative fixtures;
- BIR-14E crawl-log and quality artifact integration.

Acceptance criteria:

- schema requires observed network metadata fields for live success entries;
- validator accepts live crawl logs with final URL, final host, observed public
  IP, observed timestamp, and source;
- validator accepts fixture-mode crawl logs without observed network metadata;
- validator rejects live success entries missing observed network metadata;
- validator rejects observed non-public IPs, including private, loopback,
  link-local, multicast, metadata-service, unspecified, broadcast,
  documentation, CGNAT, IPv6 special-purpose, deprecated site-local, and
  reserved non-public IPv6 ranges;
- validator enforces schema allowlisted evidence-only authority wording.

Validation command:

```bash
bash -n scripts/validate-boss-idea-crawl-log.sh scripts/run-golden-fixtures.sh scripts/validate-agentic-system.sh
scripts/validate-boss-idea-crawl-log.sh agentic/fixtures/boss-idea-response/valid-crawl-log.yaml
scripts/validate-boss-idea-crawl-log.sh agentic/fixtures/boss-idea-response/valid-crawl-log-fixture-mode.yaml
RUN_PREFIX=bir14a-fix5 scripts/run-golden-fixtures.sh
scripts/validate-agentic-system.sh
PROFILE=boss-idea-response scripts/validate-agentic-system.sh
scripts/validate-hermes-actions.sh
scripts/validate-identity-policy.sh
scripts/privacy-scan-tracked.sh
git diff --check
```

Rollback notes: remove the crawl-log schema, validator, crawl-log fixtures,
fixture assertions, pipeline/scaffold registration, architecture docs, and this
BIR-14A metadata. Keep BIR-11 and BIR-13.

AIT review path:
`agentic/reviews/boss-idea-response/bir-14a/round-<n>.json`.

Staff+ resolution:
`agentic/reviews/boss-idea-response/bir-14a/staff-escalation-decision.md`.

Maximum review rounds: 5.

### BIR-14E: Crawl-Log And Quality Artifact Integration

Status: completed after AIT round 1.

Owner role: Staff Security Engineer with QA Lead review.

Dependencies: BIR-14A through BIR-14D.

Scope:

- persist helper `observed_network` metadata into live crawl-log success
  entries;
- validate generated crawl logs with the BIR-14A crawl-log validator;
- add public-safe observed-network counts to market-discovery quality checks and
  manifest crawl metadata;
- keep raw crawl output ignored and untracked.

Files touched:

- `scripts/crawl-boss-idea-market.sh`
- `scripts/run-golden-fixtures.sh`
- `scripts/validate-boss-idea-market-discovery-quality.sh`
- `agentic/schemas/boss-idea-market-discovery-quality.schema.yaml`
- `docs/architecture/boss-idea-modules/crawl4ai-market-discovery-adapter.md`
- `docs/backlog/boss-idea-productionization-slices.md`

Write scope:

- crawl-log success-entry metadata, generated crawl-log validation, quality
  check counts, manifest summary counts, deterministic fixtures, and docs.

Deferred scope:

- provider health and fallback operations move to BIR-15.

Acceptance criteria:

- live crawl-log success entries include validated `observed_network`;
- generated crawl logs pass `validate-boss-idea-crawl-log.sh`;
- market-discovery quality includes public-safe observed-network summary counts;
- manifest crawl metadata includes public-safe observed-network summary counts;
- fixture mode remains deterministic and no-network.

Validation command:

```bash
bash -n scripts/crawl-boss-idea-market.sh scripts/run-golden-fixtures.sh scripts/validate-boss-idea-market-discovery-quality.sh
RUN_PREFIX=bir14e scripts/run-golden-fixtures.sh
scripts/validate-agentic-system.sh
PROFILE=boss-idea-response scripts/validate-agentic-system.sh
scripts/privacy-scan-tracked.sh
git diff --check
```

Rollback notes: remove crawl-log observed-network persistence, generated
crawl-log validation, quality/manifest observed-network summary fields,
BIR-14E golden assertions, and this BIR-14E metadata. Keep BIR-14A through
BIR-14D.

AIT review path:
`agentic/reviews/boss-idea-response/bir-14e/round-<n>.json`.

Maximum review rounds: 5.

### BIR-14D: Redirect And DNS Rebinding Negative Fixtures

Status: completed after AIT round 1.

Owner role: Staff Security Engineer.

Dependencies: BIR-14C live-mode enforcement.

Scope:

- enforce that helper observed IPs match the observed final host's
  post-crawl DNS or literal resolution;
- add deterministic no-network negatives for private final URL, observed IP
  mismatch, and final-host/final-url mismatch;
- keep observed metadata persistence deferred to BIR-14E.

Files touched:

- `scripts/crawl-boss-idea-market.sh`
- `scripts/run-golden-fixtures.sh`
- `docs/backlog/boss-idea-productionization-slices.md`

Write scope:

- live helper-boundary DNS/redirect enforcement and deterministic fixtures only.

Deferred scope:

- BIR-14E crawl-log and quality artifact integration.

Acceptance criteria:

- helper observed IPs must intersect the observed final host's post-crawl
  public resolution;
- helper private final URLs fail before output acceptance;
- helper final-host/final-url mismatches fail;
- fixture mode remains deterministic and no-network.

Validation command:

```bash
bash -n scripts/crawl-boss-idea-market.sh scripts/run-golden-fixtures.sh
RUN_PREFIX=bir14d scripts/run-golden-fixtures.sh
scripts/validate-agentic-system.sh
PROFILE=boss-idea-response scripts/validate-agentic-system.sh
scripts/privacy-scan-tracked.sh
git diff --check
```

Rollback notes: remove observed-IP/final-host resolution enforcement,
BIR-14D golden fixtures, and this BIR-14D metadata. Keep BIR-14A through
BIR-14C.

AIT review path:
`agentic/reviews/boss-idea-response/bir-14d/round-<n>.json`.

Maximum review rounds: 5.

### BIR-14C: Live-Mode Enforcement

Status: completed after AIT round 1.

Owner role: Staff Security Engineer.

Dependencies: BIR-14A observed network metadata contract and BIR-14B helper
output extension.

Scope:

- enforce that live helper observed final URL/host stays inside the per-run
  approved host allowlist;
- keep helper observed IP validation aligned with the BIR-14A public-IP policy;
- add deterministic no-network live helper negatives;
- leave crawl-log and quality artifact persistence for BIR-14E.

Files touched:

- `scripts/crawl-boss-idea-market.sh`
- `scripts/run-golden-fixtures.sh`
- `docs/backlog/boss-idea-productionization-slices.md`

Write scope:

- live helper-boundary enforcement and deterministic fixtures only;
- no default live network execution and no observed metadata persistence.

Deferred scope:

- BIR-14D redirect/DNS rebinding negative fixture expansion;
- BIR-14E crawl-log and quality artifact integration.

Acceptance criteria:

- live helper payloads whose observed final host is outside the per-run
  allowlist fail closed;
- helper observed IP metadata still rejects malformed and non-public IPs;
- deterministic fixture mode remains no-network;
- observed metadata is not yet persisted into crawl logs or quality artifacts.

Validation command:

```bash
bash -n scripts/crawl-boss-idea-market.sh scripts/run-golden-fixtures.sh
RUN_PREFIX=bir14c scripts/run-golden-fixtures.sh
scripts/validate-agentic-system.sh
PROFILE=boss-idea-response scripts/validate-agentic-system.sh
scripts/privacy-scan-tracked.sh
git diff --check
```

Rollback notes: remove final-host allowlist enforcement, BIR-14C golden
fixtures, and this BIR-14C metadata. Keep BIR-14A and BIR-14B.

AIT review path:
`agentic/reviews/boss-idea-response/bir-14c/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: if round 5 fails, keep live crawl behavior unchanged
and split schema-only contract from validator fixture enforcement.

### BIR-14B: Crawl4AI Helper Output Extension

Status: completed after AIT round 3.

Owner role: Staff Platform Engineer with Staff Security Engineer review.

Dependencies: BIR-14A observed network metadata contract.

Scope:

- extend the Python Crawl4AI helper successful JSON payload with
  `observed_network`;
- validate helper `observed_network` shape at the Ruby wrapper boundary;
- keep crawl-log persistence and strict live-mode artifact validation deferred
  to BIR-14C through BIR-14E;
- add deterministic no-network helper contract coverage.

Files touched:

- `scripts/lib/boss_idea_crawl4ai.py`
- `scripts/crawl-boss-idea-market.sh`
- `scripts/run-golden-fixtures.sh`
- `docs/architecture/boss-idea-modules/crawl4ai-market-discovery-adapter.md`
- `docs/backlog/boss-idea-productionization-slices.md`

Write scope:

- helper output contract, wrapper payload validation, deterministic fixtures,
  and docs only;
- no default live network execution, no provider behavior changes, and no
  crawl-log/quality artifact persistence of observed metadata yet.

Deferred scope:

- BIR-14C live-mode enforcement;
- BIR-14D redirect/DNS rebinding negative fixtures;
- BIR-14E crawl-log and quality artifact integration.

Acceptance criteria:

- successful helper payloads include requested URL, final URL, final host,
  observed IPs, resolved timestamp, and source;
- wrapper rejects successful live helper payloads missing `observed_network`;
- helper contract tests remain deterministic and no-network;
- fixture mode remains deterministic.

Validation command:

```bash
bash -n scripts/crawl-boss-idea-market.sh scripts/run-golden-fixtures.sh
python3 -m py_compile scripts/lib/boss_idea_crawl4ai.py
RUN_PREFIX=bir14b scripts/run-golden-fixtures.sh
scripts/validate-agentic-system.sh
PROFILE=boss-idea-response scripts/validate-agentic-system.sh
scripts/privacy-scan-tracked.sh
git diff --check
```

Rollback notes: remove helper observed-network output, wrapper helper-payload
validation, golden fixture assertions, architecture docs, and this BIR-14B
metadata. Keep BIR-14A.

AIT review path:
`agentic/reviews/boss-idea-response/bir-14b/round-<n>.json`.

Maximum review rounds: 5.

## BIR-15: Provider Health And Fallback Operations

Status: completed.

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

### BIR-15A: Provider Health Schema And Retention Policy

Status: completed.

Owner role: QA Lead.

Source artifacts:

- `docs/architecture/boss-idea-productionization-roadmap.md`
- `docs/architecture/boss-idea-modules/crawl4ai-market-discovery-adapter.md`
- `docs/runbooks/boss-idea-no-paid-market-search.md`

Dependencies: BIR-14 crawl-log and discovery-quality public-safety metadata.

Scope:

- define a provider health artifact schema for scrubbed aggregate health
  summaries;
- define a fixed retention policy for raw provider-health events and scrubbed
  summaries;
- define fallback reason taxonomy shared by health summaries and later fallback
  recommendation slices;
- require explicit challenge/captcha counters;
- require advisory-only authority wording;
- validate that tracked provider health artifacts are public-safe summaries
  without raw URLs, hosts, IPs, queries, provider responses, crawl bodies, or
  credentials.

Deferred scope:

- recording provider health events from market discovery runs;
- generating periodic provider health reports;
- recommending retry, fallback, or escalation actions;
- changing provider priority or automatically approving fallback execution.

Files touched:

- `agentic/schemas/boss-idea-provider-health.schema.yaml`
- `scripts/validate-boss-idea-provider-health.sh`
- `agentic/fixtures/boss-idea-response/valid-provider-health.yaml`
- `agentic/fixtures/boss-idea-response/invalid-provider-health-*.yaml`
- `scripts/run-golden-fixtures.sh`
- `scripts/validate-agentic-system.sh`
- `agentic/pipeline.yaml`
- `docs/architecture/boss-idea-modules/crawl4ai-market-discovery-adapter.md`
- `docs/backlog/boss-idea-productionization-slices.md`

Acceptance criteria:

- challenge/captcha counters are required at provider and summary levels;
- fallback reasons must use the BIR-15A taxonomy;
- raw provider-health events are retained only under ignored paths for 14 days;
- tracked scrubbed summaries use a 90-day retention policy and counts-only
  content;
- provider health authority is advisory only and cannot approve provider
  switches, fallbacks, roadmap, budget, artifacts, or implementation.

Validation command:

```bash
bash -n scripts/validate-boss-idea-provider-health.sh scripts/run-golden-fixtures.sh scripts/validate-agentic-system.sh
scripts/validate-boss-idea-provider-health.sh agentic/fixtures/boss-idea-response/valid-provider-health.yaml
RUN_PREFIX=bir15a scripts/run-golden-fixtures.sh
scripts/validate-agentic-system.sh
PROFILE=boss-idea-response scripts/validate-agentic-system.sh
scripts/privacy-scan-tracked.sh
git diff --check
```

Negative-path tests:

- authority wording that approves provider selection or fallback execution
  fails;
- fallback reason outside the schema taxonomy fails;
- retention policy drift fails;
- raw URL content in a tracked provider-health artifact fails;
- summary challenge/captcha counters that do not match provider counters fail.

Rollback notes: remove the provider-health schema, validator, fixtures,
validation registration, docs, and this BIR-15A metadata. Keep BIR-14.

AIT review path:
`agentic/reviews/boss-idea-response/bir-15a/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: if round 5 fails, keep BIR-15 event recording deferred
and split the provider health contract into separate retention, taxonomy, and
public-safety schema slices.

### BIR-15B: Provider Health Event Recording From Discovery Runs

Status: completed after AIT round 1.

Owner role: QA Lead.

Dependencies: BIR-15A provider health schema, retention policy, and fallback
reason taxonomy.

Scope:

- add a provider-health event log schema for ignored run evidence;
- validate provider attempt, success, failure, challenge/captcha, and fallback
  event counts;
- record `provider-health-events.yaml` from `crawl-boss-idea-market.sh`
  successful runs;
- record failed provider-health events for provider discovery/crawl failures
  after provider context is known;
- classify challenge/captcha, timeout, policy block, insufficient-results, and
  provider-error reasons using the BIR-15A taxonomy;
- keep event logs public-safe and under ignored `agentic/runs/<run-id>/`
  evidence paths.

Deferred scope:

- summarizing provider health across multiple runs;
- provider retry/fallback recommendation rules;
- automatic provider switching or fallback approval;
- changing provider priority.

Files touched:

- `agentic/schemas/boss-idea-provider-health-events.schema.yaml`
- `scripts/validate-boss-idea-provider-health-events.sh`
- `agentic/fixtures/boss-idea-response/valid-provider-health-events.yaml`
- `agentic/fixtures/boss-idea-response/invalid-provider-health-events-*.yaml`
- `scripts/crawl-boss-idea-market.sh`
- `scripts/run-golden-fixtures.sh`
- `scripts/validate-agentic-system.sh`
- `agentic/pipeline.yaml`
- `agentic/README.md`
- `docs/architecture/boss-idea-modules/crawl4ai-market-discovery-adapter.md`
- `docs/backlog/boss-idea-productionization-slices.md`

Acceptance criteria:

- successful market discovery runs write a validated ignored
  `provider-health-events.yaml`;
- lower-trust fallback providers record `fallback_used` event counts with
  taxonomy-constrained reasons;
- challenge/captcha failures record `challenge_or_captcha` counts before exit;
- event logs contain only public-safe event labels and aggregate counts;
- event logs remain advisory evidence only and do not approve provider changes
  or fallback execution.

Validation command:

```bash
bash -n scripts/crawl-boss-idea-market.sh scripts/validate-boss-idea-provider-health-events.sh scripts/run-golden-fixtures.sh scripts/validate-agentic-system.sh
scripts/validate-boss-idea-provider-health-events.sh agentic/fixtures/boss-idea-response/valid-provider-health-events.yaml
RUN_PREFIX=bir15b scripts/run-golden-fixtures.sh
scripts/validate-agentic-system.sh
PROFILE=boss-idea-response scripts/validate-agentic-system.sh
scripts/privacy-scan-tracked.sh
git diff --check
```

Negative-path tests:

- provider-health event log with a fallback reason outside the taxonomy fails;
- provider-health event log with raw query content fails;
- event count summary that drops challenge/captcha events fails;
- event authority wording that approves provider selection or fallback
  execution fails;
- DuckDuckGo HTML challenge fixture writes a failed event log with
  `challenge_or_captcha_count: 1`.

Rollback notes: remove provider-health event schema, validator, fixtures,
event recording from the market discovery script, validation registration, docs,
and this BIR-15B metadata. Keep BIR-15A.

AIT review path:
`agentic/reviews/boss-idea-response/bir-15b/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: if round 5 fails, keep provider-health summaries manual
and defer automatic event recording until the discovery script can expose a
cleaner provider execution boundary.

### BIR-15C: Provider Health Summary Report

Status: completed after AIT round 1.

Owner role: QA Lead.

Dependencies: BIR-15A provider health schema and BIR-15B provider health event
recording.

Scope:

- add a command that reads one or more ignored provider-health event logs;
- aggregate provider attempts, successes, failures, challenge/captcha events,
  timeout failures, policy-block failures, and fallback reason counts;
- write a scrubbed provider-health summary that validates against the BIR-15A
  provider health schema;
- derive advisory provider status from aggregate counts;
- keep the report advisory-only and public-safe.

Deferred scope:

- fallback recommendation rules;
- automatic provider switching;
- scheduling or retaining rolling reports;
- changing provider priority or approval authority.

Files touched:

- `scripts/summarize-boss-idea-provider-health.sh`
- `scripts/run-golden-fixtures.sh`
- `scripts/validate-agentic-system.sh`
- `agentic/pipeline.yaml`
- `agentic/README.md`
- `docs/architecture/boss-idea-modules/crawl4ai-market-discovery-adapter.md`
- `docs/backlog/boss-idea-productionization-slices.md`

Acceptance criteria:

- summary command fails if referenced event logs are missing or invalid;
- generated summaries pass `validate-boss-idea-provider-health.sh`;
- challenge/captcha and fallback reason counts are preserved in summaries;
- output contains only schema-approved scrubbed counts and labels;
- provider health remains advisory evidence and cannot approve provider changes
  or fallback execution.

Validation command:

```bash
bash -n scripts/summarize-boss-idea-provider-health.sh scripts/run-golden-fixtures.sh scripts/validate-agentic-system.sh
RUN_PREFIX=bir15c scripts/run-golden-fixtures.sh
scripts/validate-agentic-system.sh
PROFILE=boss-idea-response scripts/validate-agentic-system.sh
scripts/privacy-scan-tracked.sh
git diff --check
```

Negative-path tests:

- summarizing a run without `provider-health-events.yaml` fails;
- generated summary with challenge/captcha event input preserves
  `total_challenge_or_captcha_count`;
- generated summary with fallback events preserves taxonomy-constrained fallback
  reason counts.

Rollback notes: remove the summary command, golden fixture coverage, validation
registration, docs, and this BIR-15C metadata. Keep BIR-15A/B event logs.

AIT review path:
`agentic/reviews/boss-idea-response/bir-15c/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: if round 5 fails, keep event logs as raw ignored
evidence and defer public-safe summaries until BIR-15C can be split into
single-run and multi-run summary slices.

### BIR-15D: Fallback Recommendation Rules Without Automatic Approval

Status: completed after AIT round 1.

Owner role: QA Lead.

Dependencies: BIR-15A provider health schema and BIR-15C provider health
summary report.

Scope:

- define a fallback advisory artifact schema;
- add a validator that blocks automatic execution, approval status drift,
  invalid reason labels, raw provider content, and non-advisory authority;
- add an advisory command that reads a validated provider-health summary and
  emits human-decision-only guidance;
- map provider health counters to advisory actions without changing provider
  priority or executing fallbacks.

Deferred scope:

- automatically switching providers;
- approving fallback execution;
- recording Staff+ decisions;
- scheduling or publishing advisory reports.

Files touched:

- `agentic/schemas/boss-idea-provider-fallback-advisory.schema.yaml`
- `scripts/validate-boss-idea-provider-fallback-advisory.sh`
- `scripts/recommend-boss-idea-provider-fallback.sh`
- `agentic/fixtures/boss-idea-response/valid-provider-fallback-advisory.yaml`
- `agentic/fixtures/boss-idea-response/invalid-provider-fallback-advisory-*.yaml`
- `scripts/run-golden-fixtures.sh`
- `scripts/validate-agentic-system.sh`
- `agentic/pipeline.yaml`
- `agentic/README.md`
- `docs/architecture/boss-idea-modules/crawl4ai-market-discovery-adapter.md`
- `docs/backlog/boss-idea-productionization-slices.md`

Acceptance criteria:

- advisory output requires `requires_human_decision: true`;
- advisory output requires `automatic_execution_allowed: false`;
- advisory output requires `approval_status: not_approved`;
- reason labels are constrained to the BIR-15 taxonomy plus
  `provider_healthy`;
- generated advisory output passes validator checks and remains public-safe;
- advisory rules do not mutate provider priority, manifest decisions, or
  fallback execution behavior.

Validation command:

```bash
bash -n scripts/validate-boss-idea-provider-fallback-advisory.sh scripts/recommend-boss-idea-provider-fallback.sh scripts/run-golden-fixtures.sh scripts/validate-agentic-system.sh
scripts/validate-boss-idea-provider-fallback-advisory.sh agentic/fixtures/boss-idea-response/valid-provider-fallback-advisory.yaml
RUN_PREFIX=bir15d scripts/run-golden-fixtures.sh
scripts/validate-agentic-system.sh
PROFILE=boss-idea-response scripts/validate-agentic-system.sh
scripts/privacy-scan-tracked.sh
git diff --check
```

Negative-path tests:

- automatic execution enabled fails;
- approval status other than `not_approved` fails;
- invalid reason label fails;
- raw URL content fails.

Rollback notes: remove fallback advisory schema, validator, command, fixtures,
validation registration, docs, and this BIR-15D metadata. Keep BIR-15A through
BIR-15C.

AIT review path:
`agentic/reviews/boss-idea-response/bir-15d/round-<n>.json`.

Maximum review rounds: 5.

Staff+ escalation path: if round 5 fails, keep provider-health summaries
advisory-only and defer fallback guidance until a narrower rule taxonomy can be
reviewed.

### BIR-15E: Fixtures, Privacy Scan, And Docs Closure

Status: completed after AIT round 1.

Owner role: QA Lead.

Dependencies: BIR-15A through BIR-15D.

Scope:

- add final cross-schema fixture assertions for provider-health taxonomy,
  retention, and advisory approval constraints;
- document provider health event, summary, and fallback advisory workflow in
  the no-paid market-search runbook;
- keep privacy scan and tracked-file checks in the BIR-15 validation path;
- close BIR-15 without adding new provider behavior.

Acceptance criteria:

- event taxonomy matches the provider-health fallback reason taxonomy;
- advisory reason labels include the provider-health taxonomy and keep
  `approval_status: not_approved`;
- event retention policy matches the provider-health retention policy;
- runbook states provider health and fallback advisory artifacts are
  public-safe, advisory-only, and non-executing;
- full golden fixtures, scaffold validation, profile validation, privacy scan,
  and diff whitespace checks pass.

Validation command:

```bash
RUN_PREFIX=bir15e scripts/run-golden-fixtures.sh
scripts/validate-agentic-system.sh
PROFILE=boss-idea-response scripts/validate-agentic-system.sh
scripts/privacy-scan-tracked.sh
git diff --check
```

Rollback notes: remove BIR-15E cross-schema fixture assertions, runbook updates,
and this metadata. Keep BIR-15A through BIR-15D if their independent reviews
remain valid.

AIT review path:
`agentic/reviews/boss-idea-response/bir-15e/round-<n>.json`.

Maximum review rounds: 5.

## BIR-16: Documentation State Cleanup

Status: completed by the productionization documentation update.

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
