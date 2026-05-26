#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/run-boss-idea-live-smoke.sh --live [--force] [--search-provider searxng] [--summary <path>] <run-id>

Runs the Boss Idea live smoke sequence for a prepared run:
  1. SearXNG preflight
  2. market discovery and crawl
  3. market discovery quality validation
  4. market research validation

The command requires both --live and BOSS_IDEA_LIVE_CRAWL=1. The summary is
public-safe and must stay under ignored agentic/reviews/ evidence.
USAGE
}

LIVE=0
FORCE=0
SEARCH_PROVIDER="${BOSS_IDEA_LIVE_SMOKE_SEARCH_PROVIDER:-searxng}"
SUMMARY_PATH="${BOSS_IDEA_LIVE_SMOKE_SUMMARY_PATH:-}"
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --live)
      LIVE=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --search-provider)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      SEARCH_PROVIDER="$2"
      shift 2
      ;;
    --summary|--evidence)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      SUMMARY_PATH="$2"
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

if [[ "${#POSITIONAL[@]}" -ne 1 ]]; then
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

RUN_ID="$RUN_ID" \
LIVE="$LIVE" \
FORCE="$FORCE" \
SEARCH_PROVIDER="$SEARCH_PROVIDER" \
SUMMARY_PATH="$SUMMARY_PATH" \
ruby <<'RUBY'
require File.expand_path("scripts/lib/boss_idea", Dir.pwd)
require "fileutils"
require "open3"
require "time"
require "yaml"

AUTHORITY_NOTE = "Boss Idea live smoke evidence is advisory only and cannot approve artifacts, go/no-go decisions, roadmap, budget, implementation, PR publishing, or deployment."

def ignored_path?(path)
  system("git", "check-ignore", "-q", path)
end

def validate_summary_path!(path)
  unless BossIdea.repo_local_path?(path) && path.start_with?("agentic/reviews/")
    warn "live smoke summary path must stay under ignored agentic/reviews/"
    exit 2
  end
  unless ignored_path?(path)
    warn "live smoke summary path is not ignored by git: #{path}"
    exit 2
  end
end

def write_summary(summary)
  path = summary.fetch("summary_path")
  FileUtils.mkdir_p(File.dirname(path))
  tmp_path = "#{path}.tmp"
  File.write(tmp_path, summary.to_yaml)
  File.rename(tmp_path, path)
end

def phase_statuses
  {
    "live_gate" => { "status" => "not_run" },
    "provider_gate" => { "status" => "not_run" },
    "preflight" => { "status" => "not_run" },
    "market_discovery" => { "status" => "not_run" },
    "quality_validation" => { "status" => "not_run" },
    "research_validation" => { "status" => "not_run" }
  }
end

def fail_phase!(summary, phase, message, code = 1)
  summary["status"] = "failed"
  summary["failed_phase"] = phase
  summary["error"] = message
  summary["completed_at"] = Time.now.utc.iso8601
  summary.fetch("phases")[phase] ||= {}
  summary.fetch("phases")[phase]["status"] = "failed"
  summary.fetch("phases")[phase]["error"] = message
  write_summary(summary)
  warn "boss idea live smoke failed: phase=#{phase}: #{message}"
  puts "summary=#{summary.fetch("summary_path")}"
  exit code
end

def run_phase!(summary, phase, command, log_path)
  summary.fetch("phases")[phase] = {
    "status" => "running",
    "log_path" => log_path,
    "command" => command
  }
  write_summary(summary)

  stdout = +""
  stderr = +""
  status = nil
  begin
    stdout, stderr, status = Open3.capture3(*command)
  rescue SystemCallError => e
    FileUtils.mkdir_p(File.dirname(log_path))
    File.write(log_path, e.message)
    fail_phase!(summary, phase, e.message, 1)
  end

  FileUtils.mkdir_p(File.dirname(log_path))
  File.write(log_path, stdout + stderr)
  exit_status = status.exitstatus || 1
  unless status.success?
    summary.fetch("phases")[phase]["status"] = "failed"
    summary.fetch("phases")[phase]["exit_status"] = exit_status
    summary.fetch("phases")[phase]["error"] = "see log_path"
    write_summary(summary)
    fail_phase!(summary, phase, "command failed with exit status #{exit_status}; log=#{log_path}", exit_status)
  end

  summary.fetch("phases")[phase]["status"] = "passed"
  summary.fetch("phases")[phase]["exit_status"] = exit_status
  write_summary(summary)
end

def load_yaml_if_present(path)
  return nil unless File.file?(path)

  YAML.safe_load(File.read(path), aliases: true)
rescue Psych::SyntaxError
  nil
end

run_id = ENV.fetch("RUN_ID")
live = ENV.fetch("LIVE") == "1"
force = ENV.fetch("FORCE") == "1"
provider = ENV.fetch("SEARCH_PROVIDER").to_s
summary_path = ENV["SUMMARY_PATH"].to_s
summary_path = "agentic/reviews/boss-idea-response/live-smoke/#{run_id}/summary.yaml" if summary_path.empty?
validate_summary_path!(summary_path)

evidence_dir = File.dirname(summary_path)
logs_dir = File.join(evidence_dir, "logs")
run_dir = File.join("agentic/runs", run_id)
preflight_evidence_path = File.join(evidence_dir, "searxng-preflight.yaml")
results_path = File.join(run_dir, "market-search-results.yaml")
quality_path = File.join(run_dir, "market-discovery-quality.yaml")
research_path = File.join(run_dir, "market-research.md")

summary = {
  "schema_version" => 1,
  "kind" => "boss_idea_live_smoke_summary",
  "run_id" => run_id,
  "status" => "started",
  "started_at" => Time.now.utc.iso8601,
  "summary_path" => summary_path,
  "provider" => provider,
  "raw_provider_response_recorded" => false,
  "raw_page_body_recorded" => false,
  "authority_note" => AUTHORITY_NOTE,
  "paths" => {
    "preflight_evidence" => preflight_evidence_path,
    "market_results" => results_path,
    "quality" => quality_path,
    "research" => research_path
  },
  "phases" => phase_statuses
}
write_summary(summary)

unless live
  fail_phase!(summary, "live_gate", "missing --live", 2)
end
unless ENV["BOSS_IDEA_LIVE_CRAWL"].to_s == "1"
  fail_phase!(summary, "live_gate", "missing BOSS_IDEA_LIVE_CRAWL=1", 2)
end
summary.fetch("phases")["live_gate"]["status"] = "passed"
write_summary(summary)

if provider == "fixture"
  fail_phase!(summary, "provider_gate", "live smoke cannot run with fixture provider", 2)
end
if provider != "searxng"
  fail_phase!(summary, "provider_gate", "live smoke currently supports only searxng provider because the preflight is SearXNG-specific", 2)
end
unless ENV["BOSS_IDEA_SEARCH_SEARXNG_FIXTURE"].to_s.empty?
  fail_phase!(summary, "provider_gate", "live smoke cannot use BOSS_IDEA_SEARCH_SEARXNG_FIXTURE", 2)
end
summary.fetch("phases")["provider_gate"]["status"] = "passed"
write_summary(summary)

run_phase!(
  summary,
  "preflight",
  ["scripts/boss-idea-searxng-preflight.sh", "--evidence", preflight_evidence_path],
  File.join(logs_dir, "preflight.log")
)
summary["endpoint_label"] = ENV["BOSS_IDEA_SEARCH_SEARXNG_ENDPOINT_LABEL"].to_s unless ENV["BOSS_IDEA_SEARCH_SEARXNG_ENDPOINT_LABEL"].to_s.empty?
write_summary(summary)

market_command = ["scripts/crawl-boss-idea-market.sh", "--live"]
market_command << "--force" if force
market_command.concat([run_id, "--from-query-pack", "--search-provider", provider, "--output", results_path])
run_phase!(
  summary,
  "market_discovery",
  market_command,
  File.join(logs_dir, "market-discovery.log")
)

run_phase!(
  summary,
  "quality_validation",
  ["scripts/validate-boss-idea-market-discovery-quality.sh", quality_path],
  File.join(logs_dir, "quality-validation.log")
)
quality = load_yaml_if_present(quality_path)
if quality.is_a?(Hash)
  summary["quality"] = {
    "provider" => quality["provider"],
    "mode" => quality["mode"],
    "score" => quality["score"],
    "band" => quality["band"],
    "authority_note" => quality["authority_note"]
  }
  write_summary(summary)
end

run_phase!(
  summary,
  "research_validation",
  ["scripts/validate-boss-idea-research.sh", research_path],
  File.join(logs_dir, "research-validation.log")
)

summary["status"] = "passed"
summary["completed_at"] = Time.now.utc.iso8601
write_summary(summary)

puts "boss idea live smoke ok: #{run_id}"
puts "summary=#{summary_path}"
puts "market_results=#{results_path}"
puts "quality=#{quality_path}"
puts "research=#{research_path}"
RUBY
