extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_dynamic_rom_state_schema.v1"
const COORDINATE_KIND := "ENERGY_NORMALIZED_GENERALIZED"
const METRIC_KIND := "IDENTITY_ENERGY_METRIC"
const FIELDS: Array[String] = [
	"schema", "coordinate_kind", "metric_kind", "state_ids",
	"state_count", "schema_hash", "checksum",
]

static func create(state_count: int) -> Dictionary:
	if state_count < 1:
		return {}
	var ids: Array = []
	for index in range(state_count):
		ids.append("state/dynamic-rom/%03d" % index)
	var value: Dictionary = {
		"schema": SCHEMA,
		"coordinate_kind": COORDINATE_KIND,
		"metric_kind": METRIC_KIND,
		"state_ids": ids,
		"state_count": state_count,
		"schema_hash": Utils.canonical_hash({
			"coordinate_kind": COORDINATE_KIND,
			"metric_kind": METRIC_KIND,
			"state_ids": ids,
		}),
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
	if String(value.get("coordinate_kind", "")) != COORDINATE_KIND:
		return Utils.failure("INVALID_DYNAMIC_ROM_COORDINATE_KIND")
	if String(value.get("metric_kind", "")) != METRIC_KIND:
		return Utils.failure("INVALID_DYNAMIC_ROM_METRIC_KIND")
	if not Utils.is_json_integer(value.get("state_count")) or int(value["state_count"]) < 1:
		return Utils.failure("INVALID_DYNAMIC_ROM_STATE_COUNT")
	if typeof(value.get("state_ids")) != TYPE_ARRAY or value["state_ids"].size() != int(value["state_count"]):
		return Utils.failure("DYNAMIC_ROM_STATE_IDS_MISMATCH")
	checked = Utils.validate_sorted_unique_strings(value["state_ids"], false)
	if not bool(checked.get("success", false)):
		return checked
	for state_id in value["state_ids"]:
		if not Utils.is_canonical_id(state_id, 2):
			return Utils.failure("INVALID_DYNAMIC_ROM_STATE_ID")
	var expected := Utils.canonical_hash({
		"coordinate_kind": COORDINATE_KIND,
		"metric_kind": METRIC_KIND,
		"state_ids": value["state_ids"],
	})
	if not Utils.is_lower_hex_64(value.get("schema_hash")) or String(value["schema_hash"]) != expected:
		return Utils.failure("DYNAMIC_ROM_STATE_SCHEMA_HASH_MISMATCH")
	return Utils.validate_checksum(value)
