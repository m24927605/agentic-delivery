#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ $# -ne 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  echo "usage: scripts/validate-boss-idea-provider-health-events.sh <provider-health-events.yaml>" >&2
  exit 2
fi

PROVIDER_HEALTH_EVENTS_FILE="$1" ruby <<'RUBY'
require File.expand_path("scripts/lib/boss_idea", Dir.pwd)
require "ipaddr"
require "time"

path = ENV.fetch("PROVIDER_HEALTH_EVENTS_FILE")
event_log = BossIdea.load_yaml(path)
BossIdea.required_mapping!(event_log, "provider_health_events")
schema = BossIdea.load_yaml("agentic/schemas/boss-idea-provider-health-events.schema.yaml").fetch("schema")
health_schema = BossIdea.load_yaml("agentic/schemas/boss-idea-provider-health.schema.yaml").fetch("schema")
BossIdea.require_fields!(event_log, Array(schema["required_fields"]), "provider_health_events")

def require_iso8601!(value, label)
  Time.iso8601(value.to_s)
rescue ArgumentError
  BossIdea.fail_with("#{label} must be ISO8601")
end

def require_positive_integer!(value, label)
  unless value.is_a?(Integer) && value.positive?
    BossIdea.fail_with("#{label} must be a positive integer")
  end
end

def require_non_negative_integer!(value, label)
  unless value.is_a?(Integer) && value >= 0
    BossIdea.fail_with("#{label} must be a non-negative integer")
  end
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
        BossIdea.fail_with("#{label}.#{key} is not allowed in public-safe provider health events")
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
        BossIdea.fail_with("#{label} contains non-public-safe provider health event content")
      end
    end
    if ip_literal?(text)
      BossIdea.fail_with("#{label} contains raw IP address content")
    end
  end
end

BossIdea.fail_with("provider_health_events.schema_version must be 1") unless event_log["schema_version"] == 1
unless event_log["artifact_kind"].to_s == schema.fetch("artifact_kind").to_s
  BossIdea.fail_with("provider_health_events.artifact_kind is invalid: #{event_log["artifact_kind"]}")
end
require_iso8601!(event_log["generated_at"], "provider_health_events.generated_at")

allowed_providers = Array(schema["allowed_providers"]).map(&:to_s)
allowed_modes = Array(schema["allowed_modes"]).map(&:to_s)
provider = event_log["provider"].to_s
mode = event_log["mode"].to_s
BossIdea.fail_with("provider_health_events.provider is invalid: #{provider}") unless allowed_providers.include?(provider)
BossIdea.fail_with("provider_health_events.mode is invalid: #{mode}") unless allowed_modes.include?(mode)

retention = BossIdea.required_mapping!(event_log["retention_policy"], "provider_health_events.retention_policy")
schema.fetch("retention_policy").each do |field, expected|
  unless retention[field] == expected
    BossIdea.fail_with("provider_health_events.retention_policy.#{field} must be #{expected.inspect}")
  end
end

event_count_fields = schema.fetch("event_count_fields")
event_counts = BossIdea.required_mapping!(event_log["event_counts"], "provider_health_events.event_counts")
event_count_fields.values.each do |field|
  BossIdea.fail_with("provider_health_events.event_counts.#{field} is required") unless event_counts.key?(field)
  require_non_negative_integer!(event_counts[field], "provider_health_events.event_counts.#{field}")
end

events = event_log["events"]
unless events.is_a?(Array) && !events.empty?
  BossIdea.fail_with("provider_health_events.events must be a non-empty array")
end

allowed_event_types = Array(schema["allowed_event_types"]).map(&:to_s)
reasons = Array(schema["reason_taxonomy"]).map(&:to_s)
event_types_requiring_reason = Array(schema["event_types_requiring_reason"]).map(&:to_s)
seen_event_ids = {}
actual_counts = Hash.new(0)
events.each_with_index do |event, index|
  label = "provider_health_events.events[#{index}]"
  BossIdea.required_mapping!(event, label)
  BossIdea.require_fields!(event, Array(schema["event_required_fields"]), label)

  event_id = event["event_id"].to_s
  BossIdea.fail_with("#{label}.event_id must be unique: #{event_id}") if seen_event_ids[event_id]
  seen_event_ids[event_id] = true
  require_iso8601!(event["occurred_at"], "#{label}.occurred_at")

  event_type = event["event_type"].to_s
  BossIdea.fail_with("#{label}.event_type is invalid: #{event_type}") unless allowed_event_types.include?(event_type)
  BossIdea.fail_with("#{label}.provider must match root provider") unless event["provider"].to_s == provider
  BossIdea.fail_with("#{label}.mode must match root mode") unless event["mode"].to_s == mode
  require_positive_integer!(event["count"], "#{label}.count")
  BossIdea.fail_with("#{label}.public_safe must be true") unless event["public_safe"] == true
  BossIdea.fail_with("#{label}.source must be market_discovery") unless event["source"].to_s == "market_discovery"

  reason = event["reason"].to_s
  if event_types_requiring_reason.include?(event_type)
    BossIdea.fail_with("#{label}.reason is required for #{event_type}") if reason.empty?
    BossIdea.fail_with("#{label}.reason is invalid: #{reason}") unless reasons.include?(reason)
  elsif !reason.empty?
    BossIdea.fail_with("#{label}.reason is only allowed on failure, challenge, or fallback events")
  end
  if event_type == "challenge_or_captcha" && reason != "challenge_or_captcha"
    BossIdea.fail_with("#{label}.reason must be challenge_or_captcha")
  end

  actual_counts[event_count_fields.fetch(event_type)] += event["count"]
end

event_count_fields.values.each do |field|
  unless event_counts[field] == actual_counts[field]
    BossIdea.fail_with("provider_health_events.event_counts.#{field} must equal event totals")
  end
end
if event_counts["provider_success_count"] + event_counts["provider_failure_count"] > event_counts["provider_attempt_count"]
  BossIdea.fail_with("provider_health_events terminal event counts cannot exceed provider_attempt_count")
end
if event_counts["challenge_or_captcha_count"] > event_counts["provider_failure_count"]
  BossIdea.fail_with("provider_health_events challenge_or_captcha_count cannot exceed provider_failure_count")
end

authority_note = event_log["authority_note"].to_s.downcase
Array(schema.dig("authority_policy", "required_phrases")).each do |phrase|
  unless authority_note.include?(phrase.to_s.downcase)
    BossIdea.fail_with("provider_health_events.authority_note must state advisory-only authority")
  end
end
health_authority_policy = health_schema.fetch("authority_policy")
Array(health_authority_policy["forbidden_phrases"]).each do |phrase|
  if authority_note.include?(phrase.to_s.downcase)
    BossIdea.fail_with("provider_health_events.authority_note contains forbidden authority phrase: #{phrase}")
  end
end
Array(health_authority_policy["forbidden_patterns"]).each do |pattern|
  if event_log["authority_note"].to_s.match?(Regexp.new(pattern, Regexp::IGNORECASE))
    BossIdea.fail_with("provider_health_events.authority_note contains forbidden authority pattern: #{pattern}")
  end
end

forbidden_keys = Array(health_schema.dig("public_safety", "forbidden_keys")).map(&:to_s)
forbidden_value_patterns = Array(health_schema.dig("public_safety", "forbidden_value_patterns")).map do |pattern|
  Regexp.new(pattern.to_s, Regexp::IGNORECASE)
end
public_safe_scan!(event_log, "provider_health_events", forbidden_keys, forbidden_value_patterns)

puts "boss idea provider health events ok: #{path}"
RUBY
