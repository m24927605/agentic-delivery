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
BossIdea.require_fields!(frontmatter, %w[work_type timebox_days demo_path validation_command rollback_notes], "poc_mvp")
BossIdea.require_array!(frontmatter, "scope_in", "poc_mvp")
BossIdea.require_array!(frontmatter, "scope_out", "poc_mvp")

BossIdea.fail_with("poc_mvp.work_type must be poc or mvp") unless %w[poc mvp].include?(frontmatter["work_type"].to_s)
days = frontmatter["timebox_days"]
BossIdea.fail_with("poc_mvp.timebox_days must be a positive integer") unless days.is_a?(Integer) && days.positive?
BossIdea.fail_with("poc_mvp.demo_path must be repo-local") unless BossIdea.repo_local_path?(frontmatter["demo_path"])
BossIdea.fail_with("poc_mvp.validation_command must be a repo-local script command") unless BossIdea.safe_command?(frontmatter["validation_command"])

puts "boss idea poc mvp ok: #{path}"
RUBY
