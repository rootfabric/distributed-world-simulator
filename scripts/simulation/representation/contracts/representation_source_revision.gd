extends RefCounted

const Utils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")

const SCHEMA := "planet_simulator.representation_source_revision.v1"
const FIELDS: Array[String] = [
	"schema",
	"source_domain",
	"source_id",
	"authority_epoch",
	"source_revision",
	"source_hash",
	"dependency_hash",
	"checksum",
]


static func create(
	source_domain: String,
	source_id: String,
	authority_epoch: int,
	source_revision: int,
	source_hash: String,
	dependency_hash: String
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"source_domain": source_domain,
		"source_id": source_id,
		"authority_epoch": authority_epoch,
		"source_revision": source_revision,
		"source_hash": source_hash,
		"dependency_hash": dependency_hash,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_REPRESENTATION_SOURCE_REVISION_SCHEMA")
	if not Utils.is_source_domain(value.get("source_domain")):
		return Utils.failure("INVALID_REPRESENTATION_SOURCE_DOMAIN")
	if not Utils.is_canonical_id(value.get("source_id"), 2):
		return Utils.failure("INVALID_REPRESENTATION_SOURCE_ID")
	if not Utils.is_json_integer(value.get("authority_epoch")) or int(value["authority_epoch"]) < 1:
		return Utils.failure("INVALID_REPRESENTATION_AUTHORITY_EPOCH")
	if not Utils.is_json_integer(value.get("source_revision")) or int(value["source_revision"]) < 0:
		return Utils.failure("INVALID_REPRESENTATION_SOURCE_REVISION")
	if not Utils.is_lower_hex_64(value.get("source_hash")):
		return Utils.failure("INVALID_REPRESENTATION_SOURCE_HASH")
	if not Utils.is_lower_hex_64(value.get("dependency_hash")):
		return Utils.failure("INVALID_REPRESENTATION_DEPENDENCY_HASH")
	return Utils.validate_checksum(value)
