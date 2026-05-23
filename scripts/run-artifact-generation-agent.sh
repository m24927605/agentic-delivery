#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/run-artifact-generation-agent.sh --dry-run <planning-run-id> [--artifact <path>]
  scripts/run-artifact-generation-agent.sh --execute <planning-run-id> [--artifact <path>]

Runs or previews an AI document-generation agent for requested artifacts that
have generation_instructions in the planning manifest. Generated artifacts move
only to drafted; approval still requires update-artifact-status.sh.
USAGE
}

MODE=""
ARTIFACT_FILTER=""
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      MODE="dry-run"
      shift
      ;;
    --execute)
      MODE="execute"
      shift
      ;;
    --artifact)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      ARTIFACT_FILTER="$2"
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
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

if [[ -z "$MODE" || "${#POSITIONAL[@]}" -ne 1 ]]; then
  usage
  exit 2
fi

RUN_ID="${POSITIONAL[0]}"

case "$RUN_ID" in
  */*|*..*|"")
    echo "invalid run id: $RUN_ID" >&2
    exit 2
    ;;
esac

case "$ARTIFACT_FILTER" in
  /*|*..*)
    echo "invalid artifact path: $ARTIFACT_FILTER" >&2
    exit 2
    ;;
esac

MANIFEST="agentic/runs/$RUN_ID/manifest.yaml"

if [[ ! -f "$MANIFEST" ]]; then
  echo "planning manifest not found: $MANIFEST" >&2
  exit 1
fi

if [[ "$MODE" == "execute" ]]; then
  if ! command -v ait >/dev/null 2>&1; then
    echo "ait command not found" >&2
    exit 1
  fi

  if ! command -v claude >/dev/null 2>&1; then
    echo "claude command not found" >&2
    exit 1
  fi
fi

RUN_ID="$RUN_ID" MANIFEST="$MANIFEST" MODE="$MODE" ARTIFACT_FILTER="$ARTIFACT_FILTER" ruby <<'RUBY'
require "digest"
require "fileutils"
require "shellwords"
require "time"
require "yaml"

run_id = ENV.fetch("RUN_ID")
manifest_path = ENV.fetch("MANIFEST")
mode = ENV.fetch("MODE")
artifact_filter = ENV["ARTIFACT_FILTER"].to_s
manifest = YAML.load_file(manifest_path)
run = manifest["run"] || {}
now = Time.now.utc.iso8601

unless run["id"].to_s == run_id
  warn "run.id mismatch: expected #{run_id}, got #{run["id"] || "(empty)"}"
  exit 1
end

def public_safe_path?(path)
  return false if path.to_s.empty?
  return false if path.start_with?("/")
  return false if path.split("/").include?("..")
  true
end

private_patterns = [
  Regexp.new("private product " + "name", Regexp::IGNORECASE),
  Regexp.new("private strategy " + "file", Regexp::IGNORECASE),
  Regexp.new("customer " + "name", Regexp::IGNORECASE),
  Regexp.new("ownership[_-]" + "token", Regexp::IGNORECASE),
  Regexp.new("vu" + "lcan", Regexp::IGNORECASE),
  Regexp.new("secure " + "harness", Regexp::IGNORECASE),
  Regexp.new("private agent runtime " + "gateway", Regexp::IGNORECASE),
  Regexp.new("origin-" + "strategy", Regexp::IGNORECASE)
]

artifacts = Array(manifest["artifacts"]).select { |artifact| artifact.is_a?(Hash) }
artifacts = artifacts.select { |artifact| artifact["path"].to_s == artifact_filter } unless artifact_filter.empty?
artifacts = artifacts.select do |artifact|
  !artifact["generation_instructions"].to_s.strip.empty? &&
    !%w[approved rejected deferred].include?(artifact["status"].to_s)
end

if artifacts.empty?
  warn "no agent-generatable artifacts found"
  exit 1
end

prompt_dir = File.join("agentic/runs", run_id, "artifact-generation")
FileUtils.mkdir_p(prompt_dir)

generated = []

artifacts.each do |artifact|
  path = artifact["path"].to_s
  unless public_safe_path?(path)
    warn "invalid artifact path: #{path}"
    exit 2
  end

  prompt_path = File.join(prompt_dir, path.gsub(%r{[^A-Za-z0-9_.-]+}, "_") + ".prompt.md")
  prompt = <<~PROMPT
    You are generating one public-safe delivery artifact for this repository.

    Run id: #{run_id}
    Goal:
    #{run["goal"]}

    Artifact path:
    #{path}

    Artifact kind:
    #{artifact["kind"]}

    Purpose:
    #{artifact["purpose"]}

    Instructions:
    #{artifact["generation_instructions"]}

    Constraints:
    - Edit only #{path}.
    - Keep content public-safe.
    - Include required implementation-ready sections when generating Markdown:
      Purpose, Scope, Acceptance Criteria, Validation, Rollback, and Review Expectations.
    - Do not include customer identifiers, secrets, private strategy, raw review traces, or internal-only credentials.
    - Do not approve the artifact. Generated content remains draft until manifest status is explicitly approved.
    - Prefer concise, implementation-ready Markdown or YAML matching the target file type.
  PROMPT
  File.write(prompt_path, prompt)

  agent_name = case artifact["owner_agent"].to_s
  when "schema_validation" then "schema-validation-agent"
  when "integration" then "integration-agent"
  when "orchestrator" then "hermes-orchestrator"
  else "document-builder-agent"
  end

  claude_bin = `command -v claude`.strip
  command = [
    "env",
    "-u",
    "ANTHROPIC_API_KEY",
    "ait",
    "run",
    "--adapter",
    "claude-code",
    "--stdin",
    "none",
    "--apply",
    "current",
    "--review",
    "never",
    "--no-auto-commit",
    "--format",
    "json",
    "--",
    "env",
    "-u",
    "ANTHROPIC_API_KEY",
    claude_bin,
    "--add-dir",
    Dir.pwd,
    "--agent",
    agent_name,
    "-p",
    prompt
  ]
  display_command = command.map { |token| Shellwords.escape(token) }.join(" ")

  if mode == "dry-run"
    generated << {
      "path" => path,
      "prompt_path" => prompt_path,
      "command" => display_command,
      "status" => artifact["status"]
    }
    next
  end

  system(*command)
  status = $?
  unless status&.success?
    warn "artifact generation agent failed for #{path}"
    exit(status&.exitstatus || 1)
  end

  unless File.file?(path)
    warn "artifact generation agent did not create artifact: #{path}"
    exit 1
  end

  content = File.read(path)
  matching_private_pattern = private_patterns.find { |pattern| content.match?(pattern) }
  if matching_private_pattern
    warn "generated artifact failed public-safety pattern for #{path}: #{matching_private_pattern.inspect}"
    exit 1
  end

  old_status = artifact["status"].to_s.empty? ? "planned" : artifact["status"].to_s
  artifact["status"] = "drafted"
  artifact["updated_at"] = now
  artifact["updated_by"] = "run-artifact-generation-agent"
  artifact["generation"] = {
    "generated_by" => "scripts/run-artifact-generation-agent.sh",
    "generated_at" => now,
    "prompt_path" => prompt_path,
    "content_sha256" => Digest::SHA256.hexdigest(content),
    "mode" => "ai_agent"
  }
  artifact["status_history"] = Array(artifact["status_history"])
  artifact["status_history"] << {
    "from_status" => old_status,
    "to_status" => "drafted",
    "at" => now,
    "actor" => "run-artifact-generation-agent",
    "reason" => "AI agent generated draft artifact from requested instructions"
  }

  generated << {
    "path" => path,
    "prompt_path" => prompt_path,
    "status" => "drafted",
    "content_sha256" => artifact["generation"]["content_sha256"]
  }
end

manifest["agent_generated_artifacts"] = Array(manifest["agent_generated_artifacts"]) + generated
if mode == "execute"
  manifest["run"]["state"] = "draft_artifacts_ready"
  manifest["run"]["updated_at"] = now
  manifest["run"]["state_history"] = Array(manifest["run"]["state_history"])
  manifest["run"]["state_history"] << {
    "state" => "draft_artifacts_ready",
    "at" => now
  }
File.write(manifest_path, manifest.to_yaml)
end

puts "artifact generation agent #{mode}: #{run_id} artifacts=#{generated.length}"
generated.each { |item| puts "- #{item["path"]} prompt=#{item["prompt_path"]} status=#{item["status"]}" }
RUBY

if [[ "$MODE" == "execute" ]]; then
  if [[ -n "$ARTIFACT_FILTER" ]]; then
    scripts/validate-artifact-templates.sh "$RUN_ID" --artifact "$ARTIFACT_FILTER" >/dev/null
  else
    scripts/validate-artifact-templates.sh "$RUN_ID" >/dev/null
  fi
fi
