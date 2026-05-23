#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ $# -ne 1 ]]; then
  echo "usage: scripts/summarize-agency-review.sh <run-id>" >&2
  exit 2
fi

RUN_ID="$1"
RUN_DIR="agentic/runs/$RUN_ID"
OUT_DIR="$RUN_DIR/review-outputs"
SUMMARY="$RUN_DIR/review-summary.md"
MANIFEST="$RUN_DIR/manifest.yaml"

case "$RUN_ID" in
  */*|*..*)
    echo "invalid run id: $RUN_ID" >&2
    exit 2
    ;;
esac

if [[ ! -d "$OUT_DIR" ]]; then
  echo "review output directory not found: $OUT_DIR" >&2
  exit 1
fi

if ! compgen -G "$OUT_DIR/*.json" >/dev/null; then
  echo "no review json files found in $OUT_DIR" >&2
  exit 1
fi

RUN_ID="$RUN_ID" RUN_DIR="$RUN_DIR" OUT_DIR="$OUT_DIR" SUMMARY="$SUMMARY" MANIFEST="$MANIFEST" ruby <<'RUBY'
require "json"
require "yaml"
require "time"

run_id = ENV.fetch("RUN_ID")
out_dir = ENV.fetch("OUT_DIR")
summary_path = ENV.fetch("SUMMARY")
manifest_path = ENV.fetch("MANIFEST")
now = Time.now.utc.iso8601

rows = []
sections = []

Dir.glob(File.join(out_dir, "*.json")).sort.each do |path|
  agent = File.basename(path, ".json")
  raw = File.read(path)
  parsed = JSON.parse(raw)
  exit_code = parsed["exit_code"]
  verified_status = parsed.dig("attempt", "attempt", "verified_status")
  trace_ref = parsed.dig("attempt", "evidence_summary", "raw_trace_ref")
  stdout = parsed["command_stdout"].to_s.strip
  stderr = parsed["command_stderr"].to_s.strip

  rows << [agent, exit_code, verified_status, trace_ref]

  sections << [
    "## #{agent}",
    "",
    "- `exit_code`: #{exit_code.inspect}",
    "- `verified_status`: #{verified_status.inspect}",
    "- `trace_ref`: #{trace_ref.inspect}",
    "",
    "### stdout",
    "",
    stdout.empty? ? "_No stdout captured._" : stdout,
    "",
    ("### stderr\n\n#{stderr}\n" unless stderr.empty?)
  ].compact.join("\n")
end

table = [
  "| Agent | Exit | AIT verified | Trace reference |",
  "| --- | --- | --- | --- |"
]
rows.each do |agent, exit_code, verified_status, trace_ref|
  table << "| `#{agent}` | #{exit_code.inspect} | #{verified_status.inspect} | `#{trace_ref}` |"
end

content = [
  "# Agency Review Summary",
  "",
  "- `run_id`: `#{run_id}`",
  "- `generated_at`: `#{now}`",
  "",
  table.join("\n"),
  "",
  sections.join("\n\n")
].join("\n")

File.write(summary_path, content)

if File.exist?(manifest_path)
  manifest = YAML.load_file(manifest_path)
  manifest["run"] ||= {}
  manifest["run"]["updated_at"] = now
  manifest["review_summary"] = {
    "path" => summary_path,
    "generated_at" => now,
    "agents" => rows.map(&:first)
  }
  File.write(manifest_path, manifest.to_yaml)
end
RUBY

echo "wrote $SUMMARY"
