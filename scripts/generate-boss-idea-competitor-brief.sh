#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/generate-boss-idea-competitor-brief.sh [--force] [--output <brief.md>] [--research <market-research.md>] [--quality <quality.yaml>] <run-id>
USAGE
}

FORCE=0
OUTPUT=""
RESEARCH=""
QUALITY=""
RUN_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE=1
      shift
      ;;
    --output)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      OUTPUT="$2"
      shift 2
      ;;
    --research)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      RESEARCH="$2"
      shift 2
      ;;
    --quality)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      QUALITY="$2"
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
      RUN_ID="$1"
      shift
      ;;
  esac
done

if [[ -z "$RUN_ID" ]]; then
  usage
  exit 2
fi

RUN_ID="$RUN_ID" \
FORCE="$FORCE" \
OUTPUT="$OUTPUT" \
RESEARCH="$RESEARCH" \
QUALITY="$QUALITY" \
ruby <<'RUBY'
require File.expand_path("scripts/lib/boss_idea", Dir.pwd)
require "fileutils"
require "pathname"
require "time"
require "yaml"

run_id = ENV.fetch("RUN_ID")
BossIdea.fail_with("invalid run id: #{run_id}", 2) unless BossIdea.repo_local_path?(run_id) && !run_id.include?("/")

force = ENV.fetch("FORCE") == "1"
run_dir = File.join("agentic/runs", run_id)
manifest_path = File.join(run_dir, "manifest.yaml")
output_path = ENV["OUTPUT"].to_s
research_path = ENV["RESEARCH"].to_s
quality_path = ENV["QUALITY"].to_s
output_path = File.join(run_dir, "competitor-brief.md") if output_path.empty?

def load_manifest(path, run_id)
  BossIdea.fail_with("blocked_missing_source: #{path}") unless File.file?(path)
  manifest = YAML.safe_load(File.read(path), permitted_classes: [Date], aliases: true) || {}
  BossIdea.required_mapping!(manifest, "planning manifest")
  run = BossIdea.required_mapping!(manifest["run"], "planning manifest.run")
  BossIdea.fail_with("blocked_schema_invalid: manifest run.id does not match #{run_id}") unless run["id"].to_s == run_id
  BossIdea.fail_with("blocked_schema_invalid: manifest profile must be boss-idea-response") unless run["profile"].to_s == "boss-idea-response"
  BossIdea.require_array!(manifest, "artifacts", "planning manifest")
  manifest
end

def lexists?(path)
  File.lstat(path)
  true
rescue Errno::ENOENT
  false
end

def validate_run_path!(path, run_dir, label)
  BossIdea.fail_with("invalid #{label} path: #{path}", 2) unless BossIdea.repo_local_path?(path)
  unless path.start_with?("#{run_dir}/")
    BossIdea.fail_with("#{label} path must stay under #{run_dir}: #{path}", 2)
  end
end

def reject_symlink_components!(path, run_dir)
  run_path = Pathname.new(run_dir)
  relative = Pathname.new(path).relative_path_from(run_path).to_s
  BossIdea.fail_with("invalid output path: #{path}", 2) if relative.start_with?("../") || relative == ".."

  current = run_dir
  File.dirname(relative).split("/").each do |part|
    next if part.empty? || part == "."

    current = File.join(current, part)
    next unless lexists?(current)

    BossIdea.fail_with("invalid output path uses symlink component: #{current}", 2) if File.lstat(current).symlink?
  end

  if lexists?(path) && File.lstat(path).symlink?
    BossIdea.fail_with("invalid output path is a symlink: #{path}", 2)
  end
end

def prepare_output_target!(path, run_dir)
  BossIdea.fail_with("blocked_missing_source: #{run_dir}") unless File.directory?(run_dir)
  BossIdea.fail_with("invalid run directory is a symlink: #{run_dir}", 2) if File.lstat(run_dir).symlink?

  expected_run_real = Pathname.new(File.expand_path(run_dir, Dir.pwd)).cleanpath.to_s
  run_real = Pathname.new(run_dir).realpath.to_s
  BossIdea.fail_with("invalid run directory realpath: #{run_dir}", 2) unless run_real == expected_run_real

  reject_symlink_components!(File.dirname(path), run_dir)
  FileUtils.mkdir_p(File.dirname(path))
  reject_symlink_components!(path, run_dir)

  output_parent_real = Pathname.new(File.dirname(path)).realpath.to_s
  unless output_parent_real == run_real || output_parent_real.start_with?("#{run_real}/")
    BossIdea.fail_with("invalid output path escapes run directory: #{path}", 2)
  end
end

def clean_repo_path(path)
  Pathname.new(File.expand_path(path, Dir.pwd)).cleanpath.to_s
end

def reserved_conflict!(candidate_clean, reserved_clean_paths, reserved_clean_dirs, label)
  if reserved_clean_paths.include?(candidate_clean)
    BossIdea.fail_with("#{label} conflicts with reserved run artifact", 2)
  end

  if reserved_clean_dirs.any? { |reserved_dir| candidate_clean == reserved_dir || candidate_clean.start_with?("#{reserved_dir}/") }
    BossIdea.fail_with("#{label} conflicts with reserved run evidence directory", 2)
  end
end

def safe_cell(value)
  value.to_s.gsub("|", "/").gsub(/\s+/, " ").strip
end

def ids_cell(ids)
  Array(ids).map(&:to_s).reject(&:empty?).join(", ")
end

def source_ids_for(claim, fallback_ids)
  ids = Array(claim && claim["source_ids"]).map(&:to_s).reject(&:empty?)
  ids.empty? ? fallback_ids : ids
end

def claim_at(claims, index)
  claims[index] || claims.first || {}
end

def mapping_rows(rows)
  rows.flat_map do |row|
    Array(row.fetch(:source_ids)).map do |source_id|
      "| #{source_id} | #{row.fetch(:claim_id)} | #{row.fetch(:section)} |"
    end
  end.join("\n")
end

manifest = load_manifest(manifest_path, run_id)
research_path = manifest.dig("boss_idea_market_research", "artifact_path").to_s if research_path.empty?
quality_path = manifest.dig("boss_idea_market_crawl", "quality_path").to_s if quality_path.empty?
research_path = File.join(run_dir, "market-research.md") if research_path.empty?
quality_path = File.join(run_dir, "market-discovery-quality.yaml") if quality_path.empty?

validate_run_path!(output_path, run_dir, "output")
validate_run_path!(research_path, run_dir, "research")
validate_run_path!(quality_path, run_dir, "quality")
reserved_output_paths = [
  manifest_path,
  research_path,
  quality_path,
  File.join(run_dir, "market-search-results.yaml"),
  File.join(run_dir, "market-candidate-urls.yaml"),
  File.join(run_dir, "market-research-query-pack.yaml"),
  File.join(run_dir, "crawl4ai", "crawl-log.yaml")
]
reserved_output_dirs = [
  File.join(run_dir, "crawl4ai", "raw")
]
%w[results_path candidate_urls_path quality_path crawl_log_path artifact_path].each do |field|
  value = manifest.dig("boss_idea_market_crawl", field).to_s
  reserved_output_paths << value unless value.empty?
end
value = manifest.dig("boss_idea_market_crawl", "raw_evidence_path").to_s
reserved_output_dirs << value unless value.empty?
%w[artifact_path raw_evidence_path].each do |field|
  value = manifest.dig("boss_idea_market_research", field).to_s
  reserved_output_paths << value unless value.empty?
end
output_clean = clean_repo_path(output_path)
reserved_output_paths = reserved_output_paths.flat_map { |path| [path, "#{path}.tmp"] }
reserved_clean_paths = reserved_output_paths.uniq.reject { |path| path.to_s.empty? }.map { |path| clean_repo_path(path) }.uniq
reserved_clean_dirs = reserved_output_dirs.uniq.reject { |path| path.to_s.empty? }.map { |path| clean_repo_path(path) }.uniq
reserved_conflict!(output_clean, reserved_clean_paths, reserved_clean_dirs, "output path")
BossIdea.fail_with("competitor brief output already exists: #{output_path}; use --force to overwrite") if lexists?(output_path) && !force
BossIdea.fail_with("blocked_missing_source: #{research_path}") unless File.file?(research_path)
BossIdea.fail_with("blocked_missing_source: #{quality_path}") unless File.file?(quality_path)

unless system("scripts/validate-boss-idea-research.sh", research_path, out: File::NULL)
  BossIdea.fail_with("blocked_invalid_research: #{research_path}")
end
unless system("scripts/validate-boss-idea-market-discovery-quality.sh", quality_path, out: File::NULL)
  BossIdea.fail_with("blocked_invalid_quality: #{quality_path}")
end

research_frontmatter, = BossIdea.load_markdown(research_path)
quality = BossIdea.load_yaml(quality_path)
unless quality["run_id"].to_s == run_id
  BossIdea.fail_with("blocked_quality_run_mismatch: #{quality_path} run_id must equal #{run_id}")
end
sources = BossIdea.require_array!(research_frontmatter, "sources", "research")
claims = BossIdea.require_array!(research_frontmatter, "claims", "research")
source_ids = sources.map { |source| source["id"].to_s }.reject(&:empty?)
BossIdea.fail_with("blocked_invalid_research: no source ids") if source_ids.empty?

primary_source = sources.first
secondary_source = sources[1] || primary_source
first_claim = claim_at(claims, 0)
second_claim = claim_at(claims, 1)
third_claim = claim_at(claims, 2)
fourth_claim = claim_at(claims, 3)

summary_sources = source_ids_for(first_claim, [primary_source["id"].to_s])
competitor_sources = source_ids_for(first_claim, summary_sources)
mainstream_sources = source_ids_for(second_claim, summary_sources)
implementation_sources = source_ids_for(third_claim, summary_sources)
differentiator_sources = source_ids_for(fourth_claim, summary_sources)

quality_band = quality["band"].to_s
quality_score = quality["score"].to_i
source_count = sources.length
evidence_gaps = Array(quality["evidence_gaps"]).map(&:to_s).reject(&:empty?)
unknown_text = evidence_gaps.first || "Additional market evidence is still needed before a go/no-go decision artifact."

claim_rows = [
  { claim_id: "c-summary-1", source_ids: summary_sources, section: "Executive Summary" },
  { claim_id: "c-comp-1", source_ids: competitor_sources, section: "Competitor Matrix" },
  { claim_id: "c-mainstream-1", source_ids: mainstream_sources, section: "Mainstream Practice Summary" },
  { claim_id: "c-build-1", source_ids: implementation_sources, section: "Build" },
  { claim_id: "c-buy-1", source_ids: competitor_sources, section: "Buy" },
  { claim_id: "c-partner-1", source_ids: differentiator_sources, section: "Partner" },
  { claim_id: "c-defer-1", source_ids: summary_sources, section: "Defer" },
  { claim_id: "c-effort-1", source_ids: implementation_sources, section: "Engineering Effort Band" },
  { claim_id: "c-risk-1", source_ids: summary_sources, section: "Risks, Assumptions, And Unknowns" },
  { claim_id: "c-assumption-1", source_ids: mainstream_sources, section: "Risks, Assumptions, And Unknowns" },
  { claim_id: "c-unknown-1", source_ids: summary_sources, section: "Risks, Assumptions, And Unknowns" },
  { claim_id: "c-experiment-1", source_ids: differentiator_sources, section: "Next Experiment And Timebox" }
]

frontmatter = {
  "artifact_status" => "drafted",
  "evidence_inputs" => {
    "market_research" => research_path,
    "market_discovery_quality" => quality_path
  },
  "recommendation_boundary" => "This brief is evidence only and cannot approve artifacts, decisions, roadmap, budget, implementation, PR publishing, or deployment."
}

brief = <<~MARKDOWN
  ---
  #{frontmatter.to_yaml.sub(/\A---\n/, "")}---
  # Executive Competitor Brief

  ## Executive Summary

  | Claim ID | Summary Claim | Source IDs |
  | --- | --- | --- |
  | c-summary-1 | The validated research set contains #{source_count} source-backed entries and a #{quality_band} discovery-quality band at score #{quality_score}. | #{ids_cell(summary_sources)} |

  ## Competitor Matrix

  | Claim ID | Competitor Or Alternative | Relevant Capability | Source IDs | Gap Or Risk | Implication |
  | --- | --- | --- | --- | --- | --- |
  | c-comp-1 | #{safe_cell(primary_source["title"])} | Source-backed comparable workflow evidence | #{ids_cell(competitor_sources)} | Differentiation is not proven by this brief alone. | Compare against the next experiment result before a decision artifact. |

  ## Mainstream Practice Summary

  | Claim ID | Practice Claim | Source IDs | Unknowns Or Caveats |
  | --- | --- | --- | --- |
  | c-mainstream-1 | Validated evidence includes mainstream-practice context from #{safe_cell(secondary_source["title"])}. | #{ids_cell(mainstream_sources)} | Staffing and demand still require review. |

  ## Build / Buy / Partner / Defer Options

  Compare the four decision paths using the same evidence base.

  ### Build

  - Claim ID: c-build-1
  - Source IDs: #{ids_cell(implementation_sources)}
  - Evidence-backed case: Build path analysis should wait for reviewed artifact evidence.
  - Cost or complexity driver: Internal validation, handoff, and review work.
  - When to choose: Choose build after a separate decision artifact records the path.

  ### Buy

  - Claim ID: c-buy-1
  - Source IDs: #{ids_cell(competitor_sources)}
  - Evidence-backed case: Buy path analysis should compare existing alternatives from the research set.
  - Vendor or ecosystem dependency: Vendor fit and integration constraints need separate review.
  - When to choose: Choose buy after a bounded vendor comparison.

  ### Partner

  - Claim ID: c-partner-1
  - Source IDs: #{ids_cell(differentiator_sources)}
  - Evidence-backed case: Partner path analysis can reduce uncertainty when external workflow evidence is needed.
  - Partner dependency: Partner availability and data access remain constraints.
  - When to choose: Choose partner when access or credibility is the primary gap.

  ### Defer

  - Claim ID: c-defer-1
  - Source IDs: #{ids_cell(summary_sources)}
  - Evidence-backed case: Defer path analysis is appropriate when the evidence base is still thin.
  - Missing evidence: #{safe_cell(unknown_text)}
  - When to choose: Choose defer when the next experiment cannot be timeboxed.

  ## Engineering Effort Band

  Effort band: `unknown`

  Rationale claims:

  | Claim ID | Effort Rationale | Source IDs |
  | --- | --- | --- |
  | c-effort-1 | Effort remains unknown until engineering scope is separated from market evidence. | #{ids_cell(implementation_sources)} |

  ## Risks, Assumptions, And Unknowns

  | Type | Claim ID | Item | Source IDs |
  | --- | --- | --- | --- |
  | Risk | c-risk-1 | The evidence may not show enough differentiation from comparable alternatives. | #{ids_cell(summary_sources)} |
  | Assumption | c-assumption-1 | The decision owner can review the next experiment result within the timebox. | #{ids_cell(mainstream_sources)} |
  | Unknown | c-unknown-1 | #{safe_cell(unknown_text)} | #{ids_cell(summary_sources)} |

  ## Next Experiment And Timebox

  Experiment: Compare the idea against two alternatives from the validated research set.

  Timebox: 5 business days

  Evidence Claim ID: c-experiment-1

  Evidence Source IDs: #{ids_cell(differentiator_sources)}

  Decision after timebox: Submit a separate go/no-go decision artifact; this brief cannot approve implementation.

  ## Source Mapping

  | Source ID | Claim IDs | Brief Sections |
  | --- | --- | --- |
  #{mapping_rows(claim_rows)}
MARKDOWN

prepare_output_target!(output_path, run_dir)
FileUtils.mkdir_p(run_dir)
tmp_path = "#{output_path}.tmp"
reserved_conflict!(clean_repo_path(tmp_path), reserved_clean_paths, reserved_clean_dirs, "temp output path")
if lexists?(tmp_path)
  BossIdea.fail_with("invalid temp output path is a symlink: #{tmp_path}", 2) if File.lstat(tmp_path).symlink?
  FileUtils.rm_f(tmp_path)
end
File.write(tmp_path, brief)
unless system("scripts/validate-boss-idea-competitor-brief.sh", tmp_path, out: File::NULL)
  FileUtils.rm_f(tmp_path)
  BossIdea.fail_with("blocked_invalid_competitor_brief: generated artifact failed validation")
end
File.rename(tmp_path, output_path)

manifest["boss_idea_competitor_brief"] = {
  "artifact_path" => output_path,
  "market_research_path" => research_path,
  "market_discovery_quality_path" => quality_path,
  "source_count" => source_count,
  "claim_count" => claim_rows.length,
  "generated_at" => Time.now.utc.iso8601,
  "authority_note" => "Competitor brief is evidence only and cannot approve implementation, deployment, publishing, roadmap, budget, or go/no-go decisions."
}
manifest["run"]["updated_at"] = Time.now.utc.iso8601 if manifest["run"].is_a?(Hash)
manifest_tmp_path = "#{manifest_path}.tmp"
if lexists?(manifest_tmp_path)
  BossIdea.fail_with("invalid manifest temp path is a symlink: #{manifest_tmp_path}", 2) if File.lstat(manifest_tmp_path).symlink?
  FileUtils.rm_f(manifest_tmp_path)
end
File.write(manifest_tmp_path, manifest.to_yaml)
File.rename(manifest_tmp_path, manifest_path)

puts "boss idea competitor brief generated: #{output_path}"
RUBY
