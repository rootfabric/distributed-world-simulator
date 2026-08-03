extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA := "planet_simulator.construction_damage_component.v1"
const FIELDS: Array[String] = ["schema", "component_id", "outcome", "construct_id", "root_item_instance_id", "part_ids", "bond_ids", "checksum"]
const OUTCOMES: Array[String] = ["RETAINED", "SPLIT_CONSTRUCT", "SALVAGE"]

static func create(component_id: String, outcome: String, construct_id: String, root_item_instance_id: String, part_ids: Array, bond_ids: Array) -> Dictionary:
	var value := {
		"schema": SCHEMA, "component_id": component_id, "outcome": outcome,
		"construct_id": construct_id, "root_item_instance_id": root_item_instance_id,
		"part_ids": _sorted(part_ids), "bond_ids": _sorted(bond_ids), "checksum": "",
	}
	value["checksum"] = compute_checksum(value); return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_DAMAGE_COMPONENT_SCHEMA")
	if not String(value.get("component_id", "")).begins_with("damage-component/"): return _failure("INVALID_CONSTRUCTION_DAMAGE_COMPONENT_ID")
	var outcome := String(value.get("outcome", "")); if not OUTCOMES.has(outcome): return _failure("INVALID_CONSTRUCTION_DAMAGE_COMPONENT_OUTCOME")
	if outcome == "SALVAGE":
		if not String(value.get("construct_id", "")).is_empty() or not String(value.get("root_item_instance_id", "")).is_empty(): return _failure("SALVAGE_COMPONENT_HAS_CONSTRUCT_IDENTITY")
	else:
		if not String(value.get("construct_id", "")).begins_with("construct/") or not String(value.get("root_item_instance_id", "")).begins_with("item/"): return _failure("INVALID_CONSTRUCTION_DAMAGE_COMPONENT_CONSTRUCT")
	for field in ["part_ids", "bond_ids"]:
		if typeof(value.get(field)) != TYPE_ARRAY or value[field].is_empty() and field == "part_ids" or value[field] != _sorted(value[field]): return _failure("NON_CANONICAL_CONSTRUCTION_DAMAGE_COMPONENT_MEMBERS")
		var seen := {}; for member in value[field]:
			if typeof(member) != TYPE_STRING or seen.has(member): return _failure("INVALID_CONSTRUCTION_DAMAGE_COMPONENT_MEMBER")
			seen[member] = true
	if typeof(value.get("checksum")) != TYPE_STRING or String(value["checksum"]) != compute_checksum(value): return _failure("CONSTRUCTION_DAMAGE_COMPONENT_CHECKSUM_MISMATCH")
	return UtilsScript.validation_success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
static func _sorted(values: Array) -> Array:
	var output := values.duplicate(); output.sort(); return output
static func _failure(code: String) -> Dictionary:
	return UtilsScript.validation_failure(code, code)
