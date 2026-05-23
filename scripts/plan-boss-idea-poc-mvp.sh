#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

WORK_TYPE="${1:-poc}"
SCHEMA="agentic/schemas/boss-idea-poc-mvp.schema.yaml"

case "$WORK_TYPE" in
  -h|--help)
    echo "usage: scripts/plan-boss-idea-poc-mvp.sh [poc|mvp]" >&2
    exit 0
    ;;
esac

WORK_TYPE="$WORK_TYPE" SCHEMA="$SCHEMA" ruby <<'RUBY'
require File.expand_path("scripts/lib/boss_idea", Dir.pwd)

work_type = ENV.fetch("WORK_TYPE")
schema = BossIdea.load_yaml(ENV.fetch("SCHEMA")).fetch("schema")
allowed = Array(schema["allowed_work_types"]).map(&:to_s)
BossIdea.fail_with("work type must be #{allowed.join(" or ")}", 2) unless allowed.include?(work_type)

max_days = schema.dig("timebox_days", "max_by_work_type", work_type).to_i
timebox_days = work_type == "mvp" ? [15, max_days].min : [5, max_days].min
staffing = work_type == "mvp" ? "one implementation owner, one reviewer, and one product owner" : "one implementation owner and one reviewer"
decision = "stop"

puts <<~MARKDOWN
---
work_type: #{work_type}
timebox_days: #{timebox_days}
staffing_assumption: #{staffing}
scope_in:
  - Demonstrate one approved workflow.
scope_out:
  - Production deployment.
demo_path: docs/demo/boss-idea-demo.md
validation_command: scripts/validate-agentic-system.sh
acceptance_criteria:
  - Demo path can be reviewed from tracked artifacts.
  - Validation command passes before decision review.
rollback_notes: Revert generated POC or MVP changes and keep decision evidence.
decision_after_timebox: #{decision}
---
# POC MVP Timebox Plan
MARKDOWN
RUBY
