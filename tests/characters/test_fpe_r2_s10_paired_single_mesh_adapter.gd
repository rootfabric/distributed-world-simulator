extends SceneTree

const ProviderType = preload("res://scripts/characters/presentation/profiled_skinned_first_person_hand_visual_provider.gd")
const RigType = preload("res://scripts/characters/presentation/substitutable_first_person_hand_rig.gd")
const PoseCatalogType = preload("res://scripts/characters/presentation/first_person_hand_pose_catalog.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var paired_scene := _build_paired_scene()
	_assert(paired_scene != null, "synthetic paired scene was not built")
	var profile := _profile()
	var host := Node3D.new()
	get_root().add_child(host)
	for hand in ["right", "left"]:
		var provider = ProviderType.new()
		var provider_setup: Dictionary = provider.setup_profiled(
			paired_scene,
			profile,
			"res://synthetic/paired-profile.json",
			"res://synthetic/paired-hands.glb"
		)
		_assert(bool(provider_setup.get("success", false)), "%s paired provider setup failed" % hand)
		var rig = RigType.new()
		host.add_child(rig)
		var rig_setup: Dictionary = rig.setup(hand, 19, provider)
		_assert(bool(rig_setup.get("success", false)), "%s paired rig setup failed: %s" % [hand, JSON.stringify(rig_setup)])
		var report := rig.create_report()
		var provider_report := Dictionary(report.get("visual_provider", {}))
		var adaptation := Dictionary(provider_report.get("adaptation", {}))
		_assert(String(report.get("visual_provider_mode", "")) == "RESOURCE_SKINNED_RETARGETED", "%s mode mismatch" % hand)
		_assert(bool(provider_report.get("paired_single_mesh_split", false)), "%s paired split marker missing" % hand)
		_assert(bool(provider_report.get("auto_canonical_rebind", false)), "%s auto rebind marker missing" % hand)
		_assert(int(adaptation.get("kept_faces", 0)) == 1, "%s did not keep exactly one side triangle" % hand)
		_assert(int(adaptation.get("dropped_faces", 0)) == 1, "%s did not drop opposite side triangle" % hand)
		_assert(int(adaptation.get("compact_bind_count", 0)) == 2, "%s compact bind count mismatch" % hand)
		_assert(float(adaptation.get("calibration_scale", 0.0)) > 0.01, "%s calibration scale was not computed" % hand)
		var installed_meshes := _direct_skinned_meshes(rig.skeleton)
		_assert(installed_meshes.size() == 1, "%s expected one installed split mesh" % hand)
		if installed_meshes.size() == 1:
			var installed := installed_meshes[0]
			_assert(installed.skin != null and installed.skin.get_bind_count() == 2, "%s installed compact Skin mismatch" % hand)
			_assert(installed.mesh is ArrayMesh, "%s installed mesh is not ArrayMesh" % hand)
			if installed.mesh is ArrayMesh:
				_assert((installed.mesh as ArrayMesh).surface_get_array_len(0) == 3, "%s split mesh should contain one triangle" % hand)
		var pose_catalog = PoseCatalogType.new()
		var pose_result: Dictionary = rig.apply_pose(pose_catalog.get_pose("beacon_pinch"))
		_assert(bool(pose_result.get("success", false)), "%s pose failed after paired adaptation" % hand)
		rig._process(0.2)
		_assert(String(rig.create_report().get("settled_pose_id", "")) == "beacon_pinch", "%s pose did not settle" % hand)
		host.remove_child(rig)
		rig.free()
	host.queue_free()
	_finish()


func _build_paired_scene() -> PackedScene:
	var root := Node3D.new()
	root.name = "SyntheticPairedHands"
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	root.add_child(skeleton)
	skeleton.owner = root
	var root_bone := _add_bone(skeleton, "root", -1, Transform3D.IDENTITY)
	var wrist_r := _add_bone(skeleton, "wrist.r", root_bone, Transform3D(Basis.IDENTITY, Vector3(1.0, 0.0, 0.0)))
	var middle_r := _add_bone(skeleton, "finger_middle1.r", wrist_r, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -1.0)))
	var wrist_l := _add_bone(skeleton, "wrist.l", root_bone, Transform3D(Basis.IDENTITY, Vector3(-1.0, 0.0, 0.0)))
	var middle_l := _add_bone(skeleton, "finger_middle1.l", wrist_l, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -1.0)))

	var vertices := PackedVector3Array([
		Vector3(0.85, -0.10, 0.0), Vector3(1.15, -0.10, 0.0), Vector3(1.0, 0.10, -1.0),
		Vector3(-1.15, -0.10, 0.0), Vector3(-0.85, -0.10, 0.0), Vector3(-1.0, 0.10, -1.0),
	])
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	for index in range(vertices.size()):
		normals.append(Vector3.UP)
		uvs.append(Vector2(float(index % 3) * 0.5, float(index / 3)))
	var bones := PackedInt32Array([
		1, 2, 1, 1, 1, 2, 1, 1, 2, 1, 2, 2,
		3, 4, 3, 3, 3, 4, 3, 3, 4, 3, 4, 4,
	])
	var weights := PackedFloat32Array([
		0.8, 0.2, 0.0, 0.0, 0.8, 0.2, 0.0, 0.0, 0.2, 0.8, 0.0, 0.0,
		0.8, 0.2, 0.0, 0.0, 0.8, 0.2, 0.0, 0.0, 0.2, 0.8, 0.0, 0.0,
	])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 3, 4, 5])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var skin := Skin.new()
	var source_bones := [root_bone, wrist_r, middle_r, wrist_l, middle_l]
	skin.set_bind_count(source_bones.size())
	for bind_index in range(source_bones.size()):
		var bone_index := int(source_bones[bind_index])
		skin.set_bind_name(bind_index, skeleton.get_bone_name(bone_index))
		skin.set_bind_bone(bind_index, bone_index)
		skin.set_bind_pose(bind_index, skeleton.get_bone_global_rest(bone_index).affine_inverse())

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "paired_mesh"
	mesh_instance.mesh = mesh
	mesh_instance.skin = skin
	mesh_instance.skeleton = NodePath("..")
	skeleton.add_child(mesh_instance)
	mesh_instance.owner = root
	var packed := PackedScene.new()
	var error := packed.pack(root)
	root.free()
	return packed if error == OK else null


func _profile() -> Dictionary:
	return {
		"schema": "planet_simulator.fpe_hand_asset_profile.v1",
		"profile_id": "synthetic-paired",
		"display_name": "Synthetic Paired Hands",
		"status": "TEST_ONLY",
		"provider": "SKINNED_NAMED_BIND",
		"hand_layout": "PAIRED_SINGLE_MESH",
		"license": {"spdx": "LicenseRef-Test", "source_url": "", "redistributable": false, "attribution_required": false},
		"asset": {"scene_path": "res://synthetic/paired-hands.glb", "format": "glb", "external": false},
		"selection": {
			"mesh_node_paths": ["Skeleton3D/paired_mesh"],
			"mesh_node_paths_by_hand": {},
			"recursive_mesh_discovery": false,
			"inspection_required_before_runtime": false,
			"paired_split": {
				"strategy": "SKIN_BIND_SUFFIX",
				"suffix_by_hand": {"left": ".l", "right": ".r"},
				"shared_bind_names": ["root"],
			},
		},
		"retarget": {
			"rest_space_policy": "AUTO_CANONICAL_REBIND",
			"bone_map": {"root": "HandRoot"},
			"bone_map_by_hand": {
				"right": {"wrist.r": "Palm", "finger_middle1.r": "MiddleProximal"},
				"left": {"wrist.l": "Palm", "finger_middle1.l": "MiddleProximal"},
			},
			"unmapped_used_bind_target_by_hand": {"left": "HandRoot", "right": "HandRoot"},
			"auto_calibration": {
				"source_anchor_by_hand": {"left": "wrist.l", "right": "wrist.r"},
				"source_scale_reference_by_hand": {"left": "finger_middle1.l", "right": "finger_middle1.r"},
				"target_anchor": "Palm",
				"target_scale_reference": "MiddleProximal",
				"uniform_scale_multiplier": 1.0,
			},
		},
		"presentation": {"position": [0.0, 0.0, 0.0], "rotation_degrees": [0.0, 0.0, 0.0], "scale": [1.0, 1.0, 1.0]},
	}


func _add_bone(skeleton: Skeleton3D, name: String, parent: int, rest: Transform3D) -> int:
	var index := skeleton.add_bone(name)
	if parent >= 0:
		skeleton.set_bone_parent(index, parent)
	skeleton.set_bone_rest(index, rest)
	return index


func _direct_skinned_meshes(skeleton: Skeleton3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if skeleton == null:
		return result
	for child in skeleton.get_children():
		if child is MeshInstance3D:
			result.append(child as MeshInstance3D)
	return result


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FPE R2 S10 paired single-mesh adapter: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FPE R2 S10 paired single-mesh adapter: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
