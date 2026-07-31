extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.composite_part_slot.v1"
const FIELDS: Array[String] = [
	"schema",
	"slot_id",
	"definition_id",
	"display_name",
	"part_kind",
	"role",
	"mass_kg",
	"local_position_m",
	"required_components",
	"metadata",
]


static func create(
	slot_id: String,
	definition_id: String,
	display_name: String,
	part_kind: String,
	role: String,
	mass_kg: float,
	local_position_m: Array,
	required_components: Dictionary = {},
	metadata: Dictionary = {}
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"slot_id": slot_id,
		"definition_id": definition_id,
		"display_name": display_name,
		"part_kind": part_kind,
		"role": role,
		"mass_kg": mass_kg,
		"local_position_m": local_position_m.duplicate(true),
		"required_components": required_components.duplicate(true),
		"metadata": metadata.duplicate(true),
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_COMPOSITE_PART_SLOT_SCHEMA")
	if not _is_path_id(String(value.get("slot_id", "")), "slot/"):
		return _failure("INVALID_COMPOSITE_PART_SLOT_ID")
	if not _is_plain_identifier(String(value.get("definition_id", ""))):
		return _failure("INVALID_COMPOSITE_PART_DEFINITION_ID")
	if typeof(value.get("display_name")) != TYPE_STRING or String(value["display_name"]).strip_edges().is_empty():
		return _failure("COMPOSITE_PART_SLOT_NAME_REQUIRED")
	if not _is_upper_kind(String(value.get("part_kind", ""))):
		return _failure("INVALID_COMPOSITE_PART_KIND")
	if not _is_lower_token(String(value.get("role", ""))):
		return _failure("INVALID_COMPOSITE_PART_ROLE")
	if typeof(value.get("mass_kg")) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value["mass_kg"])) or float(value["mass_kg"]) <= 0.0:
		return _failure("INVALID_COMPOSITE_PART_MASS")
	if typeof(value.get("local_position_m")) != TYPE_ARRAY or value["local_position_m"].size() != 3:
		return _failure("INVALID_COMPOSITE_PART_POSITION")
	for component in value["local_position_m"]:
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(component)):
			return _failure("INVALID_COMPOSITE_PART_POSITION")
	for field in ["required_components", "metadata"]:
		if typeof(value.get(field)) != TYPE_DICTIONARY:
			return _failure("INVALID_COMPOSITE_PART_%s" % field.to_upper())
		if not bool(UtilsScript.canonicalize(value[field]).get("success", false)):
			return _failure("COMPOSITE_PART_%s_NOT_JSON_SAFE" % field.to_upper())
	if not bool(UtilsScript.canonicalize(value).get("success", false)):
		return _failure("COMPOSITE_PART_SLOT_NOT_JSON_SAFE")
	return _success()


static func matches_projection(slot: Dictionary, projection: Dictionary) -> bool:
	if String(slot.get("definition_id", "")) != String(projection.get("definition_id", "")):
		return false
	if int(projection.get("quantity", 0)) != 1:
		return false
	return _is_subset_dictionary(
		Dictionary(slot.get("required_components", {})),
		Dictionary(projection.get("components", {}))
	)


static func _is_subset_dictionary(required: Dictionary, actual: Dictionary) -> bool:
	for key in required:
		if not actual.has(key):
			return false
		var required_value = required[key]
		var actual_value = actual[key]
		if required_value is Dictionary:
			if not actual_value is Dictionary or not _is_subset_dictionary(Dictionary(required_value), Dictionary(actual_value)):
				return false
		elif UtilsScript.canonical_json(required_value) != UtilsScript.canonical_json(actual_value):
			return false
	return true


static func _is_path_id(value: String, prefix: String) -> bool:
	if not value.begins_with(prefix) or value.length() <= prefix.length() or value != value.to_lower() or value.contains("//"):
		return false
	for segment in value.split("/", true):
		if not _is_lower_token(segment):
			return false
	return true


static func _is_plain_identifier(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges().to_lower():
		return false
	for character in value:
		if not String(character) in "abcdefghijklmnopqrstuvwxyz0123456789-_.":
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


static func _success() -> Dictionary:
	return {"success": true, "error_code": "", "message": ""}


static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": code}
