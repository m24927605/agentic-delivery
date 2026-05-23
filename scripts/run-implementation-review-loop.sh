#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/run-implementation-review-loop.sh [--dry-run] [--result pass|request_changes|blocked] [--actor <actor-id>] [--role <role-id>] <implementation-run-id> <task-id>
USAGE
}

DRY_RUN=0
RESULT="pass"
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
case "$RESULT" in pass|request_changes|blocked) ;; *) echo "invalid result: $RESULT" >&2; exit 2 ;; esac

MANIFEST="agentic/runs/$RUN_ID/implementation-manifest.yaml"
if [[ ! -f "$MANIFEST" ]]; then
  echo "implementation manifest not found: $MANIFEST" >&2
  exit 1
fi

RUN_ID="$RUN_ID" TASK_ID="$TASK_ID" DRY_RUN="$DRY_RUN" RESULT="$RESULT" MANIFEST="$MANIFEST" ACTOR="$ACTOR" ROLE="$ROLE" ruby <<'RUBY'
require File.expand_path("scripts/lib/agentic_identity", Dir.pwd)
require "digest"
require "fileutils"
require "json"
require "time"
require "yaml"

run_id = ENV.fetch("RUN_ID")
task_id = ENV.fetch("TASK_ID")
dry_run = ENV.fetch("DRY_RUN") == "1"
result = ENV.fetch("RESULT")
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
  auth = AgenticIdentity.authorize!(policy, action: "implementation.review.record", actor: ENV["ACTOR"], role: ENV["ROLE"])
rescue AgenticIdentity::AuthorizationError => e
  warn "authorization failed: #{e.message}"
  exit 1
end

unless task
  warn "unknown implementation task: #{task_id}"
  exit 1
end

worker_result = Array(manifest["worker_results"]).reverse.find do |candidate|
  candidate.is_a?(Hash) && candidate["task_id"].to_s == task_id
end
unless dry_run || (worker_result && worker_result["status"].to_s == "succeeded")
  warn "implementation review requires a succeeded worker result: #{task_id}"
  exit 1
end

if worker_result
  begin
    AgenticIdentity.actor_must_differ!(
      auth,
      worker_result["actor"],
      "blocked_authorization_failed: implementation reviewer must differ from latest worker actor #{worker_result["actor"]}"
    )
  rescue AgenticIdentity::AuthorizationError => e
    warn "authorization failed: #{e.message}"
    exit 1
  end
end

write_scope = Array(task["write_scope"]).map(&:to_s).reject(&:empty?)
content_hash = Digest::SHA256.hexdigest(write_scope.map do |path|
  File.file?(path) ? "#{path}:#{Digest::SHA256.hexdigest(File.read(path))}" : "#{path}:missing"
end.join("\n"))

attempts = Array(manifest["review_attempts"]).select do |attempt|
  attempt.is_a?(Hash) && attempt["task_id"].to_s == task_id && attempt["type"].to_s == "implementation_code_review"
end
round = attempts.length + 1

if round > 5
  decision_dir = File.join("agentic/reviews/auto-doc-to-implementation", "h18", run_id, task_id)
  unless dry_run
    FileUtils.mkdir_p(decision_dir)
    File.open(File.join(decision_dir, "decision-log.md"), "a") do |file|
      file.puts "Round 5 exhausted for #{task_id} at #{now}; blocked_human_decision_required."
    end
    task["state"] = "blocked_code_review_required"
    task["updated_at"] = now
    manifest["run"]["state"] = "blocked_human_decision_required"
    manifest["run"]["updated_at"] = now
    File.write(manifest_path, manifest.to_yaml)
  end
  puts "blocked_human_decision_required"
  exit 1
end

if !dry_run && attempts.any? && attempts.any? { |attempt| attempt["content_sha256"].to_s == content_hash }
  warn "implementation must change before another review round: #{task_id}"
  exit 1
end

review_dir = File.join("agentic/reviews/auto-doc-to-implementation", "h18", run_id, task_id)
evidence_path = File.join(review_dir, "round-#{round}.json")
evidence = {
  "schema_version" => 1,
  "run_id" => run_id,
  "task_id" => task_id,
  "round" => round,
  "dry_run" => dry_run,
  "status" => result == "pass" ? "pass" : "fail",
  "recommendation" => result == "pass" ? "approve" : "request_changes",
  "actor" => auth.fetch("actor"),
  "actor_role" => auth.fetch("actor_role"),
  "authorization" => AgenticIdentity.audit_record(auth),
  "blocking_issues" => result == "pass" ? [] : ["Implementation review requested changes for #{task_id}"],
  "content_sha256" => content_hash,
  "created_at" => now,
  "authority_note" => "Review evidence cannot approve artifacts or implementation tasks by itself."
}

if dry_run
  puts "implementation review loop completed: #{run_id} #{task_id} round=#{round} dry_run=true"
  puts "- preview_evidence_path=#{evidence_path}"
  exit 0
end

FileUtils.mkdir_p(review_dir)
File.write(evidence_path, JSON.pretty_generate(evidence))

manifest["review_attempts"] = Array(manifest["review_attempts"])
manifest["review_attempts"] << {
  "type" => "implementation_code_review",
  "task_id" => task_id,
  "round" => round,
  "status" => evidence["status"],
  "recommendation" => evidence["recommendation"],
  "actor" => auth.fetch("actor"),
  "actor_role" => auth.fetch("actor_role"),
  "authorization" => AgenticIdentity.audit_record(auth),
  "content_sha256" => content_hash,
  "evidence_path" => evidence_path,
  "created_at" => now
}

case result
when "pass"
  validation_ok = system("scripts/validate-implementation-run.sh", run_id)
  unless validation_ok
    warn "final implementation validation failed after review pass: #{run_id}"
    exit 1
  end
  task["state"] = "implementation_review_ready"
  manifest["run"]["state"] = "implementation_review_ready"
when "request_changes"
  task["state"] = "blocked_code_review_required"
  if round >= 5
    File.open(File.join(review_dir, "decision-log.md"), "a") do |file|
      file.puts "Round 5 failed for #{task_id} at #{now}; blocked_human_decision_required."
    end
    manifest["run"]["state"] = "blocked_human_decision_required"
  else
    manifest["run"]["state"] = "blocked_code_review_required"
  end
else
  task["state"] = "blocked_code_review_required"
  manifest["run"]["state"] = "blocked_human_decision_required"
end
task["updated_at"] = now
manifest["run"]["updated_at"] = now
File.write(manifest_path, manifest.to_yaml)

puts "implementation review loop completed: #{run_id} #{task_id} round=#{round} result=#{result} dry_run=false"
puts "- #{evidence_path}"
RUBY
