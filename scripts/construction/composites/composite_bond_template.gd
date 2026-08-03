extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.composite_bond_template.v1"
const FIELDS: Array[String] = [
	"schema",
	"bond_template_id",
	"part_a_slot_id",
	"part_b_slot_id",
	"bond_kind",
	"strength_n",
	"metadata",
]


static func create(
	bond_template_id: String,
	part_a_slot_id: String,
	part_b_slot_id: String,
	bond_kind: String,
	strength_n: float,
	metadata: Dictionary = {}
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"bond_template_id": bond_template_id,
		"part_a_slot_id": part_a_slot_id,
		"part_b_slot_id": part_b_slot_id,
		"bond_kind": bond_kind,
		"strength_n": strength_n,
		"metadata": metadata.duplicate(true),
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_COMPOSITE_BOND_TEMPLATE_SCHEMA")
	if not _is_path_id(String(value.get("bond_template_id", "")), "bond-template/"):
		return _failure("INVALID_COMPOSITE_BOND_TEMPLATE_ID")
	for field in ["part_a_slot_id", "part_b_slot_id"]:
		if not _is_path_id(String(value.get(field, "")), "slot/"):
			return _failure("INVALID_COMPOSITE_BOND_SLOT_ID")
	if String(value["part_a_slot_id"]) == String(value["part_b_slot_id"]):
		return _failure("COMPOSITE_SELF_BOND_FORBIDDEN")
	if not _is_upper_kind(String(value.get("bond_kind", ""))):
		return _failure("INVALID_COMPOSITE_BOND_KIND")
	if typeof(value.get("strength_n")) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value["strength_n"])) or float(value["strength_n"]) <= 0.0:
		return _failure("INVALID_COMPOSITE_BOND_STRENGTH")
	if typeof(value.get("metadata")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value["metadata"]).get("success", false)):
		return _failure("INVALID_COMPOSITE_BOND_METADATA")
	if not bool(UtilsScript.canonicalize(value).get("success", false)):
		return _failure("COMPOSITE_BOND_TEMPLATE_NOT_JSON_SAFE")
	return _success()


static func _is_path_id(value: String, prefix: String) -> bool:
	if not value.begins_with(prefix) or value.length() <= prefix.length() or value != value.to_lower() or value.contains("//"):
		return false
	for segment in value.split("/", true):
		if segment.is_empty():
			return false
		for character in segment:
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
