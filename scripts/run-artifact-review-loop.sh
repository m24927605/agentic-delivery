#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/run-artifact-review-loop.sh [--dry-run] <planning-run-id> [--artifact <path>] [--result pass|changes_requested]

Records one bounded artifact review loop round. Review evidence is written only
under ignored agentic/reviews/.
USAGE
}

DRY_RUN=0
RESULT="pass"
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
    --result)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      RESULT="$2"
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

case "$RESULT" in
  pass|changes_requested) ;;
  *)
    echo "invalid --result: $RESULT" >&2
    exit 2
    ;;
esac

RUN_ID="$RUN_ID" DRY_RUN="$DRY_RUN" RESULT="$RESULT" ARTIFACT_FILTER="$ARTIFACT_FILTER" ruby <<'RUBY'
require "digest"
require "fileutils"
require "json"
require "time"
require "yaml"

run_id = ENV.fetch("RUN_ID")
dry_run = ENV.fetch("DRY_RUN") == "1"
result = ENV.fetch("RESULT")
artifact_filter = ENV["ARTIFACT_FILTER"].to_s
manifest_path = File.join("agentic/runs", run_id, "manifest.yaml")
now = Time.now.utc.iso8601
review_dir = File.join("agentic/reviews/auto-doc-to-implementation", run_id)
FileUtils.mkdir_p(review_dir)

def public_safe_path?(path)
  return false if path.to_s.empty?
  return false if path.start_with?("/")
  return false if path.split("/").include?("..")
  true
end

manifest = nil
if File.file?(manifest_path)
  manifest = YAML.load_file(manifest_path)
elsif dry_run
  round_path = File.join(review_dir, "round-1.json")
  File.write(round_path, JSON.pretty_generate({
    "schema_version" => 1,
    "run_id" => run_id,
    "dry_run" => true,
    "status" => "pass",
    "recommendation" => "approve",
    "blocking_issues" => [],
    "created_at" => now
  }))
  File.write(File.join(review_dir, "decision-log.md"), "# Decision Log\n\nDry-run review loop completed at #{now}.\n")
  puts "review loop completed: #{run_id} dry_run=true"
  exit 0
else
  warn "planning manifest not found: #{manifest_path}"
  exit 1
end

run = manifest["run"] || {}
unless run["id"].to_s == run_id
  warn "run.id mismatch: expected #{run_id}, got #{run["id"] || "(empty)"}"
  exit 1
end

artifacts = Array(manifest["artifacts"]).select { |artifact| artifact.is_a?(Hash) }
if !artifact_filter.empty?
  unless public_safe_path?(artifact_filter)
    warn "invalid artifact path: #{artifact_filter}"
    exit 2
  end
  artifacts = artifacts.select { |artifact| artifact["path"].to_s == artifact_filter }
else
  artifacts = artifacts.select { |artifact| %w[drafted reviewed changes_requested].include?(artifact["status"].to_s) }
end

if artifacts.empty?
  warn "no reviewable artifacts found"
  exit 1
end

manifest["review_attempts"] = Array(manifest["review_attempts"])
created_rounds = []
blocked = false

artifacts.each do |artifact|
  path = artifact["path"].to_s
  unless public_safe_path?(path) && File.file?(path)
    warn "reviewable artifact not found: #{path}"
    exit 1
  end

  content_hash = Digest::SHA256.hexdigest(File.read(path))
  previous_rounds = manifest["review_attempts"].select do |attempt|
    attempt.is_a?(Hash) && attempt["artifact_path"].to_s == path
  end
  round = previous_rounds.length + 1

  if round > 5
    File.open(File.join(review_dir, "decision-log.md"), "a") do |file|
      file.puts "Round 5 exhausted for #{path} at #{now}; blocked_human_decision_required."
    end
    blocked = true
    next
  end

  last_hash = previous_rounds.last && previous_rounds.last["content_sha256"].to_s
  if !dry_run && previous_rounds.any? && last_hash == content_hash
    warn "artifact must change before another review round: #{path}"
    exit 1
  end

  evidence_path = File.join(review_dir, "round-#{round}.json")
  evidence = {
    "schema_version" => 1,
    "run_id" => run_id,
    "artifact_path" => path,
    "round" => round,
    "dry_run" => dry_run,
    "status" => result == "pass" ? "pass" : "fail",
    "recommendation" => result == "pass" ? "approve" : "request_changes",
    "blocking_issues" => result == "pass" ? [] : ["Dry-run requested changes for #{path}"],
    "content_sha256" => content_hash,
    "created_at" => now
  }
  File.write(evidence_path, JSON.pretty_generate(evidence))
  created_rounds << evidence_path

  next if dry_run

  artifact["status"] = result == "pass" ? "reviewed" : "changes_requested"
  artifact["review_state"] = artifact["status"]
  artifact["updated_at"] = now
  artifact["updated_by"] = "run-artifact-review-loop"
  artifact["status_history"] = Array(artifact["status_history"])
  artifact["status_history"] << {
    "from_status" => artifact["status"] == "reviewed" ? "drafted" : "reviewed",
    "to_status" => artifact["status"],
    "at" => now,
    "actor" => "run-artifact-review-loop",
    "reason" => "Artifact review round #{round} #{result}"
  }

  manifest["review_attempts"] << {
    "artifact_path" => path,
    "round" => round,
    "status" => evidence["status"],
    "recommendation" => evidence["recommendation"],
    "content_sha256" => content_hash,
    "evidence_path" => evidence_path,
    "created_at" => now
  }
end

if blocked
  manifest["run"]["state"] = "blocked_human_decision_required"
  File.write(manifest_path, manifest.to_yaml) unless dry_run
  puts "blocked_human_decision_required"
  exit 1
end

unless dry_run
  manifest["run"]["state"] = "agency_review_completed"
  manifest["run"]["updated_at"] = now
  File.write(manifest_path, manifest.to_yaml)
end

puts "review loop completed: #{run_id} rounds=#{created_rounds.length} dry_run=#{dry_run}"
created_rounds.each { |path| puts "- #{path}" }
RUBY
