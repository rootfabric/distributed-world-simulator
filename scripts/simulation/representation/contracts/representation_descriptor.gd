extends RefCounted

const Utils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const RepresentationKey = preload("res://scripts/simulation/representation/contracts/representation_key.gd")
const ArtifactManifest = preload("res://scripts/simulation/representation/contracts/representation_artifact_manifest.gd")
const Candidate = preload("res://scripts/simulation/representation/contracts/representation_candidate.gd")

const SCHEMA := "planet_simulator.representation_descriptor.v1"
const AVAILABILITY: Array[String] = ["BUILDING", "READY", "STALE", "UNAVAILABLE"]
const FIELDS: Array[String] = [
	"schema",
	"representation_key",
	"availability",
	"geometric_error_m",
	"estimated_bytes",
	"collision_capable",
	"interior_capable",
	"artifact_hash",
	"checksum",
]


static func create(
	representation_key: Dictionary,
	availability: String,
	geometric_error_m: float,
	estimated_bytes: int,
	collision_capable: bool,
	interior_capable: bool,
	artifact_hash: String
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"representation_key": representation_key.duplicate(true),
		"availability": availability,
		"geometric_error_m": geometric_error_m,
		"estimated_bytes": estimated_bytes,
		"collision_capable": collision_capable,
		"interior_capable": interior_capable,
		"artifact_hash": artifact_hash,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func from_manifest(manifest: Dictionary, availability: String = "READY") -> Dictionary:
	var checked: Dictionary = ArtifactManifest.validate(manifest)
	if not bool(checked.get("success", false)):
		return {}
	return create(
		manifest["representation_key"],
		availability,
		float(manifest["geometric_error_m"]),
		int(manifest["byte_size"]),
		bool(manifest["collision_capable"]),
		bool(manifest["interior_capable"]),
		String(manifest["artifact_hash"])
	)


static func to_candidate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = validate(value)
	if not bool(checked.get("success", false)):
		return {}
	return Candidate.create(
		value["representation_key"],
		float(value["geometric_error_m"]),
		int(value["estimated_bytes"]),
		bool(value["collision_capable"]),
		bool(value["interior_capable"]),
		String(value["availability"]) == "READY",
		String(value["artifact_hash"]) if String(value["availability"]) == "READY" else ""
	)


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_REPRESENTATION_DESCRIPTOR_SCHEMA")
	if typeof(value.get("representation_key")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_REPRESENTATION_DESCRIPTOR_KEY")
	checked = RepresentationKey.validate(value["representation_key"])
	if not bool(checked.get("success", false)):
		return checked
	if typeof(value.get("availability")) != TYPE_STRING or not AVAILABILITY.has(String(value["availability"])):
		return Utils.failure("INVALID_REPRESENTATION_DESCRIPTOR_AVAILABILITY")
	if not Utils.is_non_negative_number(value.get("geometric_error_m")):
		return Utils.failure("INVALID_REPRESENTATION_GEOMETRIC_ERROR")
	if not Utils.is_json_integer(value.get("estimated_bytes")) or int(value["estimated_bytes"]) < 1:
		return Utils.failure("INVALID_REPRESENTATION_ESTIMATED_BYTES")
	if typeof(value.get("collision_capable")) != TYPE_BOOL or typeof(value.get("interior_capable")) != TYPE_BOOL:
		return Utils.failure("INVALID_REPRESENTATION_DESCRIPTOR_CAPABILITIES")
	var availability: String = String(value["availability"])
	if availability in ["READY", "STALE"]:
		if not Utils.is_lower_hex_64(value.get("artifact_hash")):
			return Utils.failure("INVALID_REPRESENTATION_DESCRIPTOR_ARTIFACT_HASH")
	elif typeof(value.get("artifact_hash")) != TYPE_STRING or not String(value["artifact_hash"]).is_empty():
		return Utils.failure("UNAVAILABLE_REPRESENTATION_DESCRIPTOR_HAS_ARTIFACT")
	return Utils.validate_checksum(value)
