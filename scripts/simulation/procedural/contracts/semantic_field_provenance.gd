extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const FieldIdScript = preload("res://scripts/simulation/procedural/contracts/semantic_field_id.gd")

const SCHEMA: String = "planet_simulator.semantic_field_provenance.v1"
const FIELDS: Array[String] = [
	"schema",
	"producer_id",
	"producer_version",
	"source_field_ids",
	"source_refs",
	"configuration_hash",
	"metadata",
	"checksum",
]
const SOURCE_REF_FIELDS: Array[String] = ["kind", "id", "checksum"]


static func source_ref(kind: String, id: String, checksum: String = "") -> Dictionary:
	return {"kind": kind, "id": id, "checksum": checksum}


static func create(
	producer_id: String,
	producer_version: String,
	source_field_ids: Array = [],
	source_refs: Array = [],
	configuration_hash: String = "",
	metadata: Dictionary = {}
) -> Dictionary:
	var normalized_fields: Array = source_field_ids.duplicate(true)
	normalized_fields.sort()
	var normalized_refs: Array = source_refs.duplicate(true)
	normalized_refs.sort_custom(func(a, b): return _source_ref_key(a) < _source_ref_key(b))
	var effective_hash: String = configuration_hash
	if effective_hash.is_empty():
		effective_hash = GeoUtilsScript.payload_hash({})
	var value: Dictionary = {
		"schema": SCHEMA,
		"producer_id": producer_id,
		"producer_version": producer_version,
		"source_field_ids": normalized_fields,
		"source_refs": normalized_refs,
		"configuration_hash": effective_hash,
		"metadata": metadata.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_SEMANTIC_FIELD_PROVENANCE_SCHEMA")
	if not GeoUtilsScript.is_canonical_id(value.get("producer_id"), 2):
		return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_PRODUCER_ID")
	if not GeoUtilsScript.is_semantic_version(value.get("producer_version")):
		return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_PRODUCER_VERSION")
	if typeof(value.get("source_field_ids")) != TYPE_ARRAY:
		return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_PROVENANCE_FIELDS")
	var previous_field: String = ""
	for index in range(value["source_field_ids"].size()):
		var field_id = value["source_field_ids"][index]
		var field_validation: Dictionary = FieldIdScript.validate(field_id)
		if not bool(field_validation.get("success", false)):
			return field_validation
		var text: String = String(field_id)
		if index > 0 and text <= previous_field:
			return GeoUtilsScript.failure("SEMANTIC_FIELD_PROVENANCE_FIELDS_NOT_SORTED_UNIQUE")
		previous_field = text
	if typeof(value.get("source_refs")) != TYPE_ARRAY:
		return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_SOURCE_REFS")
	var previous_ref_identity: String = ""
	for index in range(value["source_refs"].size()):
		var raw_ref = value["source_refs"][index]
		if typeof(raw_ref) != TYPE_DICTIONARY:
			return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_SOURCE_REF", {"index": index})
		var ref: Dictionary = raw_ref
		var ref_exact: Dictionary = GeoUtilsScript.validate_exact_fields(ref, SOURCE_REF_FIELDS)
		if not bool(ref_exact.get("success", false)):
			return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_SOURCE_REF_FIELDS", {"index": index})
		if not GeoUtilsScript.is_canonical_id(ref.get("kind"), 2):
			return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_SOURCE_KIND", {"index": index})
		if not GeoUtilsScript.is_canonical_id(ref.get("id"), 2):
			return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_SOURCE_ID", {"index": index})
		var ref_checksum = ref.get("checksum")
		if typeof(ref_checksum) != TYPE_STRING or (not String(ref_checksum).is_empty() and not GeoUtilsScript.is_lower_hex_64(ref_checksum)):
			return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_SOURCE_CHECKSUM", {"index": index})
		var identity_key: String = _source_ref_identity_key(ref)
		if index > 0 and identity_key <= previous_ref_identity:
			return GeoUtilsScript.failure("SEMANTIC_FIELD_SOURCE_REFS_NOT_SORTED_UNIQUE")
		previous_ref_identity = identity_key
	if not GeoUtilsScript.is_lower_hex_64(value.get("configuration_hash")):
		return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_CONFIGURATION_HASH")
	if typeof(value.get("metadata")) != TYPE_DICTIONARY:
		return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_PROVENANCE_METADATA")
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.semantic_field_provenance")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return GeoUtilsScript.normalize(value, validate)


static func _source_ref_key(value) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return ""
	return "%s|%s|%s" % [String(value.get("kind", "")), String(value.get("id", "")), String(value.get("checksum", ""))]


static func _source_ref_identity_key(value) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return ""
	return "%s|%s" % [String(value.get("kind", "")), String(value.get("id", ""))]
