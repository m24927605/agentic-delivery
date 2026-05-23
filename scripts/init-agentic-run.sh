#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/init-agentic-run.sh <goal text>
  scripts/init-agentic-run.sh --goal-file <path> [--artifact <path> ...] [goal text]

Goal files may include YAML frontmatter with requested artifacts:

---
artifacts:
  - path: docs/architecture/example.md
    kind: architecture
    purpose: Describe the design.
    agent: document_builder
    instructions: Write the requested architecture document.
---
USAGE
}

GOAL_FILE=""
EXTRA_ARTIFACTS=()
GOAL_PARTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --goal-file)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      GOAL_FILE="$2"
      shift 2
      ;;
    --artifact)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      EXTRA_ARTIFACTS+=("$2")
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
      GOAL_PARTS+=("$1")
      shift
      ;;
  esac
done

if [[ -z "$GOAL_FILE" && "${#GOAL_PARTS[@]}" -eq 0 ]]; then
  usage
  exit 2
fi

if [[ -n "$GOAL_FILE" && ! -f "$GOAL_FILE" ]]; then
  echo "goal file not found: $GOAL_FILE" >&2
  exit 1
fi

case "$GOAL_FILE" in
  /*|*..*)
    echo "invalid goal file path: $GOAL_FILE" >&2
    exit 2
    ;;
esac

GOAL="${GOAL_PARTS[*]:-}"
PROFILE="${PROFILE:-}"
RUN_ID="${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
RUN_DIR="agentic/runs/$RUN_ID"
MANIFEST="$RUN_DIR/manifest.yaml"

case "$RUN_ID" in
  */*|*..*)
    echo "invalid RUN_ID: $RUN_ID" >&2
    exit 2
    ;;
esac

if [[ -e "$RUN_DIR" ]]; then
  echo "run already exists: $RUN_ID" >&2
  exit 1
fi

mkdir -p "$RUN_DIR"

extra_artifacts_payload=""
if [[ "${#EXTRA_ARTIFACTS[@]}" -gt 0 ]]; then
  extra_artifacts_payload="$(printf '%s\n' "${EXTRA_ARTIFACTS[@]}")"
fi

RUN_ID="$RUN_ID" \
GOAL="$GOAL" \
GOAL_FILE="$GOAL_FILE" \
EXTRA_ARTIFACTS="$extra_artifacts_payload" \
PROFILE="$PROFILE" \
MANIFEST="$MANIFEST" \
ruby <<'RUBY'
require "yaml"
require "time"

pipeline = YAML.load_file("agentic/pipeline.yaml")
run_id = ENV.fetch("RUN_ID")
goal = ENV.fetch("GOAL")
goal_file = ENV["GOAL_FILE"].to_s
extra_artifacts = ENV["EXTRA_ARTIFACTS"].to_s.lines.map(&:strip).reject(&:empty?)
profile_id = ENV["PROFILE"].to_s.empty? ? pipeline.fetch("pipeline").fetch("default_profile") : ENV.fetch("PROFILE")
profile_path = File.join(pipeline.fetch("pipeline").fetch("profile_dir"), "#{profile_id}.yaml")
manifest_path = ENV.fetch("MANIFEST")
now = Time.now.utc.iso8601

unless File.exist?(profile_path)
  warn "profile not found: #{profile_path}"
  exit 1
end

profile = YAML.load_file(profile_path)
required_artifacts = profile.fetch("required_artifacts")
source_of_truth = profile.fetch("source_of_truth")

def public_safe_path?(path)
  return false if path.to_s.empty?
  return false if path.start_with?("/")
  return false if path.split("/").include?("..")
  true
end

def frontmatter_from_markdown(content)
  return [{}, content] unless content.start_with?("---\n")

  parts = content.split(/^---\s*$/, 3)
  return [{}, content] unless parts.length >= 3

  frontmatter = YAML.safe_load(parts[1], permitted_classes: [], aliases: false) || {}
  [frontmatter, parts[2].sub(/\A\n/, "")]
rescue Psych::SyntaxError => e
  warn "invalid YAML frontmatter in goal file: #{e.message}"
  exit 1
end

goal_frontmatter = {}
if !goal_file.empty?
  unless public_safe_path?(goal_file)
    warn "invalid goal file path: #{goal_file}"
    exit 2
  end

  goal_content = File.read(goal_file)
  goal_frontmatter, goal_body = frontmatter_from_markdown(goal_content)
  goal = [goal_body.strip, goal].reject(&:empty?).join("\n\n")
end

def artifact_entry_from(value, source)
  entry = case value
  when String
    { "path" => value }
  when Hash
    value.transform_keys(&:to_s)
  else
    warn "invalid artifact entry in #{source}: #{value.inspect}"
    exit 1
  end

  path = entry["path"].to_s
  unless public_safe_path?(path)
    warn "invalid artifact path in #{source}: #{path}"
    exit 2
  end

  {
    "path" => path,
    "kind" => entry["kind"],
    "purpose" => entry["purpose"],
    "agent" => entry["agent"] || entry["owner_agent"] || "document_builder",
    "instructions" => entry["instructions"] || entry["agent_task"] || entry["prompt"],
    "source" => source
  }
end

def owner_for(path)
  case path
  when %r{\Adocs/proposals/} then "document_builder"
  when %r{\Adocs/architecture/} then "document_builder"
  when %r{\Adocs/adr/} then "document_builder"
  when %r{\Adocs/connectors/} then "schema_validation"
  when %r{\Adocs/backlog/} then "document_builder"
  when %r{\Adocs/reviews/} then "integration"
  else "orchestrator"
  end
end

deliverables = required_artifacts.fetch("deliverables", [])
requested_artifacts = []
requested_artifacts.concat(Array(goal_frontmatter["artifacts"]).map { |entry| artifact_entry_from(entry, goal_file) })
requested_artifacts.concat(extra_artifacts.map { |path| artifact_entry_from(path, "--artifact") })

deliverable_entries = deliverables.map { |path| artifact_entry_from(path, "profile:#{profile_id}") }
all_entries = []
(deliverable_entries + requested_artifacts).each do |entry|
  existing = all_entries.find { |candidate| candidate["path"] == entry["path"] }
  if existing
    entry.each { |key, value| existing[key] = value unless value.nil? || value.to_s.empty? }
  else
    all_entries << entry
  end
end

artifacts = all_entries.map do |entry|
  path = entry["path"]
  {
    "path" => path,
    "owner_agent" => entry["agent"].to_s.empty? ? owner_for(path) : entry["agent"],
    "kind" => entry["kind"],
    "purpose" => entry["purpose"],
    "generation_instructions" => entry["instructions"],
    "requested_by" => entry["source"],
    "generation_mode" => entry["instructions"].to_s.empty? ? "scaffold" : "agent",
    "status" => "planned",
    "created_at" => now,
    "updated_at" => now,
    "decision" => nil,
    "decision_reason" => nil,
    "strategy_gate_status" => "pending",
    "review_state" => "draft",
    "updated_by" => nil,
    "status_history" => [
      {
        "from_status" => nil,
        "to_status" => "planned",
        "at" => now,
        "actor" => "init-agentic-run",
        "reason" => "Artifact planned by run initialization"
      }
    ]
  }
end

manifest = {
  "schema_version" => 1,
  "run" => {
    "id" => run_id,
    "goal" => goal,
    "goal_file" => goal_file.empty? ? nil : goal_file,
    "state" => "initialized",
    "profile" => profile_id,
    "profile_path" => profile_path,
    "created_at" => now,
    "updated_at" => now,
    "state_history" => [
      {
        "state" => "initialized",
        "at" => now
      }
    ]
  },
  "source_of_truth" => source_of_truth,
  "required_artifacts" => required_artifacts,
  "requested_artifacts" => requested_artifacts,
  "profile" => profile,
  "artifacts" => artifacts,
  "review_attempts" => [],
  "decisions" => [],
  "validation" => []
}

File.write(manifest_path, manifest.to_yaml)
RUBY

echo "$RUN_ID"
echo "manifest: $MANIFEST"
