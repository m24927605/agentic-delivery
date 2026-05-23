#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/create-artifact-revision-tasks.sh [--dry-run] <planning-run-id> [--artifact <path>]
USAGE
}

DRY_RUN=0
ARTIFACT_FILTER=""
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --artifact)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      ARTIFACT_FILTER="$2"
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

if [[ "${#POSITIONAL[@]}" -ne 1 ]]; then
  usage
  exit 2
fi

RUN_ID="${POSITIONAL[0]}"

case "$RUN_ID" in
  */*|*..*|"")
    echo "invalid run id: $RUN_ID" >&2
    exit 2
    ;;
esac

case "$ARTIFACT_FILTER" in
  /*|*..*)
    echo "invalid artifact path: $ARTIFACT_FILTER" >&2
    exit 2
    ;;
esac

MANIFEST="agentic/runs/$RUN_ID/manifest.yaml"
if [[ ! -f "$MANIFEST" ]]; then
  echo "planning manifest not found: $MANIFEST" >&2
  exit 1
fi

RUN_ID="$RUN_ID" MANIFEST="$MANIFEST" DRY_RUN="$DRY_RUN" ARTIFACT_FILTER="$ARTIFACT_FILTER" ruby <<'RUBY'
require "digest"
require "json"
require "time"
require "yaml"

run_id = ENV.fetch("RUN_ID")
manifest_path = ENV.fetch("MANIFEST")
dry_run = ENV.fetch("DRY_RUN") == "1"
artifact_filter = ENV["ARTIFACT_FILTER"].to_s
manifest = YAML.load_file(manifest_path)
now = Time.now.utc.iso8601

def public_safe_path?(path)
  return false if path.to_s.empty?
  return false if path.start_with?("/")
  return false if path.split("/").include?("..")
  true
end

unless manifest.dig("run", "id").to_s == run_id
  warn "run.id mismatch: expected #{run_id}"
  exit 1
end

artifacts = Array(manifest["artifacts"]).select { |artifact| artifact.is_a?(Hash) }
artifact_by_path = artifacts.to_h { |artifact| [artifact["path"].to_s, artifact] }
attempts = Array(manifest["review_attempts"]).select { |attempt| attempt.is_a?(Hash) }
attempts = attempts.select { |attempt| attempt["artifact_path"].to_s == artifact_filter } unless artifact_filter.empty?

failed_attempts = attempts.select do |attempt|
  %w[fail blocked].include?(attempt["status"].to_s) ||
    %w[request_changes changes_requested].include?(attempt["recommendation"].to_s)
end

latest_by_artifact = {}
failed_attempts.each do |attempt|
  path = attempt["artifact_path"].to_s
  next unless public_safe_path?(path)
  latest_by_artifact[path] = attempt if latest_by_artifact[path].nil? || attempt["round"].to_i >= latest_by_artifact[path]["round"].to_i
end

tasks = []
latest_by_artifact.each do |path, attempt|
  artifact = artifact_by_path[path]
  unless artifact
    warn "review attempt references unknown artifact: #{path}"
    exit 1
  end
  unless File.file?(path)
    warn "artifact not found: #{path}"
    exit 1
  end

  evidence_path = attempt["evidence_path"].to_s
  issues = []
  if !evidence_path.empty? && File.file?(evidence_path)
    begin
      evidence = JSON.parse(File.read(evidence_path))
      issues = Array(evidence["blocking_issues"])
    rescue JSON::ParserError
      issues = ["Review evidence could not be parsed; inspect #{evidence_path}."]
    end
  end
  issues = ["Review requested changes for #{path}."] if issues.empty?

  content_hash = Digest::SHA256.hexdigest(File.read(path))
  next_id = format("rev-%03d", Array(manifest["artifact_revision_tasks"]).length + tasks.length + 1)
  tasks << {
    "task_id" => next_id,
    "artifact_path" => path,
    "state" => "open",
    "created_at" => now,
    "review_round" => attempt["round"],
    "review_evidence_path" => evidence_path.empty? ? nil : evidence_path,
    "content_sha256" => content_hash,
    "findings" => issues.map(&:to_s),
    "acceptance_criteria" => [
      "Revise only #{path}.",
      "Preserve manifest authority and explicit artifact approval.",
      "Record a changed content hash before re-review."
    ],
    "validation_command" => "scripts/validate-artifact-templates.sh #{run_id} --artifact #{path}",
    "rollback_notes" => "Revert the revision to #{path} and remove this local task record."
  }
end

if tasks.empty?
  warn "no review findings require artifact revision tasks"
  exit 1
end

if dry_run
  puts({ "artifact_revision_tasks" => tasks }.to_yaml)
  puts "artifact revision tasks ready: #{run_id} tasks=#{tasks.length} dry_run=true"
  exit 0
end

tasks.each do |task|
  artifact = artifact_by_path.fetch(task["artifact_path"])
  next if artifact["status"].to_s == "changes_requested"

  ok = system(
    "scripts/update-artifact-status.sh",
    run_id,
    task["artifact_path"],
    "changes_requested",
    "--reason",
    "Review finding revision task #{task["task_id"]}"
  )
  unless ok
    warn "failed to update artifact status through update-artifact-status.sh: #{task["artifact_path"]}"
    exit 1
  end
end

manifest = YAML.load_file(manifest_path)
artifact_by_path = Array(manifest["artifacts"]).select { |artifact| artifact.is_a?(Hash) }.to_h { |artifact| [artifact["path"].to_s, artifact] }
manifest["artifact_revision_tasks"] = Array(manifest["artifact_revision_tasks"]) + tasks
tasks.each do |task|
  artifact = artifact_by_path.fetch(task["artifact_path"])
  artifact["revision_tasks"] = Array(artifact["revision_tasks"])
  artifact["revision_tasks"] << task["task_id"]
end
manifest["run"]["updated_at"] = now
File.write(manifest_path, manifest.to_yaml)

puts "artifact revision tasks ready: #{run_id} tasks=#{tasks.length} dry_run=false"
tasks.each { |task| puts "- #{task["task_id"]} #{task["artifact_path"]}" }
RUBY
