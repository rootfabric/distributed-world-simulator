extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const FieldIdScript = preload("res://scripts/simulation/procedural/contracts/semantic_field_id.gd")
const QueryScript = preload("res://scripts/simulation/procedural/contracts/semantic_field_query.gd")
const SampleScript = preload("res://scripts/simulation/procedural/contracts/semantic_field_sample.gd")
const BundleScript = preload("res://scripts/simulation/procedural/contracts/semantic_field_bundle.gd")
const ReceiptScript = preload("res://scripts/simulation/procedural/contracts/semantic_field_composition_receipt.gd")
const RegistryScript = preload("res://scripts/simulation/procedural/semantic_fields/semantic_field_registry_v1.gd")

const COMPOSER_ID: String = "semantic-composer/g7-2-v1"
const COMPOSER_VERSION: String = "1.0.0"
const POLICY_REQUIRE_COMPLETE: String = "semantic-composition-policy/require-complete-v1"


static func compose(query: Dictionary, partial_results: Array) -> Dictionary:
	var query_validation: Dictionary = QueryScript.validate(query)
	if not bool(query_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_G7_2_COMPOSITION_QUERY", {"cause": query_validation.get("error_code", "")})
	if partial_results.is_empty():
		return GeoUtilsScript.failure("G7_2_COMPOSITION_PARTIAL_RESULTS_REQUIRED")

	var requested_lookup: Dictionary = {}
	for field_id in query["requested_field_ids"]:
		requested_lookup[String(field_id)] = true

	var normalized_parts: Array = []
	for index in range(partial_results.size()):
		var normalized: Dictionary = _normalize_partial_result(partial_results[index], index)
		if not bool(normalized.get("success", false)):
			return normalized
		var details: Dictionary = normalized["details"]
		if not Array(details["handled_field_ids"]).is_empty():
			normalized_parts.append(details)
	normalized_parts.sort_custom(func(a, b): return String(a["adapter_id"]) < String(b["adapter_id"]))

	var adapter_ids: Dictionary = {}
	var merged_samples: Dictionary = {}
	var contributions: Array = []
	for part in normalized_parts:
		var adapter_id: String = String(part["adapter_id"])
		if adapter_ids.has(adapter_id):
			return GeoUtilsScript.failure("G7_2_COMPOSITION_DUPLICATE_ADAPTER", {"adapter_id": adapter_id})
		adapter_ids[adapter_id] = true
		var sample_checksums: Dictionary = {}
		var provenance_checksums: Dictionary = {}
		for field_id_value in part["handled_field_ids"]:
			var field_id: String = String(field_id_value)
			if not requested_lookup.has(field_id):
				return GeoUtilsScript.failure("G7_2_COMPOSITION_UNREQUESTED_FIELD", {"adapter_id": adapter_id, "field_id": field_id})
			if merged_samples.has(field_id):
				return GeoUtilsScript.failure("G7_2_COMPOSITION_FIELD_CONFLICT", {
					"field_id": field_id,
					"first_adapter_id": _owner_for_field(contributions, field_id),
					"second_adapter_id": adapter_id,
				})
			var sample: Dictionary = part["samples"][field_id]
			var descriptor: Dictionary = RegistryScript.descriptor(field_id)
			if descriptor.is_empty():
				return GeoUtilsScript.failure("G7_2_COMPOSITION_UNKNOWN_FIELD", {"field_id": field_id})
			var typed_validation: Dictionary = SampleScript.validate_against_descriptor(sample, descriptor)
			if not bool(typed_validation.get("success", false)):
				return GeoUtilsScript.failure("G7_2_COMPOSITION_INVALID_SAMPLE", {
					"adapter_id": adapter_id,
					"field_id": field_id,
					"cause": typed_validation.get("error_code", ""),
				})
			var context_validation: Dictionary = _validate_sample_context(sample, query)
			if not bool(context_validation.get("success", false)):
				return context_validation
			merged_samples[field_id] = sample.duplicate(true)
			sample_checksums[field_id] = String(sample["checksum"])
			provenance_checksums[field_id] = String(sample["provenance"]["checksum"])
		contributions.append(ReceiptScript.contribution(
			adapter_id,
			String(part["adapter_version"]),
			part["handled_field_ids"],
			sample_checksums,
			provenance_checksums
		))

	var missing_fields: Array = []
	for field_id in query["requested_field_ids"]:
		if not merged_samples.has(String(field_id)):
			missing_fields.append(String(field_id))
	if not missing_fields.is_empty():
		return GeoUtilsScript.failure("G7_2_COMPOSITION_MISSING_FIELDS", {"field_ids": missing_fields})

	var bundle: Dictionary = BundleScript.create(query, merged_samples)
	var bundle_validation: Dictionary = BundleScript.validate(bundle)
	if not bool(bundle_validation.get("success", false)):
		return GeoUtilsScript.failure("G7_2_COMPOSITION_INVALID_BUNDLE", {"cause": bundle_validation.get("error_code", "")})
	var receipt: Dictionary = ReceiptScript.create(
		COMPOSER_ID,
		COMPOSER_VERSION,
		POLICY_REQUIRE_COMPLETE,
		String(query["checksum"]),
		String(bundle["checksum"]),
		contributions
	)
	var receipt_validation: Dictionary = ReceiptScript.validate(receipt)
	if not bool(receipt_validation.get("success", false)):
		return GeoUtilsScript.failure("G7_2_COMPOSITION_INVALID_RECEIPT", {"cause": receipt_validation.get("error_code", "")})
	return GeoUtilsScript.success({
		"composer_id": COMPOSER_ID,
		"composer_version": COMPOSER_VERSION,
		"policy": POLICY_REQUIRE_COMPLETE,
		"bundle": bundle,
		"receipt": receipt,
	})


static func _normalize_partial_result(raw_result, index: int) -> Dictionary:
	if typeof(raw_result) != TYPE_DICTIONARY:
		return GeoUtilsScript.failure("G7_2_COMPOSITION_INVALID_PARTIAL_RESULT", {"index": index})
	var result: Dictionary = raw_result
	if not bool(result.get("success", false)):
		return GeoUtilsScript.failure("G7_2_COMPOSITION_UPSTREAM_FAILURE", {
			"index": index,
			"cause": result.get("error_code", ""),
		})
	if typeof(result.get("details")) != TYPE_DICTIONARY:
		return GeoUtilsScript.failure("G7_2_COMPOSITION_PARTIAL_DETAILS_REQUIRED", {"index": index})
	var details: Dictionary = result["details"]
	var adapter_id: String = String(details.get("adapter_id", ""))
	if not GeoUtilsScript.is_canonical_id(adapter_id, 2):
		return GeoUtilsScript.failure("G7_2_COMPOSITION_INVALID_ADAPTER_ID", {"index": index})
	if not GeoUtilsScript.is_semantic_version(details.get("adapter_version")):
		return GeoUtilsScript.failure("G7_2_COMPOSITION_INVALID_ADAPTER_VERSION", {"adapter_id": adapter_id})
	if typeof(details.get("handled_field_ids")) != TYPE_ARRAY or typeof(details.get("samples")) != TYPE_DICTIONARY:
		return GeoUtilsScript.failure("G7_2_COMPOSITION_INVALID_PARTIAL_SHAPE", {"adapter_id": adapter_id})
	var field_ids: Array = details["handled_field_ids"].duplicate(true)
	var previous: String = ""
	for field_index in range(field_ids.size()):
		var field_id: String = String(field_ids[field_index])
		var field_validation: Dictionary = FieldIdScript.validate(field_id)
		if not bool(field_validation.get("success", false)):
			return field_validation
		if field_index > 0 and field_id <= previous:
			return GeoUtilsScript.failure("G7_2_COMPOSITION_PARTIAL_FIELDS_NOT_SORTED_UNIQUE", {"adapter_id": adapter_id})
		previous = field_id
	var sample_keys: Array = details["samples"].keys()
	sample_keys.sort()
	if sample_keys != field_ids:
		return GeoUtilsScript.failure("G7_2_COMPOSITION_PARTIAL_COVERAGE_MISMATCH", {"adapter_id": adapter_id})
	return GeoUtilsScript.success({
		"adapter_id": adapter_id,
		"adapter_version": String(details["adapter_version"]),
		"handled_field_ids": field_ids,
		"samples": Dictionary(details["samples"]).duplicate(true),
	})


static func _validate_sample_context(sample: Dictionary, query: Dictionary) -> Dictionary:
	if String(sample["body_id"]) != String(query["body_id"]):
		return GeoUtilsScript.failure("G7_2_COMPOSITION_BODY_MISMATCH", {"field_id": sample["field_id"]})
	if String(sample["frame_id"]) != String(query["frame_id"]):
		return GeoUtilsScript.failure("G7_2_COMPOSITION_FRAME_MISMATCH", {"field_id": sample["field_id"]})
	if sample["body_fixed_position_m"] != query["body_fixed_position_m"]:
		return GeoUtilsScript.failure("G7_2_COMPOSITION_POSITION_MISMATCH", {"field_id": sample["field_id"]})
	return GeoUtilsScript.success()


static func _owner_for_field(contributions: Array, field_id: String) -> String:
	for item in contributions:
		if Array(item.get("field_ids", [])).has(field_id):
			return String(item.get("adapter_id", ""))
	return ""
