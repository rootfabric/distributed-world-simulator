extends RefCounted

const Utils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const RepresentationKey = preload("res://scripts/simulation/representation/contracts/representation_key.gd")

const SCHEMA := "planet_simulator.representation_artifact_manifest.v1"
const ENCODINGS: Array[String] = ["BASISU", "MESHOPT", "PNG", "RAW", "ZSTD"]
const FIELDS: Array[String] = [
	"schema",
	"representation_key",
	"artifact_hash",
	"byte_size",
	"encoding",
	"media_type",
	"geometric_error_m",
	"bounds_m",
	"collision_capable",
	"interior_capable",
	"build_generation",
	"checksum",
]


static func create(
	representation_key: Dictionary,
	artifact_hash: String,
	byte_size: int,
	encoding: String,
	media_type: String,
	geometric_error_m: float,
	bounds_m: Array,
	collision_capable: bool,
	interior_capable: bool,
	build_generation: int
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"representation_key": representation_key.duplicate(true),
		"artifact_hash": artifact_hash,
		"byte_size": byte_size,
		"encoding": encoding,
		"media_type": media_type,
		"geometric_error_m": geometric_error_m,
		"bounds_m": bounds_m.duplicate(true),
		"collision_capable": collision_capable,
		"interior_capable": interior_capable,
		"build_generation": build_generation,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_REPRESENTATION_ARTIFACT_MANIFEST_SCHEMA")
	if typeof(value.get("representation_key")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_REPRESENTATION_ARTIFACT_KEY")
	checked = RepresentationKey.validate(value["representation_key"])
	if not bool(checked.get("success", false)):
		return checked
	if String(value["representation_key"].get("artifact_kind", "")) == "NONE":
		return Utils.failure("REPRESENTATION_NONE_ARTIFACT_FORBIDDEN")
	if not Utils.is_lower_hex_64(value.get("artifact_hash")):
		return Utils.failure("INVALID_REPRESENTATION_ARTIFACT_HASH")
	if not Utils.is_json_integer(value.get("byte_size")) or int(value["byte_size"]) < 1:
		return Utils.failure("INVALID_REPRESENTATION_ARTIFACT_SIZE")
	if typeof(value.get("encoding")) != TYPE_STRING or not ENCODINGS.has(String(value["encoding"])):
		return Utils.failure("INVALID_REPRESENTATION_ARTIFACT_ENCODING")
	if typeof(value.get("media_type")) != TYPE_STRING:
		return Utils.failure("INVALID_REPRESENTATION_MEDIA_TYPE")
	var media_type: String = String(value["media_type"])
	if media_type.is_empty() or media_type != media_type.strip_edges().to_lower() or media_type.find("/") <= 0:
		return Utils.failure("INVALID_REPRESENTATION_MEDIA_TYPE")
	if not Utils.is_non_negative_number(value.get("geometric_error_m")):
		return Utils.failure("INVALID_REPRESENTATION_GEOMETRIC_ERROR")
	checked = Utils.validate_bounds_m(value.get("bounds_m"))
	if not bool(checked.get("success", false)):
		return checked
	if typeof(value.get("collision_capable")) != TYPE_BOOL or typeof(value.get("interior_capable")) != TYPE_BOOL:
		return Utils.failure("INVALID_REPRESENTATION_ARTIFACT_CAPABILITIES")
	if not Utils.is_json_integer(value.get("build_generation")) or int(value["build_generation"]) < 1:
		return Utils.failure("INVALID_REPRESENTATION_BUILD_GENERATION")
	return Utils.validate_checksum(value)
