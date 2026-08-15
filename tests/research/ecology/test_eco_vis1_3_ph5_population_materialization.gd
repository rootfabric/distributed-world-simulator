extends SceneTree

const SCENE_PATH := "res://scenes/labs/ecology/eco_vis1_3_ph5_population_materialization.tscn"
const EXPECTED_PATCHES := ["A", "B", "C"]
var _assertions := 0
var _failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect(packed != null, "VIS1.3 scene loads")
	if packed == null:
		_finish(); return
	var lab := packed.instantiate() as Node3D
	_expect(lab != null, "VIS1.3 scene instantiates")
	if lab == null:
		_finish(); return
	get_root().add_child(lab)
	await process_frame
	await process_frame

	var snapshot_before := lab.call("get_spatial_snapshot") as Dictionary
	_expect(int(snapshot_before.get("step_index", -1)) == 5, "VIS1.3 keeps the VIS1.2 canonical frame")
	_expect(String(snapshot_before.get("snapshot_hash", "")).length() == 64, "canonical spatial snapshot hash is present")

	var projection := lab.get_node_or_null("SpatialEcologyProjection") as Node3D
	_expect(projection != null, "VIS1.2 spatial projection survives")
	var ph5_root := projection.get_node_or_null("PH5PlantGeometry") as Node3D if projection != null else null
	_expect(ph5_root != null, "PH5 derived geometry root exists")

	for patch_id in EXPECTED_PATCHES:
		var patch_root := projection.get_node_or_null("Patch_%s" % patch_id) as Node3D if projection != null else null
		_expect(patch_root != null, "patch %s survives" % patch_id)
		if patch_root == null:
			continue
		_expect(patch_root.get_node_or_null("PatchDisc") is MeshInstance3D, "patch %s diagnostic disc survives" % patch_id)
		_expect(patch_root.get_node_or_null("PatchLabel") is Label3D, "patch %s label survives" % patch_id)
		for child in patch_root.get_children():
			_expect(not String(child.name).begins_with("Population_"), "VIS1.2 cylinder glyphs are removed from patch %s" % patch_id)

	var summary := lab.call("get_ph5_materialization_summary") as Dictionary
	_expect(String(summary.get("stage", "")) == "ECO.VIS1.3", "summary reports VIS1.3")
	_expect(String(summary.get("profile_id", "")) == "BRANCH_LEAF_INSTANCED", "accepted PH5 profile is used")
	_expect(String(summary.get("source_snapshot_hash", "")) == String(snapshot_before.get("snapshot_hash", "")), "PH5 projection points to canonical spatial snapshot")
	_expect(int(summary.get("visual_instance_count", 0)) > 0, "PH5 creates visible plant instances")
	_expect(int(summary.get("branch_vertex_count", 0)) > 0, "PH5 branch meshes contain geometry")
	_expect(int(summary.get("foliage_instance_count", 0)) > 0, "PH5 foliage instances are present")
	_expect(Array(summary.get("populations", [])).size() >= 4, "population materialization summary is populated")

	var inspected_plant := false
	if ph5_root != null:
		for patch_id in EXPECTED_PATCHES:
			var ph5_patch_root := ph5_root.get_node_or_null("Patch_%s" % patch_id) as Node3D
			_expect(ph5_patch_root != null, "PH5 namespace contains patch %s" % patch_id)
			if ph5_patch_root == null:
				continue
			for population_root in ph5_patch_root.get_children():
				if not String(population_root.name).begins_with("PH5Population_"):
					continue
				for plant in population_root.get_children():
					if String(plant.name).begins_with("Plant_"):
						_expect(plant.get_node_or_null("Branches") is MeshInstance3D, "plant has real PH5 branch mesh")
						_expect(plant.get_node_or_null("Foliage") is MultiMeshInstance3D, "plant has real PH5 foliage multimesh")
						inspected_plant = true
						break
				if inspected_plant:
					break
			if inspected_plant:
				break
	_expect(inspected_plant, "at least one PH5 plant instance is inspectable")

	var hash_a := String(lab.call("get_ph5_projection_hash"))
	_expect(hash_a.length() == 64, "PH5 projection has deterministic hash")
	lab.call("rebuild_spatial_projection")
	await process_frame
	await process_frame
	var hash_b := String(lab.call("get_ph5_projection_hash"))
	var snapshot_after := lab.call("get_spatial_snapshot") as Dictionary
	_expect(hash_a == hash_b, "PH5 rebuild preserves deterministic projection hash")
	_expect(snapshot_before == snapshot_after, "PH5 derived presentation does not mutate canonical ecology snapshot")

	var status := lab.get_node_or_null("HUD/Margin/Panel/VBox/Status") as Label
	_expect(status != null and status.text.contains("PH5=ACTIVE"), "HUD reports PH5 geometry active")
	_expect(status != null and status.text.contains("presentation exemplars"), "HUD labels morphology mapping as presentation-only")
	_expect(lab.get_node_or_null("EnvironmentReferences/WaterGradientAxis") is MeshInstance3D, "VIS1.1 environment reference survives")

	lab.queue_free()
	await process_frame
	_finish()

func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if condition: return
	_failures += 1
	push_error("ECO.VIS1.3 assertion failed: %s" % message)

func _finish() -> void:
	if _failures == 0:
		print("ECO.VIS1.3 headless scene smoke: PASS (%d assertions)" % _assertions)
		quit(0)
		return
	print("ECO.VIS1.3 headless scene smoke: FAIL (%d assertions, %d failures)" % [_assertions, _failures])
	quit(1)
