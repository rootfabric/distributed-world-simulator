extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const PartScript = preload("res://scripts/construction/contracts/construction_part_record.gd")
const BondScript = preload("res://scripts/construction/contracts/construction_bond_record.gd")

const SCHEMA: String = "planet_simulator.construct_snapshot.v1"
const FIELDS: Array[String] = [
	"schema",
	"construct_id",
	"root_item_instance_id",
	"state_revision",
	"build_state",
	"parts",
	"bonds",
	"compiled_facets",
	"checksum",
]
const VALID_BUILD_STATES: Array[String] = ["PLANNED", "PARTIAL", "OPERATIONAL", "DAMAGED", "DECONSTRUCTION"]

static func create(
	construct_id: String,
	root_item_instance_id: String,
	state_revision: int,
	build_state: String,
	parts: Array,
	bonds: Array,
	compiled_facets: Dictionary
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"construct_id": construct_id,
		"root_item_instance_id": root_item_instance_id,
		"state_revision": state_revision,
		"build_state": build_state,
		"parts": _sorted_records(parts, "part_id"),
		"bonds": _sorted_records(bonds, "bond_id"),
		"compiled_facets": compiled_facets.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value

static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_CONSTRUCT_SNAPSHOT_SCHEMA")
	if typeof(value.get("construct_id")) != TYPE_STRING or not String(value["construct_id"]).begins_with("construct/"):
		return _failure("INVALID_CONSTRUCT_ID")
	if typeof(value.get("root_item_instance_id")) != TYPE_STRING or not String(value["root_item_instance_id"]).begins_with("item/"):
		return _failure("INVALID_ROOT_ITEM_INSTANCE_ID")
	if not UtilsScript.is_json_integer(value.get("state_revision")) or int(value["state_revision"]) < 0:
		return _failure("INVALID_STATE_REVISION")
	if typeof(value.get("build_state")) != TYPE_STRING or not VALID_BUILD_STATES.has(String(value["build_state"])):
		return _failure("INVALID_BUILD_STATE")
	if typeof(value.get("parts")) != TYPE_ARRAY or typeof(value.get("bonds")) != TYPE_ARRAY:
		return _failure("INVALID_CONSTRUCT_COLLECTIONS")
	if typeof(value.get("compiled_facets")) != TYPE_DICTIONARY:
		return _failure("INVALID_COMPILED_FACETS")
	var part_ids: Dictionary = {}
	var previous_part_id: String = ""
	for raw_part in value["parts"]:
		if typeof(raw_part) != TYPE_DICTIONARY:
			return _failure("INVALID_PART_RECORD")
		var validation: Dictionary = PartScript.validate(raw_part)
		if not bool(validation.get("success", false)):
			return validation
		var part_id: String = String(raw_part["part_id"])
		if part_ids.has(part_id):
			return _failure("DUPLICATE_PART_ID")
		if not previous_part_id.is_empty() and part_id < previous_part_id:
			return _failure("PARTS_NOT_CANONICALLY_SORTED")
		part_ids[part_id] = true
		previous_part_id = part_id
	var bond_ids: Dictionary = {}
	var previous_bond_id: String = ""
	for raw_bond in value["bonds"]:
		if typeof(raw_bond) != TYPE_DICTIONARY:
			return _failure("INVALID_BOND_RECORD")
		var validation: Dictionary = BondScript.validate(raw_bond)
		if not bool(validation.get("success", false)):
			return validation
		var bond_id: String = String(raw_bond["bond_id"])
		if bond_ids.has(bond_id):
			return _failure("DUPLICATE_BOND_ID")
		if not previous_bond_id.is_empty() and bond_id < previous_bond_id:
			return _failure("BONDS_NOT_CANONICALLY_SORTED")
		if not part_ids.has(String(raw_bond["part_a_id"])) or not part_ids.has(String(raw_bond["part_b_id"])):
			return _failure("BOND_REFERENCES_UNKNOWN_PART")
		bond_ids[bond_id] = true
		previous_bond_id = bond_id
	if typeof(value.get("checksum")) != TYPE_STRING or String(value["checksum"]) != compute_checksum(value):
		return _failure("CONSTRUCT_SNAPSHOT_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)):
		return _failure("CONSTRUCT_SNAPSHOT_NOT_JSON_SAFE")
	return UtilsScript.validation_success()

static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)

static func _sorted_records(records: Array, id_field: String) -> Array:
	var output: Array = records.duplicate(true)
	output.sort_custom(func(a, b): return String(a.get(id_field, "")) < String(b.get(id_field, "")))
	return output

static func _failure(code: String) -> Dictionary:
	return UtilsScript.validation_failure(code, code)
