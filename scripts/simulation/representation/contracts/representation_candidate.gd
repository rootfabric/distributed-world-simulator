extends RefCounted

const Utils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const RepresentationKey = preload("res://scripts/simulation/representation/contracts/representation_key.gd")

const SCHEMA := "planet_simulator.representation_candidate.v1"
const FIELDS: Array[String] = [
	"schema",
	"representation_key",
	"geometric_error_m",
	"estimated_bytes",
	"collision_capable",
	"interior_capable",
	"ready",
	"artifact_hash",
	"checksum",
]


static func create(
	representation_key: Dictionary,
	geometric_error_m: float,
	estimated_bytes: int,
	collision_capable: bool,
	interior_capable: bool,
	ready: bool,
	artifact_hash: String
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"representation_key": representation_key.duplicate(true),
		"geometric_error_m": geometric_error_m,
		"estimated_bytes": estimated_bytes,
		"collision_capable": collision_capable,
		"interior_capable": interior_capable,
		"ready": ready,
		"artifact_hash": artifact_hash,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_REPRESENTATION_CANDIDATE_SCHEMA")
	if typeof(value.get("representation_key")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_REPRESENTATION_CANDIDATE_KEY")
	checked = RepresentationKey.validate(value["representation_key"])
	if not bool(checked.get("success", false)):
		return checked
	if String(value["representation_key"].get("artifact_kind", "")) == "NONE":
		return Utils.failure("REPRESENTATION_NONE_CANDIDATE_FORBIDDEN")
	if not Utils.is_non_negative_number(value.get("geometric_error_m")):
		return Utils.failure("INVALID_REPRESENTATION_GEOMETRIC_ERROR")
	if not Utils.is_json_integer(value.get("estimated_bytes")) or int(value["estimated_bytes"]) < 1:
		return Utils.failure("INVALID_REPRESENTATION_ESTIMATED_BYTES")
	if typeof(value.get("collision_capable")) != TYPE_BOOL or typeof(value.get("interior_capable")) != TYPE_BOOL:
		return Utils.failure("INVALID_REPRESENTATION_CANDIDATE_CAPABILITIES")
	if typeof(value.get("ready")) != TYPE_BOOL:
		return Utils.failure("INVALID_REPRESENTATION_CANDIDATE_READY")
	if bool(value["ready"]):
		if not Utils.is_lower_hex_64(value.get("artifact_hash")):
			return Utils.failure("INVALID_REPRESENTATION_CANDIDATE_ARTIFACT_HASH")
	elif typeof(value.get("artifact_hash")) != TYPE_STRING or not String(value["artifact_hash"]).is_empty():
		return Utils.failure("UNREADY_REPRESENTATION_CANDIDATE_HAS_ARTIFACT")
	return Utils.validate_checksum(value)
