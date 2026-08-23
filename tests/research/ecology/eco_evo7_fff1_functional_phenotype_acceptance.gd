extends SceneTree

## ECO.EVO7 FFF1 - PlantFunctionalPhenotype R1 acceptance.
## Gates: G1 deterministic phenotype; G2 plasticity without Lamarckian write;
## G3 heritable morphology with declared couplings only.
## Research-only; the compiler must stay a derived read-only surface.

const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const Extension = preload("res://scripts/research/ecology/plant_development_traits_extension_evo7_v1.gd")
const Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const CoupledDevelopment = preload("res://scripts/research/ecology/plant_environment_coupled_development_v1.gd")
const FunctionalPhenotype = preload("res://scripts/research/ecology/plant_functional_phenotype_v1.gd")
const Kernel = preload("res://scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd")
const Fixture = preload("res://scripts/research/ecology/synthetic_environment_fixture_v1.gd")

const SEED := 20260823

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var genome := Genome.create_default()
	var traits := Traits.create_default()
	var ext := Extension.create_default()
	var env_wet := Fixture.control_point("wet_lowland", SEED)
	var base := _inputs(genome, traits, ext, env_wet)

	_g1_contract_shape_and_determinism(base)
	_g2_plasticity_without_lamarck(genome, traits, ext)
	_g3_declared_couplings(genome, traits, ext, env_wet)
	_fail_closed_and_edges(genome, traits, ext, env_wet)
	_source_boundaries()
	_finish()

func _inputs(genome: Dictionary, traits: Dictionary, ext: Dictionary, env: Dictionary, age := 1.0) -> Dictionary:
	var envelope := Contract.create_seed_envelope(genome, traits, "lineage/fff1", "repro/fff1", 0, 1.25)
	var ph2 := CoupledDevelopment.realize(envelope, traits, env)
	return {
		"genome": genome,
		"ph2_realized": ph2,
		"traits_extension": ext,
		"environment_sample": env,
		"age_fraction": age,
	}

## G1: same inputs -> byte-identical phenotype and phenotype_hash.
func _g1_contract_shape_and_determinism(base: Dictionary) -> void:
	var fp := FunctionalPhenotype.compile(base)
	_check(not fp.is_empty(), "default compile succeeds")
	_check(String(fp["schema"]) == FunctionalPhenotype.SCHEMA, "functional phenotype schema id")
	_check(String(fp["version"]) == FunctionalPhenotype.VERSION, "functional phenotype version")
	_check(bool(fp["derived_representation"]), "explicitly marked derived representation")
	for field_name in [
		"genome_hash", "environment_hash", "individual_seed", "age_fraction",
		"realized_height_m", "realized_crown_radius_m", "realized_crown_density",
		"leaf_area_index_proxy", "leaf_size_proxy", "leaf_conservative_strategy",
		"structural_investment", "realized_root_depth_m", "realized_root_spread_m",
		"root_shoot_ratio", "photosynthetic_gain_proxy", "maintenance_cost_proxy",
		"net_resource_proxy", "transpiration_demand_ppm", "shade_output_ppm",
		"litter_flux_ppm", "establishment_capacity", "phenotype_hash",
	]:
		_check(fp.has(field_name), "spec field present: %s" % field_name)
	for ratio in ["realized_crown_density", "leaf_size_proxy", "leaf_conservative_strategy", "structural_investment", "root_shoot_ratio", "establishment_capacity"]:
		_check(float(fp[ratio]) >= 0.0 and float(fp[ratio]) <= 1.0, "%s within [0..1]" % ratio)
	for ppm_field in ["transpiration_demand_ppm", "shade_output_ppm", "litter_flux_ppm"]:
		_check(typeof(fp[ppm_field]) == TYPE_INT and int(fp[ppm_field]) >= 0, "%s is nonnegative int ppm" % ppm_field)
	var hash_value := String(fp["phenotype_hash"])
	_check(hash_value.length() == 64, "phenotype_hash is sha256-length")
	_check(hash_value == FunctionalPhenotype.compute_phenotype_hash(fp), "phenotype_hash reproducible from payload")

	var fp_again := FunctionalPhenotype.compile(base)
	_check(String(fp_again["phenotype_hash"]) == hash_value, "G1: identical inputs give identical hash")
	var all_equal := true
	for key in fp.keys():
		if fp[key] != fp_again[key]:
			all_equal = false
	_check(all_equal, "G1: identical inputs give byte-identical payload")

	var reordered := {
		"age_fraction": base["age_fraction"],
		"environment_sample": base["environment_sample"],
		"traits_extension": base["traits_extension"],
		"ph2_realized": base["ph2_realized"],
		"genome": base["genome"],
	}
	var fp_reordered := FunctionalPhenotype.compile(reordered)
	_check(not fp_reordered.is_empty() and String(fp_reordered["phenotype_hash"]) == hash_value, "G1: input key order does not matter")

	var mid := FunctionalPhenotype.compile(_inputs(base["genome"], Traits.create_default(), Extension.create_default(), Fixture.control_point("wet_lowland", SEED), 0.5))
	_check(not mid.is_empty() and is_finite(float(mid["realized_height_m"])), "mid-age compile finite")
	_check(float(mid["realized_height_m"]) < float(fp["realized_height_m"]), "age curve monotone toward maturity")

## G2: one genome, wet vs dry -> different realized phenotype, untouched heredity.
func _g2_plasticity_without_lamarck(genome: Dictionary, traits: Dictionary, ext: Dictionary) -> void:
	var checksum_before := String(genome["checksum"])
	var mutable_before := str(Kernel.MUTABLE_TRAITS)
	var env_wet := Fixture.control_point("wet_lowland", SEED)
	var env_dry := Fixture.control_point("dry_ridge", SEED)
	var fp_wet := FunctionalPhenotype.compile(_inputs(genome, traits, ext, env_wet))
	var fp_dry := FunctionalPhenotype.compile(_inputs(genome, traits, ext, env_dry))
	_check(not fp_wet.is_empty() and not fp_dry.is_empty(), "wet/dry compiles succeed")
	_check(float(fp_dry["realized_height_m"]) < float(fp_wet["realized_height_m"]), "G2: drought suppresses realized height (plasticity)")
	_check(String(fp_wet["phenotype_hash"]) != String(fp_dry["phenotype_hash"]), "G2: environment changes realized phenotype hash")
	_check(String(fp_wet["genome_hash"]) == checksum_before and String(fp_dry["genome_hash"]) == checksum_before, "G2: genome checksum unchanged by environment")
	_check(str(Kernel.MUTABLE_TRAITS) == mutable_before, "G2: mutation authority untouched")
	var fp_source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_functional_phenotype_v1.gd").to_lower()
	for forbidden in ["mutation_lineage_kernel", "lineagerecord", "reproduce("]:
		_check(not fp_source.contains(forbidden), "functional phenotype never touches heredity path (%s)" % forbidden)

## G3: controlled single-trait changes move exactly the declared axes.
func _g3_declared_couplings(genome: Dictionary, traits: Dictionary, ext: Dictionary, env_wet: Dictionary) -> void:
	# Reference morphology for functional probes: the default deterministic seed
	# grows a branchless pole, so functional crown axes are probed on a branched
	# variant (house pattern: controlled trait probes).
	var ref_traits := Traits.with_trait(Traits.with_trait(traits, "branch_probability", 0.9, "/ref"), "branching_depth", 4, "/ref")
	var ref_inputs := _inputs(genome, ref_traits, ext, env_wet)
	var ref_metrics: Dictionary = ref_inputs["ph2_realized"]["growth_graph"]["metrics"]
	_check(int(ref_metrics["lateral_segment_count"]) > 0, "reference morphology carries lateral segments")
	_check(float(ref_metrics["horizontal_radius_m"]) > 0.0, "reference morphology has crown radius")
	var base := FunctionalPhenotype.compile(ref_inputs)
	_check(float(base["leaf_area_index_proxy"]) > 0.0, "reference morphology bears leaf area")

	# stature potential up -> height/maintenance/shade up, root side untouched
	var tall_traits := Traits.with_trait(ref_traits, "max_height_m", 8.0, "/tall")
	var tall := FunctionalPhenotype.compile(_inputs(genome, tall_traits, ext, env_wet))
	_check(float(tall["realized_height_m"]) > float(base["realized_height_m"]) * 1.5, "G3 stature: realized height follows potential")
	_check(float(tall["maintenance_cost_proxy"]) > float(base["maintenance_cost_proxy"]), "G3 stature: structural cost rises with height")
	_check(int(tall["shade_output_ppm"]) > int(base["shade_output_ppm"]), "G3 stature: shade output rises with height")
	_check(float(tall["realized_root_depth_m"]) == float(base["realized_root_depth_m"]), "G3 stature: root depth beyond declared coupling unchanged")
	_check(float(tall["realized_root_spread_m"]) == float(base["realized_root_spread_m"]), "G3 stature: root spread beyond declared coupling unchanged")

	# crown density potential up -> density/leaf-area/fluxes up, geometry height bit-identical
	var dense_ext := Extension.with_trait(ext, "foliage_density", 0.9, "/dense")
	var dense := FunctionalPhenotype.compile(_inputs(genome, ref_traits, dense_ext, env_wet))
	_check(float(dense["realized_crown_density"]) > float(base["realized_crown_density"]), "G3 crown density: axis follows potential")
	_check(float(dense["leaf_area_index_proxy"]) > float(base["leaf_area_index_proxy"]), "G3 crown density: LAI proxy rises")
	_check(int(dense["transpiration_demand_ppm"]) > int(base["transpiration_demand_ppm"]), "G3 crown density: water demand rises")
	_check(int(dense["shade_output_ppm"]) > int(base["shade_output_ppm"]), "G3 crown density: shade rises")
	_check(float(dense["realized_height_m"]) == float(base["realized_height_m"]), "G3 crown density: height bit-identical (declared independence)")
	_check(float(dense["realized_root_depth_m"]) == float(base["realized_root_depth_m"]), "G3 crown density: root side unchanged")

	# fast leaf economics -> gain/litter up, conservative strategy exact echo
	var fast_ext := Extension.with_trait(ext, "leaf_economics_proxy", 0.95, "/fast")
	var fast := FunctionalPhenotype.compile(_inputs(genome, ref_traits, fast_ext, env_wet))
	_check(float(fast["photosynthetic_gain_proxy"]) > float(base["photosynthetic_gain_proxy"]), "G3 leaf economics: acquisitive leaves raise gain")
	_check(float(fast["leaf_conservative_strategy"]) == _snap(0.05), "G3 leaf economics: conservative strategy exact complement")
	_check(int(fast["litter_flux_ppm"]) > int(base["litter_flux_ppm"]), "G3 leaf economics: turnover raises litter flux")
	_check(float(fast["realized_height_m"]) == float(base["realized_height_m"]), "G3 leaf economics: height unchanged")

	# structural investment -> cost side only in R1 (survival coupling deferred, declared)
	var stiff_ext := Extension.with_trait(ext, "structural_investment", 0.9, "/stiff")
	var stiff := FunctionalPhenotype.compile(_inputs(genome, ref_traits, stiff_ext, env_wet))
	_check(float(stiff["maintenance_cost_proxy"]) > float(base["maintenance_cost_proxy"]), "G3 structural: wood investment raises maintenance")
	_check(float(stiff["net_resource_proxy"]) < float(base["net_resource_proxy"]), "G3 structural: net balance drops (cost of structure)")
	_check(float(stiff["structural_investment"]) == 0.9, "G3 structural: axis echoes potential")
	_check(float(stiff["realized_height_m"]) == float(base["realized_height_m"]), "G3 structural: R1 has no growth-rate coupling (declared)")

	# root spread -> spread/cost up, shoot geometry untouched
	var wide_ext := Extension.with_trait(ext, "root_spread_m", 6.0, "/wide")
	var wide := FunctionalPhenotype.compile(_inputs(genome, ref_traits, wide_ext, env_wet))
	_check(float(wide["realized_root_spread_m"]) > float(base["realized_root_spread_m"]), "G3 root spread: axis follows potential")
	_check(float(wide["maintenance_cost_proxy"]) > float(base["maintenance_cost_proxy"]), "G3 root spread: construction cost rises")
	_check(float(wide["realized_height_m"]) == float(base["realized_height_m"]), "G3 root spread: shoot geometry unchanged")

	# allocation shift -> root factors up, shoot factors down, geometry untouched
	var rooted_ext := Extension.with_trait(ext, "root_shoot_ratio", 0.8, "/rooted")
	var rooted := FunctionalPhenotype.compile(_inputs(genome, ref_traits, rooted_ext, env_wet))
	_check(float(rooted["realized_root_depth_m"]) > float(base["realized_root_depth_m"]), "G3 allocation: root depth scales with root share")
	_check(float(rooted["realized_root_spread_m"]) > float(base["realized_root_spread_m"]), "G3 allocation: root spread scales with root share")
	_check(float(rooted["photosynthetic_gain_proxy"]) < float(base["photosynthetic_gain_proxy"]), "G3 allocation: shoot share pays on gain")
	_check(float(rooted["root_shoot_ratio"]) == 0.8, "G3 allocation: ratio echoes potential")
	_check(float(rooted["realized_height_m"]) == float(base["realized_height_m"]), "G3 allocation: R1 keeps geometry independent of allocation (declared)")

	# deep genome roots pay off specifically under drought
	var deep_genome := Genome.with_root_depth(genome, 3.0, "/deep")
	var shallow_dry := FunctionalPhenotype.compile(_inputs(genome, ref_traits, ext, Fixture.control_point("dry_ridge", SEED)))
	var deep_dry := FunctionalPhenotype.compile(_inputs(deep_genome, ref_traits, ext, Fixture.control_point("dry_ridge", SEED)))
	_check(float(deep_dry["realized_root_depth_m"]) > float(shallow_dry["realized_root_depth_m"]), "G3 roots: realized depth follows genome potential")
	_check(float(deep_dry["photosynthetic_gain_proxy"]) > float(shallow_dry["photosynthetic_gain_proxy"]), "G3 roots: deep roots access more water under drought")
	_check(String(deep_genome["checksum"]) != String(genome["checksum"]), "G3 roots: heritable change goes through accepted genome contract")

	# inputs are never mutated by compile
	_check(String(traits["checksum"]) == String(Traits.compute_checksum(Traits.create_default())), "compile does not mutate PH0 traits input")

## Fail-closed behaviour and boundary ages.
func _fail_closed_and_edges(genome: Dictionary, traits: Dictionary, ext: Dictionary, env_wet: Dictionary) -> void:
	var tampered := genome.duplicate(true)
	tampered["checksum"] = "0"
	_check(FunctionalPhenotype.compile(_inputs(tampered, traits, ext, env_wet)).is_empty(), "tampered genome fails closed")

	var bad_ext := ext.duplicate(true)
	bad_ext["foliage_density"] = 5.0
	_check(FunctionalPhenotype.compile(_inputs(genome, traits, bad_ext, env_wet)).is_empty(), "out-of-range extension fails closed")

	var wrong_ph2 := _inputs(genome, traits, ext, env_wet)
	wrong_ph2["ph2_realized"] = {"schema": "not/the/right/schema"}
	_check(FunctionalPhenotype.compile(wrong_ph2).is_empty(), "foreign ph2 payload fails closed")

	var mismatched_env := _inputs(genome, traits, ext, Fixture.control_point("plateau", SEED))
	mismatched_env["environment_sample"] = Fixture.control_point("dry_ridge", SEED)
	_check(FunctionalPhenotype.compile(mismatched_env).is_empty(), "ph2/environment checksum mismatch fails closed")

	var bad_age := _inputs(genome, traits, ext, env_wet)
	bad_age["age_fraction"] = 1.5
	_check(FunctionalPhenotype.compile(bad_age).is_empty(), "age_fraction above one fails closed")

	var seedling := FunctionalPhenotype.compile(_inputs(genome, traits, ext, env_wet, 0.0))
	_check(not seedling.is_empty() and float(seedling["realized_height_m"]) == 0.0, "age zero yields zero-height seedling")
	_check(int(seedling["transpiration_demand_ppm"]) == 0 and int(seedling["litter_flux_ppm"]) == 0, "age zero yields zero fluxes")
	var seedling_again := FunctionalPhenotype.compile(_inputs(genome, traits, ext, env_wet, 0.0))
	_check(String(seedling_again["phenotype_hash"]) == String(seedling["phenotype_hash"]), "seedling state deterministic")

## Source-boundary gates in the house style of the PH0 acceptance test.
func _source_boundaries() -> void:
	var fp_source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_functional_phenotype_v1.gd").to_lower()
	for forbidden in ["camera", "meshinstance", "multimesh", "network", "persistence", "plant_type", "rendererprofile"]:
		_check(not fp_source.contains(forbidden), "functional phenotype source excludes %s" % forbidden)
	_check(fp_source.contains("derived_representation"), "derived-only marker present in source")
	_check(fp_source.contains("coupleddevelopment.realize") or fp_source.contains("preload(\"res://scripts/research/ecology/plant_environment_coupled_development_v1.gd\")"), "compiler consumes accepted PH2 surface")
	var ext_source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_development_traits_extension_evo7_v1.gd").to_lower()
	for forbidden in ["camera", "mesh", "renderer", "authority", "network", "persistence"]:
		_check(not ext_source.contains(forbidden), "extension source excludes %s" % forbidden)

func _snap(value: float) -> float:
	return snappedf(value, 1e-9)

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 FFF1 PlantFunctionalPhenotype: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 FFF1 FAIL: %s" % failure)
	print("ECO.EVO7 FFF1 PlantFunctionalPhenotype: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
