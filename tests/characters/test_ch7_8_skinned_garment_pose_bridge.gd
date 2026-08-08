extends SceneTree

const Bridge = preload("res://scripts/characters/equipment/skinned_garment_pose_bridge.gd")
const BASE_SCENE_PATH := "res://assets/external/quaternius/base_characters/Universal Base Characters[Standard]/Base Characters/Godot - UE/Superhero_Male_FullBody.gltf"
const GARMENT_SCENE_PATH := "res://assets/external/quaternius/modular_outfits_fantasy/Modular Character Outfits - Fantasy[Standard]/Exports/glTF (Godot-Unreal)/Outfits/Male_Peasant.gltf"

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_synthetic_pose_copy()
	await process_frame
	_test_real_quaternius_outfit()
	await process_frame
	_finish()


func _test_synthetic_pose_copy() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var source := _create_skeleton(["root", "spine", "head", "hand_l", "hand_r"])
	host.add_child(source)

	var bridge = Bridge.new()
	host.add_child(bridge)
	var garment_scene := _create_garment_scene(["root", "spine", "head", "hand_l", "hand_r"])
	_assert(garment_scene != null, "Synthetic garment scene failed to pack")
	if garment_scene == null:
		host.queue_free()
		return

	var setup_result: Dictionary = bridge.setup(source, garment_scene)
	_assert(bool(setup_result.get("success", false)), "Synthetic skinned garment bridge setup failed")
	var report: Dictionary = bridge.create_report()
	_assert(int(report.get("source_bone_count", 0)) == 5, "Synthetic source bone count mismatch")
	_assert(int(report.get("matched_bones", 0)) == 5, "Synthetic garment did not match every source bone")
	_assert(int(report.get("skinned_mesh_count", 0)) == 1, "Synthetic garment skinned mesh count mismatch")
	_assert(bool(report.get("ready", false)), "Synthetic garment bridge is not ready")

	var source_head := source.find_bone(StringName("head"))
	_assert(source_head >= 0, "Synthetic source head bone missing")
	var expected_rotation := Quaternion(Vector3.UP, 0.37)
	source.set_bone_pose_rotation(source_head, expected_rotation)
	var sync_result: Dictionary = bridge.sync_pose_now()
	_assert(bool(sync_result.get("success", false)), "Synthetic pose sync failed")
	_assert(int(sync_result.get("details", {}).get("copied_bones", 0)) == 5, "Synthetic pose sync copied unexpected bone count")

	var target: Skeleton3D = bridge.garment_skeletons[0]
	var target_head := target.find_bone(StringName("head"))
	_assert(target_head >= 0, "Synthetic target head bone missing")
	_assert(target.get_bone_pose_rotation(target_head).is_equal_approx(expected_rotation), "Synthetic target head pose did not follow source")
	_assert(not bool(report.get("moves_gameplay_body", true)), "Skinned bridge claims gameplay movement authority")
	_assert(not bool(report.get("reads_input", true)), "Skinned bridge claims input authority")
	_assert(not bool(report.get("owns_network_state", true)), "Skinned bridge claims network authority")

	var low_overlap_bridge = Bridge.new()
	host.add_child(low_overlap_bridge)
	var low_overlap_scene := _create_garment_scene(["alien_root", "alien_joint"])
	var low_result: Dictionary = low_overlap_bridge.setup(source, low_overlap_scene)
	_assert(not bool(low_result.get("success", true)), "Low-overlap garment was unexpectedly accepted")
	_assert(String(low_result.get("code", "")) == "GARMENT_BONE_OVERLAP_TOO_LOW", "Low-overlap garment returned wrong error")

	host.queue_free()


func _test_real_quaternius_outfit() -> void:
	_assert(ResourceLoader.exists(BASE_SCENE_PATH), "Real Quaternius base scene is missing")
	_assert(ResourceLoader.exists(GARMENT_SCENE_PATH), "Real Male_Peasant garment scene is missing")
	if not ResourceLoader.exists(BASE_SCENE_PATH) or not ResourceLoader.exists(GARMENT_SCENE_PATH):
		return

	var base_packed = load(BASE_SCENE_PATH)
	var garment_packed = load(GARMENT_SCENE_PATH)
	_assert(base_packed is PackedScene, "Real Quaternius base resource is not PackedScene")
	_assert(garment_packed is PackedScene, "Real Male_Peasant resource is not PackedScene")
	if not (base_packed is PackedScene and garment_packed is PackedScene):
		return

	var host := Node3D.new()
	root.add_child(host)
	var base_instance = (base_packed as PackedScene).instantiate()
	_assert(base_instance is Node3D, "Real Quaternius base root is not Node3D")
	if not base_instance is Node3D:
		if base_instance is Node:
			(base_instance as Node).free()
		host.queue_free()
		return
	host.add_child(base_instance)
	var source := _find_first_skeleton(base_instance)
	_assert(source != null, "Real Quaternius base skeleton missing")
	if source == null:
		host.queue_free()
		return

	var bridge = Bridge.new()
	host.add_child(bridge)
	var setup_result: Dictionary = bridge.setup(source, garment_packed as PackedScene)
	_assert(bool(setup_result.get("success", false)), "Real Male_Peasant skinned bridge setup failed")
	if not bool(setup_result.get("success", false)):
		host.queue_free()
		return

	var report: Dictionary = bridge.create_report()
	_assert(int(report.get("source_bone_count", 0)) == 65, "Real base source bone count changed from probed 65")
	_assert(int(report.get("garment_skeleton_count", 0)) == 1, "Male_Peasant should expose one garment skeleton")
	_assert(int(report.get("matched_bones", 0)) == 65, "Male_Peasant no longer has exact 65-bone overlap")
	_assert(int(report.get("garment_bone_count", 0)) == 65, "Male_Peasant garment bone count changed from probed 65")
	_assert(int(report.get("skinned_mesh_count", 0)) == 4, "Male_Peasant should expose four skinned meshes")
	var overlaps: Array = report.get("source_overlaps", [])
	_assert(overlaps.size() == 1 and is_equal_approx(float(overlaps[0]), 1.0), "Male_Peasant source overlap is not 1.0")

	var source_index := mini(10, source.get_bone_count() - 1)
	var source_name := source.get_bone_name(source_index)
	var target: Skeleton3D = bridge.garment_skeletons[0]
	var target_index := target.find_bone(source_name)
	_assert(target_index >= 0, "Real garment missing sampled source bone")
	if target_index >= 0:
		var expected_rotation := Quaternion(Vector3.RIGHT, 0.19)
		source.set_bone_pose_rotation(source_index, expected_rotation)
		var sync_result: Dictionary = bridge.sync_pose_now()
		_assert(bool(sync_result.get("success", false)), "Real garment pose sync failed")
		_assert(target.get_bone_pose_rotation(target_index).is_equal_approx(expected_rotation), "Real garment sampled bone did not follow source pose")

	host.queue_free()


func _create_skeleton(names: Array[String]) -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	for index in range(names.size()):
		skeleton.add_bone(names[index])
		if index > 0:
			skeleton.set_bone_parent(index, index - 1)
	return skeleton


func _create_garment_scene(names: Array[String]) -> PackedScene:
	var scene_root := Node3D.new()
	scene_root.name = "SyntheticGarment"
	var skeleton := _create_skeleton(names)
	skeleton.name = "Skeleton3D"
	scene_root.add_child(skeleton)
	skeleton.owner = scene_root

	var mesh := MeshInstance3D.new()
	mesh.name = "GarmentMesh"
	mesh.mesh = BoxMesh.new()
	mesh.skin = Skin.new()
	skeleton.add_child(mesh)
	mesh.owner = scene_root
	mesh.skeleton = mesh.get_path_to(skeleton)

	var packed := PackedScene.new()
	var error := packed.pack(scene_root)
	scene_root.free()
	return packed if error == OK else null


func _find_first_skeleton(root_node: Node) -> Skeleton3D:
	if root_node is Skeleton3D:
		return root_node as Skeleton3D
	for child in root_node.get_children():
		var found := _find_first_skeleton(child)
		if found != null:
			return found
	return null


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH7.8 skinned garment pose bridge: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH7.8 skinned garment pose bridge: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
