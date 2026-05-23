#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/init-implementation-run.sh --planning-run <run-id> [--artifact <path> ...]
  scripts/init-implementation-run.sh <planning-run-id>

Environment:
  PROFILE=<profile-id>  Optional; defaults to parent planning run profile or pipeline default.
  RUN_ID=<run-id>      Optional; defaults to UTC timestamp.
USAGE
}

PROFILE="${PROFILE:-}"
RUN_ID="${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
PARENT_PLANNING_RUN=""
APPROVED_INPUTS=()

if [[ $# -eq 0 ]]; then
  usage
  exit 2
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --planning-run)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      PARENT_PLANNING_RUN="$2"
      shift 2
      ;;
    --artifact)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      APPROVED_INPUTS+=("$2")
      shift 2
      ;;
    --profile)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      PROFILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      echo "unknown option: $1" >&2
      usage
      exit 2
      ;;
    *)
      if [[ -z "$PARENT_PLANNING_RUN" && -f "agentic/runs/$1/manifest.yaml" ]]; then
        PARENT_PLANNING_RUN="$1"
      else
        APPROVED_INPUTS+=("$1")
      fi
      shift
      ;;
  esac
done

case "$RUN_ID" in
  */*|*..*)
    echo "invalid RUN_ID: $RUN_ID" >&2
    exit 2
    ;;
esac

case "$PARENT_PLANNING_RUN" in
  */*|*..*)
    echo "invalid planning run id: $PARENT_PLANNING_RUN" >&2
    exit 2
    ;;
esac

RUN_DIR="agentic/runs/$RUN_ID"
MANIFEST="$RUN_DIR/implementation-manifest.yaml"

if [[ -e "$MANIFEST" ]]; then
  echo "implementation manifest already exists: $MANIFEST" >&2
  exit 1
fi

if [[ -z "$PARENT_PLANNING_RUN" ]]; then
  echo "blocked_missing_approved_artifact: implementation runs require --planning-run <run-id>" >&2
  exit 1
fi

mkdir -p "$RUN_DIR"

approved_inputs_payload=""
if [[ "${#APPROVED_INPUTS[@]}" -gt 0 ]]; then
  approved_inputs_payload="$(printf '%s\n' "${APPROVED_INPUTS[@]}")"
fi

RUN_ID="$RUN_ID" \
PROFILE="$PROFILE" \
PARENT_PLANNING_RUN="$PARENT_PLANNING_RUN" \
APPROVED_INPUTS="$approved_inputs_payload" \
MANIFEST="$MANIFEST" \
ruby <<'RUBY'
require "yaml"
require "time"

pipeline = YAML.load_file("agentic/pipeline.yaml")
run_id = ENV.fetch("RUN_ID")
parent_planning_run = ENV["PARENT_PLANNING_RUN"].to_s
approved_inputs = ENV["APPROVED_INPUTS"].to_s.lines.map(&:strip).reject(&:empty?)
manifest_path = ENV.fetch("MANIFEST")
now = Time.now.utc.iso8601

parent_manifest = nil
if !parent_planning_run.empty?
  parent_manifest_path = File.join("agentic/runs", parent_planning_run, "manifest.yaml")
  unless File.file?(parent_manifest_path)
    warn "parent planning manifest not found: #{parent_manifest_path}"
    exit 1
  end
  parent_manifest = YAML.load_file(parent_manifest_path)
end

profile_id = if !ENV["PROFILE"].to_s.empty?
  ENV.fetch("PROFILE")
elsif parent_manifest
  parent_manifest.dig("run", "profile")
else
  pipeline.fetch("pipeline").fetch("default_profile")
end

if profile_id.to_s.empty?
  warn "profile is required"
  exit 1
end

profile_path = File.join(pipeline.fetch("pipeline").fetch("profile_dir"), "#{profile_id}.yaml")
unless File.file?(profile_path)
  warn "profile not found: #{profile_path}"
  exit 1
end

profile = YAML.load_file(profile_path)

if approved_inputs.empty? && parent_manifest
  approved_inputs = Array(parent_manifest["artifacts"]).select do |artifact|
    artifact["status"].to_s == "approved"
  end.map { |artifact| artifact["path"] }.compact
end

if parent_manifest && !approved_inputs.empty?
  artifact_status_by_path = {}
  Array(parent_manifest["artifacts"]).each do |artifact|
    next unless artifact.is_a?(Hash)
    artifact_status_by_path[artifact["path"].to_s] = artifact["status"].to_s
  end

  unapproved = approved_inputs.uniq.reject { |path| artifact_status_by_path[path] == "approved" }
  unless unapproved.empty?
    warn "blocked_missing_approved_artifact: explicit artifact is not approved in parent planning run"
    unapproved.each { |path| warn "not approved in parent manifest: #{path}" }
    exit 1
  end
end

if approved_inputs.empty?
  warn "blocked_missing_approved_artifact: no approved artifacts supplied or discoverable from parent planning run"
  warn "approve at least one parent artifact with: scripts/update-artifact-status.sh #{parent_planning_run.empty? ? "<planning-run-id>" : parent_planning_run} <artifact-path> approved --reason <text>"
  exit 1
end

missing = approved_inputs.uniq.reject { |path| File.file?(path) }
unless missing.empty?
  missing.each { |path| warn "approved input not found: #{path}" }
  exit 1
end

def role_for(path)
  case path
  when %r{\Adocs/adr/} then "adr"
  when %r{\Adocs/backlog/} then "roadmap"
  when %r{\Adocs/connectors/} then "schema"
  when %r{\Adocs/reviews/} then "decision_log"
  when %r{\Adocs/architecture/} then "architecture"
  else "other"
  end
end

approved_input_records = approved_inputs.uniq.map do |path|
  parent_artifact = nil
  if parent_manifest
    parent_artifact = Array(parent_manifest["artifacts"]).find do |artifact|
      artifact.is_a?(Hash) && artifact["path"].to_s == path
    end
  end

  {
    "path" => path,
    "role" => role_for(path),
    "approval_source" => "parent_planning_run",
    "approval_state" => "approved_for_implementation",
    "artifact_status" => parent_artifact ? parent_artifact["status"] : nil,
    "approval_reason" => parent_artifact ? parent_artifact["decision_reason"] : nil
  }
end

tasks = approved_input_records.each_with_index.map do |input, idx|
  task_id = format("impl-%03d", idx + 1)
  review_path = "agentic/reviews/auto-doc-to-implementation/h18/#{run_id}/#{task_id}/round-<n>.json"
  {
    "task_id" => task_id,
    "title" => "Implement approved changes from #{input["path"]}",
    "owner" => "implementation_agent",
    "state" => "planned",
    "source_artifact" => input["path"],
    "scope" => "Apply the approved requirements in #{input["path"]} without expanding the delivery boundary.",
    "files_touched" => [input["path"]],
    "write_scope" => [input["path"]],
    "acceptance_criteria" => [
      "Implementation conforms to #{input["path"]}.",
      "Changes preserve profile source of truth and rejected directions.",
      "Relevant validation and tests pass before PR readiness."
    ],
    "affected_paths" => [input["path"]],
    "validation_command" => "scripts/validate-agentic-system.sh && scripts/validate-implementation-run.sh #{run_id}",
    "rollback_notes" => "Revert changes made for #{task_id} and rerun implementation validation.",
    "ait_review_path" => review_path,
    "dependencies" => idx.zero? ? [] : [format("impl-%03d", idx)],
    "risks" => []
  }
end

implementation_task_graph = {
  "generated_at" => now,
  "generated_by" => "scripts/init-implementation-run.sh",
  "approved_input_count" => approved_input_records.length,
  "task_count" => tasks.length,
  "tasks" => tasks.map { |task| task["task_id"] }
}

manifest = {
  "schema_version" => 1,
  "run" => {
    "id" => run_id,
    "profile" => profile_id,
    "profile_path" => profile_path,
    "mode" => "implementation",
    "state" => "implementation_planned",
    "parent_planning_run" => parent_planning_run.empty? ? nil : parent_planning_run,
    "created_at" => now,
    "updated_at" => now,
    "state_history" => [
      {
        "state" => "implementation_planned",
        "at" => now
      }
    ]
  },
  "source_of_truth" => profile.fetch("source_of_truth", []),
  "approved_inputs" => approved_input_records,
  "implementation_tasks" => tasks,
  "implementation_task_graph" => implementation_task_graph,
  "branch_plan" => {
    "base_branch" => nil,
    "working_branch" => "agentic/#{run_id}",
    "commit_strategy" => "Keep implementation commits scoped to approved inputs.",
    "pr_target" => nil
  },
  "code_ownership" => tasks.map do |task|
    {
      "owner" => task["owner"],
      "task_id" => task["task_id"],
      "paths" => task["write_scope"],
      "source_artifacts" => [task["source_artifact"]]
    }
  end,
  "test_plan" => [
    {
      "test_id" => "agentic-system-validation",
      "command" => "scripts/validate-agentic-system.sh",
      "coverage_goal" => "Validate delivery system scaffold, profile files, YAML, and shell syntax.",
      "required" => true
    }
  ],
  "pr_checklist" => [
    "Approved inputs are referenced in the PR description.",
    "Implementation tasks have acceptance criteria and validation evidence.",
    "Tests and rollback notes are included.",
    "No profile source-of-truth boundary is changed without human approval."
  ],
  "review_attempts" => [],
  "worker_dispatches" => [],
  "worker_results" => [],
  "write_scope_leases" => [],
  "validation" => [],
  "release_notes" => {
    "path" => File.join("agentic/runs", run_id, "release-notes.md"),
    "status" => "draft_pending",
    "summary" => nil,
    "operator_notes" => []
  }
}

File.write(manifest_path, manifest.to_yaml)
RUBY

echo "$RUN_ID"
echo "implementation manifest: $MANIFEST"
