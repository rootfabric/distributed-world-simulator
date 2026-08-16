extends SceneTree

const SCENE_PATH := "res://scenes/labs/ecology/eco_vis1_6_lineage_genome_field.tscn"
const VIS16_SCRIPT = preload("res://scripts/labs/ecology/eco_vis1_6_lineage_genome_field.gd")
const VIS16_BRIDGE = preload("res://scripts/labs/ecology/eco_vis1_6_lineage_genome_bridge.gd")
const EXPECTED_PLANTS := 53
const EXPECTED_BIOMASS_KG := 11.0
const PATCHES := ["A", "B", "C"]

var _assertions := 0
var _failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var alpha_baseline := VIS16_BRIDGE.create_population_baseline_genome("alpha")
	var beta_baseline := VIS16_BRIDGE.create_population_baseline_genome("beta")
	_expect(not alpha_baseline.is_empty() and not beta_baseline.is_empty(), "population lab baselines exist")
	_expect(String(alpha_baseline.get("checksum", "")) != String(beta_baseline.get("checksum", "")), "alpha/beta lab baselines differ")

	var packed := load(SCENE_PATH) as PackedScene
	_expect(packed != null, "VIS1.6 scene loads")
	if packed == null:
		_finish(); return
	var lab := packed.instantiate() as Node3D
	_expect(lab != null, "VIS1.6 scene instantiates")
	if lab == null:
		_finish(); return
	_expect(lab.get_script() == VIS16_SCRIPT, "VIS1.6 script is attached")
	if lab.get_script() != VIS16_SCRIPT:
		lab.free(); _finish(); return
	get_root().add_child(lab)
	await process_frame
	await process_frame
	print("ECO.VIS1.6 smoke progress: scene_ready")

	var snapshot_before := lab.call("get_spatial_snapshot") as Dictionary
	_expect(int(snapshot_before.get("step_index", -1)) == 5, "canonical VIS1.2 frame remains 5")
	_expect(absf(float(snapshot_before.get("total_final_biomass_kg", 0.0)) - EXPECTED_BIOMASS_KG) <= 0.000000001, "canonical biomass remains 11kg")

	var summary := lab.call("get_population_field_summary") as Dictionary
	_expect(String(summary.get("stage", "")) == "ECO.VIS1.6", "summary reports VIS1.6")
	_expect(String(summary.get("lineage_mode", "")) == "LAB_DERIVED_LINEAGE_GENOME_LOCAL_ENVIRONMENT", "lineage/genome mode active")
	_expect(bool(summary.get("lab_lineage_field", false)), "lineage field explicitly lab-derived")
	_expect(not bool(summary.get("canonical_genome_truth", true)), "canonical genome truth remains off")
	_expect(String(summary.get("profile_id", "")) == "BRANCH_LEAF_INSTANCED", "PH5 profile preserved")
	_expect(int(summary.get("visual_instance_count", 0)) == EXPECTED_PLANTS, "53 representative plants survive")
	_expect(int(summary.get("lineage_instance_count", 0)) == EXPECTED_PLANTS, "all representatives have lineage")
	_expect(int(summary.get("unique_lineage_count", 0)) == EXPECTED_PLANTS, "all representative lineages are unique")
	_expect(int(summary.get("unique_genome_count", 0)) >= 8, "genome field is meaningfully diverse")
	_expect(int(summary.get("alpha_unique_genome_count", 0)) >= 2 and int(summary.get("beta_unique_genome_count", 0)) >= 2, "both population channels diverge")
	_expect(int(summary.get("adaptation_generations", 0)) == VIS16_BRIDGE.ADAPTATION_GENERATIONS, "configured generations reported")
	_expect(float(summary.get("mean_fitness_gain", -1.0)) >= -0.000000001, "mean selected fitness is non-decreasing")
	_expect(absf(float(summary.get("represented_biomass_kg", -1.0)) - EXPECTED_BIOMASS_KG) <= 0.000000001, "represented biomass remains 11kg")
	_expect(Array(summary.get("populations", [])).size() == 6, "six patch/population summaries survive")
	print("ECO.VIS1.6 smoke progress: summary_checked")

	var projection := lab.get_node_or_null("SpatialEcologyProjection") as Node3D
	_expect(projection != null, "VIS1.2 projection survives")
	var ph5_root := projection.get_node_or_null("PH5PlantGeometry") as Node3D if projection != null else null
	_expect(ph5_root != null and ph5_root.visible, "lineage-derived PH5 field visible")

	var plant_count := 0
	var environment_matches := 0
	var represented_sum := 0.0
	var lineages := {}
	var genomes := {}
	var alpha_genomes := {}
	var beta_genomes := {}
	var development_traits := {}
	var phenotypes := {}
	var fitness_ok := 0
	var generation_ok := 0
	if ph5_root != null:
		for patch_id in PATCHES:
			var field_patch := ph5_root.get_node_or_null("Patch_%s" % patch_id) as Node3D
			_expect(field_patch != null, "lineage patch %s exists" % patch_id)
			if field_patch == null: continue
			for population_root in field_patch.get_children():
				if not String(population_root.name).begins_with("PH5Population_"): continue
				for child in population_root.get_children():
					if not String(child.name).begins_with("Plant_"): continue
					var plant := child as Node3D
					plant_count += 1
					represented_sum += float(plant.get_meta("represented_biomass_kg", -1.0))
					_expect(bool(plant.get_meta("lineage_genome_derived", false)), "plant marked lineage/genome-derived")
					_expect(not bool(plant.get_meta("canonical_genome_truth", true)), "plant does not claim canonical genome truth")
					var genome_hash := String(plant.get_meta("genome_checksum", ""))
					var lineage_hash := String(plant.get_meta("lineage_checksum", ""))
					var population_id := String(plant.get_meta("population_id", ""))
					_expect(genome_hash.length() == 64 and lineage_hash.length() == 64, "plant genome/lineage hashes exist")
					_expect(String(plant.get_meta("lineage_id", "")).begins_with("eco-lineage/"), "canonical lineage record id format retained")
					_expect(String(plant.get_meta("individual_id", "")).begins_with("eco-individual/"), "canonical individual id format retained")
					lineages[lineage_hash] = true
					genomes[genome_hash] = true
					if population_id == "alpha": alpha_genomes[genome_hash] = true
					elif population_id == "beta": beta_genomes[genome_hash] = true
					development_traits[String(plant.get_meta("inherited_traits_checksum", ""))] = true
					phenotypes[String(plant.get_meta("phenotype_hash", ""))] = true
					if int(plant.get_meta("lineage_generation", -1)) == VIS16_BRIDGE.ADAPTATION_GENERATIONS: generation_ok += 1
					if float(plant.get_meta("final_fitness", 0.0)) + 0.000000001 >= float(plant.get_meta("initial_fitness", 0.0)): fitness_ok += 1
					var local_environment := lab.call("sample_environment_at", plant.global_position.x, plant.global_position.z) as Dictionary
					if String(local_environment.get("checksum", "")) == String(plant.get_meta("environment_checksum", "")): environment_matches += 1
					_expect(plant.get_node_or_null("Branches") is MeshInstance3D, "lineage plant has PH5 branches")
					_expect(plant.get_node_or_null("Foliage") is MultiMeshInstance3D, "lineage plant has PH5 foliage")

	_expect(plant_count == EXPECTED_PLANTS, "scene contains 53 lineage representatives")
	_expect(lineages.size() == EXPECTED_PLANTS, "all lineage checksums unique")
	_expect(genomes.size() >= 8, "scene genome diversity meaningful")
	_expect(alpha_genomes.size() >= 2 and beta_genomes.size() >= 2, "both population channels have multiple genomes")
	_expect(development_traits.size() >= 8, "genome-to-development mapping produces diverse inherited traits")
	_expect(phenotypes.size() >= 45, "genotype plus environment produce diverse phenotypes")
	_expect(environment_matches == EXPECTED_PLANTS, "every lineage phenotype uses local EnvironmentSample")
	_expect(generation_ok == EXPECTED_PLANTS, "all lineages reach configured generation")
	_expect(fitness_ok == EXPECTED_PLANTS, "selection never accepts lower fitness")
	_expect(absf(represented_sum - EXPECTED_BIOMASS_KG) <= 0.000000001, "plant metadata conserves 11kg")
	print("ECO.VIS1.6 smoke progress: lineage_geometry_checked")

	var snapshot_after := lab.call("get_spatial_snapshot") as Dictionary
	_expect(snapshot_before == snapshot_after, "VIS1.6 does not mutate canonical ecology snapshot")
	_expect(String(lab.call("get_population_field_hash")).length() == 64, "VIS1.6 field hash exists")
	var status := lab.get_node_or_null("HUD/Margin/Panel/VBox/Status") as Label
	_expect(status != null and status.text.contains("VIS1.6=ACTIVE"), "HUD reports VIS1.6 active")
	_expect(status != null and status.text.contains("canonical_genome_truth=OFF"), "HUD reports genome truth boundary")
	_expect(status != null and status.text.contains("Nearest lineage:"), "HUD exposes nearest lineage inspector")
	print("ECO.VIS1.6 smoke progress: assertions_complete")
	_finish()

func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if condition: return
	_failures += 1
	push_error("ECO.VIS1.6 assertion failed: %s" % message)

func _finish() -> void:
	if _failures == 0:
		print("ECO.VIS1.6 headless scene smoke: PASS (%d assertions)" % _assertions)
		quit(0)
		return
	print("ECO.VIS1.6 headless scene smoke: FAIL (%d assertions, %d failures)" % [_assertions, _failures])
	quit(1)
