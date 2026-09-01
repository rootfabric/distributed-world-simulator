extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_dynamic_rom_state.v1"
const FIELDS: Array[String] = [
	"schema", "rom_descriptor_hash", "reduced_state_schema_hash",
	"time_s", "step_index", "values", "checksum",
]

static func create(
	rom_descriptor_hash: String,
	reduced_state_schema_hash: String,
	time_s: float,
	step_index: int,
	values: Array
) -> Dictionary:
	var canonical_values: Array = []
	for raw in values:
		canonical_values.append(float(raw))
	var value: Dictionary = {
		"schema": SCHEMA,
		"rom_descriptor_hash": rom_descriptor_hash,
		"reduced_state_schema_hash": reduced_state_schema_hash,
		"time_s": time_s,
		"step_index": step_index,
		"values": canonical_values,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_DYNAMIC_ROM_STATE_SCHEMA")
	for field in ["rom_descriptor_hash", "reduced_state_schema_hash"]:
		if not Utils.is_lower_hex_64(value.get(field)):
			return Utils.failure("INVALID_DYNAMIC_ROM_STATE_HASH", {"field": field})
	if not Utils.is_non_negative_number(value.get("time_s")):
		return Utils.failure("INVALID_DYNAMIC_ROM_STATE_TIME")
	if not Utils.is_json_integer(value.get("step_index")) or int(value["step_index"]) < 0:
		return Utils.failure("INVALID_DYNAMIC_ROM_STATE_STEP")
	if typeof(value.get("values")) != TYPE_ARRAY or value["values"].is_empty():
		return Utils.failure("INVALID_DYNAMIC_ROM_STATE_VALUES")
	for index in range(value["values"].size()):
		if not Utils.is_finite_number(value["values"][index]):
			return Utils.failure("NONFINITE_DYNAMIC_ROM_STATE_VALUE", {"index": index})
	return Utils.validate_checksum(value)
