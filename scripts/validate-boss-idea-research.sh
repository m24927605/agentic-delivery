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

sources = BossIdea.require_array!(frontmatter, "sources", "research")
source_ids = sources.map do |source|
  BossIdea.required_mapping!(source, "research.sources[]")
  BossIdea.require_fields!(source, %w[id title source_type access_date], "research.sources[]")
  BossIdea.fail_with("research.sources[].access_date must be YYYY-MM-DD") unless BossIdea.valid_date?(source["access_date"])
  source["id"].to_s
end

claims = BossIdea.require_array!(frontmatter, "claims", "research")
claims.each do |claim|
  BossIdea.required_mapping!(claim, "research.claims[]")
  BossIdea.require_fields!(claim, %w[text source_ids], "research.claims[]")
  ids = Array(claim["source_ids"]).map(&:to_s)
  BossIdea.fail_with("research.claims[].source_ids must not be empty") if ids.empty?
  missing = ids - source_ids
  BossIdea.fail_with("research.claims[] references unknown sources: #{missing.join(", ")}") unless missing.empty?
end

Array(frontmatter["inferences"]).each do |inference|
  BossIdea.required_mapping!(inference, "research.inferences[]")
  BossIdea.require_fields!(inference, %w[text label source_ids], "research.inferences[]")
  unless %w[inference unknown unsupported].include?(inference["label"].to_s)
    BossIdea.fail_with("research.inferences[].label must be inference, unknown, or unsupported")
  end
end

raw_path = frontmatter["raw_evidence_path"].to_s
unless raw_path.empty? || raw_path.start_with?("agentic/reviews/") || raw_path.start_with?("agentic/runs/")
  BossIdea.fail_with("research.raw_evidence_path must stay under ignored evidence paths")
end

puts "boss idea research ok: #{path}"
RUBY
