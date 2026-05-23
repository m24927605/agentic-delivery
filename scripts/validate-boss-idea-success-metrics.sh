#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ $# -ne 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  echo "usage: scripts/validate-boss-idea-success-metrics.sh <metrics.yaml>" >&2
  exit 2
fi

METRICS_FILE="$1" ruby <<'RUBY'
require File.expand_path("scripts/lib/boss_idea", Dir.pwd)

path = ENV.fetch("METRICS_FILE")
data = BossIdea.load_yaml(path)
BossIdea.required_mapping!(data, "success_metrics")
metrics = BossIdea.require_array!(data, "metrics", "success_metrics")
plan_timebox_days = data["plan_timebox_days"]

metrics.each_with_index do |metric, index|
  BossIdea.required_mapping!(metric, "success_metrics.metrics[#{index}]")
  BossIdea.require_fields!(metric, %w[name method threshold owner_role decision_mapping evidence_path timebox_days], "success_metrics.metrics[#{index}]")
  BossIdea.fail_with("metric evidence_path must be ignored or public-safe") unless BossIdea.ignored_or_public_evidence_path?(metric["evidence_path"])
  days = metric["timebox_days"]
  BossIdea.fail_with("metric timebox_days must be a positive integer") unless days.is_a?(Integer) && days.positive?
  if plan_timebox_days.is_a?(Integer) && days > plan_timebox_days
    BossIdea.fail_with("metric timebox_days exceeds selected plan timebox")
  end
  BossIdea.fail_with("metric output cannot automatically record go/no-go") if metric["auto_decision"] == true
end

puts "boss idea success metrics ok: #{path}"
RUBY
