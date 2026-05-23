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

score_fields = %w[
  value_score
  urgency_score
  effort_score
  technical_risk_score
  security_risk_score
  market_confidence_score
  implementation_confidence_score
  reversibility_score
  dependency_score
]

BossIdea.require_fields!(data, score_fields + %w[score_rationale recommendation_band], "scorecard")

score_fields.each do |field|
  value = data[field]
  unless value.is_a?(Integer) && value.between?(1, 5)
    BossIdea.fail_with("scorecard.#{field} must be an integer from 1 to 5")
  end
end

if data["technical_risk_score"].to_i >= 4 || data["security_risk_score"].to_i >= 4
  BossIdea.require_array!(data, "mitigations", "scorecard")
end

if data["market_confidence_score"].to_i <= 2 || data["implementation_confidence_score"].to_i <= 2
  unknowns = Array(data["unknowns"])
  follow_ups = Array(data["follow_up_questions"])
  BossIdea.fail_with("low confidence requires unknowns or follow_up_questions") if unknowns.empty? && follow_ups.empty?
end

if data["implementation_approval"] == true || data["artifact_status"].to_s == "approved"
  BossIdea.fail_with("scorecard cannot approve implementation")
end

puts "boss idea feasibility ok: #{path}"
RUBY
