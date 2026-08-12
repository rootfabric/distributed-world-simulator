extends SceneTree

const Probes = preload("res://scripts/research/ecology/plant_render_description_probes_v1.gd")
const RendererProfile = preload("res://scripts/research/ecology/plant_renderer_profile_v1.gd")
const Representation = preload("res://scripts/research/ecology/plant_multiscale_representation_v1.gd")
const FarMaterializer = preload("res://scripts/research/ecology/plant_far_representation_materializer_v1.gd")

const SEED := 530031
var assertions := 0

func _init() -> void:
	var reference: Dictionary = Probes.run_all()["REFERENCE"]
	var graph: Dictionary = reference["growth_graph"]
	var description: Dictionary = reference["render_description"]
	var profile := RendererProfile.create("FULL_PROCEDURAL")
	var ecology_identity := "|".join(PackedStringArray([
		String(reference["phenotype_hash"]),
		String(graph["graph_hash"]),
		String(description["render_description_hash"]),
	])).sha256_text()
	var tokens := PackedStringArray()
	for tier in Representation.INDIVIDUAL_TIERS:
		var artifact := Representation.build_individual(description, tier, ecology_identity, SEED, profile)
		_assert(bool(artifact.get("success", false)))
		_assert(bool(Representation.validate_artifact(artifact).get("success", false)))
		tokens.append("%s|%s" % [tier, String(artifact["representation_hash"])])
		if tier in [Representation.TIER_2_CANOPY, Representation.TIER_3_IMPOSTOR]:
			var far := FarMaterializer.build(artifact)
			_assert(bool(far.get("success", false)))
			tokens.append("MATERIALIZED|%s|%s" % [tier, String(far["materialization_hash"])])
	var population_truth := {
		"schema": Representation.POPULATION_SOURCE_SCHEMA,
		"patch_id": "eco/ph5-s3/restart-patch",
		"canonical_organism_count": 1000000,
		"center": [0.0, 0.0, 0.0],
		"radius_m": 500.0,
		"mean_height_m": 2.5,
		"mean_canopy_radius_m": 0.8,
		"foliage_mass_projection": 180000.0,
		"biomass_projection_kg": 700000.0,
		"density_per_m2": 1.273240,
	}
	population_truth["population_truth_hash"] = Representation.compute_population_truth_hash(population_truth)
	var population := Representation.build_population(population_truth, profile, SEED)
	var population_visual := FarMaterializer.build(population)
	_assert(bool(population.get("success", false)))
	_assert(int(population["materialized_growth_graph_count"]) == 0)
	_assert(bool(population_visual.get("success", false)))
	_assert(population_visual["multimesh"] is MultiMesh)
	tokens.append("POPULATION_ONLY|%s|%s" % [String(population["representation_hash"]), String(population_visual["materialization_hash"])])
	var hash := "\n".join(tokens).sha256_text()
	print("ECO.PH5-S3 Restart Replay: PASS (%d assertions) hash=%s" % [assertions, hash])
	quit(0)

func _assert(condition: bool) -> void:
	assert(condition)
	assertions += 1
