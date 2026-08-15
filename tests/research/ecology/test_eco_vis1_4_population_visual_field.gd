extends SceneTree

const SCENE_PATH := "res://scenes/labs/ecology/eco_vis1_4_population_visual_field.tscn"
const PATCHES := ["A", "B", "C"]
const EXPECTED_PLANTS := 53
const EXPECTED_BIOMASS_KG := 11.0

var _assertions := 0
var _failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect(packed != null, "scene loads")
	if packed == null:
		_finish(); return
	var lab := packed.instantiate() as Node3D
	_expect(lab != null, "scene instantiates")
	if lab == null:
		_finish(); return
	get_root().add_child(lab)
	await process_frame
	await process_frame

	var snapshot_before := lab.call("get_spatial_snapshot") as Dictionary
	_expect(int(snapshot_before.get("step_index", -1)) == 5, "canonical frame remains 5")
	_expect(String(snapshot_before.get("snapshot_hash", "")).length() == 64, "canonical snapshot hash exists")
	_expect(absf(float(snapshot_before.get("total_final_biomass_kg", 0.0)) - EXPECTED_BIOMASS_KG) <= 0.000000001, "canonical biomass remains 11kg")

	var summary := lab.call("get_population_field_summary") as Dictionary
	_expect(String(summary.get("stage", "")) == "ECO.VIS1.4", "summary stage")
	_expect(String(summary.get("profile_id", "")) == "BRANCH_LEAF_INSTANCED", "PH5 profile preserved")
	_expect(String(summary.get("source_snapshot_hash", "")) == String(snapshot_before.get("snapshot_hash", "")), "summary points to canonical snapshot")
	_expect(int(summary.get("visual_instance_count", 0)) == EXPECTED_PLANTS, "53 representative plants")
	_expect(int(summary.get("mid_proxy_count", 0)) == EXPECTED_PLANTS, "53 mid LOD proxies")
	_expect(int(summary.get("far_proxy_count", 0)) == 13, "13 far cluster proxies")
	_expect(int(summary.get("branch_vertex_count", 0)) > 0, "near branch geometry exists")
	_expect(int(summary.get("foliage_instance_count", 0)) > 0, "near foliage exists")
	_expect(absf(float(summary.get("represented_biomass_kg", -1.0)) - EXPECTED_BIOMASS_KG) <= 0.000000001, "represented biomass conserves source")
	_expect(Array(summary.get("populations", [])).size() == 6, "six patch/population summaries")

	var population_count_sum := 0
	for value in Array(summary.get("populations", [])):
		var population := Dictionary(value)
		population_count_sum += int(population.get("visual_count", 0))
		_expect(absf(float(population.get("source_biomass_kg", 0.0)) - float(population.get("represented_biomass_kg", -1.0))) <= 0.000000001, "population biomass conserved")
		_expect(int(population.get("cluster_count", 0)) in [1, 2, 3], "cluster count bounded")
	_expect(population_count_sum == EXPECTED_PLANTS, "population counts sum to 53")

	var projection := lab.get_node_or_null("SpatialEcologyProjection") as Node3D
	_expect(projection != null, "VIS1.2 projection survives")
	var ph5_root := projection.get_node_or_null("PH5PlantGeometry") as Node3D if projection != null else null
	_expect(ph5_root != null and ph5_root.visible, "PH5 field visible by default")
	var links := projection.get_node_or_null("DispersalLinks") as Node3D if projection != null else null
	_expect(links != null and not links.visible, "links default OFF")

	var plant_count := 0
	var represented_sum := 0.0
	var unique_positions := {}
	var plants_with_ph5 := 0
	var plants_with_mid := 0
	if ph5_root != null:
		for patch_id in PATCHES:
			var diagnostic_patch := projection.get_node_or_null("Patch_%s" % patch_id) as Node3D
			_expect(diagnostic_patch != null, "diagnostic patch %s survives" % patch_id)
			if diagnostic_patch != null:
				var disc := diagnostic_patch.get_node_or_null("PatchDisc") as Node3D
				var label := diagnostic_patch.get_node_or_null("PatchLabel") as Node3D
				_expect(disc != null and not disc.visible, "patch disc defaults OFF")
				_expect(label != null and not label.visible, "patch label defaults OFF")
			var field_patch := ph5_root.get_node_or_null("Patch_%s" % patch_id) as Node3D
			_expect(field_patch != null, "field patch %s exists" % patch_id)
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
					if bool(plant.get_meta("visual_representation_only", false)) and plant.get_node_or_null("Branches") is MeshInstance3D and plant.get_node_or_null("Foliage") is MultiMeshInstance3D:
						plants_with_ph5 += 1
					var mid := plant.get_node_or_null("MidCanopy") as MeshInstance3D
					if mid != null and String(mid.get_meta("derived_lod_proxy", "")) == "MID_CANOPY":
						plants_with_mid += 1
					unique_positions["%.2f/%.2f" % [plant.position.x, plant.position.z]] = true
	_expect(plant_count == EXPECTED_PLANTS, "scene has 53 representative plant nodes")
	_expect(plants_with_ph5 == EXPECTED_PLANTS, "all representatives retain PH5 geometry")
	_expect(plants_with_mid == EXPECTED_PLANTS, "all representatives have mid LOD")
	_expect(absf(represented_sum - EXPECTED_BIOMASS_KG) <= 0.000000001, "plant metadata sums to 11kg")
	_expect(unique_positions.size() >= 45, "cluster placement remains spatially distinct")

	var visibility := lab.call("get_visual_visibility_state") as Dictionary
	_expect(not bool(visibility.get("patch_discs", true)) and not bool(visibility.get("dispersal_links", true)) and not bool(visibility.get("patch_labels", true)) and bool(visibility.get("plants", false)), "default world view hides diagnostics and shows plants")
	lab.call("set_diagnostics_visible", true)
	visibility = lab.call("get_visual_visibility_state") as Dictionary
	_expect(bool(visibility.get("patch_discs", false)) and bool(visibility.get("dispersal_links", false)) and bool(visibility.get("patch_labels", false)), "diagnostic master toggle works")
	lab.call("set_plants_visible", false)
	_expect(ph5_root != null and not ph5_root.visible, "plant toggle hides field")
	lab.call("set_plants_visible", true)
	_expect(ph5_root != null and ph5_root.visible, "plant toggle restores field")
	lab.call("set_diagnostics_visible", false)

	var hash_a := String(lab.call("get_population_field_hash"))
	_expect(hash_a.length() == 64, "field hash exists")
	lab.call("rebuild_spatial_projection")
	await process_frame
	await process_frame
	var hash_b := String(lab.call("get_population_field_hash"))
	var snapshot_after := lab.call("get_spatial_snapshot") as Dictionary
	_expect(hash_a == hash_b, "rebuild is deterministic")
	_expect(snapshot_before == snapshot_after, "VIS1.4 does not mutate canonical snapshot")
	var summary_after := lab.call("get_population_field_summary") as Dictionary
	_expect(int(summary_after.get("visual_instance_count", 0)) == EXPECTED_PLANTS, "rebuild keeps 53 plants")
	_expect(absf(float(summary_after.get("represented_biomass_kg", 0.0)) - EXPECTED_BIOMASS_KG) <= 0.000000001, "rebuild keeps biomass conservation")

	var status := lab.get_node_or_null("HUD/Margin/Panel/VBox/Status") as Label
	_expect(status != null and status.text.contains("VIS1.4=ACTIVE") and status.text.contains("MATCH"), "HUD reports active conserved field")
	var controls := lab.get_node_or_null("HUD/Margin/Panel/VBox/Controls") as Label
	_expect(controls != null and controls.text.contains("F1 diagnostics"), "HUD exposes toggles")

	lab.queue_free()
	await process_frame
	_finish()

func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if condition: return
	_failures += 1
	push_error("ECO.VIS1.4 assertion failed: %s" % message)

func _finish() -> void:
	if _failures == 0:
		print("ECO.VIS1.4 headless scene smoke: PASS (%d assertions)" % _assertions)
		quit(0)
		return
	print("ECO.VIS1.4 headless scene smoke: FAIL (%d assertions, %d failures)" % [_assertions, _failures])
	quit(1)
