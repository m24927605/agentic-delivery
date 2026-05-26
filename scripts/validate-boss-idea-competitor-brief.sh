#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ $# -ne 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  echo "usage: scripts/validate-boss-idea-competitor-brief.sh <brief.md>" >&2
  exit 2
fi

BRIEF_FILE="$1" ruby <<'RUBY'
require "set"
require File.expand_path("scripts/lib/boss_idea", Dir.pwd)

FIELD_LABELS = {
  "claim_id" => "Claim ID",
  "competitor_or_alternative" => "Competitor Or Alternative",
  "relevant_capability" => "Relevant Capability",
  "source_ids" => "Source IDs",
  "gap_or_risk" => "Gap Or Risk",
  "implication" => "Implication",
  "source_id" => "Source ID",
  "claim_ids" => "Claim IDs",
  "brief_sections" => "Brief Sections"
}.freeze

BAD_ID_TOKENS = %w[none n/a na unknown tbd ? source-id-or-none].freeze
RAW_PROVIDER_MARKERS = [
  "raw provider text",
  "raw provider response",
  "raw_provider_response",
  "raw page body",
  "raw_page_body",
  "provider_response",
  "begin raw"
].freeze

def split_table_line(line)
  line.to_s.strip.sub(/\A\|/, "").sub(/\|\z/, "").split("|").map(&:strip)
end

def table_separator?(cells)
  cells.all? { |cell| cell.match?(/\A:?-{3,}:?\z/) }
end

def normalize_label(value)
  value.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
end

def markdown_tables(text)
  lines = text.to_s.lines.map(&:strip)
  tables = []
  index = 0

  while index < lines.length
    if lines[index].start_with?("|") && lines[index + 1].to_s.start_with?("|")
      header = split_table_line(lines[index])
      separator = split_table_line(lines[index + 1])
      if !header.empty? && header.length == separator.length && table_separator?(separator)
        rows = []
        cursor = index + 2
        while cursor < lines.length && lines[cursor].start_with?("|")
          row = split_table_line(lines[cursor])
          if row.length != header.length
            BossIdea.fail_with("brief markdown table row has #{row.length} cells but expected #{header.length}")
          end
          rows << row
          cursor += 1
        end
        tables << { header: header, rows: rows }
        index = cursor
        next
      end
    end

    index += 1
  end

  tables
end

def table_with_columns(text, labels)
  expected = labels.map { |label| normalize_label(label) }
  markdown_tables(text).find do |table|
    normalized = table.fetch(:header).map { |label| normalize_label(label) }
    (expected - normalized).empty?
  end
end

def id_values(value)
  value.to_s.gsub("`", "").split(/[,\s;]+/).map(&:strip).reject(&:empty?)
end

def validate_ids!(ids, label, pattern)
  BossIdea.fail_with("#{label} is required") if ids.empty?

  ids.each do |id|
    token = id.downcase
    if BAD_ID_TOKENS.include?(token) || id.include?("<") || id.include?(">")
      BossIdea.fail_with("#{label} has invalid placeholder or empty value: #{id}")
    end
    BossIdea.fail_with("#{label} is invalid: #{id}") unless id.match?(pattern)
  end
end

def claim_text_too_long?(text, limit)
  return false if limit.to_i <= 0

  text.to_s.strip.length > limit.to_i
end

def extract_table_claims(section_name, text, source_pattern, claim_pattern, max_claim_chars)
  table = table_with_columns(text, ["Claim ID", "Source IDs"])
  return [] unless table

  headers = table.fetch(:header).map { |label| normalize_label(label) }
  claim_index = headers.index("claim_id")
  source_index = headers.index("source_ids")
  claims = []

  table.fetch(:rows).each do |row|
    claim_ids = id_values(row.fetch(claim_index, ""))
    BossIdea.fail_with("brief #{section_name} rows must have exactly one Claim ID") unless claim_ids.length == 1
    validate_ids!(claim_ids, "brief #{section_name} claim_id", claim_pattern)

    source_ids = id_values(row.fetch(source_index, ""))
    validate_ids!(source_ids, "brief #{section_name} source_ids", source_pattern)

    claim_text = row.each_with_index.reject { |_, index| [claim_index, source_index].include?(index) }.map(&:first).join(" ")
    if claim_text_too_long?(claim_text, max_claim_chars)
      BossIdea.fail_with("brief #{section_name} claim exceeds #{max_claim_chars} characters")
    end

    claims << { claim_id: claim_ids.first, source_ids: source_ids, section: section_name }
  end

  claims
end

def extract_field_claim(section_name, text, source_pattern, claim_pattern, max_claim_chars)
  claim_value = text[/^\s*[-*]?\s*(?:Evidence\s+)?Claim ID\s*:\s*(.+)$/i, 1].to_s.strip
  source_value = text[/^\s*[-*]?\s*(?:Evidence\s+)?Source IDs\s*:\s*(.+)$/i, 1].to_s.strip
  return [] if claim_value.empty? && source_value.empty?

  claim_ids = id_values(claim_value)
  BossIdea.fail_with("brief #{section_name} must have exactly one Claim ID") unless claim_ids.length == 1
  validate_ids!(claim_ids, "brief #{section_name} claim_id", claim_pattern)

  source_ids = id_values(source_value)
  validate_ids!(source_ids, "brief #{section_name} source_ids", source_pattern)

  claim_lines = text.lines.reject { |line| line.match?(/^\s*[-*]?\s*(?:Evidence\s+)?(Claim ID|Source IDs)\s*:/i) }
  claim_lines.each do |line|
    next if line.strip.empty?
    next if line.strip.match?(/\A[-*]\s*[A-Za-z ]+:\s*\z/)

    if claim_text_too_long?(line.strip, max_claim_chars)
      BossIdea.fail_with("brief #{section_name} claim exceeds #{max_claim_chars} characters")
    end
  end

  [{ claim_id: claim_ids.first, source_ids: source_ids, section: section_name }]
end

def source_mapping_rows(section_text, source_pattern, claim_pattern)
  table = table_with_columns(section_text, ["Source ID", "Claim IDs", "Brief Sections"])
  BossIdea.fail_with("brief source mapping table is required") unless table

  headers = table.fetch(:header).map { |label| normalize_label(label) }
  source_index = headers.index("source_id")
  claims_index = headers.index("claim_ids")
  sections_index = headers.index("brief_sections")

  table.fetch(:rows).map do |row|
    source_ids = id_values(row.fetch(source_index, ""))
    BossIdea.fail_with("brief source mapping rows must have exactly one Source ID") unless source_ids.length == 1
    validate_ids!(source_ids, "brief source_mapping source_id", source_pattern)

    claim_ids = id_values(row.fetch(claims_index, ""))
    validate_ids!(claim_ids, "brief source_mapping claim_ids", claim_pattern)

    brief_sections = row.fetch(sections_index, "").to_s.split(";").map(&:strip).reject(&:empty?)
    BossIdea.fail_with("brief source_mapping brief_sections is required") if brief_sections.empty?

    { source_id: source_ids.first, claim_ids: claim_ids, brief_sections: brief_sections }
  end
end

def authority_segments(text)
  text.to_s.split(/(?<=[.!?])\s+|\n/).map(&:strip).reject(&:empty?)
end

path = ENV.fetch("BRIEF_FILE")
frontmatter, body, sections = BossIdea.load_markdown(path)
BossIdea.required_mapping!(frontmatter, "competitor brief frontmatter")
schema = BossIdea.load_yaml("agentic/schemas/boss-idea-competitor-brief.schema.yaml").fetch("schema")

Array(schema.fetch("required_frontmatter")).each do |field|
  BossIdea.require_fields!(frontmatter, [field], "competitor brief")
end

artifact_status = frontmatter.fetch("artifact_status").to_s
allowed_statuses = Array(schema.fetch("artifact_statuses")).map(&:to_s)
BossIdea.fail_with("competitor brief artifact_status is invalid: #{artifact_status}") unless allowed_statuses.include?(artifact_status)

evidence_inputs = BossIdea.required_mapping!(frontmatter.fetch("evidence_inputs"), "competitor brief evidence_inputs")
Array(schema.fetch("required_evidence_inputs")).each do |field|
  value = evidence_inputs[field].to_s
  BossIdea.fail_with("competitor brief evidence_inputs.#{field} is required") if value.empty?
  BossIdea.fail_with("competitor brief evidence_inputs.#{field} must be repo-local") unless BossIdea.repo_local_path?(value)
  if value.include?("<") || value.include?(">")
    BossIdea.fail_with("competitor brief evidence_inputs.#{field} contains an unfilled placeholder")
  end
end

Array(schema.fetch("required_sections")).each do |name|
  BossIdea.require_section!(sections, name, "competitor brief")
end

boundary = frontmatter.fetch("recommendation_boundary").to_s.downcase
Array(schema.dig("authority_policy", "required_phrases")).each do |phrase|
  BossIdea.fail_with("competitor brief missing recommendation boundary phrase: #{phrase}") unless boundary.include?(phrase)
end

authority_texts = {
  "body" => body,
  "recommendation_boundary" => frontmatter.fetch("recommendation_boundary").to_s
}

Array(schema.dig("authority_policy", "forbidden_phrases")).each do |phrase|
  authority_texts.each do |label, text|
    if text.downcase.include?(phrase)
      BossIdea.fail_with("competitor brief #{label} contains forbidden authority phrase: #{phrase}")
    end
  end
end

Array(schema.dig("authority_policy", "forbidden_patterns")).each do |pattern|
  regex = Regexp.new(pattern, Regexp::IGNORECASE)
  authority_texts.each do |label, text|
    if text.match?(regex)
      BossIdea.fail_with("competitor brief #{label} contains forbidden authority pattern: #{pattern}")
    end
  end
end

surface_pattern = Regexp.new(
  "\\b(#{Array(schema.dig("authority_policy", "prohibited_authority_surfaces")).map { |surface| Regexp.escape(surface) }.join("|")})\\b",
  Regexp::IGNORECASE
)
approval_signal_pattern = Regexp.new(schema.dig("authority_policy", "approval_signal_pattern"), Regexp::IGNORECASE)
negated_approval_pattern = Regexp.new(schema.dig("authority_policy", "negated_approval_pattern"), Regexp::IGNORECASE)
authority_texts.each do |label, text|
  authority_segments(text).each do |segment|
    sanitized_segment = segment.gsub(negated_approval_pattern, "")

    if sanitized_segment.match?(surface_pattern) && sanitized_segment.match?(approval_signal_pattern)
      BossIdea.fail_with("competitor brief #{label} contains forbidden authority claim: #{segment}")
    end
  end
end

if RAW_PROVIDER_MARKERS.any? { |marker| body.downcase.include?(marker) }
  BossIdea.fail_with("competitor brief must not include raw provider text")
end

if body.downcase.include?("source-id-or-none") || body.downcase.match?(/source ids:\s*(none|n\/a|unknown)/)
  BossIdea.fail_with("competitor brief source_ids cannot allow none, n/a, or unknown")
end

source_pattern = Regexp.new(schema.dig("claim_policy", "source_id_pattern"))
claim_pattern = Regexp.new(schema.dig("claim_policy", "claim_id_pattern") || schema.dig("claim_policy", "source_id_pattern"))
max_claim_chars = schema.dig("claim_policy", "max_claim_chars").to_i

competitor_matrix = sections.fetch("competitor_matrix")
matrix_table = table_with_columns(
  competitor_matrix,
  Array(schema.fetch("competitor_matrix_required_columns")).map { |field| FIELD_LABELS.fetch(field) }
)
BossIdea.fail_with("competitor brief competitor matrix is missing required columns") unless matrix_table

source_mapping = sections.fetch("source_mapping")
mapping_rows = source_mapping_rows(source_mapping, source_pattern, claim_pattern)
claim_refs = []
Array(schema.fetch("claim_bearing_sections")).each do |section_name|
  key = BossIdea.normalize_heading(section_name)
  text = sections.fetch(key, "")
  BossIdea.fail_with("brief claim-bearing section is required: #{section_name}") if text.empty?

  section_claims = extract_table_claims(section_name, text, source_pattern, claim_pattern, max_claim_chars)
  section_claims = extract_field_claim(section_name, text, source_pattern, claim_pattern, max_claim_chars) if section_claims.empty?
  BossIdea.fail_with("brief claim-bearing section lacks claim references: #{section_name}") if section_claims.empty?

  claim_refs.concat(section_claims)
end

actual_tuples = Set.new
claim_refs.each do |claim|
  claim.fetch(:source_ids).each do |source_id|
    actual_tuples << [source_id, claim.fetch(:claim_id), BossIdea.normalize_heading(claim.fetch(:section))]
  end
end

valid_section_keys = sections.keys.to_set
mapped_tuples = Set.new
mapping_rows.each do |row|
  row.fetch(:brief_sections).each do |section_name|
    section_key = BossIdea.normalize_heading(section_name)
    unless valid_section_keys.include?(section_key)
      BossIdea.fail_with("brief Source Mapping references unknown section: #{section_name}")
    end

    row.fetch(:claim_ids).each do |claim_id|
      mapped_tuples << [row.fetch(:source_id), claim_id, section_key]
    end
  end
end

missing_tuples = actual_tuples - mapped_tuples
unless missing_tuples.empty?
  source_id, claim_id, section_key = missing_tuples.first
  BossIdea.fail_with("brief claim #{claim_id} with source #{source_id} in #{section_key} is missing from Source Mapping")
end

extra_tuples = mapped_tuples - actual_tuples
unless extra_tuples.empty?
  source_id, claim_id, section_key = extra_tuples.first
  BossIdea.fail_with("brief Source Mapping contains extra tuple: #{source_id} #{claim_id} #{section_key}")
end

puts "boss idea competitor brief ok: #{path}"
RUBY
