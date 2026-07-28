extends RefCounted

const RuntimeRoleScript = preload("res://scripts/runtime/runtime_role.gd")
const LaunchOptionsScript = preload("res://scripts/runtime/launch_options.gd")

const SCHEMA: String = "planet_simulator.runtime_descriptor.v1"
const PROTOCOL_VERSION: int = 1


static func create(options: Dictionary, context: Dictionary = {}) -> Dictionary:
	var normalized: Dictionary = LaunchOptionsScript.to_snapshot(options)
	var role: String = String(normalized.get("role", RuntimeRoleScript.OFFLINE))
	var role_descriptor: Dictionary = RuntimeRoleScript.describe(role)
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"checkpoint": String(context.get("checkpoint", "v16.8.0-runtime-h0-listen-host")),
		"build_id": String(context.get("build_id", "h0-single-process-network-first-host")),
		"project_name": String(ProjectSettings.get_setting(
			"application/config/name",
			"PlanetSimulator"
		)),
		"node_id": String(normalized.get("node_id", "local-offline")),
		"runtime_role": role,
		"world_id": String(normalized.get("world", "")),
		"instance_id": String(normalized.get("instance_id", "persistent")),
		"space_id": String(normalized.get("space_id", "sol")),
		"authority_region": String(normalized.get("authority_region", "")),
		"requested_user_data_dir": String(normalized.get("user_data_dir", "")),
		"resolved_user_data_dir": OS.get_user_data_dir(),
		"shutdown_after_ms": int(normalized.get("shutdown_after_ms", 0)),
		"shutdown_timeout_ms": int(normalized.get("shutdown_timeout_ms", 30000)),
		"process_id": OS.get_process_id(),
		"presentation_enabled": RuntimeRoleScript.presentation_enabled(role),
		"local_input_enabled": RuntimeRoleScript.accepts_local_input(role),
		"authoritative": RuntimeRoleScript.is_authoritative(role),
		"client_replica_enabled": bool(role_descriptor.get("client_replica_enabled", false)),
		"embedded_authority": bool(role_descriptor.get("embedded_authority", false)),
		"direct_client_domain_access_allowed": bool(role_descriptor.get("direct_client_domain_access_allowed", false)),
		"started_at_utc": Time.get_datetime_string_from_system(true, true),
	}


static func validate(value: Dictionary) -> Dictionary:
	if String(value.get("schema", "")) != SCHEMA:
		return _failure("UNSUPPORTED_SCHEMA", "Unexpected runtime descriptor schema")
	if int(value.get("protocol_version", -1)) != PROTOCOL_VERSION:
		return _failure("UNSUPPORTED_PROTOCOL", "Unsupported protocol version")
	if not RuntimeRoleScript.is_supported(String(value.get("runtime_role", ""))):
		return _failure("UNSUPPORTED_ROLE", "Runtime role is not supported")
	for key in ["checkpoint", "build_id", "node_id", "instance_id", "space_id"]:
		if String(value.get(key, "")).is_empty():
			return _failure("MISSING_FIELD", "Runtime descriptor field is empty: %s" % key)
	return {"success": true, "error_code": "", "message": ""}


static func _failure(error_code: String, message: String) -> Dictionary:
	return {"success": false, "error_code": error_code, "message": message}
