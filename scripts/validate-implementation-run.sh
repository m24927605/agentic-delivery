#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ $# -ne 1 ]]; then
  echo "usage: scripts/validate-implementation-run.sh <run-id>" >&2
  exit 2
fi

RUN_ID="$1"
MANIFEST="agentic/runs/$RUN_ID/implementation-manifest.yaml"

case "$RUN_ID" in
  */*|*..*)
    echo "invalid run id: $RUN_ID" >&2
    exit 2
    ;;
esac

if [[ ! -f "$MANIFEST" ]]; then
  echo "implementation manifest not found: $MANIFEST" >&2
  exit 1
fi

RUN_ID="$RUN_ID" MANIFEST="$MANIFEST" ruby <<'RUBY'
require "yaml"

run_id = ENV.fetch("RUN_ID")
manifest_path = ENV.fetch("MANIFEST")
errors = []

pipeline = YAML.load_file("agentic/pipeline.yaml")
manifest = YAML.load_file(manifest_path)
run = manifest["run"] || {}
manifest_schema = YAML.load_file("agentic/schemas/manifest.schema.yaml")

def validate_authorization_record(record, prefix, errors)
  errors << "#{prefix}.actor is required" if record["actor"].to_s.empty?
  errors << "#{prefix}.actor_role is required" if record["actor_role"].to_s.empty?
  authorization = record["authorization"]
  unless authorization.is_a?(Hash)
    errors << "#{prefix}.authorization must be a mapping"
    return
  end
  %w[action policy identity_authority].each do |field|
    errors << "#{prefix}.authorization.#{field} is required" if authorization[field].to_s.empty?
  end
end

valid_states = Array(pipeline.dig("states", "success")) + Array(pipeline.dig("states", "failure"))

errors << "run.id must equal #{run_id}" unless run["id"] == run_id
errors << "schema_version must be 1" unless manifest["schema_version"] == 1
errors << "run.mode must be implementation" unless run["mode"] == "implementation"
errors << "run.profile is required" if run["profile"].to_s.empty?
errors << "run.state is invalid: #{run["state"]}" unless valid_states.include?(run["state"])

profile_path = run["profile_path"].to_s
if profile_path.empty?
  errors << "run.profile_path is required"
elsif !File.file?(profile_path)
  errors << "profile not found: #{profile_path}"
end

parent = run["parent_planning_run"].to_s
parent_manifest = nil
if !parent.empty?
  parent_manifest_path = File.join("agentic/runs", parent, "manifest.yaml")
  if !File.file?(parent_manifest_path)
    errors << "parent planning manifest not found: agentic/runs/#{parent}/manifest.yaml"
  else
    parent_manifest = YAML.load_file(parent_manifest_path)
  end
end

approved_inputs = Array(manifest["approved_inputs"])
errors << "approved_inputs must not be empty" if approved_inputs.empty?

approved_paths = approved_inputs.map do |input|
  input.is_a?(Hash) ? input["path"].to_s : input.to_s
end

approved_paths.each do |path|
  if path.empty?
    errors << "approved_inputs contains an empty path"
  elsif !File.file?(path)
    errors << "approved input not found: #{path}"
  end
end

if parent_manifest
  parent_status_by_path = {}
  Array(parent_manifest["artifacts"]).each do |artifact|
    next unless artifact.is_a?(Hash)
    parent_status_by_path[artifact["path"].to_s] = artifact["status"].to_s
  end

  approved_paths.each do |path|
    unless parent_status_by_path[path] == "approved"
      errors << "approved input is not approved in parent planning manifest: #{path}"
    end
  end
end

tasks = Array(manifest["implementation_tasks"])
errors << "implementation_tasks must not be empty" if tasks.empty?
valid_task_states = Array(manifest_schema.dig("implementation_manifest", "task_states"))

tasks.each_with_index do |task, idx|
  prefix = "implementation_tasks[#{idx}]"
  errors << "#{prefix}.task_id is required" if task["task_id"].to_s.empty?
  errors << "#{prefix}.state is invalid: #{task["state"]}" unless valid_task_states.include?(task["state"].to_s)
  errors << "#{prefix}.owner is required" if task["owner"].to_s.empty?
  errors << "#{prefix}.scope is required" if task["scope"].to_s.empty?

  source_artifact = task["source_artifact"].to_s
  if source_artifact.empty?
    errors << "#{prefix}.source_artifact is required"
  elsif !approved_paths.include?(source_artifact)
    errors << "#{prefix}.source_artifact must reference approved_inputs: #{source_artifact}"
  end

  criteria = Array(task["acceptance_criteria"])
  errors << "#{prefix}.acceptance_criteria must not be empty" if criteria.empty?

  files_touched = Array(task["files_touched"])
  write_scope = Array(task["write_scope"])
  errors << "#{prefix}.files_touched must not be empty" if files_touched.empty?
  errors << "#{prefix}.write_scope must not be empty" if write_scope.empty?

  (files_touched + write_scope).each do |path|
    path = path.to_s
    if path.empty?
      errors << "#{prefix} contains an empty repo path"
    elsif path.start_with?("/") || path.split("/").include?("..")
      errors << "#{prefix} contains non repo-local path: #{path}"
    end
  end

  errors << "#{prefix}.validation_command is required" if task["validation_command"].to_s.empty?
  errors << "#{prefix}.rollback_notes is required" if task["rollback_notes"].to_s.empty?
  errors << "#{prefix}.ait_review_path is required" if task["ait_review_path"].to_s.empty?
  errors << "#{prefix}.dependencies must be an array" unless task["dependencies"].is_a?(Array)
end

active_task_write_scopes = {}
tasks.each_with_index do |task, idx|
  next unless %w[dispatched running code_changes_ready tests_running].include?(task["state"].to_s)
  Array(task["write_scope"]).each do |path|
    active_task_write_scopes[path.to_s] ||= []
    active_task_write_scopes[path.to_s] << "implementation_tasks[#{idx}].#{task["task_id"]}"
  end
end
active_task_write_scopes.each do |path, owners|
  errors << "active task write scope overlaps on #{path}: #{owners.join(", ")}" if owners.length > 1
end

task_graph = manifest["implementation_task_graph"]
if !task_graph.is_a?(Hash)
  errors << "implementation_task_graph must be a mapping"
else
  errors << "implementation_task_graph.task_count must equal implementation_tasks length" unless task_graph["task_count"] == tasks.length
end

branch_plan = manifest["branch_plan"]
errors << "branch_plan must be a mapping" unless branch_plan.is_a?(Hash)

code_ownership = Array(manifest["code_ownership"])
errors << "code_ownership must not be empty" if code_ownership.empty?

test_plan = Array(manifest["test_plan"])
errors << "test_plan must not be empty" if test_plan.empty?
test_plan.each_with_index do |test, idx|
  prefix = "test_plan[#{idx}]"
  errors << "#{prefix}.test_id is required" if test["test_id"].to_s.empty?
  errors << "#{prefix}.command is required" if test["command"].to_s.empty?
end

errors << "review_attempts must be an array" unless manifest["review_attempts"].is_a?(Array)
errors << "worker_dispatches must be an array" unless manifest["worker_dispatches"].is_a?(Array)
errors << "worker_results must be an array" unless manifest["worker_results"].is_a?(Array)
errors << "write_scope_leases must be an array" unless manifest["write_scope_leases"].is_a?(Array)
errors << "validation must be an array" unless manifest["validation"].is_a?(Array)
errors << "release_notes must be a mapping" unless manifest["release_notes"].is_a?(Hash)

valid_lease_states = Array(manifest_schema.dig("implementation_manifest", "lease_states"))
active_lease_write_scopes = {}
Array(manifest["write_scope_leases"]).each_with_index do |lease, idx|
  prefix = "write_scope_leases[#{idx}]"
  next errors << "#{prefix} must be a mapping" unless lease.is_a?(Hash)
  errors << "#{prefix}.state is invalid: #{lease["state"]}" unless valid_lease_states.include?(lease["state"].to_s)
  errors << "#{prefix}.task_id is required" if lease["task_id"].to_s.empty?
  Array(lease["write_scope"]).each do |path|
    path = path.to_s
    if path.empty? || path.start_with?("/") || path.split("/").include?("..")
      errors << "#{prefix}.write_scope contains non repo-local path: #{path}"
    end
    next unless lease["state"].to_s == "active"
    active_lease_write_scopes[path] ||= []
    active_lease_write_scopes[path] << "#{prefix}.#{lease["task_id"]}"
  end
end
active_lease_write_scopes.each do |path, owners|
  errors << "active write-scope lease overlaps on #{path}: #{owners.join(", ")}" if owners.length > 1
end

valid_result_statuses = Array(manifest_schema.dig("implementation_manifest", "worker_result_statuses"))
Array(manifest["worker_results"]).each_with_index do |result, idx|
  prefix = "worker_results[#{idx}]"
  next errors << "#{prefix} must be a mapping" unless result.is_a?(Hash)
  errors << "#{prefix}.status is invalid: #{result["status"]}" unless valid_result_statuses.include?(result["status"].to_s)
  errors << "#{prefix}.task_id is required" if result["task_id"].to_s.empty?
  errors << "#{prefix}.validation_evidence_path is required" if result["validation_evidence_path"].to_s.empty?
  validate_authorization_record(result, prefix, errors)
end

Array(manifest["review_attempts"]).each_with_index do |attempt, idx|
  next unless attempt.is_a?(Hash)
  next unless attempt["type"].to_s == "implementation_code_review"
  validate_authorization_record(attempt, "review_attempts[#{idx}]", errors)
end

unless errors.empty?
  errors.each { |error| warn "invalid implementation manifest: #{error}" }
  exit 1
end

puts "implementation manifest ok: #{run_id}"
puts "approved inputs: #{approved_paths.length}"
puts "implementation tasks: #{tasks.length}"
puts "test plan items: #{test_plan.length}"
RUBY
