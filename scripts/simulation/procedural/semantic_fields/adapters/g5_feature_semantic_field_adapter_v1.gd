extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const FeatureQueryScript = preload("res://scripts/simulation/procedural/contracts/feature_query.gd")
const FeatureTypeScript = preload("res://scripts/simulation/procedural/contracts/feature_type.gd")
const FeatureBoundsScript = preload("res://scripts/simulation/procedural/contracts/feature_bounds.gd")
const QueryScript = preload("res://scripts/simulation/procedural/contracts/semantic_field_query.gd")
const SampleScript = preload("res://scripts/simulation/procedural/contracts/semantic_field_sample.gd")
const ProvenanceScript = preload("res://scripts/simulation/procedural/contracts/semantic_field_provenance.gd")
const RegistryScript = preload("res://scripts/simulation/procedural/semantic_fields/semantic_field_registry_v1.gd")

const ADAPTER_ID: String = "semantic-adapter/g5-feature-v1"
const ADAPTER_VERSION: String = "1.0.0"
const SOURCE_KIND_FEATURE: String = "semantic-source/world-feature"
const INFLUENCE_POLICY: String = "FEATURE_BOUNDS_FALLOFF_V1"
const EPSILON: float = 0.000000001
const SUPPORTED_FIELDS: Array[String] = [RegistryScript.VALLEY_INFLUENCE]


static func sample(query: Dictionary, feature_graph) -> Dictionary:
	var query_validation: Dictionary = QueryScript.validate(query)
	if not bool(query_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_G7_1_G5_QUERY", {"cause": query_validation.get("error_code", "")})
	var requested: Array[String] = _requested_supported(query)
	if requested.is_empty():
		return _success_result({}, requested)
	if feature_graph == null or not feature_graph.has_method("query") or not feature_graph.has_method("manifest_hash"):
		return GeoUtilsScript.failure("INVALID_G7_1_G5_FEATURE_GRAPH")

	var manifest_hash: String = String(feature_graph.manifest_hash())
	if not GeoUtilsScript.is_lower_hex_64(manifest_hash):
		return GeoUtilsScript.failure("G7_1_G5_FEATURE_GRAPH_NOT_SEALED")
	var feature_query: Dictionary = FeatureQueryScript.create(
		String(query["body_id"]),
		String(query["frame_id"]),
		Array(query["body_fixed_position_m"]),
		0.0,
		[FeatureTypeScript.VALLEY]
	)
	var query_result_value = feature_graph.query(feature_query)
	if typeof(query_result_value) != TYPE_DICTIONARY:
		return GeoUtilsScript.failure("INVALID_G7_1_G5_QUERY_RESULT")
	var query_result: Dictionary = query_result_value
	if not bool(query_result.get("success", false)):
		return GeoUtilsScript.failure("G7_1_G5_FEATURE_QUERY_FAILED", {"cause": query_result.get("error_code", "")})
	if typeof(query_result.get("details")) != TYPE_DICTIONARY:
		return GeoUtilsScript.failure("G7_1_G5_FEATURE_QUERY_DETAILS_REQUIRED")

	var point: Vector3 = _vector3(query["body_fixed_position_m"])
	var best_feature: Dictionary = {}
	var best_influence: float = 0.0
	for raw_feature in query_result["details"].get("features", []):
		if typeof(raw_feature) != TYPE_DICTIONARY:
			continue
		var feature: Dictionary = raw_feature
		var influence: float = _bounds_influence(Dictionary(feature.get("bounds", {})), point)
		var feature_id: String = String(feature.get("feature_id", ""))
		var best_id: String = String(best_feature.get("feature_id", ""))
		if influence > best_influence + EPSILON or (absf(influence - best_influence) <= EPSILON and influence > 0.0 and (best_id.is_empty() or feature_id < best_id)):
			best_influence = influence
			best_feature = feature.duplicate(true)

	var source_refs: Array = []
	var selected_feature_id: String = ""
	if not best_feature.is_empty() and best_influence > 0.0:
		selected_feature_id = String(best_feature["feature_id"])
		source_refs.append(ProvenanceScript.source_ref(
			SOURCE_KIND_FEATURE,
			selected_feature_id,
			String(best_feature.get("checksum", ""))
		))
	var provenance: Dictionary = ProvenanceScript.create(
		ADAPTER_ID,
		ADAPTER_VERSION,
		[],
		source_refs,
		manifest_hash,
		{
			"feature_graph_manifest_hash": manifest_hash,
			"selected_feature_id": selected_feature_id,
			"influence_policy": INFLUENCE_POLICY,
			"ownership": "UPSTREAM_G5_FEATURE_GRAPH",
			"geomorphology_owned": false,
		}
	)
	var sample_value: Dictionary = SampleScript.create(
		RegistryScript.VALLEY_INFLUENCE,
		String(query["body_id"]),
		String(query["frame_id"]),
		Array(query["body_fixed_position_m"]),
		clampf(best_influence, 0.0, 1.0),
		provenance
	)
	var sample_validation: Dictionary = SampleScript.validate_against_descriptor(
		sample_value,
		RegistryScript.descriptor(RegistryScript.VALLEY_INFLUENCE)
	)
	if not bool(sample_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_G7_1_G5_SEMANTIC_SAMPLE", {"cause": sample_validation.get("error_code", "")})
	return _success_result({RegistryScript.VALLEY_INFLUENCE: sample_value}, requested)


static func _bounds_influence(bounds: Dictionary, point: Vector3) -> float:
	var validation: Dictionary = FeatureBoundsScript.validate(bounds)
	if not bool(validation.get("success", false)):
		return 0.0
	var center: Vector3 = _vector3(bounds["center_m"])
	if String(bounds["kind"]) == FeatureBoundsScript.KIND_SPHERE:
		var radius: float = float(bounds["radius_m"])
		if radius <= 0.0:
			return 0.0
		return clampf(1.0 - center.distance_to(point) / radius, 0.0, 1.0)
	var extents: Vector3 = _vector3(bounds["half_extents_m"])
	var delta: Vector3 = point - center
	var nx: float = absf(delta.x) / extents.x
	var ny: float = absf(delta.y) / extents.y
	var nz: float = absf(delta.z) / extents.z
	return clampf(1.0 - maxf(nx, maxf(ny, nz)), 0.0, 1.0)


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


static func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
