#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/dispatch-implementation-task.sh [--dry-run] [--actor <actor-id>] [--role <role-id>] <implementation-run-id> <task-id>
USAGE
}

DRY_RUN=0
ACTOR=""
ROLE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --actor)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      ACTOR="$2"
      shift 2
      ;;
    --role)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      ROLE="$2"
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
      break
      ;;
  esac
done

if [[ $# -ne 2 ]]; then
  usage
  exit 2
fi

RUN_ID="$1"
TASK_ID="$2"

case "$RUN_ID" in
  */*|*..*|"")
    echo "invalid run id: $RUN_ID" >&2
    exit 2
    ;;
esac

case "$TASK_ID" in
  */*|*..*|"")
    echo "invalid task id: $TASK_ID" >&2
    exit 2
    ;;
esac

MANIFEST="agentic/runs/$RUN_ID/implementation-manifest.yaml"

if [[ ! -f "$MANIFEST" ]]; then
  echo "implementation manifest not found: $MANIFEST" >&2
  exit 1
fi

RUN_ID="$RUN_ID" TASK_ID="$TASK_ID" DRY_RUN="$DRY_RUN" MANIFEST="$MANIFEST" ACTOR="$ACTOR" ROLE="$ROLE" ruby <<'RUBY'
require File.expand_path("scripts/lib/agentic_identity", Dir.pwd)
require "fileutils"
require "time"
require "yaml"

run_id = ENV.fetch("RUN_ID")
task_id = ENV.fetch("TASK_ID")
dry_run = ENV.fetch("DRY_RUN") == "1"
manifest_path = ENV.fetch("MANIFEST")
manifest = YAML.load_file(manifest_path)
tasks = Array(manifest["implementation_tasks"]).select { |task| task.is_a?(Hash) }
task = tasks.find { |candidate| candidate["task_id"].to_s == task_id }
now = Time.now.utc.iso8601
policy = AgenticIdentity.load_policy
policy_errors = AgenticIdentity.validate_policy(policy)
unless policy_errors.empty?
  policy_errors.each { |error| warn "invalid identity policy: #{error}" }
  exit 1
end

begin
  auth = AgenticIdentity.authorize!(policy, action: "implementation.task.dispatch", actor: ENV["ACTOR"], role: ENV["ROLE"])
rescue AgenticIdentity::AuthorizationError => e
  warn "authorization failed: #{e.message}"
  exit 1
end

unless task
  warn "unknown implementation task: #{task_id}"
  exit 1
end

def path_set(task)
  Array(task["write_scope"].nil? ? task["files_touched"] : task["write_scope"]).map(&:to_s).reject(&:empty?)
end

write_scope = path_set(task)
if write_scope.empty?
  warn "task has empty write scope: #{task_id}"
  exit 1
end

invalid_paths = write_scope.select { |path| path.start_with?("/") || path.split("/").include?("..") }
unless invalid_paths.empty?
  warn "task write scope contains non repo-local paths: #{invalid_paths.join(", ")}"
  exit 1
end

overlapping_tasks = tasks.reject { |candidate| candidate["task_id"].to_s == task_id }.select do |candidate|
  !(path_set(candidate) & write_scope).empty?
end

unless overlapping_tasks.empty?
  warn "blocked_overlapping_write_scope: #{task_id} overlaps #{overlapping_tasks.map { |candidate| candidate["task_id"] }.join(", ")}"
  exit 1
end

active_dispatches = Array(manifest["worker_dispatches"]).select do |dispatch|
  dispatch.is_a?(Hash) && %w[dispatched running].include?(dispatch["state"].to_s)
end
overlap_dispatches = active_dispatches.reject { |dispatch| dispatch["task_id"].to_s == task_id }.select do |dispatch|
  !(Array(dispatch["write_scope"]).map(&:to_s) & write_scope).empty?
end

unless overlap_dispatches.empty?
  warn "blocked_overlapping_write_scope: active dispatch overlaps #{task_id}"
  exit 1
end

active_leases = Array(manifest["write_scope_leases"]).select do |lease|
  lease.is_a?(Hash) && lease["state"].to_s == "active"
end
overlap_leases = active_leases.select do |lease|
  !(Array(lease["write_scope"]).map(&:to_s) & write_scope).empty?
end

unless overlap_leases.empty?
  warn "blocked_overlapping_write_scope: active lease overlaps #{task_id}"
  exit 1
end

dispatch = {
  "task_id" => task_id,
  "worker" => "implementation_agent",
  "actor" => auth.fetch("actor"),
  "actor_role" => auth.fetch("actor_role"),
  "authorization" => AgenticIdentity.audit_record(auth),
  "state" => "dispatched",
  "dispatched_at" => now,
  "write_scope" => write_scope,
  "validation_command" => task["validation_command"],
  "rollback_notes" => task["rollback_notes"],
  "review_record_path" => task["ait_review_path"],
  "stdout_redacted" => true,
  "instructions" => {
    "scope" => task["scope"],
    "acceptance_criteria" => Array(task["acceptance_criteria"])
  }
}

lease = {
  "lease_id" => "#{task_id}-#{now.gsub(/[^0-9A-Za-z]/, "")}",
  "task_id" => task_id,
  "state" => "active",
  "acquired_at" => now,
  "released_at" => nil,
  "write_scope" => write_scope,
  "owner" => auth.fetch("actor"),
  "identity_proof" => "repo_local_identity_policy",
  "authorization" => AgenticIdentity.audit_record(auth)
}

if dry_run
  puts({ "dispatch" => dispatch, "lease" => lease }.to_yaml)
else
  FileUtils.mkdir_p(File.join("agentic/runs", run_id, "dispatch"))
  File.write(File.join("agentic/runs", run_id, "dispatch", "#{task_id}.yaml"), dispatch.to_yaml)
  manifest["worker_dispatches"] = Array(manifest["worker_dispatches"])
  manifest["worker_dispatches"] << dispatch
  manifest["write_scope_leases"] = Array(manifest["write_scope_leases"])
  manifest["write_scope_leases"] << lease
  task["state"] = "dispatched"
  task["dispatched_at"] = now
  manifest["run"]["state"] = "worker_dispatch_ready"
  manifest["run"]["updated_at"] = now
  File.write(manifest_path, manifest.to_yaml)
end

puts "worker dispatch ready: #{run_id} #{task_id} dry_run=#{dry_run}"
RUBY
