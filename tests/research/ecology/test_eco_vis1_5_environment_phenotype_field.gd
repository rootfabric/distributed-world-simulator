extends SceneTree

const SCENE_PATH := "res://scenes/labs/ecology/eco_vis1_5_environment_phenotype_field.tscn"
const VIS15_SCRIPT = preload("res://scripts/labs/ecology/eco_vis1_5_environment_phenotype_field.gd")
const EXPECTED_PLANTS := 53
const EXPECTED_BIOMASS_KG := 11.0
const PATCHES := ["A", "B", "C"]

var _assertions := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect(packed != null, "VIS1.5 scene loads")
	if packed == null:
		_finish()
		return
	var lab := packed.instantiate() as Node3D
	_expect(lab != null, "VIS1.5 scene instantiates")
	if lab == null:
		_finish()
		return
	_expect(lab.get_script() == VIS15_SCRIPT, "VIS1.5 script is attached")
	if lab.get_script() != VIS15_SCRIPT:
		lab.free()
		_finish()
		return
	get_root().add_child(lab)
	await process_frame
	await process_frame
	print("ECO.VIS1.5 smoke progress: scene_ready")

	var snapshot_before := lab.call("get_spatial_snapshot") as Dictionary
	_expect(int(snapshot_before.get("step_index", -1)) == 5, "canonical VIS1.2 frame remains 5")
	_expect(String(snapshot_before.get("snapshot_hash", "")).length() == 64, "canonical spatial hash exists")
	_expect(absf(float(snapshot_before.get("total_final_biomass_kg", 0.0)) - EXPECTED_BIOMASS_KG) <= 0.000000001, "canonical biomass remains 11kg")

	var summary := lab.call("get_population_field_summary") as Dictionary
	_expect(String(summary.get("stage", "")) == "ECO.VIS1.5", "summary reports VIS1.5")
	_expect(String(summary.get("phenotype_mode", "")) == "LOCAL_ENVIRONMENT_COUPLED_DEVELOPMENT", "local environment phenotype mode is active")
	_expect(not bool(summary.get("canned_exemplar_mapping", true)), "SUN/SHADE canned mapping is disabled")
	_expect(String(summary.get("profile_id", "")) == "BRANCH_LEAF_INSTANCED", "PH5 renderer profile is preserved")
	_expect(int(summary.get("visual_instance_count", 0)) == EXPECTED_PLANTS, "53 representative plants survive")
	_expect(int(summary.get("phenotype_instance_count", 0)) == EXPECTED_PLANTS, "all representatives have realized phenotype")
	_expect(int(summary.get("mid_proxy_count", 0)) == EXPECTED_PLANTS, "all representatives have phenotype-aware mid LOD")
	_expect(int(summary.get("far_proxy_count", 0)) == 13, "far population LOD remains present")
	_expect(int(summary.get("unique_phenotype_count", 0)) >= 45, "phenotype realization is meaningfully diverse")
	_expect(int(summary.get("unique_environment_sample_count", 0)) >= 45, "representatives sample distinct local environments")
	_expect(String(summary.get("baseline_genome_id", "")) == "plant-genome/p1a-s2-baseline", "lab baseline genome is explicit")
	_expect(String(summary.get("baseline_genome_checksum", "")).length() == 64, "lab baseline genome checksum exists")
	_expect(String(summary.get("baseline_traits_checksum", "")).length() == 64, "lab baseline development traits checksum exists")
	_expect(absf(float(summary.get("represented_biomass_kg", -1.0)) - EXPECTED_BIOMASS_KG) <= 0.000000001, "VIS1.4 biomass conservation survives")
	_expect(Array(summary.get("populations", [])).size() == 6, "six patch/population summaries survive")
	print("ECO.VIS1.5 smoke progress: summary_checked")

	var projection := lab.get_node_or_null("SpatialEcologyProjection") as Node3D
	_expect(projection != null, "VIS1.2 projection survives")
	var ph5_root := projection.get_node_or_null("PH5PlantGeometry") as Node3D if projection != null else null
	_expect(ph5_root != null and ph5_root.visible, "phenotype PH5 field is visible")

	var plant_count := 0
	var environment_matches := 0
	var phenotypes := {}
	var environments := {}
	var height_buckets := {}
	var represented_sum := 0.0
	if ph5_root != null:
		for patch_id in PATCHES:
			var field_patch := ph5_root.get_node_or_null("Patch_%s" % patch_id) as Node3D
			_expect(field_patch != null, "phenotype patch %s exists" % patch_id)
			if field_patch == null:
				continue
			for population_root in field_patch.get_children():
				if not String(population_root.name).begins_with("PH5Population_"):
					continue
				for child in population_root.get_children():
					if not String(child.name).begins_with("Plant_"):
						continue
					var plant := child as Node3D
					plant_count += 1
					represented_sum += float(plant.get_meta("represented_biomass_kg", -1.0))
					_expect(bool(plant.get_meta("phenotype_environment_coupled", false)), "plant is marked environment-coupled")
					_expect(String(plant.get_meta("genome_checksum", "")).length() == 64, "plant retains lab genome checksum")
					var phenotype_hash := String(plant.get_meta("phenotype_hash", ""))
					var environment_hash := String(plant.get_meta("environment_checksum", ""))
					_expect(phenotype_hash.length() == 64, "plant phenotype hash exists")
					_expect(environment_hash.length() == 64, "plant environment checksum exists")
					phenotypes[phenotype_hash] = true
					environments[environment_hash] = true
					height_buckets["%.3f" % float(plant.get_meta("realized_max_height_m", 0.0))] = true
					var local_environment := lab.call("sample_environment_at", plant.global_position.x, plant.global_position.z) as Dictionary
					if String(local_environment.get("checksum", "")) == environment_hash:
						environment_matches += 1
					_expect(plant.get_node_or_null("Branches") is MeshInstance3D, "phenotype plant has PH5 branches")
					_expect(plant.get_node_or_null("Foliage") is MultiMeshInstance3D, "phenotype plant has PH5 foliage")
					var mid := plant.get_node_or_null("MidCanopy") as MeshInstance3D
					_expect(mid != null and String(mid.get_meta("derived_lod_proxy", "")) == "MID_CANOPY_PHENOTYPE", "mid LOD comes from phenotype canopy")
	_expect(plant_count == EXPECTED_PLANTS, "scene contains 53 phenotype representatives")
	_expect(environment_matches == EXPECTED_PLANTS, "every phenotype uses the EnvironmentSample at its actual world position")
	_expect(phenotypes.size() >= 45, "individual phenotype hashes are diverse")
	_expect(environments.size() >= 45, "local environment checksums are diverse")
	_expect(height_buckets.size() >= 4, "environment-coupled realized heights vary")
	_expect(absf(represented_sum - EXPECTED_BIOMASS_KG) <= 0.000000001, "plant metadata still conserves 11kg")
	print("ECO.VIS1.5 smoke progress: phenotype_geometry_checked")

	var visibility := lab.call("get_visual_visibility_state") as Dictionary
	_expect(not bool(visibility.get("patch_discs", true)) and not bool(visibility.get("dispersal_links", true)) and not bool(visibility.get("patch_labels", true)) and bool(visibility.get("plants", false)), "VIS1.4 default world view survives")
	var snapshot_after := lab.call("get_spatial_snapshot") as Dictionary
	_expect(snapshot_before == snapshot_after, "VIS1.5 derived phenotype field does not mutate canonical ecology snapshot")
	var field_hash := String(lab.call("get_population_field_hash"))
	_expect(field_hash.length() == 64, "VIS1.5 field hash exists")

	var status := lab.get_node_or_null("HUD/Margin/Panel/VBox/Status") as Label
	_expect(status != null and status.text.contains("VIS1.5=ACTIVE"), "HUD reports VIS1.5 active")
	_expect(status != null and status.text.contains("canned_exemplars=OFF"), "HUD reports canned exemplar removal")
	_expect(status != null and status.text.contains("Nearest phenotype:"), "HUD exposes nearest phenotype inspector")
	_expect(status != null and not status.text.contains("presentation exemplars alpha=SUN beta=SHADE"), "old canned mapping label is absent")
	var title := lab.get_node_or_null("HUD/Margin/Panel/VBox/Title") as Label
	_expect(title != null and title.text.contains("Environment-Coupled Phenotype Field"), "VIS1.5 title is visible")
	print("ECO.VIS1.5 smoke progress: assertions_complete")
	_finish()


func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	push_error("ECO.VIS1.5 assertion failed: %s" % message)


func _finish() -> void:
	if _failures == 0:
		print("ECO.VIS1.5 headless scene smoke: PASS (%d assertions)" % _assertions)
		quit(0)
		return
	print("ECO.VIS1.5 headless scene smoke: FAIL (%d assertions, %d failures)" % [_assertions, _failures])
	quit(1)
