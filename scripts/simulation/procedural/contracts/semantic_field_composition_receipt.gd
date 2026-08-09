extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const FieldIdScript = preload("res://scripts/simulation/procedural/contracts/semantic_field_id.gd")

const SCHEMA: String = "planet_simulator.semantic_field_composition_receipt.v1"
const FIELDS: Array[String] = [
	"schema",
	"composer_id",
	"composer_version",
	"policy",
	"query_checksum",
	"bundle_checksum",
	"contributions",
	"checksum",
]
const CONTRIBUTION_FIELDS: Array[String] = [
	"adapter_id",
	"adapter_version",
	"field_ids",
	"sample_checksums",
	"provenance_checksums",
]


static func contribution(
	adapter_id: String,
	adapter_version: String,
	field_ids: Array,
	sample_checksums: Dictionary,
	provenance_checksums: Dictionary
) -> Dictionary:
	var normalized_fields: Array = field_ids.duplicate(true)
	normalized_fields.sort()
	var ordered_samples: Dictionary = {}
	var ordered_provenance: Dictionary = {}
	for field_id in normalized_fields:
		var key: String = String(field_id)
		ordered_samples[key] = String(sample_checksums.get(key, ""))
		ordered_provenance[key] = String(provenance_checksums.get(key, ""))
	return {
		"adapter_id": adapter_id,
		"adapter_version": adapter_version,
		"field_ids": normalized_fields,
		"sample_checksums": ordered_samples,
		"provenance_checksums": ordered_provenance,
	}


static func create(
	composer_id: String,
	composer_version: String,
	policy: String,
	query_checksum: String,
	bundle_checksum: String,
	contributions: Array
) -> Dictionary:
	var normalized: Array = contributions.duplicate(true)
	normalized.sort_custom(func(a, b): return String(a.get("adapter_id", "")) < String(b.get("adapter_id", "")))
	var value: Dictionary = {
		"schema": SCHEMA,
		"composer_id": composer_id,
		"composer_version": composer_version,
		"policy": policy,
		"query_checksum": query_checksum,
		"bundle_checksum": bundle_checksum,
		"contributions": normalized,
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_SEMANTIC_FIELD_COMPOSITION_RECEIPT_SCHEMA")
	if not GeoUtilsScript.is_canonical_id(value.get("composer_id"), 2):
		return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_COMPOSER_ID")
	if not GeoUtilsScript.is_semantic_version(value.get("composer_version")):
		return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_COMPOSER_VERSION")
	if not GeoUtilsScript.is_canonical_id(value.get("policy"), 2):
		return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_COMPOSITION_POLICY")
	for checksum_field in ["query_checksum", "bundle_checksum"]:
		if not GeoUtilsScript.is_lower_hex_64(value.get(checksum_field)):
			return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_COMPOSITION_CHECKSUM", {"field": checksum_field})
	if typeof(value.get("contributions")) != TYPE_ARRAY or value["contributions"].is_empty():
		return GeoUtilsScript.failure("SEMANTIC_FIELD_COMPOSITION_CONTRIBUTIONS_REQUIRED")
	var previous_adapter: String = ""
	var claimed_fields: Dictionary = {}
	for index in range(value["contributions"].size()):
		var raw_contribution = value["contributions"][index]
		if typeof(raw_contribution) != TYPE_DICTIONARY:
			return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_COMPOSITION_CONTRIBUTION", {"index": index})
		var item: Dictionary = raw_contribution
		var item_exact: Dictionary = GeoUtilsScript.validate_exact_fields(item, CONTRIBUTION_FIELDS)
		if not bool(item_exact.get("success", false)):
			return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_COMPOSITION_CONTRIBUTION_FIELDS", {"index": index})
		var adapter_id: String = String(item.get("adapter_id", ""))
		if not GeoUtilsScript.is_canonical_id(adapter_id, 2):
			return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_COMPOSITION_ADAPTER_ID", {"index": index})
		if index > 0 and adapter_id <= previous_adapter:
			return GeoUtilsScript.failure("SEMANTIC_FIELD_COMPOSITION_ADAPTERS_NOT_SORTED_UNIQUE")
		previous_adapter = adapter_id
		if not GeoUtilsScript.is_semantic_version(item.get("adapter_version")):
			return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_COMPOSITION_ADAPTER_VERSION", {"adapter_id": adapter_id})
		if typeof(item.get("field_ids")) != TYPE_ARRAY or item["field_ids"].is_empty():
			return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_COMPOSITION_FIELDS", {"adapter_id": adapter_id})
		if typeof(item.get("sample_checksums")) != TYPE_DICTIONARY or typeof(item.get("provenance_checksums")) != TYPE_DICTIONARY:
			return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_COMPOSITION_CHECKSUM_MAPS", {"adapter_id": adapter_id})
		var previous_field: String = ""
		for field_index in range(item["field_ids"].size()):
			var field_id: String = String(item["field_ids"][field_index])
			var field_validation: Dictionary = FieldIdScript.validate(field_id)
			if not bool(field_validation.get("success", false)):
				return field_validation
			if field_index > 0 and field_id <= previous_field:
				return GeoUtilsScript.failure("SEMANTIC_FIELD_COMPOSITION_FIELDS_NOT_SORTED_UNIQUE", {"adapter_id": adapter_id})
			previous_field = field_id
			if claimed_fields.has(field_id):
				return GeoUtilsScript.failure("SEMANTIC_FIELD_COMPOSITION_DUPLICATE_FIELD", {"field_id": field_id})
			claimed_fields[field_id] = adapter_id
			if not item["sample_checksums"].has(field_id) or not GeoUtilsScript.is_lower_hex_64(item["sample_checksums"][field_id]):
				return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_COMPOSITION_SAMPLE_CHECKSUM", {"field_id": field_id})
			if not item["provenance_checksums"].has(field_id) or not GeoUtilsScript.is_lower_hex_64(item["provenance_checksums"][field_id]):
				return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_COMPOSITION_PROVENANCE_CHECKSUM", {"field_id": field_id})
		var sample_keys: Array = item["sample_checksums"].keys()
		var provenance_keys: Array = item["provenance_checksums"].keys()
		sample_keys.sort()
		provenance_keys.sort()
		if sample_keys != item["field_ids"] or provenance_keys != item["field_ids"]:
			return GeoUtilsScript.failure("SEMANTIC_FIELD_COMPOSITION_CHECKSUM_COVERAGE_MISMATCH", {"adapter_id": adapter_id})
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.semantic_field_composition_receipt")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return GeoUtilsScript.normalize(value, validate)
