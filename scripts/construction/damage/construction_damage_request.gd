extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const PolicyScript = preload("res://scripts/construction/damage/construction_salvage_policy.gd")

const SCHEMA := "planet_simulator.construction_damage_request.v1"
const FIELDS: Array[String] = [
	"schema", "damage_id", "construct_id", "source_snapshot_checksum", "retained_part_id",
	"broken_bond_ids", "degraded_bond_ids", "part_conditions", "split_targets", "salvage_policy", "checksum",
]
const VALID_CONDITIONS: Array[String] = ["INTACT", "DEGRADED", "DESTROYED"]

static func split_target(construct_id: String, root_item_instance_id: String) -> Dictionary:
	return {"construct_id": construct_id, "root_item_instance_id": root_item_instance_id}

static func create(
	damage_id: String,
	construct_id: String,
	source_snapshot_checksum: String,
	retained_part_id: String,
	broken_bond_ids: Array,
	degraded_bond_ids: Array = [],
	part_conditions: Dictionary = {},
	split_targets: Array = [],
	salvage_policy: Dictionary = {}
) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"damage_id": damage_id,
		"construct_id": construct_id,
		"source_snapshot_checksum": source_snapshot_checksum,
		"retained_part_id": retained_part_id,
		"broken_bond_ids": _sorted_strings(broken_bond_ids),
		"degraded_bond_ids": _sorted_strings(degraded_bond_ids),
		"part_conditions": _sorted_dictionary(part_conditions),
		"split_targets": _sorted_targets(split_targets),
		"salvage_policy": (PolicyScript.create() if salvage_policy.is_empty() else salvage_policy.duplicate(true)),
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_DAMAGE_REQUEST_SCHEMA")
	if not _identifier(String(value.get("damage_id", "")), "damage/"): return _failure("INVALID_CONSTRUCTION_DAMAGE_ID")
	if not _identifier(String(value.get("construct_id", "")), "construct/"): return _failure("INVALID_CONSTRUCTION_DAMAGE_CONSTRUCT_ID")
	if typeof(value.get("source_snapshot_checksum")) != TYPE_STRING or String(value["source_snapshot_checksum"]).length() != 64:
		return _failure("INVALID_CONSTRUCTION_DAMAGE_SOURCE_CHECKSUM")
	if not _identifier(String(value.get("retained_part_id", "")), "part/"): return _failure("INVALID_CONSTRUCTION_DAMAGE_RETAINED_PART")
	for field in ["broken_bond_ids", "degraded_bond_ids"]:
		if typeof(value.get(field)) != TYPE_ARRAY or value[field] != _sorted_strings(value[field]): return _failure("NON_CANONICAL_CONSTRUCTION_DAMAGE_BONDS")
		var seen := {}
		for raw_id in value[field]:
			if typeof(raw_id) != TYPE_STRING or not _identifier(String(raw_id), "bond/") or seen.has(raw_id): return _failure("INVALID_CONSTRUCTION_DAMAGE_BOND_ID")
			seen[raw_id] = true
	for bond_id in value["broken_bond_ids"]:
		if value["degraded_bond_ids"].has(bond_id): return _failure("CONSTRUCTION_DAMAGE_BOND_STATE_CONFLICT")
	if typeof(value.get("part_conditions")) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_DAMAGE_PART_CONDITIONS")
	var condition_keys: Array = value["part_conditions"].keys()
	condition_keys.sort()
	if condition_keys != value["part_conditions"].keys(): return _failure("NON_CANONICAL_CONSTRUCTION_DAMAGE_PART_CONDITIONS")
	for raw_key in condition_keys:
		if typeof(raw_key) != TYPE_STRING or not _identifier(String(raw_key), "part/"): return _failure("INVALID_CONSTRUCTION_DAMAGE_PART_ID")
		if typeof(value["part_conditions"][raw_key]) != TYPE_STRING or not VALID_CONDITIONS.has(String(value["part_conditions"][raw_key])):
			return _failure("INVALID_CONSTRUCTION_DAMAGE_PART_CONDITION")
	if typeof(value.get("split_targets")) != TYPE_ARRAY or value["split_targets"] != _sorted_targets(value["split_targets"]):
		return _failure("NON_CANONICAL_CONSTRUCTION_DAMAGE_SPLIT_TARGETS")
	var target_ids := {}; var root_ids := {}
	for target in value["split_targets"]:
		if typeof(target) != TYPE_DICTIONARY or target.keys().size() != 2 or not target.has("construct_id") or not target.has("root_item_instance_id"):
			return _failure("INVALID_CONSTRUCTION_DAMAGE_SPLIT_TARGET")
		var cid := String(target["construct_id"]); var rid := String(target["root_item_instance_id"])
		if not _identifier(cid, "construct/") or not _identifier(rid, "item/") or cid == String(value["construct_id"]): return _failure("INVALID_CONSTRUCTION_DAMAGE_SPLIT_TARGET")
		if target_ids.has(cid) or root_ids.has(rid): return _failure("DUPLICATE_CONSTRUCTION_DAMAGE_SPLIT_TARGET")
		target_ids[cid] = true; root_ids[rid] = true
	if typeof(value.get("salvage_policy")) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_DAMAGE_SALVAGE_POLICY")
	var policy_validation := PolicyScript.validate(value["salvage_policy"])
	if not bool(policy_validation.get("success", false)): return policy_validation
	if typeof(value.get("checksum")) != TYPE_STRING or String(value["checksum"]) != compute_checksum(value):
		return _failure("CONSTRUCTION_DAMAGE_REQUEST_CHECKSUM_MISMATCH")
	return UtilsScript.validation_success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)

static func _sorted_strings(values: Array) -> Array:
	var output := values.duplicate(); output.sort(); return output
static func _sorted_dictionary(value: Dictionary) -> Dictionary:
	var output := {}; var keys := value.keys(); keys.sort(); for key in keys: output[key] = value[key]
	return output
static func _sorted_targets(values: Array) -> Array:
	var output := values.duplicate(true); output.sort_custom(func(a,b): return String(a.get("construct_id", "")) < String(b.get("construct_id", ""))); return output
static func _identifier(value: String, prefix: String) -> bool:
	return value.begins_with(prefix) and value.length() > prefix.length() and value == value.strip_edges()
static func _failure(code: String) -> Dictionary:
	return UtilsScript.validation_failure(code, code)
