#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/execute-implementation-task.sh [--dry-run] [--result succeeded|failed|blocked] [--command <cmd>] [--actor <actor-id>] [--role <role-id>] <implementation-run-id> <task-id>
USAGE
}

DRY_RUN=0
RESULT=""
COMMAND_OVERRIDE=""
ACTOR=""
ROLE=""
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --result)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      RESULT="$2"
      shift 2
      ;;
    --command)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      COMMAND_OVERRIDE="$2"
      shift 2
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
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

if [[ "${#POSITIONAL[@]}" -ne 2 ]]; then
  usage
  exit 2
fi

RUN_ID="${POSITIONAL[0]}"
TASK_ID="${POSITIONAL[1]}"

case "$RUN_ID" in */*|*..*|"") echo "invalid run id: $RUN_ID" >&2; exit 2 ;; esac
case "$TASK_ID" in */*|*..*|"") echo "invalid task id: $TASK_ID" >&2; exit 2 ;; esac
case "$RESULT" in ""|succeeded|failed|blocked) ;; *) echo "invalid result: $RESULT" >&2; exit 2 ;; esac

MANIFEST="agentic/runs/$RUN_ID/implementation-manifest.yaml"
if [[ ! -f "$MANIFEST" ]]; then
  echo "implementation manifest not found: $MANIFEST" >&2
  exit 1
fi

RUN_ID="$RUN_ID" TASK_ID="$TASK_ID" DRY_RUN="$DRY_RUN" RESULT="$RESULT" COMMAND_OVERRIDE="$COMMAND_OVERRIDE" MANIFEST="$MANIFEST" ACTOR="$ACTOR" ROLE="$ROLE" ruby <<'RUBY'
require File.expand_path("scripts/lib/agentic_identity", Dir.pwd)
require "digest"
require "fileutils"
require "open3"
require "shellwords"
require "time"
require "yaml"

run_id = ENV.fetch("RUN_ID")
task_id = ENV.fetch("TASK_ID")
dry_run = ENV.fetch("DRY_RUN") == "1"
requested_result = ENV["RESULT"].to_s
command_override = ENV["COMMAND_OVERRIDE"].to_s
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
  auth = AgenticIdentity.authorize!(policy, action: "implementation.task.execute", actor: ENV["ACTOR"], role: ENV["ROLE"])
rescue AgenticIdentity::AuthorizationError => e
  warn "authorization failed: #{e.message}"
  exit 1
end

unless task
  warn "unknown implementation task: #{task_id}"
  exit 1
end

def repo_local_path?(path)
  return false if path.to_s.empty?
  return false if path.start_with?("/")
  return false if path.split("/").include?("..")
  true
end

write_scope = Array(task["write_scope"]).map(&:to_s).reject(&:empty?)
if write_scope.empty? || write_scope.any? { |path| !repo_local_path?(path) }
  warn "task write scope must be non-empty and repo-local"
  exit 1
end

unless task["validation_command"].to_s.strip.length.positive?
  warn "task validation_command is required"
  exit 1
end

unless Array(task["acceptance_criteria"]).any? && task["rollback_notes"].to_s.strip.length.positive?
  warn "task acceptance criteria and rollback notes are required"
  exit 1
end

active_leases = Array(manifest["write_scope_leases"]).select { |lease| lease.is_a?(Hash) && lease["state"].to_s == "active" }
overlap = active_leases.reject { |lease| lease["task_id"].to_s == task_id }.select do |lease|
  !(Array(lease["write_scope"]).map(&:to_s) & write_scope).empty?
end
unless overlap.empty?
  warn "blocked_overlapping_write_scope: active lease overlaps #{task_id}"
  exit 1
end

lease = active_leases.find { |candidate| candidate["task_id"].to_s == task_id }
unless lease
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
end

worker_dir = File.join("agentic/runs", run_id, "worker", task_id)
review_dir = File.join("agentic/reviews/auto-doc-to-implementation", "h16", run_id, task_id)
validation_path = File.join(review_dir, "validation-round-1.log")
stdout_path = File.join(worker_dir, "stdout.log")
prompt_path = File.join(worker_dir, "prompt.md")
command = command_override.empty? ? task["validation_command"].to_s : command_override

plan = {
  "task_id" => task_id,
  "write_scope" => write_scope,
  "worker_prompt_path" => prompt_path,
  "stdout_path" => stdout_path,
  "validation_evidence_path" => validation_path,
  "command" => command,
  "lease" => lease
}

if dry_run
  puts plan.to_yaml
  puts "implementation task execution ready: #{run_id} #{task_id} dry_run=true"
  exit 0
end

FileUtils.mkdir_p(worker_dir)
FileUtils.mkdir_p(review_dir)
File.write(prompt_path, <<~PROMPT)
  Implement one bounded task for this repo.

  Run: #{run_id}
  Task: #{task_id}
  Scope: #{task["scope"]}
  Write scope: #{write_scope.join(", ")}
  Acceptance criteria:
  #{Array(task["acceptance_criteria"]).map { |item| "- #{item}" }.join("\n")}

  Keep raw output ignored. Do not approve artifacts or tasks from worker output.
PROMPT

before_hashes = write_scope.to_h { |path| [path, File.file?(path) ? Digest::SHA256.hexdigest(File.read(path)) : nil] }
stdout, stderr, status = Open3.capture3("bash", "-lc", command)
File.write(stdout_path, stdout + stderr)
exit_status = status.exitstatus || 1
actual_result = if requested_result.empty?
  exit_status.zero? ? "succeeded" : "failed"
else
  requested_result
end

redacted_output = (stdout + stderr).gsub(/ownership[_-]token/i, "redacted_ait_metadata").gsub(%r{/Users/\S+}, "[local-path]")
File.write(validation_path, <<~LOG)
  command: #{command}
  exit_status: #{exit_status}
  recorded_at: #{now}
  output:
  #{redacted_output}
LOG

after_hashes = write_scope.to_h { |path| [path, File.file?(path) ? Digest::SHA256.hexdigest(File.read(path)) : nil] }
changed_files = write_scope.select { |path| before_hashes[path] != after_hashes[path] }

manifest["worker_results"] = Array(manifest["worker_results"])
result = {
  "task_id" => task_id,
  "status" => actual_result,
  "recorded_at" => now,
  "actor" => auth.fetch("actor"),
  "actor_role" => auth.fetch("actor_role"),
  "authorization" => AgenticIdentity.audit_record(auth),
  "changed_files" => changed_files,
  "validation_command" => command,
  "validation_exit_status" => exit_status,
  "validation_evidence_path" => validation_path,
  "stdout_path" => stdout_path,
  "rollback_notes" => task["rollback_notes"]
}
manifest["worker_results"] << result

manifest["write_scope_leases"] = Array(manifest["write_scope_leases"])
unless manifest["write_scope_leases"].include?(lease)
  manifest["write_scope_leases"] << lease
end
lease["state"] = "released"
lease["released_at"] = Time.now.utc.iso8601
lease["result_status"] = actual_result
lease["owner"] = auth.fetch("actor")
lease["identity_proof"] = "repo_local_identity_policy"
lease["authorization"] = AgenticIdentity.audit_record(auth)

task["worker_result"] = result
case actual_result
when "succeeded"
  task["state"] = exit_status.zero? ? "tests_passed" : "blocked_tests_failed"
  manifest["run"]["state"] = task["state"]
when "failed"
  task["state"] = "blocked_tests_failed"
  manifest["run"]["state"] = "blocked_tests_failed"
else
  task["state"] = "blocked_tests_failed"
  manifest["run"]["state"] = "blocked_tests_failed"
end
task["updated_at"] = Time.now.utc.iso8601
manifest["run"]["updated_at"] = task["updated_at"]
File.write(manifest_path, manifest.to_yaml)

puts "implementation task execution completed: #{run_id} #{task_id} status=#{actual_result} validation_exit=#{exit_status}"
exit(exit_status.zero? ? 0 : 1)
RUBY
