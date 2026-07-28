extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const EndpointScript = preload("res://scripts/network/contracts/network_endpoint.gd")
const SpaceScript = preload("res://scripts/network/contracts/simulation_space_descriptor.gd")

const SCHEMA: String = "planet_simulator.simulation_node_descriptor.v1"
const PROTOCOL_VERSION: int = 1
const ROLES: Array[String] = ["offline", "client", "simulation-server", "bot-client"]
const STATUSES: Array[String] = ["STARTING", "READY", "DRAINING", "OFFLINE", "FAILED"]
const FIELDS: Array[String] = [
	"schema", "protocol_version", "node_id", "runtime_role", "build_id", "checkpoint",
	"instance_id", "spaces", "endpoint", "capabilities", "status", "started_at_tick",
	"heartbeat_tick", "descriptor_revision",
]


static func create(
	node_id: String,
	runtime_role: String,
	build_id: String,
	checkpoint: String,
	instance_id: String,
	spaces: Array,
	endpoint: Dictionary,
	capabilities: Array[String],
	status: String,
	started_at_tick: int,
	heartbeat_tick: int,
	descriptor_revision: int = 0
) -> Dictionary:
	var capability_values: Array[String] = capabilities.duplicate()
	capability_values.sort()
	var space_values: Array = []
	for space in spaces:
		space_values.append(space.duplicate(true) if space is Dictionary else space)
	space_values.sort_custom(func(first, second) -> bool:
		return String(first.get("space_id", "")) < String(second.get("space_id", ""))
	)
	return {
		"schema": SCHEMA, "protocol_version": PROTOCOL_VERSION,
		"node_id": node_id, "runtime_role": runtime_role, "build_id": build_id,
		"checkpoint": checkpoint, "instance_id": instance_id, "spaces": space_values,
		"endpoint": endpoint.duplicate(true), "capabilities": capability_values,
		"status": status, "started_at_tick": started_at_tick,
		"heartbeat_tick": heartbeat_tick, "descriptor_revision": descriptor_revision,
	}


static func validate(value: Dictionary) -> Dictionary:
	var check: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(check.get("success", false)):
		return check
	for field in ["schema", "node_id", "runtime_role", "build_id", "checkpoint", "instance_id", "status"]:
		check = UtilsScript.require_string(value, field)
		if not bool(check.get("success", false)):
			return check
	if String(value["schema"]) != SCHEMA:
		return UtilsScript.validation_failure("UNSUPPORTED_SCHEMA", "Unexpected node descriptor schema")
	for field in ["protocol_version", "started_at_tick", "heartbeat_tick", "descriptor_revision"]:
		check = UtilsScript.require_json_integer(value, field)
		if not bool(check.get("success", false)):
			return check
	if int(value["protocol_version"]) != PROTOCOL_VERSION:
		return UtilsScript.validation_failure("UNSUPPORTED_PROTOCOL", "Unsupported protocol version")
	if not ROLES.has(String(value["runtime_role"])) or not STATUSES.has(String(value["status"])):
		return UtilsScript.validation_failure("INVALID_ENUM", "Invalid runtime role or node status")
	if int(value["started_at_tick"]) < 0 or int(value["heartbeat_tick"]) < int(value["started_at_tick"]) or int(value["descriptor_revision"]) < 0:
		return UtilsScript.validation_failure("INVALID_NODE_TIMELINE", "Invalid node timeline or descriptor revision")
	if typeof(value.get("endpoint")) != TYPE_DICTIONARY or not bool(EndpointScript.validate(value["endpoint"]).get("success", false)):
		return UtilsScript.validation_failure("INVALID_ENDPOINT", "Node endpoint is invalid")
	check = _validate_capabilities(value.get("capabilities"))
	if not bool(check.get("success", false)):
		return check
	if typeof(value.get("spaces")) != TYPE_ARRAY:
		return UtilsScript.validation_failure("INVALID_FIELD_TYPE", "spaces must be an Array")
	if String(value["runtime_role"]) == "simulation-server" and value["spaces"].is_empty():
		return UtilsScript.validation_failure("NODE_SPACES_REQUIRED", "simulation-server must declare at least one space")
	var space_ids: Dictionary = {}
	for space_value in value["spaces"]:
		if typeof(space_value) != TYPE_DICTIONARY:
			return UtilsScript.validation_failure("INVALID_SPACE", "spaces must contain descriptor objects")
		var validation: Dictionary = SpaceScript.validate(space_value)
		if not bool(validation.get("success", false)):
			return UtilsScript.validation_failure("INVALID_SPACE", String(validation.get("message", "")))
		if String(space_value["instance_id"]) != String(value["instance_id"]):
			return UtilsScript.validation_failure("INSTANCE_ID_MISMATCH", "Node and space instance_id must match")
		var space_id: String = String(space_value["space_id"])
		if space_ids.has(space_id):
			return UtilsScript.validation_failure("DUPLICATE_SPACE", "space_id must be unique")
		space_ids[space_id] = true
	var safe: Dictionary = UtilsScript.canonicalize(value)
	if not bool(safe.get("success", false)):
		return UtilsScript.validation_failure("NON_CANONICAL_PAYLOAD", String(safe.get("error", "")))
	return UtilsScript.validation_success()


static func normalize(value: Dictionary) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	var canonical: Dictionary = value.duplicate(true)
	canonical["capabilities"] = Array(canonical["capabilities"]).duplicate()
	canonical["capabilities"].sort()
	var normalized_spaces: Array = []
	for space in canonical["spaces"]:
		normalized_spaces.append(SpaceScript.normalize(space))
	normalized_spaces.sort_custom(func(first, second) -> bool:
		return String(first.get("space_id", "")) < String(second.get("space_id", ""))
	)
	canonical["spaces"] = normalized_spaces
	canonical["endpoint"] = EndpointScript.normalize(canonical["endpoint"])
	var round_trip: Dictionary = UtilsScript.json_round_trip(canonical)
	return round_trip.get("value", {}) if bool(round_trip.get("success", false)) else {}


static func descriptor_hash(value: Dictionary) -> String:
	return UtilsScript.payload_hash(normalize(value))


static func _validate_capabilities(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return UtilsScript.validation_failure("INVALID_FIELD_TYPE", "capabilities must be an Array")
	var seen: Dictionary = {}
	for capability in value:
		if typeof(capability) != TYPE_STRING or String(capability).strip_edges().is_empty():
			return UtilsScript.validation_failure("INVALID_FIELD_TYPE", "capabilities must contain non-empty Strings")
		if seen.has(capability):
			return UtilsScript.validation_failure("DUPLICATE_CAPABILITY", "capabilities must be unique")
		seen[capability] = true
	return UtilsScript.validation_success()
