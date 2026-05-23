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
REQUESTED_ARTIFACT="docs/architecture/example-requested-artifact.md"

cleanup() {
  rm -rf \
    "agentic/runs/$PLANNING_RUN" \
    "agentic/runs/$NO_APPROVED_RUN" \
    "agentic/runs/$IMPLEMENTATION_RUN" \
    "agentic/runs/$BAD_SCHEMA_RUN" \
    "agentic/runs/$BOSS_IDEA_RUN" \
    "agentic/runs/$BOSS_DECISION_RUN" \
    "agentic/runs/$BOSS_MEMO_BAD_ID_RUN" \
    "agentic/runs/$BOSS_MEMO_BAD_PROFILE_RUN" \
    "agentic/runs/$BOSS_MEMO_BAD_ARTIFACTS_RUN" \
    "agentic/reviews/auto-doc-to-implementation/h16/$IMPLEMENTATION_RUN" \
    "agentic/reviews/auto-doc-to-implementation/h18/$IMPLEMENTATION_RUN" \
    "agentic/reviews/auto-doc-to-implementation/$PLANNING_RUN"
  rm -f "$REQUESTED_ARTIFACT"
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

RUN_ID="$BOSS_DECISION_RUN" scripts/init-boss-idea-run.sh agentic/fixtures/boss-idea-response/valid-idea.md >/dev/null
scripts/record-boss-idea-decision.sh agentic/fixtures/boss-idea-response/valid-decision.yaml --run-id "$BOSS_DECISION_RUN" >/dev/null
grep -q "boss_idea_decisions" "agentic/runs/$BOSS_DECISION_RUN/manifest.yaml"

echo "golden fixtures ok"
