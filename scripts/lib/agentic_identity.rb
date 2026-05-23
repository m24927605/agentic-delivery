require "yaml"

module AgenticIdentity
  DEFAULT_POLICY_PATH = "agentic/identity-policy.yaml"

  class PolicyError < StandardError; end
  class AuthorizationError < StandardError; end

  module_function

  def load_policy(path = DEFAULT_POLICY_PATH)
    raise PolicyError, "identity policy not found: #{path}" unless File.file?(path)

    YAML.load_file(path)
  end

  def validate_policy(policy)
    errors = []
    errors << "policy root must be a mapping" unless policy.is_a?(Hash)
    return errors unless policy.is_a?(Hash)

    errors << "version must be 1" unless policy["version"] == 1
    errors << "identity_authority must be repo_local_asserted_actor" unless policy["identity_authority"].to_s == "repo_local_asserted_actor"

    defaults = policy["defaults"].is_a?(Hash) ? policy["defaults"] : {}
    roles = index_records(policy["roles"], "roles", errors)
    actors = index_records(policy["actors"], "actors", errors)
    actions = policy["actions"].is_a?(Hash) ? policy["actions"] : {}

    errors << "defaults.actor is required" if defaults["actor"].to_s.empty?
    errors << "defaults.role is required" if defaults["role"].to_s.empty?
    errors << "actions must be a non-empty mapping" if actions.empty?

    actors.each do |actor_id, actor|
      actor_roles = Array(actor["roles"]).map(&:to_s)
      errors << "actors.#{actor_id}.roles must not be empty" if actor_roles.empty?
      actor_roles.each do |role|
        errors << "actors.#{actor_id}.roles references unknown role: #{role}" unless roles.key?(role)
      end

      default_role = actor["default_role"].to_s
      errors << "actors.#{actor_id}.default_role is required" if default_role.empty?
      errors << "actors.#{actor_id}.default_role must be one of actor roles" unless actor_roles.include?(default_role)
    end

    if !defaults["actor"].to_s.empty?
      default_actor = actors[defaults["actor"].to_s]
      if default_actor.nil?
        errors << "defaults.actor references unknown actor: #{defaults["actor"]}"
      elsif !Array(default_actor["roles"]).map(&:to_s).include?(defaults["role"].to_s)
        errors << "defaults.role is not allowed for defaults.actor"
      end
    end

    actions.each do |action_id, action|
      unless action.is_a?(Hash)
        errors << "actions.#{action_id} must be a mapping"
        next
      end

      action_roles = Array(action["roles"]).map(&:to_s)
      errors << "actions.#{action_id}.roles must not be empty" if action_roles.empty?
      action_roles.each do |role|
        errors << "actions.#{action_id}.roles references unknown role: #{role}" unless roles.key?(role)
      end

      default_actor_id = action["default_actor"].to_s
      default_role = action["default_role"].to_s
      default_actor = actors[default_actor_id]
      errors << "actions.#{action_id}.default_actor references unknown actor: #{default_actor_id}" unless default_actor
      errors << "actions.#{action_id}.default_role is required" if default_role.empty?
      errors << "actions.#{action_id}.default_role must be one of action roles" unless action_roles.include?(default_role)

      if default_actor
        actor_roles = Array(default_actor["roles"]).map(&:to_s)
        errors << "actions.#{action_id}.default_role is not allowed for default_actor" unless actor_roles.include?(default_role)
      end
    end

    Array(policy["separation_of_duty"]).each_with_index do |rule, index|
      unless rule.is_a?(Hash)
        errors << "separation_of_duty[#{index}] must be a mapping"
        next
      end

      errors << "separation_of_duty[#{index}].id is required" if rule["id"].to_s.empty?
      action_id = rule["action"].to_s
      errors << "separation_of_duty[#{index}].action references unknown action: #{action_id}" unless actions.key?(action_id)
      errors << "separation_of_duty[#{index}].rule is required" if rule["rule"].to_s.empty?
    end

    errors
  end

  def authorize!(policy, action:, actor: nil, role: nil)
    action_id = action.to_s
    actions = policy.fetch("actions")
    action_record = actions[action_id]
    raise AuthorizationError, "unknown authorization action: #{action_id}" unless action_record.is_a?(Hash)

    actor_record, actor_id, role_id = resolve_actor_role(policy, action_record, actor, role)
    allowed_roles = Array(action_record["roles"]).map(&:to_s)
    unless allowed_roles.include?(role_id)
      raise AuthorizationError, "actor role is not authorized for #{action_id}: #{actor_id}/#{role_id}"
    end

    {
      "actor" => actor_id,
      "actor_role" => role_id,
      "action" => action_id,
      "policy" => DEFAULT_POLICY_PATH,
      "identity_authority" => policy["identity_authority"],
      "actor_display_name" => actor_record["display_name"]
    }
  end

  def actor_must_differ!(auth, other_actor, message)
    return if other_actor.to_s.empty?
    return unless auth.fetch("actor").to_s == other_actor.to_s

    raise AuthorizationError, message
  end

  def audit_record(auth)
    {
      "action" => auth.fetch("action"),
      "policy" => auth.fetch("policy"),
      "identity_authority" => auth.fetch("identity_authority")
    }
  end

  def index_records(value, label, errors)
    records = {}
    unless value.is_a?(Array) && !value.empty?
      errors << "#{label} must be a non-empty array"
      return records
    end

    value.each_with_index do |record, index|
      unless record.is_a?(Hash)
        errors << "#{label}[#{index}] must be a mapping"
        next
      end

      id = record["id"].to_s
      if id.empty?
        errors << "#{label}[#{index}].id is required"
      elsif records.key?(id)
        errors << "#{label}[#{index}].id duplicates #{id}"
      else
        records[id] = record
      end
    end
    records
  end

  def resolve_actor_role(policy, action_record, actor, role)
    actors = Array(policy["actors"]).to_h { |record| [record["id"].to_s, record] }
    default_actor = action_record["default_actor"].to_s.empty? ? policy.dig("defaults", "actor").to_s : action_record["default_actor"].to_s
    actor_id = first_present(actor, ENV["AIT_ACTOR"], ENV["AGENTIC_ACTOR"], default_actor)
    actor_record = actors[actor_id]
    raise AuthorizationError, "unknown actor: #{actor_id}" unless actor_record

    actor_roles = Array(actor_record["roles"]).map(&:to_s)
    default_role = action_record["default_role"].to_s.empty? ? actor_record["default_role"].to_s : action_record["default_role"].to_s
    role_id = first_present(role, ENV["AIT_ACTOR_ROLE"], ENV["AGENTIC_ACTOR_ROLE"], default_role, actor_record["default_role"])
    raise AuthorizationError, "actor role is not assigned to actor: #{actor_id}/#{role_id}" unless actor_roles.include?(role_id)

    [actor_record, actor_id, role_id]
  end

  def first_present(*values)
    values.map { |value| value.to_s.strip }.find { |value| !value.empty? }.to_s
  end
end
