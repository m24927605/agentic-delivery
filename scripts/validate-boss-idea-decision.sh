#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ $# -ne 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  echo "usage: scripts/validate-boss-idea-decision.sh <decision.yaml>" >&2
  exit 2
fi

DECISION_FILE="$1" ruby <<'RUBY'
require File.expand_path("scripts/lib/boss_idea", Dir.pwd)

path = ENV.fetch("DECISION_FILE")
data = BossIdea.load_yaml(path)
BossIdea.required_mapping!(data, "decision")
BossIdea.require_fields!(data, %w[decision reason metric_result], "decision")
BossIdea.require_array!(data, "evidence_artifacts", "decision")

normalized = data["decision"].to_s.tr("-", "_")
allowed = %w[go no_go defer pivot research_more]
BossIdea.fail_with("decision.decision is invalid: #{data["decision"]}") unless allowed.include?(normalized)

Array(data["evidence_artifacts"]).each do |path_value|
  BossIdea.fail_with("decision evidence artifact must be repo-local: #{path_value}") unless BossIdea.repo_local_path?(path_value)
end

if normalized == "go"
  BossIdea.fail_with("go decision requires metric_result") if data["metric_result"].to_s.empty?
  unless data["implementation_artifacts_approved"] == true
    BossIdea.fail_with("go decision cannot unblock implementation without approved artifacts")
  end
end

puts "boss idea decision ok: #{path}"
RUBY
