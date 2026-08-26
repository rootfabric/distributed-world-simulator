extends SceneTree

## ECO.EVO7 FFF2 - morphology evolution acceptance.
## Gates: G4 common mutation pool causality; G5 geometry divergence (numeric form);
## G13 single mutation authority. Research-only.

const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const ExtensionTraits = preload("res://scripts/research/ecology/plant_development_traits_extension_evo7_v1.gd")
const Kernel = preload("res://scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd")
const LineageExtension = preload("res://scripts/research/ecology/plant_mutation_lineage_extension_evo7_v1.gd")
const Bridge = preload("res://scripts/research/ecology/evo7_morphology_evolution_bridge_v1.gd")
const Fixture = preload("res://scripts/research/ecology/synthetic_environment_fixture_v1.gd")

const SEED := 20260823

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_policy_contract()
	_bundle_and_single_authority()
	var result := Bridge.run_all(SEED, 24, 18, 4)
	_g4_common_pool_causality(result)
	_g5_geometry_divergence(result)
	_heritable_shift_and_guards(result)
	_source_boundaries()
	_finish()

func _policy_contract() -> void:
	var policy := LineageExtension.default_policy()
	_check(bool(LineageExtension.validate_policy(policy).get("success", false)), "default evo7 policy validates")
	var policy_hash := LineageExtension.policy_hash(policy)
	_check(policy_hash.length() == 64, "evo7 policy hash sha256-length")
	_check(policy_hash == LineageExtension.policy_hash(LineageExtension.default_policy()), "evo7 policy hash deterministic")
	_check(LineageExtension.AXIS_NAMES == [
		"ph0:max_height_m", "ph0:crown_spread_m", "ph0:apical_dominance",
		"ext:foliage_density", "ext:leaf_economics_proxy", "ext:structural_investment",
		"ext:root_spread_m", "ext:root_shoot_ratio",
	], "canonical morphology axis order frozen (8 axes)")
	for axis in LineageExtension.AXES:
		var source: Dictionary = Traits.BOUNDS if String(axis["layer"]) == "ph0" else ExtensionTraits.BOUNDS
		_check(source.has(String(axis["name"])), "%s axis bound exists in its layer contract" % axis["name"])

	var no_genome := LineageExtension.default_policy()
	no_genome.erase("genome_policy")
	_check(not bool(LineageExtension.validate_policy(no_genome).get("success", false)), "policy without genome policy rejected")
	var bad_probability := LineageExtension.default_policy()
	bad_probability["morphology_probability"] = 1.5
	_check(not bool(LineageExtension.validate_policy(bad_probability).get("success", false)), "out-of-range morphology probability rejected")
	var negative_step := LineageExtension.default_policy()
	negative_step["step_ext_foliage_density"] = -0.1
	_check(not bool(LineageExtension.validate_policy(negative_step).get("success", false)), "negative morphology step rejected")
	var huge_step := LineageExtension.default_policy()
	huge_step["step_ext_root_shoot_ratio"] = 5.0
	_check(not bool(LineageExtension.validate_policy(huge_step).get("success", false)), "step beyond axis range rejected")

func _bundle_and_single_authority() -> void:
	var ancestor := Bridge.default_ancestor_bundle(SEED)
	_check(not ancestor.is_empty(), "ancestor bundle created")
	_check(String(ancestor["bundle_checksum"]) == LineageExtension.bundle_checksum(
		ancestor["genome"], ancestor["dev_traits"], ancestor["ext_traits"],
		ancestor["lineage"], int(ancestor["individual_seed"])), "bundle checksum reproducible")

	var seed_a := ("EVO7-MORPHO|%d|%d|%d|%d" % [SEED, 1, 0, 0]).hash()
	var child_a := LineageExtension.reproduce_bundle(ancestor, seed_a, 0, LineageExtension.default_policy())
	var child_a_again := LineageExtension.reproduce_bundle(ancestor, seed_a, 0, LineageExtension.default_policy())
	_check(not child_a.is_empty(), "reproduce_bundle succeeds")
	_check(String(child_a["result_hash"]) == String(child_a_again["result_hash"]), "reproduction deterministic for same seed")
	_check(int(child_a["morphology_events"].size()) == 8, "morphology event per canonical axis")
	_check(String(child_a["bundle"]["lineage"]["parent_individual_id"]) == String(ancestor["lineage"]["individual_id"]), "lineage chain stays on the v1 record")
	_check(int(child_a["bundle"]["lineage"]["generation"]) == int(ancestor["lineage"]["generation"]) + 1, "generation advances once per reproduction")
	_check(String(child_a["bundle"]["genome"]["checksum"]) == String(child_a["bundle"]["lineage"]["genome_checksum"]), "child genome bound to v1 lineage record")
	var child_b := LineageExtension.reproduce_bundle(ancestor, seed_a + 1, 1, LineageExtension.default_policy())
	_check(String(child_b["result_hash"]) != String(child_a["result_hash"]), "different seeds give different reproduction results")

	var tampered: Dictionary = ancestor.duplicate(true)
	tampered["ext_traits"]["foliage_density"] = 0.4
	var tampered_child := LineageExtension.reproduce_bundle(tampered, seed_a, 0, LineageExtension.default_policy())
	_check(tampered_child.is_empty(), "tampered bundle fails closed (checksum gate)")

	var mutable_expected := ["water_preference", "root_depth_m", "growth_rate", "shade_tolerance", "seed_dispersal_distance_m"]
	_check(Kernel.MUTABLE_TRAITS.size() == 5 and String(Kernel.MUTABLE_TRAITS[0]) == mutable_expected[0], "v1 kernel mutable traits intact (genome authority unchanged)")

func _g4_common_pool_causality(result: Dictionary) -> void:
	_check(not result.is_empty(), "bridge run succeeds")
	_check(String(result["common_first_candidate_pool_hash"]).length() == 64, "G4: generation-one candidate pool hash present")
	_check(int(result["distinct_final_population_pairs"]) >= 8, "G4: final selected populations differ across environments (pairs >= 8 of 10)")
	var repeat := Bridge.run_all(SEED, 24, 18, 4)
	_check(String(repeat["result_hash"]) == String(result["result_hash"]), "G4: evolution deterministic replay (identical result hash)")
	var other_seed := Bridge.run_all(SEED + 1, 24, 18, 4)
	_check(String(other_seed["result_hash"]) != String(result["result_hash"]), "G4: different lineage seed changes evolution")

func _g5_geometry_divergence(result: Dictionary) -> void:
	_check(int(result["geometry_distinct_pairs"]) >= 8, "G5: geometry-distinct scenario pairs >= 8 of 10")
	_check(int(result["scenarios_distinct_from_baseline"]) >= 3, "G5: >= 3 scenarios distinct from mesic baseline")

	var wet: Dictionary = result["scenarios"]["wet_lowland"]["mean_features"]
	var sunny: Dictionary = result["scenarios"]["sunny_slope"]["mean_features"]
	var shaded: Dictionary = result["scenarios"]["shaded_slope"]["mean_features"]
	var dry: Dictionary = result["scenarios"]["dry_ridge"]["mean_features"]
	var plateau: Dictionary = result["scenarios"]["plateau"]["mean_features"]

	_check(float(dry["realized_root_depth_m"]) > 1.5 * float(wet["realized_root_depth_m"]), "G5 direction: drought evolves deeper roots than wet")
	_check(float(dry["realized_root_depth_m"]) > float(plateau["realized_root_depth_m"]), "G5 direction: root depth follows moisture gradient (dry > mesic)")
	_check(float(sunny["realized_crown_density"]) > float(shaded["realized_crown_density"]) + 0.2, "G5 direction: light gradient evolves crown density (sunny > shaded)")
	_check(float(shaded["realized_height_m"]) < 1.0, "G5 direction: shade cannot pay for stature (dwarf understory)")
	_check(float(wet["realized_height_m"]) > 2.0, "G5 direction: productive wet environment keeps stature")
	_check(float(result["scenarios"]["sunny_slope"]["mean_fitness"]) > 0.0, "G5: sunny population reaches positive net balance")
	_check(float(result["scenarios"]["dry_ridge"]["mean_fitness"]) > 0.0, "G5: dry population reaches positive net balance via root strategy")

func _heritable_shift_and_guards(result: Dictionary) -> void:
	var ancestor := Bridge.default_ancestor_bundle(SEED)
	var ancestor_before := String(ancestor["bundle_checksum"])
	var env_dry := Fixture.control_point("dry_ridge", SEED)
	var env_wet := Fixture.control_point("wet_lowland", SEED)
	var ancestor_dry := Bridge._evaluate(ancestor, env_dry)
	var ancestor_wet := Bridge._evaluate(ancestor, env_wet)
	_check(String(ancestor["bundle_checksum"]) == ancestor_before, "ancestor bundle unchanged by evaluation")

	var dry: Dictionary = result["scenarios"]["dry_ridge"]["mean_features"]
	var wet: Dictionary = result["scenarios"]["wet_lowland"]["mean_features"]
	_check(float(dry["realized_root_depth_m"]) > 2.0 * float(ancestor_dry["features"]["realized_root_depth_m"]), "evolution heritably doubles dry root depth vs ancestor")
	_check(float(wet["realized_crown_density"]) > float(ancestor_wet["features"]["realized_crown_density"]), "evolution heritably raises wet crown density vs ancestor")
	_check(float(dry["realized_root_depth_m"]) <= 20.0 and float(wet["realized_crown_density"]) <= 1.0, "evolved means stay inside declared bounds")

func _source_boundaries() -> void:
	var extension_source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_mutation_lineage_extension_evo7_v1.gd")
	var bridge_source := FileAccess.get_file_as_string("res://scripts/research/ecology/evo7_morphology_evolution_bridge_v1.gd")
	for source: String in [extension_source, bridge_source]:
		var lowered: String = source.to_lower()
		for forbidden in ["randf", "randi(", "randomize", "randomnumbergenerator"]:
			_check(not lowered.contains(forbidden), "no platform RNG (%s) in evolution layer" % forbidden)
	_check(extension_source.contains("Kernel.reproduce"), "genome heredity delegated to the v1 kernel")
	_check(extension_source.contains("plant_mutation_lineage_kernel_v1.gd"), "extension preloads the single kernel")
	var kernel_source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd")
	_check(kernel_source.contains("\"water_preference\",\n\t\"root_depth_m\",\n\t\"growth_rate\",\n\t\"shade_tolerance\",\n\t\"seed_dispersal_distance_m\","), "kernel MUTABLE_TRAITS block untouched")

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 FFF2 Morphology Evolution: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 FFF2 FAIL: %s" % failure)
	print("ECO.EVO7 FFF2 Morphology Evolution: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
