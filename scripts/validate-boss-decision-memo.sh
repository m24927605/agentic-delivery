#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ $# -ne 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  echo "usage: scripts/validate-boss-decision-memo.sh <memo.md>" >&2
  exit 2
fi

MEMO_FILE="$1" ruby <<'RUBY'
require File.expand_path("scripts/lib/boss_idea", Dir.pwd)

path = ENV.fetch("MEMO_FILE")
frontmatter, body, sections = BossIdea.load_markdown(path)
BossIdea.required_mapping!(frontmatter, "memo frontmatter")
schema = BossIdea.load_yaml("agentic/schemas/boss-decision-memo.schema.yaml").fetch("schema")

Array(schema["required_sections"]).each { |name| BossIdea.require_section!(sections, name, "memo") }

frontmatter_recommendation = frontmatter["recommendation"].to_s.strip
body_recommendation = sections["recommendation"].to_s.lines.find { |line| !line.strip.empty? }.to_s.strip
if !frontmatter_recommendation.empty? && !body_recommendation.empty? && frontmatter_recommendation != body_recommendation
  BossIdea.fail_with("memo recommendation mismatch between frontmatter and body")
end

recommendation = frontmatter_recommendation.empty? ? body_recommendation : frontmatter_recommendation
allowed = Array(schema["allowed_recommendations"]).map(&:to_s)
BossIdea.fail_with("memo recommendation is invalid: #{recommendation}") unless allowed.include?(recommendation)

time_staffing = sections["time_and_staffing"].to_s
if %w[poc mvp].include?(recommendation)
  timebox = time_staffing[/^\s*timebox\s*:\s*(.+)$/i, 1].to_s.strip
  staffing = time_staffing[/^\s*staffing\s*:\s*(.+)$/i, 1].to_s.strip
  BossIdea.fail_with("POC/MVP memo requires Timebox") unless timebox =~ /\A\d+\s+(business\s+)?(day|days|week|weeks)\z/i
  BossIdea.fail_with("POC/MVP memo requires Staffing") if staffing.length < 5 || staffing =~ /\A(tbd|\?|n\/a)\z/i
end

artifact_status = frontmatter["artifact_status"].to_s.strip
allowed_statuses = Array(schema["artifact_statuses"]).map(&:to_s)
BossIdea.fail_with("memo artifact_status is invalid: #{artifact_status}") unless allowed_statuses.include?(artifact_status)

approval_pattern = Regexp.new(schema.fetch("implementation_approval_assertion_pattern"), Regexp::IGNORECASE)
if body.each_line.any? { |line| line.match?(approval_pattern) } && artifact_status != "approved"
  BossIdea.fail_with("memo cannot claim approval without approved artifact status")
end

puts "boss decision memo ok: #{path}"
RUBY
