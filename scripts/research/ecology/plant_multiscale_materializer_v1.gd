extends RefCounted

const Representation = preload("res://scripts/research/ecology/plant_multiscale_representation_v1.gd")
const RendererProfile = preload("res://scripts/research/ecology/plant_renderer_profile_v1.gd")
const Materializer3D = preload("res://scripts/research/ecology/plant_3d_materializer_v1.gd")
const FarMaterializer = preload("res://scripts/research/ecology/plant_far_representation_materializer_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.plant_multiscale_materialization.v1"
const VERSION := "1.0.0"
const REDUCED_BRANCH_FRACTION := 0.35
const REDUCED_FOLIAGE_FRACTION := 0.20

static func build(description: Dictionary, representation: Dictionary) -> Dictionary:
	if not bool(representation.get("success", false)):
		return _failure("ECO_PH5_S3_REPRESENTATION_REJECTED")
	if String(representation.get("ecological_truth_hash", "")) != String(description.get("source_graph_hash", "")):
		return _failure("ECO_PH5_S3_TRUTH_HASH_MISMATCH")
	if String(representation.get("render_description_hash", "")) != String(description.get("render_description_hash", "")):
		return _failure("ECO_PH5_S3_DESCRIPTION_HASH_MISMATCH")
	var tier := String(representation.get("tier", ""))
	if not tier in Representation.TIER_ORDER:
		return _failure("ECO_PH5_S3_UNKNOWN_TIER", {"tier": tier})

	var result := {
		"success": true,
		"error_code": "",
		"schema": SCHEMA,
		"version": VERSION,
		"derived_representation": true,
		"ecological_truth_hash": String(representation["ecological_truth_hash"]),
		"render_description_hash": String(representation["render_description_hash"]),
		"representation_hash": String(representation["representation_hash"]),
		"tier": tier,
		"profile_id": "",
		"profile_hash": "",
		"branch_mesh": null,
		"foliage_multimesh": null,
		"far_mesh": null,
		"origin": Vector3.ZERO,
		"billboard": false,
		"branch_primitive_count": 0,
		"foliage_instance_count": 0,
		"far_primitive_count": 0,
		"individual_node_required": tier != Representation.TIER_4_POPULATION_ONLY,
		"source_materialization_hash": "",
	}

	if tier in [Representation.TIER_0_FULL, Representation.TIER_1_REDUCED]:
		var profile := _profile_for_tier(tier)
		var built := Materializer3D.build(description, profile)
		if built.is_empty():
			return _failure("ECO_PH5_S3_NEAR_MATERIALIZATION_FAILED", {"tier": tier})
		result["profile_id"] = String(profile["profile_id"])
		result["profile_hash"] = String(profile["profile_hash"])
		result["branch_mesh"] = built["branch_mesh"]
		result["foliage_multimesh"] = built["foliage_multimesh"]
		result["branch_primitive_count"] = int(built["branch_count"])
		result["foliage_instance_count"] = int(built["foliage_instance_count"])
		result["source_materialization_hash"] = String(built["geometry_hash"])
	else:
		var far := FarMaterializer.build(representation)
		if not bool(far.get("success", false)):
			return _failure("ECO_PH5_S3_FAR_MATERIALIZATION_FAILED", {"tier": tier})
		result["far_mesh"] = far["mesh"]
		result["origin"] = far["origin"]
		result["billboard"] = bool(far["billboard"])
		result["far_primitive_count"] = int(far["primitive_count"])
		result["individual_node_required"] = bool(far["individual_node_required"])
		result["source_materialization_hash"] = String(far["materialization_hash"])

	if int(result["branch_primitive_count"]) != int(representation["branch_primitive_count"]):
		return _failure("ECO_PH5_S3_BRANCH_COUNT_DIVERGENCE", {"tier": tier})
	if int(result["foliage_instance_count"]) != int(representation["foliage_instance_count"]):
		return _failure("ECO_PH5_S3_FOLIAGE_COUNT_DIVERGENCE", {"tier": tier})
	if int(result["far_primitive_count"]) != int(representation["canopy_primitive_count"]) + int(representation["impostor_count"]):
		return _failure("ECO_PH5_S3_FAR_COUNT_DIVERGENCE", {"tier": tier})
	result["materialization_hash"] = compute_hash(result)
	return result

static func _profile_for_tier(tier: String) -> Dictionary:
	var profile_id := "FULL_PROCEDURAL" if tier == Representation.TIER_0_FULL else "BRANCH_LEAF_INSTANCED"
	var profile := RendererProfile.create(profile_id)
	if tier == Representation.TIER_1_REDUCED:
		profile["branch_fraction"] = REDUCED_BRANCH_FRACTION
		profile["foliage_fraction"] = REDUCED_FOLIAGE_FRACTION
		profile["profile_hash"] = RendererProfile.compute_hash(profile)
	return profile

static func compute_hash(materialization: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SCHEMA,
		VERSION,
		String(materialization.get("ecological_truth_hash", "")),
		String(materialization.get("render_description_hash", "")),
		String(materialization.get("representation_hash", "")),
		String(materialization.get("tier", "")),
		String(materialization.get("profile_id", "")),
		String(materialization.get("profile_hash", "")),
		str(int(materialization.get("branch_primitive_count", 0))),
		str(int(materialization.get("foliage_instance_count", 0))),
		str(int(materialization.get("far_primitive_count", 0))),
		str(int(materialization.get("individual_node_required", false))),
		String(materialization.get("source_materialization_hash", "")),
	])).sha256_text()

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
