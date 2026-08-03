extends RefCounted

const RuntimeRoleScript = preload("res://scripts/runtime/runtime_role.gd")
const LaunchOptionsScript = preload("res://scripts/runtime/launch_options.gd")
const NetworkRuntimeIdentityScript = preload("res://scripts/network/observability/network_runtime_identity.gd")
const FingerprintScript = preload("res://scripts/network/observability/network_build_fingerprint.gd")
const ProtocolManifestScript = preload("res://scripts/network/observability/network_protocol_manifest.gd")
const NetworkConditionProfileScript = preload("res://scripts/network/conditions/network_condition_profile.gd")

const SCHEMA: String = "planet_simulator.runtime_descriptor.v1"
const PROTOCOL_VERSION: int = 1


static func create(options: Dictionary, context: Dictionary = {}) -> Dictionary:
	var normalized: Dictionary = LaunchOptionsScript.to_snapshot(options)
	var role: String = String(normalized.get("role", RuntimeRoleScript.OFFLINE))
	var role_descriptor: Dictionary = RuntimeRoleScript.describe(role)
	var identity_result: Dictionary = NetworkRuntimeIdentityScript.validate_config({
		"world_id": String(normalized.get("world", "")),
		"playable_sandbox": bool(normalized.get("network_playground", false)),
		"network_session_token": String(normalized.get("network_session_token", "")),
		"network_build_id": String(normalized.get("network_build_id", "")),
		"network_git_commit": String(normalized.get("network_git_commit", "")),
		"network_protocol_hash": String(normalized.get("network_protocol_hash", "")),
	})
	var network_fingerprint: Dictionary = identity_result.get("details", {}).get("fingerprint", {}) if bool(identity_result.get("success", false)) else {}
	var protocol_manifest: Dictionary = identity_result.get("details", {}).get("protocol_manifest", {}) if bool(identity_result.get("success", false)) else {}
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"checkpoint": String(context.get("checkpoint", "v16.10.6-architecture-a3-single-server-multiplayer")),
		"build_id": String(context.get("build_id", "a3-single-server-multiplayer-architecture-freeze")),
		"network_fingerprint": network_fingerprint.duplicate(true),
		"network_protocol_manifest": protocol_manifest.duplicate(true),
		"network_condition_profile": String(normalized.get("network_condition_profile", "LOCAL")),
		"network_condition_presets_file": String(normalized.get("network_condition_presets_file", "")),
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
		"server_address": String(normalized.get("server_address", "127.0.0.1")),
		"server_port": int(normalized.get("server_port", 24580)),
		"player_identity": String(normalized.get("player_identity", "local-astronaut")),
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
		"dedicated_authority": bool(role_descriptor.get("dedicated_authority", false)),
		"remote_game_client": bool(role_descriptor.get("remote_game_client", false)),
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
	if value.has("network_fingerprint"):
		if not value.get("network_fingerprint") is Dictionary:
			return _failure("INVALID_NETWORK_FINGERPRINT", "network_fingerprint must be a Dictionary")
		var fingerprint_check: Dictionary = FingerprintScript.validate(Dictionary(value["network_fingerprint"]))
		if not bool(fingerprint_check.get("success", false)):
			return _failure("INVALID_NETWORK_FINGERPRINT", String(fingerprint_check.get("error_code", "INVALID_NETWORK_FINGERPRINT")))
	if value.has("network_protocol_manifest"):
		if not value.get("network_protocol_manifest") is Dictionary:
			return _failure("INVALID_NETWORK_PROTOCOL_MANIFEST", "network_protocol_manifest must be a Dictionary")
		var manifest_check: Dictionary = ProtocolManifestScript.validate(Dictionary(value["network_protocol_manifest"]))
		if not bool(manifest_check.get("success", false)):
			return _failure("INVALID_NETWORK_PROTOCOL_MANIFEST", String(manifest_check.get("error_code", "INVALID_NETWORK_PROTOCOL_MANIFEST")))
	if not NetworkConditionProfileScript.is_profile_id(String(value.get("network_condition_profile", ""))):
		return _failure("INVALID_NETWORK_CONDITION_PROFILE", "network_condition_profile is invalid")
	if String(value.get("network_condition_presets_file", "")).strip_edges().is_empty():
		return _failure("INVALID_NETWORK_CONDITION_PRESETS_FILE", "network_condition_presets_file is empty")
	return {"success": true, "error_code": "", "message": ""}


static func _failure(error_code: String, message: String) -> Dictionary:
	return {"success": false, "error_code": error_code, "message": message}
