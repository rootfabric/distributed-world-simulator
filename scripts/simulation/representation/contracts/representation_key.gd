extends RefCounted

const Utils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")

const SCHEMA := "planet_simulator.representation_key.v1"
const FIELDS: Array[String] = [
	"schema",
	"source_revision",
	"scope_id",
	"lod_level",
	"artifact_kind",
	"variant_id",
	"checksum",
]


static func create(
	source_revision: Dictionary,
	scope_id: String,
	lod_level: int,
	artifact_kind: String,
	variant_id: String = "representation-variant/default"
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"source_revision": source_revision.duplicate(true),
		"scope_id": scope_id,
		"lod_level": lod_level,
		"artifact_kind": artifact_kind,
		"variant_id": variant_id,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_REPRESENTATION_KEY_SCHEMA")
	if typeof(value.get("source_revision")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_REPRESENTATION_KEY_SOURCE")
	checked = SourceRevision.validate(value["source_revision"])
	if not bool(checked.get("success", false)):
		return checked
	if not Utils.is_canonical_id(value.get("scope_id"), 2):
		return Utils.failure("INVALID_REPRESENTATION_SCOPE_ID")
	if not Utils.is_json_integer(value.get("lod_level")):
		return Utils.failure("INVALID_REPRESENTATION_LOD_LEVEL")
	var lod_level: int = int(value["lod_level"])
	if lod_level < 0 or lod_level > Utils.MAX_LOD_LEVEL:
		return Utils.failure("INVALID_REPRESENTATION_LOD_LEVEL")
	if not Utils.is_artifact_kind(value.get("artifact_kind")):
		return Utils.failure("INVALID_REPRESENTATION_ARTIFACT_KIND")
	if not Utils.is_canonical_id(value.get("variant_id"), 2):
		return Utils.failure("INVALID_REPRESENTATION_VARIANT_ID")
	return Utils.validate_checksum(value)


static func source_domain(value: Dictionary) -> String:
	return String(Dictionary(value.get("source_revision", {})).get("source_domain", ""))


static func source_id(value: Dictionary) -> String:
	return String(Dictionary(value.get("source_revision", {})).get("source_id", ""))
