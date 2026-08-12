extends RefCounted

const RenderDescription = preload("res://scripts/research/ecology/plant_render_description_v1.gd")
const RendererProfile = preload("res://scripts/research/ecology/plant_renderer_profile_v1.gd")
const Materializer3D = preload("res://scripts/research/ecology/plant_3d_materializer_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.plant_multiscale_representation.v1"
const VERSION := "1.0.0"
const RENDERER_VERSION := "ECO_PH5_S3_MULTI_SCALE_V1"

const TIER_0_FULL := "TIER_0_FULL"
const TIER_1_REDUCED := "TIER_1_REDUCED"
const TIER_2_CANOPY := "TIER_2_CANOPY"
const TIER_3_IMPOSTOR := "TIER_3_IMPOSTOR"
const INDIVIDUAL_TIERS: Array[String] = [TIER_0_FULL, TIER_1_REDUCED, TIER_2_CANOPY, TIER_3_IMPOSTOR]

const LEGACY_PROFILE_BY_TIER := {
	TIER_0_FULL: "FULL_PROCEDURAL",
	TIER_1_REDUCED: "BRANCH_LEAF_INSTANCED",
	TIER_2_CANOPY: "CANOPY_APPROXIMATION",
	TIER_3_IMPOSTOR: "IMPOSTOR_BILLBOARD",
}
const COST_UNITS := {
	TIER_0_FULL: 10000,
	TIER_1_REDUCED: 2500,
	TIER_2_CANOPY: 250,
	TIER_3_IMPOSTOR: 10,
}

static func build(
	description: Dictionary,
	tier: String,
	source_ecology_identity: String,
	deterministic_seed: int,
	profile: Dictionary = {}
) -> Dictionary:
	if tier not in INDIVIDUAL_TIERS:
		return _failure("ECO_PH5_S3_INDIVIDUAL_TIER_REQUIRED", {"tier": tier})
	if not _is_sha256_hex(source_ecology_identity) or deterministic_seed < 0:
		return _failure("ECO_PH5_S3_INVALID_SOURCE_IDENTITY")
	if not bool(RenderDescription.validate(description).get("success", false)):
		return _failure("ECO_PH5_S3_INVALID_RENDER_DESCRIPTION")

	var renderer_profile := RendererProfile.create("FULL_PROCEDURAL") if profile.is_empty() else profile
	if not bool(RendererProfile.validate(renderer_profile).get("success", false)):
		return _failure("ECO_PH5_S3_INVALID_RENDERER_PROFILE")

	var result := _base(description, tier, source_ecology_identity, deterministic_seed, renderer_profile)
	match tier:
		TIER_0_FULL:
			if not _apply_geometry(result, description, renderer_profile, false):
				return _failure("ECO_PH5_S3_FULL_MATERIALIZATION_FAILED")
		TIER_1_REDUCED:
			if not _apply_geometry(result, description, renderer_profile, true):
				return _failure("ECO_PH5_S3_REDUCED_MATERIALIZATION_FAILED")
		TIER_2_CANOPY:
			_apply_canopy(result, description)
		TIER_3_IMPOSTOR:
			_apply_impostor(result, description)

	result["representation_hash"] = compute_hash(result)
	result["presentation_identity"] = String(result["representation_hash"])
	return result

static func materialize_near(description: Dictionary, tier: String, profile: Dictionary) -> Dictionary:
	if tier not in [TIER_0_FULL, TIER_1_REDUCED]:
		return {}
	if not bool(RenderDescription.validate(description).get("success", false)):
		return {}
	if not bool(RendererProfile.validate(profile).get("success", false)):
		return {}
	if tier == TIER_0_FULL:
		return Materializer3D.build(description, profile)
	var reduced := _reduced_projection(description)
	return {} if reduced.is_empty() else Materializer3D.build(reduced, profile)

static func validate_artifact(representation: Dictionary) -> Dictionary:
	if String(representation.get("schema", "")) != SCHEMA or String(representation.get("version", "")) != VERSION:
		return _failure("ECO_PH5_S3_ARTIFACT_SCHEMA_VERSION_MISMATCH")
	var tier := String(representation.get("tier", ""))
	if tier not in INDIVIDUAL_TIERS:
		return _failure("ECO_PH5_S3_ARTIFACT_INVALID_TIER")
	if not bool(representation.get("derived_representation", false)):
		return _failure("ECO_PH5_S3_ARTIFACT_NOT_DERIVED")
	if String(representation.get("renderer_version", "")) != RENDERER_VERSION:
		return _failure("ECO_PH5_S3_ARTIFACT_RENDERER_VERSION_MISMATCH")
	for field_name in ["ecological_truth_hash", "source_ecology_identity", "source_graph_hash", "render_description_hash", "profile_hash", "deterministic_input_identity"]:
		if not _is_sha256_hex(String(representation.get(field_name, ""))):
			return _failure("ECO_PH5_S3_ARTIFACT_INVALID_IDENTITY", {"field": field_name})
	if String(representation["ecological_truth_hash"]) != String(representation["source_ecology_identity"]):
		return _failure("ECO_PH5_S3_ARTIFACT_SOURCE_IDENTITY_MISMATCH")
	if String(representation.get("profile_id", "")).is_empty():
		return _failure("ECO_PH5_S3_ARTIFACT_PROFILE_MISSING")
	if int(representation.get("deterministic_seed", -1)) < 0:
		return _failure("ECO_PH5_S3_ARTIFACT_INVALID_SEED")
	if int(representation.get("materialized_growth_graph_count", -1)) != 1:
		return _failure("ECO_PH5_S3_ARTIFACT_GROWTH_GRAPH_COUNT_MISMATCH")
	if not bool(representation.get("individual_materialized", false)):
		return _failure("ECO_PH5_S3_ARTIFACT_INDIVIDUAL_NOT_MATERIALIZED")
	var expected_input := _input_identity(
		String(representation["source_ecology_identity"]),
		String(representation["source_graph_hash"]),
		String(representation["render_description_hash"]),
		String(representation["profile_hash"]),
		tier,
		int(representation["deterministic_seed"])
	)
	if String(representation["deterministic_input_identity"]) != expected_input:
		return _failure("ECO_PH5_S3_ARTIFACT_INPUT_IDENTITY_MISMATCH")
	var value := String(representation.get("representation_hash", ""))
	if not _is_sha256_hex(value) or value != compute_hash(representation):
		return _failure("ECO_PH5_S3_ARTIFACT_HASH_MISMATCH")
	if String(representation.get("presentation_identity", "")) != value:
		return _failure("ECO_PH5_S3_ARTIFACT_PRESENTATION_IDENTITY_MISMATCH")
	return _success()

static func compute_hash(representation: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SCHEMA,
		VERSION,
		RENDERER_VERSION,
		String(representation.get("source_ecology_identity", "")),
		String(representation.get("source_graph_hash", "")),
		String(representation.get("render_description_hash", "")),
		String(representation.get("tier", "")),
		String(representation.get("legacy_profile_id", "")),
		String(representation.get("profile_id", "")),
		String(representation.get("profile_hash", "")),
		str(int(representation.get("deterministic_seed", -1))),
		String(representation.get("deterministic_input_identity", "")),
		str(int(representation.get("individual_seed", -1))),
		str(int(representation.get("branch_primitive_count", 0))),
		str(int(representation.get("foliage_instance_count", 0))),
		str(int(representation.get("canopy_primitive_count", 0))),
		str(int(representation.get("impostor_count", 0))),
		str(int(representation.get("cost_units", 0))),
		String(representation.get("geometry_hash", "")),
		String(representation.get("projection_description_hash", "")),
		JSON.stringify(representation.get("source_bounds", {})),
		JSON.stringify(representation.get("canopy_descriptor", {})),
		JSON.stringify(representation.get("impostor_descriptor", {})),
	])).sha256_text()

static func _base(description: Dictionary, tier: String, source_ecology_identity: String, deterministic_seed: int, profile: Dictionary) -> Dictionary:
	var graph_hash := String(description["source_graph_hash"])
	var render_hash := String(description["render_description_hash"])
	return {
		"success": true,
		"error_code": "",
		"schema": SCHEMA,
		"version": VERSION,
		"renderer_version": RENDERER_VERSION,
		"derived_representation": true,
		"ecological_truth_hash": source_ecology_identity,
		"source_ecology_identity": source_ecology_identity,
		"source_graph_hash": graph_hash,
		"render_description_hash": render_hash,
		"development_traits_checksum": String(description.get("development_traits_checksum", "")),
		"individual_seed": int(description.get("individual_seed", -1)),
		"deterministic_seed": deterministic_seed,
		"tier": tier,
		"legacy_profile_id": String(LEGACY_PROFILE_BY_TIER[tier]),
		"profile_id": String(profile["profile_id"]),
		"profile_hash": String(profile["profile_hash"]),
		"deterministic_input_identity": _input_identity(source_ecology_identity, graph_hash, render_hash, String(profile["profile_hash"]), tier, deterministic_seed),
		"individual_materialized": true,
		"materialized_growth_graph_count": 1,
		"branch_primitive_count": 0,
		"foliage_instance_count": 0,
		"canopy_primitive_count": 0,
		"impostor_count": 0,
		"cost_units": int(COST_UNITS[tier]),
		"population_projection_required": false,
		"source_bounds": Dictionary(description.get("bounds", {})).duplicate(true),
		"geometry_hash": "",
		"projection_description_hash": render_hash,
		"canopy_descriptor": {},
		"impostor_descriptor": {},
		"metrics": {},
	}

static func _apply_geometry(result: Dictionary, description: Dictionary, profile: Dictionary, reduced: bool) -> bool:
	var projection := _reduced_projection(description) if reduced else description
	if projection.is_empty():
		return false
	var built := Materializer3D.build(projection, profile)
	if built.is_empty():
		return false
	result["branch_primitive_count"] = int(built["branch_count"])
	result["foliage_instance_count"] = int(built["foliage_instance_count"])
	result["geometry_hash"] = String(built["geometry_hash"])
	result["projection_description_hash"] = String(projection["render_description_hash"])
	var vertices := int(built["branch_vertex_count"])
	var triangles := int(built["branch_triangle_count"])
	var foliage_count := int(built["foliage_instance_count"])
	result["metrics"] = {
		"representation_object_count": 3,
		"geometry_primitive_count": triangles,
		"instance_count": foliage_count,
		"estimated_memory_bytes": 512 + vertices * 32 + foliage_count * 80,
		"materialized_growth_graph_count": 1,
	}
	return true

static func _apply_canopy(result: Dictionary, description: Dictionary) -> void:
	var canopy: Dictionary = description.get("canopy", {})
	var radius := maxf(0.01, float(canopy.get("radius_xz_m", 0.01)))
	var height := maxf(0.01, float(canopy.get("height_m", 0.01)))
	var foliage: Array = description.get("foliage_anchors", [])
	var foliage_mass := 0.0
	for anchor in foliage:
		var size := maxf(0.0, float(Dictionary(anchor).get("size_m", 0.0)))
		foliage_mass += size * size
	var area := PI * radius * radius
	var density := float(foliage.size()) / maxf(area, 0.000001)
	var bounds: Dictionary = description.get("bounds", {})
	var descriptor := {
		"center": Array(canopy.get("center", [0.0, height * 0.5, 0.0])).duplicate(),
		"radius_xz_m": radius,
		"height_m": height,
		"base_y_m": maxf(0.0, float(canopy.get("base_y_m", 0.0))),
		"density": density,
		"foliage_mass_projection": maxf(foliage_mass, 0.000001),
		"branch_envelope_m": maxf(radius, float(bounds.get("radius_xz_m", radius))),
	}
	result["canopy_primitive_count"] = 1
	result["canopy_descriptor"] = descriptor
	result["metrics"] = {
		"representation_object_count": 1,
		"geometry_primitive_count": 1,
		"instance_count": 0,
		"estimated_memory_bytes": 512,
		"materialized_growth_graph_count": 1,
	}

static func _apply_impostor(result: Dictionary, description: Dictionary) -> void:
	var bounds: Dictionary = description.get("bounds", {})
	var canopy: Dictionary = description.get("canopy", {})
	var width := maxf(0.02, float(bounds.get("radius_xz_m", canopy.get("radius_xz_m", 0.01))) * 2.0)
	var height := maxf(0.02, float(bounds.get("height_m", canopy.get("height_m", 0.01))))
	var shape_identity := "|".join(PackedStringArray([
		String(description.get("source_graph_hash", "")),
		String(description.get("render_description_hash", "")),
		JSON.stringify(bounds),
		JSON.stringify(canopy),
	])).sha256_text()
	result["impostor_count"] = 1
	result["impostor_descriptor"] = {
		"center": Array(canopy.get("center", [0.0, height * 0.5, 0.0])).duplicate(),
		"width_m": width,
		"height_m": height,
		"resolution_px": 256,
		"source_shape_identity": shape_identity,
	}
	result["metrics"] = {
		"representation_object_count": 1,
		"geometry_primitive_count": 2,
		"instance_count": 1,
		"estimated_memory_bytes": 256 * 256 * 4 + 256,
		"materialized_growth_graph_count": 1,
	}

static func _reduced_projection(description: Dictionary) -> Dictionary:
	var reduced := description.duplicate(true)
	var reduced_branches := _reduce_branches(Array(description.get("branches", [])))
	var reduced_foliage := _reduce_foliage(Array(description.get("foliage_anchors", [])))
	if reduced_branches.is_empty():
		return {}
	reduced["branches"] = reduced_branches
	reduced["foliage_anchors"] = reduced_foliage
	reduced["render_description_hash"] = RenderDescription.compute_hash(reduced)
	return reduced

static func _reduce_branches(source: Array) -> Array:
	var main_chain: Array = []
	var lateral_groups := {}
	var lateral_order: Array[String] = []
	for value in source:
		var branch: Dictionary = value
		if bool(branch.get("main_axis", false)):
			main_chain.append(branch)
		else:
			var segment_id := String(branch.get("segment_id", ""))
			var group_id := segment_id.get_slice("_", 0)
			if not lateral_groups.has(group_id):
				lateral_groups[group_id] = []
				lateral_order.append(group_id)
			lateral_groups[group_id].append(branch)
	var result: Array = []
	if not main_chain.is_empty():
		result.append(_merge_branch_chain(main_chain, "reduced/main", true))
	for group_id in lateral_order:
		var chain: Array = lateral_groups[group_id]
		if not chain.is_empty():
			result.append(_merge_branch_chain(chain, "reduced/%s" % group_id, false))
	return result

static func _merge_branch_chain(chain: Array, segment_id: String, main_axis: bool) -> Dictionary:
	var first: Dictionary = chain[0]
	var last: Dictionary = chain[chain.size() - 1]
	var total_length := 0.0
	for value in chain:
		total_length += float(Dictionary(value).get("length_m", 0.0))
	return {
		"segment_id": segment_id,
		"parent_segment_id": "",
		"main_axis": main_axis,
		"axis_order": 0 if main_axis else 1,
		"start": Array(first.get("start", [0.0, 0.0, 0.0])).duplicate(),
		"end": Array(last.get("end", [0.0, 0.0, 0.0])).duplicate(),
		"radius_start_m": float(first.get("radius_start_m", 0.0025)),
		"radius_end_m": float(last.get("radius_end_m", 0.0015)),
		"length_m": maxf(total_length, 0.000001),
	}

static func _reduce_foliage(source: Array) -> Array:
	if source.is_empty():
		return []
	var result: Array = []
	var target := clampi(int(ceil(float(source.size()) * 0.30)), 1, source.size())
	for index in range(target):
		var source_index := mini(source.size() - 1, int(floor(float(index) * float(source.size()) / float(target))))
		result.append(Dictionary(source[source_index]).duplicate(true))
	return result

static func _input_identity(source_ecology_identity: String, graph_hash: String, render_hash: String, profile_hash: String, tier: String, deterministic_seed: int) -> String:
	return "|".join(PackedStringArray([
		source_ecology_identity,
		graph_hash,
		render_hash,
		profile_hash,
		tier,
		str(deterministic_seed),
	])).sha256_text()

static func _is_sha256_hex(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102):
			return false
	return true

static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
