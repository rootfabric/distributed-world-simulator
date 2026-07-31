extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.construction_bond_record.v1"
const FIELDS: Array[String] = [
	"schema",
	"bond_id",
	"part_a_id",
	"part_b_id",
	"bond_kind",
	"strength_n",
	"state",
	"metadata",
]
const VALID_STATES: Array[String] = ["INTACT", "DEGRADED", "BROKEN"]

static func create(
	bond_id: String,
	part_a_id: String,
	part_b_id: String,
	bond_kind: String,
	strength_n: float,
	state: String = "INTACT",
	metadata: Dictionary = {}
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"bond_id": bond_id,
		"part_a_id": part_a_id,
		"part_b_id": part_b_id,
		"bond_kind": bond_kind,
		"strength_n": strength_n,
		"state": state,
		"metadata": metadata.duplicate(true),
	}

static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_BOND_SCHEMA")
	for field in ["bond_id", "part_a_id", "part_b_id", "bond_kind", "state"]:
		if typeof(value.get(field)) != TYPE_STRING or String(value[field]).strip_edges().is_empty():
			return _failure("INVALID_%s" % field.to_upper())
	if String(value["part_a_id"]) == String(value["part_b_id"]):
		return _failure("SELF_BOND_FORBIDDEN")
	if String(value["bond_kind"]) != String(value["bond_kind"]).to_upper():
		return _failure("INVALID_BOND_KIND")
	if not VALID_STATES.has(String(value["state"])):
		return _failure("INVALID_BOND_STATE")
	if typeof(value.get("strength_n")) not in [TYPE_INT, TYPE_FLOAT] or float(value["strength_n"]) <= 0.0:
		return _failure("INVALID_BOND_STRENGTH")
	if typeof(value.get("metadata")) != TYPE_DICTIONARY:
		return _failure("INVALID_BOND_METADATA")
	if not bool(UtilsScript.canonicalize(value).get("success", false)):
		return _failure("BOND_NOT_JSON_SAFE")
	return UtilsScript.validation_success()

static func _failure(code: String) -> Dictionary:
	return UtilsScript.validation_failure(code, code)
