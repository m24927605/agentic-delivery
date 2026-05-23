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
schema = BossIdea.load_yaml("agentic/schemas/boss-idea-decision.schema.yaml").fetch("schema")
BossIdea.require_fields!(data, Array(schema["required_fields"]), "decision")
BossIdea.require_array!(data, "evidence_artifacts", "decision")

normalized = data["decision"].to_s.tr("-", "_")
allowed = Array(schema["allowed_decisions"]).map(&:to_s)
BossIdea.fail_with("decision.decision is invalid: #{data["decision"]}") unless allowed.include?(normalized)

Array(data["evidence_artifacts"]).each do |path_value|
  unless BossIdea.ignored_or_public_evidence_path?(path_value)
    BossIdea.fail_with("decision evidence artifact must be ignored or public-safe: #{path_value}")
  end
  if path_value.to_s.start_with?("docs/") && !File.file?(path_value)
    BossIdea.fail_with("decision evidence artifact does not exist: #{path_value}")
  end
end

if normalized == "go"
  BossIdea.fail_with("go decision requires metric_result") if data["metric_result"].to_s.empty?
  if schema["go_requires_implementation_artifacts_approved"] == true && data["implementation_artifacts_approved"] != true
    BossIdea.fail_with("go decision cannot unblock implementation without approved artifacts")
  end
elsif data["implementation_artifacts_approved"] == true
  BossIdea.fail_with("only go decision can assert approved implementation artifacts")
end

puts "boss idea decision ok: #{path}"
RUBY
