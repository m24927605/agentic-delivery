#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ $# -ne 1 ]]; then
  echo "usage: scripts/report-run-status.sh <run-id>" >&2
  exit 2
fi

RUN_ID="$1"

case "$RUN_ID" in
  */*|*..*|"")
    echo "invalid run id: $RUN_ID" >&2
    exit 2
    ;;
esac

RUN_ID="$RUN_ID" ruby <<'RUBY'
require "yaml"

run_id = ENV.fetch("RUN_ID")
planning_manifest = File.join("agentic/runs", run_id, "manifest.yaml")
implementation_manifest = File.join("agentic/runs", run_id, "implementation-manifest.yaml")

existing_manifests = [planning_manifest, implementation_manifest].select { |path| File.file?(path) }

if existing_manifests.empty?
  warn "manifest not found: #{planning_manifest} or #{implementation_manifest}"
  exit 1
end

if existing_manifests.length > 1
  warn "ambiguous run id: both planning and implementation manifests exist for #{run_id}"
  existing_manifests.each { |path| warn "found: #{path}" }
  exit 1
end

manifest_path = existing_manifests.first
manifest = YAML.load_file(manifest_path)
run = manifest["run"] || {}

manifest_run_id = run["id"].to_s
if manifest_run_id != run_id
  warn "run.id mismatch: expected #{run_id}, got #{manifest_run_id.empty? ? "(empty)" : manifest_run_id}"
  exit 1
end

mode = if manifest_path.end_with?("implementation-manifest.yaml")
  "implementation"
elsif !run["mode"].to_s.empty? && run["mode"].to_s != "planning"
  warn "planning manifest run.mode conflicts with manifest path: #{run["mode"]}"
  exit 1
else
  run["mode"].to_s.empty? ? "planning" : run["mode"].to_s
end

unless %w[planning implementation].include?(mode)
  warn "unsupported run.mode: #{mode}"
  exit 1
end

profile = run["profile"].to_s
state = run["state"].to_s
parent_planning_run = run["parent_planning_run"]
review_attempts_count = Array(manifest["review_attempts"]).length
validation_count = Array(manifest["validation"]).length

if mode == "implementation"
  artifacts_total = Array(manifest["approved_inputs"]).length
  artifacts_approved = artifacts_total
  artifacts_pending = 0
  artifacts_rejected = 0
  artifacts_deferred = 0
else
  artifacts = Array(manifest["artifacts"])
  artifacts_total = artifacts.length
  artifacts_approved = artifacts.count { |artifact| artifact.is_a?(Hash) && artifact["status"].to_s == "approved" }
  artifacts_rejected = artifacts.count { |artifact| artifact.is_a?(Hash) && artifact["status"].to_s == "rejected" }
  artifacts_deferred = artifacts.count { |artifact| artifact.is_a?(Hash) && artifact["status"].to_s == "deferred" }
  artifacts_pending = artifacts_total - artifacts_approved - artifacts_rejected - artifacts_deferred
end

def next_action_for(mode, state, review_attempts_count)
  failure_state = state.start_with?("blocked_")
  return "blocked_human_decision_required" if failure_state

  case mode
  when "planning"
    case state
    when "initialized"
      "generate_artifacts"
    when "draft_artifacts_ready"
      "run_artifact_review_loop"
    when "schema_validation_passed"
      "run_agency_review"
    when "agency_review_running"
      "run_agency_review"
    when "agency_review_completed"
      review_attempts_count.positive? ? "summarize_review" : "run_agency_review"
    when "artifact_review_loop_completed", "strategy_loaded", "artifact_plan_created", "research_in_progress", "integration_in_progress", "final_artifacts_ready"
      "report_run_status"
    when "delivered"
      "none"
    else
      "report_run_status"
    end
  when "implementation"
    case state
    when "implementation_planned"
      "generate_implementation_task_graph"
    when "implementation_task_graph_ready"
      "dispatch_implementation_task"
    when "worker_dispatch_ready", "branch_prepared", "code_changes_ready", "tests_running", "tests_passed", "implementation_review_ready", "pr_ready"
      "validate_implementation_run"
    when "release_ready"
      "none"
    else
      "report_run_status"
    end
  end
end

status = {
  "run_status" => {
    "run_id" => run_id,
    "mode" => mode,
    "profile" => profile.empty? ? nil : profile,
    "state" => state.empty? ? nil : state,
    "parent_planning_run" => parent_planning_run,
    "manifest" => manifest_path,
    "artifacts_or_approved_inputs_count" => artifacts_total,
    "artifacts_total" => artifacts_total,
    "artifacts_approved" => artifacts_approved,
    "artifacts_pending" => artifacts_pending,
    "artifacts_rejected" => artifacts_rejected,
    "artifacts_deferred" => artifacts_deferred,
    "review_attempts_count" => review_attempts_count,
    "validation_count" => validation_count,
    "next_suggested_action" => next_action_for(mode, state, review_attempts_count)
  }
}

puts status.to_yaml
RUBY
