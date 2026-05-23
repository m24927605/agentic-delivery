#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RUN_PREFIX="${RUN_PREFIX:-h20-golden}"
PLANNING_RUN="${RUN_PREFIX}-planning"
NO_APPROVED_RUN="${RUN_PREFIX}-no-approved"
IMPLEMENTATION_RUN="${RUN_PREFIX}-implementation"
BAD_SCHEMA_RUN="${RUN_PREFIX}-bad-schema"
BOSS_IDEA_RUN="${RUN_PREFIX}-boss-idea"
BOSS_DECISION_RUN="${RUN_PREFIX}-boss-decision"
BOSS_MEMO_BAD_ID_RUN="${RUN_PREFIX}-boss-memo-bad-id"
BOSS_MEMO_BAD_PROFILE_RUN="${RUN_PREFIX}-boss-memo-bad-profile"
BOSS_MEMO_BAD_ARTIFACTS_RUN="${RUN_PREFIX}-boss-memo-bad-artifacts"
BOSS_DECISION_BAD_ID_RUN="${RUN_PREFIX}-boss-decision-bad-id"
BOSS_DECISION_BAD_PROFILE_RUN="${RUN_PREFIX}-boss-decision-bad-profile"
BOSS_IMPLEMENTATION_RUN="${RUN_PREFIX}-boss-implementation"
REQUESTED_ARTIFACT="docs/architecture/example-requested-artifact.md"

cleanup() {
  rm -rf \
    "agentic/runs/$PLANNING_RUN" \
    "agentic/runs/$NO_APPROVED_RUN" \
    "agentic/runs/${NO_APPROVED_RUN}-impl" \
    "agentic/runs/$IMPLEMENTATION_RUN" \
    "agentic/runs/$BAD_SCHEMA_RUN" \
    "agentic/runs/$BOSS_IDEA_RUN" \
    "agentic/runs/$BOSS_DECISION_RUN" \
    "agentic/runs/$BOSS_MEMO_BAD_ID_RUN" \
    "agentic/runs/$BOSS_MEMO_BAD_PROFILE_RUN" \
    "agentic/runs/$BOSS_MEMO_BAD_ARTIFACTS_RUN" \
    "agentic/runs/$BOSS_DECISION_BAD_ID_RUN" \
    "agentic/runs/$BOSS_DECISION_BAD_PROFILE_RUN" \
    "agentic/runs/$BOSS_IMPLEMENTATION_RUN" \
    "agentic/reviews/auto-doc-to-implementation/h16/$IMPLEMENTATION_RUN" \
    "agentic/reviews/auto-doc-to-implementation/h16/$BOSS_IMPLEMENTATION_RUN" \
    "agentic/reviews/auto-doc-to-implementation/h18/$IMPLEMENTATION_RUN" \
    "agentic/reviews/auto-doc-to-implementation/h18/$BOSS_IMPLEMENTATION_RUN" \
    "agentic/reviews/auto-doc-to-implementation/$PLANNING_RUN"
  rm -f "$REQUESTED_ARTIFACT"
  rm -f /tmp/h20-*.log
  rm -f /tmp/h20-*.yaml
}

cleanup
trap cleanup EXIT

echo "fixture: scaffold validation"
scripts/validate-agentic-system.sh >/dev/null
scripts/validate-hermes-actions.sh >/dev/null
scripts/validate-identity-policy.sh >/dev/null
scripts/privacy-scan-tracked.sh >/dev/null

echo "fixture: schema validator rejects bad manifest"
mkdir -p "agentic/runs/$BAD_SCHEMA_RUN"
cat >"agentic/runs/$BAD_SCHEMA_RUN/implementation-manifest.yaml" <<'YAML'
---
schema_version: 99
run:
  id: h20-golden-bad-schema
  mode: implementation
  state: implementation_planned
  profile: default-delivery
  profile_path: agentic/profiles/default-delivery.yaml
approved_inputs: []
implementation_tasks: []
test_plan: []
review_attempts: []
worker_dispatches: []
worker_results: []
write_scope_leases: []
validation: []
release_notes: {}
YAML
if scripts/validate-manifest-schema.sh "$BAD_SCHEMA_RUN" >/tmp/h20-bad-schema.log 2>&1; then
  echo "expected bad schema manifest to fail" >&2
  exit 1
fi
grep -q "unsupported" /tmp/h20-bad-schema.log
rm -rf "agentic/runs/$BAD_SCHEMA_RUN"

echo "fixture: no approved artifacts blocks implementation"
RUN_ID="$NO_APPROVED_RUN" scripts/init-agentic-run.sh "H20 negative no approved artifact" >/dev/null
if RUN_ID="${NO_APPROVED_RUN}-impl" scripts/init-implementation-run.sh --planning-run "$NO_APPROVED_RUN" >/tmp/h20-no-approved.log 2>&1; then
  echo "expected no-approved implementation init to fail" >&2
  exit 1
fi
grep -q "blocked_missing_approved_artifact" /tmp/h20-no-approved.log

echo "fixture: unauthorized artifact approval is blocked"
if AIT_ACTOR=document_builder AIT_ACTOR_ROLE=document_builder scripts/update-artifact-status.sh "$NO_APPROVED_RUN" docs/architecture/agentic-delivery-system.md approved --reason "H20 fixture unauthorized approval" >/tmp/h20-unauthorized-approval.log 2>&1; then
  echo "expected unauthorized artifact approval to fail" >&2
  exit 1
fi
grep -q "authorization failed" /tmp/h20-unauthorized-approval.log

echo "fixture: requested artifact generation and template validation"
RUN_ID="$PLANNING_RUN" scripts/init-agentic-run.sh --goal-file agentic/fixtures/requested-artifacts-goal.md >/dev/null
scripts/generate-artifacts.sh "$PLANNING_RUN" >/dev/null
scripts/validate-artifact-templates.sh "$PLANNING_RUN" --artifact "$REQUESTED_ARTIFACT" >/dev/null

echo "fixture: review finding to revision task"
scripts/run-artifact-review-loop.sh "$PLANNING_RUN" --artifact "$REQUESTED_ARTIFACT" --result changes_requested >/dev/null
scripts/create-artifact-revision-tasks.sh --dry-run "$PLANNING_RUN" --artifact "$REQUESTED_ARTIFACT" >/dev/null

echo "fixture: approved implementation flow"
scripts/update-artifact-status.sh "$PLANNING_RUN" "$REQUESTED_ARTIFACT" approved --reason "H20 fixture approval" >/dev/null
RUN_ID="$IMPLEMENTATION_RUN" scripts/init-implementation-run.sh --planning-run "$PLANNING_RUN" --artifact "$REQUESTED_ARTIFACT" >/dev/null
scripts/validate-manifest-schema.sh "$IMPLEMENTATION_RUN" >/dev/null
scripts/generate-implementation-task-graph.sh "$IMPLEMENTATION_RUN" >/dev/null
scripts/dispatch-implementation-task.sh "$IMPLEMENTATION_RUN" impl-001 >/dev/null
scripts/validate-implementation-run.sh "$IMPLEMENTATION_RUN" >/dev/null
scripts/execute-implementation-task.sh --command "scripts/validate-agentic-system.sh >/dev/null && scripts/validate-implementation-run.sh $IMPLEMENTATION_RUN >/dev/null" "$IMPLEMENTATION_RUN" impl-001 >/dev/null
scripts/run-implementation-review-loop.sh "$IMPLEMENTATION_RUN" impl-001 --result pass >/dev/null

echo "fixture: repeated implementation review without change fails"
if scripts/run-implementation-review-loop.sh "$IMPLEMENTATION_RUN" impl-001 --result pass >/tmp/h20-repeat-review.log 2>&1; then
  echo "expected repeated implementation review to fail without changed content" >&2
  exit 1
fi
grep -q "implementation must change before another review round" /tmp/h20-repeat-review.log

echo "fixture: boss idea response validators"
scripts/init-boss-idea-run.sh --dry-run agentic/fixtures/boss-idea-response/valid-idea.md >/dev/null
if scripts/init-boss-idea-run.sh --dry-run agentic/fixtures/boss-idea-response/invalid-idea-missing-owner.md >/tmp/h20-boss-idea-owner.log 2>&1; then
  echo "expected missing boss idea owner to fail" >&2
  exit 1
fi
grep -q "decision_owner" /tmp/h20-boss-idea-owner.log
if scripts/init-boss-idea-run.sh --dry-run agentic/fixtures/boss-idea-response/invalid-idea-missing-response-time.md >/tmp/h20-boss-idea-time.log 2>&1; then
  echo "expected missing boss idea response time to fail" >&2
  exit 1
fi
grep -q "requested_response_time" /tmp/h20-boss-idea-time.log
if scripts/init-boss-idea-run.sh --dry-run agentic/fixtures/boss-idea-response/invalid-idea-missing-response-class.md >/tmp/h20-boss-idea-response-class.log 2>&1; then
  echo "expected missing boss idea response class to fail" >&2
  exit 1
fi
grep -q "response_class" /tmp/h20-boss-idea-response-class.log
if scripts/init-boss-idea-run.sh --dry-run agentic/fixtures/boss-idea-response/invalid-idea-bad-response-class.md >/tmp/h20-boss-idea-bad-response-class.log 2>&1; then
  echo "expected bad boss idea response class to fail" >&2
  exit 1
fi
grep -q "response_class is invalid" /tmp/h20-boss-idea-bad-response-class.log
if scripts/init-boss-idea-run.sh --dry-run ../outside.md >/tmp/h20-boss-idea-path.log 2>&1; then
  echo "expected non repo-local boss idea path to fail" >&2
  exit 1
fi
grep -q "invalid file path" /tmp/h20-boss-idea-path.log

RUN_ID="$BOSS_IDEA_RUN" scripts/init-boss-idea-run.sh agentic/fixtures/boss-idea-response/valid-idea.md >/dev/null
scripts/validate-manifest-schema.sh "$BOSS_IDEA_RUN" >/dev/null
grep -q "boss_idea_intake" "agentic/runs/$BOSS_IDEA_RUN/manifest.yaml"
ruby -ryaml -e 'm=YAML.load_file(ARGV.fetch(0)); abort("expected all artifacts planned") unless m.fetch("artifacts").all? { |a| a["status"] == "planned" }' "agentic/runs/$BOSS_IDEA_RUN/manifest.yaml"

scripts/collect-boss-idea-research.sh --dry-run "$BOSS_IDEA_RUN" >/tmp/h20-boss-market-query-pack.log
grep -q "competitor_landscape" /tmp/h20-boss-market-query-pack.log
scripts/collect-boss-idea-research.sh "$BOSS_IDEA_RUN" --search-results agentic/fixtures/boss-idea-response/valid-market-search-results.yaml --output "agentic/runs/$BOSS_IDEA_RUN/generated-research.md" >/dev/null
scripts/validate-boss-idea-research.sh "agentic/runs/$BOSS_IDEA_RUN/generated-research.md" >/dev/null
grep -q "boss_idea_market_research" "agentic/runs/$BOSS_IDEA_RUN/manifest.yaml"
ruby -ryaml -e 'm=YAML.load_file(ARGV.fetch(0)); abort("market research collection must not approve artifacts") unless m.fetch("artifacts").all? { |a| a["status"] == "planned" }' "agentic/runs/$BOSS_IDEA_RUN/manifest.yaml"
if scripts/collect-boss-idea-research.sh "$BOSS_IDEA_RUN" --search-results agentic/fixtures/boss-idea-response/valid-market-search-results.yaml --output "agentic/runs/$BOSS_IDEA_RUN/generated-research.md" >/tmp/h20-boss-market-existing-output.log 2>&1; then
  echo "expected market research overwrite without force to fail" >&2
  exit 1
fi
grep -q "already exists" /tmp/h20-boss-market-existing-output.log
scripts/collect-boss-idea-research.sh "$BOSS_IDEA_RUN" --force --search-results agentic/fixtures/boss-idea-response/valid-market-search-results.yaml --output "agentic/runs/$BOSS_IDEA_RUN/generated-research.md" >/dev/null
if scripts/collect-boss-idea-research.sh "$BOSS_IDEA_RUN" --search-results agentic/fixtures/boss-idea-response/invalid-market-search-missing-reference.yaml --output "agentic/runs/$BOSS_IDEA_RUN/bad-generated-research.md" >/tmp/h20-boss-market-missing-reference.log 2>&1; then
  echo "expected market search result missing reference to fail" >&2
  exit 1
fi
grep -q "reference" /tmp/h20-boss-market-missing-reference.log
if scripts/collect-boss-idea-research.sh "$BOSS_IDEA_RUN" --search-results agentic/fixtures/boss-idea-response/invalid-market-search-missing-mainstream.yaml --output "agentic/runs/$BOSS_IDEA_RUN/bad-generated-research.md" >/tmp/h20-boss-market-missing-signal.log 2>&1; then
  echo "expected market search result missing mainstream signal to fail" >&2
  exit 1
fi
grep -q "required signals" /tmp/h20-boss-market-missing-signal.log
if scripts/collect-boss-idea-research.sh "$BOSS_IDEA_RUN" --search-results agentic/fixtures/boss-idea-response/invalid-market-search-bad-query-id.yaml --output "agentic/runs/$BOSS_IDEA_RUN/bad-generated-research.md" >/tmp/h20-boss-market-bad-query.log 2>&1; then
  echo "expected market search result with bad query id to fail" >&2
  exit 1
fi
grep -q "query_id is unknown" /tmp/h20-boss-market-bad-query.log
if scripts/collect-boss-idea-research.sh "$BOSS_IDEA_RUN" --search-results agentic/fixtures/boss-idea-response/invalid-market-search-bad-source-type.yaml --output "agentic/runs/$BOSS_IDEA_RUN/bad-generated-research.md" >/tmp/h20-boss-market-bad-source-type.log 2>&1; then
  echo "expected market search result with bad source type to fail" >&2
  exit 1
fi
grep -q "source_type is invalid" /tmp/h20-boss-market-bad-source-type.log
if scripts/collect-boss-idea-research.sh "$BOSS_IDEA_RUN" --search-results agentic/fixtures/boss-idea-response/invalid-market-search-future-access-date.yaml --output "agentic/runs/$BOSS_IDEA_RUN/bad-generated-research.md" >/tmp/h20-boss-market-future-date.log 2>&1; then
  echo "expected market search result with future access date to fail" >&2
  exit 1
fi
grep -q "future" /tmp/h20-boss-market-future-date.log
if scripts/collect-boss-idea-research.sh "$BOSS_IDEA_RUN" --search-results agentic/fixtures/boss-idea-response/invalid-market-search-long-claim.yaml --output "agentic/runs/$BOSS_IDEA_RUN/bad-generated-research.md" >/tmp/h20-boss-market-long-claim.log 2>&1; then
  echo "expected market search result with long claim to fail" >&2
  exit 1
fi
grep -q "280 characters" /tmp/h20-boss-market-long-claim.log
if scripts/collect-boss-idea-research.sh "$BOSS_IDEA_RUN" --search-results agentic/fixtures/boss-idea-response/invalid-market-search-multiline-claim.yaml --output "agentic/runs/$BOSS_IDEA_RUN/bad-generated-research.md" >/tmp/h20-boss-market-multiline-claim.log 2>&1; then
  echo "expected market search result with multiline claim to fail" >&2
  exit 1
fi
grep -q "one line" /tmp/h20-boss-market-multiline-claim.log
if scripts/collect-boss-idea-research.sh "$BOSS_IDEA_RUN" --search-results agentic/fixtures/boss-idea-response/invalid-market-search-bad-url.yaml --output "agentic/runs/$BOSS_IDEA_RUN/bad-generated-research.md" >/tmp/h20-boss-market-bad-url.log 2>&1; then
  echo "expected market search result with bad url to fail" >&2
  exit 1
fi
grep -q "url must be http or https" /tmp/h20-boss-market-bad-url.log
if scripts/collect-boss-idea-research.sh "$BOSS_IDEA_RUN" --search-results agentic/fixtures/boss-idea-response/invalid-market-search-bad-reference-url.yaml --output "agentic/runs/$BOSS_IDEA_RUN/bad-generated-research.md" >/tmp/h20-boss-market-bad-reference-url.log 2>&1; then
  echo "expected market search result with bad reference url to fail" >&2
  exit 1
fi
grep -q "reference URL must be http or https" /tmp/h20-boss-market-bad-reference-url.log
if scripts/collect-boss-idea-research.sh "$BOSS_IDEA_RUN" --search-results agentic/fixtures/boss-idea-response/invalid-market-search-validator-bad-reference.yaml --output "agentic/runs/$BOSS_IDEA_RUN/bad-validator-research.md" >/tmp/h20-boss-market-validator-reference.log 2>&1; then
  echo "expected generated research with validator-rejected reference to fail" >&2
  exit 1
fi
grep -q "reference URL must be http or https" /tmp/h20-boss-market-validator-reference.log
if test -e "agentic/runs/$BOSS_IDEA_RUN/bad-validator-research.md" || test -e "agentic/runs/$BOSS_IDEA_RUN/bad-validator-research.md.tmp"; then
  echo "expected validator failure to clean partial research output" >&2
  exit 1
fi
if scripts/collect-boss-idea-research.sh "$BOSS_IDEA_RUN" --search-results agentic/fixtures/boss-idea-response/valid-market-search-results.yaml --output ../bad-market-research.md >/tmp/h20-boss-market-output-path.log 2>&1; then
  echo "expected market research output outside repo to fail" >&2
  exit 1
fi
grep -q "invalid output path" /tmp/h20-boss-market-output-path.log
if scripts/collect-boss-idea-research.sh "$BOSS_IDEA_RUN" --search-results agentic/fixtures/boss-idea-response/valid-market-search-results.yaml --output "agentic/runs/${BOSS_IDEA_RUN}-other/bad.md" >/tmp/h20-boss-market-output-run.log 2>&1; then
  echo "expected market research output outside run dir to fail" >&2
  exit 1
fi
grep -q "output path must stay under" /tmp/h20-boss-market-output-run.log
if find "agentic/runs/$BOSS_IDEA_RUN" -name "*.tmp" -print | grep -q .; then
  echo "expected market research collection failures to clean tmp files" >&2
  exit 1
fi

echo "fixture: boss idea Crawl4AI market discovery"
scripts/crawl-boss-idea-market.sh --dry-run "$BOSS_IDEA_RUN" >/tmp/h20-boss-market-crawl-dry.log
grep -q "competitor_landscape" /tmp/h20-boss-market-crawl-dry.log
scripts/crawl-boss-idea-market.sh --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider fixture --output "agentic/runs/$BOSS_IDEA_RUN/market-search-results.yaml" >/dev/null
test -f "agentic/runs/$BOSS_IDEA_RUN/market-search-results.yaml"
test -f "agentic/runs/$BOSS_IDEA_RUN/market-candidate-urls.yaml"
test -f "agentic/runs/$BOSS_IDEA_RUN/crawl4ai/crawl-log.yaml"
test -f "agentic/runs/$BOSS_IDEA_RUN/market-research.md"
scripts/validate-boss-idea-research.sh "agentic/runs/$BOSS_IDEA_RUN/market-research.md" >/dev/null
grep -q "boss_idea_market_crawl" "agentic/runs/$BOSS_IDEA_RUN/manifest.yaml"
git check-ignore -q "agentic/runs/$BOSS_IDEA_RUN/crawl4ai/raw/competitor-public-workflow.md"
ruby -ryaml -e 'm=YAML.load_file(ARGV.fetch(0)); c=m.fetch("boss_idea_market_crawl"); abort("expected fixture provider") unless c["provider"] == "fixture"; abort("expected source count") unless c["source_count"].to_i >= 2; abort("market crawl must not approve artifacts") unless m.fetch("artifacts").all? { |a| a["status"] == "planned" }' "agentic/runs/$BOSS_IDEA_RUN/manifest.yaml"

if BOSS_IDEA_LIVE_CRAWL=1 scripts/crawl-boss-idea-market.sh --live --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider fixture --output "agentic/runs/$BOSS_IDEA_RUN/bad-live-fixture-results.yaml" >/tmp/h20-boss-market-crawl-live-fixture.log 2>&1; then
  echo "expected live fixture crawl to fail" >&2
  exit 1
fi
grep -q "approved live provider" /tmp/h20-boss-market-crawl-live-fixture.log

if BOSS_IDEA_CRAWLER_USER_AGENT=bad scripts/crawl-boss-idea-market.sh --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider fixture --output "agentic/runs/$BOSS_IDEA_RUN/bad-user-agent-results.yaml" >/tmp/h20-boss-market-crawl-user-agent.log 2>&1; then
  echo "expected bad crawler user-agent to fail" >&2
  exit 1
fi
grep -q "user-agent" /tmp/h20-boss-market-crawl-user-agent.log

cat >"agentic/runs/$BOSS_IDEA_RUN/invalid-market-crawl-localhost.yaml" <<'YAML'
candidates:
  - id: bad-localhost
    query_id: competitor_landscape
    url: http://127.0.0.1/internal
    title: Bad localhost source
    snippet: Should fail before crawl.
    provider: fixture
    source_type: vendor_docs
    signal: competitor
    claim: This unsafe local target must not be crawled.
    content_path: agentic/fixtures/boss-idea-response/market-crawl-pages/competitor-workflow.html
YAML
if scripts/crawl-boss-idea-market.sh --force --results-only "$BOSS_IDEA_RUN" --seeds "agentic/runs/$BOSS_IDEA_RUN/invalid-market-crawl-localhost.yaml" --output "agentic/runs/$BOSS_IDEA_RUN/bad-localhost-results.yaml" >/tmp/h20-boss-market-crawl-localhost.log 2>&1; then
  echo "expected localhost market crawl seed to fail" >&2
  exit 1
fi
grep -q "blocked IP" /tmp/h20-boss-market-crawl-localhost.log

scripts/validate-boss-idea-research.sh agentic/fixtures/boss-idea-response/valid-research.md >/dev/null
if scripts/validate-boss-idea-research.sh agentic/fixtures/boss-idea-response/invalid-research-missing-sources.md >/tmp/h20-boss-research-missing-sources.log 2>&1; then
  echo "expected missing research sources to fail" >&2
  exit 1
fi
grep -q "sources" /tmp/h20-boss-research-missing-sources.log
if scripts/validate-boss-idea-research.sh agentic/fixtures/boss-idea-response/invalid-research-missing-claims.md >/tmp/h20-boss-research-missing-claims.log 2>&1; then
  echo "expected missing research claims to fail" >&2
  exit 1
fi
grep -q "claims" /tmp/h20-boss-research-missing-claims.log
if scripts/validate-boss-idea-research.sh agentic/fixtures/boss-idea-response/invalid-research-sources-not-array.md >/tmp/h20-boss-research-sources-type.log 2>&1; then
  echo "expected non-array research sources to fail" >&2
  exit 1
fi
grep -q "sources must be a non-empty array" /tmp/h20-boss-research-sources-type.log
if scripts/validate-boss-idea-research.sh agentic/fixtures/boss-idea-response/invalid-research-missing-citation.md >/tmp/h20-boss-research.log 2>&1; then
  echo "expected missing research citation to fail" >&2
  exit 1
fi
grep -q "source_ids" /tmp/h20-boss-research.log
if scripts/validate-boss-idea-research.sh agentic/fixtures/boss-idea-response/invalid-research-unknown-source.md >/tmp/h20-boss-research-unknown.log 2>&1; then
  echo "expected unknown research source to fail" >&2
  exit 1
fi
grep -q "unknown sources" /tmp/h20-boss-research-unknown.log
if scripts/validate-boss-idea-research.sh agentic/fixtures/boss-idea-response/invalid-research-bad-raw-path.md >/tmp/h20-boss-research-path.log 2>&1; then
  echo "expected bad raw evidence path to fail" >&2
  exit 1
fi
grep -q "raw_evidence_path" /tmp/h20-boss-research-path.log
if scripts/validate-boss-idea-research.sh agentic/fixtures/boss-idea-response/invalid-research-bad-url.md >/tmp/h20-boss-research-url.log 2>&1; then
  echo "expected bad research URL scheme to fail" >&2
  exit 1
fi
grep -q "sources\\[\\].url URL must be http or https" /tmp/h20-boss-research-url.log
if scripts/validate-boss-idea-research.sh agentic/fixtures/boss-idea-response/invalid-research-bad-reference-url.md >/tmp/h20-boss-research-reference-url.log 2>&1; then
  echo "expected bad research reference URL scheme to fail" >&2
  exit 1
fi
grep -q "sources\\[\\].reference URL must be http or https" /tmp/h20-boss-research-reference-url.log
if scripts/validate-boss-idea-research.sh agentic/fixtures/boss-idea-response/invalid-research-raw-path-traversal.md >/tmp/h20-boss-research-path-traversal.log 2>&1; then
  echo "expected traversal raw evidence path to fail" >&2
  exit 1
fi
grep -q "repo-local" /tmp/h20-boss-research-path-traversal.log
if scripts/validate-boss-idea-research.sh agentic/fixtures/boss-idea-response/invalid-research-bad-inference-label.md >/tmp/h20-boss-research-inference.log 2>&1; then
  echo "expected bad inference label to fail" >&2
  exit 1
fi
grep -q "label" /tmp/h20-boss-research-inference.log
if scripts/validate-boss-idea-research.sh agentic/fixtures/boss-idea-response/invalid-research-missing-inference-text.md >/tmp/h20-boss-research-inference-text.log 2>&1; then
  echo "expected missing inference text to fail" >&2
  exit 1
fi
grep -q "inferences.*text" /tmp/h20-boss-research-inference-text.log
if scripts/validate-boss-idea-research.sh agentic/fixtures/boss-idea-response/invalid-research-missing-inference-source-ids.md >/tmp/h20-boss-research-inference-sources.log 2>&1; then
  echo "expected missing inference source ids to fail" >&2
  exit 1
fi
grep -q "inferences.*source_ids" /tmp/h20-boss-research-inference-sources.log
if scripts/validate-boss-idea-research.sh agentic/fixtures/boss-idea-response/invalid-research-duplicate-source.md >/tmp/h20-boss-research-duplicate.log 2>&1; then
  echo "expected duplicate source id to fail" >&2
  exit 1
fi
grep -q "duplicates" /tmp/h20-boss-research-duplicate.log
if scripts/validate-boss-idea-research.sh agentic/fixtures/boss-idea-response/invalid-research-future-access-date.md >/tmp/h20-boss-research-future.log 2>&1; then
  echo "expected future access date to fail" >&2
  exit 1
fi
grep -q "future" /tmp/h20-boss-research-future.log
if scripts/validate-boss-idea-research.sh agentic/fixtures/boss-idea-response/invalid-research-bad-source-type.md >/tmp/h20-boss-research-source-type.log 2>&1; then
  echo "expected bad source type to fail" >&2
  exit 1
fi
grep -q "source_type is invalid" /tmp/h20-boss-research-source-type.log
if scripts/validate-boss-idea-research.sh agentic/fixtures/boss-idea-response/invalid-research-missing-reference.md >/tmp/h20-boss-research-reference.log 2>&1; then
  echo "expected missing stable reference to fail" >&2
  exit 1
fi
grep -q "reference" /tmp/h20-boss-research-reference.log

scripts/score-boss-idea-feasibility.sh --dry-run agentic/fixtures/boss-idea-response/valid-scorecard.yaml >/dev/null
if scripts/score-boss-idea-feasibility.sh --dry-run agentic/fixtures/boss-idea-response/invalid-scorecard-bad-recommendation-band.yaml >/tmp/h20-boss-score-band.log 2>&1; then
  echo "expected invalid scorecard recommendation band to fail" >&2
  exit 1
fi
grep -q "recommendation_band" /tmp/h20-boss-score-band.log
if scripts/score-boss-idea-feasibility.sh --dry-run agentic/fixtures/boss-idea-response/invalid-scorecard-missing-dimension.yaml >/tmp/h20-boss-score-missing.log 2>&1; then
  echo "expected scorecard missing dimension to fail" >&2
  exit 1
fi
grep -q "dependency_score" /tmp/h20-boss-score-missing.log
if scripts/score-boss-idea-feasibility.sh --dry-run agentic/fixtures/boss-idea-response/invalid-scorecard-out-of-range.yaml >/tmp/h20-boss-score-range.log 2>&1; then
  echo "expected out-of-range scorecard to fail" >&2
  exit 1
fi
grep -q "integer from 1 to 5" /tmp/h20-boss-score-range.log
if scripts/score-boss-idea-feasibility.sh --dry-run agentic/fixtures/boss-idea-response/invalid-scorecard-non-integer-score.yaml >/tmp/h20-boss-score-integer.log 2>&1; then
  echo "expected non-integer scorecard to fail" >&2
  exit 1
fi
grep -q "integer from 1 to 5" /tmp/h20-boss-score-integer.log
if scripts/score-boss-idea-feasibility.sh --dry-run agentic/fixtures/boss-idea-response/invalid-scorecard-high-risk-no-mitigation.yaml >/tmp/h20-boss-score.log 2>&1; then
  echo "expected high risk without mitigation to fail" >&2
  exit 1
fi
grep -q "mitigations" /tmp/h20-boss-score.log
if scripts/score-boss-idea-feasibility.sh --dry-run agentic/fixtures/boss-idea-response/invalid-scorecard-security-risk-no-mitigation.yaml >/tmp/h20-boss-score-security.log 2>&1; then
  echo "expected high security risk without mitigation to fail" >&2
  exit 1
fi
grep -q "mitigations" /tmp/h20-boss-score-security.log
if scripts/score-boss-idea-feasibility.sh --dry-run agentic/fixtures/boss-idea-response/invalid-scorecard-scalar-mitigation.yaml >/tmp/h20-boss-score-mitigation-type.log 2>&1; then
  echo "expected scalar scorecard mitigation to fail" >&2
  exit 1
fi
grep -q "mitigations must be a non-empty array" /tmp/h20-boss-score-mitigation-type.log
if scripts/score-boss-idea-feasibility.sh --dry-run agentic/fixtures/boss-idea-response/invalid-scorecard-low-confidence-no-followup.yaml >/tmp/h20-boss-score-confidence.log 2>&1; then
  echo "expected low confidence without follow-up to fail" >&2
  exit 1
fi
grep -q "low confidence" /tmp/h20-boss-score-confidence.log
if scripts/score-boss-idea-feasibility.sh --dry-run agentic/fixtures/boss-idea-response/invalid-scorecard-empty-unknowns.yaml >/tmp/h20-boss-score-confidence-empty.log 2>&1; then
  echo "expected empty low-confidence support to fail" >&2
  exit 1
fi
grep -q "low confidence" /tmp/h20-boss-score-confidence-empty.log
if scripts/score-boss-idea-feasibility.sh --dry-run agentic/fixtures/boss-idea-response/invalid-scorecard-low-confidence-scalar-unknowns.yaml >/tmp/h20-boss-score-confidence-type.log 2>&1; then
  echo "expected scalar low-confidence support to fail" >&2
  exit 1
fi
grep -q "unknowns must be an array" /tmp/h20-boss-score-confidence-type.log
if scripts/score-boss-idea-feasibility.sh --dry-run agentic/fixtures/boss-idea-response/invalid-scorecard-blank-rationale.yaml >/tmp/h20-boss-score-rationale.log 2>&1; then
  echo "expected blank score rationale to fail" >&2
  exit 1
fi
grep -q "score_rationale" /tmp/h20-boss-score-rationale.log
if scripts/score-boss-idea-feasibility.sh --dry-run agentic/fixtures/boss-idea-response/invalid-scorecard-numeric-rationale.yaml >/tmp/h20-boss-score-rationale-type.log 2>&1; then
  echo "expected numeric score rationale to fail" >&2
  exit 1
fi
grep -q "score_rationale" /tmp/h20-boss-score-rationale-type.log
if scripts/score-boss-idea-feasibility.sh --dry-run agentic/fixtures/boss-idea-response/invalid-scorecard-implementation-approval.yaml >/tmp/h20-boss-score-approval.log 2>&1; then
  echo "expected implementation approval in scorecard to fail" >&2
  exit 1
fi
grep -q "cannot approve implementation" /tmp/h20-boss-score-approval.log
if scripts/score-boss-idea-feasibility.sh --dry-run agentic/fixtures/boss-idea-response/invalid-scorecard-string-implementation-approval.yaml >/tmp/h20-boss-score-approval-type.log 2>&1; then
  echo "expected string implementation approval in scorecard to fail" >&2
  exit 1
fi
grep -q "implementation_approval must be boolean" /tmp/h20-boss-score-approval-type.log
if scripts/score-boss-idea-feasibility.sh --dry-run agentic/fixtures/boss-idea-response/invalid-scorecard-approved-artifact-status.yaml >/tmp/h20-boss-score-artifact-status.log 2>&1; then
  echo "expected approved artifact status in scorecard to fail" >&2
  exit 1
fi
grep -q "cannot approve implementation" /tmp/h20-boss-score-artifact-status.log
if scripts/score-boss-idea-feasibility.sh --dry-run agentic/fixtures/boss-idea-response/invalid-scorecard-mixed-case-approved-artifact-status.yaml >/tmp/h20-boss-score-artifact-status-case.log 2>&1; then
  echo "expected mixed-case approved artifact status in scorecard to fail" >&2
  exit 1
fi
grep -q "cannot approve implementation" /tmp/h20-boss-score-artifact-status-case.log
if scripts/score-boss-idea-feasibility.sh --dry-run agentic/fixtures/boss-idea-response/invalid-scorecard-padded-approved-artifact-status.yaml >/tmp/h20-boss-score-artifact-status-padding.log 2>&1; then
  echo "expected padded approved artifact status in scorecard to fail" >&2
  exit 1
fi
grep -q "cannot approve implementation" /tmp/h20-boss-score-artifact-status-padding.log

scripts/generate-boss-decision-memo.sh --output "agentic/runs/$BOSS_IDEA_RUN/generated-memo.md" "$BOSS_IDEA_RUN" >/dev/null
scripts/validate-boss-decision-memo.sh "agentic/runs/$BOSS_IDEA_RUN/generated-memo.md" >/dev/null
scripts/generate-boss-decision-memo.sh --recommendation mvp --output "agentic/runs/$BOSS_IDEA_RUN/generated-mvp-memo.md" "$BOSS_IDEA_RUN" >/dev/null
scripts/validate-boss-decision-memo.sh "agentic/runs/$BOSS_IDEA_RUN/generated-mvp-memo.md" >/dev/null
if scripts/generate-boss-decision-memo.sh --output "agentic/runs/$BOSS_IDEA_RUN/missing-run-memo.md" "${BOSS_IDEA_RUN}-missing" >/tmp/h20-boss-memo-missing-run.log 2>&1; then
  echo "expected decision memo generation for missing run to fail" >&2
  exit 1
fi
grep -q "blocked_missing_source" /tmp/h20-boss-memo-missing-run.log
mkdir -p "agentic/runs/$BOSS_MEMO_BAD_ID_RUN"
cat >"agentic/runs/$BOSS_MEMO_BAD_ID_RUN/manifest.yaml" <<YAML
schema_version: 1
run:
  id: wrong-run
  profile: boss-idea-response
artifacts:
  - path: docs/architecture/boss-idea-response-system.md
YAML
if scripts/generate-boss-decision-memo.sh --output "agentic/runs/$BOSS_MEMO_BAD_ID_RUN/memo.md" "$BOSS_MEMO_BAD_ID_RUN" >/tmp/h20-boss-memo-bad-id.log 2>&1; then
  echo "expected decision memo generation with bad manifest id to fail" >&2
  exit 1
fi
grep -q "blocked_schema_invalid" /tmp/h20-boss-memo-bad-id.log
mkdir -p "agentic/runs/$BOSS_MEMO_BAD_PROFILE_RUN"
cat >"agentic/runs/$BOSS_MEMO_BAD_PROFILE_RUN/manifest.yaml" <<YAML
schema_version: 1
run:
  id: $BOSS_MEMO_BAD_PROFILE_RUN
  profile: default-delivery
artifacts:
  - path: docs/architecture/boss-idea-response-system.md
YAML
if scripts/generate-boss-decision-memo.sh --output "agentic/runs/$BOSS_MEMO_BAD_PROFILE_RUN/memo.md" "$BOSS_MEMO_BAD_PROFILE_RUN" >/tmp/h20-boss-memo-bad-profile.log 2>&1; then
  echo "expected decision memo generation with bad profile to fail" >&2
  exit 1
fi
grep -q "blocked_schema_invalid" /tmp/h20-boss-memo-bad-profile.log
mkdir -p "agentic/runs/$BOSS_MEMO_BAD_ARTIFACTS_RUN"
cat >"agentic/runs/$BOSS_MEMO_BAD_ARTIFACTS_RUN/manifest.yaml" <<YAML
schema_version: 1
run:
  id: $BOSS_MEMO_BAD_ARTIFACTS_RUN
  profile: boss-idea-response
artifacts: {}
YAML
if scripts/generate-boss-decision-memo.sh --output "agentic/runs/$BOSS_MEMO_BAD_ARTIFACTS_RUN/memo.md" "$BOSS_MEMO_BAD_ARTIFACTS_RUN" >/tmp/h20-boss-memo-bad-artifacts.log 2>&1; then
  echo "expected decision memo generation with non-array artifacts to fail" >&2
  exit 1
fi
grep -q "artifacts must be a non-empty array" /tmp/h20-boss-memo-bad-artifacts.log
if scripts/generate-boss-decision-memo.sh --output ../bad-memo.md "$BOSS_IDEA_RUN" >/tmp/h20-boss-memo-output-path.log 2>&1; then
  echo "expected bad decision memo output path to fail" >&2
  exit 1
fi
grep -q "invalid output path" /tmp/h20-boss-memo-output-path.log
if scripts/generate-boss-decision-memo.sh --recommendation ship_now --output "agentic/runs/$BOSS_IDEA_RUN/bad-band-memo.md" "$BOSS_IDEA_RUN" >/tmp/h20-boss-memo-bad-band.log 2>&1; then
  echo "expected bad decision memo recommendation generation to fail" >&2
  exit 1
fi
grep -q "invalid recommendation" /tmp/h20-boss-memo-bad-band.log

scripts/validate-boss-decision-memo.sh agentic/fixtures/boss-idea-response/valid-memo.md >/dev/null
scripts/validate-boss-decision-memo.sh agentic/fixtures/boss-idea-response/valid-mvp-memo.md >/dev/null
scripts/validate-boss-decision-memo.sh agentic/fixtures/boss-idea-response/valid-memo-negated-approval.md >/dev/null
scripts/validate-boss-decision-memo.sh agentic/fixtures/boss-idea-response/valid-memo-approved-implementation.md >/dev/null
if scripts/validate-boss-decision-memo.sh agentic/fixtures/boss-idea-response/invalid-memo-missing-options.md >/tmp/h20-boss-memo.log 2>&1; then
  echo "expected memo missing options to fail" >&2
  exit 1
fi
grep -q "Options Considered" /tmp/h20-boss-memo.log
if scripts/validate-boss-decision-memo.sh agentic/fixtures/boss-idea-response/invalid-memo-invalid-recommendation.md >/tmp/h20-boss-memo-recommendation.log 2>&1; then
  echo "expected memo invalid recommendation to fail" >&2
  exit 1
fi
grep -q "recommendation is invalid" /tmp/h20-boss-memo-recommendation.log
if scripts/validate-boss-decision-memo.sh agentic/fixtures/boss-idea-response/invalid-memo-missing-timebox.md >/tmp/h20-boss-memo-timebox.log 2>&1; then
  echo "expected memo missing timebox to fail" >&2
  exit 1
fi
grep -q "requires Timebox" /tmp/h20-boss-memo-timebox.log
if scripts/validate-boss-decision-memo.sh agentic/fixtures/boss-idea-response/invalid-memo-missing-staffing.md >/tmp/h20-boss-memo-staffing.log 2>&1; then
  echo "expected memo missing staffing to fail" >&2
  exit 1
fi
grep -q "requires Staffing" /tmp/h20-boss-memo-staffing.log
if scripts/validate-boss-decision-memo.sh agentic/fixtures/boss-idea-response/invalid-memo-approval-claim-unapproved.md >/tmp/h20-boss-memo-approval.log 2>&1; then
  echo "expected memo approval claim without approved status to fail" >&2
  exit 1
fi
grep -q "cannot claim approval" /tmp/h20-boss-memo-approval.log
if scripts/validate-boss-decision-memo.sh agentic/fixtures/boss-idea-response/invalid-memo-recommendation-mismatch.md >/tmp/h20-boss-memo-mismatch.log 2>&1; then
  echo "expected memo recommendation mismatch to fail" >&2
  exit 1
fi
grep -q "recommendation mismatch" /tmp/h20-boss-memo-mismatch.log
if scripts/validate-boss-decision-memo.sh agentic/fixtures/boss-idea-response/invalid-memo-bad-artifact-status.md >/tmp/h20-boss-memo-status.log 2>&1; then
  echo "expected memo bad artifact status to fail" >&2
  exit 1
fi
grep -q "artifact_status is invalid" /tmp/h20-boss-memo-status.log
if scripts/validate-boss-decision-memo.sh agentic/fixtures/boss-idea-response/invalid-memo-missing-frontmatter.md >/tmp/h20-boss-memo-frontmatter.log 2>&1; then
  echo "expected memo missing frontmatter to fail" >&2
  exit 1
fi
grep -q "artifact_status is invalid" /tmp/h20-boss-memo-frontmatter.log
if scripts/validate-boss-decision-memo.sh agentic/fixtures/boss-idea-response/invalid-memo-missing-time-and-staffing.md >/tmp/h20-boss-memo-time-section.log 2>&1; then
  echo "expected memo missing time and staffing section to fail" >&2
  exit 1
fi
grep -q "Time And Staffing" /tmp/h20-boss-memo-time-section.log

scripts/plan-boss-idea-poc-mvp.sh poc >"agentic/runs/$BOSS_IDEA_RUN/generated-poc-plan.md"
scripts/validate-boss-idea-poc-mvp.sh "agentic/runs/$BOSS_IDEA_RUN/generated-poc-plan.md" >/dev/null
scripts/plan-boss-idea-poc-mvp.sh mvp >"agentic/runs/$BOSS_IDEA_RUN/generated-mvp-plan.md"
scripts/validate-boss-idea-poc-mvp.sh "agentic/runs/$BOSS_IDEA_RUN/generated-mvp-plan.md" >/dev/null
if scripts/plan-boss-idea-poc-mvp.sh pilot >/tmp/h20-boss-poc-generator-type.log 2>&1; then
  echo "expected bad POC/MVP generator work type to fail" >&2
  exit 1
fi
grep -q "work type" /tmp/h20-boss-poc-generator-type.log

scripts/validate-boss-idea-poc-mvp.sh agentic/fixtures/boss-idea-response/valid-poc-plan.md >/dev/null
scripts/validate-boss-idea-poc-mvp.sh agentic/fixtures/boss-idea-response/valid-mvp-plan.md >/dev/null
if scripts/validate-boss-idea-poc-mvp.sh agentic/fixtures/boss-idea-response/invalid-poc-plan-missing-timebox.md >/tmp/h20-boss-poc.log 2>&1; then
  echo "expected missing POC timebox to fail" >&2
  exit 1
fi
grep -q "timebox_days" /tmp/h20-boss-poc.log
if scripts/validate-boss-idea-poc-mvp.sh agentic/fixtures/boss-idea-response/invalid-poc-plan-missing-scope-out.md >/tmp/h20-boss-poc-scope-out.log 2>&1; then
  echo "expected missing POC scope-out to fail" >&2
  exit 1
fi
grep -q "scope_out" /tmp/h20-boss-poc-scope-out.log
if scripts/validate-boss-idea-poc-mvp.sh agentic/fixtures/boss-idea-response/invalid-poc-plan-missing-scope-in.md >/tmp/h20-boss-poc-scope-in.log 2>&1; then
  echo "expected missing POC scope-in to fail" >&2
  exit 1
fi
grep -q "scope_in" /tmp/h20-boss-poc-scope-in.log
if scripts/validate-boss-idea-poc-mvp.sh agentic/fixtures/boss-idea-response/invalid-poc-plan-empty-staffing.md >/tmp/h20-boss-poc-staffing-empty.log 2>&1; then
  echo "expected empty POC staffing assumption to fail" >&2
  exit 1
fi
grep -q "staffing_assumption" /tmp/h20-boss-poc-staffing-empty.log
if scripts/validate-boss-idea-poc-mvp.sh agentic/fixtures/boss-idea-response/invalid-poc-plan-bad-demo-path.md >/tmp/h20-boss-poc-demo-path.log 2>&1; then
  echo "expected bad POC demo path to fail" >&2
  exit 1
fi
grep -q "demo_path" /tmp/h20-boss-poc-demo-path.log
if scripts/validate-boss-idea-poc-mvp.sh agentic/fixtures/boss-idea-response/invalid-poc-plan-bad-validation-command.md >/tmp/h20-boss-poc-command.log 2>&1; then
  echo "expected bad POC validation command to fail" >&2
  exit 1
fi
grep -q "validation_command" /tmp/h20-boss-poc-command.log
if scripts/validate-boss-idea-poc-mvp.sh agentic/fixtures/boss-idea-response/invalid-poc-plan-production-scope.md >/tmp/h20-boss-poc-production.log 2>&1; then
  echo "expected POC production scope to fail" >&2
  exit 1
fi
grep -q "production" /tmp/h20-boss-poc-production.log
if scripts/validate-boss-idea-poc-mvp.sh agentic/fixtures/boss-idea-response/invalid-poc-plan-missing-acceptance-criteria.md >/tmp/h20-boss-poc-acceptance.log 2>&1; then
  echo "expected missing POC acceptance criteria to fail" >&2
  exit 1
fi
grep -q "acceptance_criteria" /tmp/h20-boss-poc-acceptance.log
if scripts/validate-boss-idea-poc-mvp.sh agentic/fixtures/boss-idea-response/invalid-poc-plan-missing-decision.md >/tmp/h20-boss-poc-decision.log 2>&1; then
  echo "expected missing POC post-timebox decision to fail" >&2
  exit 1
fi
grep -q "decision_after_timebox" /tmp/h20-boss-poc-decision.log
if scripts/validate-boss-idea-poc-mvp.sh agentic/fixtures/boss-idea-response/invalid-poc-plan-timebox-too-large.md >/tmp/h20-boss-poc-timebox-large.log 2>&1; then
  echo "expected oversized POC timebox to fail" >&2
  exit 1
fi
grep -q "timebox_days" /tmp/h20-boss-poc-timebox-large.log
if scripts/validate-boss-idea-poc-mvp.sh agentic/fixtures/boss-idea-response/invalid-poc-plan-zero-timebox.md >/tmp/h20-boss-poc-timebox-zero.log 2>&1; then
  echo "expected zero POC timebox to fail" >&2
  exit 1
fi
grep -q "timebox_days" /tmp/h20-boss-poc-timebox-zero.log
if scripts/validate-boss-idea-poc-mvp.sh agentic/fixtures/boss-idea-response/invalid-poc-plan-non-integer-timebox.md >/tmp/h20-boss-poc-timebox-type.log 2>&1; then
  echo "expected non-integer POC timebox to fail" >&2
  exit 1
fi
grep -q "timebox_days" /tmp/h20-boss-poc-timebox-type.log
if scripts/validate-boss-idea-poc-mvp.sh agentic/fixtures/boss-idea-response/invalid-mvp-plan-timebox-too-large.md >/tmp/h20-boss-mvp-timebox-large.log 2>&1; then
  echo "expected oversized MVP timebox to fail" >&2
  exit 1
fi
grep -q "timebox_days" /tmp/h20-boss-mvp-timebox-large.log
if scripts/validate-boss-idea-poc-mvp.sh agentic/fixtures/boss-idea-response/invalid-poc-plan-bad-work-type.md >/tmp/h20-boss-poc-work-type.log 2>&1; then
  echo "expected bad POC work type to fail" >&2
  exit 1
fi
grep -q "work_type" /tmp/h20-boss-poc-work-type.log

scripts/validate-boss-idea-success-metrics.sh agentic/fixtures/boss-idea-response/valid-metrics.yaml >/dev/null
if scripts/validate-boss-idea-success-metrics.sh agentic/fixtures/boss-idea-response/invalid-metrics-missing-threshold.yaml >/tmp/h20-boss-metrics.log 2>&1; then
  echo "expected missing metric threshold to fail" >&2
  exit 1
fi
grep -q "threshold" /tmp/h20-boss-metrics.log
if scripts/validate-boss-idea-success-metrics.sh agentic/fixtures/boss-idea-response/invalid-metrics-missing-owner.yaml >/tmp/h20-boss-metrics-owner.log 2>&1; then
  echo "expected missing metric owner to fail" >&2
  exit 1
fi
grep -q "owner_role" /tmp/h20-boss-metrics-owner.log
if scripts/validate-boss-idea-success-metrics.sh agentic/fixtures/boss-idea-response/invalid-metrics-bad-evidence-path.yaml >/tmp/h20-boss-metrics-evidence.log 2>&1; then
  echo "expected bad metric evidence path to fail" >&2
  exit 1
fi
grep -q "evidence_path" /tmp/h20-boss-metrics-evidence.log
if scripts/validate-boss-idea-success-metrics.sh agentic/fixtures/boss-idea-response/invalid-metrics-timebox-exceeds-plan.yaml >/tmp/h20-boss-metrics-timebox-exceeds.log 2>&1; then
  echo "expected metric timebox exceeding plan to fail" >&2
  exit 1
fi
grep -q "exceeds selected plan timebox" /tmp/h20-boss-metrics-timebox-exceeds.log
if scripts/validate-boss-idea-success-metrics.sh agentic/fixtures/boss-idea-response/invalid-metrics-auto-decision.yaml >/tmp/h20-boss-metrics-auto.log 2>&1; then
  echo "expected metric auto decision to fail" >&2
  exit 1
fi
grep -q "automatically record" /tmp/h20-boss-metrics-auto.log
if scripts/validate-boss-idea-success-metrics.sh agentic/fixtures/boss-idea-response/invalid-metrics-string-auto-decision.yaml >/tmp/h20-boss-metrics-auto-string.log 2>&1; then
  echo "expected string metric auto decision to fail" >&2
  exit 1
fi
grep -q "automatically record" /tmp/h20-boss-metrics-auto-string.log
if scripts/validate-boss-idea-success-metrics.sh agentic/fixtures/boss-idea-response/invalid-metrics-non-integer-timebox.yaml >/tmp/h20-boss-metrics-timebox-type.log 2>&1; then
  echo "expected non-integer metric timebox to fail" >&2
  exit 1
fi
grep -q "timebox_days" /tmp/h20-boss-metrics-timebox-type.log
if scripts/validate-boss-idea-success-metrics.sh agentic/fixtures/boss-idea-response/invalid-metrics-zero-timebox.yaml >/tmp/h20-boss-metrics-timebox-zero.log 2>&1; then
  echo "expected zero metric timebox to fail" >&2
  exit 1
fi
grep -q "timebox_days" /tmp/h20-boss-metrics-timebox-zero.log
if scripts/validate-boss-idea-success-metrics.sh agentic/fixtures/boss-idea-response/invalid-metrics-missing-plan-timebox.yaml >/tmp/h20-boss-metrics-plan-timebox.log 2>&1; then
  echo "expected missing plan timebox to fail" >&2
  exit 1
fi
grep -q "plan_timebox_days" /tmp/h20-boss-metrics-plan-timebox.log
if scripts/validate-boss-idea-success-metrics.sh agentic/fixtures/boss-idea-response/invalid-metrics-string-plan-timebox.yaml >/tmp/h20-boss-metrics-plan-timebox-type.log 2>&1; then
  echo "expected string plan timebox to fail" >&2
  exit 1
fi
grep -q "plan_timebox_days" /tmp/h20-boss-metrics-plan-timebox-type.log
if scripts/validate-boss-idea-success-metrics.sh agentic/fixtures/boss-idea-response/invalid-metrics-missing-metrics.yaml >/tmp/h20-boss-metrics-missing.log 2>&1; then
  echo "expected missing metrics array to fail" >&2
  exit 1
fi
grep -q "metrics" /tmp/h20-boss-metrics-missing.log
if scripts/validate-boss-idea-success-metrics.sh agentic/fixtures/boss-idea-response/invalid-metrics-empty-metrics.yaml >/tmp/h20-boss-metrics-empty.log 2>&1; then
  echo "expected empty metrics array to fail" >&2
  exit 1
fi
grep -q "metrics" /tmp/h20-boss-metrics-empty.log
if scripts/validate-boss-idea-success-metrics.sh agentic/fixtures/boss-idea-response/invalid-metrics-bad-shape.yaml >/tmp/h20-boss-metrics-shape.log 2>&1; then
  echo "expected bad metric shape to fail" >&2
  exit 1
fi
grep -q "must be a mapping" /tmp/h20-boss-metrics-shape.log
if scripts/validate-boss-idea-success-metrics.sh agentic/fixtures/boss-idea-response/invalid-metrics-bad-decision-mapping.yaml >/tmp/h20-boss-metrics-mapping.log 2>&1; then
  echo "expected bad metric decision mapping to fail" >&2
  exit 1
fi
grep -q "decision_mapping" /tmp/h20-boss-metrics-mapping.log
if scripts/validate-boss-idea-success-metrics.sh agentic/fixtures/boss-idea-response/invalid-metrics-missing-decision-mapping.yaml >/tmp/h20-boss-metrics-missing-mapping.log 2>&1; then
  echo "expected missing metric decision mapping to fail" >&2
  exit 1
fi
grep -q "decision_mapping" /tmp/h20-boss-metrics-missing-mapping.log
if scripts/validate-boss-idea-success-metrics.sh agentic/fixtures/boss-idea-response/invalid-metrics-incomplete-decision-mapping.yaml >/tmp/h20-boss-metrics-incomplete-mapping.log 2>&1; then
  echo "expected incomplete metric decision mapping to fail" >&2
  exit 1
fi
grep -q "inconclusive" /tmp/h20-boss-metrics-incomplete-mapping.log

scripts/validate-boss-idea-decision.sh agentic/fixtures/boss-idea-response/valid-decision.yaml >/dev/null
scripts/validate-boss-idea-decision.sh agentic/fixtures/boss-idea-response/valid-no-go-decision.yaml >/dev/null
if scripts/validate-boss-idea-decision.sh agentic/fixtures/boss-idea-response/invalid-decision-unknown.yaml >/tmp/h20-boss-decision-unknown.log 2>&1; then
  echo "expected unknown decision value to fail" >&2
  exit 1
fi
grep -q "invalid" /tmp/h20-boss-decision-unknown.log
if scripts/validate-boss-idea-decision.sh agentic/fixtures/boss-idea-response/invalid-decision-unapproved-go.yaml >/tmp/h20-boss-decision-unapproved.log 2>&1; then
  echo "expected unapproved go decision to fail" >&2
  exit 1
fi
grep -q "approved artifacts" /tmp/h20-boss-decision-unapproved.log
if scripts/validate-boss-idea-decision.sh agentic/fixtures/boss-idea-response/invalid-decision-bad-evidence-path.yaml >/tmp/h20-boss-decision-evidence-path.log 2>&1; then
  echo "expected bad decision evidence path to fail" >&2
  exit 1
fi
grep -q "evidence artifact" /tmp/h20-boss-decision-evidence-path.log
if scripts/validate-boss-idea-decision.sh agentic/fixtures/boss-idea-response/invalid-decision-missing-reason.yaml >/tmp/h20-boss-decision-reason.log 2>&1; then
  echo "expected missing decision reason to fail" >&2
  exit 1
fi
grep -q "reason" /tmp/h20-boss-decision-reason.log
if scripts/validate-boss-idea-decision.sh agentic/fixtures/boss-idea-response/invalid-decision-missing-evidence.yaml >/tmp/h20-boss-decision-evidence.log 2>&1; then
  echo "expected missing decision evidence to fail" >&2
  exit 1
fi
grep -q "evidence_artifacts" /tmp/h20-boss-decision-evidence.log
if scripts/validate-boss-idea-decision.sh agentic/fixtures/boss-idea-response/invalid-decision-missing-metric-result.yaml >/tmp/h20-boss-decision-metric.log 2>&1; then
  echo "expected missing go decision metric result to fail" >&2
  exit 1
fi
grep -q "metric_result" /tmp/h20-boss-decision-metric.log
if scripts/validate-boss-idea-decision.sh agentic/fixtures/boss-idea-response/invalid-decision-no-go-approved-artifacts.yaml >/tmp/h20-boss-decision-no-go-approved.log 2>&1; then
  echo "expected no-go decision with approved artifacts claim to fail" >&2
  exit 1
fi
grep -q "only go decision" /tmp/h20-boss-decision-no-go-approved.log

RUN_ID="$BOSS_DECISION_RUN" scripts/init-boss-idea-run.sh agentic/fixtures/boss-idea-response/valid-idea.md >/dev/null
if scripts/record-boss-idea-decision.sh agentic/fixtures/boss-idea-response/valid-decision.yaml >/tmp/h20-boss-decision-no-run.log 2>&1; then
  echo "expected record decision without run id to fail" >&2
  exit 1
fi
grep -q "usage:" /tmp/h20-boss-decision-no-run.log
if scripts/record-boss-idea-decision.sh agentic/fixtures/boss-idea-response/valid-no-go-decision.yaml --run-id "${BOSS_DECISION_RUN}-missing" >/tmp/h20-boss-decision-missing-run.log 2>&1; then
  echo "expected record decision with missing manifest to fail" >&2
  exit 1
fi
grep -q "planning manifest not found" /tmp/h20-boss-decision-missing-run.log
mkdir -p "agentic/runs/$BOSS_DECISION_BAD_ID_RUN"
cat >"agentic/runs/$BOSS_DECISION_BAD_ID_RUN/manifest.yaml" <<YAML
schema_version: 1
run:
  id: wrong-run
  profile: boss-idea-response
artifacts:
  - path: docs/architecture/boss-idea-modules/go-no-go-decision.md
    status: approved
YAML
if scripts/record-boss-idea-decision.sh agentic/fixtures/boss-idea-response/valid-no-go-decision.yaml --run-id "$BOSS_DECISION_BAD_ID_RUN" >/tmp/h20-boss-decision-bad-id.log 2>&1; then
  echo "expected record decision with bad manifest id to fail" >&2
  exit 1
fi
grep -q "blocked_schema_invalid" /tmp/h20-boss-decision-bad-id.log
mkdir -p "agentic/runs/$BOSS_DECISION_BAD_PROFILE_RUN"
cat >"agentic/runs/$BOSS_DECISION_BAD_PROFILE_RUN/manifest.yaml" <<YAML
schema_version: 1
run:
  id: $BOSS_DECISION_BAD_PROFILE_RUN
  profile: default-delivery
artifacts:
  - path: docs/architecture/boss-idea-modules/go-no-go-decision.md
    status: approved
YAML
if scripts/record-boss-idea-decision.sh agentic/fixtures/boss-idea-response/valid-no-go-decision.yaml --run-id "$BOSS_DECISION_BAD_PROFILE_RUN" >/tmp/h20-boss-decision-bad-profile.log 2>&1; then
  echo "expected record decision with bad manifest profile to fail" >&2
  exit 1
fi
grep -q "blocked_schema_invalid" /tmp/h20-boss-decision-bad-profile.log
if scripts/record-boss-idea-decision.sh agentic/fixtures/boss-idea-response/valid-no-go-decision.yaml --run-id "$BOSS_DECISION_RUN" --actor claude_code_cli --role code_reviewer >/tmp/h20-boss-decision-auth.log 2>&1; then
  echo "expected unauthorized decision record to fail" >&2
  exit 1
fi
grep -q "authorization failed" /tmp/h20-boss-decision-auth.log
scripts/record-boss-idea-decision.sh agentic/fixtures/boss-idea-response/valid-no-go-decision.yaml --run-id "$BOSS_DECISION_RUN" >/dev/null
if scripts/record-boss-idea-decision.sh agentic/fixtures/boss-idea-response/valid-decision.yaml --run-id "$BOSS_DECISION_RUN" >/tmp/h20-boss-decision-manifest-approval.log 2>&1; then
  echo "expected go decision without approved manifest artifacts to fail" >&2
  exit 1
fi
grep -q "approved manifest artifacts" /tmp/h20-boss-decision-manifest-approval.log
scripts/update-artifact-status.sh "$BOSS_DECISION_RUN" docs/architecture/boss-idea-modules/go-no-go-decision.md approved --reason "H20 boss decision approval fixture" >/dev/null
scripts/record-boss-idea-decision.sh agentic/fixtures/boss-idea-response/valid-decision.yaml --run-id "$BOSS_DECISION_RUN" >/dev/null
grep -q "boss_idea_decisions" "agentic/runs/$BOSS_DECISION_RUN/manifest.yaml"
ruby -ryaml -e 'm=YAML.load_file(ARGV.fetch(0)); d=Array(m["boss_idea_decisions"]); abort("missing decision audit fields") unless d.all? { |entry| entry["actor"].to_s != "" && entry["actor_role"].to_s != "" && entry["authorization"].is_a?(Hash) }' "agentic/runs/$BOSS_DECISION_RUN/manifest.yaml"
RUN_ID="$BOSS_IMPLEMENTATION_RUN" scripts/init-implementation-run.sh --planning-run "$BOSS_DECISION_RUN" --artifact docs/architecture/boss-idea-modules/go-no-go-decision.md >/dev/null
scripts/validate-manifest-schema.sh "$BOSS_IMPLEMENTATION_RUN" >/dev/null
scripts/validate-implementation-run.sh "$BOSS_IMPLEMENTATION_RUN" >/dev/null
ruby -ryaml -e 'm=YAML.load_file(ARGV.fetch(0)); abort("expected boss idea implementation profile") unless m.dig("run", "profile") == "boss-idea-response"; paths=Array(m["approved_inputs"]).map { |input| input["path"] }; abort("missing approved boss idea input") unless paths.include?("docs/architecture/boss-idea-modules/go-no-go-decision.md")' "agentic/runs/$BOSS_IMPLEMENTATION_RUN/implementation-manifest.yaml"

echo "golden fixtures ok"
