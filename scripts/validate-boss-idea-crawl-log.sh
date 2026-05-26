#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ $# -ne 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  echo "usage: scripts/validate-boss-idea-crawl-log.sh <crawl-log.yaml>" >&2
  exit 2
fi

CRAWL_LOG_FILE="$1" ruby <<'RUBY'
require File.expand_path("scripts/lib/boss_idea", Dir.pwd)
require "ipaddr"
require "time"
require "uri"

path = ENV.fetch("CRAWL_LOG_FILE")
crawl_log = BossIdea.load_yaml(path)
BossIdea.required_mapping!(crawl_log, "crawl_log")
schema = BossIdea.load_yaml("agentic/schemas/boss-idea-crawl-log.schema.yaml").fetch("schema")
BossIdea.require_fields!(crawl_log, Array(schema["required_fields"]), "crawl_log")

def blocked_ip?(value, non_public_ranges, ipv6_public_ranges)
  ip = IPAddr.new(value.to_s).native
  return true if non_public_ranges.any? { |range| range.include?(ip) }

  ip.ipv6? && !ipv6_public_ranges.any? { |range| range.include?(ip) }
rescue IPAddr::InvalidAddressError
  BossIdea.fail_with("crawl_log observed_network.observed_ips contains invalid IP: #{value}")
end

def http_url?(value)
  uri = URI.parse(value.to_s)
  %w[http https].include?(uri.scheme) && !uri.host.to_s.empty?
rescue URI::InvalidURIError
  false
end

def authority_segments(text)
  text.to_s.split(/(?<=[.!?])\s+|\n/).map(&:strip).reject(&:empty?)
end

def require_observed_network!(entry, entry_label, schema, non_public_ranges, ipv6_public_ranges)
  observed = BossIdea.required_mapping!(entry["observed_network"], "#{entry_label}.observed_network")
  BossIdea.require_fields!(observed, Array(schema["observed_network_required_fields"]), "#{entry_label}.observed_network")

  %w[requested_url final_url].each do |field|
    BossIdea.fail_with("#{entry_label}.observed_network.#{field} must be http or https") unless http_url?(observed[field])
  end

  final_host = observed["final_host"].to_s
  BossIdea.fail_with("#{entry_label}.observed_network.final_host is required") if final_host.empty?

  final_uri = URI.parse(observed["final_url"].to_s)
  unless final_uri.host.to_s.downcase == final_host.downcase
    BossIdea.fail_with("#{entry_label}.observed_network.final_host must match final_url host")
  end

  observed_ips = observed["observed_ips"]
  unless observed_ips.is_a?(Array) && !observed_ips.empty?
    BossIdea.fail_with("#{entry_label}.observed_network.observed_ips must be a non-empty array")
  end
  observed_ips.each do |ip|
    if blocked_ip?(ip, non_public_ranges, ipv6_public_ranges)
      BossIdea.fail_with("#{entry_label}.observed_network.observed_ips contains blocked IP: #{ip}")
    end
  end

  begin
    Time.iso8601(observed["resolved_at"].to_s)
  rescue ArgumentError
    BossIdea.fail_with("#{entry_label}.observed_network.resolved_at must be ISO8601")
  end

  allowed_sources = Array(schema["observed_network_sources"]).map(&:to_s)
  unless allowed_sources.include?(observed["source"].to_s)
    BossIdea.fail_with("#{entry_label}.observed_network.source is invalid: #{observed["source"]}")
  end
end

BossIdea.fail_with("crawl_log.schema_version must be 1") unless crawl_log["schema_version"] == 1

allowed_providers = Array(schema["allowed_providers"]).map(&:to_s)
BossIdea.fail_with("crawl_log.provider is invalid: #{crawl_log["provider"]}") unless allowed_providers.include?(crawl_log["provider"].to_s)

allowed_modes = Array(schema["allowed_modes"]).map(&:to_s)
mode = crawl_log["mode"].to_s
BossIdea.fail_with("crawl_log.mode is invalid: #{crawl_log["mode"]}") unless allowed_modes.include?(mode)

unless [true, false].include?(crawl_log["fixture_overrides_live"])
  BossIdea.fail_with("crawl_log.fixture_overrides_live must be boolean")
end

BossIdea.required_mapping!(crawl_log["policy"], "crawl_log.policy")
entries = crawl_log["entries"]
unless entries.is_a?(Array) && !entries.empty?
  BossIdea.fail_with("crawl_log.entries must be a non-empty array")
end

allowed_statuses = Array(schema["allowed_statuses"]).map(&:to_s)
live_modes = Array(schema["live_modes_requiring_observed_network"]).map(&:to_s)
non_public_ranges = Array(schema.dig("observed_ip_policy", "reject_non_public_ranges")).map do |range|
  IPAddr.new(range.to_s)
end
ipv6_public_ranges = Array(schema.dig("observed_ip_policy", "ipv6_public_unicast_ranges")).map do |range|
  IPAddr.new(range.to_s)
end
entries.each_with_index do |entry, index|
  entry_label = "crawl_log.entries[#{index}]"
  BossIdea.required_mapping!(entry, entry_label)
  BossIdea.require_fields!(entry, Array(schema["entry_required_fields"]), entry_label)
  status = entry["status"].to_s
  BossIdea.fail_with("#{entry_label}.status is invalid: #{status}") unless allowed_statuses.include?(status)

  BossIdea.fail_with("#{entry_label}.url must be http or https") unless http_url?(entry["url"])

  if status == "success"
    BossIdea.require_fields!(entry, Array(schema["success_entry_required_fields"]), entry_label)
    BossIdea.fail_with("#{entry_label}.truncated must be boolean") unless [true, false].include?(entry["truncated"])
  end
  if (status == "success" && live_modes.include?(mode)) || entry.key?("observed_network")
    require_observed_network!(entry, entry_label, schema, non_public_ranges, ipv6_public_ranges)
  end
end

authority_policy = schema.fetch("authority_policy")
authority_note = crawl_log["authority_note"].to_s
authority_note_lower = authority_note.downcase
Array(authority_policy["required_phrases"]).each do |phrase|
  unless authority_note_lower.include?(phrase.to_s.downcase)
    BossIdea.fail_with("crawl_log.authority_note must state evidence-only authority")
  end
end

Array(authority_policy["forbidden_phrases"]).each do |phrase|
  if authority_note_lower.include?(phrase.to_s.downcase)
    BossIdea.fail_with("crawl_log.authority_note contains forbidden authority phrase: #{phrase}")
  end
end

Array(authority_policy["forbidden_patterns"]).each do |pattern|
  regex = Regexp.new(pattern, Regexp::IGNORECASE)
  if authority_note.match?(regex)
    BossIdea.fail_with("crawl_log.authority_note contains forbidden authority pattern: #{pattern}")
  end
end

surface_pattern = Regexp.new(
  "\\b(#{Array(authority_policy["prohibited_authority_surfaces"]).map { |surface| Regexp.escape(surface) }.join("|")})\\b",
  Regexp::IGNORECASE
)
approval_signal_pattern = Regexp.new(authority_policy.fetch("approval_signal_pattern"), Regexp::IGNORECASE)
negated_approval_pattern = Regexp.new(authority_policy.fetch("negated_approval_pattern"), Regexp::IGNORECASE)
authority_segments(authority_note).each do |segment|
  sanitized_segment = segment.gsub(negated_approval_pattern, "")

  if sanitized_segment.match?(surface_pattern) && sanitized_segment.match?(approval_signal_pattern)
    BossIdea.fail_with("crawl_log.authority_note contains forbidden authority claim: #{segment}")
  end
end

allowed_note_patterns = Array(authority_policy["allowed_note_patterns"]).map do |pattern|
  Regexp.new(pattern, Regexp::IGNORECASE)
end
unless allowed_note_patterns.any? { |pattern| authority_note.match?(pattern) }
  BossIdea.fail_with("crawl_log.authority_note must match allowed evidence-only wording")
end

puts "boss idea crawl log ok: #{path}"
RUBY
