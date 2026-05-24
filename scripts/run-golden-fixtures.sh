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
  if [[ -n "${SEARXNG_BAD_CONTENT_TYPE_PID:-}" ]]; then
    kill "$SEARXNG_BAD_CONTENT_TYPE_PID" 2>/dev/null || true
    wait "$SEARXNG_BAD_CONTENT_TYPE_PID" 2>/dev/null || true
  fi
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
grep -q "boss_idea_market_research" "agentic/runs/$BOSS_IDEA_RUN/manifest.yaml"
git check-ignore -q "agentic/runs/$BOSS_IDEA_RUN/crawl4ai/raw/competitor-public-workflow.md"
ruby -ryaml -e 'm=YAML.load_file(ARGV.fetch(0)); c=m.fetch("boss_idea_market_crawl"); r=m.fetch("boss_idea_market_research"); abort("expected fixture provider") unless c["provider"] == "fixture"; abort("expected source count") unless c["source_count"].to_i >= 2; abort("expected research artifact") unless r["artifact_path"].to_s.end_with?("market-research.md"); abort("market crawl must not approve artifacts") unless m.fetch("artifacts").all? { |a| a["status"] == "planned" }' "agentic/runs/$BOSS_IDEA_RUN/manifest.yaml"

if scripts/crawl-boss-idea-market.sh --live --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider fixture --output "agentic/runs/$BOSS_IDEA_RUN/bad-live-no-env-results.yaml" >/tmp/h20-boss-market-crawl-live-no-env.log 2>&1; then
  echo "expected --live without env to fail" >&2
  exit 1
fi
grep -q "requires both" /tmp/h20-boss-market-crawl-live-no-env.log

if BOSS_IDEA_LIVE_CRAWL=1 scripts/crawl-boss-idea-market.sh --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider fixture --output "agentic/runs/$BOSS_IDEA_RUN/bad-live-env-only-results.yaml" >/tmp/h20-boss-market-crawl-env-only.log 2>&1; then
  echo "expected live env without --live to fail" >&2
  exit 1
fi
grep -q "requires both" /tmp/h20-boss-market-crawl-env-only.log

if BOSS_IDEA_LIVE_CRAWL=1 scripts/crawl-boss-idea-market.sh --live --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider fixture --output "agentic/runs/$BOSS_IDEA_RUN/bad-live-fixture-results.yaml" >/tmp/h20-boss-market-crawl-live-fixture.log 2>&1; then
  echo "expected live fixture crawl to fail" >&2
  exit 1
fi
grep -q "approved live provider" /tmp/h20-boss-market-crawl-live-fixture.log

cat >"agentic/runs/$BOSS_IDEA_RUN/invalid-market-crawl-live-seed.yaml" <<'YAML'
candidates:
  - id: live-seed-without-approval
    query_id: competitor_landscape
    url: https://example.com/live-seed
    title: Live seed without approval
    snippet: Should fail before Crawl4AI runtime is invoked.
    provider: live_seed
    source_type: vendor_docs
    signal: competitor
    claim: Live seed crawling requires explicit approval.
YAML
if BOSS_IDEA_LIVE_CRAWL=1 scripts/crawl-boss-idea-market.sh --live --force --results-only "$BOSS_IDEA_RUN" --seeds "agentic/runs/$BOSS_IDEA_RUN/invalid-market-crawl-live-seed.yaml" --output "agentic/runs/$BOSS_IDEA_RUN/bad-live-seed-results.yaml" >/tmp/h20-boss-market-crawl-live-seed.log 2>&1; then
  echo "expected unapproved live seed to fail" >&2
  exit 1
fi
grep -q "live_approved" /tmp/h20-boss-market-crawl-live-seed.log

if scripts/crawl-boss-idea-market.sh --force --results-only "$BOSS_IDEA_RUN" --search-provider live_seed --seeds "agentic/runs/$BOSS_IDEA_RUN/invalid-market-crawl-live-seed.yaml" --output "agentic/runs/$BOSS_IDEA_RUN/bad-live-seed-no-flags-results.yaml" >/tmp/h20-boss-market-crawl-live-seed-no-flags.log 2>&1; then
  echo "expected live_seed without live flags to fail" >&2
  exit 1
fi
grep -q "requires both" /tmp/h20-boss-market-crawl-live-seed-no-flags.log

if BOSS_IDEA_LIVE_CRAWL=1 scripts/crawl-boss-idea-market.sh --force --results-only "$BOSS_IDEA_RUN" --search-provider live_seed --seeds "agentic/runs/$BOSS_IDEA_RUN/invalid-market-crawl-live-seed.yaml" --output "agentic/runs/$BOSS_IDEA_RUN/bad-live-seed-env-only-results.yaml" >/tmp/h20-boss-market-crawl-live-seed-env-only.log 2>&1; then
  echo "expected live_seed with env only to fail" >&2
  exit 1
fi
grep -q "requires both" /tmp/h20-boss-market-crawl-live-seed-env-only.log

if BOSS_IDEA_LIVE_CRAWL=1 scripts/crawl-boss-idea-market.sh --live --force --results-only "$BOSS_IDEA_RUN" --search-provider live_seed --output "agentic/runs/$BOSS_IDEA_RUN/bad-live-seed-no-seeds-results.yaml" >/tmp/h20-boss-market-crawl-live-seed-no-seeds.log 2>&1; then
  echo "expected live_seed without seeds to fail" >&2
  exit 1
fi
grep -q "must specify --from-query-pack or --seeds" /tmp/h20-boss-market-crawl-live-seed-no-seeds.log

cat >"agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-helper.py" <<'PY'
#!/usr/bin/env python3
import json
print(json.dumps({
    "ok": True,
    "url": "https://93.184.216.34/live-seed",
    "crawl4ai_version": "fake-crawl4ai",
    "markdown": "Remote page content about public research options.",
    "truncated": False,
}))
PY
chmod +x "agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-helper.py"
cat >"agentic/runs/$BOSS_IDEA_RUN/valid-market-crawl-live-seed.yaml" <<'YAML'
candidates:
  - id: approved-live-seed
    query_id: competitor_landscape
    url: https://93.184.216.34/live-seed
    title: Approved live seed
    snippet: Uses a fake helper to exercise live_seed metadata without external network.
    provider: live_seed
    source_type: vendor_docs
    signal: competitor
    claim: Runtime metadata is captured for the approved live crawl.
    live_approved: true
YAML
BOSS_IDEA_LIVE_CRAWL=1 BOSS_IDEA_CRAWL4AI_PYTHON=python3 BOSS_IDEA_CRAWL4AI_HELPER="agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-helper.py" scripts/crawl-boss-idea-market.sh --live --force --results-only "$BOSS_IDEA_RUN" --seeds "agentic/runs/$BOSS_IDEA_RUN/valid-market-crawl-live-seed.yaml" --output "agentic/runs/$BOSS_IDEA_RUN/live-seed-results.yaml" >/dev/null
ruby -ryaml -e 'm=YAML.load_file(ARGV.fetch(0)); c=m.fetch("boss_idea_market_crawl"); abort("expected live_seed mode") unless c["mode"] == "live_seed"; abort("expected fake crawl4ai version") unless c["crawl4ai_version"] == "fake-crawl4ai"' "agentic/runs/$BOSS_IDEA_RUN/manifest.yaml"

cat >"agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-runtime-missing.py" <<'PY'
#!/usr/bin/env python3
import json
import sys
print(json.dumps({
    "ok": False,
    "error": "crawl4ai runtime unavailable: ModuleNotFoundError: No module named crawl4ai",
}), file=sys.stderr)
sys.exit(3)
PY
chmod +x "agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-runtime-missing.py"
if BOSS_IDEA_LIVE_CRAWL=1 BOSS_IDEA_CRAWL4AI_PYTHON=python3 BOSS_IDEA_CRAWL4AI_HELPER="agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-runtime-missing.py" scripts/crawl-boss-idea-market.sh --live --force --results-only "$BOSS_IDEA_RUN" --seeds "agentic/runs/$BOSS_IDEA_RUN/valid-market-crawl-live-seed.yaml" --output "agentic/runs/$BOSS_IDEA_RUN/bad-runtime-missing-results.yaml" >/tmp/h20-boss-market-crawl-runtime-missing.log 2>&1; then
  echo "expected Crawl4AI runtime unavailable to fail" >&2
  exit 1
fi
grep -q "crawl4ai runtime unavailable" /tmp/h20-boss-market-crawl-runtime-missing.log

if BOSS_IDEA_LIVE_CRAWL=1 BOSS_IDEA_CRAWL4AI_HELPER=scripts/lib/missing-crawl4ai-helper.py scripts/crawl-boss-idea-market.sh --live --force --results-only "$BOSS_IDEA_RUN" --seeds "agentic/runs/$BOSS_IDEA_RUN/valid-market-crawl-live-seed.yaml" --output "agentic/runs/$BOSS_IDEA_RUN/bad-missing-helper-results.yaml" >/tmp/h20-boss-market-crawl-helper-missing.log 2>&1; then
  echo "expected missing Crawl4AI helper to fail" >&2
  exit 1
fi
grep -q "helper not found" /tmp/h20-boss-market-crawl-helper-missing.log

if scripts/crawl-boss-idea-market.sh --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider brave --output "agentic/runs/$BOSS_IDEA_RUN/bad-brave-no-live-results.yaml" >/tmp/h20-boss-market-crawl-brave-no-live.log 2>&1; then
  echo "expected Brave provider without live flags to fail" >&2
  exit 1
fi
grep -q "public network search/crawl requires" /tmp/h20-boss-market-crawl-brave-no-live.log

if BOSS_IDEA_LIVE_CRAWL=1 scripts/crawl-boss-idea-market.sh --live --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider brave --output "agentic/runs/$BOSS_IDEA_RUN/bad-brave-missing-key-results.yaml" >/tmp/h20-boss-market-crawl-brave-key.log 2>&1; then
  echo "expected Brave provider without API key to fail" >&2
  exit 1
fi
grep -q "BOSS_IDEA_SEARCH_BRAVE_API_KEY" /tmp/h20-boss-market-crawl-brave-key.log

BRAVE_KEY_ENV="BOSS_IDEA_SEARCH_BRAVE_API_KEY"
env BOSS_IDEA_LIVE_CRAWL=1 "$BRAVE_KEY_ENV=fake" BOSS_IDEA_SEARCH_BRAVE_BASE_URL=http://127.0.0.1/should-not-be-used BOSS_IDEA_SEARCH_BRAVE_FIXTURE=agentic/fixtures/boss-idea-response/brave-search-fixture.json BOSS_IDEA_CRAWL4AI_PYTHON=python3 BOSS_IDEA_CRAWL4AI_HELPER="agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-helper.py" scripts/crawl-boss-idea-market.sh --live --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider brave --output "agentic/runs/$BOSS_IDEA_RUN/brave-results.yaml" >/dev/null
scripts/validate-boss-idea-research.sh "agentic/runs/$BOSS_IDEA_RUN/market-research.md" >/dev/null
ruby -ryaml -e 'm=YAML.load_file(ARGV.fetch(0)); c=m.fetch("boss_idea_market_crawl"); abort("expected brave provider") unless c["provider"] == "brave"; abort("expected brave mode") unless c["mode"] == "brave"; abort("expected fake crawl4ai version") unless c["crawl4ai_version"] == "fake-crawl4ai"; abort("expected brave source count") unless c["source_count"].to_i >= 4' "agentic/runs/$BOSS_IDEA_RUN/manifest.yaml"

cat >"agentic/runs/$BOSS_IDEA_RUN/brave-private-fixture.json" <<'JSON'
{
  "query_results": {
    "competitor_landscape": {"web": {"results": [{"url": "http://10.0.0.1/private-competitor", "title": "Private competitor", "description": "Should be blocked."}]}},
    "mainstream_practices": {"web": {"results": [{"url": "http://10.0.0.1/private-mainstream", "title": "Private mainstream", "description": "Should be blocked."}]}},
    "implementation_patterns": {"web": {"results": [{"url": "http://10.0.0.1/private-implementation", "title": "Private implementation", "description": "Should be blocked."}]}},
    "operator_workflow": {"web": {"results": [{"url": "http://10.0.0.1/private-operator", "title": "Private operator", "description": "Should be blocked."}]}}
  }
}
JSON
if env BOSS_IDEA_LIVE_CRAWL=1 "$BRAVE_KEY_ENV=fake" BOSS_IDEA_SEARCH_BRAVE_FIXTURE="agentic/runs/$BOSS_IDEA_RUN/brave-private-fixture.json" BOSS_IDEA_CRAWL4AI_PYTHON=python3 BOSS_IDEA_CRAWL4AI_HELPER="agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-helper.py" scripts/crawl-boss-idea-market.sh --live --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider brave --output "agentic/runs/$BOSS_IDEA_RUN/bad-brave-private-results.yaml" >/tmp/h20-boss-market-crawl-brave-private.log 2>&1; then
  echo "expected Brave private-IP candidates to fail" >&2
  exit 1
fi
grep -q "Brave search returned no candidate URLs" /tmp/h20-boss-market-crawl-brave-private.log

cat >"agentic/runs/$BOSS_IDEA_RUN/brave-missing-results-fixture.json" <<'JSON'
{
  "query_results": {
    "competitor_landscape": {}
  }
}
JSON
if env BOSS_IDEA_LIVE_CRAWL=1 "$BRAVE_KEY_ENV=fake" BOSS_IDEA_SEARCH_BRAVE_FIXTURE="agentic/runs/$BOSS_IDEA_RUN/brave-missing-results-fixture.json" BOSS_IDEA_CRAWL4AI_PYTHON=python3 BOSS_IDEA_CRAWL4AI_HELPER="agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-helper.py" scripts/crawl-boss-idea-market.sh --live --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider brave --output "agentic/runs/$BOSS_IDEA_RUN/bad-brave-missing-results.yaml" >/tmp/h20-boss-market-crawl-brave-missing-results.log 2>&1; then
  echo "expected Brave missing web.results fixture to fail" >&2
  exit 1
fi
grep -q "missing web.results" /tmp/h20-boss-market-crawl-brave-missing-results.log

if scripts/crawl-boss-idea-market.sh --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider searxng --output "agentic/runs/$BOSS_IDEA_RUN/bad-searxng-no-live-results.yaml" >/tmp/h20-boss-market-crawl-searxng-no-live.log 2>&1; then
  echo "expected SearXNG provider without live flags or fixture to fail" >&2
  exit 1
fi
grep -q "public network search/crawl requires" /tmp/h20-boss-market-crawl-searxng-no-live.log

if BOSS_IDEA_LIVE_CRAWL=1 scripts/crawl-boss-idea-market.sh --live --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider searxng --output "agentic/runs/$BOSS_IDEA_RUN/bad-searxng-missing-base-results.yaml" >/tmp/h20-boss-market-crawl-searxng-base.log 2>&1; then
  echo "expected SearXNG provider without base URL to fail" >&2
  exit 1
fi
grep -q "BOSS_IDEA_SEARCH_SEARXNG_BASE_URL" /tmp/h20-boss-market-crawl-searxng-base.log

if BOSS_IDEA_LIVE_CRAWL=1 BOSS_IDEA_SEARCH_SEARXNG_BASE_URL=http://127.0.0.1:8080/search scripts/crawl-boss-idea-market.sh --live --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider searxng --output "agentic/runs/$BOSS_IDEA_RUN/bad-searxng-paid-policy-results.yaml" >/tmp/h20-boss-market-crawl-searxng-paid-policy.log 2>&1; then
  echo "expected SearXNG provider without no-paid policy to fail" >&2
  exit 1
fi
grep -q "BOSS_IDEA_SEARCH_SEARXNG_NO_PAID_ENGINES" /tmp/h20-boss-market-crawl-searxng-paid-policy.log

if BOSS_IDEA_LIVE_CRAWL=1 BOSS_IDEA_SEARCH_SEARXNG_BASE_URL=https://user:credential@example.com/search BOSS_IDEA_SEARCH_SEARXNG_NO_PAID_ENGINES=1 scripts/crawl-boss-idea-market.sh --live --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider searxng --output "agentic/runs/$BOSS_IDEA_RUN/bad-searxng-userinfo-results.yaml" >/tmp/h20-boss-market-crawl-searxng-userinfo.log 2>&1; then
  echo "expected SearXNG base URL userinfo to fail" >&2
  exit 1
fi
grep -q "must not contain userinfo" /tmp/h20-boss-market-crawl-searxng-userinfo.log

SEARXNG_BAD_CONTENT_TYPE_PORT="agentic/runs/$BOSS_IDEA_RUN/searxng-bad-content-type.port"
ruby -rwebrick -e 'port_file=ARGV.fetch(0); server=WEBrick::HTTPServer.new(Port: 0, BindAddress: "127.0.0.1", Logger: WEBrick::Log.new(File::NULL), AccessLog: []); File.write(port_file, server.config[:Port]); trap("TERM") { server.shutdown }; server.mount_proc("/search") { |_req, res| res["Content-Type"] = "text/html"; res.body = "<html>not json</html>" }; server.start' "$SEARXNG_BAD_CONTENT_TYPE_PORT" &
SEARXNG_BAD_CONTENT_TYPE_PID=$!
for _ in 1 2 3 4 5; do
  test -s "$SEARXNG_BAD_CONTENT_TYPE_PORT" && break
  sleep 1
done
SEARXNG_BAD_CONTENT_TYPE_PORT_VALUE="$(cat "$SEARXNG_BAD_CONTENT_TYPE_PORT")"
if BOSS_IDEA_LIVE_CRAWL=1 BOSS_IDEA_SEARCH_SEARXNG_BASE_URL="http://127.0.0.1:${SEARXNG_BAD_CONTENT_TYPE_PORT_VALUE}/search" BOSS_IDEA_SEARCH_SEARXNG_NO_PAID_ENGINES=1 scripts/crawl-boss-idea-market.sh --live --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider searxng --output "agentic/runs/$BOSS_IDEA_RUN/bad-searxng-content-type-results.yaml" >/tmp/h20-boss-market-crawl-searxng-content-type.log 2>&1; then
  echo "expected SearXNG non-JSON content type to fail" >&2
  kill "$SEARXNG_BAD_CONTENT_TYPE_PID" 2>/dev/null || true
  wait "$SEARXNG_BAD_CONTENT_TYPE_PID" 2>/dev/null || true
  exit 1
fi
kill "$SEARXNG_BAD_CONTENT_TYPE_PID" 2>/dev/null || true
wait "$SEARXNG_BAD_CONTENT_TYPE_PID" 2>/dev/null || true
unset SEARXNG_BAD_CONTENT_TYPE_PID
grep -q "non-JSON content type" /tmp/h20-boss-market-crawl-searxng-content-type.log

BOSS_IDEA_SEARCH_SEARXNG_FIXTURE=agentic/fixtures/boss-idea-response/searxng-search-fixture.json scripts/crawl-boss-idea-market.sh --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider searxng --output "agentic/runs/$BOSS_IDEA_RUN/searxng-results.yaml" >/dev/null
scripts/validate-boss-idea-research.sh "agentic/runs/$BOSS_IDEA_RUN/market-research.md" >/dev/null
ruby -ryaml -e 'm=YAML.load_file(ARGV.fetch(0)); c=m.fetch("boss_idea_market_crawl"); abort("expected searxng provider") unless c["provider"] == "searxng"; abort("expected fixture mode") unless c["mode"] == "fixture"; abort("expected no-paid provider") unless c["no_paid_provider"] == true; abort("expected provider priority") unless c["provider_priority"].to_i == 1; abort("expected searxng source count") unless c["source_count"].to_i >= 4' "agentic/runs/$BOSS_IDEA_RUN/manifest.yaml"
ruby -ryaml -e 'c=YAML.load_file(ARGV.fetch(0)); abort("expected searxng provider") unless c["provider"] == "searxng"; abort("expected provider metadata") unless c.fetch("candidates").all? { |x| x["provider_metadata"].is_a?(Hash) && x["provider_metadata"]["provider"] == "searxng" && x["provider_metadata"]["result_rank"].to_i >= 1 }' "agentic/runs/$BOSS_IDEA_RUN/market-candidate-urls.yaml"
ruby -rjson -e 'source=JSON.parse(File.read(ARGV.fetch(0))); source.fetch("query_results").each_value { |payload| payload["no_paid_engine_policy"] = "unknown" }; File.write(ARGV.fetch(1), JSON.pretty_generate(source))' agentic/fixtures/boss-idea-response/searxng-search-fixture.json "agentic/runs/$BOSS_IDEA_RUN/searxng-unknown-policy-fixture.json"
BOSS_IDEA_SEARCH_SEARXNG_FIXTURE="agentic/runs/$BOSS_IDEA_RUN/searxng-unknown-policy-fixture.json" scripts/crawl-boss-idea-market.sh --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider searxng --output "agentic/runs/$BOSS_IDEA_RUN/searxng-unknown-policy-results.yaml" >/dev/null
if scripts/generate-boss-decision-memo.sh --output "agentic/runs/$BOSS_IDEA_RUN/bad-searxng-unknown-policy-memo.md" "$BOSS_IDEA_RUN" >/tmp/h20-boss-market-crawl-searxng-unknown-memo.log 2>&1; then
  echo "expected SearXNG unknown no-paid policy evidence to block decision memo" >&2
  exit 1
fi
grep -q "blocked_unknown_no_paid_engine_policy" /tmp/h20-boss-market-crawl-searxng-unknown-memo.log

cat >"agentic/runs/$BOSS_IDEA_RUN/searxng-malformed-fixture.json" <<'JSON'
{"query_results":
JSON
if BOSS_IDEA_SEARCH_SEARXNG_FIXTURE="agentic/runs/$BOSS_IDEA_RUN/searxng-malformed-fixture.json" scripts/crawl-boss-idea-market.sh --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider searxng --output "agentic/runs/$BOSS_IDEA_RUN/bad-searxng-malformed-results.yaml" >/tmp/h20-boss-market-crawl-searxng-malformed.log 2>&1; then
  echo "expected malformed SearXNG fixture to fail" >&2
  exit 1
fi
grep -q "invalid SearXNG fixture JSON" /tmp/h20-boss-market-crawl-searxng-malformed.log

cat >"agentic/runs/$BOSS_IDEA_RUN/searxng-missing-results-fixture.json" <<'JSON'
{
  "query_results": {
    "competitor_landscape": {}
  }
}
JSON
if BOSS_IDEA_SEARCH_SEARXNG_FIXTURE="agentic/runs/$BOSS_IDEA_RUN/searxng-missing-results-fixture.json" scripts/crawl-boss-idea-market.sh --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider searxng --output "agentic/runs/$BOSS_IDEA_RUN/bad-searxng-missing-results.yaml" >/tmp/h20-boss-market-crawl-searxng-missing-results.log 2>&1; then
  echo "expected SearXNG missing results fixture to fail" >&2
  exit 1
fi
grep -q "missing results" /tmp/h20-boss-market-crawl-searxng-missing-results.log

cat >"agentic/runs/$BOSS_IDEA_RUN/searxng-paid-fixture.json" <<'JSON'
{
  "query_results": {
    "competitor_landscape": {
      "no_paid_engine_policy": "operator-confirmed",
      "results": [
        {"url": "https://93.184.216.34/paid", "title": "Paid result", "content": "Should be blocked.", "engine_cost": "paid"}
      ]
    }
  }
}
JSON
if BOSS_IDEA_SEARCH_SEARXNG_FIXTURE="agentic/runs/$BOSS_IDEA_RUN/searxng-paid-fixture.json" scripts/crawl-boss-idea-market.sh --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider searxng --output "agentic/runs/$BOSS_IDEA_RUN/bad-searxng-paid-results.yaml" >/tmp/h20-boss-market-crawl-searxng-paid.log 2>&1; then
  echo "expected SearXNG paid engine fixture to fail" >&2
  exit 1
fi
grep -q "paid engine" /tmp/h20-boss-market-crawl-searxng-paid.log

cat >"agentic/runs/$BOSS_IDEA_RUN/searxng-private-fixture.json" <<'JSON'
{
  "query_results": {
    "competitor_landscape": {
      "no_paid_engine_policy": "operator-confirmed",
      "results": [
        {"url": "http://10.0.0.1/private", "title": "Private result", "content": "Should be filtered."}
      ]
    },
    "mainstream_practices": {
      "no_paid_engine_policy": "operator-confirmed",
      "results": [
        {"url": "http://169.254.169.254/latest/meta-data", "title": "Metadata result", "content": "Should be filtered."}
      ]
    },
    "implementation_patterns": {
      "no_paid_engine_policy": "operator-confirmed",
      "results": [
        {"url": "http://127.0.0.1/private", "title": "Loopback result", "content": "Should be filtered."}
      ]
    },
    "operator_workflow": {
      "no_paid_engine_policy": "operator-confirmed",
      "results": [
        {"url": "ftp://example.com/not-http", "title": "Scheme result", "content": "Should be filtered."}
      ]
    }
  }
}
JSON
if BOSS_IDEA_SEARCH_SEARXNG_BASE_URL=http://127.0.0.1:8080/search BOSS_IDEA_SEARCH_SEARXNG_FIXTURE="agentic/runs/$BOSS_IDEA_RUN/searxng-private-fixture.json" scripts/crawl-boss-idea-market.sh --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider searxng --output "agentic/runs/$BOSS_IDEA_RUN/bad-searxng-private-results.yaml" >/tmp/h20-boss-market-crawl-searxng-private.log 2>&1; then
  echo "expected SearXNG private-IP candidates to fail" >&2
  exit 1
fi
grep -q "SearXNG search returned no candidate URLs" /tmp/h20-boss-market-crawl-searxng-private.log

if scripts/crawl-boss-idea-market.sh --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider duckduckgo_html --output "agentic/runs/$BOSS_IDEA_RUN/bad-duckduckgo-no-live-results.yaml" >/tmp/h20-boss-market-crawl-duckduckgo-no-live.log 2>&1; then
  echo "expected DuckDuckGo HTML provider without live flags or fixture to fail" >&2
  exit 1
fi
grep -q "public network search/crawl requires" /tmp/h20-boss-market-crawl-duckduckgo-no-live.log

BOSS_IDEA_SEARCH_DUCKDUCKGO_HTML_FIXTURE=agentic/fixtures/boss-idea-response/duckduckgo-html-fixtures scripts/crawl-boss-idea-market.sh --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider duckduckgo_html --output "agentic/runs/$BOSS_IDEA_RUN/duckduckgo-results.yaml" >/dev/null
scripts/validate-boss-idea-research.sh "agentic/runs/$BOSS_IDEA_RUN/market-research.md" >/dev/null
ruby -ryaml -e 'm=YAML.load_file(ARGV.fetch(0)); c=m.fetch("boss_idea_market_crawl"); abort("expected duckduckgo provider") unless c["provider"] == "duckduckgo_html"; abort("expected fixture mode") unless c["mode"] == "fixture"; abort("expected no-paid provider") unless c["no_paid_provider"] == true; abort("expected provider priority") unless c["provider_priority"].to_i == 2' "agentic/runs/$BOSS_IDEA_RUN/manifest.yaml"
ruby -ryaml -e 'c=YAML.load_file(ARGV.fetch(0)); abort("expected lower-trust fallback metadata") unless c.fetch("candidates").all? { |x| x.dig("provider_metadata", "lower_trust_fallback") == true && x.dig("provider_metadata", "fallback_from") == "searxng" }' "agentic/runs/$BOSS_IDEA_RUN/market-candidate-urls.yaml"

mkdir -p "agentic/runs/$BOSS_IDEA_RUN/duckduckgo-empty-fixture"
cat >"agentic/runs/$BOSS_IDEA_RUN/duckduckgo-empty-fixture/competitor_landscape.html" <<'HTML'
<!doctype html><html><body><p>No result anchors.</p></body></html>
HTML
if BOSS_IDEA_SEARCH_DUCKDUCKGO_HTML_FIXTURE="agentic/runs/$BOSS_IDEA_RUN/duckduckgo-empty-fixture" scripts/crawl-boss-idea-market.sh --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider duckduckgo_html --output "agentic/runs/$BOSS_IDEA_RUN/bad-duckduckgo-empty-results.yaml" >/tmp/h20-boss-market-crawl-duckduckgo-empty.log 2>&1; then
  echo "expected empty DuckDuckGo HTML fixture to fail" >&2
  exit 1
fi
grep -q "no parseable results" /tmp/h20-boss-market-crawl-duckduckgo-empty.log
mkdir -p "agentic/runs/$BOSS_IDEA_RUN/duckduckgo-challenge-fixture"
cat >"agentic/runs/$BOSS_IDEA_RUN/duckduckgo-challenge-fixture/competitor_landscape.html" <<'HTML'
<!doctype html><html><body><h1>Are you human?</h1><p>captcha challenge</p></body></html>
HTML
if BOSS_IDEA_SEARCH_DUCKDUCKGO_HTML_FIXTURE="agentic/runs/$BOSS_IDEA_RUN/duckduckgo-challenge-fixture" scripts/crawl-boss-idea-market.sh --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider duckduckgo_html --output "agentic/runs/$BOSS_IDEA_RUN/bad-duckduckgo-challenge-results.yaml" >/tmp/h20-boss-market-crawl-duckduckgo-challenge.log 2>&1; then
  echo "expected DuckDuckGo HTML challenge fixture to fail" >&2
  exit 1
fi
grep -q "challenge detected" /tmp/h20-boss-market-crawl-duckduckgo-challenge.log

if scripts/crawl-boss-idea-market.sh --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider local_browser_search --output "agentic/runs/$BOSS_IDEA_RUN/bad-local-browser-no-live-results.yaml" >/tmp/h20-boss-market-crawl-local-browser-no-live.log 2>&1; then
  echo "expected local browser provider without live flags or fixture to fail" >&2
  exit 1
fi
grep -q "public network search/crawl requires" /tmp/h20-boss-market-crawl-local-browser-no-live.log
if BOSS_IDEA_LIVE_CRAWL=1 BOSS_IDEA_SEARCH_LOCAL_BROWSER_SEARCH_URL=http://127.0.0.1/search scripts/crawl-boss-idea-market.sh --live --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider local_browser_search --output "agentic/runs/$BOSS_IDEA_RUN/bad-local-browser-search-url-results.yaml" >/tmp/h20-boss-market-crawl-local-browser-search-url.log 2>&1; then
  echo "expected local browser private search URL to fail" >&2
  exit 1
fi
grep -q "blocked IP" /tmp/h20-boss-market-crawl-local-browser-search-url.log

BOSS_IDEA_SEARCH_LOCAL_BROWSER_FIXTURE=agentic/fixtures/boss-idea-response/local-browser-search-fixture.json scripts/crawl-boss-idea-market.sh --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider local_browser_search --output "agentic/runs/$BOSS_IDEA_RUN/local-browser-results.yaml" >/dev/null
scripts/validate-boss-idea-research.sh "agentic/runs/$BOSS_IDEA_RUN/market-research.md" >/dev/null
ruby -ryaml -e 'm=YAML.load_file(ARGV.fetch(0)); c=m.fetch("boss_idea_market_crawl"); abort("expected local browser provider") unless c["provider"] == "local_browser_search"; abort("expected fixture mode") unless c["mode"] == "fixture"; abort("expected no-paid provider") unless c["no_paid_provider"] == true; abort("expected provider priority") unless c["provider_priority"].to_i == 3' "agentic/runs/$BOSS_IDEA_RUN/manifest.yaml"

cat >"agentic/runs/$BOSS_IDEA_RUN/local-browser-missing-results-fixture.json" <<'JSON'
{
  "query_results": {
    "competitor_landscape": {"ok": true}
  }
}
JSON
if BOSS_IDEA_SEARCH_LOCAL_BROWSER_FIXTURE="agentic/runs/$BOSS_IDEA_RUN/local-browser-missing-results-fixture.json" scripts/crawl-boss-idea-market.sh --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider local_browser_search --output "agentic/runs/$BOSS_IDEA_RUN/bad-local-browser-missing-results.yaml" >/tmp/h20-boss-market-crawl-local-browser-missing-results.log 2>&1; then
  echo "expected local browser missing results fixture to fail" >&2
  exit 1
fi
grep -q "missing results" /tmp/h20-boss-market-crawl-local-browser-missing-results.log

cat >"agentic/runs/$BOSS_IDEA_RUN/local-browser-huge-helper.py" <<'PY'
#!/usr/bin/env python3
print("x" * (2 * 1024 * 1024 + 2))
PY
chmod +x "agentic/runs/$BOSS_IDEA_RUN/local-browser-huge-helper.py"
if BOSS_IDEA_LIVE_CRAWL=1 BOSS_IDEA_SEARCH_LOCAL_BROWSER_SEARCH_URL=https://93.184.216.34/search BOSS_IDEA_SEARCH_LOCAL_BROWSER_HELPER="agentic/runs/$BOSS_IDEA_RUN/local-browser-huge-helper.py" scripts/crawl-boss-idea-market.sh --live --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider local_browser_search --output "agentic/runs/$BOSS_IDEA_RUN/bad-local-browser-huge-results.yaml" >/tmp/h20-boss-market-crawl-local-browser-huge.log 2>&1; then
  echo "expected oversized local browser helper stdout to fail" >&2
  exit 1
fi
grep -q "stdout exceeds max response bytes" /tmp/h20-boss-market-crawl-local-browser-huge.log

cat >"agentic/runs/$BOSS_IDEA_RUN/invalid-market-crawl-live-redirect.yaml" <<'YAML'
candidates:
  - id: live-redirect-private
    query_id: competitor_landscape
    url: https://93.184.216.34/live-redirect
    redirect_url: http://10.0.0.1/private
    title: Live redirect to private target
    snippet: Should fail before Crawl4AI runtime is invoked.
    provider: live_seed
    source_type: vendor_docs
    signal: competitor
    claim: Live seed redirect policy blocks private targets.
    live_approved: true
YAML
if BOSS_IDEA_LIVE_CRAWL=1 scripts/crawl-boss-idea-market.sh --live --force --results-only "$BOSS_IDEA_RUN" --seeds "agentic/runs/$BOSS_IDEA_RUN/invalid-market-crawl-live-redirect.yaml" --output "agentic/runs/$BOSS_IDEA_RUN/bad-live-redirect-results.yaml" >/tmp/h20-boss-market-crawl-live-redirect.log 2>&1; then
  echo "expected live redirect-to-private market crawl seed to fail" >&2
  exit 1
fi
grep -q "blocked IP" /tmp/h20-boss-market-crawl-live-redirect.log

if scripts/crawl-boss-idea-market.sh --force --results-only "$BOSS_IDEA_RUN" --search-provider exotic --seeds agentic/fixtures/boss-idea-response/market-crawl-seeds.yaml --output "agentic/runs/$BOSS_IDEA_RUN/bad-provider-results.yaml" >/tmp/h20-boss-market-crawl-provider.log 2>&1; then
  echo "expected exotic seed provider to fail" >&2
  exit 1
fi
grep -q "search provider is not allowed" /tmp/h20-boss-market-crawl-provider.log

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

cat >"agentic/runs/$BOSS_IDEA_RUN/invalid-market-crawl-malformed-url.yaml" <<'YAML'
candidates:
  - id: bad-malformed-url
    query_id: competitor_landscape
    url: "https://exa mple.com/x"
    title: Bad malformed URL source
    snippet: Should fail in the per-candidate loop and record crawl-log evidence.
    provider: fixture
    source_type: vendor_docs
    signal: competitor
    claim: This malformed target must not be crawled.
    content_path: agentic/fixtures/boss-idea-response/market-crawl-pages/competitor-workflow.html
YAML
if scripts/crawl-boss-idea-market.sh --force --results-only "$BOSS_IDEA_RUN" --seeds "agentic/runs/$BOSS_IDEA_RUN/invalid-market-crawl-malformed-url.yaml" --output "agentic/runs/$BOSS_IDEA_RUN/bad-malformed-url-results.yaml" >/tmp/h20-boss-market-crawl-malformed-url.log 2>&1; then
  echo "expected malformed market crawl seed URL to fail" >&2
  exit 1
fi
grep -q "valid URL" /tmp/h20-boss-market-crawl-malformed-url.log
ruby -ryaml -e 'log=YAML.load_file(ARGV.fetch(0)); abort("expected malformed-url failed entry") unless log.fetch("entries").any? { |entry| entry["status"] == "failed" && entry["error"].to_s.include?("valid URL") }' "agentic/runs/$BOSS_IDEA_RUN/crawl4ai/crawl-log.yaml"

cat >"agentic/runs/$BOSS_IDEA_RUN/invalid-market-crawl-redirect.yaml" <<'YAML'
candidates:
  - id: bad-redirect
    query_id: competitor_landscape
    url: https://example.com/redirect
    redirect_url: http://10.0.0.1/private
    title: Bad redirect source
    snippet: Should fail before following redirect.
    provider: fixture
    source_type: vendor_docs
    signal: competitor
    claim: This unsafe redirect target must not be crawled.
    content_path: agentic/fixtures/boss-idea-response/market-crawl-pages/competitor-workflow.html
YAML
if scripts/crawl-boss-idea-market.sh --force --results-only "$BOSS_IDEA_RUN" --seeds "agentic/runs/$BOSS_IDEA_RUN/invalid-market-crawl-redirect.yaml" --output "agentic/runs/$BOSS_IDEA_RUN/bad-redirect-results.yaml" >/tmp/h20-boss-market-crawl-redirect.log 2>&1; then
  echo "expected redirect-to-private market crawl seed to fail" >&2
  exit 1
fi
grep -q "blocked IP" /tmp/h20-boss-market-crawl-redirect.log

cat >"agentic/runs/$BOSS_IDEA_RUN/invalid-market-crawl-circuit.yaml" <<'YAML'
candidates:
  - id: blocked-one
    query_id: competitor_landscape
    url: https://example.com/blocked-one
    title: Blocked one
    snippet: Should fail through robots policy.
    provider: fixture
    source_type: vendor_docs
    signal: competitor
    claim: Robots policy should stop this source.
    robots_allowed: false
    content_path: agentic/fixtures/boss-idea-response/market-crawl-pages/competitor-workflow.html
  - id: blocked-two
    query_id: competitor_landscape
    url: https://example.com/blocked-two
    title: Blocked two
    snippet: Should fail through robots policy.
    provider: fixture
    source_type: vendor_docs
    signal: competitor
    claim: Robots policy should stop this source.
    robots_allowed: false
    content_path: agentic/fixtures/boss-idea-response/market-crawl-pages/competitor-workflow.html
  - id: blocked-three
    query_id: competitor_landscape
    url: https://example.com/blocked-three
    title: Blocked three
    snippet: Should fail through robots policy.
    provider: fixture
    source_type: vendor_docs
    signal: competitor
    claim: Robots policy should stop this source.
    robots_allowed: false
    content_path: agentic/fixtures/boss-idea-response/market-crawl-pages/competitor-workflow.html
  - id: blocked-four
    query_id: competitor_landscape
    url: https://example.com/blocked-four
    title: Blocked four
    snippet: Should fail through robots policy.
    provider: fixture
    source_type: vendor_docs
    signal: competitor
    claim: Robots policy should stop this source.
    robots_allowed: false
    content_path: agentic/fixtures/boss-idea-response/market-crawl-pages/competitor-workflow.html
  - id: blocked-five
    query_id: competitor_landscape
    url: https://example.com/blocked-five
    title: Blocked five
    snippet: Should fail through robots policy.
    provider: fixture
    source_type: vendor_docs
    signal: competitor
    claim: Robots policy should stop this source.
    robots_allowed: false
    content_path: agentic/fixtures/boss-idea-response/market-crawl-pages/competitor-workflow.html
YAML
if scripts/crawl-boss-idea-market.sh --force --results-only "$BOSS_IDEA_RUN" --seeds "agentic/runs/$BOSS_IDEA_RUN/invalid-market-crawl-circuit.yaml" --output "agentic/runs/$BOSS_IDEA_RUN/bad-circuit-results.yaml" >/tmp/h20-boss-market-crawl-circuit.log 2>&1; then
  echo "expected crawl circuit breaker to fail" >&2
  exit 1
fi
grep -q "circuit breaker" /tmp/h20-boss-market-crawl-circuit.log
ruby -ryaml -e 'log=YAML.load_file(ARGV.fetch(0)); abort("expected five failed entries") unless log.fetch("entries").count { |entry| entry["status"] == "failed" } == 5' "agentic/runs/$BOSS_IDEA_RUN/crawl4ai/crawl-log.yaml"

cat >"agentic/runs/$BOSS_IDEA_RUN/valid-market-crawl-duplicate-ids.yaml" <<'YAML'
candidates:
  - id: duplicate-source
    query_id: competitor_landscape
    url: https://example.com/duplicate-one
    title: Duplicate one
    snippet: Should produce the base source id.
    provider: fixture
    source_type: vendor_docs
    signal: competitor
    claim: Comparable tooling already covers executive intake with evidence handoff.
    content_path: agentic/fixtures/boss-idea-response/market-crawl-pages/competitor-workflow.html
  - id: duplicate-source
    query_id: mainstream_practices
    url: https://example.com/duplicate-two
    title: Duplicate two
    snippet: Should produce a suffixed source id.
    provider: fixture
    source_type: public_report
    signal: mainstream_practice
    claim: Common practice favors cited analysis prior to reserving engineering effort.
    content_path: agentic/fixtures/boss-idea-response/market-crawl-pages/mainstream-practices.html
YAML
scripts/crawl-boss-idea-market.sh --force --results-only "$BOSS_IDEA_RUN" --seeds "agentic/runs/$BOSS_IDEA_RUN/valid-market-crawl-duplicate-ids.yaml" --output "agentic/runs/$BOSS_IDEA_RUN/duplicate-id-results.yaml" >/dev/null
ruby -ryaml -e 'ids=YAML.load_file(ARGV.fetch(0)).fetch("results").map { |r| r["id"] }; abort("expected unique ids") unless ids == ids.uniq && ids.any? { |id| id.start_with?("duplicate-source-") }' "agentic/runs/$BOSS_IDEA_RUN/duplicate-id-results.yaml"

ruby -e 'File.write(ARGV.fetch(0), "<!doctype html><html><body>" + ("lorem ipsum unique " * 8000) + "</body></html>")' "agentic/runs/$BOSS_IDEA_RUN/large-crawl-page.html"
cat >"agentic/runs/$BOSS_IDEA_RUN/valid-market-crawl-large.yaml" <<YAML
candidates:
  - id: large-page
    query_id: competitor_landscape
    url: https://example.com/large
    title: Large fixture page
    snippet: Should truncate and record the truncation.
    provider: fixture
    source_type: public_report
    signal: competitor
    claim: Oversized fixture content is summarized through a crawl-log record.
    content_path: agentic/runs/$BOSS_IDEA_RUN/large-crawl-page.html
YAML
scripts/crawl-boss-idea-market.sh --force --results-only "$BOSS_IDEA_RUN" --seeds "agentic/runs/$BOSS_IDEA_RUN/valid-market-crawl-large.yaml" --output "agentic/runs/$BOSS_IDEA_RUN/large-results.yaml" >/dev/null
ruby -ryaml -e 'log=YAML.load_file(ARGV.fetch(0)); abort("expected truncation") unless log.fetch("entries").any? { |entry| entry["truncated"] == true }' "agentic/runs/$BOSS_IDEA_RUN/crawl4ai/crawl-log.yaml"

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
