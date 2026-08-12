extends SceneTree

const Probes = preload("res://scripts/research/ecology/plant_render_description_probes_v1.gd")
const SourceProbes = preload("res://scripts/research/ecology/plant_environment_coupled_development_probes_v1.gd")
const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const ResourceModel = preload("res://scripts/research/ecology/plant_resource_model_v1.gd")
const RendererProfile = preload("res://scripts/research/ecology/plant_renderer_profile_v1.gd")
const Representation = preload("res://scripts/research/ecology/plant_multiscale_representation_v1.gd")
const FarMaterializer = preload("res://scripts/research/ecology/plant_far_representation_materializer_v1.gd")

const SEED := 530031
const POPULATION_COUNT := 1000000
var assertions := 0

func _init() -> void:
	var results := Probes.run_all()
	var source_results := SourceProbes.run_all()
	var reference: Dictionary = results["REFERENCE"]
	var source_reference: Dictionary = source_results["REFERENCE"]
	var graph: Dictionary = reference["growth_graph"]
	var description: Dictionary = reference["render_description"]
	var profile := RendererProfile.create("FULL_PROCEDURAL")
	var truth := _truth_fixture(source_reference)
	var truth_snapshot := JSON.stringify(truth)
	var ecology_identity := truth_snapshot.sha256_text()
	var graph_hash_before := String(graph["graph_hash"])
	var source_description_hash := String(description["render_description_hash"])

	_assert(String(truth["growth_graph"]["graph_hash"]) == graph_hash_before)
	_assert(String(truth["genome"]["checksum"]).length() == 64)
	_assert(String(truth["resource_state"]["checksum"]).length() == 64)
	_assert(String(truth["selection_relevant_phenotype_hash"]).length() == 64)
	_assert(String(truth["seed_reproduction_state"]["checksum"]).length() == 64)
	_assert(not Dictionary(truth["lifecycle_state"]).is_empty())

	var artifacts := {}
	var hashes := {}
	for tier in Representation.INDIVIDUAL_TIERS:
		var first := Representation.build_individual(description, tier, ecology_identity, SEED, profile)
		var second := Representation.build_individual(description, tier, ecology_identity, SEED, profile)
		_assert(bool(first.get("success", false)))
		_assert(bool(Representation.validate_artifact(first).get("success", false)))
		_assert(String(first["representation_hash"]).length() == 64)
		_assert(String(first["representation_hash"]) == String(second["representation_hash"]))
		_assert(String(first["presentation_identity"]) == String(first["representation_hash"]))
		_assert(String(first["source_ecology_identity"]) == ecology_identity)
		_assert(String(first["source_graph_hash"]) == graph_hash_before)
		_assert(String(first["render_description_hash"]) == source_description_hash)
		_assert(String(first["profile_id"]) == "FULL_PROCEDURAL")
		_assert(String(first["profile_hash"]) == String(profile["profile_hash"]))
		_assert(String(first["renderer_version"]) == Representation.RENDERER_VERSION)
		_assert(int(first["deterministic_seed"]) == SEED)
		_assert(int(first["individual_seed"]) == int(description["individual_seed"]))
		_assert(int(first["materialized_growth_graph_count"]) == 1)
		_assert(JSON.stringify(truth) == truth_snapshot)
		_assert(String(graph["graph_hash"]) == graph_hash_before)
		artifacts[tier] = first
		hashes[String(first["representation_hash"])] = true
	_assert(hashes.size() == 4)

	var full: Dictionary = artifacts[Representation.TIER_0_FULL]
	var reduced: Dictionary = artifacts[Representation.TIER_1_REDUCED]
	var canopy: Dictionary = artifacts[Representation.TIER_2_CANOPY]
	var impostor: Dictionary = artifacts[Representation.TIER_3_IMPOSTOR]
	_assert(int(full["branch_primitive_count"]) == Array(description["branches"]).size())
	_assert(int(full["foliage_instance_count"]) == Array(description["foliage_anchors"]).size())
	_assert(String(full["geometry_hash"]) == "5b869596e4c341f1f43aa457828016ec8af657a1c0e771b22a7348f1e8ae743e")
	_assert(int(reduced["branch_primitive_count"]) < int(full["branch_primitive_count"]))
	_assert(int(reduced["foliage_instance_count"]) < int(full["foliage_instance_count"]))
	_assert(Dictionary(reduced["source_bounds"]) == Dictionary(full["source_bounds"]))
	_assert(float(canopy["canopy_descriptor"]["radius_xz_m"]) > 0.0)
	_assert(float(canopy["canopy_descriptor"]["density"]) >= 0.0)
	_assert(float(canopy["canopy_descriptor"]["foliage_mass_projection"]) > 0.0)
	_assert(float(canopy["canopy_descriptor"]["branch_envelope_m"]) > 0.0)
	_assert(float(impostor["impostor_descriptor"]["width_m"]) > 0.0)
	_assert(float(impostor["impostor_descriptor"]["height_m"]) > 0.0)
	_assert(String(impostor["impostor_descriptor"]["source_shape_identity"]).length() == 64)

	var full_geometry := Representation.materialize_near(description, Representation.TIER_0_FULL, profile)
	var reduced_geometry := Representation.materialize_near(description, Representation.TIER_1_REDUCED, profile)
	_assert(full_geometry["branch_mesh"] is ArrayMesh)
	_assert(full_geometry["foliage_multimesh"] is MultiMesh)
	_assert(reduced_geometry["branch_mesh"] is ArrayMesh)
	_assert(reduced_geometry["foliage_multimesh"] is MultiMesh)
	_assert(int(reduced_geometry["branch_count"]) < int(full_geometry["branch_count"]))
	_assert(int(reduced_geometry["foliage_instance_count"]) < int(full_geometry["foliage_instance_count"]))
	_assert(String(full_geometry["source_graph_hash"]) == graph_hash_before)
	_assert(String(reduced_geometry["source_graph_hash"]) == graph_hash_before)

	var canopy_mesh := FarMaterializer.build(canopy)
	var impostor_mesh := FarMaterializer.build(impostor)
	_assert(bool(canopy_mesh["success"]) and canopy_mesh["mesh"] is SphereMesh)
	_assert(bool(impostor_mesh["success"]) and impostor_mesh["mesh"] is QuadMesh)
	_assert(bool(impostor_mesh["billboard"]))
	_assert(String(canopy_mesh["source_ecology_identity"]) == ecology_identity)
	_assert(String(impostor_mesh["source_ecology_identity"]) == ecology_identity)

	var transition_order := [Representation.TIER_0_FULL, Representation.TIER_1_REDUCED, Representation.TIER_2_CANOPY, Representation.TIER_3_IMPOSTOR, Representation.TIER_0_FULL]
	var transition_hashes: Array[String] = []
	for tier in transition_order:
		var switched := Representation.build_individual(description, tier, ecology_identity, SEED, profile)
		transition_hashes.append(String(switched["representation_hash"]))
		_assert(JSON.stringify(truth) == truth_snapshot)
		_assert(String(truth["growth_graph"]["graph_hash"]) == graph_hash_before)
		_assert(String(switched["source_ecology_identity"]) == ecology_identity)
	_assert(transition_hashes[0] == transition_hashes[4])
	_assert(transition_hashes[0] != transition_hashes[1])
	_assert(transition_hashes[1] != transition_hashes[2])
	_assert(transition_hashes[2] != transition_hashes[3])

	var population_truth := _population_truth_fixture()
	var population_snapshot := JSON.stringify(population_truth)
	var population_a := Representation.build_population(population_truth, profile, SEED)
	var population_b := Representation.build_population(population_truth, profile, SEED)
	var tampered_population := population_truth.duplicate(true)
	tampered_population["canonical_organism_count"] = POPULATION_COUNT - 1
	_assert(not bool(Representation.build_population(tampered_population, profile, SEED).get("success", false)))
	_assert(bool(population_a.get("success", false)))
	_assert(bool(Representation.validate_artifact(population_a).get("success", false)))
	_assert(String(population_a["tier"]) == Representation.TIER_4_POPULATION_ONLY)
	_assert(String(population_a["representation_hash"]) == String(population_b["representation_hash"]))
	_assert(String(population_a["source_ecology_identity"]) == String(population_truth["population_truth_hash"]))
	_assert(String(population_a["source_graph_hash"]).is_empty())
	_assert(String(population_a["render_description_hash"]).is_empty())
	_assert(int(population_a["canonical_organism_count"]) == POPULATION_COUNT)
	_assert(int(population_a["materialized_growth_graph_count"]) == 0)
	_assert(int(population_a["metrics"]["materialized_growth_graph_count"]) == 0)
	_assert(int(population_a["visual_sample_count"]) <= Representation.MAX_POPULATION_VISUAL_INSTANCES)
	_assert(int(population_a["visual_sample_count"]) < POPULATION_COUNT)
	_assert(not population_a.has("individual_growth_graphs"))
	_assert(not population_a.has("canonical_organisms"))
	_assert(JSON.stringify(population_truth) == population_snapshot)
	var population_visual := FarMaterializer.build(population_a)
	var population_visual_again := FarMaterializer.build(population_b)
	_assert(bool(population_visual["success"]))
	_assert(population_visual["mesh"] == null)
	_assert(population_visual["multimesh"] is MultiMesh)
	_assert(int(population_visual["instance_count"]) == int(population_a["visual_sample_count"]))
	_assert(not bool(population_visual["individual_node_required"]))
	_assert(String(population_visual["population_layout_hash"]).length() == 64)
	_assert(String(population_visual["materialization_hash"]) == String(population_visual_again["materialization_hash"]))
	_assert(JSON.stringify(population_truth) == population_snapshot)

	var near_population_view := {
		"canonical_organism_count": int(population_truth["canonical_organism_count"]),
		"materialized_growth_graph_count": 1,
		"individual_representation_hash": String(full["representation_hash"]),
	}
	_assert(int(near_population_view["canonical_organism_count"]) == int(population_a["canonical_organism_count"]))
	_assert(int(near_population_view["materialized_growth_graph_count"]) > int(population_a["materialized_growth_graph_count"]))
	_assert(JSON.stringify(population_truth) == population_snapshot)

	var metrics := _performance_metrics(description, profile, ecology_identity, population_truth)
	_assert(int(metrics[Representation.TIER_0_FULL]["geometry_primitive_count"]) > int(metrics[Representation.TIER_1_REDUCED]["geometry_primitive_count"]))
	_assert(int(metrics[Representation.TIER_1_REDUCED]["geometry_primitive_count"]) > int(metrics[Representation.TIER_2_CANOPY]["geometry_primitive_count"]))
	_assert(int(metrics[Representation.TIER_4_POPULATION_ONLY]["materialized_growth_graph_count"]) == 0)
	_assert(JSON.stringify(truth) == truth_snapshot)
	_assert(JSON.stringify(population_truth) == population_snapshot)

	var matrix_hash := _matrix_hash(artifacts, population_a)
	print("ECO.PH5-S3 strict_matrix_hash=%s" % matrix_hash)
	print("ECO.PH5-S3 population canonical=%d visual_samples=%d materialized_growth_graphs=%d layout=%s" % [int(population_a["canonical_organism_count"]), int(population_a["visual_sample_count"]), int(population_a["materialized_growth_graph_count"]), String(population_visual["population_layout_hash"])])
	print("ECO.PH5-S3 Truth-Invariance + Aggregate Population: PASS (%d assertions)" % assertions)
	quit(0)

func _truth_fixture(source_reference: Dictionary) -> Dictionary:
	var genome := Genome.create_default()
	var traits := Traits.create_default()
	var environment: Dictionary = SourceProbes.make_environment_samples()["REFERENCE"]
	var resource_state := ResourceModel.evaluate(environment, genome)
	var envelope := Contract.create_seed_envelope(genome, traits, SourceProbes.PARENT_LINEAGE, SourceProbes.REPRODUCTION_EVENT, SourceProbes.SEED_INDEX)
	var lifecycle_state := Contract.create_initial_development_state(envelope)
	return {
		"genome": genome,
		"resource_state": resource_state,
		"lifecycle_state": lifecycle_state,
		"selection_relevant_phenotype_hash": String(source_reference["phenotype_hash"]),
		"seed_reproduction_state": envelope,
		"growth_graph": Dictionary(source_reference["growth_graph"]).duplicate(true),
	}

func _population_truth_fixture() -> Dictionary:
	var truth := {
		"schema": Representation.POPULATION_SOURCE_SCHEMA,
		"patch_id": "eco/ph5-s3/far-patch-001",
		"canonical_organism_count": POPULATION_COUNT,
		"center": [3200.0, 0.0, -1800.0],
		"radius_m": 480.0,
		"mean_height_m": 2.8,
		"mean_canopy_radius_m": 0.9,
		"foliage_mass_projection": 186000.0,
		"biomass_projection_kg": 742000.0,
		"density_per_m2": 1.381553,
	}
	truth["population_truth_hash"] = Representation.compute_population_truth_hash(truth)
	return truth

func _performance_metrics(description: Dictionary, profile: Dictionary, ecology_identity: String, population_truth: Dictionary) -> Dictionary:
	var result := {}
	for tier in Representation.INDIVIDUAL_TIERS:
		var started := Time.get_ticks_usec()
		var artifact := {}
		for index in range(20): artifact = Representation.build_individual(description, tier, ecology_identity, SEED, profile)
		var elapsed := Time.get_ticks_usec() - started
		var metrics: Dictionary = Dictionary(artifact["metrics"]).duplicate(true)
		metrics["generation_time_us_mean_20"] = float(elapsed) / 20.0
		result[tier] = metrics
		print("ECO.PH5-S3 metric %s objects=%d primitives=%d instances=%d memory_estimate=%dB growth_graphs=%d generation_mean=%.2fus" % [tier, int(metrics["representation_object_count"]), int(metrics["geometry_primitive_count"]), int(metrics["instance_count"]), int(metrics["estimated_memory_bytes"]), int(metrics["materialized_growth_graph_count"]), float(metrics["generation_time_us_mean_20"])])
	var started_population := Time.get_ticks_usec()
	var population_artifact := {}
	for index in range(20): population_artifact = Representation.build_population(population_truth, profile, SEED)
	var elapsed_population := Time.get_ticks_usec() - started_population
	var population_metrics: Dictionary = Dictionary(population_artifact["metrics"]).duplicate(true)
	population_metrics["generation_time_us_mean_20"] = float(elapsed_population) / 20.0
	result[Representation.TIER_4_POPULATION_ONLY] = population_metrics
	print("ECO.PH5-S3 metric %s objects=%d primitives=%d instances=%d memory_estimate=%dB growth_graphs=%d generation_mean=%.2fus" % [Representation.TIER_4_POPULATION_ONLY, int(population_metrics["representation_object_count"]), int(population_metrics["geometry_primitive_count"]), int(population_metrics["instance_count"]), int(population_metrics["estimated_memory_bytes"]), int(population_metrics["materialized_growth_graph_count"]), float(population_metrics["generation_time_us_mean_20"])])
	return result

func _matrix_hash(artifacts: Dictionary, population_artifact: Dictionary) -> String:
	var tokens := PackedStringArray()
	for tier in Representation.INDIVIDUAL_TIERS:
		tokens.append("%s|%s" % [tier, String(artifacts[tier]["representation_hash"])])
	tokens.append("%s|%s" % [Representation.TIER_4_POPULATION_ONLY, String(population_artifact["representation_hash"])])
	return "\n".join(tokens).sha256_text()

func _assert(condition: bool) -> void:
	assert(condition)
	assertions += 1
