#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
PROFILE="${PROFILE:-}"

if [[ $# -eq 0 ]]; then
  echo "usage: scripts/strategy-gate-check.sh <file> [file ...]" >&2
  exit 2
fi

status=0

profile_json="$(PROFILE="$PROFILE" ruby <<'RUBY'
require "json"
require "yaml"

pipeline = YAML.load_file("agentic/pipeline.yaml")
profile_id = ENV["PROFILE"].to_s.empty? ? pipeline.fetch("pipeline").fetch("default_profile") : ENV.fetch("PROFILE")
profile_path = File.join(pipeline.fetch("pipeline").fetch("profile_dir"), "#{profile_id}.yaml")
profile = YAML.load_file(profile_path)
strategy_gate = profile.fetch("strategy_gate", {})
puts JSON.generate({
  profile_id: profile_id,
  anchor_patterns: strategy_gate.fetch("anchor_patterns", []),
  platform_risk_patterns: strategy_gate.fetch("platform_risk_patterns", []),
  internal_tool_terms: strategy_gate.fetch("internal_tool_terms", [])
})
RUBY
)"

anchor_pattern="$(PROFILE_JSON="$profile_json" ruby -rjson -e 'p=JSON.parse(ENV.fetch("PROFILE_JSON")); puts p.fetch("anchor_patterns").join("|")')"
platform_risk_pattern="$(PROFILE_JSON="$profile_json" ruby -rjson -e 'p=JSON.parse(ENV.fetch("PROFILE_JSON")); puts p.fetch("platform_risk_patterns").join("|")')"
internal_tool_pattern="$(PROFILE_JSON="$profile_json" ruby -rjson -e 'p=JSON.parse(ENV.fetch("PROFILE_JSON")); puts p.fetch("internal_tool_terms").join("|")')"
profile_id="$(PROFILE_JSON="$profile_json" ruby -rjson -e 'p=JSON.parse(ENV.fetch("PROFILE_JSON")); puts p.fetch("profile_id")')"

for file in "$@"; do
  if [[ ! -f "$file" ]]; then
    echo "missing: $file" >&2
    status=1
    continue
  fi

  echo "strategy gate [$profile_id]: $file"

  if [[ -n "$anchor_pattern" ]] && ! rg -n "$anchor_pattern" "$file" >/dev/null; then
    echo "  warning: no explicit profile anchor found" >&2
  fi

  if [[ -n "$platform_risk_pattern" ]] && rg -n "$platform_risk_pattern" "$file" >/dev/null; then
    echo "  warning: platform-risk phrase present; ensure it is framed as non-goal or rejected direction" >&2
  fi

  if [[ "$file" == docs/proposals/* || "$file" == docs/backlog/* ]]; then
    if [[ -n "$internal_tool_pattern" ]] && rg -n "$internal_tool_pattern" "$file" >/dev/null; then
      echo "  warning: internal tool term appears in potentially customer-facing artifact" >&2
    fi
  fi
done

exit "$status"
