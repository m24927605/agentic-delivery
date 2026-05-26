#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/boss-idea-searxng-preflight.sh [--probe <query>] [--evidence <path>]

Checks a self-hosted SearXNG endpoint before a live Boss Idea market discovery
run. Evidence is always public-safe and must be written under ignored
agentic/runs/ or agentic/reviews/ paths.

Required environment:
  BOSS_IDEA_SEARCH_SEARXNG_BASE_URL
  BOSS_IDEA_SEARCH_SEARXNG_ENDPOINT_LABEL
  BOSS_IDEA_SEARCH_SEARXNG_NO_PAID_ENGINES=1
USAGE
}

PROBE="${BOSS_IDEA_SEARXNG_PREFLIGHT_PROBE:-agentic delivery public searxng preflight}"
EVIDENCE="${BOSS_IDEA_SEARXNG_PREFLIGHT_EVIDENCE_PATH:-agentic/runs/boss-idea-searxng-preflight/preflight.yaml}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --probe)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      PROBE="$2"
      shift 2
      ;;
    --evidence)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      EVIDENCE="$2"
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
      echo "unexpected argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

PROBE="$PROBE" EVIDENCE="$EVIDENCE" ruby <<'RUBY'
require File.expand_path("scripts/lib/boss_idea", Dir.pwd)
require "fileutils"
require "json"
require "net/http"
require "time"
require "uri"
require "yaml"

SENSITIVE_QUERY_KEY = /(?:\A|[_-])(?:api[_-]?key|access[_-]?token|auth|authorization|credential|key|password|secret|token)(?:\z|[_-])/i
AUTHORITY_NOTE = "SearXNG preflight evidence is advisory only and cannot approve artifacts, go/no-go decisions, roadmap, budget, implementation, PR publishing, or deployment."

def fail_with(message, evidence, code = 1)
  evidence["status"] = "failed"
  evidence["error"] = message
  write_evidence(evidence)
  warn "searxng preflight failed: #{message}"
  puts "evidence=#{evidence.fetch("evidence_path")}"
  exit code
end

def write_evidence(evidence)
  path = evidence.fetch("evidence_path")
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, evidence.to_yaml)
end

def validate_evidence_path!(path)
  unless BossIdea.repo_local_path?(path) &&
      (path.start_with?("agentic/runs/") || path.start_with?("agentic/reviews/"))
    warn "preflight evidence path must stay under ignored agentic/runs/ or agentic/reviews/"
    exit 2
  end
end

def parse_positive_integer_env(name, default, max)
  value = ENV[name].to_s
  return default if value.empty?

  integer = Integer(value, 10)
  return integer if integer.positive? && integer <= max

  raise ArgumentError
rescue ArgumentError
  warn "#{name} must be a positive integer no greater than #{max}"
  exit 2
end

def sensitive_query_key?(key)
  key.to_s.match?(SENSITIVE_QUERY_KEY)
end

def sanitized_uri(uri, redact_probe: true)
  scheme = uri.scheme.to_s
  host = uri.host.to_s
  return "<redacted-url>" if scheme.empty? || host.empty?

  userinfo = uri.userinfo.to_s.empty? ? "" : "redacted@"
  display_host = host.include?(":") && !host.start_with?("[") ? "[#{host}]" : host
  default_port = uri.default_port
  port = uri.port && uri.port != default_port ? ":#{uri.port}" : ""
  path = uri.path.to_s
  params = URI.decode_www_form(uri.query.to_s).map do |key, value|
    if sensitive_query_key?(key)
      [key, "<redacted>"]
    elsif redact_probe && key == "q"
      [key, "<redacted-probe>"]
    else
      [key, value]
    end
  end
  query = params.empty? ? "" : "?#{URI.encode_www_form(params)}"
  "#{scheme}://#{userinfo}#{display_host}#{port}#{path}#{query}"
end

def base_uri_or_fail(value, evidence)
  fail_with("missing BOSS_IDEA_SEARCH_SEARXNG_BASE_URL", evidence, 2) if value.empty?

  uri = URI.parse(value)
  evidence["base_url"] = sanitized_uri(uri)
  unless %w[http https].include?(uri.scheme)
    fail_with("SearXNG base URL must be http or https: #{sanitized_uri(uri)}", evidence, 2)
  end
  fail_with("SearXNG base URL host is required", evidence, 2) if uri.host.to_s.empty?
  unless uri.userinfo.to_s.empty?
    fail_with("SearXNG base URL must not contain userinfo: #{sanitized_uri(uri)}", evidence, 2)
  end

  credential_keys = URI.decode_www_form(uri.query.to_s).map(&:first).select { |key| sensitive_query_key?(key) }
  unless credential_keys.empty?
    fail_with("SearXNG base URL must not contain credential-like query parameters: #{sanitized_uri(uri)}", evidence, 2)
  end

  uri
rescue URI::InvalidURIError
  fail_with("invalid SearXNG base URL", evidence, 2)
end

def search_uri(base_uri, probe)
  uri = base_uri.dup
  uri.path = "/search" if uri.path.to_s.empty? || uri.path == "/"
  params = URI.decode_www_form(uri.query.to_s).reject { |key, _value| %w[q format].include?(key) }
  params << ["q", probe]
  params << ["format", "json"]
  uri.query = URI.encode_www_form(params)
  uri
end

def validate_endpoint_label!(evidence)
  label = ENV["BOSS_IDEA_SEARCH_SEARXNG_ENDPOINT_LABEL"].to_s.strip
  fail_with("missing BOSS_IDEA_SEARCH_SEARXNG_ENDPOINT_LABEL", evidence, 2) if label.empty?
  unless label.match?(/\A[A-Za-z0-9][A-Za-z0-9._-]{0,79}\z/)
    fail_with("BOSS_IDEA_SEARCH_SEARXNG_ENDPOINT_LABEL must be public-safe", evidence, 2)
  end
  evidence["endpoint_label"] = label
  evidence.fetch("checks")["endpoint_label"] = "passed"
  label
end

evidence_path = ENV.fetch("EVIDENCE")
validate_evidence_path!(evidence_path)

evidence = {
  "schema_version" => 1,
  "kind" => "boss_idea_searxng_preflight",
  "provider" => "searxng",
  "status" => "started",
  "checked_at" => Time.now.utc.iso8601,
  "evidence_path" => evidence_path,
  "probe_query" => "<redacted>",
  "raw_response_recorded" => false,
  "authority_note" => AUTHORITY_NOTE,
  "checks" => {}
}

base_uri = base_uri_or_fail(ENV["BOSS_IDEA_SEARCH_SEARXNG_BASE_URL"].to_s, evidence)
evidence.fetch("checks")["base_url"] = "passed"

validate_endpoint_label!(evidence)

unless ENV["BOSS_IDEA_SEARCH_SEARXNG_NO_PAID_ENGINES"].to_s == "1"
  fail_with("missing BOSS_IDEA_SEARCH_SEARXNG_NO_PAID_ENGINES=1", evidence, 2)
end
evidence.fetch("checks")["no_paid_engine_policy"] = "operator-confirmed"

probe = ENV.fetch("PROBE")
uri = search_uri(base_uri, probe)
evidence["probe_url"] = sanitized_uri(uri)

timeout = parse_positive_integer_env("BOSS_IDEA_SEARCH_SEARXNG_TIMEOUT_SECONDS", 10, 30)
request = Net::HTTP::Get.new(uri)
request["Accept"] = "application/json"
gateway_token = ENV["BOSS_IDEA_SEARCH_SEARXNG_API_KEY"].to_s
request["Authorization"] = "Bearer #{gateway_token}" unless gateway_token.empty?

begin
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: timeout, read_timeout: timeout) do |http|
    http.request(request)
  end
rescue StandardError => e
  fail_with("SearXNG preflight request failed: #{e.class}: #{e.message}", evidence)
end

evidence["http_status"] = response.code.to_i
evidence["content_type"] = response["content-type"].to_s
unless response.is_a?(Net::HTTPSuccess)
  fail_with("SearXNG preflight returned HTTP #{response.code}", evidence)
end

unless evidence.fetch("content_type").downcase.include?("json")
  fail_with("SearXNG preflight returned non-JSON content type", evidence)
end

begin
  payload = JSON.parse(response.body)
rescue JSON::ParserError => e
  fail_with("SearXNG preflight returned invalid JSON: #{e.message}", evidence)
end

fail_with("SearXNG preflight JSON root must be an object", evidence) unless payload.is_a?(Hash)

results = payload["results"]
fail_with("SearXNG preflight JSON missing results array", evidence) unless results.is_a?(Array)

evidence["result_count"] = results.length
evidence.fetch("checks")["json_output"] = "passed"
evidence["status"] = "passed"
write_evidence(evidence)

puts "searxng preflight ok"
puts "endpoint_label=#{evidence.fetch("endpoint_label")}"
puts "base_url=#{evidence.fetch("base_url")}"
puts "probe_url=#{evidence.fetch("probe_url")}"
puts "evidence=#{evidence_path}"
RUBY
