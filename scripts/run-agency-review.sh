#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude || true)}"
PROMPT_TEMPLATE="${PROMPT_TEMPLATE:-$ROOT/agentic/prompts/review-agent.md}"
OUT_BASE="${OUT_BASE:-$ROOT/.ait/review-outputs}"
PROFILE="${PROFILE:-}"
REQUESTED_RUN_ID="${RUN_ID:-}"
RUN_ID="${REQUESTED_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"

if [[ -n "$REQUESTED_RUN_ID" ]]; then
  RUN_DIR="$ROOT/agentic/runs/$RUN_ID"
  MANIFEST="$RUN_DIR/manifest.yaml"
  OUT_DIR="$RUN_DIR/review-outputs"
else
  RUN_DIR=""
  MANIFEST=""
  OUT_DIR="$OUT_BASE/$RUN_ID"
fi

PROFILE_ID="$(PROFILE="$PROFILE" ROOT="$ROOT" MANIFEST="$MANIFEST" ruby <<'RUBY'
require "yaml"
root = ENV.fetch("ROOT")
pipeline = YAML.load_file(File.join(root, "agentic/pipeline.yaml"))
manifest_path = ENV["MANIFEST"].to_s
manifest_profile = nil
if !manifest_path.empty? && File.exist?(manifest_path)
  manifest = YAML.load_file(manifest_path)
  manifest_profile = manifest.dig("run", "profile")
end
profile_id = if !ENV["PROFILE"].to_s.empty?
  ENV.fetch("PROFILE")
elsif manifest_profile && !manifest_profile.to_s.empty?
  manifest_profile
else
  pipeline.fetch("pipeline").fetch("default_profile")
end
puts profile_id
RUBY
)"
PROFILE_PATH="$ROOT/agentic/profiles/${PROFILE_ID}.yaml"

if [[ "${USE_CLAUDE_LOGIN_AUTH:-1}" == "1" ]]; then
  unset ANTHROPIC_API_KEY || true
fi

mkdir -p "$OUT_DIR"

if [[ -n "$REQUESTED_RUN_ID" && ! -f "$MANIFEST" ]]; then
  echo "manifest not found for RUN_ID=$RUN_ID: $MANIFEST" >&2
  echo "initialize it first with: scripts/init-agentic-run.sh \"<goal>\"" >&2
  exit 1
fi

if [[ ! -x "$CLAUDE_BIN" ]]; then
  echo "Claude binary not executable: $CLAUDE_BIN" >&2
  exit 1
fi

if [[ ! -f "$PROMPT_TEMPLATE" ]]; then
  echo "Prompt template not found: $PROMPT_TEMPLATE" >&2
  exit 1
fi

if [[ ! -f "$PROFILE_PATH" ]]; then
  echo "Profile not found: $PROFILE_PATH" >&2
  exit 1
fi

if [[ $# -gt 0 ]]; then
  AGENTS=("$@")
else
  AGENTS=()
  while IFS= read -r agent; do
    [[ -n "$agent" ]] && AGENTS+=("$agent")
  done < <(PROFILE_PATH="$PROFILE_PATH" ROOT="$ROOT" ruby <<'RUBY'
require "yaml"

profile = YAML.load_file(ENV.fetch("PROFILE_PATH"))
agents = profile.dig("review_board", "required_agents")

if !agents || agents.empty?
  pipeline = YAML.load_file(File.join(ENV.fetch("ROOT"), "agentic/pipeline.yaml"))
  agents = pipeline.dig("review_board", "default_agents") || []
end

if !agents || agents.empty?
  warn "no review agents configured in profile or pipeline"
  exit 1
end

puts agents
RUBY
)
fi

render_prompt() {
  local agent_name="$1"
  AGENT_NAME="$agent_name" DOC_ROOT="$ROOT" PROFILE_PATH="$PROFILE_PATH" PROMPT_TEMPLATE="$PROMPT_TEMPLATE" ruby <<'RUBY'
require "yaml"

template = File.read(ENV.fetch("PROMPT_TEMPLATE"))
profile = YAML.load_file(ENV.fetch("PROFILE_PATH"))
source_of_truth = profile.fetch("source_of_truth", [])
required_files = profile.dig("review_prompt", "required_files") || []
required_questions = profile.dig("domain", "required_questions") || []
strategy_gate_checks = profile.dig("domain", "strategy_gate_checks") || []
rejected_directions = profile.dig("domain", "rejected_directions") || []
output_sections = profile.dig("review_prompt", "output_sections") || []

def bullet(items)
  items.map { |item| "- #{item}" }.join("\n")
end

def numbered(items)
  items.each_with_index.map { |item, idx| "#{idx + 1}. #{item}" }.join("\n")
end

replacements = {
  "{{AGENT_NAME}}" => ENV.fetch("AGENT_NAME"),
  "{{DOC_ROOT}}" => ENV.fetch("DOC_ROOT"),
  "{{PROFILE_ID}}" => profile.fetch("profile").fetch("id"),
  "{{PROFILE_NAME}}" => profile.fetch("profile").fetch("name"),
  "{{PRIMARY_STRATEGY_DOC}}" => profile.dig("domain", "primary_strategy_doc").to_s,
  "{{PRODUCT_POSITIONING}}" => profile.dig("domain", "product_positioning").to_s,
  "{{SOURCE_OF_TRUTH}}" => numbered(source_of_truth),
  "{{REQUIRED_FILES}}" => numbered(required_files),
  "{{REVIEW_QUESTIONS}}" => bullet(required_questions),
  "{{STRATEGY_GATE_CHECKS}}" => bullet(strategy_gate_checks),
  "{{REJECTED_DIRECTIONS}}" => bullet(rejected_directions),
  "{{OUTPUT_SECTIONS}}" => numbered(output_sections)
}

replacements.each { |key, value| template = template.gsub(key, value) }
puts template
RUBY
}

record_review_attempt() {
  local agent_name="$1"
  local out_file="$2"
  local command_exit="$3"

  if [[ -z "$MANIFEST" ]]; then
    return 0
  fi

  AGENT_NAME="$agent_name" PROFILE_ID="$PROFILE_ID" OUT_FILE="$out_file" COMMAND_EXIT="$command_exit" MANIFEST="$MANIFEST" ROOT="$ROOT" ruby <<'RUBY'
require "json"
require "yaml"
require "time"

manifest_path = ENV.fetch("MANIFEST")
out_file = ENV.fetch("OUT_FILE")
root = ENV.fetch("ROOT")
agent = ENV.fetch("AGENT_NAME")
command_exit = ENV.fetch("COMMAND_EXIT").to_i
now = Time.now.utc.iso8601

relative_out = out_file.start_with?(root + "/") ? out_file[(root.length + 1)..] : out_file

parsed = {}
parse_error = nil
begin
  parsed = JSON.parse(File.read(out_file))
rescue => e
  parse_error = "#{e.class}: #{e.message}"
end

attempt = {
  "agent" => agent,
  "profile" => ENV.fetch("PROFILE_ID", nil),
  "output" => relative_out,
  "command_exit" => command_exit,
  "exit_code" => parsed["exit_code"] || command_exit,
  "verified_status" => parsed.dig("attempt", "attempt", "verified_status"),
  "attempt_id" => parsed["attempt_id"] || parsed.dig("attempt", "attempt", "id"),
  "trace_ref" => parsed.dig("attempt", "evidence_summary", "raw_trace_ref"),
  "recorded_at" => now
}
attempt["parse_error"] = parse_error if parse_error

manifest = YAML.load_file(manifest_path)
manifest["review_attempts"] ||= []
manifest["review_attempts"] << attempt
manifest["run"] ||= {}
manifest["run"]["updated_at"] = now

File.write(manifest_path, manifest.to_yaml)
RUBY
}

overall_status=0

if [[ -n "$REQUESTED_RUN_ID" ]]; then
  "$ROOT/scripts/update-run-state.sh" "$RUN_ID" agency_review_running >/dev/null
fi

for agent in "${AGENTS[@]}"; do
  out_file="$OUT_DIR/${agent}.json"
  prompt="$(render_prompt "$agent")"

  echo "Running agency review: $agent"
  set +e
  ait run --adapter claude-code --stdin none --apply never --review never --format json -- \
    "$CLAUDE_BIN" \
    --add-dir "$ROOT" \
    --agent "$agent" \
    -p "$prompt" > "$out_file"
  command_exit=$?
  set -e

  record_review_attempt "$agent" "$out_file" "$command_exit"

  if [[ "$command_exit" -ne 0 ]]; then
    overall_status="$command_exit"
    echo "Review failed for $agent with exit code $command_exit; continuing to record remaining agents." >&2
  fi

  echo "Wrote $out_file"
done

echo "Agency review output directory: $OUT_DIR"

if [[ -n "$REQUESTED_RUN_ID" ]]; then
  if [[ "$overall_status" -eq 0 ]]; then
    "$ROOT/scripts/update-run-state.sh" "$RUN_ID" agency_review_completed >/dev/null
  else
    "$ROOT/scripts/update-run-state.sh" "$RUN_ID" blocked_review_failed >/dev/null
  fi
fi

exit "$overall_status"
