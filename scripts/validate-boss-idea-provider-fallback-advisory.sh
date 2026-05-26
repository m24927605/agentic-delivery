#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ $# -ne 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  echo "usage: scripts/validate-boss-idea-provider-fallback-advisory.sh <fallback-advisory.yaml>" >&2
  exit 2
fi

FALLBACK_ADVISORY_FILE="$1" ruby <<'RUBY'
require File.expand_path("scripts/lib/boss_idea", Dir.pwd)
require "ipaddr"
require "time"

path = ENV.fetch("FALLBACK_ADVISORY_FILE")
advisory = BossIdea.load_yaml(path)
BossIdea.required_mapping!(advisory, "provider_fallback_advisory")
schema = BossIdea.load_yaml("agentic/schemas/boss-idea-provider-fallback-advisory.schema.yaml").fetch("schema")
health_schema = BossIdea.load_yaml("agentic/schemas/boss-idea-provider-health.schema.yaml").fetch("schema")
BossIdea.require_fields!(advisory, Array(schema["required_fields"]), "provider_fallback_advisory")

def require_iso8601!(value, label)
  Time.iso8601(value.to_s)
rescue ArgumentError
  BossIdea.fail_with("#{label} must be ISO8601")
end

def ip_literal?(value)
  text = value.to_s.strip
  return false if text.empty?
  if text.match?(/\A\d{1,3}(?:\.\d{1,3}){3}\z/)
    IPAddr.new(text)
    return true
  end
  return false unless text.include?(":")

  IPAddr.new(text).ipv6?
rescue IPAddr::InvalidAddressError
  false
end

def public_safe_scan!(value, label, forbidden_keys, forbidden_value_patterns)
  case value
  when Hash
    value.each do |key, inner|
      key_text = key.to_s.downcase
      if forbidden_keys.include?(key_text)
        BossIdea.fail_with("#{label}.#{key} is not allowed in provider fallback advisory")
      end
      public_safe_scan!(inner, "#{label}.#{key}", forbidden_keys, forbidden_value_patterns)
    end
  when Array
    value.each_with_index { |inner, index| public_safe_scan!(inner, "#{label}[#{index}]", forbidden_keys, forbidden_value_patterns) }
  when String
    text = value.to_s
    forbidden_value_patterns.each do |pattern|
      BossIdea.fail_with("#{label} contains non-public-safe fallback advisory content") if text.match?(pattern)
    end
    BossIdea.fail_with("#{label} contains raw IP address content") if ip_literal?(text)
  end
end

BossIdea.fail_with("provider_fallback_advisory.schema_version must be 1") unless advisory["schema_version"] == 1
unless advisory["artifact_kind"].to_s == schema.fetch("artifact_kind")
  BossIdea.fail_with("provider_fallback_advisory.artifact_kind is invalid: #{advisory["artifact_kind"]}")
end
require_iso8601!(advisory["generated_at"], "provider_fallback_advisory.generated_at")
source_path = advisory["source_provider_health_path"].to_s
BossIdea.fail_with("provider_fallback_advisory.source_provider_health_path must be repo-local") unless BossIdea.repo_local_path?(source_path)

allowed_providers = Array(schema["allowed_providers"]).map(&:to_s)
allowed_actions = Array(schema["allowed_actions"]).map(&:to_s)
allowed_reasons = Array(schema["allowed_reason_labels"]).map(&:to_s)
recommendations = advisory["recommendations"]
unless recommendations.is_a?(Array) && !recommendations.empty?
  BossIdea.fail_with("provider_fallback_advisory.recommendations must be a non-empty array")
end
recommendations.each_with_index do |recommendation, index|
  label = "provider_fallback_advisory.recommendations[#{index}]"
  BossIdea.required_mapping!(recommendation, label)
  BossIdea.require_fields!(recommendation, Array(schema["recommendation_required_fields"]), label)
  provider = recommendation["provider"].to_s
  action = recommendation["advisory_action"].to_s
  reason = recommendation["reason"].to_s
  BossIdea.fail_with("#{label}.provider is invalid: #{provider}") unless allowed_providers.include?(provider)
  BossIdea.fail_with("#{label}.advisory_action is invalid: #{action}") unless allowed_actions.include?(action)
  BossIdea.fail_with("#{label}.reason is invalid: #{reason}") unless allowed_reasons.include?(reason)
  if recommendation.key?("suggested_fallback_provider") && !recommendation["suggested_fallback_provider"].to_s.empty?
    suggested = recommendation["suggested_fallback_provider"].to_s
    BossIdea.fail_with("#{label}.suggested_fallback_provider is invalid: #{suggested}") unless allowed_providers.include?(suggested)
  end
  BossIdea.fail_with("#{label}.requires_human_decision must be true") unless recommendation["requires_human_decision"] == true
  BossIdea.fail_with("#{label}.automatic_execution_allowed must be false") unless recommendation["automatic_execution_allowed"] == false
  unless recommendation["approval_status"].to_s == schema.fetch("approval_status")
    BossIdea.fail_with("#{label}.approval_status must be #{schema.fetch("approval_status")}")
  end
end

authority_note = advisory["authority_note"].to_s
authority_lower = authority_note.downcase
Array(schema.dig("authority_policy", "required_phrases")).each do |phrase|
  BossIdea.fail_with("provider_fallback_advisory.authority_note must state advisory-only authority") unless authority_lower.include?(phrase.to_s.downcase)
end
health_authority_policy = health_schema.fetch("authority_policy")
Array(health_authority_policy["forbidden_phrases"]).each do |phrase|
  if authority_lower.include?(phrase.to_s.downcase)
    BossIdea.fail_with("provider_fallback_advisory.authority_note contains forbidden authority phrase: #{phrase}")
  end
end
Array(health_authority_policy["forbidden_patterns"]).each do |pattern|
  if authority_note.match?(Regexp.new(pattern, Regexp::IGNORECASE))
    BossIdea.fail_with("provider_fallback_advisory.authority_note contains forbidden authority pattern: #{pattern}")
  end
end

forbidden_keys = Array(health_schema.dig("public_safety", "forbidden_keys")).map(&:to_s)
forbidden_value_patterns = Array(health_schema.dig("public_safety", "forbidden_value_patterns")).map do |pattern|
  Regexp.new(pattern.to_s, Regexp::IGNORECASE)
end
public_safe_scan!(advisory.reject { |key, _| key == "source_provider_health_path" }, "provider_fallback_advisory", forbidden_keys, forbidden_value_patterns)

puts "boss idea provider fallback advisory ok: #{path}"
RUBY
