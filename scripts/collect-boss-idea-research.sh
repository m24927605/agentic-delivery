#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/collect-boss-idea-research.sh [--dry-run] [--force] [--search-results <yaml>] [--output <research.md>] <run-id>

The command derives a market search query pack from a boss idea run, consumes
public-safe search results, and writes a validated market research artifact.
USAGE
}

DRY_RUN=0
FORCE=0
SEARCH_RESULTS=""
OUTPUT=""
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --search-results)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      SEARCH_RESULTS="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      OUTPUT="$2"
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

if [[ -z "$SEARCH_RESULTS" && "$DRY_RUN" -ne 1 ]]; then
  echo "missing --search-results; use --dry-run to generate the query pack only" >&2
  exit 2
fi

RUN_ID="$RUN_ID" \
DRY_RUN="$DRY_RUN" \
FORCE="$FORCE" \
SEARCH_RESULTS="$SEARCH_RESULTS" \
OUTPUT="$OUTPUT" \
ruby <<'RUBY'
require File.expand_path("scripts/lib/boss_idea", Dir.pwd)
require "date"
require "fileutils"
require "time"
require "yaml"

run_id = ENV.fetch("RUN_ID")
dry_run = ENV.fetch("DRY_RUN") == "1"
force = ENV.fetch("FORCE") == "1"
search_results_path = ENV["SEARCH_RESULTS"].to_s
output_path = ENV["OUTPUT"].to_s
run_dir = File.join("agentic/runs", run_id)
manifest_path = File.join(run_dir, "manifest.yaml")
query_pack_path = File.join(run_dir, "market-research-query-pack.yaml")
output_path = File.join(run_dir, "market-research.md") if output_path.empty?
now = Time.now.utc.iso8601
today = Date.today.iso8601

def fail_with(message, code = 1)
  warn message
  exit code
end

def compact_query(value)
  value.to_s.gsub(/\s+/, " ").strip[0, 180]
end

def safe_source_id?(value)
  value.to_s.match?(/\A[a-z][a-z0-9-]*\z/)
end

def load_manifest(path)
  fail_with("invalid manifest path: #{path}") unless BossIdea.repo_local_path?(path)
  fail_with("planning manifest not found: #{path}") unless File.file?(path)

  YAML.safe_load(File.read(path), permitted_classes: [Date], aliases: true) || {}
rescue Psych::SyntaxError => e
  fail_with("invalid YAML in #{path}: #{e.message}")
end

manifest = load_manifest(manifest_path)
run = manifest["run"].is_a?(Hash) ? manifest["run"] : {}
fail_with("run.id must equal #{run_id}") unless run["id"].to_s == run_id
fail_with("run.profile must be boss-idea-response") unless run["profile"].to_s == "boss-idea-response"
intake = manifest["boss_idea_intake"]
BossIdea.required_mapping!(intake, "boss_idea_intake")

raw_idea = intake["raw_idea"].to_s
business_question = intake["business_question"].to_s
target = intake["target_user_or_operator"].to_s
response_class = intake["response_class"].to_s
fail_with("boss_idea_intake.raw_idea is required") if raw_idea.empty?
fail_with("boss_idea_intake.business_question is required") if business_question.empty?

queries = [
  {
    "id" => "competitor_landscape",
    "query" => compact_query("#{business_question} competitors public product docs"),
    "purpose" => "Identify public competitors or adjacent products already addressing the idea."
  },
  {
    "id" => "mainstream_practices",
    "query" => compact_query("#{raw_idea} mainstream practice public report"),
    "purpose" => "Find mainstream approaches, commonly used workflows, and public evidence."
  },
  {
    "id" => "implementation_patterns",
    "query" => compact_query("#{raw_idea} implementation pattern vendor documentation"),
    "purpose" => "Find implementation patterns that can inform feasibility and POC/MVP shape."
  },
  {
    "id" => "operator_workflow",
    "query" => compact_query("#{target.empty? ? "internal operator" : target} #{response_class} workflow alternatives"),
    "purpose" => "Find operator-facing workflow expectations and gaps."
  }
]

query_pack = {
  "schema_version" => 1,
  "run_id" => run_id,
  "generated_at" => now,
  "idea_id" => intake["idea_id"],
  "raw_idea" => raw_idea,
  "business_question" => business_question,
  "queries" => queries,
  "search_result_contract" => {
    "required_file" => "YAML with top-level results array",
    "required_fields" => BossIdea.load_yaml("agentic/schemas/boss-idea-market-search.schema.yaml").dig("schema", "result_required_fields")
  },
  "authority_note" => "Search output is evidence only. It cannot approve artifacts or implementation."
}

if dry_run
  puts query_pack.to_yaml
  puts "boss idea market research query pack ready: #{run_id}"
  exit 0
end

fail_with("invalid output path: #{output_path}", 2) unless BossIdea.repo_local_path?(output_path)
unless output_path.start_with?("#{run_dir}/")
  fail_with("output path must stay under #{run_dir}: #{output_path}", 2)
end
if File.exist?(output_path) && !force
  fail_with("research output already exists: #{output_path}; use --force to overwrite")
end

search = BossIdea.load_yaml(search_results_path)
search_schema = BossIdea.load_yaml("agentic/schemas/boss-idea-market-search.schema.yaml").fetch("schema")
research_schema = BossIdea.load_yaml("agentic/schemas/boss-idea-research.schema.yaml").fetch("schema")
allowed_source_types = Array(research_schema["allowed_source_types"]).map(&:to_s)
allowed_signals = Array(search_schema["allowed_signals"]).map(&:to_s)
required_signals = Array(search_schema["required_signals"]).map(&:to_s)
query_ids = queries.map { |query| query.fetch("id") }
results = BossIdea.require_array!(search, "results", "market_search")
required_result_fields = Array(search_schema["result_required_fields"])

source_ids = []
signals = []
normalized_results = results.map do |result|
  BossIdea.required_mapping!(result, "market_search.results[]")
  BossIdea.require_fields!(result, required_result_fields, "market_search.results[]")
  id = result["id"].to_s
  fail_with("market_search.results[].id must be lowercase slug") unless safe_source_id?(id)
  fail_with("market_search.results[].query_id is unknown: #{result["query_id"]}") unless query_ids.include?(result["query_id"].to_s)
  fail_with("market_search.results[].source_type is invalid: #{result["source_type"]}") unless allowed_source_types.include?(result["source_type"].to_s)
  fail_with("market_search.results[].signal is invalid: #{result["signal"]}") unless allowed_signals.include?(result["signal"].to_s)
  fail_with("market_search.results[].access_date must be YYYY-MM-DD") unless BossIdea.valid_date?(result["access_date"])
  fail_with("market_search.results[].access_date cannot be in the future") if Date.iso8601(result["access_date"].to_s) > Date.today
  claim = result["claim"].to_s
  fail_with("market_search.results[].claim must be one line") if claim.include?("\n")
  fail_with("market_search.results[].claim must be 280 characters or fewer") if claim.length > 280
  reference = result["reference"].to_s
  if reference.match?(%r{\A[a-z][a-z0-9+.-]*://}) && reference !~ %r{\Ahttps?://}
    fail_with("market_search.results[].reference URL must be http or https")
  end
  if result["url"].to_s.length.positive? && result["url"].to_s !~ %r{\Ahttps?://}
    fail_with("market_search.results[].url must be http or https")
  end
  source_ids << id
  signals << result["signal"].to_s
  result
end

duplicates = source_ids.group_by(&:itself).select { |_, values| values.length > 1 }.keys
fail_with("market_search.results[].id duplicates: #{duplicates.join(", ")}") unless duplicates.empty?
missing_signals = required_signals - signals.uniq
fail_with("market_search.results missing required signals: #{missing_signals.join(", ")}") unless missing_signals.empty?

sources = normalized_results.map do |result|
  source = {
    "id" => result["id"].to_s,
    "title" => result["title"].to_s,
    "source_type" => result["source_type"].to_s,
    "access_date" => result["access_date"].to_s,
    "reference" => result["reference"].to_s
  }
  source["url"] = result["url"].to_s if result["url"].to_s.length.positive?
  source
end

claims = normalized_results.map do |result|
  {
    "text" => result["claim"].to_s,
    "source_ids" => [result["id"].to_s]
  }
end

signal_groups = normalized_results.group_by { |result| result["signal"].to_s }
inferences = []
if signal_groups["competitor"] && signal_groups["mainstream_practice"]
  ids = (signal_groups["competitor"] + signal_groups["mainstream_practice"]).map { |result| result["id"].to_s }
  inferences << {
    "text" => "The idea has both competitor and mainstream-practice evidence, so the next decision should compare differentiation before committing implementation scope.",
    "label" => "inference",
    "source_ids" => ids
  }
end
unless signal_groups["differentiator"]
  inferences << {
    "text" => "Differentiation remains unknown because the collected source set does not include a differentiator signal.",
    "label" => "unknown",
    "source_ids" => source_ids
  }
end

frontmatter = {
  "sources" => sources,
  "claims" => claims,
  "inferences" => inferences,
  "raw_evidence_path" => query_pack_path
}

def bullet_lines(results)
  results.map do |result|
    "- #{result["title"]}: #{result["claim"]} [#{result["id"]}]"
  end.join("\n")
end

body = <<~MARKDOWN
  # Market Research Evidence

  ## Search Questions

  #{queries.map { |query| "- #{query["id"]}: #{query["query"]}" }.join("\n")}

  ## Competitor Signals

  #{bullet_lines(signal_groups["competitor"] || [])}

  ## Mainstream Practices

  #{bullet_lines(signal_groups["mainstream_practice"] || [])}

  ## Implementation Patterns

  #{bullet_lines(signal_groups["implementation_pattern"] || [])}

  ## Differentiation Notes

  #{bullet_lines(signal_groups["differentiator"] || [])}

  ## Evidence Gaps

  #{signal_groups["unknown"] ? bullet_lines(signal_groups["unknown"]) : "- No unknown signal was supplied by the search result set."}

  ## Recommended Follow Up

  - Review source freshness before using this research in a decision memo.
  - Add a differentiator signal before making a strong build-vs-buy claim.
  - Treat this artifact as evidence only; approval still requires manifest-backed review.
MARKDOWN

FileUtils.mkdir_p(run_dir)
query_pack_tmp_path = "#{query_pack_path}.tmp"
output_tmp_path = "#{output_path}.tmp"
File.write(query_pack_tmp_path, query_pack.to_yaml)
File.write(output_tmp_path, frontmatter.to_yaml + "---\n" + body)

unless system("scripts/validate-boss-idea-research.sh", output_tmp_path)
  FileUtils.rm_f(query_pack_tmp_path)
  FileUtils.rm_f(output_tmp_path)
  exit(1)
end
File.rename(query_pack_tmp_path, query_pack_path)
File.rename(output_tmp_path, output_path)

manifest["boss_idea_market_research"] = {
  "artifact_path" => output_path,
  "raw_evidence_path" => query_pack_path,
  "source_count" => sources.length,
  "claim_count" => claims.length,
  "query_count" => queries.length,
  "generated_at" => now,
  "authority_note" => "Market research is evidence only and cannot approve implementation."
}
manifest["run"]["updated_at"] = now if manifest["run"].is_a?(Hash)
tmp_path = "#{manifest_path}.tmp"
File.write(tmp_path, manifest.to_yaml)
File.rename(tmp_path, manifest_path)

puts "boss idea market research collected: #{output_path}"
puts "query pack: #{query_pack_path}"
RUBY
