#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/summarize-boss-idea-provider-health.sh --output <provider-health.yaml> <run-id> [<run-id>...]

Builds a public-safe provider health summary from ignored provider-health event
logs. The command does not recommend or approve provider changes.
USAGE
}

OUTPUT=""
RUN_IDS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      OUTPUT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      echo "unknown option: $1" >&2
      usage
      exit 2
      ;;
    *)
      RUN_IDS+=("$1")
      shift
      ;;
  esac
done

if [[ -z "$OUTPUT" || "${#RUN_IDS[@]}" -eq 0 ]]; then
  usage
  exit 2
fi

OUTPUT="$OUTPUT" RUN_IDS="${RUN_IDS[*]}" ruby <<'RUBY'
require File.expand_path("scripts/lib/boss_idea", Dir.pwd)
require "fileutils"
require "time"

output_path = ENV.fetch("OUTPUT")
run_ids = ENV.fetch("RUN_IDS").split(/\s+/).reject(&:empty?)
BossIdea.fail_with("invalid output path: #{output_path}", 2) unless BossIdea.repo_local_path?(output_path)

run_ids.each do |run_id|
  BossIdea.fail_with("invalid run id: #{run_id}", 2) if run_id.empty? || run_id.include?("/") || run_id.include?("..")
end

health_schema = BossIdea.load_yaml("agentic/schemas/boss-idea-provider-health.schema.yaml").fetch("schema")
events_schema = BossIdea.load_yaml("agentic/schemas/boss-idea-provider-health-events.schema.yaml").fetch("schema")
retention_policy = health_schema.fetch("retention_policy").slice(
  "raw_event_retention_days",
  "scrubbed_summary_retention_days",
  "tracked_artifact_policy",
  "raw_event_path_policy",
  "public_safe_counts_only"
)
allowed_reasons = Array(health_schema["fallback_reason_taxonomy"]).map(&:to_s)

def provider_priority(provider)
  {
    "searxng" => 1,
    "duckduckgo_html" => 2,
    "local_browser_search" => 3,
    "brave" => 4,
    "live_seed" => 5,
    "fixture" => 9,
    "seed_replay" => 9
  }.fetch(provider.to_s, 99)
end

def no_paid_provider?(provider)
  %w[searxng duckduckgo_html local_browser_search live_seed fixture seed_replay].include?(provider.to_s)
end

def advisory_status(counters)
  return "unknown" if counters.fetch("attempt_count").zero?
  return "healthy" if counters.fetch("failure_count").zero?
  return "degraded" if counters.fetch("success_count").positive?

  "unavailable"
end

provider_summaries = {}
event_times = []
run_ids.each do |run_id|
  events_path = File.join("agentic/runs", run_id, "provider-health-events.yaml")
  BossIdea.fail_with("provider health events not found: #{events_path}") unless File.file?(events_path)
  unless system("scripts/validate-boss-idea-provider-health-events.sh", events_path, out: File::NULL, err: File::NULL)
    BossIdea.fail_with("provider health events failed validation: #{events_path}")
  end

  event_log = BossIdea.load_yaml(events_path)
  BossIdea.fail_with("provider_health_events.run_id must equal #{run_id}") unless event_log["run_id"].to_s == run_id
  provider = event_log["provider"].to_s
  summary = provider_summaries[provider] ||= {
    "provider" => provider,
    "provider_priority" => provider_priority(provider),
    "no_paid_provider" => no_paid_provider?(provider),
    "counters" => Hash.new(0),
    "fallback_reason_counts" => Hash.new(0),
    "evidence_gaps" => []
  }

  counts = event_log.fetch("event_counts")
  summary.fetch("counters")["attempt_count"] += counts.fetch("provider_attempt_count")
  summary.fetch("counters")["success_count"] += counts.fetch("provider_success_count")
  summary.fetch("counters")["failure_count"] += counts.fetch("provider_failure_count")
  summary.fetch("counters")["challenge_or_captcha_count"] += counts.fetch("challenge_or_captcha_count")
  summary.fetch("counters")["fallback_used_count"] += counts.fetch("fallback_used_count")

  Array(event_log["events"]).each do |event|
    occurred_at = Time.iso8601(event.fetch("occurred_at").to_s)
    event_times << occurred_at
    event_type = event["event_type"].to_s
    reason = event["reason"].to_s
    count = event["count"].to_i
    if event_type == "provider_failure" && reason == "provider_timeout"
      summary.fetch("counters")["timeout_count"] += count
    elsif event_type == "provider_failure" && reason == "policy_block"
      summary.fetch("counters")["policy_block_count"] += count
    elsif event_type == "fallback_used"
      BossIdea.fail_with("provider health fallback reason is invalid: #{reason}") unless allowed_reasons.include?(reason)
      summary.fetch("fallback_reason_counts")[reason] += count
    end
  end
end

BossIdea.fail_with("provider health summary requires at least one event timestamp") if event_times.empty?
started_at = event_times.min
ended_at = event_times.max
lookback_days = [((ended_at - started_at) / 86_400.0).ceil, 1].max

providers = provider_summaries.values.sort_by { |summary| [summary.fetch("provider_priority"), summary.fetch("provider")] }.map do |summary|
  counters = summary.fetch("counters")
  %w[attempt_count success_count failure_count challenge_or_captcha_count timeout_count policy_block_count fallback_used_count].each do |field|
    counters[field] = counters[field].to_i
  end
  evidence_gaps = summary.fetch("evidence_gaps")
  evidence_gaps << "provider_failures_observed" if counters["failure_count"].positive?
  evidence_gaps << "challenge_or_captcha_observed" if counters["challenge_or_captcha_count"].positive?
  evidence_gaps << "fallback_used_observed" if counters["fallback_used_count"].positive?
  {
    "provider" => summary.fetch("provider"),
    "provider_priority" => summary.fetch("provider_priority"),
    "no_paid_provider" => summary.fetch("no_paid_provider"),
    "advisory_status" => advisory_status(counters),
    "counters" => counters,
    "fallback_reasons" => summary.fetch("fallback_reason_counts").sort.map do |reason, count|
      { "reason" => reason, "count" => count }
    end,
    "evidence_gaps" => evidence_gaps.uniq
  }
end

summary_totals = {
  "provider_count" => providers.length,
  "total_attempt_count" => providers.sum { |provider| provider.fetch("counters").fetch("attempt_count") },
  "total_success_count" => providers.sum { |provider| provider.fetch("counters").fetch("success_count") },
  "total_failure_count" => providers.sum { |provider| provider.fetch("counters").fetch("failure_count") },
  "total_challenge_or_captcha_count" => providers.sum { |provider| provider.fetch("counters").fetch("challenge_or_captcha_count") },
  "total_fallback_used_count" => providers.sum { |provider| provider.fetch("counters").fetch("fallback_used_count") },
  "advisory_only" => true
}

provider_health = {
  "schema_version" => 1,
  "artifact_kind" => health_schema.fetch("artifact_kind"),
  "generated_at" => Time.now.utc.iso8601,
  "run_scope" => run_ids.length == 1 ? "single_run" : "recent_runs",
  "window" => {
    "started_at" => started_at.utc.iso8601,
    "ended_at" => ended_at.utc.iso8601,
    "lookback_days" => lookback_days
  },
  "retention_policy" => retention_policy,
  "providers" => providers,
  "summary" => summary_totals,
  "authority_note" => "Provider health is advisory evidence only. It cannot approve artifacts, roadmap, budget, implementation, provider selection, or fallback execution."
}

FileUtils.mkdir_p(File.dirname(output_path))
File.write(output_path, provider_health.to_yaml)
unless system("scripts/validate-boss-idea-provider-health.sh", output_path, out: File::NULL, err: File::NULL)
  BossIdea.fail_with("generated provider health summary failed validation")
end

puts "boss idea provider health summary: #{output_path}"
RUBY
