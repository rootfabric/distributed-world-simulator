extends SceneTree

const SCENE_PATH := "res://scenes/labs/ecology/eco_vis1_7_temporal_evolution_field.tscn"
const VIS17_SCRIPT = preload("res://scripts/labs/ecology/eco_vis1_7_temporal_evolution_field.gd")
const EXPECTED_PLANTS := 53
const EXPECTED_BIOMASS_KG := 11.0

var _assertions := 0
var _failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect(packed != null, "VIS1.7 scene loads")
	if packed == null:
		_finish()
		return
	var lab := packed.instantiate() as Node3D
	_expect(lab != null, "VIS1.7 scene instantiates")
	if lab == null:
		_finish()
		return
	_expect(lab.get_script() == VIS17_SCRIPT, "VIS1.7 script is attached")
	if lab.get_script() != VIS17_SCRIPT:
		lab.free()
		_finish()
		return
	get_root().add_child(lab)
	await process_frame
	await process_frame
	print("ECO.VIS1.7 smoke progress: scene_ready")
	var snapshot_before := lab.call("get_spatial_snapshot") as Dictionary
	var summary := lab.call("get_population_field_summary") as Dictionary
	var state := lab.call("get_evolution_state") as Dictionary
	_expect(String(summary.get("stage", "")) == "ECO.VIS1.7", "summary reports VIS1.7")
	_expect(String(summary.get("temporal_mode", "")) == "LAB_DERIVED_TEMPORAL_LINEAGE_SCRUBBER", "temporal mode is active")
	_expect(int(summary.get("current_generation", -1)) == 3, "default generation preserves VIS1.6 checkpoint")
	_expect(int(summary.get("max_generation", -1)) == 12, "timeline exposes twelve generations")
	_expect(not bool(summary.get("canonical_timeline_truth", true)), "timeline does not claim canonical truth")
	_expect(int(summary.get("visual_instance_count", 0)) == EXPECTED_PLANTS, "53 representative plants survive")
	_expect(int(summary.get("lineage_instance_count", 0)) == EXPECTED_PLANTS, "53 lineage instances survive")
	_expect(int(summary.get("trajectory_count", 0)) == EXPECTED_PLANTS, "every representative has a trajectory")
	_expect(absf(float(summary.get("represented_biomass_kg", -1.0)) - EXPECTED_BIOMASS_KG) <= 0.000000001, "represented biomass remains 11kg")
	_expect(String(summary.get("projection_hash", "")).length() == 64, "temporal field hash exists")
	_expect(int(state.get("generation", -1)) == 3 and not bool(state.get("playing", true)), "timeline starts paused at generation three")
	print("ECO.VIS1.7 smoke progress: summary_checked")
	var projection := lab.get_node_or_null("SpatialEcologyProjection") as Node3D
	var ph5_root := projection.get_node_or_null("PH5PlantGeometry") as Node3D if projection != null else null
	_expect(ph5_root != null and ph5_root.visible, "temporal PH5 field is visible")
	var plant_count := 0
	var generation_matches := 0
	var trajectory_hashes := {}
	var represented_sum := 0.0
	if ph5_root != null:
		for patch_root in ph5_root.get_children():
			for population_root in patch_root.get_children():
				if not String(population_root.name).begins_with("PH5Population_"):
					continue
				for child in population_root.get_children():
					if not String(child.name).begins_with("Plant_"):
						continue
					var plant := child as Node3D
					plant_count += 1
					represented_sum += float(plant.get_meta("represented_biomass_kg", 0.0))
					if int(plant.get_meta("timeline_generation", -1)) == 3:
						generation_matches += 1
					var trajectory_hash := String(plant.get_meta("trajectory_hash", ""))
					_expect(trajectory_hash.length() == 64, "plant trajectory hash exists")
					trajectory_hashes[trajectory_hash] = true
					_expect(bool(plant.get_meta("temporal_evolution_derived", false)), "plant is marked temporal-derived")
					_expect(not bool(plant.get_meta("canonical_timeline_truth", true)), "plant metadata preserves timeline truth boundary")
					_expect(plant.get_node_or_null("Branches") is MeshInstance3D, "temporal plant has PH5 branches")
					_expect(plant.get_node_or_null("Foliage") is MultiMeshInstance3D, "temporal plant has PH5 foliage")
	_expect(plant_count == EXPECTED_PLANTS, "scene contains 53 temporal representatives")
	_expect(generation_matches == EXPECTED_PLANTS, "all representatives are at generation three")
	_expect(trajectory_hashes.size() == EXPECTED_PLANTS, "all representative trajectories are unique")
	_expect(absf(represented_sum - EXPECTED_BIOMASS_KG) <= 0.000000001, "plant metadata conserves 11kg")
	var snapshot_after := lab.call("get_spatial_snapshot") as Dictionary
	_expect(snapshot_before == snapshot_after, "VIS1.7 does not mutate canonical ecology snapshot")
	var status := lab.get_node_or_null("HUD/Margin/Panel/VBox/Status") as Label
	_expect(status != null and status.text.contains("VIS1.7=ACTIVE"), "HUD reports VIS1.7 active")
	_expect(status != null and status.text.contains("canonical_timeline_truth=OFF"), "HUD reports timeline truth boundary")
	var controls := lab.get_node_or_null("HUD/Margin/Panel/VBox/Controls") as Label
	_expect(controls != null and controls.text.contains("Left/Right generation"), "HUD exposes generation controls")
	var title := lab.get_node_or_null("HUD/Margin/Panel/VBox/Title") as Label
	_expect(title != null and title.text.contains("Temporal Evolution Scrubber"), "VIS1.7 title is visible")
	print("ECO.VIS1.7 smoke progress: assertions_complete")
	_finish()

func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	push_error("ECO.VIS1.7 assertion failed: %s" % message)

func _finish() -> void:
	if _failures == 0:
		print("ECO.VIS1.7 headless scene smoke: PASS (%d assertions)" % _assertions)
		quit(0)
		return
	print("ECO.VIS1.7 headless scene smoke: FAIL (%d assertions, %d failures)" % [_assertions, _failures])
	quit(1)
