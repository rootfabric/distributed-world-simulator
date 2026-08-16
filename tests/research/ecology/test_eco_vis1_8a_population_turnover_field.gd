extends SceneTree

const VIS18_FieldScript = preload("res://scripts/labs/ecology/eco_vis1_8a_population_turnover_field.gd")
const VIS18_Bridge = preload("res://scripts/labs/ecology/eco_vis1_8a_turnover_bridge.gd")
const SCENE_PATH := "res://scenes/labs/ecology/eco_vis1_8a_population_turnover_field.tscn"

var _assertions := 0
var _failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect(packed != null, "VIS1.8A scene loads")
	if packed == null:
		_finish()
		return
	var lab := packed.instantiate() as Node3D
	_expect(lab != null, "VIS1.8A scene instantiates")
	if lab == null:
		_finish()
		return
	_expect(lab.get_script() == VIS18_FieldScript, "VIS1.8A field script is attached")
	get_root().add_child(lab)
	await process_frame
	print("ECO.VIS1.8A smoke progress: scene_ready")

	var snapshot_before: Dictionary = lab.call("get_spatial_snapshot")
	var snapshot_hash_before := String(snapshot_before.get("snapshot_hash", ""))
	_expect(snapshot_hash_before.length() == 64, "canonical spatial snapshot is available")
	var state0: Dictionary = lab.call("get_turnover_state")
	_expect(String(state0.get("stage", "")) == "ECO.VIS1.8A", "stage marker matches")
	_expect(int(state0.get("generation", -1)) == 0, "VIS1.8A starts at generation zero")
	_expect(int(state0.get("founder_count", 0)) == 53, "VIS1.8A starts from 53 VIS1.7 representatives")
	_expect(int(state0.get("visual_count", 0)) == 53, "generation zero has 53 representatives")
	_expect(int(state0.get("birth_count", -1)) == 0 and int(state0.get("death_count", -1)) == 0, "generation zero has no turnover events")
	_expect(not bool(state0.get("canonical_population_truth", true)), "turnover remains non-canonical")
	var summary0: Dictionary = lab.call("get_population_field_summary")
	_expect(is_equal_approx(float(summary0.get("represented_biomass_kg", 0.0)), 11.0), "generation zero conserves 11kg represented biomass")
	var signature0 := _representative_signature(lab)
	_expect(signature0.length() == 64, "generation zero representative signature exists")
	print("ECO.VIS1.8A smoke progress: generation0_checked")

	lab.call("set_evolution_generation", 1)
	await process_frame
	var state1: Dictionary = lab.call("get_turnover_state")
	_expect(int(state1.get("generation", -1)) == 1, "generation one applies")
	_expect(int(state1.get("birth_count", 0)) > 0, "generation one has births")
	_expect(int(state1.get("death_count", 0)) > 0, "generation one has deaths")
	_expect(int(state1.get("survivor_count", 0)) > 0, "generation one has survivors")
	_expect(int(state1.get("visual_count", 0)) == int(state1.get("survivor_count", 0)) + int(state1.get("birth_count", 0)), "generation one count arithmetic is exact")
	var summary1: Dictionary = lab.call("get_population_field_summary")
	_expect(is_equal_approx(float(summary1.get("represented_biomass_kg", 0.0)), 11.0), "generation one conserves 11kg represented biomass")
	_expect(is_equal_approx(float(summary1.get("source_biomass_kg", 0.0)), 11.0), "generation one retains 11kg source biomass")
	var signature1 := _representative_signature(lab)
	_expect(signature1 != signature0, "turnover changes representative identity or placement")
	_expect(_count_newborns(lab, 1) == int(state1.get("birth_count", 0)), "all generation-one births are visible")
	_expect(_count_death_markers(lab) == int(state1.get("death_count", 0)), "death markers match current deaths")
	_expect(_count_parented_recruits(lab) > 0, "recruits expose parent identity")
	_expect(_all_visible_plants_have_ph5(lab), "turnover representatives retain PH5 branches and foliage")
	print("ECO.VIS1.8A smoke progress: turnover_checked")

	lab.call("set_evolution_generation", 3)
	await process_frame
	var state3: Dictionary = lab.call("get_turnover_state")
	var hash3 := String(state3.get("field_hash", ""))
	var turnover3 := String(state3.get("turnover_hash", ""))
	_expect(hash3.length() == 64 and turnover3.length() == 64, "generation three hashes exist")
	_expect(int(state3.get("cumulative_births", 0)) > 0 and int(state3.get("cumulative_deaths", 0)) > 0, "generation three accumulates turnover")
	var signature3 := _representative_signature(lab)

	lab.call("set_evolution_generation", 0)
	await process_frame
	lab.call("set_evolution_generation", 3)
	await process_frame
	var repeated3: Dictionary = lab.call("get_turnover_state")
	_expect(String(repeated3.get("field_hash", "")) == hash3, "generation three field is deterministic after rewind")
	_expect(String(repeated3.get("turnover_hash", "")) == turnover3, "generation three turnover is deterministic after rewind")
	_expect(_representative_signature(lab) == signature3, "generation three identities and positions are deterministic after rewind")

	lab.call("set_evolution_generation", 6)
	await process_frame
	var state6: Dictionary = lab.call("get_turnover_state")
	_expect(int(state6.get("generation", -1)) == 6, "generation six applies")
	_expect(int(state6.get("cumulative_births", 0)) >= int(state3.get("cumulative_births", 0)), "cumulative births are monotonic")
	_expect(int(state6.get("cumulative_deaths", 0)) >= int(state3.get("cumulative_deaths", 0)), "cumulative deaths are monotonic")
	var summary6: Dictionary = lab.call("get_population_field_summary")
	_expect(is_equal_approx(float(summary6.get("represented_biomass_kg", 0.0)), 11.0), "generation six conserves represented biomass")
	_expect(int(summary6.get("unique_stable_id_count", 0)) == int(state6.get("visual_count", 0)), "stable ids are unique within current generation")
	var snapshot_after: Dictionary = lab.call("get_spatial_snapshot")
	_expect(String(snapshot_after.get("snapshot_hash", "")) == snapshot_hash_before, "canonical VIS1.2 snapshot is unchanged by turnover")
	_expect(snapshot_after == snapshot_before, "canonical VIS1.2 snapshot remains byte-equivalent as Dictionary")
	print("ECO.VIS1.8A smoke progress: determinism_checked")

	var status := lab.get_node_or_null("HUD/Margin/Panel/VBox/Status") as Label
	var title := lab.get_node_or_null("HUD/Margin/Panel/VBox/Title") as Label
	_expect(status != null and status.text.contains("VIS1.8A=ACTIVE"), "HUD reports VIS1.8A state")
	_expect(status != null and status.text.contains("births="), "HUD reports births")
	_expect(status != null and status.text.contains("deaths="), "HUD reports deaths")
	_expect(title != null and title.text.contains("reps="), "title visibly reports current representative count")
	print("ECO.VIS1.8A smoke progress: assertions_complete")

	if _failures == 0:
		print("ECO.VIS1.8A headless scene smoke: PASS (%d assertions)" % _assertions)
		quit(0)
	else:
		print("ECO.VIS1.8A headless scene smoke: FAIL (%d assertions, %d failures)" % [_assertions, _failures])
		quit(1)

func _representative_signature(lab: Node3D) -> String:
	var root := lab.get_node_or_null("SpatialEcologyProjection/PH5PlantGeometry") as Node3D
	if root == null:
		return ""
	var tokens := PackedStringArray()
	for patch_root in root.get_children():
		for population_root in patch_root.get_children():
			for child in population_root.get_children():
				if not child is Node3D or not String(child.name).begins_with("Plant_"):
					continue
				var plant := child as Node3D
				tokens.append("%s|%.6f|%.6f" % [String(plant.get_meta("stable_id", "")), plant.global_position.x, plant.global_position.z])
	tokens.sort()
	return "\n".join(tokens).sha256_text()

func _count_newborns(lab: Node3D, generation: int) -> int:
	var root := lab.get_node_or_null("SpatialEcologyProjection/PH5PlantGeometry") as Node3D
	if root == null:
		return 0
	var count := 0
	for patch_root in root.get_children():
		for population_root in patch_root.get_children():
			for child in population_root.get_children():
				if child is Node3D and String(child.name).begins_with("Plant_") and int(child.get_meta("birth_generation", -1)) == generation:
					count += 1
	return count

func _count_parented_recruits(lab: Node3D) -> int:
	var root := lab.get_node_or_null("SpatialEcologyProjection/PH5PlantGeometry") as Node3D
	if root == null:
		return 0
	var count := 0
	for patch_root in root.get_children():
		for population_root in patch_root.get_children():
			for child in population_root.get_children():
				if child is Node3D and String(child.name).begins_with("Plant_") and not String(child.get_meta("parent_stable_id", "")).is_empty():
					count += 1
	return count

func _count_death_markers(lab: Node3D) -> int:
	var root := lab.get_node_or_null("SpatialEcologyProjection/VIS18TurnoverEvents") as Node3D
	return 0 if root == null else root.get_child_count()

func _all_visible_plants_have_ph5(lab: Node3D) -> bool:
	var root := lab.get_node_or_null("SpatialEcologyProjection/PH5PlantGeometry") as Node3D
	if root == null:
		return false
	var found := false
	for patch_root in root.get_children():
		for population_root in patch_root.get_children():
			for child in population_root.get_children():
				if not child is Node3D or not String(child.name).begins_with("Plant_"):
					continue
				found = true
				if child.get_node_or_null("Branches") == null or child.get_node_or_null("Foliage") == null:
					return false
	return found

func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	push_error("ECO.VIS1.8A assertion failed: %s" % message)

func _finish() -> void:
	quit(0 if _failures == 0 else 1)
