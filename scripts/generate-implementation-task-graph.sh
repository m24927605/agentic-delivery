#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/generate-implementation-task-graph.sh [--dry-run] <implementation-run-id>
USAGE
}

DRY_RUN=0

if [[ $# -gt 0 && "$1" == "--dry-run" ]]; then
  DRY_RUN=1
  shift
fi

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

RUN_ID="$1"

case "$RUN_ID" in
  */*|*..*|"")
    echo "invalid run id: $RUN_ID" >&2
    exit 2
    ;;
esac

MANIFEST="agentic/runs/$RUN_ID/implementation-manifest.yaml"

if [[ ! -f "$MANIFEST" ]]; then
  echo "implementation manifest not found: $MANIFEST" >&2
  exit 1
fi

RUN_ID="$RUN_ID" MANIFEST="$MANIFEST" DRY_RUN="$DRY_RUN" ruby <<'RUBY'
require "time"
require "yaml"

run_id = ENV.fetch("RUN_ID")
manifest_path = ENV.fetch("MANIFEST")
dry_run = ENV.fetch("DRY_RUN") == "1"
manifest = YAML.load_file(manifest_path)
run = manifest["run"] || {}
now = Time.now.utc.iso8601

unless run["id"].to_s == run_id
  warn "run.id mismatch: expected #{run_id}, got #{run["id"] || "(empty)"}"
  exit 1
end

unless run["mode"].to_s == "implementation"
  warn "run.mode must be implementation"
  exit 1
end

approved_inputs = Array(manifest["approved_inputs"]).select { |input| input.is_a?(Hash) }
if approved_inputs.empty?
  warn "blocked_missing_approved_artifact: implementation task graph requires approved inputs"
  exit 1
end

def repo_local_path?(path)
  return false if path.to_s.empty?
  return false if path.start_with?("/")
  return false if path.split("/").include?("..")
  File.file?(path)
end

errors = []
tasks = approved_inputs.each_with_index.map do |input, idx|
  path = input["path"].to_s
  errors << "approved input path is not repo-local: #{path}" unless repo_local_path?(path)
  task_id = format("impl-%03d", idx + 1)
  review_path = "agentic/reviews/auto-doc-to-implementation/h18/#{run_id}/#{task_id}/round-<n>.json"
  {
    "task_id" => task_id,
    "title" => "Implement approved artifact #{path}",
    "owner" => "implementation_agent",
    "state" => "planned",
    "source_artifact" => path,
    "scope" => "Apply the approved requirements in #{path} without expanding the delivery boundary.",
    "files_touched" => [path],
    "write_scope" => [path],
    "acceptance_criteria" => [
      "Implementation traces back to approved artifact #{path}.",
      "No private profile identifiers, customer details, secrets, or review trace metadata are introduced.",
      "Validation command passes before PR package preparation."
    ],
    "validation_command" => "scripts/validate-agentic-system.sh && scripts/validate-implementation-run.sh #{run_id}",
    "rollback_notes" => "Revert files touched by #{task_id} and rerun implementation validation.",
    "ait_review_path" => review_path,
    "dependencies" => idx.zero? ? [] : [format("impl-%03d", idx)],
    "risks" => [],
    "public_safety" => {
      "repo_local_paths_only" => true,
      "private_profile_identifiers_allowed" => false
    }
  }
end

unless errors.empty?
  errors.each { |error| warn error }
  exit 1
end

graph = {
  "generated_at" => now,
  "generated_by" => "scripts/generate-implementation-task-graph.sh",
  "approved_input_count" => approved_inputs.length,
  "task_count" => tasks.length,
  "tasks" => tasks.map { |task| task["task_id"] }
}

if dry_run
  puts({ "implementation_task_graph" => graph, "implementation_tasks" => tasks }.to_yaml)
else
  manifest["implementation_tasks"] = tasks
  manifest["implementation_task_graph"] = graph
  manifest["code_ownership"] = tasks.map do |task|
    {
      "owner" => task["owner"],
      "task_id" => task["task_id"],
      "paths" => task["write_scope"],
      "source_artifacts" => [task["source_artifact"]]
    }
  end
  manifest["run"]["state"] = "implementation_task_graph_ready"
  manifest["run"]["updated_at"] = now
  manifest["run"]["state_history"] = Array(manifest["run"]["state_history"])
  manifest["run"]["state_history"] << {
    "state" => "implementation_task_graph_ready",
    "at" => now
  }
  File.write(manifest_path, manifest.to_yaml)
end

puts "implementation task graph ok: #{run_id} tasks=#{tasks.length} dry_run=#{dry_run}"
RUBY
