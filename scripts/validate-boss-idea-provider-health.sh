#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ $# -ne 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  echo "usage: scripts/validate-boss-idea-provider-health.sh <provider-health.yaml>" >&2
  exit 2
fi

PROVIDER_HEALTH_FILE="$1" ruby <<'RUBY'
require File.expand_path("scripts/lib/boss_idea", Dir.pwd)
require "ipaddr"
require "time"

path = ENV.fetch("PROVIDER_HEALTH_FILE")
health = BossIdea.load_yaml(path)
BossIdea.required_mapping!(health, "provider_health")
schema = BossIdea.load_yaml("agentic/schemas/boss-idea-provider-health.schema.yaml").fetch("schema")
BossIdea.require_fields!(health, Array(schema["required_fields"]), "provider_health")

def require_iso8601!(value, label)
  Time.iso8601(value.to_s)
rescue ArgumentError
  BossIdea.fail_with("#{label} must be ISO8601")
end

def require_non_negative_integer!(value, label)
  unless value.is_a?(Integer) && value >= 0
    BossIdea.fail_with("#{label} must be a non-negative integer")
  end
end

def require_boolean!(value, label)
  BossIdea.fail_with("#{label} must be boolean") unless [true, false].include?(value)
end

def ip_literal?(value)
  text = value.to_s.strip
  return false if text.empty?

  if text.match?(/\A\d{1,3}(?:\.\d{1,3}){3}\z/)
    IPAddr.new(text)
    return true
  end
  return false unless text.include?(":")

  ip = IPAddr.new(text)
  ip.ipv6?
rescue IPAddr::InvalidAddressError
  false
end

def public_safe_scan!(value, label, forbidden_keys, forbidden_value_patterns)
  case value
  when Hash
    value.each do |key, inner|
      key_text = key.to_s.downcase
      if forbidden_keys.include?(key_text)
        BossIdea.fail_with("#{label}.#{key} is not allowed in a public-safe provider health artifact")
      end
      public_safe_scan!(inner, "#{label}.#{key}", forbidden_keys, forbidden_value_patterns)
    end
  when Array
    value.each_with_index do |inner, index|
      public_safe_scan!(inner, "#{label}[#{index}]", forbidden_keys, forbidden_value_patterns)
    end
  when String
    text = value.to_s
    forbidden_value_patterns.each do |pattern|
      if text.match?(pattern)
        BossIdea.fail_with("#{label} contains non-public-safe provider health content")
      end
    end
    if ip_literal?(text)
      BossIdea.fail_with("#{label} contains raw IP address content")
    end
  end
end

BossIdea.fail_with("provider_health.schema_version must be 1") unless health["schema_version"] == 1
unless health["artifact_kind"].to_s == schema.fetch("artifact_kind").to_s
  BossIdea.fail_with("provider_health.artifact_kind is invalid: #{health["artifact_kind"]}")
end

require_iso8601!(health["generated_at"], "provider_health.generated_at")

allowed_run_scopes = Array(schema["allowed_run_scopes"]).map(&:to_s)
unless allowed_run_scopes.include?(health["run_scope"].to_s)
  BossIdea.fail_with("provider_health.run_scope is invalid: #{health["run_scope"]}")
end

window = BossIdea.required_mapping!(health["window"], "provider_health.window")
%w[started_at ended_at lookback_days].each do |field|
  BossIdea.fail_with("provider_health.window.#{field} is required") if window[field].nil?
end
started_at = require_iso8601!(window["started_at"], "provider_health.window.started_at")
ended_at = require_iso8601!(window["ended_at"], "provider_health.window.ended_at")
BossIdea.fail_with("provider_health.window.started_at cannot be after ended_at") if started_at > ended_at
unless window["lookback_days"].is_a?(Integer) && window["lookback_days"].positive?
  BossIdea.fail_with("provider_health.window.lookback_days must be a positive integer")
end

retention = BossIdea.required_mapping!(health["retention_policy"], "provider_health.retention_policy")
policy_schema = schema.fetch("retention_policy")
BossIdea.require_fields!(retention, Array(policy_schema["required_fields"]), "provider_health.retention_policy")
%w[raw_event_retention_days scrubbed_summary_retention_days tracked_artifact_policy raw_event_path_policy public_safe_counts_only].each do |field|
  expected = policy_schema.fetch(field)
  unless retention[field] == expected
    BossIdea.fail_with("provider_health.retention_policy.#{field} must be #{expected.inspect}")
  end
end

allowed_providers = Array(schema["allowed_providers"]).map(&:to_s)
allowed_statuses = Array(schema["allowed_health_statuses"]).map(&:to_s)
allowed_fallback_reasons = Array(schema["fallback_reason_taxonomy"]).map(&:to_s)
counter_fields = Array(schema["counter_required_fields"]).map(&:to_s)
providers = health["providers"]
unless providers.is_a?(Array) && !providers.empty?
  BossIdea.fail_with("provider_health.providers must be a non-empty array")
end

seen_providers = {}
summary_totals = Hash.new(0)
providers.each_with_index do |provider_health, index|
  label = "provider_health.providers[#{index}]"
  BossIdea.required_mapping!(provider_health, label)
  Array(schema["provider_required_fields"]).each do |field|
    unless provider_health.key?(field.to_s) && !provider_health[field.to_s].nil?
      BossIdea.fail_with("#{label}.#{field} is required")
    end
  end

  provider = provider_health["provider"].to_s
  BossIdea.fail_with("#{label}.provider is invalid: #{provider}") unless allowed_providers.include?(provider)
  BossIdea.fail_with("#{label}.provider must be unique: #{provider}") if seen_providers[provider]
  seen_providers[provider] = true

  unless provider_health["provider_priority"].is_a?(Integer) && provider_health["provider_priority"].positive?
    BossIdea.fail_with("#{label}.provider_priority must be a positive integer")
  end
  require_boolean!(provider_health["no_paid_provider"], "#{label}.no_paid_provider")
  unless allowed_statuses.include?(provider_health["advisory_status"].to_s)
    BossIdea.fail_with("#{label}.advisory_status is invalid: #{provider_health["advisory_status"]}")
  end

  counters = BossIdea.required_mapping!(provider_health["counters"], "#{label}.counters")
  BossIdea.require_fields!(counters, counter_fields, "#{label}.counters")
  counter_fields.each do |field|
    require_non_negative_integer!(counters[field], "#{label}.counters.#{field}")
  end

  if counters["success_count"] + counters["failure_count"] > counters["attempt_count"]
    BossIdea.fail_with("#{label}.counters success_count plus failure_count cannot exceed attempt_count")
  end
  %w[challenge_or_captcha_count timeout_count policy_block_count].each do |field|
    if counters[field] > counters["failure_count"]
      BossIdea.fail_with("#{label}.counters.#{field} cannot exceed failure_count")
    end
  end
  if counters["fallback_used_count"] > counters["attempt_count"]
    BossIdea.fail_with("#{label}.counters.fallback_used_count cannot exceed attempt_count")
  end

  fallback_reasons = provider_health["fallback_reasons"]
  unless fallback_reasons.is_a?(Array)
    BossIdea.fail_with("#{label}.fallback_reasons must be an array")
  end
  fallback_reason_total = 0
  fallback_reasons.each_with_index do |fallback_reason, reason_index|
    reason_label = "#{label}.fallback_reasons[#{reason_index}]"
    BossIdea.required_mapping!(fallback_reason, reason_label)
    BossIdea.require_fields!(fallback_reason, %w[reason count], reason_label)
    reason = fallback_reason["reason"].to_s
    unless allowed_fallback_reasons.include?(reason)
      BossIdea.fail_with("#{reason_label}.reason is invalid: #{reason}")
    end
    require_non_negative_integer!(fallback_reason["count"], "#{reason_label}.count")
    fallback_reason_total += fallback_reason["count"]
  end
  unless fallback_reason_total == counters["fallback_used_count"]
    BossIdea.fail_with("#{label}.fallback_reasons counts must equal counters.fallback_used_count")
  end

  evidence_gaps = provider_health["evidence_gaps"]
  unless evidence_gaps.is_a?(Array) && evidence_gaps.all? { |gap| gap.is_a?(String) }
    BossIdea.fail_with("#{label}.evidence_gaps must be an array of strings")
  end

  summary_totals["total_attempt_count"] += counters["attempt_count"]
  summary_totals["total_success_count"] += counters["success_count"]
  summary_totals["total_failure_count"] += counters["failure_count"]
  summary_totals["total_challenge_or_captcha_count"] += counters["challenge_or_captcha_count"]
  summary_totals["total_fallback_used_count"] += counters["fallback_used_count"]
end

summary = BossIdea.required_mapping!(health["summary"], "provider_health.summary")
BossIdea.require_fields!(summary, Array(schema["summary_required_fields"]), "provider_health.summary")
unless summary["provider_count"] == providers.length
  BossIdea.fail_with("provider_health.summary.provider_count must match providers length")
end
summary_totals.each do |field, expected|
  unless summary[field] == expected
    BossIdea.fail_with("provider_health.summary.#{field} must equal provider counter total")
  end
end
require_boolean!(summary["advisory_only"], "provider_health.summary.advisory_only")
BossIdea.fail_with("provider_health.summary.advisory_only must be true") unless summary["advisory_only"] == true

authority_policy = schema.fetch("authority_policy")
authority_note = health["authority_note"].to_s
authority_note_lower = authority_note.downcase
Array(authority_policy["required_phrases"]).each do |phrase|
  unless authority_note_lower.include?(phrase.to_s.downcase)
    BossIdea.fail_with("provider_health.authority_note must state advisory-only authority")
  end
end
Array(authority_policy["forbidden_phrases"]).each do |phrase|
  if authority_note_lower.include?(phrase.to_s.downcase)
    BossIdea.fail_with("provider_health.authority_note contains forbidden authority phrase: #{phrase}")
  end
end
Array(authority_policy["forbidden_patterns"]).each do |pattern|
  if authority_note.match?(Regexp.new(pattern, Regexp::IGNORECASE))
    BossIdea.fail_with("provider_health.authority_note contains forbidden authority pattern: #{pattern}")
  end
end

forbidden_keys = Array(schema.dig("public_safety", "forbidden_keys")).map(&:to_s)
forbidden_value_patterns = Array(schema.dig("public_safety", "forbidden_value_patterns")).map do |pattern|
  Regexp.new(pattern.to_s, Regexp::IGNORECASE)
end
public_safe_scan!(health, "provider_health", forbidden_keys, forbidden_value_patterns)

puts "boss idea provider health ok: #{path}"
RUBY
