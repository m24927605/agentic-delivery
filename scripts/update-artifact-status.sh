#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/update-artifact-status.sh <run-id> <artifact-path> <status> [--reason <text>] [--actor <actor-id>] [--role <role-id>]

Valid statuses:
  planned drafted reviewed changes_requested approved rejected deferred

Reason is required for approved, rejected, deferred, and changes_requested.
Reason text is stored in the local planning manifest; keep it public-safe.
USAGE
}

if [[ $# -lt 3 ]]; then
  usage
  exit 2
fi

RUN_ID="$1"
ARTIFACT_PATH="$2"
STATUS="$3"
shift 3

REASON=""
ACTOR=""
ROLE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reason)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      REASON="$2"
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
      echo "unexpected argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

case "$RUN_ID" in
  */*|*..*|"")
    echo "invalid run id: $RUN_ID" >&2
    exit 2
    ;;
esac

case "$ARTIFACT_PATH" in
  /*|*..*|"")
    echo "invalid artifact path: $ARTIFACT_PATH" >&2
    exit 2
    ;;
esac

MANIFEST="agentic/runs/$RUN_ID/manifest.yaml"

if [[ ! -f "$MANIFEST" ]]; then
  echo "planning manifest not found: $MANIFEST" >&2
  exit 1
fi

RUN_ID="$RUN_ID" \
ARTIFACT_PATH="$ARTIFACT_PATH" \
STATUS="$STATUS" \
REASON="$REASON" \
MANIFEST="$MANIFEST" \
ACTOR="$ACTOR" \
ROLE="$ROLE" \
ruby <<'RUBY'
require File.expand_path("scripts/lib/agentic_identity", Dir.pwd)
require "yaml"
require "time"

valid_statuses = %w[
  planned
  drafted
  reviewed
  changes_requested
  approved
  rejected
  deferred
]

allowed_transitions = {
  "planned" => %w[planned drafted reviewed approved rejected deferred],
  "drafted" => %w[drafted reviewed changes_requested approved rejected deferred],
  "reviewed" => %w[reviewed changes_requested approved rejected deferred],
  "changes_requested" => %w[changes_requested drafted approved rejected deferred],
  "approved" => %w[approved],
  "rejected" => %w[rejected],
  "deferred" => %w[deferred planned drafted reviewed approved rejected]
}

run_id = ENV.fetch("RUN_ID")
artifact_path = ENV.fetch("ARTIFACT_PATH")
new_status = ENV.fetch("STATUS")
reason = ENV["REASON"].to_s
manifest_path = ENV.fetch("MANIFEST")
actor_input = ENV["ACTOR"].to_s
role_input = ENV["ROLE"].to_s

unless valid_statuses.include?(new_status)
  warn "invalid artifact status: #{new_status}"
  warn "valid statuses: #{valid_statuses.join(", ")}"
  exit 2
end

manifest = YAML.load_file(manifest_path)
run = manifest["run"] || {}
unless run["id"].to_s == run_id
  warn "run.id mismatch: expected #{run_id}, got #{run["id"] || "(empty)"}"
  exit 1
end

artifacts = Array(manifest["artifacts"])
artifact = artifacts.find { |candidate| candidate.is_a?(Hash) && candidate["path"].to_s == artifact_path }

unless artifact
  warn "unknown artifact: #{artifact_path}"
  exit 1
end

old_status = artifact["status"].to_s
old_status = "planned" if old_status.empty?
now = Time.now.utc.iso8601
policy = AgenticIdentity.load_policy
policy_errors = AgenticIdentity.validate_policy(policy)
unless policy_errors.empty?
  policy_errors.each { |error| warn "invalid identity policy: #{error}" }
  exit 1
end

auth_action = new_status == "approved" ? "artifact.approve" : "artifact.status.update"
begin
  auth = AgenticIdentity.authorize!(policy, action: auth_action, actor: actor_input, role: role_input)
  if new_status == "approved"
    AgenticIdentity.actor_must_differ!(
      auth,
      artifact["owner_agent"],
      "blocked_authorization_failed: artifact approver must differ from owner_agent #{artifact["owner_agent"]}"
    )
  end
rescue AgenticIdentity::AuthorizationError => e
  warn "authorization failed: #{e.message}"
  exit 1
end

unless allowed_transitions.fetch(old_status, []).include?(new_status)
  warn "invalid artifact status transition: #{old_status} -> #{new_status}"
  exit 2
end

if %w[approved rejected deferred changes_requested].include?(new_status) && reason.strip.empty?
  warn "reason is required for artifact status: #{new_status}"
  exit 2
end

terminal_decisions = %w[approved rejected deferred changes_requested]

artifact["status"] = new_status
artifact["updated_at"] = now
artifact["updated_by"] = auth.fetch("actor")
artifact["updated_by_role"] = auth.fetch("actor_role")
artifact["decision"] = terminal_decisions.include?(new_status) ? new_status : artifact["decision"]
artifact["decision_reason"] = reason.empty? ? artifact["decision_reason"] : reason
artifact["status_history"] = Array(artifact["status_history"])
artifact["status_history"] << {
  "from_status" => old_status,
  "to_status" => new_status,
  "at" => now,
  "actor" => auth.fetch("actor"),
  "actor_role" => auth.fetch("actor_role"),
  "reason" => reason.empty? ? nil : reason,
  "authorization" => AgenticIdentity.audit_record(auth)
}

case new_status
when "planned"
  artifact["review_state"] ||= "draft"
when "drafted"
  artifact["review_state"] = "draft"
when "reviewed"
  artifact["review_state"] = "reviewed"
when "changes_requested"
  artifact["review_state"] = "changes_requested"
when "approved"
  artifact["strategy_gate_status"] = "pass"
  artifact["review_state"] = "approved"
when "rejected"
  artifact["strategy_gate_status"] = "rejected"
  artifact["review_state"] = "rejected"
when "deferred"
  artifact["strategy_gate_status"] = "deferred"
  artifact["review_state"] = "deferred"
end

manifest["decisions"] = Array(manifest["decisions"])
manifest["decisions"] << {
  "type" => "artifact_status",
  "artifact_path" => artifact_path,
  "from_status" => old_status,
  "to_status" => new_status,
  "reason" => reason.empty? ? nil : reason,
  "actor" => auth.fetch("actor"),
  "actor_role" => auth.fetch("actor_role"),
  "authorization" => AgenticIdentity.audit_record(auth),
  "at" => now
}

manifest["run"] ||= {}
manifest["run"]["updated_at"] = now

File.write(manifest_path, manifest.to_yaml)
RUBY

echo "updated artifact status: $RUN_ID $ARTIFACT_PATH -> $STATUS"
