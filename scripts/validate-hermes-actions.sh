#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ $# -gt 1 ]]; then
  echo "usage: scripts/validate-hermes-actions.sh [actions-yaml]" >&2
  exit 2
fi

ACTIONS_FILE="${1:-agentic/hermes-actions.yaml}"

if [[ ! -e "$ACTIONS_FILE" ]]; then
  echo "Hermes actions file not found: $ACTIONS_FILE" >&2
  exit 1
fi

ACTIONS_FILE="$ACTIONS_FILE" ruby <<'RUBY'
require "yaml"
require File.expand_path("scripts/lib/agentic_identity", Dir.pwd)

path = ENV.fetch("ACTIONS_FILE")
errors = []

begin
  document = YAML.load_file(path)
rescue Psych::SyntaxError => e
  warn "invalid YAML in #{path}: #{e.message}"
  exit 1
end

unless document.is_a?(Hash)
  warn "invalid Hermes actions contract: root must be a mapping"
  exit 1
end

allowed_signal_types = Array(document["success_signal_types"]).map(&:to_s)
if allowed_signal_types.empty?
  errors << "success_signal_types must be present and non-empty"
end

supported_signal_types = %w[
  stdout_contains
  file_exists
  manifest_path
  manifest_field_equals
  directory_has_files
]
unsupported_allowed_signal_types = allowed_signal_types - supported_signal_types
unless unsupported_allowed_signal_types.empty?
  errors << "success_signal_types contains validator-unsupported types: #{unsupported_allowed_signal_types.join(", ")}"
end

actions = document["actions"]
unless actions.is_a?(Array) && !actions.empty?
  errors << "actions must be present and non-empty"
  actions = []
end

execute_mode = document["execute_mode"]
if !execute_mode.is_a?(Hash)
  errors << "execute_mode must be present and a mapping"
  execute_mode = {}
end

executable_actions = Array(execute_mode["executable_actions"]).map(&:to_s)
if executable_actions.empty?
  errors << "execute_mode.executable_actions must be present and non-empty"
end

if execute_mode["mutating_actions_require_pre_post_validation"] == true
  %w[pre_validation_command post_validation_command].each do |field|
    errors << "execute_mode.#{field} is required for mutating actions" if execute_mode[field].to_s.strip.empty?
  end
end

identity_policy = nil
identity_policy_path = document["identity_policy"].to_s.empty? ? "agentic/identity-policy.yaml" : document["identity_policy"].to_s
begin
  identity_policy = AgenticIdentity.load_policy(identity_policy_path)
  AgenticIdentity.validate_policy(identity_policy).each { |error| errors << "identity_policy #{error}" }
rescue AgenticIdentity::PolicyError => e
  errors << e.message
end

required_fields = %w[
  id
  purpose
  mode
  command_template
  required_inputs
  reads
  writes
  success_signals
  failure_states
  retry_policy
]

seen_ids = {}

actions.each_with_index do |action, index|
  prefix = "actions[#{index}]"
  retry_policy = nil

  unless action.is_a?(Hash)
    errors << "#{prefix} must be a mapping"
    next
  end

  required_fields.each do |field|
    errors << "#{prefix}.#{field} is required" unless action.key?(field)
  end

  if action.key?("id")
    id = action["id"].to_s
    if id.empty?
      errors << "#{prefix}.id must not be empty"
    elsif seen_ids.key?(id)
      errors << "#{prefix}.id duplicates actions[#{seen_ids[id]}].id: #{id}"
    else
      seen_ids[id] = index
    end
  end

  if action.key?("command_template")
    command_template = action["command_template"].to_s
    errors << "#{prefix}.command_template must not be empty" if command_template.strip.empty?
  end

  if action.key?("purpose")
    purpose = action["purpose"].to_s
    errors << "#{prefix}.purpose must not be empty" if purpose.strip.empty?
  end

  if action.key?("mode")
    mode = action["mode"].to_s
    if mode.strip.empty?
      errors << "#{prefix}.mode must not be empty"
    elsif !%w[planning implementation both].include?(mode)
      errors << "#{prefix}.mode must be one of: planning, implementation, both"
    end
  end

  %w[required_inputs reads writes success_signals failure_states].each do |field|
    value = action[field]
    errors << "#{prefix}.#{field} must be an array" unless value.is_a?(Array)
  end

  if action.key?("retry_policy")
    retry_policy = action["retry_policy"]

    unless retry_policy.is_a?(Hash)
      errors << "#{prefix}.retry_policy must be a mapping"
      retry_policy = nil
    end
  end

  if retry_policy
    retryable = retry_policy["retryable"]
    max_attempts = retry_policy["max_attempts"]
    requires_human_decision = retry_policy["requires_human_decision_on_exhaustion"]

    unless [true, false].include?(retryable)
      errors << "#{prefix}.retry_policy.retryable must be a boolean"
    end

    unless max_attempts.is_a?(Integer) && max_attempts.positive?
      errors << "#{prefix}.retry_policy.max_attempts must be a positive integer"
    end

    unless [true, false].include?(requires_human_decision)
      errors << "#{prefix}.retry_policy.requires_human_decision_on_exhaustion must be a boolean"
    end
  end

  if action.key?("input_contract")
    input_contract = action["input_contract"]

    unless input_contract.is_a?(Hash)
      errors << "#{prefix}.input_contract must be a mapping"
      input_contract = nil
    end

    if input_contract
      input_contract.each do |contract_key, contract_value|
        if contract_key.to_s == "aliases"
          unless contract_value.is_a?(Hash)
            errors << "#{prefix}.input_contract.aliases must be a mapping"
            next
          end

          contract_value.each do |alias_key, alias_description|
            errors << "#{prefix}.input_contract.aliases contains an empty alias key" if alias_key.to_s.strip.empty?
            errors << "#{prefix}.input_contract.aliases.#{alias_key} must describe the alias" if alias_description.to_s.strip.empty?
          end
        elsif contract_value.to_s.strip.empty?
          errors << "#{prefix}.input_contract.#{contract_key} must describe the input"
        end
      end
    end
  end

  if Array(action["writes"]).any? && executable_actions.include?(action["id"].to_s)
    authorization = action["authorization"]
    if !authorization.is_a?(Hash)
      errors << "#{prefix}.authorization must be present for mutating executable actions"
    elsif authorization["action"].to_s.strip.empty?
      errors << "#{prefix}.authorization.action is required"
    elsif identity_policy && !identity_policy.fetch("actions", {}).key?(authorization["action"].to_s)
      errors << "#{prefix}.authorization.action is not declared in identity policy: #{authorization["action"]}"
    end
  end

  Array(action["success_signals"]).each_with_index do |signal, signal_index|
    signal_prefix = "#{prefix}.success_signals[#{signal_index}]"

    unless signal.is_a?(Hash) && signal.length == 1
      errors << "#{signal_prefix} must be a single-key mapping"
      next
    end

    signal_type = signal.keys.first.to_s
    unless allowed_signal_types.include?(signal_type)
      errors << "#{signal_prefix} uses unknown success signal type: #{signal_type}"
      next
    end

    payload = signal.values.first
    case signal_type
    when "stdout_contains", "file_exists", "manifest_path"
      if payload.to_s.strip.empty?
        errors << "#{signal_prefix}.#{signal_type} must not be empty"
      end
    when "manifest_field_equals"
      unless payload.is_a?(Hash)
        errors << "#{signal_prefix}.manifest_field_equals must be a mapping"
        next
      end

      errors << "#{signal_prefix}.manifest_field_equals.path is required" if payload["path"].to_s.strip.empty?
      errors << "#{signal_prefix}.manifest_field_equals.value is required" unless payload.key?("value")
    when "directory_has_files"
      unless payload.is_a?(Hash)
        errors << "#{signal_prefix}.directory_has_files must be a mapping"
        next
      end

      errors << "#{signal_prefix}.directory_has_files.path is required" if payload["path"].to_s.strip.empty?
      errors << "#{signal_prefix}.directory_has_files.pattern is required" if payload["pattern"].to_s.strip.empty?
    end
  end
end

action_ids = actions.select { |action| action.is_a?(Hash) }.map { |action| action["id"].to_s }
unknown_executable = executable_actions - action_ids
unless unknown_executable.empty?
  errors << "execute_mode.executable_actions references undefined actions: #{unknown_executable.join(", ")}"
end

actions.select { |action| action.is_a?(Hash) }.each_with_index do |action, index|
  writes = Array(action["writes"]).map(&:to_s)
  if execute_mode["mutating_actions_require_pre_post_validation"] == true && executable_actions.include?(action["id"].to_s) && writes.any?
    errors << "actions[#{index}] mutating executable action requires top-level pre/post validation policy" if execute_mode["pre_validation_command"].to_s.strip.empty? || execute_mode["post_validation_command"].to_s.strip.empty?
  end

  (Array(action["reads"]) + writes).each do |path|
    next if path == "*"
    next if path.start_with?("{{")
    if path.start_with?("/") || path.split("/").include?("..")
      errors << "actions[#{index}] contains non repo-local read/write path: #{path}"
    end
  end
end

unless errors.empty?
  errors.each { |error| warn "invalid Hermes actions contract: #{error}" }
  exit 1
end

puts "hermes actions ok: #{path}"
puts "actions: #{actions.length}"
puts "success signal types: #{allowed_signal_types.join(", ")}"
RUBY
