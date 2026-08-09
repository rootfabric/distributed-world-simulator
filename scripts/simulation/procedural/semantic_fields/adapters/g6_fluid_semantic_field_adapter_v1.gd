extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const WaterSurfaceQueryScript = preload("res://scripts/simulation/procedural/contracts/water_surface_query.gd")
const QueryScript = preload("res://scripts/simulation/procedural/contracts/semantic_field_query.gd")
const SampleScript = preload("res://scripts/simulation/procedural/contracts/semantic_field_sample.gd")
const ProvenanceScript = preload("res://scripts/simulation/procedural/contracts/semantic_field_provenance.gd")
const RegistryScript = preload("res://scripts/simulation/procedural/semantic_fields/semantic_field_registry_v1.gd")
const ResolverScript = preload("res://scripts/simulation/procedural/hydrology/water_surface_resolver_v1.gd")

const ADAPTER_ID: String = "semantic-adapter/g6-fluid-v1"
const ADAPTER_VERSION: String = "1.0.0"
const MAX_RESOLVE_DISTANCE_M: float = 1000000000000.0
const SOURCE_KIND_FEATURE: String = "semantic-source/world-feature"
const SOURCE_KIND_FLUID_REGION: String = "semantic-source/fluid-region"
const SOURCE_KIND_RIVER_SPLINE: String = "semantic-source/river-spline"
const SOURCE_KIND_CHANNEL_PROFILE: String = "semantic-source/river-channel-profile"
const SOURCE_KIND_FLUID_SURFACE: String = "semantic-source/fluid-surface"
const SUPPORTED_FIELDS: Array[String] = [
	RegistryScript.FLUID_SURFACE_DISTANCE_M,
	RegistryScript.RIVER_DISTANCE_M,
	RegistryScript.RIVER_WIDTH_M,
]


static func sample(query: Dictionary, compiled_geographies: Array) -> Dictionary:
	var query_validation: Dictionary = QueryScript.validate(query)
	if not bool(query_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_G7_1_G6_QUERY", {"cause": query_validation.get("error_code", "")})
	var requested: Array[String] = _requested_supported(query)
	if requested.is_empty():
		return _success_result({}, requested)
	if compiled_geographies.is_empty():
		return GeoUtilsScript.failure("G7_1_G6_COMPILED_GEOGRAPHY_REQUIRED")

	var fluid_type_ids: Array = _fluid_type_ids(compiled_geographies)
	var water_query: Dictionary = WaterSurfaceQueryScript.create(
		String(query["body_id"]),
		String(query["frame_id"]),
		Array(query["body_fixed_position_m"]),
		MAX_RESOLVE_DISTANCE_M,
		fluid_type_ids
	)
	var resolved: Dictionary = ResolverScript.resolve(water_query, compiled_geographies)
	if not bool(resolved.get("success", false)):
		return GeoUtilsScript.failure("G7_1_G6_RESOLVE_FAILED", {"cause": resolved.get("error_code", "")})
	if not bool(resolved.get("details", {}).get("matched", false)):
		return GeoUtilsScript.failure("G7_1_G6_NO_FLUID_SAMPLE")
	var water_sample_value = resolved["details"].get("sample", {})
	if typeof(water_sample_value) != TYPE_DICTIONARY:
		return GeoUtilsScript.failure("INVALID_G7_1_G6_WATER_SAMPLE")
	var water_sample: Dictionary = water_sample_value
	var fluid_region_id: String = String(water_sample.get("fluid_region_id", ""))
	var candidate: Dictionary = _candidate_by_region(compiled_geographies, fluid_region_id)
	if candidate.is_empty():
		return GeoUtilsScript.failure("G7_1_G6_MATCHED_SOURCE_NOT_FOUND")

	var provenance: Dictionary = _provenance(candidate, water_sample, resolved)
	var samples: Dictionary = {}
	for field_id in requested:
		var field_value: float = 0.0
		match field_id:
			RegistryScript.RIVER_DISTANCE_M:
				field_value = float(water_sample.get("distance_to_centerline_m", 0.0))
			RegistryScript.RIVER_WIDTH_M:
				field_value = float(water_sample.get("width_m", 0.0))
			RegistryScript.FLUID_SURFACE_DISTANCE_M:
				field_value = float(water_sample.get("distance_to_surface_m", 0.0))
			_:
				continue
		if not is_finite(field_value) or field_value < 0.0:
			return GeoUtilsScript.failure("INVALID_G7_1_G6_DERIVED_VALUE", {"field_id": field_id})
		var sample_value: Dictionary = SampleScript.create(
			field_id,
			String(query["body_id"]),
			String(query["frame_id"]),
			Array(query["body_fixed_position_m"]),
			field_value,
			provenance
		)
		var sample_validation: Dictionary = SampleScript.validate_against_descriptor(
			sample_value,
			RegistryScript.descriptor(field_id)
		)
		if not bool(sample_validation.get("success", false)):
			return GeoUtilsScript.failure("INVALID_G7_1_G6_SEMANTIC_SAMPLE", {
				"field_id": field_id,
				"cause": sample_validation.get("error_code", ""),
			})
		samples[field_id] = sample_value
	return _success_result(samples, requested)


static func _provenance(candidate: Dictionary, water_sample: Dictionary, resolved: Dictionary) -> Dictionary:
	var refs: Array = []
	var source_feature_id: String = String(candidate.get("source_feature_id", water_sample.get("source_feature_id", "")))
	if not source_feature_id.is_empty():
		refs.append(ProvenanceScript.source_ref(
			SOURCE_KIND_FEATURE,
			source_feature_id,
			String(candidate.get("source_feature_checksum", ""))
		))
	var fluid_region_id: String = String(candidate.get("fluid_region_id", water_sample.get("fluid_region_id", "")))
	if not fluid_region_id.is_empty():
		refs.append(ProvenanceScript.source_ref(SOURCE_KIND_FLUID_REGION, fluid_region_id, ""))
	var spline: Dictionary = Dictionary(candidate.get("river_spline", {}))
	if not spline.is_empty():
		refs.append(ProvenanceScript.source_ref(
			SOURCE_KIND_RIVER_SPLINE,
			String(spline.get("spline_id", "")),
			String(spline.get("checksum", ""))
		))
	var profile: Dictionary = Dictionary(candidate.get("channel_profile", {}))
	if not profile.is_empty():
		refs.append(ProvenanceScript.source_ref(
			SOURCE_KIND_CHANNEL_PROFILE,
			String(profile.get("profile_id", "")),
			String(profile.get("checksum", ""))
		))
	var descriptor: Dictionary = Dictionary(candidate.get("fluid_surface_descriptor", {}))
	if not descriptor.is_empty() and not fluid_region_id.is_empty():
		refs.append(ProvenanceScript.source_ref(
			SOURCE_KIND_FLUID_SURFACE,
			fluid_region_id,
			String(descriptor.get("checksum", ""))
		))

	var configuration_hash: String = GeoUtilsScript.payload_hash({
		"adapter_id": ADAPTER_ID,
		"adapter_version": ADAPTER_VERSION,
		"resolver_id": String(resolved.get("details", {}).get("resolver_id", "")),
		"resolver_version": String(resolved.get("details", {}).get("resolver_version", "")),
		"compiled_manifest_hash": String(candidate.get("manifest_hash", "")),
		"max_resolve_distance_m": MAX_RESOLVE_DISTANCE_M,
	})
	return ProvenanceScript.create(
		ADAPTER_ID,
		ADAPTER_VERSION,
		[],
		refs,
		configuration_hash,
		{
			"source_feature_id": source_feature_id,
			"fluid_region_id": fluid_region_id,
			"resolver_id": String(resolved.get("details", {}).get("resolver_id", "")),
			"resolver_version": String(resolved.get("details", {}).get("resolver_version", "")),
			"inside_channel": bool(water_sample.get("inside_channel", false)),
			"downstream_t": float(water_sample.get("downstream_t", 0.0)),
			"ownership": "UPSTREAM_G5_G6_RIVER_FLUID_GEOGRAPHY",
		}
	)


static func _candidate_by_region(compiled_geographies: Array, fluid_region_id: String) -> Dictionary:
	for raw_candidate in compiled_geographies:
		var candidate: Dictionary = _candidate_details(raw_candidate)
		if String(candidate.get("fluid_region_id", "")) == fluid_region_id:
			return candidate
	return {}


static func _fluid_type_ids(compiled_geographies: Array) -> Array:
	var ids: Dictionary = {}
	for raw_candidate in compiled_geographies:
		var candidate: Dictionary = _candidate_details(raw_candidate)
		var descriptor_value = candidate.get("fluid_surface_descriptor", {})
		if typeof(descriptor_value) != TYPE_DICTIONARY:
			continue
		var fluid_type_id: String = String(descriptor_value.get("fluid_type_id", ""))
		if not fluid_type_id.is_empty():
			ids[fluid_type_id] = true
	var result: Array = ids.keys()
	result.sort()
	return result


static func _candidate_details(raw_candidate) -> Dictionary:
	if typeof(raw_candidate) != TYPE_DICTIONARY:
		return {}
	var candidate: Dictionary = raw_candidate
	if candidate.has("success"):
		if not bool(candidate.get("success", false)) or typeof(candidate.get("details")) != TYPE_DICTIONARY:
			return {}
		candidate = candidate["details"]
	return candidate


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
