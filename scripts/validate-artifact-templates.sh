#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/validate-artifact-templates.sh <planning-run-id> [--artifact <path>]
USAGE
}

if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

RUN_ID="$1"
shift
ARTIFACT_FILTER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifact)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      ARTIFACT_FILTER="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

case "$RUN_ID" in
  */*|*..*|"")
    echo "invalid run id: $RUN_ID" >&2
    exit 2
    ;;
esac

case "$ARTIFACT_FILTER" in
  /*|*..*)
    echo "invalid artifact path: $ARTIFACT_FILTER" >&2
    exit 2
    ;;
esac

MANIFEST="agentic/runs/$RUN_ID/manifest.yaml"
if [[ ! -f "$MANIFEST" ]]; then
  echo "planning manifest not found: $MANIFEST" >&2
  exit 1
fi

RUN_ID="$RUN_ID" MANIFEST="$MANIFEST" ARTIFACT_FILTER="$ARTIFACT_FILTER" ruby <<'RUBY'
require "yaml"

run_id = ENV.fetch("RUN_ID")
manifest_path = ENV.fetch("MANIFEST")
artifact_filter = ENV["ARTIFACT_FILTER"].to_s
schema = YAML.load_file("agentic/schemas/artifact-template.schema.yaml")
manifest = YAML.load_file(manifest_path)
errors = []

def public_safe_path?(path)
  return false if path.to_s.empty?
  return false if path.start_with?("/")
  return false if path.split("/").include?("..")
  true
end

def kind_for(artifact, path)
  explicit = artifact["kind"].to_s
  return explicit unless explicit.empty?

  case path
  when %r{\Adocs/architecture/} then "architecture"
  when %r{\Adocs/backlog/} then "roadmap"
  when %r{\Adocs/adr/} then "adr"
  when /\.ya?ml\z/i then "schema"
  else "other"
  end
end

def markdown_headings(content)
  content.lines.map do |line|
    line[/\A\#{1,6}\s+(.+?)\s*\z/, 1]&.strip
  end.compact
end

unless manifest.dig("run", "id").to_s == run_id
  warn "run.id mismatch: expected #{run_id}"
  exit 1
end

artifacts = Array(manifest["artifacts"]).select { |artifact| artifact.is_a?(Hash) }
artifacts = artifacts.select { |artifact| artifact["path"].to_s == artifact_filter } unless artifact_filter.empty?

if artifacts.empty?
  warn "no artifacts found for template validation"
  exit 1
end

artifacts.each do |artifact|
  path = artifact["path"].to_s
  unless public_safe_path?(path)
    errors << "invalid artifact path: #{path}"
    next
  end

  next unless File.file?(path)
  generation = artifact["generation"].is_a?(Hash) ? artifact["generation"] : {}
  generated_or_requested = generation["created_file"] == true ||
    generation["mode"].to_s == "ai_agent" ||
    !artifact["generation_instructions"].to_s.strip.empty? ||
    !artifact["requested_by"].to_s.start_with?("profile:")
  next if artifact_filter.empty? && !generated_or_requested

  kind = kind_for(artifact, path)
  kind_schema = schema.dig("kinds", kind) || schema.dig("kinds", "other") || {}

  if File.extname(path) =~ /\.ya?ml\z/i
    document = YAML.load_file(path)
    Array(kind_schema["required_yaml_keys"]).each do |key|
      errors << "#{path} missing YAML key: #{key}" unless document.is_a?(Hash) && document.key?(key)
    end
  else
    content = File.read(path)
    headings = markdown_headings(content)
    required = Array(kind_schema["required_markdown_headings"])
    required = Array(schema.dig("defaults", "required_markdown_headings")) if required.empty?
    required.each do |heading|
      errors << "#{path} missing required section: #{heading}" unless headings.include?(heading)
    end
  end
end

unless errors.empty?
  errors.each { |error| warn "artifact template invalid: #{error}" }
  exit 1
end

puts "artifact templates ok: #{run_id} artifacts=#{artifacts.length}"
RUBY
