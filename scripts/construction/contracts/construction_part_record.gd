extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.construction_part_record.v1"
const FIELDS: Array[String] = [
	"schema",
	"part_id",
	"item_instance_id",
	"part_kind",
	"role",
	"mass_kg",
	"local_position_m",
	"metadata",
]

static func create(
	part_id: String,
	item_instance_id: String,
	part_kind: String,
	role: String,
	mass_kg: float,
	local_position_m: Array,
	metadata: Dictionary = {}
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"part_id": part_id,
		"item_instance_id": item_instance_id,
		"part_kind": part_kind,
		"role": role,
		"mass_kg": mass_kg,
		"local_position_m": local_position_m.duplicate(true),
		"metadata": metadata.duplicate(true),
	}

static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_PART_SCHEMA")
	for field in ["part_id", "item_instance_id", "part_kind", "role"]:
		if typeof(value.get(field)) != TYPE_STRING or String(value[field]).strip_edges().is_empty():
			return _failure("INVALID_%s" % field.to_upper())
	if not _is_path_id(String(value["part_id"])):
		return _failure("INVALID_PART_ID")
	if not String(value["item_instance_id"]).begins_with("item/"):
		return _failure("INVALID_ITEM_INSTANCE_ID")
	if not _is_upper_kind(String(value["part_kind"])):
		return _failure("INVALID_PART_KIND")
	if not _is_lower_token(String(value["role"])):
		return _failure("INVALID_PART_ROLE")
	if typeof(value.get("mass_kg")) not in [TYPE_INT, TYPE_FLOAT] or float(value["mass_kg"]) <= 0.0:
		return _failure("INVALID_PART_MASS")
	if typeof(value.get("local_position_m")) != TYPE_ARRAY or value["local_position_m"].size() != 3:
		return _failure("INVALID_LOCAL_POSITION")
	for component in value["local_position_m"]:
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT] or is_nan(float(component)) or is_inf(float(component)):
			return _failure("INVALID_LOCAL_POSITION")
	if typeof(value.get("metadata")) != TYPE_DICTIONARY:
		return _failure("INVALID_PART_METADATA")
	if not bool(UtilsScript.canonicalize(value).get("success", false)):
		return _failure("PART_NOT_JSON_SAFE")
	return UtilsScript.validation_success()

static func _is_path_id(value: String) -> bool:
	if value != value.to_lower() or value.contains("//"):
		return false
	var segments: PackedStringArray = value.split("/", true)
	if segments.size() < 2:
		return false
	for segment in segments:
		if not _is_lower_token(segment):
			return false
	return true

static func _is_lower_token(value: String) -> bool:
	if value.is_empty() or value != value.to_lower():
		return false
	for character in value:
		if not String(character) in "abcdefghijklmnopqrstuvwxyz0123456789-_":
			return false
	return true

static func _is_upper_kind(value: String) -> bool:
	if value.is_empty() or value != value.to_upper():
		return false
	for character in value:
		if not String(character) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_":
			return false
	return true

static func _failure(code: String) -> Dictionary:
	return UtilsScript.validation_failure(code, code)
