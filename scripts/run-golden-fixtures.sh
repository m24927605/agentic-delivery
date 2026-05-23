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
REQUESTED_ARTIFACT="docs/architecture/example-requested-artifact.md"

cleanup() {
  rm -rf \
    "agentic/runs/$PLANNING_RUN" \
    "agentic/runs/$NO_APPROVED_RUN" \
    "agentic/runs/$IMPLEMENTATION_RUN" \
    "agentic/runs/$BAD_SCHEMA_RUN" \
    "agentic/runs/$BOSS_IDEA_RUN" \
    "agentic/runs/$BOSS_DECISION_RUN" \
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

RUN_ID="$BOSS_IDEA_RUN" scripts/init-boss-idea-run.sh agentic/fixtures/boss-idea-response/valid-idea.md >/dev/null
scripts/validate-manifest-schema.sh "$BOSS_IDEA_RUN" >/dev/null
grep -q "boss_idea_intake" "agentic/runs/$BOSS_IDEA_RUN/manifest.yaml"

scripts/validate-boss-idea-research.sh agentic/fixtures/boss-idea-response/valid-research.md >/dev/null
if scripts/validate-boss-idea-research.sh agentic/fixtures/boss-idea-response/invalid-research-missing-citation.md >/tmp/h20-boss-research.log 2>&1; then
  echo "expected missing research citation to fail" >&2
  exit 1
fi
grep -q "source_ids" /tmp/h20-boss-research.log

scripts/score-boss-idea-feasibility.sh --dry-run agentic/fixtures/boss-idea-response/valid-scorecard.yaml >/dev/null
if scripts/score-boss-idea-feasibility.sh --dry-run agentic/fixtures/boss-idea-response/invalid-scorecard-high-risk-no-mitigation.yaml >/tmp/h20-boss-score.log 2>&1; then
  echo "expected high risk without mitigation to fail" >&2
  exit 1
fi
grep -q "mitigations" /tmp/h20-boss-score.log

scripts/validate-boss-decision-memo.sh agentic/fixtures/boss-idea-response/valid-memo.md >/dev/null
if scripts/validate-boss-decision-memo.sh agentic/fixtures/boss-idea-response/invalid-memo-missing-options.md >/tmp/h20-boss-memo.log 2>&1; then
  echo "expected memo missing options to fail" >&2
  exit 1
fi
grep -q "Options Considered" /tmp/h20-boss-memo.log

scripts/validate-boss-idea-poc-mvp.sh agentic/fixtures/boss-idea-response/valid-poc-plan.md >/dev/null
if scripts/validate-boss-idea-poc-mvp.sh agentic/fixtures/boss-idea-response/invalid-poc-plan-missing-timebox.md >/tmp/h20-boss-poc.log 2>&1; then
  echo "expected missing POC timebox to fail" >&2
  exit 1
fi
grep -q "timebox_days" /tmp/h20-boss-poc.log

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
