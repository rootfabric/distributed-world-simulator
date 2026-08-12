extends RefCounted

const RendererProfile = preload("res://scripts/research/ecology/plant_renderer_profile_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.plant_multiscale_representation.v1"
const VERSION := "1.0.0"
const RENDERER_VERSION := "ECO_PH5_S3_MULTI_SCALE_V1"
const POPULATION_SOURCE_SCHEMA := "distributed_world_simulator.ecology.population_representation_source.v1"
const TIER_4_POPULATION_ONLY := "TIER_4_POPULATION_ONLY"
const MAX_POPULATION_VISUAL_INSTANCES := 128

static func build(population_truth: Dictionary, profile: Dictionary, deterministic_seed: int) -> Dictionary:
	if not _valid_source(population_truth) or deterministic_seed < 0:
		return _failure("ECO_PH5_S3_INVALID_POPULATION_SOURCE")
	if not bool(RendererProfile.validate(profile).get("success", false)):
		return _failure("ECO_PH5_S3_INVALID_RENDERER_PROFILE")

	var source := population_truth.duplicate(true)
	var truth_hash := String(source["population_truth_hash"])
	var canonical_count := int(source["canonical_organism_count"])
	var visual_samples := mini(MAX_POPULATION_VISUAL_INSTANCES, maxi(1, int(ceil(sqrt(float(canonical_count))))))
	var input_identity := _input_identity(truth_hash, String(profile["profile_hash"]), deterministic_seed)
	var aggregate := {
		"center": Array(source["center"]).duplicate(),
		"radius_m": float(source["radius_m"]),
		"mean_height_m": float(source["mean_height_m"]),
		"mean_canopy_radius_m": float(source["mean_canopy_radius_m"]),
		"foliage_mass_projection": float(source["foliage_mass_projection"]),
		"biomass_projection_kg": float(source["biomass_projection_kg"]),
		"density_per_m2": float(source["density_per_m2"]),
	}
	var result := {
		"success": true,
		"error_code": "",
		"schema": SCHEMA,
		"version": VERSION,
		"renderer_version": RENDERER_VERSION,
		"derived_representation": true,
		"ecological_truth_hash": truth_hash,
		"source_ecology_identity": truth_hash,
		"source_graph_hash": "",
		"render_description_hash": "",
		"development_traits_checksum": "",
		"individual_seed": -1,
		"deterministic_seed": deterministic_seed,
		"tier": TIER_4_POPULATION_ONLY,
		"legacy_profile_id": "",
		"profile_id": String(profile["profile_id"]),
		"profile_hash": String(profile["profile_hash"]),
		"deterministic_input_identity": input_identity,
		"individual_materialized": false,
		"materialized_growth_graph_count": 0,
		"branch_primitive_count": 0,
		"foliage_instance_count": 0,
		"canopy_primitive_count": 0,
		"impostor_count": 0,
		"cost_units": 1,
		"population_projection_required": true,
		"population_patch_id": String(source["patch_id"]),
		"canonical_organism_count": canonical_count,
		"visual_sample_count": visual_samples,
		"aggregate_descriptor": aggregate,
		"metrics": {
			"representation_object_count": 1,
			"geometry_primitive_count": 1,
			"instance_count": visual_samples,
			"estimated_memory_bytes": 384 + visual_samples * 64,
			"materialized_growth_graph_count": 0,
		},
	}
	result["representation_hash"] = compute_hash(result)
	result["presentation_identity"] = String(result["representation_hash"])
	return result

static func validate_artifact(representation: Dictionary) -> Dictionary:
	if String(representation.get("schema", "")) != SCHEMA or String(representation.get("version", "")) != VERSION:
		return _failure("ECO_PH5_S3_ARTIFACT_SCHEMA_VERSION_MISMATCH")
	if String(representation.get("tier", "")) != TIER_4_POPULATION_ONLY:
		return _failure("ECO_PH5_S3_ARTIFACT_INVALID_TIER")
	if not bool(representation.get("derived_representation", false)) or bool(representation.get("individual_materialized", true)):
		return _failure("ECO_PH5_S3_POPULATION_ARTIFACT_NOT_AGGREGATE")
	if String(representation.get("renderer_version", "")) != RENDERER_VERSION:
		return _failure("ECO_PH5_S3_ARTIFACT_RENDERER_VERSION_MISMATCH")
	for field_name in ["ecological_truth_hash", "source_ecology_identity", "profile_hash", "deterministic_input_identity"]:
		if not _is_sha256_hex(String(representation.get(field_name, ""))):
			return _failure("ECO_PH5_S3_ARTIFACT_INVALID_IDENTITY", {"field": field_name})
	if String(representation["ecological_truth_hash"]) != String(representation["source_ecology_identity"]):
		return _failure("ECO_PH5_S3_ARTIFACT_SOURCE_IDENTITY_MISMATCH")
	if not String(representation.get("source_graph_hash", "")).is_empty() or not String(representation.get("render_description_hash", "")).is_empty():
		return _failure("ECO_PH5_S3_POPULATION_ARTIFACT_INDIVIDUAL_SOURCE_LEAK")
	if String(representation.get("profile_id", "")).is_empty() or int(representation.get("deterministic_seed", -1)) < 0:
		return _failure("ECO_PH5_S3_POPULATION_ARTIFACT_PROVENANCE_MISSING")
	if int(representation.get("canonical_organism_count", 0)) <= 0:
		return _failure("ECO_PH5_S3_POPULATION_ARTIFACT_INVALID_COUNT")
	var samples := int(representation.get("visual_sample_count", 0))
	if samples <= 0 or samples > MAX_POPULATION_VISUAL_INSTANCES:
		return _failure("ECO_PH5_S3_POPULATION_ARTIFACT_INVALID_SAMPLE_COUNT")
	if int(representation.get("materialized_growth_graph_count", -1)) != 0:
		return _failure("ECO_PH5_S3_POPULATION_ARTIFACT_MATERIALIZED_GRAPH_LEAK")
	if not representation.get("aggregate_descriptor", {}) is Dictionary:
		return _failure("ECO_PH5_S3_POPULATION_ARTIFACT_INVALID_DESCRIPTOR")
	var expected_input := _input_identity(String(representation["source_ecology_identity"]), String(representation["profile_hash"]), int(representation["deterministic_seed"]))
	if String(representation["deterministic_input_identity"]) != expected_input:
		return _failure("ECO_PH5_S3_ARTIFACT_INPUT_IDENTITY_MISMATCH")
	var value := String(representation.get("representation_hash", ""))
	if not _is_sha256_hex(value) or value != compute_hash(representation):
		return _failure("ECO_PH5_S3_ARTIFACT_HASH_MISMATCH")
	if String(representation.get("presentation_identity", "")) != value:
		return _failure("ECO_PH5_S3_ARTIFACT_PRESENTATION_IDENTITY_MISMATCH")
	return _success()

static func compute_truth_hash(source: Dictionary) -> String:
	return "|".join(PackedStringArray([
		POPULATION_SOURCE_SCHEMA,
		String(source.get("patch_id", "")),
		str(int(source.get("canonical_organism_count", 0))),
		_vec_token(Array(source.get("center", []))),
		"%.9f" % float(source.get("radius_m", 0.0)),
		"%.9f" % float(source.get("mean_height_m", 0.0)),
		"%.9f" % float(source.get("mean_canopy_radius_m", 0.0)),
		"%.9f" % float(source.get("foliage_mass_projection", 0.0)),
		"%.9f" % float(source.get("biomass_projection_kg", 0.0)),
		"%.9f" % float(source.get("density_per_m2", 0.0)),
	])).sha256_text()

static func compute_hash(representation: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SCHEMA,
		VERSION,
		RENDERER_VERSION,
		String(representation.get("source_ecology_identity", "")),
		TIER_4_POPULATION_ONLY,
		String(representation.get("profile_id", "")),
		String(representation.get("profile_hash", "")),
		str(int(representation.get("deterministic_seed", -1))),
		String(representation.get("deterministic_input_identity", "")),
		str(int(representation.get("cost_units", 0))),
		String(representation.get("population_patch_id", "")),
		str(int(representation.get("canonical_organism_count", 0))),
		str(int(representation.get("visual_sample_count", 0))),
		JSON.stringify(representation.get("aggregate_descriptor", {})),
	])).sha256_text()

static func _valid_source(source: Dictionary) -> bool:
	if String(source.get("schema", "")) != POPULATION_SOURCE_SCHEMA:
		return false
	var patch_id := String(source.get("patch_id", ""))
	if patch_id.is_empty() or patch_id != patch_id.strip_edges():
		return false
	if typeof(source.get("canonical_organism_count")) != TYPE_INT or int(source.get("canonical_organism_count", 0)) <= 0:
		return false
	var center: Array = source.get("center", [])
	if center.size() != 3:
		return false
	for value in center:
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			return false
	for field_name in ["radius_m", "mean_height_m", "mean_canopy_radius_m", "foliage_mass_projection", "biomass_projection_kg", "density_per_m2"]:
		var value = source.get(field_name)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < 0.0:
			return false
	if float(source.get("radius_m", 0.0)) <= 0.0:
		return false
	var truth_hash := String(source.get("population_truth_hash", ""))
	return _is_sha256_hex(truth_hash) and truth_hash == compute_truth_hash(source)

static func _input_identity(source_ecology_identity: String, profile_hash: String, deterministic_seed: int) -> String:
	return "|".join(PackedStringArray([
		source_ecology_identity,
		"",
		"",
		profile_hash,
		TIER_4_POPULATION_ONLY,
		str(deterministic_seed),
	])).sha256_text()

static func _vec_token(values: Array) -> String:
	if values.size() != 3:
		return "INVALID"
	return "%.9f,%.9f,%.9f" % [float(values[0]), float(values[1]), float(values[2])]

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
