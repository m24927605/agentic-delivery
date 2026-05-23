#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

POLICY="${1:-agentic/identity-policy.yaml}"

case "$POLICY" in
  /*|*..*)
    echo "invalid policy path: $POLICY" >&2
    exit 2
    ;;
esac

POLICY="$POLICY" ruby <<'RUBY'
require File.expand_path("scripts/lib/agentic_identity", Dir.pwd)

policy_path = ENV.fetch("POLICY")
policy = AgenticIdentity.load_policy(policy_path)
errors = AgenticIdentity.validate_policy(policy)

unless errors.empty?
  errors.each { |error| warn "invalid identity policy: #{error}" }
  exit 1
end

puts "identity policy ok: #{policy_path}"
puts "roles: #{Array(policy["roles"]).length}"
puts "actors: #{Array(policy["actors"]).length}"
puts "actions: #{policy["actions"].length}"
RUBY
