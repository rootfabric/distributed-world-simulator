extends SceneTree

## ECO.EVO7 FFF0 - contract mapping acceptance.
## Machine-fixates the FFF0 audit facts (docs/plans/ECO_EVO7_FFF0_CONTRACT_MAPPING_RU.md):
## reuse surfaces stay intact, semantic gaps stay real, single mutation authority holds.
## Research-only; asserts no production/runtime authority is touched.

const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const Kernel = preload("res://scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd")
const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const EnvSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const RendererProfile = preload("res://scripts/research/ecology/plant_renderer_profile_v1.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_m1_genome_v1_frozen()
	_m2_single_mutation_authority()
	_m3_ph0_traits_intact()
	_m4_plasticity_surface_exists()
	_m5_environment_channel_gaps()
	_m6_bridge_delegates_kernel()
	_m7_structural_cost_without_axis()
	_m8_allocation_placeholder_not_heritable()
	_m9_render_boundary_derived_only()
	_m10_determinism_smoke()
	_finish()

## M1: PlantGenome v1 schema is frozen (13 exact fields, exact-count validation).
func _m1_genome_v1_frozen() -> void:
	var expected := [
		"schema", "version", "genome_id", "height_m", "growth_rate", "root_depth_m",
		"water_preference", "water_tolerance_width", "shade_tolerance", "seed_count",
		"seed_dispersal_distance_m", "lifespan_years", "checksum",
	]
	_check(Genome.FIELD_NAMES.size() == expected.size(), "genome v1 field count is thirteen")
	for i in expected.size():
		_check(String(Genome.FIELD_NAMES[i]) == expected[i], "genome field %d is %s" % [i, expected[i]])
	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_genome_v1.gd")
	_check(source.contains("keys().size() != FIELD_NAMES.size()"), "genome validate enforces exact field count (v1 not extensible in place)")
	_check(source.contains("\"distributed_world_simulator.ecology.plant_genome.v1\""), "genome schema id unchanged")

## M2: kernel owns exactly the five ecological mutable traits; morphology stays outside evolution (FFF0-A gap).
func _m2_single_mutation_authority() -> void:
	var expected := ["water_preference", "root_depth_m", "growth_rate", "shade_tolerance", "seed_dispersal_distance_m"]
	_check(Kernel.MUTABLE_TRAITS.size() == expected.size(), "kernel mutates exactly five traits")
	for i in expected.size():
		_check(String(Kernel.MUTABLE_TRAITS[i]) == expected[i], "mutable trait %d is %s" % [i, expected[i]])
	for morphological in ["height_m", "max_height_m", "crown_spread_m", "apical_dominance", "foliage_density"]:
		_check(not Kernel.MUTABLE_TRAITS.has(morphological), "%s is outside mutation authority today" % morphological)
	var kernel_source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd")
	_check(kernel_source.contains("static func reproduce"), "kernel exposes reproduce()")
	_check(kernel_source.contains("static func policy_hash"), "kernel exposes policy_hash()")
	_check(kernel_source.contains("static func validate_policy"), "kernel exposes validate_policy()")
	_check(kernel_source.contains("mutation_probability"), "kernel policy carries mutation_probability")

## M3: PH0 development trait contract intact (eight traits + bounds).
func _m3_ph0_traits_intact() -> void:
	var expected := [
		"max_height_m", "internode_length_m", "apical_dominance", "branch_probability",
		"branch_angle_deg", "branch_length_ratio", "branching_depth", "crown_spread_m",
	]
	_check(Traits.TRAIT_NAMES.size() == expected.size(), "PH0 trait count is eight")
	for i in expected.size():
		_check(String(Traits.TRAIT_NAMES[i]) == expected[i], "PH0 trait %d is %s" % [i, expected[i]])
	for trait_name in expected:
		_check(Traits.BOUNDS.has(trait_name), "bounds registered for %s" % trait_name)
		var bounds: Array = Traits.BOUNDS[trait_name]
		_check(bounds.size() == 2, "%s bounds pair present" % trait_name)

## M4: environment-coupled realization surface exists (plasticity without genome write).
func _m4_plasticity_surface_exists() -> void:
	var ph2_source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_environment_coupled_development_v1.gd")
	_check(ph2_source.contains("static func realize"), "PH2 realize surface exists")
	_check(ph2_source.contains("realized_development_traits"), "PH2 emits realized development traits")
	_check(ph2_source.contains("phenotype_hash"), "PH2 seals phenotype hash")
	_check(ph2_source.contains("growth_graph"), "PH2 embeds growth graph")
	var profile_source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_development_plasticity_profile_v1.gd")
	for coefficient in ["shade_elongation_strength", "drought_size_suppression", "light_branching_strength", "nutrient_growth_strength", "flood_growth_suppression"]:
		_check(profile_source.contains(coefficient), "plasticity coefficient %s present" % coefficient)

## M5: environment channels lack texture/litter/transpiration (code-level gap proof).
func _m5_environment_channel_gaps() -> void:
	var present := ["temperature_c", "soil_moisture", "sunlight", "nutrients", "flood_frequency"]
	for field_name in present:
		_check(EnvSample.FIELD_NAMES.has(field_name), "environment channel %s exists" % field_name)
	for absent in ["soil_texture", "sand_fraction", "litter", "organic_matter", "transpiration", "understory_light"]:
		_check(not EnvSample.FIELD_NAMES.has(absent), "environment channel %s absent (FFF0 gap)" % absent)

## M6: EVO6-WATER bridge delegates to the single kernel (G13 preview).
func _m6_bridge_delegates_kernel() -> void:
	var bridge_source := FileAccess.get_file_as_string("res://scripts/research/ecology/evo6_water_evolution_bridge_v1.gd")
	_check(bridge_source.contains("plant_mutation_lineage_kernel_v1.gd"), "water bridge preloads the accepted kernel")
	_check(bridge_source.contains("MutationKernel.reproduce"), "water bridge reproduces only through kernel")
	_check(bridge_source.contains("No second mutation path"), "single-authority rule stated in bridge header")
	_check(not bridge_source.contains("MUTABLE_TRAITS"), "bridge defines no own mutable trait set")

## M7: structural cost side exists while heritable axis does not (gap fixation).
func _m7_structural_cost_without_axis() -> void:
	var resource_source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_resource_model_v1.gd")
	_check(resource_source.contains("structural_cost"), "resource model prices structure (cost-side proxy)")
	_check(resource_source.contains("maintenance_cost"), "resource model prices maintenance")
	var traits_source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_development_traits_v1.gd")
	for axis in ["wood_density", "leaf_economics", "sla", "root_spread", "foliage_density", "structural_investment"]:
		_check(not traits_source.contains(axis), "PH0 traits contain no %s axis yet" % axis)

## M8: allocation placeholders exist in state but are not heritable (gap fixation).
func _m8_allocation_placeholder_not_heritable() -> void:
	var genome := Genome.create_default()
	var traits := Traits.create_default()
	var envelope := Contract.create_seed_envelope(genome, traits, "lineage/fff0", "repro/fff0", 0, 1.25)
	_check(not envelope.is_empty(), "seed envelope created for allocation probe")
	var state := Contract.create_initial_development_state(envelope)
	if state.is_empty():
		_check(false, "development state created")
	else:
		_check(state.has("root_allocation"), "development state carries root_allocation placeholder")
		_check(state.has("shoot_allocation"), "development state carries shoot_allocation placeholder")
		_check(is_equal_approx(float(state.get("root_allocation", 1.0)), 0.5) and is_equal_approx(float(state.get("shoot_allocation", 1.0)), 0.5), "allocation values remain hard-coded placeholders (no heritable axis)")
	_check(not Kernel.MUTABLE_TRAITS.has("root_allocation"), "root_allocation outside mutation authority")
	_check(not Kernel.MUTABLE_TRAITS.has("shoot_allocation"), "shoot_allocation outside mutation authority")

## M9: render pipeline is derived-only (G15 boundary preview).
func _m9_render_boundary_derived_only() -> void:
	_check(RendererProfile.PROFILE_ORDER.size() == 6, "renderer profile order has six profiles")
	var expected_profiles := ["DEBUG_SKELETON", "BRANCH_TUBES", "BRANCH_LEAF_INSTANCED", "CANOPY_APPROXIMATION", "FULL_PROCEDURAL", "IMPOSTOR_BILLBOARD"]
	for i in expected_profiles.size():
		_check(String(RendererProfile.PROFILE_ORDER[i]) == expected_profiles[i], "profile %d is %s" % [i, expected_profiles[i]])
	var render_source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_render_description_v1.gd")
	_check(render_source.contains("static func build"), "render description builds from growth graph")
	_check(not render_source.contains("plant_genome_v1.gd"), "render description does not depend on genome truth")
	_check(not render_source.contains("MutationKernel"), "render pipeline has no mutation access")
	var multiscale_source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_multiscale_representation_v1.gd")
	_check(multiscale_source.contains("ecological_truth_hash"), "multiscale keeps ecological truth hash separate from presentation")

## M10: determinism smoke over reused checksum/seed surfaces (G1 foundation).
func _m10_determinism_smoke() -> void:
	var traits_a := Traits.create_default()
	var traits_b := Traits.create_default()
	_check(String(traits_a["checksum"]) == String(traits_b["checksum"]), "PH0 default traits checksum reproducible")
	_check(String(traits_a["checksum"]).length() == 64, "traits checksum sha256-length")
	var seed_a := Contract.derive_individual_seed("lineage/fff0", "repro/det", 0, "1.0.0")
	var seed_b := Contract.derive_individual_seed("lineage/fff0", "repro/det", 0, "1.0.0")
	var seed_c := Contract.derive_individual_seed("lineage/fff0", "repro/det", 1, "1.0.0")
	_check(seed_a == seed_b, "individual seed deterministic")
	_check(seed_a != seed_c, "seed index changes individual seed")
	var lineage_source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_lineage_record_v1.gd")
	_check(lineage_source.contains("static func create_ancestor"), "lineage ancestor path exists")
	_check(lineage_source.contains("static func create_descendant"), "lineage descent path exists")
	_check(lineage_source.contains("mutation_event_hash"), "lineage records mutation event hash")

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 FFF0 Contract Mapping: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 FFF0 FAIL: %s" % failure)
	print("ECO.EVO7 FFF0 Contract Mapping: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
