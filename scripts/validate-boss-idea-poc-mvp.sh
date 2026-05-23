#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ $# -ne 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  echo "usage: scripts/validate-boss-idea-poc-mvp.sh <plan.md>" >&2
  exit 2
fi

PLAN_FILE="$1" ruby <<'RUBY'
require File.expand_path("scripts/lib/boss_idea", Dir.pwd)

path = ENV.fetch("PLAN_FILE")
frontmatter, = BossIdea.load_markdown(path)
BossIdea.required_mapping!(frontmatter, "poc_mvp frontmatter")
schema = BossIdea.load_yaml("agentic/schemas/boss-idea-poc-mvp.schema.yaml").fetch("schema")
BossIdea.require_fields!(frontmatter, Array(schema["required_fields"]), "poc_mvp")
BossIdea.require_array!(frontmatter, "scope_in", "poc_mvp")
BossIdea.require_array!(frontmatter, "scope_out", "poc_mvp")
BossIdea.require_array!(frontmatter, "acceptance_criteria", "poc_mvp")

allowed_work_types = Array(schema["allowed_work_types"]).map(&:to_s)
work_type = frontmatter["work_type"].to_s
BossIdea.fail_with("poc_mvp.work_type must be #{allowed_work_types.join(" or ")}") unless allowed_work_types.include?(work_type)
days = frontmatter["timebox_days"]
min_days = schema.dig("timebox_days", "min").to_i
max_days = schema.dig("timebox_days", "max_by_work_type", work_type).to_i
unless days.is_a?(Integer) && days >= min_days && days <= max_days
  BossIdea.fail_with("poc_mvp.timebox_days must be an integer from #{min_days} to #{max_days} for #{work_type}")
end
staffing = frontmatter["staffing_assumption"].to_s.strip
BossIdea.fail_with("poc_mvp.staffing_assumption is required") if staffing.empty?
BossIdea.fail_with("poc_mvp.demo_path must be repo-local") unless BossIdea.repo_local_path?(frontmatter["demo_path"])
BossIdea.fail_with("poc_mvp.validation_command must be a repo-local script command") unless BossIdea.safe_command?(frontmatter["validation_command"])
decision = frontmatter["decision_after_timebox"].to_s
allowed_decisions = Array(schema["decision_after_timebox_values"]).map(&:to_s)
BossIdea.fail_with("poc_mvp.decision_after_timebox is invalid: #{decision}") unless allowed_decisions.include?(decision)

production_patterns = Array(schema["production_scope_patterns"]).map { |value| Regexp.new(Regexp.escape(value.to_s), Regexp::IGNORECASE) }
scope_in_text = Array(frontmatter["scope_in"]).join("\n")
if production_patterns.any? { |pattern| scope_in_text.match?(pattern) }
  BossIdea.fail_with("poc_mvp.scope_in cannot include production launch or deployment")
end

puts "boss idea poc mvp ok: #{path}"
RUBY
