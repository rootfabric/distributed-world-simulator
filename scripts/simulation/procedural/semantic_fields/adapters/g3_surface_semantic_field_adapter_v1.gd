extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const GeoProviderDescriptorScript = preload("res://scripts/simulation/procedural/contracts/geo_provider_descriptor.gd")
const QueryScript = preload("res://scripts/simulation/procedural/contracts/semantic_field_query.gd")
const SampleScript = preload("res://scripts/simulation/procedural/contracts/semantic_field_sample.gd")
const ProvenanceScript = preload("res://scripts/simulation/procedural/contracts/semantic_field_provenance.gd")
const RegistryScript = preload("res://scripts/simulation/procedural/semantic_fields/semantic_field_registry_v1.gd")

const ADAPTER_ID: String = "semantic-adapter/g3-surface-v1"
const ADAPTER_VERSION: String = "1.0.0"
const SOURCE_KIND_PROVIDER: String = "semantic-source/geo-provider"
const SUPPORTED_FIELDS: Array[String] = [RegistryScript.SURFACE_HEIGHT_M]


static func sample(query: Dictionary, provider) -> Dictionary:
	var query_validation: Dictionary = QueryScript.validate(query)
	if not bool(query_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_G7_1_G3_QUERY", {"cause": query_validation.get("error_code", "")})
	var requested: Array[String] = _requested_supported(query)
	if requested.is_empty():
		return _success_result({}, requested)
	if provider == null or not provider.has_method("get_descriptor") or not provider.has_method("sample_surface"):
		return GeoUtilsScript.failure("INVALID_G7_1_G3_PROVIDER")

	var descriptor_value = provider.get_descriptor()
	if typeof(descriptor_value) != TYPE_DICTIONARY:
		return GeoUtilsScript.failure("INVALID_G7_1_G3_PROVIDER_DESCRIPTOR")
	var descriptor: Dictionary = descriptor_value
	var descriptor_validation: Dictionary = GeoProviderDescriptorScript.validate(descriptor)
	if not bool(descriptor_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_G7_1_G3_PROVIDER_DESCRIPTOR", {"cause": descriptor_validation.get("error_code", "")})
	if not bool(descriptor.get("deterministic", false)):
		return GeoUtilsScript.failure("G7_1_G3_PROVIDER_NOT_DETERMINISTIC")
	if not Array(descriptor.get("provides", [])).has(RegistryScript.SURFACE_HEIGHT_M):
		return GeoUtilsScript.failure("G7_1_G3_SURFACE_HEIGHT_NOT_PROVIDED")

	var provider_result_value = provider.sample_surface(
		{
			"body_id": String(query["body_id"]),
			"frame_id": String(query["frame_id"]),
		},
		{
			"body_fixed_position_m": Array(query["body_fixed_position_m"]).duplicate(true),
		},
		{}
	)
	if typeof(provider_result_value) != TYPE_DICTIONARY:
		return GeoUtilsScript.failure("INVALID_G7_1_G3_PROVIDER_RESULT")
	var provider_result: Dictionary = provider_result_value
	if not bool(provider_result.get("success", false)):
		return GeoUtilsScript.failure("G7_1_G3_PROVIDER_SAMPLE_FAILED", {"cause": provider_result.get("error_code", "")})
	if typeof(provider_result.get("details")) != TYPE_DICTIONARY:
		return GeoUtilsScript.failure("G7_1_G3_PROVIDER_DETAILS_REQUIRED")
	var provider_details: Dictionary = provider_result["details"]
	if typeof(provider_details.get("values")) != TYPE_DICTIONARY:
		return GeoUtilsScript.failure("G7_1_G3_PROVIDER_VALUES_REQUIRED")
	var provider_fields: Dictionary = provider_details["values"]
	if not provider_fields.has(RegistryScript.SURFACE_HEIGHT_M):
		return GeoUtilsScript.failure("G7_1_G3_SURFACE_HEIGHT_MISSING")
	var height_value = provider_fields[RegistryScript.SURFACE_HEIGHT_M]
	if typeof(height_value) != TYPE_FLOAT and typeof(height_value) != TYPE_INT:
		return GeoUtilsScript.failure("G7_1_G3_SURFACE_HEIGHT_INVALID")
	if not is_finite(float(height_value)):
		return GeoUtilsScript.failure("G7_1_G3_SURFACE_HEIGHT_NON_FINITE")

	var provenance: Dictionary = ProvenanceScript.create(
		ADAPTER_ID,
		ADAPTER_VERSION,
		[],
		[
			ProvenanceScript.source_ref(
				SOURCE_KIND_PROVIDER,
				String(descriptor["provider_id"]),
				String(descriptor["checksum"])
			),
		],
		String(descriptor["checksum"]),
		{
			"upstream_provider_id": String(descriptor["provider_id"]),
			"upstream_contract_version": String(descriptor["contract_version"]),
			"upstream_generator_version": String(descriptor["generator_version"]),
			"ownership": "UPSTREAM_G3_PROVIDER",
		}
	)
	var sample_value: Dictionary = SampleScript.create(
		RegistryScript.SURFACE_HEIGHT_M,
		String(query["body_id"]),
		String(query["frame_id"]),
		Array(query["body_fixed_position_m"]),
		float(height_value),
		provenance
	)
	var sample_validation: Dictionary = SampleScript.validate_against_descriptor(
		sample_value,
		RegistryScript.descriptor(RegistryScript.SURFACE_HEIGHT_M)
	)
	if not bool(sample_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_G7_1_G3_SEMANTIC_SAMPLE", {"cause": sample_validation.get("error_code", "")})

	return _success_result({RegistryScript.SURFACE_HEIGHT_M: sample_value}, requested)


static func _requested_supported(query: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for field_id in query.get("requested_field_ids", []):
		var text: String = String(field_id)
		if SUPPORTED_FIELDS.has(text):
			result.append(text)
	result.sort()
	return result


static func _success_result(samples: Dictionary, handled: Array[String]) -> Dictionary:
	return GeoUtilsScript.success({
		"adapter_id": ADAPTER_ID,
		"adapter_version": ADAPTER_VERSION,
		"handled_field_ids": handled.duplicate(),
		"samples": samples.duplicate(true),
	})
