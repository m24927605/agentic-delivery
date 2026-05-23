#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/run-hermes-action.sh --dry-run <action-id> [key=value ...]
  scripts/run-hermes-action.sh <action-id> [key=value ...]

Execution is enabled only for actions implemented by the current Hermes adapter slice.
USAGE
}

DRY_RUN=0

if [[ $# -gt 0 && "$1" == "--dry-run" ]]; then
  DRY_RUN=1
  shift
fi

if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

ACTION_ID="$1"
shift

if [[ "$ACTION_ID" == "-h" || "$ACTION_ID" == "--help" ]]; then
  usage
  exit 0
fi

HERMES_ACTIONS_FILE="${HERMES_ACTIONS_FILE:-agentic/hermes-actions.yaml}"

if [[ ! -e "$HERMES_ACTIONS_FILE" ]]; then
  echo "Hermes actions file not found: $HERMES_ACTIONS_FILE" >&2
  exit 1
fi

ACTION_ID="$ACTION_ID" DRY_RUN="$DRY_RUN" HERMES_ACTIONS_FILE="$HERMES_ACTIONS_FILE" ruby - "$@" <<'RUBY'
require File.expand_path("scripts/lib/agentic_identity", Dir.pwd)
require "shellwords"
require "time"
require "yaml"

action_id = ENV.fetch("ACTION_ID")
dry_run = ENV.fetch("DRY_RUN") == "1"
actions_file = ENV.fetch("HERMES_ACTIONS_FILE")
errors = []
params = {}

ARGV.each do |argument|
  unless argument.include?("=")
    errors << "invalid argument, expected key=value: #{argument}"
    next
  end

  key, value = argument.split("=", 2)
  if key.to_s.empty?
    errors << "invalid argument with empty key: #{argument}"
    next
  end

  if params.key?(key)
    errors << "duplicate argument: #{key}"
    next
  end

  params[key] = value.to_s
end

unless errors.empty?
  errors.each { |error| warn error }
  exit 2
end

document = YAML.load_file(actions_file)
actions = Array(document["actions"])
action = actions.find { |candidate| candidate.is_a?(Hash) && candidate["id"].to_s == action_id }
identity_actor = params.delete("actor")
identity_role = params.delete("role")

unless action
  warn "undefined Hermes action: #{action_id}"
  exit 1
end

template = action["command_template"].to_s
if template.strip.empty?
  warn "command_template is empty for action: #{action_id}"
  exit 1
end

template_placeholders = template.scan(/\{\{([A-Za-z0-9_]+)\}\}/).flatten.uniq
required_inputs = Array(action["required_inputs"]).map(&:to_s)
optional_inputs = Array(action["optional_inputs"]).map(&:to_s)
input_aliases = action.dig("input_contract", "aliases").is_a?(Hash) ? action.dig("input_contract", "aliases").keys.map(&:to_s) : []

params["profile"] = ENV["PROFILE"].to_s if template_placeholders.include?("profile") && !params.key?("profile") && !ENV["PROFILE"].to_s.strip.empty?
params["run_id"] = ENV["RUN_ID"].to_s if template_placeholders.include?("run_id") && !params.key?("run_id") && !ENV["RUN_ID"].to_s.strip.empty?

if template_placeholders.include?("profile") && !required_inputs.include?("profile") && (!params.key?("profile") || params["profile"].to_s.strip.empty?)
  pipeline = YAML.load_file("agentic/pipeline.yaml")
  params["profile"] = pipeline.fetch("pipeline").fetch("default_profile").to_s
end

if template_placeholders.include?("run_id") && optional_inputs.include?("run_id") && (!params.key?("run_id") || params["run_id"].to_s.strip.empty?)
  params["run_id"] = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
end

if action_id == "start_implementation_run"
  implementation_aliases = %w[planning_run parent_planning_run]
  empty_aliases = implementation_aliases.select { |key| params.key?(key) && params[key].to_s.strip.empty? }
  unless empty_aliases.empty?
    warn "start_implementation_run convenience alias value must not be empty: #{empty_aliases.join(", ")}"
    exit 2
  end

  provided_aliases = implementation_aliases.select { |key| params.key?(key) }

  if params.key?("implementation_args") && !provided_aliases.empty?
    warn "start_implementation_run accepts either implementation_args or one convenience alias, not both"
    exit 2
  end

  if provided_aliases.length > 1
    warn "start_implementation_run accepts only one convenience alias; use implementation_args for combined init-implementation-run.sh arguments"
    exit 2
  end

  if !params.key?("implementation_args")
    if params.key?("planning_run")
      params["implementation_args"] = "--planning-run #{Shellwords.escape(params.fetch("planning_run"))}"
    elsif params.key?("parent_planning_run")
      params["implementation_args"] = "--planning-run #{Shellwords.escape(params.fetch("parent_planning_run"))}"
    end
  end

  implementation_args = params["implementation_args"].to_s.strip
  begin
    implementation_tokens = Shellwords.split(implementation_args)
  rescue ArgumentError => e
    warn "start_implementation_run implementation_args is not valid shell syntax: #{e.message}"
    exit 2
  end

  has_implementation_source = implementation_tokens.each_cons(2).any? do |flag, value|
    flag == "--planning-run" && value.to_s.strip != ""
  end

  unless has_implementation_source
    warn "start_implementation_run requires implementation_args with --planning-run <id>"
    exit 2
  end

  params["implementation_args"] = implementation_tokens.map { |token| Shellwords.escape(token) }.join(" ")
end

known_inputs = (required_inputs + optional_inputs + input_aliases).uniq
unknown_inputs = params.keys.reject { |key| known_inputs.include?(key) }
unless unknown_inputs.empty?
  warn "unknown input(s) for #{action_id}: #{unknown_inputs.join(", ")}"
  exit 2
end

required_inputs.each do |input|
  next if params.key?(input.to_s) && !params[input.to_s].to_s.empty?

  warn "missing required input for #{action_id}: #{input}"
  exit 2
end

missing_template_inputs = template_placeholders.reject { |key| params.key?(key) }
unless missing_template_inputs.empty?
  warn "missing template input(s) for #{action_id}: #{missing_template_inputs.join(", ")}"
  exit 2
end

command = template.gsub(/\{\{([A-Za-z0-9_]+)\}\}/) do
  key = Regexp.last_match(1)
  value = params.fetch(key)
  key == "implementation_args" ? value : Shellwords.escape(value)
end

begin
  tokens = Shellwords.split(command)
rescue ArgumentError => e
  warn "rendered command is not valid shell syntax: #{e.message}"
  exit 1
end

tokens.each do |token|
  next unless token.start_with?("scripts/")

  unless File.file?(token)
    warn "command references missing script: #{token}"
    exit 1
  end
end

if dry_run
  puts command
  exit 0
end

execute_mode = document["execute_mode"].is_a?(Hash) ? document["execute_mode"] : {}
executable_actions = Array(execute_mode["executable_actions"]).map(&:to_s)

unless executable_actions.include?(action_id)
  warn "action execution is not enabled for #{action_id} in this slice; use --dry-run"
  exit 2
end

mutating = Array(action["writes"]).any?
pre_validation = execute_mode["pre_validation_command"].to_s
post_validation = execute_mode["post_validation_command"].to_s
requires_pre_post = execute_mode["mutating_actions_require_pre_post_validation"] == true

if mutating
  authorization = action["authorization"].is_a?(Hash) ? action["authorization"] : {}
  authorization_action = authorization["action"].to_s
  if authorization_action.strip.empty?
    warn "mutating action is missing authorization.action: #{action_id}"
    exit 1
  end

  begin
    policy = AgenticIdentity.load_policy
    policy_errors = AgenticIdentity.validate_policy(policy)
    unless policy_errors.empty?
      policy_errors.each { |error| warn "invalid identity policy: #{error}" }
      exit 1
    end
    auth = AgenticIdentity.authorize!(policy, action: authorization_action, actor: identity_actor, role: identity_role)
  rescue AgenticIdentity::AuthorizationError => e
    warn "authorization failed: #{e.message}"
    exit 1
  end

  ENV["AIT_ACTOR"] = auth.fetch("actor")
  ENV["AIT_ACTOR_ROLE"] = auth.fetch("actor_role")
end

if mutating && requires_pre_post && pre_validation.strip.empty?
  warn "execute_mode pre_validation_command is required for mutating action: #{action_id}"
  exit 1
end

if mutating && requires_pre_post && post_validation.strip.empty?
  warn "execute_mode post_validation_command is required for mutating action: #{action_id}"
  exit 1
end

if mutating && requires_pre_post
  system("bash", "-c", pre_validation)
  pre_status = $?
  exit(pre_status.exitstatus || 1) unless pre_status&.success?
end

system("bash", "-c", command)
status = $?

if status&.exited?
  command_status = status.exitstatus
  if command_status.zero? && mutating && requires_pre_post
    system("bash", "-c", post_validation)
    post_status = $?
    exit(post_status.exitstatus || 1) unless post_status&.success?
  end
  exit(command_status)
end

exit(128 + (status&.termsig || 0))
RUBY
