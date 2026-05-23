#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ $# -ne 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  echo "usage: scripts/validate-boss-idea-research.sh <research-file.md>" >&2
  exit 2
fi

RESEARCH_FILE="$1" ruby <<'RUBY'
require File.expand_path("scripts/lib/boss_idea", Dir.pwd)

path = ENV.fetch("RESEARCH_FILE")
frontmatter, = BossIdea.load_markdown(path)
BossIdea.required_mapping!(frontmatter, "research frontmatter")
schema = BossIdea.load_yaml("agentic/schemas/boss-idea-research.schema.yaml")
schema_root = schema.fetch("schema")
BossIdea.require_fields!(frontmatter, Array(schema_root["required_fields"]), "research")

sources = BossIdea.require_array!(frontmatter, "sources", "research")
source_required_fields = Array(schema_root["source_required_fields"])
allowed_source_types = Array(schema_root["allowed_source_types"]).map(&:to_s)
source_ids = sources.map do |source|
  BossIdea.required_mapping!(source, "research.sources[]")
  BossIdea.require_fields!(source, source_required_fields, "research.sources[]")
  BossIdea.fail_with("research.sources[].access_date must be YYYY-MM-DD") unless BossIdea.valid_date?(source["access_date"])
  access_date = Date.iso8601(source["access_date"].to_s)
  BossIdea.fail_with("research.sources[].access_date cannot be in the future") if access_date > Date.today
  unless allowed_source_types.include?(source["source_type"].to_s)
    BossIdea.fail_with("research.sources[].source_type is invalid: #{source["source_type"]}")
  end
  source["id"].to_s
end
duplicates = source_ids.group_by(&:itself).select { |_, values| values.length > 1 }.keys
BossIdea.fail_with("research.sources[].id duplicates: #{duplicates.join(", ")}") unless duplicates.empty?

claims = BossIdea.require_array!(frontmatter, "claims", "research")
claim_required_fields = Array(schema_root["claim_required_fields"])
claims.each do |claim|
  BossIdea.required_mapping!(claim, "research.claims[]")
  BossIdea.require_fields!(claim, claim_required_fields, "research.claims[]")
  ids = Array(claim["source_ids"]).map(&:to_s)
  BossIdea.fail_with("research.claims[].source_ids must not be empty") if ids.empty?
  missing = ids - source_ids
  BossIdea.fail_with("research.claims[] references unknown sources: #{missing.join(", ")}") unless missing.empty?
end

inference_required_fields = Array(schema_root["inference_required_fields"])
allowed_inference_labels = Array(schema_root["allowed_inference_labels"]).map(&:to_s)
Array(frontmatter["inferences"]).each do |inference|
  BossIdea.required_mapping!(inference, "research.inferences[]")
  BossIdea.require_fields!(inference, inference_required_fields, "research.inferences[]")
  unless allowed_inference_labels.include?(inference["label"].to_s)
    BossIdea.fail_with("research.inferences[].label must be inference, unknown, or unsupported")
  end
  ids = Array(inference["source_ids"]).map(&:to_s)
  BossIdea.fail_with("research.inferences[].source_ids must not be empty") if ids.empty?
  missing = ids - source_ids
  BossIdea.fail_with("research.inferences[] references unknown sources: #{missing.join(", ")}") unless missing.empty?
end

raw_path = frontmatter["raw_evidence_path"].to_s
BossIdea.fail_with("research.raw_evidence_path is required") if raw_path.empty?
BossIdea.fail_with("research.raw_evidence_path must be repo-local") unless BossIdea.repo_local_path?(raw_path)
unless raw_path.start_with?("agentic/reviews/") || raw_path.start_with?("agentic/runs/")
  BossIdea.fail_with("research.raw_evidence_path must stay under ignored evidence paths")
end

puts "boss idea research ok: #{path}"
RUBY
