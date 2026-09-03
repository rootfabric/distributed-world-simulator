extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_dynamic_state_schema.v1"
const STATE_FIELDS: Array[String] = [
	"state_id", "quantity_id", "dimension", "region_id",
]
const FIELDS: Array[String] = [
	"schema", "states", "state_count", "schema_hash", "checksum",
]

static func create(states: Array) -> Dictionary:
	var ordered := Utils.sorted_dicts(states, "state_id")
	var value: Dictionary = {
		"schema": SCHEMA,
		"states": ordered,
		"state_count": ordered.size(),
		"schema_hash": Utils.canonical_hash(ordered),
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_DYNAMIC_STATE_SCHEMA")
	if typeof(value.get("states")) != TYPE_ARRAY or value["states"].is_empty():
		return Utils.failure("INVALID_DYNAMIC_STATE_SCHEMA_STATES")
	if not Utils.is_json_integer(value.get("state_count")) or int(value["state_count"]) != value["states"].size():
		return Utils.failure("DYNAMIC_STATE_COUNT_MISMATCH")
	var previous := ""
	for index in range(value["states"].size()):
		var raw = value["states"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_DYNAMIC_STATE_DESCRIPTOR", {"index": index})
		var state: Dictionary = raw
		checked = Utils.validate_exact_fields(state, STATE_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		if not Utils.is_canonical_id(state.get("state_id"), 2):
			return Utils.failure("INVALID_DYNAMIC_STATE_ID", {"index": index})
		if not Utils.is_canonical_id(state.get("quantity_id"), 2):
			return Utils.failure("INVALID_DYNAMIC_STATE_QUANTITY", {"index": index})
		checked = Utils.validate_dimension(state.get("dimension"))
		if not bool(checked.get("success", false)):
			return Utils.failure("INVALID_DYNAMIC_STATE_DIMENSION", {"index": index})
		if not Utils.is_canonical_id(state.get("region_id"), 2):
			return Utils.failure("INVALID_DYNAMIC_STATE_REGION", {"index": index})
		var current := String(state["state_id"])
		if index > 0 and current <= previous:
			return Utils.failure("DYNAMIC_STATES_NOT_SORTED_UNIQUE", {"index": index})
		previous = current
	if not Utils.is_lower_hex_64(value.get("schema_hash")):
		return Utils.failure("INVALID_DYNAMIC_STATE_SCHEMA_HASH")
	if String(value["schema_hash"]) != Utils.canonical_hash(value["states"]):
		return Utils.failure("DYNAMIC_STATE_SCHEMA_HASH_MISMATCH")
	return Utils.validate_checksum(value)

static func state_index(value: Dictionary) -> Dictionary:
	var output := {}
	for index in range(value.get("states", []).size()):
		var state: Dictionary = value["states"][index]
		output[String(state["state_id"])] = index
	return output
