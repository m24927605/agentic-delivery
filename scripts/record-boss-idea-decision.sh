#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/record-boss-idea-decision.sh <decision.yaml> [--run-id <run-id>] [--actor <actor-id>] [--role <role-id>]
USAGE
}

DECISION_FILE=""
RUN_ID=""
ACTOR=""
ROLE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      RUN_ID="$2"
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
      exit 2
      ;;
    *)
      DECISION_FILE="$1"
      shift
      ;;
  esac
done

if [[ -z "$DECISION_FILE" ]]; then
  usage
  exit 2
fi

scripts/validate-boss-idea-decision.sh "$DECISION_FILE" >/dev/null

DECISION_FILE="$DECISION_FILE" RUN_ID="$RUN_ID" ACTOR="$ACTOR" ROLE="$ROLE" ruby <<'RUBY'
require File.expand_path("scripts/lib/agentic_identity", Dir.pwd)
require File.expand_path("scripts/lib/boss_idea", Dir.pwd)
require "time"

decision_file = ENV.fetch("DECISION_FILE")
run_id = ENV["RUN_ID"].to_s
actor = ENV["ACTOR"].to_s
role = ENV["ROLE"].to_s
decision = BossIdea.load_yaml(decision_file)

policy = AgenticIdentity.load_policy
errors = AgenticIdentity.validate_policy(policy)
BossIdea.fail_with("invalid identity policy: #{errors.join("; ")}") unless errors.empty?
auth = AgenticIdentity.authorize!(policy, action: "boss_idea.decision.record", actor: actor, role: role)

if !run_id.empty?
  BossIdea.fail_with("invalid run id: #{run_id}", 2) unless BossIdea.repo_local_path?(run_id) && !run_id.include?("/")
  manifest_path = "agentic/runs/#{run_id}/manifest.yaml"
  BossIdea.fail_with("planning manifest not found: #{manifest_path}") unless File.file?(manifest_path)
  manifest = YAML.load_file(manifest_path)
  manifest["boss_idea_decisions"] = Array(manifest["boss_idea_decisions"])
  manifest["boss_idea_decisions"] << decision.merge(
    "source_file" => decision_file,
    "recorded_at" => Time.now.utc.iso8601,
    "actor" => auth.fetch("actor"),
    "actor_role" => auth.fetch("actor_role"),
    "authorization" => AgenticIdentity.audit_record(auth)
  )
  manifest["run"] ||= {}
  manifest["run"]["updated_at"] = Time.now.utc.iso8601
  File.write(manifest_path, manifest.to_yaml)
end

puts "boss idea decision recorded: #{decision_file}"
RUBY
