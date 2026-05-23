require "date"
require "fileutils"
require "pathname"
require "yaml"

module BossIdea
  module_function

  def repo_local_path?(path)
    value = path.to_s
    return false if value.empty?
    return false if value.start_with?("/")
    return false if value.split("/").include?("..")

    true
  end

  def load_markdown(path)
    fail_with("invalid file path: #{path}") unless repo_local_path?(path)
    fail_with("file not found: #{path}") unless File.file?(path)
    fail_with("file escapes repo root: #{path}") unless within_repo_root?(path)

    content = File.read(path)
    frontmatter, body = parse_frontmatter(content, path)
    [frontmatter, body, markdown_sections(body)]
  end

  def load_yaml(path)
    fail_with("invalid file path: #{path}") unless repo_local_path?(path)
    fail_with("file not found: #{path}") unless File.file?(path)
    fail_with("file escapes repo root: #{path}") unless within_repo_root?(path)

    YAML.safe_load(File.read(path), permitted_classes: [Date], aliases: false) || {}
  rescue Psych::SyntaxError => e
    fail_with("invalid YAML in #{path}: #{e.message}")
  end

  def parse_frontmatter(content, path)
    return [{}, content] unless content.start_with?("---\n")

    parts = content.split(/^---\s*$/, 3)
    return [{}, content] unless parts.length >= 3

    frontmatter = YAML.safe_load(parts[1], permitted_classes: [Date], aliases: false) || {}
    [stringify_keys(frontmatter), parts[2].sub(/\A\n/, "")]
  rescue Psych::SyntaxError => e
    fail_with("invalid YAML frontmatter in #{path}: #{e.message}")
  end

  def markdown_sections(body)
    sections = {}
    current = nil
    body.each_line do |line|
      if line =~ /^\#{2,6}\s+(.+?)\s*$/
        current = normalize_heading(Regexp.last_match(1))
        sections[current] = +""
      elsif current
        sections[current] << line
      end
    end
    sections.transform_values(&:strip)
  end

  def normalize_heading(value)
    value.to_s.strip.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
  end

  def required_mapping!(value, label)
    fail_with("#{label} must be a mapping") unless value.is_a?(Hash)
    value
  end

  def require_fields!(record, fields, label)
    fields.each do |field|
      value = record[field.to_s]
      if value.nil? || (value.respond_to?(:empty?) && value.empty?)
        fail_with("#{label}.#{field} is required")
      end
    end
  end

  def require_array!(record, field, label)
    value = record[field.to_s]
    fail_with("#{label}.#{field} must be a non-empty array") unless value.is_a?(Array) && !value.empty?
    value
  end

  def require_section!(sections, name, label)
    key = normalize_heading(name)
    value = sections[key].to_s
    fail_with("#{label} section is required: #{name}") if value.empty?
    value
  end

  def valid_date?(value)
    Date.iso8601(value.to_s)
    true
  rescue ArgumentError
    false
  end

  def safe_command?(value)
    command = value.to_s.strip
    return false if command.empty?
    return false if command.start_with?("/")
    return false if command.include?("..")
    return false if command =~ /[;&|`]/

    command.start_with?("scripts/")
  end

  def ignored_or_public_evidence_path?(path)
    value = path.to_s
    return false unless repo_local_path?(value)

    value.start_with?("agentic/reviews/") ||
      value.start_with?("agentic/runs/") ||
      value.start_with?("docs/")
  end

  def within_repo_root?(path)
    root = Pathname.new(Dir.pwd).realpath.to_s
    target = Pathname.new(path).realpath.to_s
    target == root || target.start_with?("#{root}/")
  rescue Errno::ENOENT
    false
  end

  def stringify_keys(value)
    case value
    when Hash
      value.to_h { |key, inner| [key.to_s, stringify_keys(inner)] }
    when Array
      value.map { |inner| stringify_keys(inner) }
    else
      value
    end
  end

  def fail_with(message, code = 1)
    warn message
    exit code
  end
end
