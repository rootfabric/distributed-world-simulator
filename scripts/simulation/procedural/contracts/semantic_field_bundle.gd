extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const QueryScript = preload("res://scripts/simulation/procedural/contracts/semantic_field_query.gd")
const SampleScript = preload("res://scripts/simulation/procedural/contracts/semantic_field_sample.gd")

const SCHEMA: String = "planet_simulator.semantic_field_bundle.v1"
const FIELDS: Array[String] = ["schema", "query", "samples", "checksum"]


static func create(query: Dictionary, samples: Dictionary) -> Dictionary:
	var ordered_samples: Dictionary = {}
	var keys: Array = samples.keys()
	keys.sort()
	for raw_key in keys:
		ordered_samples[String(raw_key)] = samples[raw_key].duplicate(true) if samples[raw_key] is Dictionary else samples[raw_key]
	var value: Dictionary = {
		"schema": SCHEMA,
		"query": query.duplicate(true),
		"samples": ordered_samples,
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_SEMANTIC_FIELD_BUNDLE_SCHEMA")
	if typeof(value.get("query")) != TYPE_DICTIONARY:
		return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_BUNDLE_QUERY")
	var query_validation: Dictionary = QueryScript.validate(value["query"])
	if not bool(query_validation.get("success", false)):
		return query_validation
	if typeof(value.get("samples")) != TYPE_DICTIONARY:
		return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_BUNDLE_SAMPLES")
	var samples: Dictionary = value["samples"]
	var requested: Array = value["query"]["requested_field_ids"]
	var sample_ids: Array = samples.keys()
	sample_ids.sort()
	if sample_ids != requested:
		return GeoUtilsScript.failure("SEMANTIC_FIELD_BUNDLE_COVERAGE_MISMATCH")
	for raw_field_id in sample_ids:
		var field_id: String = String(raw_field_id)
		if typeof(samples[field_id]) != TYPE_DICTIONARY:
			return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_BUNDLE_SAMPLE", {"field_id": field_id})
		var sample: Dictionary = samples[field_id]
		var sample_validation: Dictionary = SampleScript.validate(sample)
		if not bool(sample_validation.get("success", false)):
			return sample_validation
		if String(sample["field_id"]) != field_id:
			return GeoUtilsScript.failure("SEMANTIC_FIELD_BUNDLE_SAMPLE_ID_MISMATCH", {"field_id": field_id})
		if String(sample["body_id"]) != String(value["query"]["body_id"]) or String(sample["frame_id"]) != String(value["query"]["frame_id"]):
			return GeoUtilsScript.failure("SEMANTIC_FIELD_BUNDLE_SAMPLE_CONTEXT_MISMATCH", {"field_id": field_id})
		if sample["body_fixed_position_m"] != value["query"]["body_fixed_position_m"]:
			return GeoUtilsScript.failure("SEMANTIC_FIELD_BUNDLE_SAMPLE_POSITION_MISMATCH", {"field_id": field_id})
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.semantic_field_bundle")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return GeoUtilsScript.normalize(value, validate)
