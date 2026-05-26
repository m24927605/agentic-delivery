#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/recommend-boss-idea-provider-fallback.sh --output <fallback-advisory.yaml> <provider-health.yaml>

Produces advisory-only fallback guidance from a scrubbed provider-health summary.
It cannot approve or execute fallback provider changes.
USAGE
}

OUTPUT=""
INPUT=""

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
      if [[ -n "$INPUT" ]]; then
        usage
        exit 2
      fi
      INPUT="$1"
      shift
      ;;
  esac
done

if [[ -z "$OUTPUT" || -z "$INPUT" ]]; then
  usage
  exit 2
fi

OUTPUT="$OUTPUT" INPUT="$INPUT" ruby <<'RUBY'
require File.expand_path("scripts/lib/boss_idea", Dir.pwd)
require "fileutils"
require "time"

input_path = ENV.fetch("INPUT")
output_path = ENV.fetch("OUTPUT")
BossIdea.fail_with("invalid provider health path: #{input_path}", 2) unless BossIdea.repo_local_path?(input_path)
BossIdea.fail_with("invalid output path: #{output_path}", 2) unless BossIdea.repo_local_path?(output_path)
unless system("scripts/validate-boss-idea-provider-health.sh", input_path, out: File::NULL, err: File::NULL)
  BossIdea.fail_with("provider health summary failed validation: #{input_path}")
end

health = BossIdea.load_yaml(input_path)

def fallback_candidate_for(provider)
  {
    "searxng" => "duckduckgo_html",
    "duckduckgo_html" => "local_browser_search",
    "local_browser_search" => "searxng",
    "brave" => "searxng",
    "live_seed" => "searxng"
  }[provider.to_s]
end

def dominant_failure_reason(counters)
  return "challenge_or_captcha" if counters.fetch("challenge_or_captcha_count").positive?
  return "provider_timeout" if counters.fetch("timeout_count").positive?
  return "policy_block" if counters.fetch("policy_block_count").positive?
  return "operator_selected" if counters.fetch("fallback_used_count").positive?
  return "provider_error" if counters.fetch("failure_count").positive?

  "provider_healthy"
end

recommendations = Array(health["providers"]).map do |provider_health|
  provider = provider_health.fetch("provider")
  counters = provider_health.fetch("counters")
  reason = dominant_failure_reason(counters)
  action = if reason == "challenge_or_captcha"
    "escalate_staff_review"
  elsif counters.fetch("failure_count").positive? && fallback_candidate_for(provider)
    "consider_fallback"
  elsif counters.fetch("failure_count").positive?
    "retry_primary"
  elsif counters.fetch("fallback_used_count").positive?
    "monitor_fallback"
  else
    "keep_current_provider"
  end
  recommendation = {
    "provider" => provider,
    "advisory_action" => action,
    "reason" => reason,
    "requires_human_decision" => true,
    "automatic_execution_allowed" => false,
    "approval_status" => "not_approved"
  }
  fallback_provider = fallback_candidate_for(provider)
  if action == "consider_fallback" && fallback_provider
    recommendation["suggested_fallback_provider"] = fallback_provider
  end
  recommendation
end

advisory = {
  "schema_version" => 1,
  "artifact_kind" => "boss_idea_provider_fallback_advisory",
  "generated_at" => Time.now.utc.iso8601,
  "source_provider_health_path" => input_path,
  "recommendations" => recommendations,
  "authority_note" => "Provider fallback advisory is advisory evidence only. It cannot approve artifacts, roadmap, budget, implementation, provider selection, or fallback execution."
}

FileUtils.mkdir_p(File.dirname(output_path))
File.write(output_path, advisory.to_yaml)
unless system("scripts/validate-boss-idea-provider-fallback-advisory.sh", output_path, out: File::NULL, err: File::NULL)
  BossIdea.fail_with("generated provider fallback advisory failed validation")
end

puts "boss idea provider fallback advisory: #{output_path}"
RUBY
