#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/generate-boss-decision-memo.sh [--recommendation <band>] [--output <path>] <run-id>
USAGE
}

OUTPUT=""
RECOMMENDATION="poc"
RUN_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      OUTPUT="$2"
      shift 2
      ;;
    --recommendation)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      RECOMMENDATION="$2"
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

RUN_ID="$RUN_ID" OUTPUT="$OUTPUT" RECOMMENDATION="$RECOMMENDATION" ruby <<'RUBY'
require File.expand_path("scripts/lib/boss_idea", Dir.pwd)
require "pathname"

run_id = ENV.fetch("RUN_ID")
BossIdea.fail_with("invalid run id: #{run_id}", 2) unless BossIdea.repo_local_path?(run_id) && !run_id.include?("/")

schema = BossIdea.load_yaml("agentic/schemas/boss-decision-memo.schema.yaml").fetch("schema")
recommendation = ENV.fetch("RECOMMENDATION")
allowed_recommendations = Array(schema["allowed_recommendations"]).map(&:to_s)
BossIdea.fail_with("invalid recommendation: #{recommendation}", 2) unless allowed_recommendations.include?(recommendation)

manifest_path = "agentic/runs/#{run_id}/manifest.yaml"
BossIdea.fail_with("blocked_missing_source: #{manifest_path}") unless File.file?(manifest_path)
manifest = YAML.safe_load(File.read(manifest_path), permitted_classes: [Date], aliases: true) || {}
BossIdea.required_mapping!(manifest, "planning manifest")
run = BossIdea.required_mapping!(manifest["run"], "planning manifest.run")
BossIdea.fail_with("blocked_schema_invalid: manifest run.id does not match #{run_id}") unless run["id"].to_s == run_id
BossIdea.fail_with("blocked_schema_invalid: manifest profile must be boss-idea-response") unless run["profile"].to_s == "boss-idea-response"
BossIdea.require_array!(manifest, "artifacts", "planning manifest")

timebox = recommendation == "mvp" ? "10 business days" : "5 business days"
staffing = recommendation == "mvp" ? "one implementation owner, one reviewer, and one product owner" : "one implementation owner and one reviewer"
recommended_path = case recommendation
                   when "do"
                     "Prepare implementation only after approved artifacts and go/no-go decision."
                   when "defer"
                     "Defer implementation until material unknowns are resolved."
                   when "no_go"
                     "Do not proceed; record the reason and stop implementation planning."
                   when "research_more"
                     "Run additional cited research before choosing POC or MVP."
                   when "mvp"
                     "Run a tightly scoped MVP only after artifacts are approved."
                   else
                     "Run a timeboxed POC only after artifacts are approved."
                   end

memo = <<~MARKDOWN
  ---
  recommendation: #{recommendation}
  artifact_status: drafted
  ---
  # Boss Decision Memo

  ## Recommendation
  #{recommendation}

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
  #{recommended_path}

  ## Time And Staffing
  Timebox: #{timebox}
  Staffing: #{staffing}

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
  output_dir = File.dirname(output)
  FileUtils.mkdir_p(output_dir)
  BossIdea.fail_with("invalid output path: #{output}", 2) unless BossIdea.within_repo_root?(output_dir)
  root = Pathname.new(Dir.pwd).realpath.to_s
  target = Pathname.new(File.expand_path(output, Dir.pwd)).cleanpath.to_s
  BossIdea.fail_with("invalid output path: #{output}", 2) unless target == root || target.start_with?("#{root}/")
  File.write(output, memo)
  puts "boss decision memo generated: #{output}"
end
RUBY
