extends RefCounted

const RuntimeRoleScript = preload("res://scripts/runtime/runtime_role.gd")

const SCHEMA: String = "planet_simulator.launch_options.v1"


static func defaults() -> Dictionary:
	return {
		"schema": SCHEMA,
		"role": RuntimeRoleScript.OFFLINE,
		"world": "",
		"run_tests": "",
		"node_id": "local-offline",
		"instance_id": "persistent",
		"space_id": "sol",
		"authority_region": "",
		"user_data_dir": "",
		"print_runtime_descriptor": false,
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
			"user-data-dir":
				options["user_data_dir"] = value
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
	if role != RuntimeRoleScript.OFFLINE and String(options.get("node_id", "")) == "local-offline":
		options["node_id"] = "local-%s" % role
