#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DRY_RUN=0
SCORECARD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      echo "usage: scripts/score-boss-idea-feasibility.sh [--dry-run] <scorecard.yaml>" >&2
      exit 0
      ;;
    --*)
      echo "unknown option: $1" >&2
      exit 2
      ;;
    *)
      SCORECARD="$1"
      shift
      ;;
  esac
done

if [[ -z "$SCORECARD" ]]; then
  echo "usage: scripts/score-boss-idea-feasibility.sh [--dry-run] <scorecard.yaml>" >&2
  exit 2
fi

SCORECARD="$SCORECARD" DRY_RUN="$DRY_RUN" ruby <<'RUBY'
require File.expand_path("scripts/lib/boss_idea", Dir.pwd)

path = ENV.fetch("SCORECARD")
data = BossIdea.load_yaml(path)
BossIdea.required_mapping!(data, "scorecard")
schema = BossIdea.load_yaml("agentic/schemas/boss-idea-scorecard.schema.yaml").fetch("schema")

score_fields = Array(schema["higher_is_better"]) + Array(schema["higher_is_worse"])
range = schema.fetch("score_range")
min_score = Integer(range.fetch("min"))
max_score = Integer(range.fetch("max"))

BossIdea.require_fields!(data, Array(schema["required_fields"]), "scorecard")

score_fields.each do |field|
  value = data[field]
  unless value.is_a?(Integer) && value.between?(min_score, max_score)
    BossIdea.fail_with("scorecard.#{field} must be an integer from #{min_score} to #{max_score}")
  end
end

allowed_bands = Array(schema["recommendation_bands"]).map(&:to_s)
unless allowed_bands.include?(data["recommendation_band"].to_s)
  BossIdea.fail_with("scorecard.recommendation_band is invalid: #{data["recommendation_band"]}")
end

high_risk_threshold = Integer(schema.fetch("high_risk_threshold"))
if Array(schema["high_risk_fields"]).any? { |field| data[field].to_i >= high_risk_threshold }
  BossIdea.require_array!(data, "mitigations", "scorecard")
end

low_confidence_threshold = Integer(schema.fetch("low_confidence_threshold"))
if Array(schema["low_confidence_fields"]).any? { |field| data[field].to_i <= low_confidence_threshold }
  support_count = Array(schema["low_confidence_support_fields"]).sum do |field|
    value = data[field]
    next 0 if value.nil?
    unless value.is_a?(Array)
      BossIdea.fail_with("scorecard.#{field} must be an array")
    end
    value.length
  end
  BossIdea.fail_with("low confidence requires unknowns or follow_up_questions") if support_count.zero?
end

if data["implementation_approval"] == true || data["artifact_status"].to_s == "approved"
  BossIdea.fail_with("scorecard cannot approve implementation")
end

mode = ENV.fetch("DRY_RUN") == "1" ? "dry-run" : "validate"
puts "boss idea feasibility ok: #{path} (#{mode})"
RUBY
