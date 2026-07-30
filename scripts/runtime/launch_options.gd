extends RefCounted

const RuntimeRoleScript = preload("res://scripts/runtime/runtime_role.gd")

const SCHEMA: String = "planet_simulator.launch_options.v1"


static func defaults() -> Dictionary:
	return {
		"schema": SCHEMA,
		"role": RuntimeRoleScript.LISTEN_HOST,
		"world": "",
		"run_tests": "",
		"node_id": "local-listen-host",
		"instance_id": "persistent",
		"space_id": "sol",
		"authority_region": "",
		"server_address": "127.0.0.1",
		"server_port": 24580,
		"player_identity": "local-astronaut",
		"connect_timeout_ms": 15000,
		"command_timeout_ms": 5000,
		"m2_result_file": "",
		"m2_phase": 0,
		"m2_expected_state_file": "",
		"user_data_dir": "",
		"print_runtime_descriptor": false,
		"shutdown_after_ms": 0,
		"shutdown_timeout_ms": 30000,
	}


static func parse(arguments) -> Dictionary:
	var options: Dictionary = defaults()
	var errors: Array[String] = []
	for argument_value in arguments:
		var argument: String = String(argument_value).strip_edges()
		if argument.is_empty():
			continue
		if argument == "--print-runtime-descriptor":
			options["print_runtime_descriptor"] = true
			continue
		if not argument.begins_with("--") or not argument.contains("="):
			errors.append("Unknown launch argument: %s" % argument)
			continue
		var separator: int = argument.find("=")
		var key: String = argument.substr(2, separator - 2).strip_edges()
		var value: String = argument.substr(separator + 1).strip_edges()
		match key:
			"role":
				options["role"] = RuntimeRoleScript.normalize(value)
			"world":
				options["world"] = value.to_lower()
			"run-tests":
				options["run_tests"] = value.to_lower()
			"node-id":
				options["node_id"] = value
			"instance-id":
				options["instance_id"] = value
			"space-id":
				options["space_id"] = value
			"authority-region":
				options["authority_region"] = value
			"server-address":
				options["server_address"] = value
			"server-port":
				options["server_port"] = _parse_port(value, key, errors)
			"player-identity":
				options["player_identity"] = value.to_lower()
			"connect-timeout-ms":
				options["connect_timeout_ms"] = _parse_positive_int(value, key, errors)
			"command-timeout-ms":
				options["command_timeout_ms"] = _parse_positive_int(value, key, errors)
			"m2-result-file":
				options["m2_result_file"] = value
			"m2-phase":
				options["m2_phase"] = _parse_non_negative_int(value, key, errors)
			"m2-expected-state-file":
				options["m2_expected_state_file"] = value
			"user-data-dir":
				options["user_data_dir"] = value
			"shutdown-after-ms":
				options["shutdown_after_ms"] = _parse_non_negative_int(value, key, errors)
			"shutdown-timeout-ms":
				options["shutdown_timeout_ms"] = _parse_positive_int(value, key, errors)
			_:
				errors.append("Unknown launch option: --%s" % key)
	_validate(options, errors)
	return {
		"success": errors.is_empty(),
		"options": options,
		"errors": errors,
	}


static func from_os() -> Dictionary:
	return parse(OS.get_cmdline_user_args())


static func to_snapshot(options: Dictionary) -> Dictionary:
	var snapshot: Dictionary = defaults()
	for key in snapshot.keys():
		if options.has(key):
			snapshot[key] = options[key]
	return snapshot


static func _parse_non_negative_int(value: String, key: String, errors: Array[String]) -> int:
	if not value.is_valid_int():
		errors.append("Launch option --%s must be an integer" % key)
		return 0
	var parsed: int = value.to_int()
	if parsed < 0:
		errors.append("Launch option --%s cannot be negative" % key)
		return 0
	return parsed


static func _parse_port(value: String, key: String, errors: Array[String]) -> int:
	var parsed: int = _parse_positive_int(value, key, errors)
	if parsed > 65535:
		errors.append("Launch option --%s must be at most 65535" % key)
		return 0
	return parsed


static func _parse_positive_int(value: String, key: String, errors: Array[String]) -> int:
	if not value.is_valid_int():
		errors.append("Launch option --%s must be an integer" % key)
		return 0
	var parsed: int = value.to_int()
	if parsed <= 0:
		errors.append("Launch option --%s must be greater than zero" % key)
		return 0
	return parsed


static func _validate(options: Dictionary, errors: Array[String]) -> void:
	var role: String = String(options.get("role", ""))
	if not RuntimeRoleScript.is_supported(role):
		errors.append(
			"Unsupported runtime role '%s'. Supported roles: %s" % [
				role,
				", ".join(PackedStringArray(RuntimeRoleScript.SUPPORTED)),
			]
		)
	for required_key in ["node_id", "instance_id", "space_id"]:
		if String(options.get(required_key, "")).strip_edges().is_empty():
			errors.append("Launch option '%s' cannot be empty" % required_key)
	if role in [RuntimeRoleScript.GAME_CLIENT, RuntimeRoleScript.DEDICATED_SERVER]:
		if String(options.get("server_address", "")).strip_edges().is_empty():
			errors.append("Launch option server_address cannot be empty")
		if int(options.get("server_port", 0)) < 1:
			errors.append("Launch option server_port is invalid")
	if role == RuntimeRoleScript.GAME_CLIENT and String(options.get("player_identity", "")).strip_edges().is_empty():
		errors.append("Launch option player_identity cannot be empty")
	var node_id: String = String(options.get("node_id", ""))
	if role == RuntimeRoleScript.OFFLINE and node_id == "local-listen-host":
		options["node_id"] = "local-offline"
	elif role != RuntimeRoleScript.OFFLINE and node_id in ["local-offline", "local-listen-host"]:
		options["node_id"] = "local-%s" % role
