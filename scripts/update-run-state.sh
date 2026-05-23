#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ $# -ne 2 ]]; then
  echo "usage: scripts/update-run-state.sh <run-id> <new-state>" >&2
  exit 2
fi

RUN_ID="$1"
NEW_STATE="$2"
MANIFEST="agentic/runs/$RUN_ID/manifest.yaml"
IMPLEMENTATION_MANIFEST="agentic/runs/$RUN_ID/implementation-manifest.yaml"

case "$RUN_ID" in
  */*|*..*)
    echo "invalid run id: $RUN_ID" >&2
    exit 2
    ;;
esac

if [[ ! -f "$MANIFEST" ]]; then
  if [[ -f "$IMPLEMENTATION_MANIFEST" ]]; then
    MANIFEST="$IMPLEMENTATION_MANIFEST"
  else
    echo "manifest not found: $MANIFEST or $IMPLEMENTATION_MANIFEST" >&2
    exit 1
  fi
fi

RUN_ID="$RUN_ID" NEW_STATE="$NEW_STATE" MANIFEST="$MANIFEST" ruby <<'RUBY'
require "yaml"
require "time"

pipeline = YAML.load_file("agentic/pipeline.yaml")
new_state = ENV.fetch("NEW_STATE")
manifest_path = ENV.fetch("MANIFEST")
valid_states = pipeline.fetch("states").fetch("success") + pipeline.fetch("states").fetch("failure")

unless valid_states.include?(new_state)
  warn "invalid state: #{new_state}"
  warn "valid states: #{valid_states.join(", ")}"
  exit 2
end

manifest = YAML.load_file(manifest_path)
now = Time.now.utc.iso8601
manifest["run"] ||= {}
manifest["run"]["state"] = new_state
manifest["run"]["updated_at"] = now
manifest["run"]["state_history"] ||= []
manifest["run"]["state_history"] << {
  "state" => new_state,
  "at" => now
}

File.write(manifest_path, manifest.to_yaml)
RUBY

echo "updated $RUN_ID -> $NEW_STATE"
