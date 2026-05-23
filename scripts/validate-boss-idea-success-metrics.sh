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
schema = BossIdea.load_yaml("agentic/schemas/boss-idea-success-metrics.schema.yaml").fetch("schema")
BossIdea.require_fields!(data, Array(schema["required_fields"]), "success_metrics")
metrics = BossIdea.require_array!(data, "metrics", "success_metrics")
plan_timebox_days = data["plan_timebox_days"]
min_days = Integer(schema.dig("timebox_days", "min"))
unless plan_timebox_days.is_a?(Integer) && plan_timebox_days >= min_days
  BossIdea.fail_with("success_metrics.plan_timebox_days must be a positive integer")
end

metrics.each_with_index do |metric, index|
  BossIdea.required_mapping!(metric, "success_metrics.metrics[#{index}]")
  BossIdea.require_fields!(metric, Array(schema["metric_required_fields"]), "success_metrics.metrics[#{index}]")
  decision_mapping = BossIdea.required_mapping!(metric["decision_mapping"], "success_metrics.metrics[#{index}].decision_mapping")
  BossIdea.require_fields!(decision_mapping, Array(schema["decision_mapping_required_fields"]), "success_metrics.metrics[#{index}].decision_mapping")
  if schema["evidence_path_policy"].to_s == "ignored_or_public"
    BossIdea.fail_with("metric evidence_path must be ignored or public-safe") unless BossIdea.ignored_or_public_evidence_path?(metric["evidence_path"])
  end
  days = metric["timebox_days"]
  BossIdea.fail_with("metric timebox_days must be a positive integer") unless days.is_a?(Integer) && days >= min_days
  if schema.dig("timebox_days", "must_not_exceed_plan_timebox") == true && days > plan_timebox_days
    BossIdea.fail_with("metric timebox_days exceeds selected plan timebox")
  end
  auto_decision = metric["auto_decision"]
  allowed_auto_decisions = Array(schema["auto_decision_allowed_values"])
  unless auto_decision.nil? || allowed_auto_decisions.include?(auto_decision)
    BossIdea.fail_with("metric output cannot automatically record go/no-go")
  end
end

puts "boss idea success metrics ok: #{path}"
RUBY
