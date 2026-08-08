extends SceneTree

const LabScene = preload("res://scenes/labs/character/quaternius_equipment_lab.tscn")
const Factory = preload("res://scripts/characters/equipment/selective_garment_scene_factory.gd")
const Bridge = preload("res://scripts/characters/equipment/skinned_garment_pose_bridge.gd")
const MALE_PEASANT_PATH := "res://assets/external/quaternius/modular_outfits_fantasy/Modular Character Outfits - Fantasy[Standard]/Exports/glTF (Godot-Unreal)/Outfits/Male_Peasant.gltf"

var failures: Array[String] = []
var assertions := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var lab = LabScene.instantiate()
	root.add_child(lab)
	await process_frame
	await physics_frame

	var source_skeleton: Skeleton3D = lab.equipment_rig_adapter.resolve_pose_skeleton(lab.avatar)
	var skinned_parent: Node3D = lab.equipment_rig_adapter.resolve_skinned_parent(lab.avatar)
	_assert(source_skeleton != null and source_skeleton.get_bone_count() == 65, "CH8B source skeleton mismatch")
	_assert(skinned_parent != null, "CH8B skinned parent missing")

	var loaded = load(MALE_PEASANT_PATH)
	_assert(loaded is PackedScene, "CH8B Male_Peasant scene missing")
	if not loaded is PackedScene or source_skeleton == null or skinned_parent == null:
		lab.queue_free()
		_finish()
		return

	var source_scene := loaded as PackedScene
	var selections := [
		{"label": "upper", "names": ["Male_Peasant_Body", "Male_Peasant_Arms"], "count": 2},
		{"label": "lower", "names": ["Male_Peasant_Legs"], "count": 1},
		{"label": "feet", "names": ["Male_Peasant_Feet"], "count": 1},
	]
	var bridges: Array = []
	var player_position_before: Vector3 = lab.player.position
	var capsule_height_before := float(lab.player_capsule.height)

	for selection in selections:
		var factory_result: Dictionary = Factory.create(source_scene, selection["names"])
		_assert(bool(factory_result.get("success", false)), "CH8B %s selection failed" % String(selection["label"]))
		if not bool(factory_result.get("success", false)):
			continue
		var details: Dictionary = factory_result.get("details", {})
		_assert(int(details.get("source_mesh_count", 0)) == 4, "CH8B source mesh count changed")
		_assert(int(details.get("selected_skinned_mesh_count", 0)) == int(selection["count"]), "CH8B selected mesh count mismatch")
		var selected_scene = details.get("scene")
		_assert(selected_scene is PackedScene, "CH8B selected scene is not PackedScene")
		if not selected_scene is PackedScene:
			continue

		var bridge = Bridge.new()
		skinned_parent.add_child(bridge)
		var setup_result: Dictionary = bridge.setup(source_skeleton, selected_scene as PackedScene)
		_assert(bool(setup_result.get("success", false)), "CH8B %s bridge setup failed" % String(selection["label"]))
		if not bool(setup_result.get("success", false)):
			bridge.queue_free()
			continue
		bridges.append(bridge)
		var report: Dictionary = bridge.create_report()
		_assert(int(report.get("matched_bones", 0)) == 65, "CH8B %s bridge lost 65/65 match" % String(selection["label"]))
		_assert(int(report.get("garment_skeleton_count", 0)) == 1, "CH8B %s bridge skeleton count mismatch" % String(selection["label"]))
		_assert(int(report.get("skinned_mesh_count", 0)) == int(selection["count"]), "CH8B %s bridge retained wrong meshes" % String(selection["label"]))
		var actual_names: Array[String] = []
		_collect_mesh_names(bridge.get_visual_root(), actual_names)
		actual_names.sort()
		var expected_names: Array = selection["names"]
		expected_names.sort()
		_assert(actual_names == expected_names, "CH8B %s mesh identity mismatch" % String(selection["label"]))

	_assert(bridges.size() == 3, "CH8B expected three simultaneous selective bridges")
	lab.avatar.apply_motion(Vector3(2.0, 0.0, 0.0), Vector3.UP, Vector3.RIGHT, {"grounded": true, "crouching": false})
	await process_frame
	for bridge in bridges:
		var sync_result: Dictionary = bridge.sync_pose_now()
		_assert(bool(sync_result.get("success", false)), "CH8B pose sync failed")
		_assert(int(sync_result.get("details", {}).get("copied_bones", 0)) == 65, "CH8B pose sync did not copy 65 bones")

	_assert(lab.player.position.is_equal_approx(player_position_before), "CH8B moved gameplay body")
	_assert(is_equal_approx(float(lab.player_capsule.height), capsule_height_before), "CH8B modified gameplay capsule")
	for bridge in bridges:
		bridge.queue_free()
	lab.queue_free()
	_finish()

func _collect_mesh_names(root_node: Node, output: Array[String]) -> void:
	if root_node == null:
		return
	if root_node is MeshInstance3D:
		output.append(String(root_node.name))
	for child in root_node.get_children():
		_collect_mesh_names(child, output)

func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("CH8B Quaternius selective skinned parts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH8B Quaternius selective skinned parts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
