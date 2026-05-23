#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/generate-boss-decision-memo.sh [--output <path>] <run-id>
USAGE
}

OUTPUT=""
RUN_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      OUTPUT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      echo "unknown option: $1" >&2
      exit 2
      ;;
    *)
      RUN_ID="$1"
      shift
      ;;
  esac
done

if [[ -z "$RUN_ID" ]]; then
  usage
  exit 2
fi

RUN_ID="$RUN_ID" OUTPUT="$OUTPUT" ruby <<'RUBY'
require File.expand_path("scripts/lib/boss_idea", Dir.pwd)

run_id = ENV.fetch("RUN_ID")
BossIdea.fail_with("invalid run id: #{run_id}", 2) unless BossIdea.repo_local_path?(run_id) && !run_id.include?("/")

memo = <<~MARKDOWN
  ---
  recommendation: poc
  artifact_status: drafted
  ---
  # Boss Decision Memo

  ## Recommendation
  poc

  ## Decision Needed
  Decide whether to approve a bounded POC plan.

  ## Context
  Generated from planning run #{run_id}.

  ## Evidence Summary
  Link reviewed intake, research, and scorecard artifacts here.

  ## Options Considered
  - do
  - defer
  - no_go
  - poc

  ## Recommended Path
  Run a timeboxed POC only after artifacts are approved.

  ## Time And Staffing
  Timebox: 5 business days
  Staffing: one implementation owner and one reviewer

  ## Risks And Unknowns
  Record material unknowns before approval.

  ## Success Metrics
  Record measurable POC success metrics.

  ## Next Step
  Review and approve the memo artifact before implementation consumes it.
MARKDOWN

output = ENV["OUTPUT"].to_s
if output.empty?
  puts memo
else
  BossIdea.fail_with("invalid output path: #{output}", 2) unless BossIdea.repo_local_path?(output)
  FileUtils.mkdir_p(File.dirname(output))
  File.write(output, memo)
  puts "boss decision memo generated: #{output}"
end
RUBY
