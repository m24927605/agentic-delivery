#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DRY_RUN=0
RUN_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      echo "usage: scripts/hermes-memory-sync.sh [--dry-run] [run-id]" >&2
      exit 0
      ;;
    --*)
      echo "unknown option: $1" >&2
      exit 2
      ;;
    *)
      RUN_ID="$1"
      shift
      ;;
  esac
done

case "$RUN_ID" in
  */*|*..*)
    echo "invalid run id: $RUN_ID" >&2
    exit 2
    ;;
esac

DRY_RUN="$DRY_RUN" RUN_ID="$RUN_ID" ruby <<'RUBY'
require "time"
require "yaml"

dry_run = ENV.fetch("DRY_RUN") == "1"
run_id = ENV["RUN_ID"].to_s
now = Time.now.utc.iso8601
manifests = if run_id.empty?
  Dir.glob("agentic/runs/*/{manifest.yaml,implementation-manifest.yaml}").sort
else
  [
    File.join("agentic/runs", run_id, "manifest.yaml"),
    File.join("agentic/runs", run_id, "implementation-manifest.yaml")
  ].select { |path| File.file?(path) }
end

payload = {
  "schema_version" => 1,
  "generated_at" => now,
  "dry_run" => dry_run,
  "hermes_enabled" => ENV["HERMES_ENABLED"].to_s != "0",
  "authority" => "repo_manifest",
  "memory_is_authoritative" => false,
  "items" => manifests.map do |path|
    manifest = YAML.load_file(path)
    run = manifest["run"] || {}
    {
      "run_id" => run["id"],
      "mode" => run["mode"].to_s.empty? ? "planning" : run["mode"],
      "state" => run["state"],
      "manifest" => path
    }
  end
}

puts "hermes memory sync dry run: #{dry_run}"
puts payload.to_yaml
RUBY
