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

[
  "Recommendation",
  "Decision Needed",
  "Context",
  "Evidence Summary",
  "Options Considered",
  "Recommended Path",
  "Time And Staffing",
  "Risks And Unknowns",
  "Success Metrics",
  "Next Step"
].each { |name| BossIdea.require_section!(sections, name, "memo") }

recommendation = frontmatter["recommendation"].to_s
recommendation = sections["recommendation"].to_s.lines.first.to_s.strip if recommendation.empty?
allowed = %w[do defer no_go poc mvp]
BossIdea.fail_with("memo recommendation is invalid: #{recommendation}") unless allowed.include?(recommendation)

time_staffing = sections["time_and_staffing"].to_s
if %w[poc mvp].include?(recommendation)
  BossIdea.fail_with("POC/MVP memo requires Timebox") unless time_staffing =~ /timebox\s*:/i
  BossIdea.fail_with("POC/MVP memo requires Staffing") unless time_staffing =~ /staffing\s*:/i
end

artifact_status = frontmatter["artifact_status"].to_s
if body =~ /approved for implementation/i && artifact_status != "approved"
  BossIdea.fail_with("memo cannot claim approval without approved artifact status")
end

puts "boss decision memo ok: #{path}"
RUBY
