#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ $# -ne 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  echo "usage: scripts/validate-boss-idea-market-discovery-quality.sh <quality-file.yaml>" >&2
  exit 2
fi

QUALITY_FILE="$1" ruby <<'RUBY'
require File.expand_path("scripts/lib/boss_idea", Dir.pwd)

path = ENV.fetch("QUALITY_FILE")
quality = BossIdea.load_yaml(path)
BossIdea.required_mapping!(quality, "market_discovery_quality")
schema = BossIdea.load_yaml("agentic/schemas/boss-idea-market-discovery-quality.schema.yaml").fetch("schema")
BossIdea.require_fields!(quality, Array(schema["required_fields"]), "market_discovery_quality")

unless quality["schema_version"] == 1
  BossIdea.fail_with("market_discovery_quality.schema_version must be 1")
end

allowed_providers = Array(schema["allowed_providers"]).map(&:to_s)
unless allowed_providers.include?(quality["provider"].to_s)
  BossIdea.fail_with("market_discovery_quality.provider is invalid: #{quality["provider"]}")
end

allowed_modes = Array(schema["allowed_modes"]).map(&:to_s)
unless allowed_modes.include?(quality["mode"].to_s)
  BossIdea.fail_with("market_discovery_quality.mode is invalid: #{quality["mode"]}")
end

score = quality["score"]
score_min = Integer(schema.dig("score", "min"))
score_max = Integer(schema.dig("score", "max"))
unless score.is_a?(Integer) && score >= score_min && score <= score_max
  BossIdea.fail_with("market_discovery_quality.score must be an integer between #{score_min} and #{score_max}")
end

unless Array(schema["allowed_bands"]).include?(quality["band"].to_s)
  BossIdea.fail_with("market_discovery_quality.band is invalid: #{quality["band"]}")
end

unless quality["provider_priority"].is_a?(Integer) && quality["provider_priority"].positive?
  BossIdea.fail_with("market_discovery_quality.provider_priority must be a positive integer")
end

unless [true, false].include?(quality["no_paid_provider"])
  BossIdea.fail_with("market_discovery_quality.no_paid_provider must be boolean")
end

checks = BossIdea.required_mapping!(quality["checks"], "market_discovery_quality.checks")
BossIdea.require_fields!(checks, Array(schema["checks_required_fields"]), "market_discovery_quality.checks")
%w[source_count query_coverage_count query_count unique_host_count duplicate_host_count fresh_source_max_age_days stale_source_count missing_or_invalid_access_date_count lower_trust_fallback_count crawl_log_success_count observed_network_entry_count live_success_missing_observed_network_count].each do |field|
  unless checks[field].is_a?(Integer) && checks[field] >= 0
    BossIdea.fail_with("market_discovery_quality.checks.#{field} must be a non-negative integer")
  end
end
unless [true, false].include?(checks["required_signals_present"])
  BossIdea.fail_with("market_discovery_quality.checks.required_signals_present must be boolean")
end
unless [true, false].include?(checks["live_observed_network_required"])
  BossIdea.fail_with("market_discovery_quality.checks.live_observed_network_required must be boolean")
end
if checks["query_coverage_count"] > checks["query_count"]
  BossIdea.fail_with("market_discovery_quality.checks.query_coverage_count cannot exceed query_count")
end
if checks["unique_host_count"] > checks["source_count"]
  BossIdea.fail_with("market_discovery_quality.checks.unique_host_count cannot exceed source_count")
end
if checks["duplicate_host_count"] > checks["source_count"]
  BossIdea.fail_with("market_discovery_quality.checks.duplicate_host_count cannot exceed source_count")
end
if checks["observed_network_entry_count"] > checks["crawl_log_success_count"]
  BossIdea.fail_with("market_discovery_quality.checks.observed_network_entry_count cannot exceed crawl_log_success_count")
end
if checks["live_success_missing_observed_network_count"] > checks["crawl_log_success_count"]
  BossIdea.fail_with("market_discovery_quality.checks.live_success_missing_observed_network_count cannot exceed crawl_log_success_count")
end

BossIdea.fail_with("market_discovery_quality.evidence_gaps is required") unless quality.key?("evidence_gaps")
evidence_gaps = quality["evidence_gaps"]
unless evidence_gaps.is_a?(Array) && evidence_gaps.all? { |gap| gap.is_a?(String) }
  BossIdea.fail_with("market_discovery_quality.evidence_gaps must be an array of strings")
end

Array(schema["checks_optional_date_fields"]).each do |field|
  value = checks[field]
  next if value.nil? || value.to_s.empty?

  BossIdea.fail_with("market_discovery_quality.checks.#{field} must be YYYY-MM-DD") unless BossIdea.valid_date?(value)
end

authority_note = quality["authority_note"].to_s.downcase
Array(schema.dig("authority_policy", "required_phrases")).each do |phrase|
  BossIdea.fail_with("market_discovery_quality.authority_note must state advisory-only authority") unless authority_note.include?(phrase.to_s.downcase)
end

puts "boss idea market discovery quality ok: #{path}"
RUBY
