#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ruby <<'RUBY'
require "yaml"

items = Dir.glob("agentic/runs/*/{manifest.yaml,implementation-manifest.yaml}").sort.map do |path|
  manifest = YAML.load_file(path)
  run = manifest["run"] || {}
  {
    "run_id" => run["id"],
    "mode" => run["mode"].to_s.empty? ? "planning" : run["mode"],
    "state" => run["state"],
    "manifest" => path,
    "next_action_source" => "scripts/report-run-status.sh"
  }
end

puts "hermes scheduler dry run"
puts({
  "schema_version" => 1,
  "authority" => "repo_manifest",
  "scheduled_actions" => items
}.to_yaml)
RUBY
