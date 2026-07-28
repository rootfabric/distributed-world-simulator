extends RefCounted

const SCHEMA := "planet_simulator.network_process_harness_manifest.v1"
const ROOT_FIELDS := ["schema", "checkpoint", "build_id", "defaults", "scenarios"]
const DEFAULT_FIELDS := ["host", "port_range_start", "port_range_end", "readiness_timeout_ms", "scenario_timeout_ms", "shutdown_timeout_ms", "poll_delay_ms"]
const SCENARIO_FIELDS := [
	"id", "server_script", "client_script", "server_node_id", "client_node_id",
	"server_ready_state", "server_terminal_states", "client_terminal_states",
	"expected_outcome", "expected_failure_code", "server_args", "client_args",
	"server_expect", "client_expect", "shared_fields", "assertions",
	"readiness_timeout_ms", "timeout_ms",
]
const ASSERTION_FIELDS := ["source", "actual", "equals"]
const RESERVED_ARGUMENTS := ["host", "node-id", "port", "result-file", "timeout-ms"]

static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("MANIFEST_NOT_FOUND", "Manifest file does not exist")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("MANIFEST_OPEN_FAILED", "Manifest file cannot be opened")
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error != OK or not parser.data is Dictionary:
		return _failure("MANIFEST_JSON_INVALID", "Manifest must contain a JSON object")
	var result := validate(parser.data)
	if not bool(result.get("success", false)):
		return result
	return {"success": true, "manifest": Dictionary(parser.data).duplicate(true)}

static func validate(manifest: Dictionary) -> Dictionary:
	var exact := _exact_fields(manifest, ROOT_FIELDS, "manifest")
	if not bool(exact.get("success", false)): return exact
	if String(manifest.get("schema", "")) != SCHEMA:
		return _failure("MANIFEST_SCHEMA_INVALID", "Unsupported process harness manifest schema")
	if not _is_canonical_identifier(String(manifest.get("checkpoint", "")), false, true):
		return _failure("CHECKPOINT_INVALID", "checkpoint is not canonical")
	if not _is_canonical_identifier(String(manifest.get("build_id", "")), false, true):
		return _failure("BUILD_ID_INVALID", "build_id is not canonical")
	if not manifest.get("defaults") is Dictionary or not manifest.get("scenarios") is Array:
		return _failure("MANIFEST_TYPE_INVALID", "defaults must be object and scenarios must be array")
	var defaults: Dictionary = manifest["defaults"]
	exact = _exact_fields(defaults, DEFAULT_FIELDS, "defaults")
	if not bool(exact.get("success", false)): return exact
	if not defaults["host"] is String or String(defaults["host"]).strip_edges().is_empty():
		return _failure("HOST_INVALID", "defaults.host must be a non-empty string")
	for key in ["port_range_start", "port_range_end", "readiness_timeout_ms", "scenario_timeout_ms", "shutdown_timeout_ms", "poll_delay_ms"]:
		if not _is_json_int(defaults[key]): return _failure("DEFAULT_INTEGER_INVALID", "%s must be an integer" % key)
	var port_start := int(defaults["port_range_start"])
	var port_end := int(defaults["port_range_end"])
	if port_start < 1024 or port_end > 65535 or port_start > port_end:
		return _failure("PORT_RANGE_INVALID", "Port range must be within 1024..65535")
	for key in ["readiness_timeout_ms", "scenario_timeout_ms", "shutdown_timeout_ms", "poll_delay_ms"]:
		if int(defaults[key]) <= 0 or int(defaults[key]) > 600000:
			return _failure("TIMEOUT_INVALID", "%s is outside the allowed range" % key)
	var scenarios: Array = manifest["scenarios"]
	if scenarios.is_empty() or scenarios.size() > 64:
		return _failure("SCENARIO_COUNT_INVALID", "Scenario count must be within 1..64")
	var seen := {}
	for scenario_value in scenarios:
		if not scenario_value is Dictionary: return _failure("SCENARIO_TYPE_INVALID", "Every scenario must be an object")
		var checked := _validate_scenario(scenario_value)
		if not bool(checked.get("success", false)): return checked
		var scenario_id := String(scenario_value["id"])
		if seen.has(scenario_id): return _failure("DUPLICATE_SCENARIO_ID", "Duplicate scenario ID: %s" % scenario_id)
		seen[scenario_id] = true
	var safe := _validate_json_value(manifest, 0)
	if not bool(safe.get("success", false)): return safe
	return {"success": true}

static func select_scenarios(manifest: Dictionary, requested_ids: Array[String]) -> Dictionary:
	var validation := validate(manifest)
	if not bool(validation.get("success", false)): return validation
	if requested_ids.is_empty(): return {"success": true, "scenarios": Array(manifest["scenarios"]).duplicate(true)}
	var requested_seen := {}
	for scenario_id in requested_ids:
		if requested_seen.has(scenario_id): return _failure("DUPLICATE_SCENARIO_REQUEST", "Scenario requested twice: %s" % scenario_id)
		requested_seen[scenario_id] = true
	var selected: Array = []
	var missing := requested_ids.duplicate()
	for scenario in Array(manifest["scenarios"]):
		var scenario_id := String(scenario.get("id", ""))
		if scenario_id in requested_ids:
			selected.append(Dictionary(scenario).duplicate(true))
			missing.erase(scenario_id)
	if not missing.is_empty(): return _failure("SCENARIO_NOT_FOUND", "Unknown scenarios: %s" % missing)
	return {"success": true, "scenarios": selected}

static func _validate_scenario(scenario: Dictionary) -> Dictionary:
	var exact := _exact_fields(scenario, SCENARIO_FIELDS, "scenario")
	if not bool(exact.get("success", false)): return exact
	for key in ["id", "server_node_id", "client_node_id"]:
		if not scenario[key] is String or not _is_canonical_identifier(String(scenario[key]), false, false):
			return _failure("SCENARIO_IDENTIFIER_INVALID", "%s is invalid" % key)
	for key in ["server_script", "client_script"]:
		if not scenario[key] is String: return _failure("SCRIPT_PATH_INVALID", "%s must be a string" % key)
		var path := String(scenario[key])
		if not path.begins_with("res://") or not path.ends_with(".gd") or not FileAccess.file_exists(path):
			return _failure("SCRIPT_PATH_INVALID", "%s must reference an existing res:// GDScript" % key)
	if not scenario["server_ready_state"] is String or not _is_state(String(scenario["server_ready_state"])):
		return _failure("STATE_INVALID", "server_ready_state is invalid")
	for key in ["server_terminal_states", "client_terminal_states"]:
		if not scenario[key] is Array or Array(scenario[key]).is_empty(): return _failure("STATE_LIST_INVALID", "%s must be non-empty" % key)
		var seen_states := {}
		for state in Array(scenario[key]):
			if not state is String or not _is_state(String(state)): return _failure("STATE_INVALID", "%s contains invalid state" % key)
			if seen_states.has(state): return _failure("DUPLICATE_STATE", "%s contains duplicate state" % key)
			seen_states[state] = true
	if String(scenario["expected_outcome"]) not in ["SUCCESS", "EXPECTED_FAILURE"]:
		return _failure("EXPECTED_OUTCOME_INVALID", "expected_outcome is invalid")
	if not scenario["expected_failure_code"] is String or (not String(scenario["expected_failure_code"]).is_empty() and not _is_state(String(scenario["expected_failure_code"]))):
		return _failure("EXPECTED_FAILURE_CODE_INVALID", "expected_failure_code is invalid")
	if String(scenario["expected_outcome"]) == "SUCCESS" and not String(scenario["expected_failure_code"]).is_empty():
		return _failure("SUCCESS_WITH_FAILURE_CODE", "Successful scenario cannot declare failure code")
	if String(scenario["expected_outcome"]) == "EXPECTED_FAILURE" and String(scenario["expected_failure_code"]).is_empty():
		return _failure("FAILURE_CODE_REQUIRED", "Expected failure requires a code")
	for key in ["server_args", "client_args", "server_expect", "client_expect"]:
		if not scenario[key] is Dictionary: return _failure("SCENARIO_TYPE_INVALID", "%s must be an object" % key)
	for key in ["server_args", "client_args"]:
		for argument_name in Dictionary(scenario[key]).keys():
			var normalized := String(argument_name)
			if not _is_argument_name(normalized): return _failure("INVALID_ARGUMENT_NAME", "%s contains invalid argument name" % key)
			if normalized in RESERVED_ARGUMENTS: return _failure("RESERVED_ARGUMENT_OVERRIDE", "%s cannot override --%s" % [key, normalized])
	for key in ["shared_fields"]:
		if not scenario[key] is Array: return _failure("FIELD_PATH_LIST_INVALID", "%s must be an array" % key)
		for path_value in Array(scenario[key]):
			if not path_value is String or not _is_field_path(String(path_value)): return _failure("FIELD_PATH_INVALID", "%s contains invalid field path" % key)
	for key in ["server_expect", "client_expect"]:
		for path_value in Dictionary(scenario[key]).keys():
			if not _is_field_path(String(path_value)): return _failure("FIELD_PATH_INVALID", "%s contains invalid field path" % key)
	if not scenario["assertions"] is Array: return _failure("ASSERTIONS_INVALID", "assertions must be an array")
	for assertion_value in Array(scenario["assertions"]):
		if not assertion_value is Dictionary: return _failure("ASSERTION_INVALID", "Assertion must be an object")
		exact = _exact_fields(assertion_value, ASSERTION_FIELDS, "assertion")
		if not bool(exact.get("success", false)): return exact
		if String(assertion_value["source"]) not in ["server", "client"]: return _failure("ASSERTION_SOURCE_INVALID", "Assertion source is invalid")
		if not assertion_value["actual"] is String or not _is_field_path(String(assertion_value["actual"])): return _failure("FIELD_PATH_INVALID", "Assertion path is invalid")
	for key in ["readiness_timeout_ms", "timeout_ms"]:
		if not _is_json_int(scenario[key]) or int(scenario[key]) < 0 or int(scenario[key]) > 600000:
			return _failure("SCENARIO_TIMEOUT_INVALID", "%s is invalid" % key)
	return {"success": true}

static func _exact_fields(value: Dictionary, expected: Array, label: String) -> Dictionary:
	var keys: Array = value.keys()
	keys.sort()
	var wanted := expected.duplicate(); wanted.sort()
	if keys != wanted: return _failure("%s_FIELDS_INVALID" % label.to_upper(), "%s fields must be exact" % label)
	return {"success": true}

static func _is_json_int(value) -> bool:
	if value is int: return abs(int(value)) <= 9007199254740991
	if value is float: return is_finite(value) and value == floor(value) and abs(value) <= 9007199254740991.0
	return false

static func _is_canonical_identifier(value: String, uppercase: bool, allow_slash: bool) -> bool:
	if value.is_empty() or value != value.strip_edges() or value.length() > 128: return false
	var allowed := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-" if uppercase else "abcdefghijklmnopqrstuvwxyz0123456789._-"
	if allow_slash: allowed += "/"
	if value[0] in ["/", ".", "-"] or value.ends_with("/") or value.contains("..") or value.contains("//"): return false
	for c in value:
		if not allowed.contains(c): return false
	return true

static func _is_state(value: String) -> bool:
	return _is_canonical_identifier(value, true, false)

static func _is_argument_name(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges() or value.length() > 64 or value[0] == "-" or value.ends_with("-"): return false
	for c in value:
		if not "abcdefghijklmnopqrstuvwxyz0123456789-".contains(c): return false
	return true

static func _is_field_path(path: String) -> bool:
	if path.is_empty() or path != path.strip_edges() or path.begins_with(".") or path.ends_with(".") or path.contains(".."): return false
	for segment in path.split(".", true):
		if segment.is_empty(): return false
		for c in segment:
			if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_".contains(c): return false
	return true

static func _validate_json_value(value, depth: int) -> Dictionary:
	if depth > 16: return _failure("JSON_DEPTH_EXCEEDED", "Manifest nesting is too deep")
	if value == null or value is bool or value is String: return {"success": true}
	if value is int or value is float:
		return {"success": true} if (not value is float or is_finite(value)) and abs(float(value)) <= 9007199254740991.0 else _failure("JSON_NUMBER_INVALID", "Unsafe JSON number")
	if value is Array:
		for child in value:
			var checked := _validate_json_value(child, depth + 1)
			if not bool(checked.get("success", false)): return checked
		return {"success": true}
	if value is Dictionary:
		for key in value.keys():
			if not key is String: return _failure("JSON_KEY_INVALID", "Dictionary keys must be strings")
			var checked := _validate_json_value(value[key], depth + 1)
			if not bool(checked.get("success", false)): return checked
		return {"success": true}
	return _failure("RUNTIME_OBJECT_REJECTED", "Manifest contains a non-JSON runtime value")

static func _failure(error_code: String, message: String) -> Dictionary:
	return {"success": false, "error_code": error_code, "message": message}
