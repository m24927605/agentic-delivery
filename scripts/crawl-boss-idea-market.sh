#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/crawl-boss-idea-market.sh --dry-run <run-id>
  scripts/crawl-boss-idea-market.sh [--force] [--results-only] <run-id> --from-query-pack --search-provider fixture --output <results.yaml>
  scripts/crawl-boss-idea-market.sh [--force] [--results-only] <run-id> --seeds <seeds.yaml> --output <results.yaml>

The command turns a Boss Idea market query pack into deterministic public-source
crawl/search results for the BIR-09 market research collector. Default fixture
paths never use the public internet. Live provider mode is guarded by both
--live and BOSS_IDEA_LIVE_CRAWL=1 and is reserved for a later approved provider
slice.
USAGE
}

DRY_RUN=0
FORCE=0
RESULTS_ONLY=0
FROM_QUERY_PACK=0
LIVE=0
SEARCH_PROVIDER=""
SEEDS=""
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
    --results-only)
      RESULTS_ONLY=1
      shift
      ;;
    --from-query-pack)
      FROM_QUERY_PACK=1
      shift
      ;;
    --search-provider)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      SEARCH_PROVIDER="$2"
      shift 2
      ;;
    --seeds)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      SEEDS="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      OUTPUT="$2"
      shift 2
      ;;
    --live)
      LIVE=1
      shift
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
DRY_RUN="$DRY_RUN" \
FORCE="$FORCE" \
RESULTS_ONLY="$RESULTS_ONLY" \
FROM_QUERY_PACK="$FROM_QUERY_PACK" \
LIVE="$LIVE" \
SEARCH_PROVIDER="$SEARCH_PROVIDER" \
SEEDS="$SEEDS" \
OUTPUT="$OUTPUT" \
ruby <<'RUBY'
require File.expand_path("scripts/lib/boss_idea", Dir.pwd)
require "cgi"
require "date"
require "fileutils"
require "ipaddr"
require "resolv"
require "set"
require "time"
require "uri"
require "yaml"

run_id = ENV.fetch("RUN_ID")
dry_run = ENV.fetch("DRY_RUN") == "1"
force = ENV.fetch("FORCE") == "1"
results_only = ENV.fetch("RESULTS_ONLY") == "1"
from_query_pack = ENV.fetch("FROM_QUERY_PACK") == "1"
live = ENV.fetch("LIVE") == "1"
live_env = ENV["BOSS_IDEA_LIVE_CRAWL"].to_s == "1"
search_provider = ENV["SEARCH_PROVIDER"].to_s
seeds_path = ENV["SEEDS"].to_s
output_path = ENV["OUTPUT"].to_s

RUN_DIR = File.join("agentic/runs", run_id)
MANIFEST_PATH = File.join(RUN_DIR, "manifest.yaml")
QUERY_PACK_PATH = File.join(RUN_DIR, "market-research-query-pack.yaml")
CANDIDATE_URLS_PATH = File.join(RUN_DIR, "market-candidate-urls.yaml")
RAW_DIR = File.join(RUN_DIR, "crawl4ai/raw")
CRAWL_LOG_PATH = File.join(RUN_DIR, "crawl4ai/crawl-log.yaml")
DEFAULT_FIXTURE_SEEDS = "agentic/fixtures/boss-idea-response/market-crawl-seeds.yaml"
DEFAULT_USER_AGENT = "agentic-delivery-boss-idea-crawler/0.1.0 (+mailto:agentic-delivery@example.invalid)"
ALLOWED_PROVIDERS = %w[fixture seed_replay].freeze
STOP_WORDS = %w[
  a an and are as at be by for from has have in into is it its of on or that
  the this to with without
].freeze

POLICY = {
  "max_candidate_urls_per_query" => 10,
  "max_crawled_pages_per_query" => 5,
  "max_crawled_pages_per_run" => 30,
  "max_redirect_depth" => 3,
  "page_timeout_seconds" => 20,
  "max_response_bytes" => 2 * 1024 * 1024,
  "max_markdown_chars" => 120_000,
  "per_host_concurrency" => 1,
  "minimum_per_host_delay_seconds" => 2,
  "max_consecutive_policy_blocks" => 5,
  "max_total_failures" => 10
}.freeze

def fail_with(message, code = 1)
  warn message
  exit code
end

def safe_slug(value)
  slug = value.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
  slug.empty? ? "source" : slug[0, 64]
end

def compact_query(value)
  value.to_s.gsub(/\s+/, " ").strip[0, 180]
end

def load_manifest(path)
  fail_with("invalid manifest path: #{path}") unless BossIdea.repo_local_path?(path)
  fail_with("planning manifest not found: #{path}") unless File.file?(path)

  YAML.safe_load(File.read(path), permitted_classes: [Date], aliases: true) || {}
rescue Psych::SyntaxError => e
  fail_with("invalid YAML in #{path}: #{e.message}")
end

def generated_query_pack(run_id, manifest)
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

  {
    "schema_version" => 1,
    "run_id" => run_id,
    "generated_at" => Time.now.utc.iso8601,
    "idea_id" => intake["idea_id"],
    "raw_idea" => raw_idea,
    "business_question" => business_question,
    "queries" => queries,
    "search_result_contract" => {
      "required_file" => "YAML with top-level results array",
      "required_fields" => BossIdea.load_yaml("agentic/schemas/boss-idea-market-search.schema.yaml").dig("schema", "result_required_fields")
    },
    "authority_note" => "Search and crawl output is evidence only. It cannot approve artifacts or implementation."
  }
end

def user_agent
  ENV["BOSS_IDEA_CRAWLER_USER_AGENT"].to_s.empty? ? DEFAULT_USER_AGENT : ENV.fetch("BOSS_IDEA_CRAWLER_USER_AGENT")
end

def valid_user_agent?(value)
  value.to_s.match?(/\Aagentic-delivery-boss-idea-crawler\/[0-9A-Za-z._-]+ \(\+mailto:[^)@\s]+@[^)\s]+\)\z/)
end

def blocked_ip?(value)
  ip = IPAddr.new(value.to_s)
  ip.loopback? ||
    ip.private? ||
    ip.link_local? ||
    ip.multicast? ||
    ip.to_s.start_with?("169.254.")
rescue IPAddr::InvalidAddressError
  false
end

def host_ip_literal(host)
  IPAddr.new(host.to_s)
rescue IPAddr::InvalidAddressError
  nil
end

def validate_ip_list!(values, label)
  Array(values).each do |value|
    raise ArgumentError, "#{label} resolves to blocked IP: #{value}" if blocked_ip?(value)
  end
end

def parse_http_url!(value, label)
  uri = URI.parse(value.to_s)
  raise ArgumentError, "#{label} must be http or https" unless %w[http https].include?(uri.scheme)
  raise ArgumentError, "#{label} host is required" if uri.host.to_s.empty?
  host = uri.host.downcase
  raise ArgumentError, "#{label} host is blocked: #{host}" if %w[localhost localhost.localdomain].include?(host) || host.end_with?(".localhost", ".local")
  literal = host_ip_literal(host)
  raise ArgumentError, "#{label} host resolves to blocked IP: #{host}" if literal && blocked_ip?(literal.to_s)
  uri
rescue URI::InvalidURIError
  raise ArgumentError, "#{label} must be a valid URL"
end

def validate_url_policy!(candidate, allow_hosts, redirect_depth = 0)
  raise ArgumentError, "candidate.url exceeds max redirect depth" if redirect_depth > POLICY.fetch("max_redirect_depth")
  url = candidate["url"].to_s
  uri = parse_http_url!(url, "candidate.url")
  host = uri.host.downcase
  raise ArgumentError, "candidate.url host is not in per-run allowlist: #{host}" unless allow_hosts.include?(host)

  validate_ip_list!(candidate["resolved_ips"], "candidate.url")
  validate_ip_list!(candidate["connect_ips"], "candidate.url connect-time")
  if Array(candidate["resolved_ips"]).any? && Array(candidate["connect_ips"]).any?
    safe_before = Array(candidate["resolved_ips"]).none? { |ip| blocked_ip?(ip) }
    blocked_connect = Array(candidate["connect_ips"]).any? { |ip| blocked_ip?(ip) }
    raise ArgumentError, "candidate.url DNS rebinding to blocked IP" if safe_before && blocked_connect
  end

  if candidate.key?("robots_allowed") && candidate["robots_allowed"] == false
    raise ArgumentError, "robots policy disallows crawl: #{url}"
  end
  if candidate.key?("tls_valid") && candidate["tls_valid"] == false
    raise ArgumentError, "TLS certificate validation fails: #{url}"
  end

  redirect_url = candidate["redirect_url"].to_s
  unless redirect_url.empty?
    redirect_candidate = candidate.merge("url" => redirect_url)
    validate_url_policy!(redirect_candidate, allow_hosts, redirect_depth + 1)
  end

  uri
end

def html_to_markdown(content)
  text = content.to_s.dup
  text.gsub!(/<script\b.*?<\/script>/mi, " ")
  text.gsub!(/<style\b.*?<\/style>/mi, " ")
  text.gsub!(/<[^>]+>/, " ")
  CGI.unescapeHTML(text).gsub(/\s+/, " ").strip
end

def words(value)
  value.to_s.downcase.scan(/[a-z0-9]+/)
end

def copyright_safe_claim!(claim, source_text)
  raise ArgumentError, "candidate.claim must be one line" if claim.include?("\n")
  raise ArgumentError, "candidate.claim must be 280 characters or fewer" if claim.length > 280

  claim_words = words(claim)
  source_words = words(source_text)
  if claim_words.length >= 13
    source_ngrams = source_words.each_cons(13).map { |chunk| chunk.join(" ") }.to_set
    claim_words.each_cons(13) do |chunk|
      raise ArgumentError, "candidate.claim copies more than 12 consecutive source words" if source_ngrams.include?(chunk.join(" "))
    end
  end

  filtered_claim = claim_words.reject { |word| STOP_WORDS.include?(word) }
  return if filtered_claim.empty?

  filtered_source = source_words.reject { |word| STOP_WORDS.include?(word) }.uniq
  overlap = (filtered_claim & filtered_source).length.to_f / filtered_claim.length
  raise ArgumentError, "candidate.claim exceeds 20 percent raw-source token overlap" if overlap > 0.20
end

def load_candidates(path)
  fail_with("invalid seeds path: #{path}") unless BossIdea.repo_local_path?(path)
  fail_with("seeds file not found: #{path}") unless File.file?(path)

  data = BossIdea.load_yaml(path)
  candidates = data["candidates"] || data["urls"]
  fail_with("market crawl seeds must contain candidates") unless candidates.is_a?(Array) && !candidates.empty?
  candidates
end

def read_fixture_content(candidate)
  content_path = candidate["content_path"].to_s
  raise ArgumentError, "fixture candidate.content_path is required" if content_path.empty?
  raise ArgumentError, "invalid candidate.content_path: #{content_path}" unless BossIdea.repo_local_path?(content_path)
  raise ArgumentError, "candidate.content_path not found: #{content_path}" unless File.file?(content_path)

  File.read(content_path)
end

manifest = load_manifest(MANIFEST_PATH)
run = manifest["run"].is_a?(Hash) ? manifest["run"] : {}
fail_with("run.id must equal #{run_id}") unless run["id"].to_s == run_id
fail_with("run.profile must be boss-idea-response") unless run["profile"].to_s == "boss-idea-response"

query_pack = if File.file?(QUERY_PACK_PATH)
  BossIdea.load_yaml(QUERY_PACK_PATH)
else
  generated_query_pack(run_id, manifest)
end
query_pack_preexisting = File.file?(QUERY_PACK_PATH)
fail_with("query pack run_id must equal #{run_id}") unless query_pack["run_id"].to_s == run_id
query_ids = query_pack.fetch("queries").map { |query| query.fetch("id") }

if dry_run
  puts query_pack.to_yaml
  puts "boss idea market crawl dry run ready: #{run_id}"
  exit 0
end

fail_with("cannot combine --from-query-pack and --seeds", 2) if from_query_pack && !seeds_path.empty?
fail_with("must specify --from-query-pack or --seeds", 2) unless from_query_pack || !seeds_path.empty?
fail_with("missing --output", 2) if output_path.empty?
fail_with("invalid output path: #{output_path}", 2) unless BossIdea.repo_local_path?(output_path)
fail_with("output path must stay under #{RUN_DIR}: #{output_path}", 2) unless output_path.start_with?("#{RUN_DIR}/")
fail_with("crawl results already exist: #{output_path}; use --force to overwrite") if File.exist?(output_path) && !force

if live || live_env
  fail_with("live crawl requires both --live and BOSS_IDEA_LIVE_CRAWL=1", 2) unless live && live_env
end
if live_env && (!seeds_path.empty? || search_provider == "fixture")
  fail_with("live crawl must use an approved live provider, not fixture or --seeds", 2)
end
if from_query_pack
  fail_with("missing --search-provider", 2) if search_provider.empty?
  if search_provider != "fixture"
    fail_with("public network search/crawl requires --live and BOSS_IDEA_LIVE_CRAWL=1", 2) unless live && live_env
    fail_with("live search provider is not implemented in this slice: #{search_provider}", 2)
  end
  seeds_path = DEFAULT_FIXTURE_SEEDS
end
search_provider = "seed_replay" if search_provider.empty?
fail_with("search provider is not allowed for this slice: #{search_provider}", 2) unless ALLOWED_PROVIDERS.include?(search_provider)

ua = user_agent
fail_with("crawler user-agent is invalid") unless valid_user_agent?(ua)

market_schema = BossIdea.load_yaml("agentic/schemas/boss-idea-market-search.schema.yaml").fetch("schema")
research_schema = BossIdea.load_yaml("agentic/schemas/boss-idea-research.schema.yaml").fetch("schema")
allowed_signals = Array(market_schema["allowed_signals"]).map(&:to_s)
allowed_source_types = Array(research_schema["allowed_source_types"]).map(&:to_s)
candidates = load_candidates(seeds_path)
begin
  allow_hosts = candidates.map { |candidate| parse_http_url!(candidate["url"], "candidate.url").host.downcase }.uniq
rescue ArgumentError => e
  fail_with(e.message)
end

fail_with("candidate URL count exceeds policy") if candidates.length > POLICY.fetch("max_crawled_pages_per_run")
unless force
  [output_path, CANDIDATE_URLS_PATH, CRAWL_LOG_PATH].each do |path|
    fail_with("crawl artifact already exists: #{path}; use --force to overwrite") if File.exist?(path)
  end
  if Dir.exist?(RAW_DIR) && Dir.children(RAW_DIR).any?
    fail_with("raw crawl evidence already exists: #{RAW_DIR}; use --force to overwrite")
  end
end

per_query_counts = Hash.new(0)
candidate_records = []
results = []
crawl_log = {
  "schema_version" => 1,
  "run_id" => run_id,
  "provider" => search_provider,
  "mode" => search_provider == "fixture" ? "fixture" : "seed_replay",
  "user_agent" => ua,
  "policy" => POLICY,
  "entries" => []
}

consecutive_failures = 0
total_failures = 0
failure_messages = []
seen_ids = {}
today = Date.today.iso8601

FileUtils.mkdir_p(RAW_DIR)
fail_with("raw crawl evidence path is not ignored by git: #{RAW_DIR}") unless system("git", "check-ignore", "-q", RAW_DIR)

candidates.each_with_index do |candidate, index|
  begin
    BossIdea.required_mapping!(candidate, "candidates[]")
    %w[query_id url title source_type signal claim].each do |field|
      raise ArgumentError, "candidates[].#{field} is required" if candidate[field].to_s.empty?
    end
    query_id = candidate["query_id"].to_s
    raise ArgumentError, "candidates[].query_id is unknown: #{query_id}" unless query_ids.include?(query_id)
    raise ArgumentError, "candidates[].source_type is invalid: #{candidate["source_type"]}" unless allowed_source_types.include?(candidate["source_type"].to_s)
    raise ArgumentError, "candidates[].signal is invalid: #{candidate["signal"]}" unless allowed_signals.include?(candidate["signal"].to_s)
    per_query_counts[query_id] += 1
    raise ArgumentError, "max crawled pages per query exceeded: #{query_id}" if per_query_counts[query_id] > POLICY.fetch("max_crawled_pages_per_query")

    uri = validate_url_policy!(candidate, allow_hosts)
    extraction_type = candidate["extraction_type"].to_s.empty? ? "markdown" : candidate["extraction_type"].to_s
    raise ArgumentError, "Crawl4AI output must be markdown-only" unless extraction_type == "markdown"

    html = read_fixture_content(candidate)
    raise ArgumentError, "candidate content exceeds max response bytes" if html.bytesize > POLICY.fetch("max_response_bytes")
    markdown = html_to_markdown(html)
    raise ArgumentError, "Crawl4AI returned no usable markdown" if markdown.empty?
    truncated = false
    if markdown.length > POLICY.fetch("max_markdown_chars")
      markdown = markdown[0, POLICY.fetch("max_markdown_chars")]
      truncated = true
    end

    claim = candidate["claim"].to_s.gsub(/\s+/, " ").strip
    copyright_safe_claim!(claim, markdown)
    source_id = candidate["id"].to_s.empty? ? safe_slug(candidate["title"]) : candidate["id"].to_s
    if seen_ids[source_id]
      base_source_id = source_id
      suffix = index + 1
      source_id = "#{base_source_id}-#{suffix}"
      while seen_ids[source_id]
        suffix += 1
        source_id = "#{base_source_id}-#{suffix}"
      end
    end
    seen_ids[source_id] = true
    raw_path = File.join(RAW_DIR, "#{source_id}.md")
    fail_with("raw crawl evidence file is not ignored by git: #{raw_path}") unless system("git", "check-ignore", "-q", raw_path)
    File.write(raw_path, markdown)

    candidate_records << {
      "query_id" => query_id,
      "url" => candidate["url"].to_s,
      "title" => candidate["title"].to_s,
      "snippet" => candidate["snippet"].to_s,
      "provider" => search_provider,
      "retrieved_at" => Time.now.utc.iso8601
    }
    result = {
      "id" => source_id,
      "query_id" => query_id,
      "title" => candidate["title"].to_s,
      "source_type" => candidate["source_type"].to_s,
      "access_date" => candidate["access_date"].to_s.empty? ? today : candidate["access_date"].to_s,
      "reference" => candidate["reference"].to_s.empty? ? candidate["url"].to_s : candidate["reference"].to_s,
      "url" => candidate["url"].to_s,
      "signal" => candidate["signal"].to_s,
      "claim" => claim
    }
    results << result
    crawl_log.fetch("entries") << {
      "url" => candidate["url"].to_s,
      "status" => "success",
      "raw_path" => raw_path,
      "truncated" => truncated
    }
    consecutive_failures = 0
  rescue SystemExit
    raise
  rescue StandardError => e
    consecutive_failures += 1
    total_failures += 1
    failure_messages << e.message
    crawl_log.fetch("entries") << {
      "url" => candidate["url"].to_s,
      "status" => "failed",
      "error" => e.message
    }
    if consecutive_failures >= POLICY.fetch("max_consecutive_policy_blocks") || total_failures >= POLICY.fetch("max_total_failures")
      FileUtils.mkdir_p(File.dirname(CRAWL_LOG_PATH))
      File.write(CRAWL_LOG_PATH, crawl_log.to_yaml)
      fail_with("crawl circuit breaker tripped: #{e.message}")
    end
    next
  end
end

if total_failures.positive?
  FileUtils.mkdir_p(File.dirname(CRAWL_LOG_PATH))
  File.write(CRAWL_LOG_PATH, crawl_log.to_yaml)
  fail_with("crawl failed for #{total_failures} candidate(s): #{failure_messages.uniq.join("; ")}")
end

FileUtils.mkdir_p(File.dirname(output_path))
FileUtils.mkdir_p(File.dirname(CANDIDATE_URLS_PATH))
File.write(QUERY_PACK_PATH, query_pack.to_yaml) unless query_pack_preexisting && !force
File.write(CANDIDATE_URLS_PATH, {
  "schema_version" => 1,
  "run_id" => run_id,
  "provider" => search_provider,
  "candidates" => candidate_records
}.to_yaml)
File.write(CRAWL_LOG_PATH, crawl_log.to_yaml)
File.write(output_path, { "results" => results }.to_yaml)

unless results_only
  research_output = File.join(RUN_DIR, "market-research.md")
  unless system("scripts/collect-boss-idea-research.sh", run_id, "--force", "--search-results", output_path, "--output", research_output)
    fail_with("downstream market research collection failed")
  end
end

manifest = load_manifest(MANIFEST_PATH)
manifest["boss_idea_market_crawl"] = {
  "provider" => search_provider,
  "mode" => search_provider == "fixture" ? "fixture" : "seed_replay",
  "crawl4ai_version" => "not-used-fixture",
  "candidate_urls_path" => CANDIDATE_URLS_PATH,
  "results_path" => output_path,
  "raw_evidence_path" => RAW_DIR,
  "crawl_log_path" => CRAWL_LOG_PATH,
  "policy" => POLICY,
  "source_count" => results.length,
  "generated_at" => Time.now.utc.iso8601,
  "authority_note" => "Crawl/search output is evidence only and cannot approve artifacts or implementation."
}
manifest["run"]["updated_at"] = Time.now.utc.iso8601 if manifest["run"].is_a?(Hash)
tmp_path = "#{MANIFEST_PATH}.tmp"
File.write(tmp_path, manifest.to_yaml)
File.rename(tmp_path, MANIFEST_PATH)

puts "boss idea market crawl collected: #{output_path}"
puts "candidate urls: #{CANDIDATE_URLS_PATH}"
puts "crawl log: #{CRAWL_LOG_PATH}"
RUBY
