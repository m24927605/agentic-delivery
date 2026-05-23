#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/authorize-agentic-action.sh --action <action-id> [--actor <actor-id>] [--role <role-id>] [--format text|json]
USAGE
}

ACTION=""
ACTOR=""
ROLE=""
FORMAT="text"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --action)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      ACTION="$2"
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
    --format)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      FORMAT="$2"
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

if [[ -z "$ACTION" ]]; then
  usage
  exit 2
fi

case "$FORMAT" in
  text|json) ;;
  *)
    echo "invalid format: $FORMAT" >&2
    exit 2
    ;;
esac

ACTION="$ACTION" ACTOR="$ACTOR" ROLE="$ROLE" FORMAT="$FORMAT" ruby <<'RUBY'
require "json"
require File.expand_path("scripts/lib/agentic_identity", Dir.pwd)

policy = AgenticIdentity.load_policy
errors = AgenticIdentity.validate_policy(policy)
unless errors.empty?
  errors.each { |error| warn "invalid identity policy: #{error}" }
  exit 1
end

begin
  auth = AgenticIdentity.authorize!(
    policy,
    action: ENV.fetch("ACTION"),
    actor: ENV["ACTOR"],
    role: ENV["ROLE"]
  )
rescue AgenticIdentity::AuthorizationError => e
  warn "authorization failed: #{e.message}"
  exit 1
end

if ENV.fetch("FORMAT") == "json"
  puts JSON.pretty_generate(auth)
else
  puts "authorization ok: action=#{auth.fetch("action")} actor=#{auth.fetch("actor")} role=#{auth.fetch("actor_role")}"
end
RUBY
