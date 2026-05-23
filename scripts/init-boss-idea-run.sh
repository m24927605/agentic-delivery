#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/init-boss-idea-run.sh [--dry-run] <goal-file>
  scripts/init-boss-idea-run.sh [--dry-run] --goal-file <goal-file>

The goal file must contain public-safe YAML frontmatter for idea intake.
USAGE
}

DRY_RUN=0
GOAL_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --goal-file)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      GOAL_FILE="$2"
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
      if [[ -n "$GOAL_FILE" ]]; then
        echo "unexpected argument: $1" >&2
        usage
        exit 2
      fi
      GOAL_FILE="$1"
      shift
      ;;
  esac
done

if [[ -z "$GOAL_FILE" ]]; then
  usage
  exit 2
fi

GOAL_FILE="$GOAL_FILE" DRY_RUN="$DRY_RUN" ruby <<'RUBY'
require File.expand_path("scripts/lib/boss_idea", Dir.pwd)

goal_file = ENV.fetch("GOAL_FILE")
frontmatter, = BossIdea.load_markdown(goal_file)
BossIdea.required_mapping!(frontmatter, "idea intake frontmatter")

required = %w[
  raw_idea
  decision_owner
  requested_by_role
  requested_response_time
  response_class
  business_question
]
BossIdea.require_fields!(frontmatter, required, "idea_intake")

schema = BossIdea.load_yaml("agentic/schemas/boss-idea-intake.schema.yaml")
allowed_response_classes = Array(schema.dig("schema", "allowed_response_classes")).map(&:to_s)
unless allowed_response_classes.include?(frontmatter["response_class"].to_s)
  BossIdea.fail_with("idea_intake.response_class is invalid: #{frontmatter["response_class"]}", 2)
end

if ENV.fetch("DRY_RUN") == "1"
  puts "boss idea intake ok: #{goal_file}"
end
RUBY

if [[ "$DRY_RUN" -eq 1 ]]; then
  exit 0
fi

RUN_OUTPUT="$(PROFILE=boss-idea-response scripts/init-agentic-run.sh --goal-file "$GOAL_FILE")"
RUN_ID="$(printf '%s\n' "$RUN_OUTPUT" | sed -n '1p')"
MANIFEST="agentic/runs/$RUN_ID/manifest.yaml"

GOAL_FILE="$GOAL_FILE" MANIFEST="$MANIFEST" ruby <<'RUBY'
require File.expand_path("scripts/lib/boss_idea", Dir.pwd)
require "time"

goal_file = ENV.fetch("GOAL_FILE")
manifest_path = ENV.fetch("MANIFEST")
frontmatter, = BossIdea.load_markdown(goal_file)
schema = BossIdea.load_yaml("agentic/schemas/boss-idea-intake.schema.yaml")
allowed_fields = Array(schema.dig("schema", "required_fields")) + Array(schema.dig("schema", "optional_fields"))
intake = frontmatter.select { |key, _| allowed_fields.include?(key.to_s) }
manifest = YAML.load_file(manifest_path)
manifest["boss_idea_intake"] = intake.merge(
  "source_file" => goal_file,
  "recorded_at" => Time.now.utc.iso8601
)
tmp_path = "#{manifest_path}.tmp"
File.write(tmp_path, manifest.to_yaml)
File.rename(tmp_path, manifest_path)
RUBY

printf '%s\n' "$RUN_OUTPUT"
echo "boss idea intake initialized: $RUN_ID"
