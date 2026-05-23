#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/validate-manifest-schema.sh [--all]
  scripts/validate-manifest-schema.sh <run-id>
  scripts/validate-manifest-schema.sh <manifest-path>
USAGE
}

if [[ $# -gt 1 ]]; then
  usage
  exit 2
fi

TARGET="${1:---all}"

case "$TARGET" in
  --all) ;;
  -h|--help)
    usage
    exit 0
    ;;
  /*|*..*)
    echo "invalid target: $TARGET" >&2
    exit 2
    ;;
esac

TARGET="$TARGET" ruby <<'RUBY'
require "yaml"

target = ENV.fetch("TARGET")
schema = YAML.load_file("agentic/schemas/manifest.schema.yaml")
errors = []

def repo_local_path?(path)
  return false if path.to_s.empty?
  return false if path.start_with?("/")
  return false if path.split("/").include?("..")
  true
end

def value_at(document, dotted)
  dotted.to_s.split(".").reduce(document) do |value, key|
    value.is_a?(Hash) ? value[key] : nil
  end
end

def validate_required(document, fields, prefix, errors)
  fields.each do |field|
    value = value_at(document, field)
    if value.nil? || (value.is_a?(String) && value.empty?)
      errors << "#{prefix}.#{field} is required"
    end
  end
end

def validate_authorization_record(value, prefix, errors)
  return if value.nil?
  unless value.is_a?(Hash)
    errors << "#{prefix}.authorization must be a mapping"
    return
  end

  %w[action policy identity_authority].each do |field|
    errors << "#{prefix}.authorization.#{field} is required" if value[field].to_s.empty?
  end
end

def validate_planning(path, manifest, schema, errors)
  required_fields = Array(schema.dig("planning_manifest", "required_fields"))
  required_fields = required_fields - ["schema_version"] if manifest["schema_version"].nil?
  validate_required(manifest, required_fields, path, errors)

  run = manifest["run"] || {}
  errors << "#{path}.run.id must match directory" if path =~ %r{agentic/runs/([^/]+)/manifest\.yaml\z} && run["id"].to_s != Regexp.last_match(1)
  errors << "#{path}.run.profile_path not found: #{run["profile_path"]}" if !run["profile_path"].to_s.empty? && !File.file?(run["profile_path"])

  statuses = Array(schema.dig("planning_manifest", "artifact_statuses"))
  Array(manifest["artifacts"]).each_with_index do |artifact, idx|
    unless artifact.is_a?(Hash)
      errors << "#{path}.artifacts[#{idx}] must be a mapping"
      next
    end

    validate_required(artifact, schema.dig("planning_manifest", "artifact_required_fields"), "#{path}.artifacts[#{idx}]", errors)
    artifact_path = artifact["path"].to_s
    errors << "#{path}.artifacts[#{idx}].path must be repo-local: #{artifact_path}" unless repo_local_path?(artifact_path)
    errors << "#{path}.artifacts[#{idx}].status is invalid: #{artifact["status"]}" unless statuses.include?(artifact["status"].to_s)
    errors << "#{path}.artifacts[#{idx}].status_history must be an array" unless artifact["status_history"].is_a?(Array)
    Array(artifact["status_history"]).each_with_index do |entry, history_idx|
      next unless entry.is_a?(Hash)
      validate_authorization_record(entry["authorization"], "#{path}.artifacts[#{idx}].status_history[#{history_idx}]", errors)
    end
  end

  Array(manifest["decisions"]).each_with_index do |decision, idx|
    next unless decision.is_a?(Hash)
    validate_authorization_record(decision["authorization"], "#{path}.decisions[#{idx}]", errors)
  end
end

def validate_implementation(path, manifest, schema, errors)
  required_fields = Array(schema.dig("implementation_manifest", "required_fields"))
  required_fields = required_fields - ["schema_version"] if manifest["schema_version"].nil?
  validate_required(manifest, required_fields, path, errors)

  run = manifest["run"] || {}
  errors << "#{path}.run.id must match directory" if path =~ %r{agentic/runs/([^/]+)/implementation-manifest\.yaml\z} && run["id"].to_s != Regexp.last_match(1)
  errors << "#{path}.run.mode must be implementation" unless run["mode"].to_s == "implementation"
  errors << "#{path}.run.profile_path not found: #{run["profile_path"]}" if !run["profile_path"].to_s.empty? && !File.file?(run["profile_path"])

  task_states = Array(schema.dig("implementation_manifest", "task_states"))
  Array(manifest["implementation_tasks"]).each_with_index do |task, idx|
    unless task.is_a?(Hash)
      errors << "#{path}.implementation_tasks[#{idx}] must be a mapping"
      next
    end

    validate_required(task, schema.dig("implementation_manifest", "task_required_fields"), "#{path}.implementation_tasks[#{idx}]", errors)
    errors << "#{path}.implementation_tasks[#{idx}].state is invalid: #{task["state"]}" unless task_states.include?(task["state"].to_s)
    Array(task["write_scope"]).each do |write_path|
      errors << "#{path}.implementation_tasks[#{idx}].write_scope contains non repo-local path: #{write_path}" unless repo_local_path?(write_path.to_s)
    end
  end

  lease_states = Array(schema.dig("implementation_manifest", "lease_states"))
  Array(manifest["write_scope_leases"]).each_with_index do |lease, idx|
    next errors << "#{path}.write_scope_leases[#{idx}] must be a mapping" unless lease.is_a?(Hash)
    errors << "#{path}.write_scope_leases[#{idx}].state is invalid: #{lease["state"]}" unless lease_states.include?(lease["state"].to_s)
    Array(lease["write_scope"]).each do |write_path|
      errors << "#{path}.write_scope_leases[#{idx}].write_scope contains non repo-local path: #{write_path}" unless repo_local_path?(write_path.to_s)
    end
  end

  result_statuses = Array(schema.dig("implementation_manifest", "worker_result_statuses"))
  Array(manifest["worker_results"]).each_with_index do |result, idx|
    next errors << "#{path}.worker_results[#{idx}] must be a mapping" unless result.is_a?(Hash)
    errors << "#{path}.worker_results[#{idx}].status is invalid: #{result["status"]}" unless result_statuses.include?(result["status"].to_s)
  end
end

paths = if target == "--all"
  Dir.glob("agentic/runs/*/{manifest,implementation-manifest}.yaml").sort
elsif File.file?(target)
  [target]
else
  [
    File.join("agentic/runs", target, "manifest.yaml"),
    File.join("agentic/runs", target, "implementation-manifest.yaml")
  ].select { |path| File.file?(path) }
end

if paths.empty?
  puts "manifest schema ok: no manifests"
  exit 0
end

paths.each do |path|
  manifest = YAML.load_file(path)
  version = manifest["schema_version"]
  if version.nil?
    warn "manifest schema legacy_v0: #{path}"
  elsif version != 1
    errors << "#{path}.schema_version unsupported: #{version}"
  end

  if File.basename(path) == "manifest.yaml"
    validate_planning(path, manifest, schema, errors)
  elsif File.basename(path) == "implementation-manifest.yaml"
    validate_implementation(path, manifest, schema, errors)
  else
    errors << "unknown manifest path: #{path}"
  end
end

unless errors.empty?
  errors.each { |error| warn "invalid manifest schema: #{error}" }
  exit 1
end

puts "manifest schema ok: #{paths.length}"
RUBY
