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
BOSS_IDEA_SYMLINK_RUN="${RUN_PREFIX}-boss-idea-symlink"
BOSS_DECISION_RUN="${RUN_PREFIX}-boss-decision"
BOSS_BRIEF_NEGATIVE_RUN="${RUN_PREFIX}-boss-brief-negative"
BOSS_MEMO_BAD_ID_RUN="${RUN_PREFIX}-boss-memo-bad-id"
BOSS_MEMO_BAD_PROFILE_RUN="${RUN_PREFIX}-boss-memo-bad-profile"
BOSS_MEMO_BAD_ARTIFACTS_RUN="${RUN_PREFIX}-boss-memo-bad-artifacts"
BOSS_DECISION_BAD_ID_RUN="${RUN_PREFIX}-boss-decision-bad-id"
BOSS_DECISION_BAD_PROFILE_RUN="${RUN_PREFIX}-boss-decision-bad-profile"
BOSS_IMPLEMENTATION_RUN="${RUN_PREFIX}-boss-implementation"
BOSS_LIVE_SMOKE_RUN="${RUN_PREFIX}-boss-live-smoke"
REQUESTED_ARTIFACT="docs/architecture/example-requested-artifact.md"

cleanup() {
  if [[ -n "${LIVE_SMOKE_SEARXNG_PID:-}" ]]; then
    kill "$LIVE_SMOKE_SEARXNG_PID" 2>/dev/null || true
    wait "$LIVE_SMOKE_SEARXNG_PID" 2>/dev/null || true
  fi
  if [[ -n "${SEARXNG_PREFLIGHT_JSON_PID:-}" ]]; then
    kill "$SEARXNG_PREFLIGHT_JSON_PID" 2>/dev/null || true
    wait "$SEARXNG_PREFLIGHT_JSON_PID" 2>/dev/null || true
  fi
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
    "agentic/runs/$BOSS_IDEA_SYMLINK_RUN" \
    "agentic/runs/$BOSS_DECISION_RUN" \
    "agentic/runs/$BOSS_BRIEF_NEGATIVE_RUN" \
    "agentic/runs/$BOSS_MEMO_BAD_ID_RUN" \
    "agentic/runs/$BOSS_MEMO_BAD_PROFILE_RUN" \
    "agentic/runs/$BOSS_MEMO_BAD_ARTIFACTS_RUN" \
    "agentic/runs/$BOSS_DECISION_BAD_ID_RUN" \
    "agentic/runs/$BOSS_DECISION_BAD_PROFILE_RUN" \
    "agentic/runs/$BOSS_IMPLEMENTATION_RUN" \
    "agentic/runs/$BOSS_LIVE_SMOKE_RUN" \
    "agentic/reviews/auto-doc-to-implementation/h16/$IMPLEMENTATION_RUN" \
    "agentic/reviews/auto-doc-to-implementation/h16/$BOSS_IMPLEMENTATION_RUN" \
    "agentic/reviews/auto-doc-to-implementation/h18/$IMPLEMENTATION_RUN" \
    "agentic/reviews/auto-doc-to-implementation/h18/$BOSS_IMPLEMENTATION_RUN" \
    "agentic/reviews/auto-doc-to-implementation/$PLANNING_RUN" \
    "agentic/reviews/boss-idea-response/live-smoke/$BOSS_LIVE_SMOKE_RUN"
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

echo "fixture: Hermes Boss Idea live smoke action contract"
scripts/run-hermes-action.sh --dry-run run_boss_idea_live_smoke run_id="$BOSS_LIVE_SMOKE_RUN" live_crawl=1 searxng_base_url=http://127.0.0.1:8080/search searxng_endpoint_label=local-searxng searxng_no_paid_engines=1 actor=local-operator role=operator >/tmp/h20-hermes-live-smoke-dry-run.log
grep -q "BOSS_IDEA_LIVE_CRAWL=1" /tmp/h20-hermes-live-smoke-dry-run.log
grep -q "scripts/run-boss-idea-live-smoke.sh --live --force --search-provider searxng" /tmp/h20-hermes-live-smoke-dry-run.log
if scripts/run-hermes-action.sh run_boss_idea_live_smoke run_id="$BOSS_LIVE_SMOKE_RUN" live_crawl=1 searxng_base_url=http://127.0.0.1:8080/search searxng_endpoint_label=local-searxng searxng_no_paid_engines=1 >/tmp/h20-hermes-live-smoke-missing-identity.log 2>&1; then
  echo "expected Hermes live smoke execution without explicit identity to fail" >&2
  exit 1
fi
grep -q "explicit actor and role" /tmp/h20-hermes-live-smoke-missing-identity.log
if scripts/run-hermes-action.sh run_boss_idea_live_smoke run_id="$BOSS_LIVE_SMOKE_RUN" live_crawl=1 searxng_base_url=http://127.0.0.1:8080/search searxng_endpoint_label=local-searxng searxng_no_paid_engines=1 actor=document_builder role=document_builder >/tmp/h20-hermes-live-smoke-unauthorized.log 2>&1; then
  echo "expected Hermes live smoke unauthorized identity to fail" >&2
  exit 1
fi
grep -q "authorization failed" /tmp/h20-hermes-live-smoke-unauthorized.log
if scripts/run-hermes-action.sh --dry-run run_boss_idea_live_smoke run_id="$BOSS_LIVE_SMOKE_RUN" searxng_base_url=http://127.0.0.1:8080/search searxng_endpoint_label=local-searxng searxng_no_paid_engines=1 actor=local-operator role=operator >/tmp/h20-hermes-live-smoke-missing-live-gate.log 2>&1; then
  echo "expected Hermes live smoke missing live_crawl input to fail" >&2
  exit 1
fi
grep -q "missing required input" /tmp/h20-hermes-live-smoke-missing-live-gate.log

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

echo "fixture: boss idea crawl log observed network contract"
ruby -e 'require File.expand_path("scripts/lib/boss_idea", Dir.pwd); schema=BossIdea.load_yaml("agentic/schemas/boss-idea-crawl-log.schema.yaml").fetch("schema"); live=Array(schema["live_modes_requiring_observed_network"]); fields=Array(schema["observed_network_required_fields"]); fixtures=Array(schema["fixture_modes_without_network"]); public_ranges=Array(schema.dig("observed_ip_policy","ipv6_public_unicast_ranges")); ranges=Array(schema.dig("observed_ip_policy","reject_non_public_ranges")); authority=schema.fetch("authority_policy"); abort("expected searxng live metadata requirement") unless live.include?("searxng"); abort("expected final URL metadata") unless fields.include?("final_url"); abort("expected observed IP metadata") unless fields.include?("observed_ips"); abort("expected fixture mode exemption") unless fixtures.include?("fixture"); abort("expected IPv6 public unicast allowlist") unless public_ranges.include?("2000::/3"); abort("expected CGNAT rejection") unless ranges.include?("100.64.0.0/10"); abort("expected IPv6 documentation rejection") unless ranges.include?("2001:db8::/32") && ranges.include?("3fff::/20"); abort("expected IPv6 discard rejection") unless ranges.include?("100:0:0:1::/64"); abort("expected forbidden authority patterns") if Array(authority["forbidden_patterns"]).empty?; abort("expected authority allowlist") if Array(authority["allowed_note_patterns"]).empty?'
scripts/validate-boss-idea-crawl-log.sh agentic/fixtures/boss-idea-response/valid-crawl-log.yaml >/dev/null
scripts/validate-boss-idea-crawl-log.sh agentic/fixtures/boss-idea-response/valid-crawl-log-fixture-mode.yaml >/dev/null
if scripts/validate-boss-idea-crawl-log.sh agentic/fixtures/boss-idea-response/invalid-crawl-log-live-missing-observed-network.yaml >/tmp/h20-boss-crawl-log-missing-observed.log 2>&1; then
  echo "expected live crawl log missing observed network metadata to fail" >&2
  exit 1
fi
grep -q "observed_network" /tmp/h20-boss-crawl-log-missing-observed.log
if scripts/validate-boss-idea-crawl-log.sh agentic/fixtures/boss-idea-response/invalid-crawl-log-private-observed-ip.yaml >/tmp/h20-boss-crawl-log-private-ip.log 2>&1; then
  echo "expected crawl log private observed IP to fail" >&2
  exit 1
fi
grep -q "blocked IP" /tmp/h20-boss-crawl-log-private-ip.log
if scripts/validate-boss-idea-crawl-log.sh agentic/fixtures/boss-idea-response/invalid-crawl-log-failed-entry-private-observed-ip.yaml >/tmp/h20-boss-crawl-log-failed-private-ip.log 2>&1; then
  echo "expected failed crawl log entry private observed IP to fail" >&2
  exit 1
fi
grep -q "blocked IP" /tmp/h20-boss-crawl-log-failed-private-ip.log
if scripts/validate-boss-idea-crawl-log.sh agentic/fixtures/boss-idea-response/invalid-crawl-log-unspecified-observed-ip.yaml >/tmp/h20-boss-crawl-log-unspecified-ip.log 2>&1; then
  echo "expected crawl log unspecified observed IP to fail" >&2
  exit 1
fi
grep -q "blocked IP" /tmp/h20-boss-crawl-log-unspecified-ip.log
if scripts/validate-boss-idea-crawl-log.sh agentic/fixtures/boss-idea-response/invalid-crawl-log-documentation-observed-ip.yaml >/tmp/h20-boss-crawl-log-documentation-ip.log 2>&1; then
  echo "expected crawl log documentation observed IP to fail" >&2
  exit 1
fi
grep -q "blocked IP" /tmp/h20-boss-crawl-log-documentation-ip.log
if scripts/validate-boss-idea-crawl-log.sh agentic/fixtures/boss-idea-response/invalid-crawl-log-broadcast-observed-ip.yaml >/tmp/h20-boss-crawl-log-broadcast-ip.log 2>&1; then
  echo "expected crawl log broadcast observed IP to fail" >&2
  exit 1
fi
grep -q "blocked IP" /tmp/h20-boss-crawl-log-broadcast-ip.log
if scripts/validate-boss-idea-crawl-log.sh agentic/fixtures/boss-idea-response/invalid-crawl-log-cgnat-observed-ip.yaml >/tmp/h20-boss-crawl-log-cgnat-ip.log 2>&1; then
  echo "expected crawl log CGNAT observed IP to fail" >&2
  exit 1
fi
grep -q "blocked IP" /tmp/h20-boss-crawl-log-cgnat-ip.log
for crawl_log_ipv6_negative in \
  agentic/fixtures/boss-idea-response/invalid-crawl-log-ipv6-discard-observed-ip.yaml \
  agentic/fixtures/boss-idea-response/invalid-crawl-log-ipv6-documentation-3fff-observed-ip.yaml \
  agentic/fixtures/boss-idea-response/invalid-crawl-log-ipv6-private-translation-observed-ip.yaml \
  agentic/fixtures/boss-idea-response/invalid-crawl-log-ipv6-reserved-observed-ip.yaml \
  agentic/fixtures/boss-idea-response/invalid-crawl-log-ipv6-site-local-observed-ip.yaml; do
  if scripts/validate-boss-idea-crawl-log.sh "$crawl_log_ipv6_negative" >/tmp/h20-boss-crawl-log-ipv6-special.log 2>&1; then
    echo "expected crawl log IPv6 special-purpose observed IP to fail: $crawl_log_ipv6_negative" >&2
    exit 1
  fi
  grep -q "blocked IP" /tmp/h20-boss-crawl-log-ipv6-special.log
done
if scripts/validate-boss-idea-crawl-log.sh agentic/fixtures/boss-idea-response/invalid-crawl-log-authority-approval.yaml >/tmp/h20-boss-crawl-log-authority.log 2>&1; then
  echo "expected crawl log authority approval to fail" >&2
  exit 1
fi
grep -q "forbidden authority" /tmp/h20-boss-crawl-log-authority.log
for crawl_log_authority_negative in \
  agentic/fixtures/boss-idea-response/invalid-crawl-log-authority-cleared.yaml \
  agentic/fixtures/boss-idea-response/invalid-crawl-log-authority-good-to-go.yaml \
  agentic/fixtures/boss-idea-response/invalid-crawl-log-authority-greenlit.yaml; do
  if scripts/validate-boss-idea-crawl-log.sh "$crawl_log_authority_negative" >/tmp/h20-boss-crawl-log-authority-extra.log 2>&1; then
    echo "expected crawl log authority synonym to fail: $crawl_log_authority_negative" >&2
    exit 1
  fi
  grep -q "allowed evidence-only wording" /tmp/h20-boss-crawl-log-authority-extra.log
done
CRAWL_LOG_NEGATIVE_DIR="agentic/runs/$BOSS_BRIEF_NEGATIVE_RUN/crawl-log-negatives"
mkdir -p "$CRAWL_LOG_NEGATIVE_DIR"
ruby -ryaml -rfileutils -e 'base=YAML.load_file(ARGV.fetch(0)); dir=ARGV.fetch(1); ips={"mapped-loopback"=>"::ffff:127.0.0.1","mapped-private"=>"::ffff:10.0.0.1","mapped-link-local"=>"::ffff:169.254.1.1","mapped-metadata"=>"::ffff:169.254.169.254","mapped-documentation"=>"::ffff:192.0.2.1"}; ips.each { |name, ip| doc=Marshal.load(Marshal.dump(base)); doc.fetch("entries").fetch(0).fetch("observed_network")["observed_ips"]=[ip]; File.write(File.join(dir, "invalid-crawl-log-#{name}.yaml"), doc.to_yaml) }' agentic/fixtures/boss-idea-response/valid-crawl-log.yaml "$CRAWL_LOG_NEGATIVE_DIR"
for crawl_log_negative in "$CRAWL_LOG_NEGATIVE_DIR"/invalid-crawl-log-mapped-*.yaml; do
  if scripts/validate-boss-idea-crawl-log.sh "$crawl_log_negative" >/tmp/h20-boss-crawl-log-mapped-ip.log 2>&1; then
    echo "expected crawl log mapped blocked observed IP to fail: $crawl_log_negative" >&2
    exit 1
  fi
  grep -q "blocked IP" /tmp/h20-boss-crawl-log-mapped-ip.log
done
ruby -ryaml -rfileutils -e 'base=YAML.load_file(ARGV.fetch(0)); dir=ARGV.fetch(1); ips={"reserved-0101"=>"101::1","reserved-4000"=>"4000::1","reserved-8000"=>"8000::1","reserved-c000"=>"c000::1","reserved-e000"=>"e000::1","deprecated-site-local"=>"fec0::1"}; ips.each { |name, ip| doc=Marshal.load(Marshal.dump(base)); doc.fetch("entries").fetch(0).fetch("observed_network")["observed_ips"]=[ip]; File.write(File.join(dir, "invalid-crawl-log-ipv6-#{name}.yaml"), doc.to_yaml) }' agentic/fixtures/boss-idea-response/valid-crawl-log.yaml "$CRAWL_LOG_NEGATIVE_DIR"
for crawl_log_negative in "$CRAWL_LOG_NEGATIVE_DIR"/invalid-crawl-log-ipv6-*.yaml; do
  if scripts/validate-boss-idea-crawl-log.sh "$crawl_log_negative" >/tmp/h20-boss-crawl-log-ipv6-reserved.log 2>&1; then
    echo "expected crawl log reserved IPv6 observed IP to fail: $crawl_log_negative" >&2
    exit 1
  fi
  grep -q "blocked IP" /tmp/h20-boss-crawl-log-ipv6-reserved.log
done

echo "fixture: boss idea provider health schema and retention contract"
ruby -e 'require File.expand_path("scripts/lib/boss_idea", Dir.pwd); schema=BossIdea.load_yaml("agentic/schemas/boss-idea-provider-health.schema.yaml").fetch("schema"); reasons=Array(schema["fallback_reason_taxonomy"]); counters=Array(schema["counter_required_fields"]); retention=schema.fetch("retention_policy"); safety=schema.fetch("public_safety"); authority=schema.fetch("authority_policy"); abort("expected challenge/captcha fallback reason") unless reasons.include?("challenge_or_captcha"); abort("expected provider timeout fallback reason") unless reasons.include?("provider_timeout"); abort("expected challenge/captcha counter") unless counters.include?("challenge_or_captcha_count"); abort("expected 14-day raw retention") unless retention["raw_event_retention_days"] == 14; abort("expected scrubbed summary tracked policy") unless retention["tracked_artifact_policy"] == "scrubbed_summary_only"; abort("expected raw events ignored path policy") unless retention["raw_event_path_policy"] == "ignored_paths_only"; abort("expected URL forbidden in tracked health") unless Array(safety["forbidden_keys"]).include?("url"); abort("expected advisory authority") unless authority["advisory_only"] == true'
ruby -e 'require File.expand_path("scripts/lib/boss_idea", Dir.pwd); health=BossIdea.load_yaml("agentic/schemas/boss-idea-provider-health.schema.yaml").fetch("schema"); events=BossIdea.load_yaml("agentic/schemas/boss-idea-provider-health-events.schema.yaml").fetch("schema"); advisory=BossIdea.load_yaml("agentic/schemas/boss-idea-provider-fallback-advisory.schema.yaml").fetch("schema"); health_reasons=Array(health["fallback_reason_taxonomy"]); event_reasons=Array(events["reason_taxonomy"]); advisory_reasons=Array(advisory["allowed_reason_labels"]); abort("provider health event taxonomy drift") unless event_reasons == health_reasons; abort("advisory reason taxonomy missing health reasons") unless (health_reasons - advisory_reasons).empty?; abort("event retention drift") unless events.fetch("retention_policy") == health.fetch("retention_policy").slice("raw_event_retention_days","scrubbed_summary_retention_days","tracked_artifact_policy","raw_event_path_policy","public_safe_counts_only"); abort("advisory must require human decision") unless Array(advisory["recommendation_required_fields"]).include?("requires_human_decision"); abort("advisory approval status must be not_approved") unless advisory["approval_status"] == "not_approved"'
scripts/validate-boss-idea-provider-health-events.sh agentic/fixtures/boss-idea-response/valid-provider-health-events.yaml >/dev/null
if scripts/validate-boss-idea-provider-health-events.sh agentic/fixtures/boss-idea-response/invalid-provider-health-events-fallback-reason.yaml >/tmp/h20-boss-provider-health-events-fallback-reason.log 2>&1; then
  echo "expected provider health events invalid fallback reason to fail" >&2
  exit 1
fi
grep -q "reason is invalid" /tmp/h20-boss-provider-health-events-fallback-reason.log
if scripts/validate-boss-idea-provider-health-events.sh agentic/fixtures/boss-idea-response/invalid-provider-health-events-raw-query.yaml >/tmp/h20-boss-provider-health-events-raw-query.log 2>&1; then
  echo "expected provider health events raw query to fail" >&2
  exit 1
fi
grep -q "public-safe provider health events" /tmp/h20-boss-provider-health-events-raw-query.log
if scripts/validate-boss-idea-provider-health-events.sh agentic/fixtures/boss-idea-response/invalid-provider-health-events-summary-captcha-count.yaml >/tmp/h20-boss-provider-health-events-captcha-summary.log 2>&1; then
  echo "expected provider health events challenge/captcha summary mismatch to fail" >&2
  exit 1
fi
grep -q "challenge_or_captcha_count" /tmp/h20-boss-provider-health-events-captcha-summary.log
if scripts/validate-boss-idea-provider-health-events.sh agentic/fixtures/boss-idea-response/invalid-provider-health-events-authority-approval.yaml >/tmp/h20-boss-provider-health-events-authority.log 2>&1; then
  echo "expected provider health events authority approval to fail" >&2
  exit 1
fi
grep -q "authority" /tmp/h20-boss-provider-health-events-authority.log
scripts/validate-boss-idea-provider-health.sh agentic/fixtures/boss-idea-response/valid-provider-health.yaml >/dev/null
if scripts/validate-boss-idea-provider-health.sh agentic/fixtures/boss-idea-response/invalid-provider-health-authority-approval.yaml >/tmp/h20-boss-provider-health-authority.log 2>&1; then
  echo "expected provider health authority approval to fail" >&2
  exit 1
fi
grep -q "authority" /tmp/h20-boss-provider-health-authority.log
if scripts/validate-boss-idea-provider-health.sh agentic/fixtures/boss-idea-response/invalid-provider-health-fallback-reason.yaml >/tmp/h20-boss-provider-health-fallback-reason.log 2>&1; then
  echo "expected provider health invalid fallback reason to fail" >&2
  exit 1
fi
grep -q "reason is invalid" /tmp/h20-boss-provider-health-fallback-reason.log
if scripts/validate-boss-idea-provider-health.sh agentic/fixtures/boss-idea-response/invalid-provider-health-retention.yaml >/tmp/h20-boss-provider-health-retention.log 2>&1; then
  echo "expected provider health retention violation to fail" >&2
  exit 1
fi
grep -q "retention_policy.raw_event_retention_days" /tmp/h20-boss-provider-health-retention.log
if scripts/validate-boss-idea-provider-health.sh agentic/fixtures/boss-idea-response/invalid-provider-health-raw-url.yaml >/tmp/h20-boss-provider-health-raw-url.log 2>&1; then
  echo "expected provider health raw URL to fail" >&2
  exit 1
fi
grep -q "public-safe provider health" /tmp/h20-boss-provider-health-raw-url.log
if scripts/validate-boss-idea-provider-health.sh agentic/fixtures/boss-idea-response/invalid-provider-health-summary-captcha-count.yaml >/tmp/h20-boss-provider-health-captcha-summary.log 2>&1; then
  echo "expected provider health challenge/captcha summary mismatch to fail" >&2
  exit 1
fi
grep -q "total_challenge_or_captcha_count" /tmp/h20-boss-provider-health-captcha-summary.log
scripts/validate-boss-idea-provider-fallback-advisory.sh agentic/fixtures/boss-idea-response/valid-provider-fallback-advisory.yaml >/dev/null
if scripts/validate-boss-idea-provider-fallback-advisory.sh agentic/fixtures/boss-idea-response/invalid-provider-fallback-advisory-auto-execution.yaml >/tmp/h20-boss-provider-fallback-auto.log 2>&1; then
  echo "expected provider fallback advisory auto execution to fail" >&2
  exit 1
fi
grep -q "automatic_execution_allowed" /tmp/h20-boss-provider-fallback-auto.log
if scripts/validate-boss-idea-provider-fallback-advisory.sh agentic/fixtures/boss-idea-response/invalid-provider-fallback-advisory-approval.yaml >/tmp/h20-boss-provider-fallback-approval.log 2>&1; then
  echo "expected provider fallback advisory approval to fail" >&2
  exit 1
fi
grep -q "approval_status" /tmp/h20-boss-provider-fallback-approval.log
if scripts/validate-boss-idea-provider-fallback-advisory.sh agentic/fixtures/boss-idea-response/invalid-provider-fallback-advisory-reason.yaml >/tmp/h20-boss-provider-fallback-reason.log 2>&1; then
  echo "expected provider fallback advisory invalid reason to fail" >&2
  exit 1
fi
grep -q "reason is invalid" /tmp/h20-boss-provider-fallback-reason.log
if scripts/validate-boss-idea-provider-fallback-advisory.sh agentic/fixtures/boss-idea-response/invalid-provider-fallback-advisory-raw-url.yaml >/tmp/h20-boss-provider-fallback-raw-url.log 2>&1; then
  echo "expected provider fallback advisory raw URL to fail" >&2
  exit 1
fi
grep -q "fallback advisory content" /tmp/h20-boss-provider-fallback-raw-url.log
scripts/recommend-boss-idea-provider-fallback.sh --output "agentic/runs/$BOSS_BRIEF_NEGATIVE_RUN/provider-fallback-advisory.yaml" agentic/fixtures/boss-idea-response/valid-provider-health.yaml >/dev/null
scripts/validate-boss-idea-provider-fallback-advisory.sh "agentic/runs/$BOSS_BRIEF_NEGATIVE_RUN/provider-fallback-advisory.yaml" >/dev/null
ruby -ryaml -e 'a=YAML.load_file(ARGV.fetch(0)); recs=a.fetch("recommendations"); abort("expected consider fallback") unless recs.any? { |r| r["provider"] == "searxng" && r["advisory_action"] == "consider_fallback" && r["suggested_fallback_provider"] == "duckduckgo_html" && r["requires_human_decision"] == true && r["automatic_execution_allowed"] == false && r["approval_status"] == "not_approved" }; abort("expected challenge escalation") unless recs.any? { |r| r["provider"] == "duckduckgo_html" && r["advisory_action"] == "escalate_staff_review" && r["reason"] == "challenge_or_captcha" }' "agentic/runs/$BOSS_BRIEF_NEGATIVE_RUN/provider-fallback-advisory.yaml"

echo "fixture: boss idea competitor brief template contract"
ruby <<'RUBY'
require File.expand_path("scripts/lib/boss_idea", Dir.pwd)

schema = BossIdea.load_yaml("agentic/schemas/boss-idea-competitor-brief.schema.yaml").fetch("schema")
frontmatter, body, sections = BossIdea.load_markdown("agentic/fixtures/boss-idea-response/competitor-brief-template.md")

Array(schema.fetch("required_frontmatter")).each do |field|
  abort("missing frontmatter #{field}") unless frontmatter.key?(field)
end

Array(schema.fetch("required_evidence_inputs")).each do |field|
  abort("missing evidence input #{field}") unless frontmatter.fetch("evidence_inputs").key?(field)
end

Array(schema.fetch("required_sections")).each do |section|
  BossIdea.require_section!(sections, section, "competitor brief template")
end

boundary = frontmatter.fetch("recommendation_boundary").downcase
Array(schema.dig("authority_policy", "required_phrases")).each do |phrase|
  abort("missing boundary phrase #{phrase}") unless boundary.include?(phrase)
end

Array(schema.dig("authority_policy", "forbidden_phrases")).each do |phrase|
  abort("forbidden authority phrase #{phrase}") if body.downcase.include?(phrase)
end

abort("missing option headings") unless Array(schema.fetch("option_ids")).all? do |option|
  sections.key?(option) && !sections.fetch(option).empty?
end

column_labels = {
  "claim_id" => "Claim ID",
  "competitor_or_alternative" => "Competitor Or Alternative",
  "relevant_capability" => "Relevant Capability",
  "source_ids" => "Source IDs",
  "gap_or_risk" => "Gap Or Risk",
  "implication" => "Implication",
  "source_id" => "Source ID",
  "claim_ids" => "Claim IDs",
  "brief_sections" => "Brief Sections"
}

competitor_matrix = sections.fetch("competitor_matrix")
Array(schema.fetch("competitor_matrix_required_columns")).each do |field|
  abort("missing competitor matrix column #{field}") unless competitor_matrix.include?(column_labels.fetch(field))
end

source_mapping = sections.fetch("source_mapping")
Array(schema.fetch("source_mapping_required_fields")).each do |field|
  abort("missing source mapping field #{field}") unless source_mapping.include?(column_labels.fetch(field))
end

Array(schema.fetch("claim_bearing_sections")).each do |section|
  key = BossIdea.normalize_heading(section)
  text = sections.fetch(key, "")
  Array(schema.fetch("claim_reference_required_fields")).each do |field|
    abort("missing #{field} in claim-bearing section #{section}") unless text.include?(column_labels.fetch(field))
  end
end

claim_policy = schema.fetch("claim_policy")
abort("competitor claims must require source ids") unless claim_policy.fetch("competitor_claims_require_source_ids") == true
abort("competitor or market claims must require claim ids") unless claim_policy.fetch("competitor_or_market_claims_require_claim_ids") == true
abort("claim ids must map to sources") unless claim_policy.fetch("claim_ids_must_map_to_sources") == true
abort("raw provider text must stay disallowed") unless claim_policy.fetch("copied_raw_provider_text_allowed") == false
abort("template must not allow source-id-or-none") if body.downcase.include?("source-id-or-none")
abort("template must not allow uncited claim placeholders") if body.downcase.match?(/source ids:\s*(none|n\/a|unknown)/)
RUBY

scripts/validate-boss-idea-competitor-brief.sh agentic/fixtures/boss-idea-response/valid-competitor-brief.md >/dev/null
if scripts/validate-boss-idea-competitor-brief.sh agentic/fixtures/boss-idea-response/invalid-competitor-brief-source-none.md >/tmp/h20-boss-brief-source-none.log 2>&1; then
  echo "expected competitor brief source none to fail" >&2
  exit 1
fi
grep -q "source_ids cannot allow" /tmp/h20-boss-brief-source-none.log
if scripts/validate-boss-idea-competitor-brief.sh agentic/fixtures/boss-idea-response/invalid-competitor-brief-unmapped-source.md >/tmp/h20-boss-brief-unmapped-source.log 2>&1; then
  echo "expected competitor brief unmapped source to fail" >&2
  exit 1
fi
grep -q "missing from Source Mapping" /tmp/h20-boss-brief-unmapped-source.log
if scripts/validate-boss-idea-competitor-brief.sh agentic/fixtures/boss-idea-response/invalid-competitor-brief-approval-authority.md >/tmp/h20-boss-brief-approval-authority.log 2>&1; then
  echo "expected competitor brief authority claim to fail" >&2
  exit 1
fi
grep -q "forbidden authority phrase" /tmp/h20-boss-brief-approval-authority.log

BRIEF_NEGATIVE_DIR="agentic/runs/$BOSS_BRIEF_NEGATIVE_RUN"
mkdir -p "$BRIEF_NEGATIVE_DIR"
ruby - agentic/fixtures/boss-idea-response/valid-competitor-brief.md "$BRIEF_NEGATIVE_DIR" <<'RUBY'
valid = File.read(ARGV.fetch(0))
dir = ARGV.fetch(1)
boundary_line = "Decision after timebox: Submit a separate go/no-go decision artifact; this brief cannot approve implementation."
boundary_frontmatter = 'recommendation_boundary: "This brief is evidence only and cannot approve artifacts, decisions, roadmap, budget, implementation, PR publishing, or deployment."'
File.write(File.join(dir, "invalid-deployment-authority.md"), valid.sub(boundary_line, "Decision after timebox: This brief approves deployment."))
File.write(File.join(dir, "invalid-can-approve-authority.md"), valid.sub(boundary_line, "Decision after timebox: This brief can approve deployment."))
File.write(File.join(dir, "invalid-implementation-approved-authority.md"), valid.sub(boundary_line, "Decision after timebox: Implementation approved by this brief."))
File.write(File.join(dir, "invalid-budget-approval-authority.md"), valid.sub(boundary_line, "Decision after timebox: Budget approval granted by this brief."))
File.write(File.join(dir, "invalid-go-decision-authority.md"), valid.sub(boundary_line, "Decision after timebox: go/no-go decision is approved by this brief."))
File.write(File.join(dir, "invalid-go-decision-approval-granted.md"), valid.sub(boundary_line, "Decision after timebox: go/no-go decision approval granted by this brief."))
File.write(File.join(dir, "invalid-mixed-body-authority.md"), valid.sub(boundary_line, "Decision after timebox: This brief cannot approve implementation, but deployment is authorized."))
File.write(File.join(dir, "invalid-may-deploy-authority.md"), valid.sub(boundary_line, "Decision after timebox: This brief may deploy."))
File.write(File.join(dir, "invalid-implementation-proceed-authority.md"), valid.sub(boundary_line, "Decision after timebox: Implementation may proceed."))
File.write(File.join(dir, "invalid-pr-publishing-proceed-authority.md"), valid.sub(boundary_line, "Decision after timebox: PR publishing may proceed."))
File.write(File.join(dir, "invalid-roadmap-set-authority.md"), valid.sub(boundary_line, "Decision after timebox: Roadmap can be set by this brief."))
File.write(File.join(dir, "invalid-boundary-authority.md"), valid.sub(boundary_frontmatter, 'recommendation_boundary: "This brief is evidence only and cannot approve implementation. This brief approves deployment."'))
File.write(File.join(dir, "invalid-mixed-boundary-authority.md"), valid.sub(boundary_frontmatter, 'recommendation_boundary: "This brief is evidence only and cannot approve implementation, but deployment is authorized."'))
File.write(File.join(dir, "invalid-boundary-proceed-authority.md"), valid.sub(boundary_frontmatter, 'recommendation_boundary: "This brief is evidence only and cannot approve implementation. Implementation may proceed."'))
File.write(File.join(dir, "invalid-extra-source-mapping.md"), valid.sub("| source-a | c-experiment-1 | Next Experiment And Timebox |", "| source-a | c-experiment-1 | Next Experiment And Timebox |\n| source-b | c-summary-1 | Executive Summary |"))
File.write(File.join(dir, "invalid-mismatched-source-section.md"), valid.sub("| source-a | c-summary-1 | Executive Summary |", "| source-a | c-summary-1 | Build |"))
File.write(File.join(dir, "invalid-malformed-claim-table.md"), valid.sub("| c-comp-1 | Comparable workflow | Source-backed research review | source-a | Manual review can delay urgency. | Keep the next step timeboxed. |", "| c-comp-1 | Comparable workflow | Source-backed research review | source-a | Manual review can delay urgency. | Keep the next step timeboxed. |\n| c-comp-bad | Comparable workflow | Source-backed research review | Missing source cell | Keep the next step timeboxed. |"))
RUBY
if scripts/validate-boss-idea-competitor-brief.sh "$BRIEF_NEGATIVE_DIR/invalid-deployment-authority.md" >/tmp/h20-boss-brief-deployment-authority.log 2>&1; then
  echo "expected competitor brief deployment authority claim to fail" >&2
  exit 1
fi
grep -q "forbidden authority pattern" /tmp/h20-boss-brief-deployment-authority.log
if scripts/validate-boss-idea-competitor-brief.sh "$BRIEF_NEGATIVE_DIR/invalid-can-approve-authority.md" >/tmp/h20-boss-brief-can-approve-authority.log 2>&1; then
  echo "expected competitor brief can approve authority claim to fail" >&2
  exit 1
fi
grep -q "forbidden authority pattern" /tmp/h20-boss-brief-can-approve-authority.log
if scripts/validate-boss-idea-competitor-brief.sh "$BRIEF_NEGATIVE_DIR/invalid-implementation-approved-authority.md" >/tmp/h20-boss-brief-implementation-approved-authority.log 2>&1; then
  echo "expected competitor brief implementation approved authority claim to fail" >&2
  exit 1
fi
grep -q "forbidden authority pattern" /tmp/h20-boss-brief-implementation-approved-authority.log
if scripts/validate-boss-idea-competitor-brief.sh "$BRIEF_NEGATIVE_DIR/invalid-budget-approval-authority.md" >/tmp/h20-boss-brief-budget-approval-authority.log 2>&1; then
  echo "expected competitor brief budget approval authority claim to fail" >&2
  exit 1
fi
grep -q "forbidden authority pattern" /tmp/h20-boss-brief-budget-approval-authority.log
if scripts/validate-boss-idea-competitor-brief.sh "$BRIEF_NEGATIVE_DIR/invalid-go-decision-authority.md" >/tmp/h20-boss-brief-go-decision-authority.log 2>&1; then
  echo "expected competitor brief go/no-go authority claim to fail" >&2
  exit 1
fi
grep -q "forbidden authority" /tmp/h20-boss-brief-go-decision-authority.log
if scripts/validate-boss-idea-competitor-brief.sh "$BRIEF_NEGATIVE_DIR/invalid-go-decision-approval-granted.md" >/tmp/h20-boss-brief-go-decision-approval-granted.log 2>&1; then
  echo "expected competitor brief go/no-go approval granted claim to fail" >&2
  exit 1
fi
grep -q "forbidden authority pattern" /tmp/h20-boss-brief-go-decision-approval-granted.log
if scripts/validate-boss-idea-competitor-brief.sh "$BRIEF_NEGATIVE_DIR/invalid-mixed-body-authority.md" >/tmp/h20-boss-brief-mixed-body-authority.log 2>&1; then
  echo "expected competitor brief mixed body authority claim to fail" >&2
  exit 1
fi
grep -q "forbidden authority claim" /tmp/h20-boss-brief-mixed-body-authority.log
if scripts/validate-boss-idea-competitor-brief.sh "$BRIEF_NEGATIVE_DIR/invalid-may-deploy-authority.md" >/tmp/h20-boss-brief-may-deploy-authority.log 2>&1; then
  echo "expected competitor brief may deploy authority claim to fail" >&2
  exit 1
fi
grep -q "forbidden authority claim" /tmp/h20-boss-brief-may-deploy-authority.log
if scripts/validate-boss-idea-competitor-brief.sh "$BRIEF_NEGATIVE_DIR/invalid-implementation-proceed-authority.md" >/tmp/h20-boss-brief-implementation-proceed-authority.log 2>&1; then
  echo "expected competitor brief implementation proceed authority claim to fail" >&2
  exit 1
fi
grep -q "forbidden authority claim" /tmp/h20-boss-brief-implementation-proceed-authority.log
if scripts/validate-boss-idea-competitor-brief.sh "$BRIEF_NEGATIVE_DIR/invalid-pr-publishing-proceed-authority.md" >/tmp/h20-boss-brief-pr-publishing-proceed-authority.log 2>&1; then
  echo "expected competitor brief PR publishing authority claim to fail" >&2
  exit 1
fi
grep -q "forbidden authority claim" /tmp/h20-boss-brief-pr-publishing-proceed-authority.log
if scripts/validate-boss-idea-competitor-brief.sh "$BRIEF_NEGATIVE_DIR/invalid-roadmap-set-authority.md" >/tmp/h20-boss-brief-roadmap-set-authority.log 2>&1; then
  echo "expected competitor brief roadmap set authority claim to fail" >&2
  exit 1
fi
grep -q "forbidden authority claim" /tmp/h20-boss-brief-roadmap-set-authority.log
if scripts/validate-boss-idea-competitor-brief.sh "$BRIEF_NEGATIVE_DIR/invalid-boundary-authority.md" >/tmp/h20-boss-brief-boundary-authority.log 2>&1; then
  echo "expected competitor brief boundary authority claim to fail" >&2
  exit 1
fi
grep -q "recommendation_boundary contains forbidden authority" /tmp/h20-boss-brief-boundary-authority.log
if scripts/validate-boss-idea-competitor-brief.sh "$BRIEF_NEGATIVE_DIR/invalid-mixed-boundary-authority.md" >/tmp/h20-boss-brief-mixed-boundary-authority.log 2>&1; then
  echo "expected competitor brief mixed boundary authority claim to fail" >&2
  exit 1
fi
grep -q "recommendation_boundary contains forbidden authority claim" /tmp/h20-boss-brief-mixed-boundary-authority.log
if scripts/validate-boss-idea-competitor-brief.sh "$BRIEF_NEGATIVE_DIR/invalid-boundary-proceed-authority.md" >/tmp/h20-boss-brief-boundary-proceed-authority.log 2>&1; then
  echo "expected competitor brief boundary proceed authority claim to fail" >&2
  exit 1
fi
grep -q "recommendation_boundary contains forbidden authority claim" /tmp/h20-boss-brief-boundary-proceed-authority.log
if scripts/validate-boss-idea-competitor-brief.sh "$BRIEF_NEGATIVE_DIR/invalid-extra-source-mapping.md" >/tmp/h20-boss-brief-extra-source-mapping.log 2>&1; then
  echo "expected competitor brief extra source mapping to fail" >&2
  exit 1
fi
grep -q "extra tuple" /tmp/h20-boss-brief-extra-source-mapping.log
if scripts/validate-boss-idea-competitor-brief.sh "$BRIEF_NEGATIVE_DIR/invalid-mismatched-source-section.md" >/tmp/h20-boss-brief-mismatched-source-section.log 2>&1; then
  echo "expected competitor brief mismatched source section to fail" >&2
  exit 1
fi
grep -q "missing from Source Mapping" /tmp/h20-boss-brief-mismatched-source-section.log
if scripts/validate-boss-idea-competitor-brief.sh "$BRIEF_NEGATIVE_DIR/invalid-malformed-claim-table.md" >/tmp/h20-boss-brief-malformed-claim-table.log 2>&1; then
  echo "expected competitor brief malformed claim table to fail" >&2
  exit 1
fi
grep -q "markdown table row" /tmp/h20-boss-brief-malformed-claim-table.log

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
test -f "agentic/runs/$BOSS_IDEA_RUN/market-discovery-quality.yaml"
test -f "agentic/runs/$BOSS_IDEA_RUN/crawl4ai/crawl-log.yaml"
test -f "agentic/runs/$BOSS_IDEA_RUN/market-research.md"
scripts/validate-boss-idea-research.sh "agentic/runs/$BOSS_IDEA_RUN/market-research.md" >/dev/null
scripts/validate-boss-idea-market-discovery-quality.sh "agentic/runs/$BOSS_IDEA_RUN/market-discovery-quality.yaml" >/dev/null
grep -q "boss_idea_market_crawl" "agentic/runs/$BOSS_IDEA_RUN/manifest.yaml"
grep -q "boss_idea_market_research" "agentic/runs/$BOSS_IDEA_RUN/manifest.yaml"
git check-ignore -q "agentic/runs/$BOSS_IDEA_RUN/crawl4ai/raw/competitor-public-workflow.md"
ruby -ryaml -e 'm=YAML.load_file(ARGV.fetch(0)); q=YAML.load_file(ARGV.fetch(1)); c=m.fetch("boss_idea_market_crawl"); r=m.fetch("boss_idea_market_research"); abort("expected fixture provider") unless c["provider"] == "fixture"; abort("expected source count") unless c["source_count"].to_i >= 2; abort("expected research artifact") unless r["artifact_path"].to_s.end_with?("market-research.md"); abort("expected quality path") unless c["quality_path"] == ARGV.fetch(1); abort("expected quality score") unless c["quality_score"].to_i == q.fetch("score").to_i; abort("expected quality band") unless c["quality_band"].to_s == q.fetch("band").to_s; abort("quality must be advisory") unless q.fetch("authority_note").include?("cannot approve"); abort("market crawl must not approve artifacts") unless m.fetch("artifacts").all? { |a| a["status"] == "planned" }' "agentic/runs/$BOSS_IDEA_RUN/manifest.yaml" "agentic/runs/$BOSS_IDEA_RUN/market-discovery-quality.yaml"
scripts/generate-boss-idea-competitor-brief.sh --output "agentic/runs/$BOSS_IDEA_RUN/generated-competitor-brief.md" "$BOSS_IDEA_RUN" >/dev/null
scripts/validate-boss-idea-competitor-brief.sh "agentic/runs/$BOSS_IDEA_RUN/generated-competitor-brief.md" >/dev/null
ruby - "agentic/runs/$BOSS_IDEA_RUN/generated-competitor-brief.md" "agentic/runs/$BOSS_IDEA_RUN/market-research.md" "agentic/runs/$BOSS_IDEA_RUN/market-discovery-quality.yaml" <<'RUBY'
require File.expand_path("scripts/lib/boss_idea", Dir.pwd)

brief_path = ARGV.fetch(0)
research_path = ARGV.fetch(1)
quality_path = ARGV.fetch(2)
frontmatter, body, sections = BossIdea.load_markdown(brief_path)
research_frontmatter, = BossIdea.load_markdown(research_path)
quality = BossIdea.load_yaml(quality_path)
sources = BossIdea.require_array!(research_frontmatter, "sources", "research")

abort("expected generated artifact status") unless frontmatter["artifact_status"] == "drafted"
abort("expected generated research input") unless frontmatter.dig("evidence_inputs", "market_research").to_s == research_path
abort("expected generated quality input") unless frontmatter.dig("evidence_inputs", "market_discovery_quality").to_s == quality_path
abort("expected no placeholders") if body.match?(/<[a-z0-9_-]+>/i)
abort("expected generated source mapping") unless sections.fetch("source_mapping").include?("| Source ID | Claim IDs | Brief Sections |")

expected_summary = "The validated research set contains #{sources.length} source-backed entries and a #{quality.fetch("band")} discovery-quality band at score #{quality.fetch("score").to_i}."
abort("expected computed generated summary") unless body.include?(expected_summary)
abort("expected comparable workflow wording") unless body.include?("Source-backed comparable workflow evidence")

raw_texts = Array(research_frontmatter["claims"]).map { |claim| claim["text"].to_s.strip }
raw_texts += Array(research_frontmatter["inferences"]).map { |inference| inference["text"].to_s.strip }
raw_texts.reject(&:empty?).each do |raw_text|
  abort("generated competitor brief copied raw research text: #{raw_text}") if body.include?(raw_text)
end
RUBY
GENERATED_BRIEF_NEGATIVE_DIR="agentic/runs/$BOSS_IDEA_RUN/generated-brief-negatives"
mkdir -p "$GENERATED_BRIEF_NEGATIVE_DIR"
ruby - "agentic/runs/$BOSS_IDEA_RUN/generated-competitor-brief.md" "$GENERATED_BRIEF_NEGATIVE_DIR" <<'RUBY'
require File.expand_path("scripts/lib/boss_idea", Dir.pwd)

brief_path = ARGV.fetch(0)
dir = ARGV.fetch(1)
brief = File.read(brief_path)

File.write(File.join(dir, "missing-source-mapping-row.md"), brief.sub(/^\| [^|]+ \| c-summary-1 \| Executive Summary \|\n/, ""))
File.write(File.join(dir, "source-none.md"), brief.sub(/Source IDs: [^\n]+/, "Source IDs: none"))

frontmatter, body = BossIdea.load_markdown(brief_path)
frontmatter["recommendation_boundary"] = "This brief is evidence only and cannot approve implementation. This brief approves deployment."
File.write(File.join(dir, "boundary-approval.md"), frontmatter.to_yaml + "---\n" + body)
RUBY
if scripts/validate-boss-idea-competitor-brief.sh "$GENERATED_BRIEF_NEGATIVE_DIR/missing-source-mapping-row.md" >/tmp/h20-boss-generated-brief-missing-map.log 2>&1; then
  echo "expected generated competitor brief missing source mapping row to fail" >&2
  exit 1
fi
grep -q "missing from Source Mapping" /tmp/h20-boss-generated-brief-missing-map.log
if scripts/validate-boss-idea-competitor-brief.sh "$GENERATED_BRIEF_NEGATIVE_DIR/source-none.md" >/tmp/h20-boss-generated-brief-source-none.log 2>&1; then
  echo "expected generated competitor brief source none to fail" >&2
  exit 1
fi
grep -q "source_ids cannot allow" /tmp/h20-boss-generated-brief-source-none.log
if scripts/validate-boss-idea-competitor-brief.sh "$GENERATED_BRIEF_NEGATIVE_DIR/boundary-approval.md" >/tmp/h20-boss-generated-brief-boundary-approval.log 2>&1; then
  echo "expected generated competitor brief boundary approval to fail" >&2
  exit 1
fi
grep -q "forbidden authority" /tmp/h20-boss-generated-brief-boundary-approval.log
grep -q "boss_idea_competitor_brief" "agentic/runs/$BOSS_IDEA_RUN/manifest.yaml"
ruby -ryaml -e 'm=YAML.load_file(ARGV.fetch(0)); brief=m.fetch("boss_idea_competitor_brief"); abort("expected generated brief path") unless brief["artifact_path"].to_s.end_with?("generated-competitor-brief.md"); abort("expected research input") unless brief["market_research_path"].to_s.end_with?("market-research.md"); abort("expected quality input") unless brief["market_discovery_quality_path"].to_s.end_with?("market-discovery-quality.yaml"); abort("brief must not approve artifacts") unless m.fetch("artifacts").all? { |a| a["status"] == "planned" }' "agentic/runs/$BOSS_IDEA_RUN/manifest.yaml"
HERMES_COMPETITOR_BRIEF_FILE="hermes-competitor-brief.md"
HERMES_COMPETITOR_BRIEF="agentic/runs/$BOSS_IDEA_RUN/$HERMES_COMPETITOR_BRIEF_FILE"
scripts/run-hermes-action.sh --dry-run generate_boss_idea_competitor_brief run_id="$BOSS_IDEA_RUN" brief_file="$HERMES_COMPETITOR_BRIEF" >/tmp/h20-hermes-competitor-brief-dry-run.log
grep -q "scripts/generate-boss-idea-competitor-brief.sh" /tmp/h20-hermes-competitor-brief-dry-run.log
grep -q -- "--output $HERMES_COMPETITOR_BRIEF" /tmp/h20-hermes-competitor-brief-dry-run.log
if scripts/run-hermes-action.sh generate_boss_idea_competitor_brief run_id="$BOSS_IDEA_RUN" brief_file="$HERMES_COMPETITOR_BRIEF" actor=claude_code_cli role=code_reviewer >/tmp/h20-hermes-competitor-brief-unauthorized.log 2>&1; then
  echo "expected Hermes competitor brief generation with unauthorized identity to fail" >&2
  exit 1
fi
grep -q "authorization failed" /tmp/h20-hermes-competitor-brief-unauthorized.log
scripts/run-hermes-action.sh generate_boss_idea_competitor_brief run_id="$BOSS_IDEA_RUN" brief_file="$HERMES_COMPETITOR_BRIEF" actor=artifact_generator role=document_builder >/tmp/h20-hermes-competitor-brief-generate.log
grep -q "boss idea competitor brief generated" /tmp/h20-hermes-competitor-brief-generate.log
scripts/validate-boss-idea-competitor-brief.sh "$HERMES_COMPETITOR_BRIEF" >/dev/null
if scripts/run-hermes-action.sh validate_boss_idea_competitor_brief run_id="$BOSS_IDEA_RUN" brief_file="../../README.md" >/tmp/h20-hermes-competitor-brief-validate-path.log 2>&1; then
  echo "expected Hermes competitor brief validation outside run path to fail" >&2
  exit 1
fi
grep -q "invalid brief file path" /tmp/h20-hermes-competitor-brief-validate-path.log
if scripts/run-hermes-action.sh validate_boss_idea_competitor_brief run_id="." brief_file="$BOSS_IDEA_RUN/$HERMES_COMPETITOR_BRIEF_FILE" >/tmp/h20-hermes-competitor-brief-validate-dot-run.log 2>&1; then
  echo "expected Hermes competitor brief validation dot run id to fail" >&2
  exit 1
fi
grep -q "invalid run id" /tmp/h20-hermes-competitor-brief-validate-dot-run.log
ln -s "../../fixtures/boss-idea-response/valid-competitor-brief.md" "agentic/runs/$BOSS_IDEA_RUN/linked-competitor-brief.md"
if scripts/run-hermes-action.sh validate_boss_idea_competitor_brief run_id="$BOSS_IDEA_RUN" brief_file="linked-competitor-brief.md" >/tmp/h20-hermes-competitor-brief-validate-symlink.log 2>&1; then
  echo "expected Hermes competitor brief validation symlink escape to fail" >&2
  exit 1
fi
grep -q "symlink" /tmp/h20-hermes-competitor-brief-validate-symlink.log
mkdir -p "agentic/runs/$BOSS_IDEA_RUN/symlink-run-target"
cp "$HERMES_COMPETITOR_BRIEF" "agentic/runs/$BOSS_IDEA_RUN/symlink-run-target/brief.md"
ln -s "$BOSS_IDEA_RUN/symlink-run-target" "agentic/runs/$BOSS_IDEA_SYMLINK_RUN"
if scripts/run-hermes-action.sh validate_boss_idea_competitor_brief run_id="$BOSS_IDEA_SYMLINK_RUN" brief_file="brief.md" >/tmp/h20-hermes-competitor-brief-validate-run-symlink.log 2>&1; then
  echo "expected Hermes competitor brief validation symlinked run root to fail" >&2
  exit 1
fi
grep -q "run directory" /tmp/h20-hermes-competitor-brief-validate-run-symlink.log
rm -f "agentic/runs/$BOSS_IDEA_SYMLINK_RUN"
scripts/run-hermes-action.sh validate_boss_idea_competitor_brief run_id="$BOSS_IDEA_RUN" brief_file="$HERMES_COMPETITOR_BRIEF_FILE" >/tmp/h20-hermes-competitor-brief-validate.log
grep -q "boss idea competitor brief ok" /tmp/h20-hermes-competitor-brief-validate.log
ruby -ryaml -e 'm=YAML.load_file(ARGV.fetch(0)); brief=m.fetch("boss_idea_competitor_brief"); abort("expected Hermes generated brief path") unless brief["artifact_path"].to_s == ARGV.fetch(1); abort("Hermes brief generation must not approve artifacts") unless m.fetch("artifacts").all? { |a| a["status"] == "planned" }' "agentic/runs/$BOSS_IDEA_RUN/manifest.yaml" "$HERMES_COMPETITOR_BRIEF"
if scripts/generate-boss-idea-competitor-brief.sh --output "agentic/runs/$BOSS_IDEA_RUN/generated-competitor-brief.md" "$BOSS_IDEA_RUN" >/tmp/h20-boss-brief-existing-output.log 2>&1; then
  echo "expected competitor brief overwrite without force to fail" >&2
  exit 1
fi
grep -q "already exists" /tmp/h20-boss-brief-existing-output.log
scripts/generate-boss-idea-competitor-brief.sh --force --output "agentic/runs/$BOSS_IDEA_RUN/generated-competitor-brief.md" "$BOSS_IDEA_RUN" >/dev/null
if scripts/generate-boss-idea-competitor-brief.sh --output ../bad-competitor-brief.md "$BOSS_IDEA_RUN" >/tmp/h20-boss-brief-output-path.log 2>&1; then
  echo "expected competitor brief output outside run dir to fail" >&2
  exit 1
fi
grep -q "invalid output path" /tmp/h20-boss-brief-output-path.log
mkdir -p "agentic/runs/$BOSS_IDEA_RUN/brief-symlink-target"
ln -s "brief-symlink-target" "agentic/runs/$BOSS_IDEA_RUN/brief-symlink"
if scripts/generate-boss-idea-competitor-brief.sh --output "agentic/runs/$BOSS_IDEA_RUN/brief-symlink/escaped.md" "$BOSS_IDEA_RUN" >/tmp/h20-boss-brief-output-symlink.log 2>&1; then
  echo "expected competitor brief output through symlink to fail" >&2
  exit 1
fi
grep -q "symlink" /tmp/h20-boss-brief-output-symlink.log
if scripts/generate-boss-idea-competitor-brief.sh --force --output "agentic/runs/$BOSS_IDEA_RUN/manifest.yaml" "$BOSS_IDEA_RUN" >/tmp/h20-boss-brief-output-manifest.log 2>&1; then
  echo "expected competitor brief output over manifest to fail" >&2
  exit 1
fi
grep -q "reserved run artifact" /tmp/h20-boss-brief-output-manifest.log
if scripts/generate-boss-idea-competitor-brief.sh --force --output "agentic/runs/$BOSS_IDEA_RUN/manifest.yaml.tmp" "$BOSS_IDEA_RUN" >/tmp/h20-boss-brief-output-manifest-tmp.log 2>&1; then
  echo "expected competitor brief output over manifest temp path to fail" >&2
  exit 1
fi
grep -q "reserved run artifact" /tmp/h20-boss-brief-output-manifest-tmp.log
if scripts/generate-boss-idea-competitor-brief.sh --force --output "agentic/runs/$BOSS_IDEA_RUN/market-research.md" "$BOSS_IDEA_RUN" >/tmp/h20-boss-brief-output-research.log 2>&1; then
  echo "expected competitor brief output over research to fail" >&2
  exit 1
fi
grep -q "reserved run artifact" /tmp/h20-boss-brief-output-research.log
if scripts/generate-boss-idea-competitor-brief.sh --force --output "agentic/runs/$BOSS_IDEA_RUN/market-discovery-quality.yaml" "$BOSS_IDEA_RUN" >/tmp/h20-boss-brief-output-quality.log 2>&1; then
  echo "expected competitor brief output over quality to fail" >&2
  exit 1
fi
grep -q "reserved run artifact" /tmp/h20-boss-brief-output-quality.log
if scripts/generate-boss-idea-competitor-brief.sh --force --output "agentic/runs/$BOSS_IDEA_RUN/crawl4ai/raw/competitor-public-workflow.md" "$BOSS_IDEA_RUN" >/tmp/h20-boss-brief-output-raw.log 2>&1; then
  echo "expected competitor brief output under raw evidence directory to fail" >&2
  exit 1
fi
grep -q "reserved run evidence directory" /tmp/h20-boss-brief-output-raw.log
if scripts/generate-boss-idea-competitor-brief.sh --research "agentic/runs/$BOSS_IDEA_RUN/missing-research.md" --output "agentic/runs/$BOSS_IDEA_RUN/missing-source-brief.md" "$BOSS_IDEA_RUN" >/tmp/h20-boss-brief-missing-research.log 2>&1; then
  echo "expected competitor brief missing research to fail" >&2
  exit 1
fi
grep -q "blocked_missing_source" /tmp/h20-boss-brief-missing-research.log
ruby -ryaml -e 'q=YAML.load_file(ARGV.fetch(0)); q["run_id"] = "other-run"; File.write(ARGV.fetch(1), q.to_yaml)' "agentic/runs/$BOSS_IDEA_RUN/market-discovery-quality.yaml" "agentic/runs/$BOSS_IDEA_RUN/quality-wrong-run.yaml"
if scripts/generate-boss-idea-competitor-brief.sh --quality "agentic/runs/$BOSS_IDEA_RUN/quality-wrong-run.yaml" --output "agentic/runs/$BOSS_IDEA_RUN/wrong-quality-run-brief.md" "$BOSS_IDEA_RUN" >/tmp/h20-boss-brief-quality-run.log 2>&1; then
  echo "expected competitor brief mismatched quality run_id to fail" >&2
  exit 1
fi
grep -q "blocked_quality_run_mismatch" /tmp/h20-boss-brief-quality-run.log
cp "agentic/runs/$BOSS_IDEA_RUN/market-discovery-quality.yaml" "agentic/runs/$BOSS_IDEA_RUN/quality.tmp"
if scripts/generate-boss-idea-competitor-brief.sh --quality "agentic/runs/$BOSS_IDEA_RUN/quality.tmp" --output "agentic/runs/$BOSS_IDEA_RUN/quality" "$BOSS_IDEA_RUN" >/tmp/h20-boss-brief-output-temp-collision.log 2>&1; then
  echo "expected competitor brief temp output collision with quality input to fail" >&2
  exit 1
fi
grep -q "temp output path conflicts" /tmp/h20-boss-brief-output-temp-collision.log
ruby -ryaml -e 'q=YAML.load_file(ARGV.fetch(0)); q.delete("score"); File.write(ARGV.fetch(1), q.to_yaml)' "agentic/runs/$BOSS_IDEA_RUN/market-discovery-quality.yaml" "agentic/runs/$BOSS_IDEA_RUN/invalid-quality-missing-score.yaml"
if scripts/validate-boss-idea-market-discovery-quality.sh "agentic/runs/$BOSS_IDEA_RUN/invalid-quality-missing-score.yaml" >/tmp/h20-boss-market-quality-missing-score.log 2>&1; then
  echo "expected quality artifact missing score to fail" >&2
  exit 1
fi
grep -q "score is required" /tmp/h20-boss-market-quality-missing-score.log
ruby -ryaml -e 'q=YAML.load_file(ARGV.fetch(0)); q["score"] = 101; File.write(ARGV.fetch(1), q.to_yaml)' "agentic/runs/$BOSS_IDEA_RUN/market-discovery-quality.yaml" "agentic/runs/$BOSS_IDEA_RUN/invalid-quality-bad-score.yaml"
if scripts/validate-boss-idea-market-discovery-quality.sh "agentic/runs/$BOSS_IDEA_RUN/invalid-quality-bad-score.yaml" >/tmp/h20-boss-market-quality-bad-score.log 2>&1; then
  echo "expected quality artifact bad score to fail" >&2
  exit 1
fi
grep -q "score must be an integer" /tmp/h20-boss-market-quality-bad-score.log
ruby -ryaml -e 'q=YAML.load_file(ARGV.fetch(0)); q["band"] = "excellent"; File.write(ARGV.fetch(1), q.to_yaml)' "agentic/runs/$BOSS_IDEA_RUN/market-discovery-quality.yaml" "agentic/runs/$BOSS_IDEA_RUN/invalid-quality-bad-band.yaml"
if scripts/validate-boss-idea-market-discovery-quality.sh "agentic/runs/$BOSS_IDEA_RUN/invalid-quality-bad-band.yaml" >/tmp/h20-boss-market-quality-bad-band.log 2>&1; then
  echo "expected quality artifact bad band to fail" >&2
  exit 1
fi
grep -q "band is invalid" /tmp/h20-boss-market-quality-bad-band.log
ruby -ryaml -e 'q=YAML.load_file(ARGV.fetch(0)); q["no_paid_provider"] = "true"; File.write(ARGV.fetch(1), q.to_yaml)' "agentic/runs/$BOSS_IDEA_RUN/market-discovery-quality.yaml" "agentic/runs/$BOSS_IDEA_RUN/invalid-quality-bad-boolean.yaml"
if scripts/validate-boss-idea-market-discovery-quality.sh "agentic/runs/$BOSS_IDEA_RUN/invalid-quality-bad-boolean.yaml" >/tmp/h20-boss-market-quality-bad-boolean.log 2>&1; then
  echo "expected quality artifact bad boolean to fail" >&2
  exit 1
fi
grep -q "no_paid_provider must be boolean" /tmp/h20-boss-market-quality-bad-boolean.log
ruby -ryaml -e 'q=YAML.load_file(ARGV.fetch(0)); q["authority_note"] = "Quality score approves implementation."; File.write(ARGV.fetch(1), q.to_yaml)' "agentic/runs/$BOSS_IDEA_RUN/market-discovery-quality.yaml" "agentic/runs/$BOSS_IDEA_RUN/invalid-quality-authority.yaml"
if scripts/validate-boss-idea-market-discovery-quality.sh "agentic/runs/$BOSS_IDEA_RUN/invalid-quality-authority.yaml" >/tmp/h20-boss-market-quality-authority.log 2>&1; then
  echo "expected quality artifact authority note to fail" >&2
  exit 1
fi
grep -q "authority_note must state advisory-only authority" /tmp/h20-boss-market-quality-authority.log
ruby -ryaml -ruri -e 'seeds=YAML.load_file(ARGV.fetch(0)); hosts=%w[example.com example.org example.net iana.org]; seeds.fetch("candidates").each_with_index { |candidate, index| uri=URI.parse(candidate.fetch("url")); candidate["url"] = "https://#{hosts.fetch(index)}#{uri.path}" }; File.write(ARGV.fetch(1), seeds.to_yaml)' agentic/fixtures/boss-idea-response/market-crawl-seeds.yaml "agentic/runs/$BOSS_IDEA_RUN/clean-quality-seeds.yaml"
scripts/crawl-boss-idea-market.sh --force "$BOSS_IDEA_RUN" --seeds "agentic/runs/$BOSS_IDEA_RUN/clean-quality-seeds.yaml" --output "agentic/runs/$BOSS_IDEA_RUN/clean-quality-results.yaml" >/dev/null
scripts/validate-boss-idea-market-discovery-quality.sh "agentic/runs/$BOSS_IDEA_RUN/market-discovery-quality.yaml" >/dev/null
ruby -ryaml -e 'q=YAML.load_file(ARGV.fetch(0)); abort("expected empty evidence gaps to validate") unless q.fetch("evidence_gaps") == []; abort("expected diversified hosts") unless q.dig("checks", "unique_host_count").to_i >= 3' "agentic/runs/$BOSS_IDEA_RUN/market-discovery-quality.yaml"

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

python3 - <<'PY'
import importlib.util
spec = importlib.util.spec_from_file_location("boss_idea_crawl4ai", "scripts/lib/boss_idea_crawl4ai.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
payload = module.observed_network_payload("https://93.184.216.34/live-seed", "https://93.184.216.34/live-seed")
assert payload["requested_url"] == "https://93.184.216.34/live-seed"
assert payload["final_url"] == "https://93.184.216.34/live-seed"
assert payload["final_host"] == "93.184.216.34"
assert payload["observed_ips"] == ["93.184.216.34"]
assert payload["source"] == "dns"
PY

cat >"agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-helper.py" <<'PY'
#!/usr/bin/env python3
import json
import sys
from urllib.parse import urlparse
requested_url = sys.argv[sys.argv.index("--url") + 1]
final_host = urlparse(requested_url).hostname or "93.184.216.34"
print(json.dumps({
    "ok": True,
    "url": requested_url,
    "crawl4ai_version": "fake-crawl4ai",
    "markdown": "Remote page content about public research options.",
    "truncated": False,
    "observed_network": {
        "requested_url": requested_url,
        "final_url": requested_url,
        "final_host": final_host,
        "observed_ips": ["93.184.216.34"],
        "resolved_at": "2026-05-25T00:00:00Z",
        "source": "dns",
    },
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
scripts/validate-boss-idea-crawl-log.sh "agentic/runs/$BOSS_IDEA_RUN/crawl4ai/crawl-log.yaml" >/dev/null
scripts/validate-boss-idea-market-discovery-quality.sh "agentic/runs/$BOSS_IDEA_RUN/market-discovery-quality.yaml" >/dev/null
ruby -ryaml -e 'm=YAML.load_file(ARGV.fetch(0)); q=YAML.load_file(ARGV.fetch(1)); l=YAML.load_file(ARGV.fetch(2)); c=m.fetch("boss_idea_market_crawl"); e=l.fetch("entries").first; checks=q.fetch("checks"); abort("expected live_seed mode") unless c["mode"] == "live_seed"; abort("expected fake crawl4ai version") unless c["crawl4ai_version"] == "fake-crawl4ai"; abort("expected live crawl observed network") unless e.fetch("observed_network").fetch("observed_ips") == ["93.184.216.34"]; abort("expected quality observed count") unless checks["observed_network_entry_count"] == 1 && checks["live_success_missing_observed_network_count"] == 0; abort("expected manifest observed count") unless c["observed_network_entry_count"] == 1 && c["live_success_missing_observed_network_count"] == 0' "agentic/runs/$BOSS_IDEA_RUN/manifest.yaml" "agentic/runs/$BOSS_IDEA_RUN/market-discovery-quality.yaml" "agentic/runs/$BOSS_IDEA_RUN/crawl4ai/crawl-log.yaml"

cat >"agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-missing-observed.py" <<'PY'
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
chmod +x "agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-missing-observed.py"
if BOSS_IDEA_LIVE_CRAWL=1 BOSS_IDEA_CRAWL4AI_PYTHON=python3 BOSS_IDEA_CRAWL4AI_HELPER="agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-missing-observed.py" scripts/crawl-boss-idea-market.sh --live --force --results-only "$BOSS_IDEA_RUN" --seeds "agentic/runs/$BOSS_IDEA_RUN/valid-market-crawl-live-seed.yaml" --output "agentic/runs/$BOSS_IDEA_RUN/bad-live-seed-missing-observed.yaml" >/tmp/h20-boss-market-crawl-missing-observed-network.log 2>&1; then
  echo "expected Crawl4AI helper missing observed_network to fail" >&2
  exit 1
fi
grep -q "observed_network is required" /tmp/h20-boss-market-crawl-missing-observed-network.log

cat >"agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-invalid-observed-ip.py" <<'PY'
#!/usr/bin/env python3
import json
import sys
from urllib.parse import urlparse
requested_url = sys.argv[sys.argv.index("--url") + 1]
final_host = urlparse(requested_url).hostname or "93.184.216.34"
print(json.dumps({
    "ok": True,
    "url": requested_url,
    "crawl4ai_version": "fake-crawl4ai",
    "markdown": "Remote page content about public research options.",
    "truncated": False,
    "observed_network": {
        "requested_url": requested_url,
        "final_url": requested_url,
        "final_host": final_host,
        "observed_ips": ["not-an-ip"],
        "resolved_at": "2026-05-25T00:00:00Z",
        "source": "dns",
    },
}))
PY
chmod +x "agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-invalid-observed-ip.py"
if BOSS_IDEA_LIVE_CRAWL=1 BOSS_IDEA_CRAWL4AI_PYTHON=python3 BOSS_IDEA_CRAWL4AI_HELPER="agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-invalid-observed-ip.py" scripts/crawl-boss-idea-market.sh --live --force --results-only "$BOSS_IDEA_RUN" --seeds "agentic/runs/$BOSS_IDEA_RUN/valid-market-crawl-live-seed.yaml" --output "agentic/runs/$BOSS_IDEA_RUN/bad-live-seed-invalid-observed-ip.yaml" >/tmp/h20-boss-market-crawl-invalid-observed-ip.log 2>&1; then
  echo "expected Crawl4AI helper invalid observed IP to fail" >&2
  exit 1
fi
grep -q "invalid IP" /tmp/h20-boss-market-crawl-invalid-observed-ip.log

cat >"agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-prefix-observed-ip.py" <<'PY'
#!/usr/bin/env python3
import json
import os
import sys
from urllib.parse import urlparse
requested_url = sys.argv[sys.argv.index("--url") + 1]
final_host = urlparse(requested_url).hostname or "93.184.216.34"
print(json.dumps({
    "ok": True,
    "url": requested_url,
    "crawl4ai_version": "fake-crawl4ai",
    "markdown": "Remote page content about public research options.",
    "truncated": False,
    "observed_network": {
        "requested_url": requested_url,
        "final_url": requested_url,
        "final_host": final_host,
        "observed_ips": [os.environ["OBSERVED_IP"]],
        "resolved_at": "2026-05-25T00:00:00Z",
        "source": "dns",
    },
}))
PY
chmod +x "agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-prefix-observed-ip.py"
for observed_ip_prefix in "93.184.216.34/24" "2001:4860::1/64"; do
  if OBSERVED_IP="$observed_ip_prefix" BOSS_IDEA_LIVE_CRAWL=1 BOSS_IDEA_CRAWL4AI_PYTHON=python3 BOSS_IDEA_CRAWL4AI_HELPER="agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-prefix-observed-ip.py" scripts/crawl-boss-idea-market.sh --live --force --results-only "$BOSS_IDEA_RUN" --seeds "agentic/runs/$BOSS_IDEA_RUN/valid-market-crawl-live-seed.yaml" --output "agentic/runs/$BOSS_IDEA_RUN/bad-live-seed-prefix-observed-ip.yaml" >/tmp/h20-boss-market-crawl-prefix-observed-ip.log 2>&1; then
    echo "expected Crawl4AI helper prefix observed IP to fail: $observed_ip_prefix" >&2
    exit 1
  fi
  grep -q "invalid IP" /tmp/h20-boss-market-crawl-prefix-observed-ip.log
done

cat >"agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-blocked-observed-ip.py" <<'PY'
#!/usr/bin/env python3
import json
import sys
from urllib.parse import urlparse
requested_url = sys.argv[sys.argv.index("--url") + 1]
final_host = urlparse(requested_url).hostname or "93.184.216.34"
print(json.dumps({
    "ok": True,
    "url": requested_url,
    "crawl4ai_version": "fake-crawl4ai",
    "markdown": "Remote page content about public research options.",
    "truncated": False,
    "observed_network": {
        "requested_url": requested_url,
        "final_url": requested_url,
        "final_host": final_host,
        "observed_ips": ["100.64.0.1"],
        "resolved_at": "2026-05-25T00:00:00Z",
        "source": "dns",
    },
}))
PY
chmod +x "agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-blocked-observed-ip.py"
if BOSS_IDEA_LIVE_CRAWL=1 BOSS_IDEA_CRAWL4AI_PYTHON=python3 BOSS_IDEA_CRAWL4AI_HELPER="agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-blocked-observed-ip.py" scripts/crawl-boss-idea-market.sh --live --force --results-only "$BOSS_IDEA_RUN" --seeds "agentic/runs/$BOSS_IDEA_RUN/valid-market-crawl-live-seed.yaml" --output "agentic/runs/$BOSS_IDEA_RUN/bad-live-seed-blocked-observed-ip.yaml" >/tmp/h20-boss-market-crawl-blocked-observed-ip.log 2>&1; then
  echo "expected Crawl4AI helper blocked observed IP to fail" >&2
  exit 1
fi
grep -q "blocked IP" /tmp/h20-boss-market-crawl-blocked-observed-ip.log

cat >"agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-outside-final-host.py" <<'PY'
#!/usr/bin/env python3
import json
import sys
requested_url = sys.argv[sys.argv.index("--url") + 1]
print(json.dumps({
    "ok": True,
    "url": requested_url,
    "crawl4ai_version": "fake-crawl4ai",
    "markdown": "Remote page content about public research options.",
    "truncated": False,
    "observed_network": {
        "requested_url": requested_url,
        "final_url": "https://outside.example/live-seed",
        "final_host": "outside.example",
        "observed_ips": ["93.184.216.34"],
        "resolved_at": "2026-05-25T00:00:00Z",
        "source": "dns",
    },
}))
PY
chmod +x "agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-outside-final-host.py"
if BOSS_IDEA_LIVE_CRAWL=1 BOSS_IDEA_CRAWL4AI_PYTHON=python3 BOSS_IDEA_CRAWL4AI_HELPER="agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-outside-final-host.py" scripts/crawl-boss-idea-market.sh --live --force --results-only "$BOSS_IDEA_RUN" --seeds "agentic/runs/$BOSS_IDEA_RUN/valid-market-crawl-live-seed.yaml" --output "agentic/runs/$BOSS_IDEA_RUN/bad-live-seed-outside-final-host.yaml" >/tmp/h20-boss-market-crawl-outside-final-host.log 2>&1; then
  echo "expected Crawl4AI helper outside final host to fail" >&2
  exit 1
fi
grep -q "final_host is not in per-run allowlist" /tmp/h20-boss-market-crawl-outside-final-host.log

cat >"agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-observed-ip-mismatch.py" <<'PY'
#!/usr/bin/env python3
import json
import sys
from urllib.parse import urlparse
requested_url = sys.argv[sys.argv.index("--url") + 1]
final_host = urlparse(requested_url).hostname or "93.184.216.34"
print(json.dumps({
    "ok": True,
    "url": requested_url,
    "crawl4ai_version": "fake-crawl4ai",
    "markdown": "Remote page content about public research options.",
    "truncated": False,
    "observed_network": {
        "requested_url": requested_url,
        "final_url": requested_url,
        "final_host": final_host,
        "observed_ips": ["8.8.8.8"],
        "resolved_at": "2026-05-25T00:00:00Z",
        "source": "dns",
    },
}))
PY
chmod +x "agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-observed-ip-mismatch.py"
if BOSS_IDEA_LIVE_CRAWL=1 BOSS_IDEA_CRAWL4AI_PYTHON=python3 BOSS_IDEA_CRAWL4AI_HELPER="agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-observed-ip-mismatch.py" scripts/crawl-boss-idea-market.sh --live --force --results-only "$BOSS_IDEA_RUN" --seeds "agentic/runs/$BOSS_IDEA_RUN/valid-market-crawl-live-seed.yaml" --output "agentic/runs/$BOSS_IDEA_RUN/bad-live-seed-observed-ip-mismatch.yaml" >/tmp/h20-boss-market-crawl-observed-ip-mismatch.log 2>&1; then
  echo "expected Crawl4AI helper observed IP mismatch to fail" >&2
  exit 1
fi
grep -q "do not match final host DNS" /tmp/h20-boss-market-crawl-observed-ip-mismatch.log

cat >"agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-private-final-url.py" <<'PY'
#!/usr/bin/env python3
import json
import sys
requested_url = sys.argv[sys.argv.index("--url") + 1]
print(json.dumps({
    "ok": True,
    "url": requested_url,
    "crawl4ai_version": "fake-crawl4ai",
    "markdown": "Remote page content about public research options.",
    "truncated": False,
    "observed_network": {
        "requested_url": requested_url,
        "final_url": "http://10.0.0.1/private",
        "final_host": "10.0.0.1",
        "observed_ips": ["10.0.0.1"],
        "resolved_at": "2026-05-25T00:00:00Z",
        "source": "dns",
    },
}))
PY
chmod +x "agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-private-final-url.py"
if BOSS_IDEA_LIVE_CRAWL=1 BOSS_IDEA_CRAWL4AI_PYTHON=python3 BOSS_IDEA_CRAWL4AI_HELPER="agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-private-final-url.py" scripts/crawl-boss-idea-market.sh --live --force --results-only "$BOSS_IDEA_RUN" --seeds "agentic/runs/$BOSS_IDEA_RUN/valid-market-crawl-live-seed.yaml" --output "agentic/runs/$BOSS_IDEA_RUN/bad-live-seed-private-final-url.yaml" >/tmp/h20-boss-market-crawl-private-final-url.log 2>&1; then
  echo "expected Crawl4AI helper private final URL to fail" >&2
  exit 1
fi
grep -q "blocked IP" /tmp/h20-boss-market-crawl-private-final-url.log

cat >"agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-final-host-mismatch.py" <<'PY'
#!/usr/bin/env python3
import json
import sys
requested_url = sys.argv[sys.argv.index("--url") + 1]
print(json.dumps({
    "ok": True,
    "url": requested_url,
    "crawl4ai_version": "fake-crawl4ai",
    "markdown": "Remote page content about public research options.",
    "truncated": False,
    "observed_network": {
        "requested_url": requested_url,
        "final_url": requested_url,
        "final_host": "93.184.216.35",
        "observed_ips": ["93.184.216.34"],
        "resolved_at": "2026-05-25T00:00:00Z",
        "source": "dns",
    },
}))
PY
chmod +x "agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-final-host-mismatch.py"
if BOSS_IDEA_LIVE_CRAWL=1 BOSS_IDEA_CRAWL4AI_PYTHON=python3 BOSS_IDEA_CRAWL4AI_HELPER="agentic/runs/$BOSS_IDEA_RUN/fake-crawl4ai-final-host-mismatch.py" scripts/crawl-boss-idea-market.sh --live --force --results-only "$BOSS_IDEA_RUN" --seeds "agentic/runs/$BOSS_IDEA_RUN/valid-market-crawl-live-seed.yaml" --output "agentic/runs/$BOSS_IDEA_RUN/bad-live-seed-final-host-mismatch.yaml" >/tmp/h20-boss-market-crawl-final-host-mismatch.log 2>&1; then
  echo "expected Crawl4AI helper final host mismatch to fail" >&2
  exit 1
fi
grep -q "final_host must match final_url host" /tmp/h20-boss-market-crawl-final-host-mismatch.log

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

echo "fixture: boss idea SearXNG preflight"
if BOSS_IDEA_SEARCH_SEARXNG_ENDPOINT_LABEL=local-searxng BOSS_IDEA_SEARCH_SEARXNG_NO_PAID_ENGINES=1 scripts/boss-idea-searxng-preflight.sh --evidence "agentic/runs/$BOSS_IDEA_RUN/searxng-preflight-missing-base.yaml" >/tmp/h20-boss-searxng-preflight-missing-base.log 2>&1; then
  echo "expected SearXNG preflight without base URL to fail" >&2
  exit 1
fi
grep -q "missing BOSS_IDEA_SEARCH_SEARXNG_BASE_URL" /tmp/h20-boss-searxng-preflight-missing-base.log
test -f "agentic/runs/$BOSS_IDEA_RUN/searxng-preflight-missing-base.yaml"

if BOSS_IDEA_SEARCH_SEARXNG_BASE_URL=http://127.0.0.1:9/search BOSS_IDEA_SEARCH_SEARXNG_ENDPOINT_LABEL=local-searxng scripts/boss-idea-searxng-preflight.sh --evidence "agentic/runs/$BOSS_IDEA_RUN/searxng-preflight-missing-policy.yaml" >/tmp/h20-boss-searxng-preflight-missing-policy.log 2>&1; then
  echo "expected SearXNG preflight without no-paid policy to fail" >&2
  exit 1
fi
grep -q "BOSS_IDEA_SEARCH_SEARXNG_NO_PAID_ENGINES=1" /tmp/h20-boss-searxng-preflight-missing-policy.log

if BOSS_IDEA_SEARCH_SEARXNG_BASE_URL="https://operator:privatevalue@example.com/search" BOSS_IDEA_SEARCH_SEARXNG_ENDPOINT_LABEL=local-searxng BOSS_IDEA_SEARCH_SEARXNG_NO_PAID_ENGINES=1 scripts/boss-idea-searxng-preflight.sh --evidence "agentic/runs/$BOSS_IDEA_RUN/searxng-preflight-redacted-userinfo.yaml" >/tmp/h20-boss-searxng-preflight-redacted-userinfo.log 2>&1; then
  echo "expected SearXNG preflight URL credentials to fail" >&2
  exit 1
fi
grep -q "redacted@example.com" /tmp/h20-boss-searxng-preflight-redacted-userinfo.log
if grep -q "privatevalue" /tmp/h20-boss-searxng-preflight-redacted-userinfo.log "agentic/runs/$BOSS_IDEA_RUN/searxng-preflight-redacted-userinfo.yaml"; then
  echo "expected SearXNG preflight output and evidence to redact URL userinfo" >&2
  exit 1
fi

if BOSS_IDEA_SEARCH_SEARXNG_BASE_URL="https://example.com/search?refresh_token=rawvalue" BOSS_IDEA_SEARCH_SEARXNG_ENDPOINT_LABEL=local-searxng BOSS_IDEA_SEARCH_SEARXNG_NO_PAID_ENGINES=1 scripts/boss-idea-searxng-preflight.sh --evidence "agentic/runs/$BOSS_IDEA_RUN/searxng-preflight-redacted-query.yaml" >/tmp/h20-boss-searxng-preflight-redacted-query.log 2>&1; then
  echo "expected SearXNG preflight query credentials to fail" >&2
  exit 1
fi
grep -q "refresh_token=%3Credacted%3E" /tmp/h20-boss-searxng-preflight-redacted-query.log
if grep -q "rawvalue" /tmp/h20-boss-searxng-preflight-redacted-query.log "agentic/runs/$BOSS_IDEA_RUN/searxng-preflight-redacted-query.yaml"; then
  echo "expected SearXNG preflight output and evidence to redact query credentials" >&2
  exit 1
fi

SEARXNG_PREFLIGHT_JSON_PORT="agentic/runs/$BOSS_IDEA_RUN/searxng-preflight-json.port"
ruby -rwebrick -e 'port_file=ARGV.fetch(0); server=WEBrick::HTTPServer.new(Port: 0, BindAddress: "127.0.0.1", Logger: WEBrick::Log.new(File::NULL), AccessLog: []); File.write(port_file, server.config[:Port]); trap("TERM") { server.shutdown }; server.mount_proc("/search") { |req, res| res["Content-Type"] = "application/json"; res.body = req.query["q"].to_s == "missing-results" ? "{\"ok\":true}" : "{\"results\":[]}" }; server.start' "$SEARXNG_PREFLIGHT_JSON_PORT" &
SEARXNG_PREFLIGHT_JSON_PID=$!
for _ in 1 2 3 4 5; do
  test -s "$SEARXNG_PREFLIGHT_JSON_PORT" && break
  sleep 1
done
SEARXNG_PREFLIGHT_JSON_PORT_VALUE="$(cat "$SEARXNG_PREFLIGHT_JSON_PORT")"
BOSS_IDEA_SEARCH_SEARXNG_BASE_URL="http://127.0.0.1:${SEARXNG_PREFLIGHT_JSON_PORT_VALUE}" BOSS_IDEA_SEARCH_SEARXNG_ENDPOINT_LABEL=local-searxng BOSS_IDEA_SEARCH_SEARXNG_NO_PAID_ENGINES=1 scripts/boss-idea-searxng-preflight.sh --evidence "agentic/runs/$BOSS_IDEA_RUN/searxng-preflight.yaml" >/tmp/h20-boss-searxng-preflight-ok.log
grep -q "searxng preflight ok" /tmp/h20-boss-searxng-preflight-ok.log
ruby -ryaml -e 'e=YAML.load_file(ARGV.fetch(0)); abort("expected preflight pass") unless e["status"] == "passed"; abort("expected advisory note") unless e.fetch("authority_note").include?("cannot approve"); abort("raw response must not be recorded") unless e["raw_response_recorded"] == false; abort("expected redacted probe") unless e["probe_url"].include?("%3Credacted-probe%3E")' "agentic/runs/$BOSS_IDEA_RUN/searxng-preflight.yaml"
if BOSS_IDEA_SEARCH_SEARXNG_BASE_URL="http://127.0.0.1:${SEARXNG_PREFLIGHT_JSON_PORT_VALUE}" BOSS_IDEA_SEARCH_SEARXNG_ENDPOINT_LABEL=local-searxng BOSS_IDEA_SEARCH_SEARXNG_NO_PAID_ENGINES=1 scripts/boss-idea-searxng-preflight.sh --probe missing-results --evidence "agentic/runs/$BOSS_IDEA_RUN/searxng-preflight-missing-results.yaml" >/tmp/h20-boss-searxng-preflight-missing-results.log 2>&1; then
  echo "expected SearXNG preflight JSON without results array to fail" >&2
  kill "$SEARXNG_PREFLIGHT_JSON_PID" 2>/dev/null || true
  wait "$SEARXNG_PREFLIGHT_JSON_PID" 2>/dev/null || true
  exit 1
fi
grep -q "missing results array" /tmp/h20-boss-searxng-preflight-missing-results.log
kill "$SEARXNG_PREFLIGHT_JSON_PID" 2>/dev/null || true
wait "$SEARXNG_PREFLIGHT_JSON_PID" 2>/dev/null || true
unset SEARXNG_PREFLIGHT_JSON_PID

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
if BOSS_IDEA_SEARCH_SEARXNG_BASE_URL="http://127.0.0.1:${SEARXNG_BAD_CONTENT_TYPE_PORT_VALUE}/search" BOSS_IDEA_SEARCH_SEARXNG_ENDPOINT_LABEL=local-searxng BOSS_IDEA_SEARCH_SEARXNG_NO_PAID_ENGINES=1 scripts/boss-idea-searxng-preflight.sh --evidence "agentic/runs/$BOSS_IDEA_RUN/searxng-preflight-non-json.yaml" >/tmp/h20-boss-searxng-preflight-non-json.log 2>&1; then
  echo "expected SearXNG preflight non-JSON response to fail" >&2
  kill "$SEARXNG_BAD_CONTENT_TYPE_PID" 2>/dev/null || true
  wait "$SEARXNG_BAD_CONTENT_TYPE_PID" 2>/dev/null || true
  exit 1
fi
grep -q "non-JSON content type" /tmp/h20-boss-searxng-preflight-non-json.log
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

echo "fixture: boss idea live smoke wrapper"
RUN_ID="$BOSS_LIVE_SMOKE_RUN" scripts/init-boss-idea-run.sh agentic/fixtures/boss-idea-response/valid-idea.md >/dev/null
if scripts/run-boss-idea-live-smoke.sh --summary "agentic/reviews/boss-idea-response/live-smoke/$BOSS_LIVE_SMOKE_RUN/no-live.yaml" "$BOSS_LIVE_SMOKE_RUN" >/tmp/h20-boss-live-smoke-no-live.log 2>&1; then
  echo "expected live smoke without --live to fail" >&2
  exit 1
fi
grep -q "phase=live_gate" /tmp/h20-boss-live-smoke-no-live.log
ruby -ryaml -e 's=YAML.load_file(ARGV.fetch(0)); abort("expected live gate failure") unless s["failed_phase"] == "live_gate"; abort("preflight must not run") unless s.dig("phases", "preflight", "status") == "not_run"' "agentic/reviews/boss-idea-response/live-smoke/$BOSS_LIVE_SMOKE_RUN/no-live.yaml"

if env -u BOSS_IDEA_LIVE_CRAWL scripts/run-boss-idea-live-smoke.sh --live --summary "agentic/reviews/boss-idea-response/live-smoke/$BOSS_LIVE_SMOKE_RUN/live-no-env.yaml" "$BOSS_LIVE_SMOKE_RUN" >/tmp/h20-boss-live-smoke-live-no-env.log 2>&1; then
  echo "expected live smoke with --live but without live env to fail" >&2
  exit 1
fi
grep -q "phase=live_gate" /tmp/h20-boss-live-smoke-live-no-env.log
grep -q "BOSS_IDEA_LIVE_CRAWL=1" /tmp/h20-boss-live-smoke-live-no-env.log
ruby -ryaml -e 's=YAML.load_file(ARGV.fetch(0)); abort("expected live env gate failure") unless s["failed_phase"] == "live_gate"; abort("preflight must not run") unless s.dig("phases", "preflight", "status") == "not_run"' "agentic/reviews/boss-idea-response/live-smoke/$BOSS_LIVE_SMOKE_RUN/live-no-env.yaml"

if BOSS_IDEA_LIVE_CRAWL=1 scripts/run-boss-idea-live-smoke.sh --live --search-provider fixture --summary "agentic/reviews/boss-idea-response/live-smoke/$BOSS_LIVE_SMOKE_RUN/fixture-provider.yaml" "$BOSS_LIVE_SMOKE_RUN" >/tmp/h20-boss-live-smoke-fixture-provider.log 2>&1; then
  echo "expected live smoke fixture provider to fail" >&2
  exit 1
fi
grep -q "phase=provider_gate" /tmp/h20-boss-live-smoke-fixture-provider.log
grep -q "fixture provider" /tmp/h20-boss-live-smoke-fixture-provider.log

if BOSS_IDEA_LIVE_CRAWL=1 BOSS_IDEA_SEARCH_SEARXNG_FIXTURE=agentic/fixtures/boss-idea-response/searxng-search-fixture.json scripts/run-boss-idea-live-smoke.sh --live --summary "agentic/reviews/boss-idea-response/live-smoke/$BOSS_LIVE_SMOKE_RUN/searxng-fixture-env.yaml" "$BOSS_LIVE_SMOKE_RUN" >/tmp/h20-boss-live-smoke-searxng-fixture-env.log 2>&1; then
  echo "expected live smoke SearXNG fixture env to fail" >&2
  exit 1
fi
grep -q "phase=provider_gate" /tmp/h20-boss-live-smoke-searxng-fixture-env.log
grep -q "BOSS_IDEA_SEARCH_SEARXNG_FIXTURE" /tmp/h20-boss-live-smoke-searxng-fixture-env.log
ruby -ryaml -e 's=YAML.load_file(ARGV.fetch(0)); abort("expected provider gate failure") unless s["failed_phase"] == "provider_gate"; abort("preflight must not run") unless s.dig("phases", "preflight", "status") == "not_run"; abort("market discovery must not run") unless s.dig("phases", "market_discovery", "status") == "not_run"' "agentic/reviews/boss-idea-response/live-smoke/$BOSS_LIVE_SMOKE_RUN/searxng-fixture-env.yaml"

if BOSS_IDEA_LIVE_CRAWL=1 BOSS_IDEA_SEARCH_SEARXNG_ENDPOINT_LABEL=local-searxng BOSS_IDEA_SEARCH_SEARXNG_NO_PAID_ENGINES=1 scripts/run-boss-idea-live-smoke.sh --live --force --summary "agentic/reviews/boss-idea-response/live-smoke/$BOSS_LIVE_SMOKE_RUN/preflight-failure.yaml" "$BOSS_LIVE_SMOKE_RUN" >/tmp/h20-boss-live-smoke-preflight-failure.log 2>&1; then
  echo "expected live smoke preflight failure to stop the run" >&2
  exit 1
fi
grep -q "phase=preflight" /tmp/h20-boss-live-smoke-preflight-failure.log
test ! -f "agentic/runs/$BOSS_LIVE_SMOKE_RUN/market-search-results.yaml"
ruby -ryaml -e 's=YAML.load_file(ARGV.fetch(0)); abort("expected preflight failure") unless s["failed_phase"] == "preflight"; abort("market discovery must not run") unless s.dig("phases", "market_discovery", "status") == "not_run"' "agentic/reviews/boss-idea-response/live-smoke/$BOSS_LIVE_SMOKE_RUN/preflight-failure.yaml"

cat >"agentic/runs/$BOSS_LIVE_SMOKE_RUN/live-smoke-searxng-server.rb" <<'RUBY'
require "json"
require "webrick"

port_file = ARGV.fetch(0)
pages = {
  "competitor" => [
    "Competitor workflow",
    "https://example.com/competitor-workflow",
    "agentic/fixtures/boss-idea-response/market-crawl-pages/competitor-workflow.html"
  ],
  "mainstream" => [
    "Mainstream practices",
    "https://example.org/mainstream-practices",
    "agentic/fixtures/boss-idea-response/market-crawl-pages/mainstream-practices.html"
  ],
  "implementation" => [
    "Implementation patterns",
    "https://example.net/implementation-patterns",
    "agentic/fixtures/boss-idea-response/market-crawl-pages/implementation-patterns.html"
  ],
  "operator" => [
    "Operator workflow",
    "https://iana.org/operator-workflow",
    "agentic/fixtures/boss-idea-response/market-crawl-pages/operator-workflow.html"
  ]
}

server = WEBrick::HTTPServer.new(Port: 0, BindAddress: "127.0.0.1", Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
File.write(port_file, server.config[:Port])
trap("TERM") { server.shutdown }
server.mount_proc("/search") do |req, res|
  query = req.query["q"].to_s.downcase
  key = if query.include?("mainstream")
    "mainstream"
  elsif query.include?("implementation")
    "implementation"
  elsif query.include?("workflow") || query.include?("operator")
    "operator"
  else
    "competitor"
  end
  title, url, content_path = pages.fetch(key)
  res["Content-Type"] = "application/json"
  res.body = JSON.generate(
    "no_paid_engine_policy" => "operator-confirmed",
    "results" => [
      {
        "url" => url,
        "title" => title,
        "content" => "Public source snippet for #{title}.",
        "content_path" => content_path,
        "resolved_ips" => ["93.184.216.34"]
      }
    ]
  )
end
server.start
RUBY
LIVE_SMOKE_SEARXNG_PORT="agentic/runs/$BOSS_LIVE_SMOKE_RUN/live-smoke-searxng.port"
ruby "agentic/runs/$BOSS_LIVE_SMOKE_RUN/live-smoke-searxng-server.rb" "$LIVE_SMOKE_SEARXNG_PORT" &
LIVE_SMOKE_SEARXNG_PID=$!
for _ in 1 2 3 4 5; do
  test -s "$LIVE_SMOKE_SEARXNG_PORT" && break
  sleep 1
done
LIVE_SMOKE_SEARXNG_PORT_VALUE="$(cat "$LIVE_SMOKE_SEARXNG_PORT")"
BOSS_IDEA_LIVE_CRAWL=1 BOSS_IDEA_SEARCH_SEARXNG_BASE_URL="http://127.0.0.1:${LIVE_SMOKE_SEARXNG_PORT_VALUE}/search" BOSS_IDEA_SEARCH_SEARXNG_ENDPOINT_LABEL=local-searxng BOSS_IDEA_SEARCH_SEARXNG_NO_PAID_ENGINES=1 scripts/run-boss-idea-live-smoke.sh --live --force --summary "agentic/reviews/boss-idea-response/live-smoke/$BOSS_LIVE_SMOKE_RUN/summary.yaml" "$BOSS_LIVE_SMOKE_RUN" >/tmp/h20-boss-live-smoke-ok.log
grep -q "boss idea live smoke ok" /tmp/h20-boss-live-smoke-ok.log
git check-ignore -q "agentic/reviews/boss-idea-response/live-smoke/$BOSS_LIVE_SMOKE_RUN/summary.yaml"
ruby -ryaml -e 's=YAML.load_file(ARGV.fetch(0)); abort("expected live smoke pass") unless s["status"] == "passed"; %w[live_gate provider_gate preflight market_discovery quality_validation research_validation].each { |p| abort("phase #{p} did not pass") unless s.dig("phases", p, "status") == "passed" }; abort("raw provider response must not be recorded") unless s["raw_provider_response_recorded"] == false; abort("raw page body must not be recorded") unless s["raw_page_body_recorded"] == false; abort("summary must be advisory") unless s.fetch("authority_note").include?("cannot approve"); abort("expected searxng quality") unless s.dig("quality", "provider") == "searxng" && s.dig("quality", "mode") == "searxng"' "agentic/reviews/boss-idea-response/live-smoke/$BOSS_LIVE_SMOKE_RUN/summary.yaml"
scripts/validate-boss-idea-research.sh "agentic/runs/$BOSS_LIVE_SMOKE_RUN/market-research.md" >/dev/null
scripts/validate-boss-idea-market-discovery-quality.sh "agentic/runs/$BOSS_LIVE_SMOKE_RUN/market-discovery-quality.yaml" >/dev/null
kill "$LIVE_SMOKE_SEARXNG_PID" 2>/dev/null || true
wait "$LIVE_SMOKE_SEARXNG_PID" 2>/dev/null || true
unset LIVE_SMOKE_SEARXNG_PID

BOSS_IDEA_SEARCH_SEARXNG_FIXTURE=agentic/fixtures/boss-idea-response/searxng-search-fixture.json scripts/crawl-boss-idea-market.sh --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider searxng --output "agentic/runs/$BOSS_IDEA_RUN/searxng-results.yaml" >/dev/null
scripts/validate-boss-idea-research.sh "agentic/runs/$BOSS_IDEA_RUN/market-research.md" >/dev/null
scripts/validate-boss-idea-market-discovery-quality.sh "agentic/runs/$BOSS_IDEA_RUN/market-discovery-quality.yaml" >/dev/null
ruby -ryaml -e 'm=YAML.load_file(ARGV.fetch(0)); c=m.fetch("boss_idea_market_crawl"); abort("expected searxng provider") unless c["provider"] == "searxng"; abort("expected fixture mode") unless c["mode"] == "fixture"; abort("expected no-paid provider") unless c["no_paid_provider"] == true; abort("expected provider priority") unless c["provider_priority"].to_i == 1; abort("expected searxng source count") unless c["source_count"].to_i >= 4' "agentic/runs/$BOSS_IDEA_RUN/manifest.yaml"
ruby -ryaml -e 'q=YAML.load_file(ARGV.fetch(0)); abort("expected searxng quality") unless q["provider"] == "searxng"; abort("expected searxng quality priority") unless q["provider_priority"].to_i == 1; abort("expected no-paid quality") unless q["no_paid_provider"] == true; abort("expected strong quality") unless q["score"].to_i >= 80 && q["band"] == "strong"; abort("quality must stay advisory") unless q["authority_note"].include?("cannot approve")' "agentic/runs/$BOSS_IDEA_RUN/market-discovery-quality.yaml"
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
scripts/validate-boss-idea-market-discovery-quality.sh "agentic/runs/$BOSS_IDEA_RUN/market-discovery-quality.yaml" >/dev/null
ruby -ryaml -e 'm=YAML.load_file(ARGV.fetch(0)); c=m.fetch("boss_idea_market_crawl"); abort("expected duckduckgo provider") unless c["provider"] == "duckduckgo_html"; abort("expected fixture mode") unless c["mode"] == "fixture"; abort("expected no-paid provider") unless c["no_paid_provider"] == true; abort("expected provider priority") unless c["provider_priority"].to_i == 2' "agentic/runs/$BOSS_IDEA_RUN/manifest.yaml"
ruby -ryaml -e 'q=YAML.load_file(ARGV.fetch(0)); abort("expected duckduckgo quality") unless q["provider"] == "duckduckgo_html"; abort("expected lower-trust quality count") unless q.dig("checks", "lower_trust_fallback_count").to_i.positive?; abort("expected lower-trust gap") unless q.fetch("evidence_gaps").include?("lower_trust_fallback_used")' "agentic/runs/$BOSS_IDEA_RUN/market-discovery-quality.yaml"
ruby -ryaml -e 'c=YAML.load_file(ARGV.fetch(0)); abort("expected lower-trust fallback metadata") unless c.fetch("candidates").all? { |x| x.dig("provider_metadata", "lower_trust_fallback") == true && x.dig("provider_metadata", "fallback_from") == "searxng" }' "agentic/runs/$BOSS_IDEA_RUN/market-candidate-urls.yaml"
scripts/validate-boss-idea-provider-health-events.sh "agentic/runs/$BOSS_IDEA_RUN/provider-health-events.yaml" >/dev/null
ruby -ryaml -e 'e=YAML.load_file(ARGV.fetch(0)); abort("expected duckduckgo provider health events") unless e["provider"] == "duckduckgo_html"; abort("expected provider success event") unless e.dig("event_counts", "provider_success_count") == 1; abort("expected lower-trust fallback event count") unless e.dig("event_counts", "fallback_used_count").to_i.positive?; abort("expected event path in manifest") unless YAML.load_file(ARGV.fetch(1)).dig("boss_idea_market_crawl", "provider_health_events_path").to_s.end_with?("provider-health-events.yaml")' "agentic/runs/$BOSS_IDEA_RUN/provider-health-events.yaml" "agentic/runs/$BOSS_IDEA_RUN/manifest.yaml"

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
scripts/validate-boss-idea-provider-health-events.sh "agentic/runs/$BOSS_IDEA_RUN/provider-health-events.yaml" >/dev/null
ruby -ryaml -e 'e=YAML.load_file(ARGV.fetch(0)); abort("expected failed duckduckgo provider health events") unless e["provider"] == "duckduckgo_html"; abort("expected provider failure event") unless e.dig("event_counts", "provider_failure_count") == 1; abort("expected challenge/captcha event") unless e.dig("event_counts", "challenge_or_captcha_count") == 1; abort("expected fallback used event") unless e.dig("event_counts", "fallback_used_count") == 1' "agentic/runs/$BOSS_IDEA_RUN/provider-health-events.yaml"
scripts/summarize-boss-idea-provider-health.sh --output "agentic/runs/$BOSS_IDEA_RUN/provider-health.yaml" "$BOSS_IDEA_RUN" >/dev/null
scripts/validate-boss-idea-provider-health.sh "agentic/runs/$BOSS_IDEA_RUN/provider-health.yaml" >/dev/null
ruby -ryaml -e 'h=YAML.load_file(ARGV.fetch(0)); p=h.fetch("providers").find { |provider| provider["provider"] == "duckduckgo_html" }; abort("missing duckduckgo provider summary") unless p; abort("expected challenge/captcha summary") unless p.dig("counters", "challenge_or_captcha_count") == 1 && h.dig("summary", "total_challenge_or_captcha_count") == 1; abort("expected fallback reason summary") unless p.fetch("fallback_reasons").any? { |r| r["reason"] == "operator_selected" && r["count"] == 1 }; abort("provider health summary must remain advisory") unless h.dig("summary", "advisory_only") == true' "agentic/runs/$BOSS_IDEA_RUN/provider-health.yaml"
if scripts/summarize-boss-idea-provider-health.sh --output "agentic/runs/$BOSS_IDEA_RUN/missing-provider-health.yaml" "${RUN_PREFIX}-missing-provider-health-events" >/tmp/h20-boss-provider-health-summary-missing.log 2>&1; then
  echo "expected provider health summary missing events to fail" >&2
  exit 1
fi
grep -q "provider health events not found" /tmp/h20-boss-provider-health-summary-missing.log

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
scripts/validate-boss-idea-market-discovery-quality.sh "agentic/runs/$BOSS_IDEA_RUN/market-discovery-quality.yaml" >/dev/null
ruby -ryaml -e 'm=YAML.load_file(ARGV.fetch(0)); c=m.fetch("boss_idea_market_crawl"); abort("expected local browser provider") unless c["provider"] == "local_browser_search"; abort("expected fixture mode") unless c["mode"] == "fixture"; abort("expected no-paid provider") unless c["no_paid_provider"] == true; abort("expected provider priority") unless c["provider_priority"].to_i == 3' "agentic/runs/$BOSS_IDEA_RUN/manifest.yaml"
ruby -ryaml -e 'q=YAML.load_file(ARGV.fetch(0)); abort("expected local browser quality") unless q["provider"] == "local_browser_search"; abort("expected local browser priority") unless q["provider_priority"].to_i == 3; abort("expected lower-trust quality count") unless q.dig("checks", "lower_trust_fallback_count").to_i.positive?' "agentic/runs/$BOSS_IDEA_RUN/market-discovery-quality.yaml"

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
cat >"agentic/runs/$BOSS_IDEA_RUN/local-browser-challenge-helper.py" <<'PY'
#!/usr/bin/env python3
import json
import sys
print(json.dumps({"ok": False, "error": "local browser search challenge detected"}), file=sys.stderr)
sys.exit(4)
PY
chmod +x "agentic/runs/$BOSS_IDEA_RUN/local-browser-challenge-helper.py"
if BOSS_IDEA_LIVE_CRAWL=1 BOSS_IDEA_SEARCH_LOCAL_BROWSER_SEARCH_URL=https://93.184.216.34/search BOSS_IDEA_SEARCH_LOCAL_BROWSER_HELPER="agentic/runs/$BOSS_IDEA_RUN/local-browser-challenge-helper.py" scripts/crawl-boss-idea-market.sh --live --force "$BOSS_IDEA_RUN" --from-query-pack --search-provider local_browser_search --output "agentic/runs/$BOSS_IDEA_RUN/bad-local-browser-challenge-results.yaml" >/tmp/h20-boss-market-crawl-local-browser-challenge.log 2>&1; then
  echo "expected local browser challenge helper to fail" >&2
  exit 1
fi
grep -q "local browser search challenge detected" /tmp/h20-boss-market-crawl-local-browser-challenge.log

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
if scripts/record-boss-idea-decision.sh agentic/fixtures/boss-idea-response/valid-no-go-decision.yaml --run-id "$BOSS_DECISION_RUN" --actor codex_cli_staff_reviewer --role code_reviewer >/tmp/h20-boss-decision-auth.log 2>&1; then
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
