extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")

const SCHEMA := "planet_simulator.construction_repair_plan.v1"
const FIELDS: Array[String] = [
	"schema", "repair_id", "damage_id", "target_construct_id", "target_root_item_instance_id",
	"target_snapshot_template", "split_construct_ids", "split_root_item_ids", "required_part_item_ids",
	"broken_bond_ids", "damage_request_checksum", "checksum",
]

static func create(repair_id: String, damage_id: String, target_snapshot_template: Dictionary, split_construct_ids: Array, split_root_item_ids: Array, required_part_item_ids: Array, broken_bond_ids: Array, damage_request_checksum: String) -> Dictionary:
	var value := {
		"schema": SCHEMA, "repair_id": repair_id, "damage_id": damage_id,
		"target_construct_id": String(target_snapshot_template.get("construct_id", "")),
		"target_root_item_instance_id": String(target_snapshot_template.get("root_item_instance_id", "")),
		"target_snapshot_template": target_snapshot_template.duplicate(true),
		"split_construct_ids": _sorted(split_construct_ids), "split_root_item_ids": _sorted(split_root_item_ids),
		"required_part_item_ids": _sorted(required_part_item_ids), "broken_bond_ids": _sorted(broken_bond_ids),
		"damage_request_checksum": damage_request_checksum, "checksum": "",
	}
	value["checksum"] = compute_checksum(value); return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_REPAIR_PLAN_SCHEMA")
	if not String(value.get("repair_id", "")).begins_with("repair/") or not String(value.get("damage_id", "")).begins_with("damage/"): return _failure("INVALID_CONSTRUCTION_REPAIR_IDENTITY")
	if typeof(value.get("target_snapshot_template")) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_REPAIR_TARGET_TEMPLATE")
	var snapshot_validation := SnapshotScript.validate(value["target_snapshot_template"]); if not bool(snapshot_validation.get("success", false)): return snapshot_validation
	if String(value["target_snapshot_template"]["construct_id"]) != String(value["target_construct_id"]) or String(value["target_snapshot_template"]["root_item_instance_id"]) != String(value["target_root_item_instance_id"]): return _failure("CONSTRUCTION_REPAIR_TARGET_IDENTITY_MISMATCH")
	for field in ["split_construct_ids", "split_root_item_ids", "required_part_item_ids", "broken_bond_ids"]:
		if typeof(value.get(field)) != TYPE_ARRAY or value[field] != _sorted(value[field]): return _failure("NON_CANONICAL_CONSTRUCTION_REPAIR_MEMBERS")
		var seen := {}; for member in value[field]:
			if typeof(member) != TYPE_STRING or seen.has(member): return _failure("INVALID_CONSTRUCTION_REPAIR_MEMBER")
			seen[member] = true
	if value["split_construct_ids"].size() != value["split_root_item_ids"].size(): return _failure("CONSTRUCTION_REPAIR_SPLIT_IDENTITY_COUNT_MISMATCH")
	if typeof(value.get("damage_request_checksum")) != TYPE_STRING or String(value["damage_request_checksum"]).length() != 64: return _failure("INVALID_CONSTRUCTION_REPAIR_DAMAGE_CHECKSUM")
	if typeof(value.get("checksum")) != TYPE_STRING or String(value["checksum"]) != compute_checksum(value): return _failure("CONSTRUCTION_REPAIR_PLAN_CHECKSUM_MISMATCH")
	return UtilsScript.validation_success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
static func _sorted(values: Array) -> Array:
	var output := values.duplicate(); output.sort(); return output
static func _failure(code: String) -> Dictionary:
	return UtilsScript.validation_failure(code, code)
