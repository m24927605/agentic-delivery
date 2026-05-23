#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROFILE="${PROFILE:-}"

require_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "missing: $file" >&2
    return 1
  fi
}

missing=0
core_files=(
  agentic/README.md
  agentic/hermes-actions.yaml
  agentic/identity-policy.yaml
  agentic/pipeline.yaml
  agentic/prompts/review-agent.md
  agentic/prompts/strategy-gate.md
  agentic/prompts/integration-agent.md
  agentic/prompts/connector-research-agent.md
  agentic/prompts/code-review-agent.md
  agentic/prompts/document-builder-agent.md
  agentic/prompts/hermes-orchestrator.md
  agentic/prompts/implementation-agent.md
  agentic/prompts/slice-code-review.md
  agentic/prompts/schema-validation-agent.md
  agentic/runs/.gitkeep
  agentic/schemas/artifact-template.schema.yaml
  agentic/schemas/identity-policy.schema.yaml
  agentic/schemas/manifest.schema.yaml
  docs/architecture/hermes-orchestration-adapter.md
  docs/adr/004-hermes-orchestration-adapter.md
  docs/backlog/hermes-adapter-implementation-slices.md
  agentic/fixtures/h8-generate-artifacts/README.md
  agentic/fixtures/h13-hermes-native/README.md
  agentic/fixtures/h20-golden-regression/README.md
  agentic/fixtures/requested-artifacts-goal.md
  scripts/create-artifact-revision-tasks.sh
  scripts/authorize-agentic-action.sh
  scripts/execute-implementation-task.sh
  scripts/generate-artifacts.sh
  scripts/run-artifact-generation-agent.sh
  scripts/run-artifact-review-loop.sh
  scripts/run-implementation-review-loop.sh
  scripts/generate-implementation-task-graph.sh
  scripts/dispatch-implementation-task.sh
  scripts/privacy-scan-tracked.sh
  scripts/record-validation-evidence.sh
  scripts/redact-local-evidence.sh
  scripts/run-golden-fixtures.sh
  scripts/hermes-memory-sync.sh
  scripts/hermes-scheduler-dry-run.sh
  scripts/hermes-gateway-dry-run.sh
  scripts/init-agentic-run.sh
  scripts/init-implementation-run.sh
  scripts/report-run-status.sh
  scripts/run-hermes-action.sh
  scripts/run-agency-review.sh
  scripts/summarize-agency-review.sh
  scripts/strategy-gate-check.sh
  scripts/update-artifact-status.sh
  scripts/update-run-state.sh
  scripts/validate-artifact-templates.sh
  scripts/validate-hermes-actions.sh
  scripts/validate-identity-policy.sh
  scripts/validate-implementation-run.sh
  scripts/validate-manifest-schema.sh
  scripts/init-boss-idea-run.sh
  scripts/validate-boss-idea-research.sh
  scripts/score-boss-idea-feasibility.sh
  scripts/generate-boss-decision-memo.sh
  scripts/validate-boss-decision-memo.sh
  scripts/plan-boss-idea-poc-mvp.sh
  scripts/validate-boss-idea-poc-mvp.sh
  scripts/validate-boss-idea-success-metrics.sh
  scripts/record-boss-idea-decision.sh
  scripts/validate-boss-idea-decision.sh
  scripts/lib/boss_idea.rb
  agentic/schemas/boss-idea-research.schema.yaml
  agentic/schemas/boss-idea-scorecard.schema.yaml
  agentic/schemas/boss-decision-memo.schema.yaml
  agentic/schemas/boss-idea-success-metrics.schema.yaml
  agentic/fixtures/boss-idea-response/valid-idea.md
  agentic/fixtures/boss-idea-response/valid-research.md
  agentic/fixtures/boss-idea-response/valid-scorecard.yaml
  agentic/fixtures/boss-idea-response/valid-memo.md
  agentic/fixtures/boss-idea-response/valid-poc-plan.md
  agentic/fixtures/boss-idea-response/valid-metrics.yaml
  agentic/fixtures/boss-idea-response/valid-decision.yaml
)

for file in "${core_files[@]}"; do
  require_file "$file" || missing=1
done

if [[ ! -d agentic/profiles ]]; then
  echo "missing: agentic/profiles" >&2
  missing=1
fi

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

PROFILE="$PROFILE" ruby <<'RUBY'
require "yaml"

pipeline = YAML.load_file("agentic/pipeline.yaml")
profile_id = ENV["PROFILE"].to_s.empty? ? pipeline.fetch("pipeline").fetch("default_profile") : ENV.fetch("PROFILE")
profile_dir = pipeline.fetch("pipeline").fetch("profile_dir")
profile_path = File.join(profile_dir, "#{profile_id}.yaml")

unless File.file?(profile_path)
  warn "missing profile: #{profile_path}"
  exit 1
end

profile = YAML.load_file(profile_path)
required_paths = [profile_path]
required_paths.concat(Array(profile["source_of_truth"]))

required_artifacts = profile.fetch("required_artifacts", {})
required_artifacts.each_value do |value|
  required_paths.concat(Array(value))
end

required_paths.concat(Array(profile.dig("review_prompt", "required_files")))
missing = required_paths.compact.uniq.reject { |path| File.file?(path) }

unless missing.empty?
  missing.each { |path| warn "missing profile file: #{path}" }
  exit 1
end

Array(pipeline.dig("validation", "syntax", "yaml")).each do |path|
  YAML.load_file(path) if File.file?(path)
end

Dir.glob(File.join(profile_dir, "*.yaml")).sort.each do |path|
  YAML.load_file(path)
end

puts "yaml ok"
puts "profile ok: #{profile_id}"
RUBY

for script in \
  scripts/generate-artifacts.sh \
  scripts/authorize-agentic-action.sh \
  scripts/run-artifact-generation-agent.sh \
  scripts/run-artifact-review-loop.sh \
  scripts/create-artifact-revision-tasks.sh \
  scripts/generate-implementation-task-graph.sh \
  scripts/dispatch-implementation-task.sh \
  scripts/execute-implementation-task.sh \
  scripts/run-implementation-review-loop.sh \
  scripts/privacy-scan-tracked.sh \
  scripts/record-validation-evidence.sh \
  scripts/redact-local-evidence.sh \
  scripts/run-golden-fixtures.sh \
  scripts/hermes-memory-sync.sh \
  scripts/hermes-scheduler-dry-run.sh \
  scripts/hermes-gateway-dry-run.sh \
  scripts/run-agency-review.sh \
  scripts/validate-agentic-system.sh \
  scripts/init-agentic-run.sh \
  scripts/init-implementation-run.sh \
  scripts/report-run-status.sh \
  scripts/run-hermes-action.sh \
  scripts/summarize-agency-review.sh \
  scripts/strategy-gate-check.sh \
  scripts/update-artifact-status.sh \
  scripts/update-run-state.sh \
  scripts/validate-artifact-templates.sh \
  scripts/validate-hermes-actions.sh \
  scripts/validate-identity-policy.sh \
  scripts/validate-implementation-run.sh \
  scripts/validate-manifest-schema.sh \
  scripts/init-boss-idea-run.sh \
  scripts/validate-boss-idea-research.sh \
  scripts/score-boss-idea-feasibility.sh \
  scripts/generate-boss-decision-memo.sh \
  scripts/validate-boss-decision-memo.sh \
  scripts/plan-boss-idea-poc-mvp.sh \
  scripts/validate-boss-idea-poc-mvp.sh \
  scripts/validate-boss-idea-success-metrics.sh \
  scripts/record-boss-idea-decision.sh \
  scripts/validate-boss-idea-decision.sh; do
  bash -n "$script"
done

scripts/privacy-scan-tracked.sh >/dev/null
scripts/validate-identity-policy.sh >/dev/null
scripts/validate-manifest-schema.sh --all >/dev/null
ruby -c scripts/lib/boss_idea.rb >/dev/null

for cmd in ait "$SHELL"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "warning: command not found: $cmd" >&2
  fi
done

claude_bin="${CLAUDE_BIN:-$(command -v claude || true)}"
if [[ -z "$claude_bin" || ! -x "$claude_bin" ]]; then
  echo "warning: Claude binary not executable; set CLAUDE_BIN if needed" >&2
fi

echo "agentic system scaffold ok"
