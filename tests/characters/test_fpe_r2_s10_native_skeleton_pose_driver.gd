extends SceneTree

const ProviderType = preload("res://scripts/characters/presentation/native_skeleton_profiled_first_person_hand_visual_provider.gd")
const RigType = preload("res://scripts/characters/presentation/substitutable_first_person_hand_rig.gd")
const PoseCatalogType = preload("res://scripts/characters/presentation/first_person_hand_pose_catalog.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := _build_source_scene()
	_assert(scene != null, "synthetic native source scene was not built")
	var host := Node3D.new()
	get_root().add_child(host)
	for hand in ["right", "left"]:
		var provider = ProviderType.new()
		var setup_result: Dictionary = provider.setup_profiled(
			scene,
			_profile(),
			"res://synthetic/native-profile.json",
			"res://synthetic/native-hands.glb"
		)
		_assert(bool(setup_result.get("success", false)), "%s native provider setup failed" % hand)
		var rig = RigType.new()
		host.add_child(rig)
		var rig_setup: Dictionary = rig.setup(hand, 19, provider)
		_assert(bool(rig_setup.get("success", false)), "%s native rig setup failed: %s" % [hand, JSON.stringify(rig_setup)])
		if bool(rig_setup.get("success", false)):
			var report := rig.create_report()
			var visual := Dictionary(report.get("visual_provider", {}))
			_assert(String(report.get("visual_provider_mode", "")) == "RESOURCE_NATIVE_SKELETON_RETARGETED", "%s native mode mismatch" % hand)
			_assert(bool(visual.get("source_skin_preserved", false)), "%s source Skin not preserved" % hand)
			_assert(bool(visual.get("source_bind_poses_preserved", false)), "%s source bind poses not preserved" % hand)
			_assert(bool(visual.get("source_skeleton_preserved", false)), "%s source skeleton not preserved" % hand)
			_assert(not bool(visual.get("canonical_skin_rebind", true)), "%s unexpectedly canonical-rebound Skin" % hand)
			_assert(int(visual.get("native_pose_pair_count", 0)) == 15, "%s native pose map is incomplete" % hand)
			_assert(provider._native_skeleton != null and provider._native_skeleton.get_bone_count() == 33, "%s native skeleton hierarchy was not preserved" % hand)
			_assert(provider._native_mesh != null and provider._native_mesh.skin != null, "%s native split mesh missing Skin" % hand)
			if provider._native_mesh != null and provider._native_mesh.skin != null:
				_assert(provider._native_mesh.skin.get_bind_count() == 2, "%s compact source Skin bind count mismatch" % hand)
				_assert(_skin_bind_pose_matches_source(provider._native_mesh.skin, provider._native_skeleton), "%s source inverse bind matrices changed" % hand)
			var source_index_name := "finger_index1.%s" % ("r" if hand == "right" else "l")
			var source_index := provider._native_skeleton.find_bone(source_index_name)
			_assert(source_index >= 0, "%s source index bone missing" % hand)
			var before := provider._native_skeleton.get_bone_pose_rotation(source_index) if source_index >= 0 else Quaternion.IDENTITY
			var pose_result: Dictionary = rig.apply_pose(PoseCatalogType.new().get_pose("beacon_pinch"))
			_assert(bool(pose_result.get("success", false)), "%s native beacon pose failed" % hand)
			rig._process(0.2)
			var after := provider._native_skeleton.get_bone_pose_rotation(source_index) if source_index >= 0 else Quaternion.IDENTITY
			_assert(before.angle_to(after) > 0.01, "%s native finger pose did not change" % hand)
			var settled := rig.create_report()
			var settled_visual := Dictionary(settled.get("visual_provider", {}))
			_assert(String(settled.get("settled_pose_id", "")) == "beacon_pinch", "%s canonical pose did not settle" % hand)
			_assert(int(settled_visual.get("last_driven_bone_count", 0)) == 15, "%s did not drive 15 native finger bones" % hand)
		host.remove_child(rig)
		rig.free()
	host.queue_free()
	_finish()


func _build_source_scene() -> PackedScene:
	var root := Node3D.new()
	root.name = "SyntheticNativeHands"
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	root.add_child(skeleton)
	skeleton.owner = root
	var root_bone := _add_bone(skeleton, "root", -1, Transform3D.IDENTITY)
	var wrists: Dictionary = {}
	var middle_base: Dictionary = {}
	for hand_suffix in ["r", "l"]:
		var side := 1.0 if hand_suffix == "r" else -1.0
		var wrist := _add_bone(skeleton, "wrist.%s" % hand_suffix, root_bone, Transform3D(Basis.IDENTITY, Vector3(side, 0.0, 0.0)))
		wrists[hand_suffix] = wrist
		for finger in ["thumb", "index", "middle", "ring", "pinky"]:
			var parent := wrist
			for segment in range(1, 4):
				var basis := Basis.from_euler(Vector3(0.0, deg_to_rad(10.0 * side), deg_to_rad(7.0 * side))) if segment == 1 else Basis.IDENTITY
				var origin := Vector3(0.0, 0.0, -0.45) if segment > 1 else Vector3(0.05 * side, 0.0, -0.25)
				var bone := _add_bone(skeleton, "finger_%s%d.%s" % [finger, segment, hand_suffix], parent, Transform3D(basis, origin))
				if finger == "middle" and segment == 1:
					middle_base[hand_suffix] = bone
				parent = bone

	var vertices := PackedVector3Array([
		Vector3(0.85, -0.10, 0.0), Vector3(1.15, -0.10, 0.0), Vector3(1.0, 0.10, -0.8),
		Vector3(-1.15, -0.10, 0.0), Vector3(-0.85, -0.10, 0.0), Vector3(-1.0, 0.10, -0.8),
	])
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	for index in range(vertices.size()):
		normals.append(Vector3.UP)
		uvs.append(Vector2(float(index % 3) * 0.5, float(index / 3)))

	# Skin bind indexes: 0=root, 1=wrist.r, 2=middle.r, 3=wrist.l, 4=middle.l.
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
	var bind_bones: Array[int] = [root_bone, int(wrists.r), int(middle_base.r), int(wrists.l), int(middle_base.l)]
	skin.set_bind_count(bind_bones.size())
	for bind_index in range(bind_bones.size()):
		var bone_index := bind_bones[bind_index]
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
	var maps := {"right": {}, "left": {}}
	for hand in ["right", "left"]:
		var suffix := "r" if hand == "right" else "l"
		var hand_map: Dictionary = {}
		for finger in ["thumb", "index", "middle", "ring", "pinky"]:
			var canonical_prefix := finger.capitalize()
			hand_map["finger_%s1.%s" % [finger, suffix]] = "%sProximal" % canonical_prefix
			hand_map["finger_%s2.%s" % [finger, suffix]] = "%sMiddle" % canonical_prefix
			hand_map["finger_%s3.%s" % [finger, suffix]] = "%sDistal" % canonical_prefix
		hand_map["wrist.%s" % suffix] = "Palm"
		maps[hand] = hand_map
	return {
		"schema": "planet_simulator.fpe_hand_asset_profile.v1",
		"profile_id": "synthetic-native",
		"display_name": "Synthetic Native Hands",
		"status": "TEST_ONLY",
		"provider": "SKINNED_NAMED_BIND",
		"hand_layout": "PAIRED_SINGLE_MESH",
		"license": {"spdx": "LicenseRef-Test", "source_url": "", "redistributable": false, "attribution_required": false},
		"asset": {"scene_path": "res://synthetic/native-hands.glb", "format": "glb", "external": false},
		"selection": {
			"mesh_node_paths": ["Skeleton3D/paired_mesh"],
			"mesh_node_paths_by_hand": {},
			"recursive_mesh_discovery": false,
			"inspection_required_before_runtime": false,
			"paired_split": {
				"strategy": "SKIN_BIND_SUFFIX",
				"suffix_by_hand": {"left": ".l", "right": ".r"},
				"shared_bind_names": ["root"]
			}
		},
		"retarget": {
			"runtime_driver": "NATIVE_SKELETON_POSE",
			"rest_space_policy": "SOURCE_NATIVE_BIND_SPACE",
			"bone_map": {"root": "HandRoot"},
			"bone_map_by_hand": maps,
			"auto_calibration": {
				"source_anchor_by_hand": {"left": "wrist.l", "right": "wrist.r"},
				"source_scale_reference_by_hand": {"left": "finger_middle1.l", "right": "finger_middle1.r"},
				"target_anchor": "Palm",
				"target_scale_reference": "MiddleProximal",
				"uniform_scale_multiplier": 1.0
			}
		},
		"presentation": {"position": [0.0, 0.0, 0.0], "rotation_degrees": [0.0, 0.0, 0.0], "scale": [1.0, 1.0, 1.0]}
	}


func _skin_bind_pose_matches_source(skin: Skin, skeleton: Skeleton3D) -> bool:
	for bind_index in range(skin.get_bind_count()):
		var bone_index := skin.get_bind_bone(bind_index)
		if bone_index < 0 or bone_index >= skeleton.get_bone_count():
			return false
		var expected := skeleton.get_bone_global_rest(bone_index).affine_inverse()
		var actual := skin.get_bind_pose(bind_index)
		if not actual.is_equal_approx(expected):
			return false
	return true


func _add_bone(skeleton: Skeleton3D, name: String, parent: int, rest: Transform3D) -> int:
	var index := skeleton.add_bone(name)
	if parent >= 0:
		skeleton.set_bone_parent(index, parent)
	skeleton.set_bone_rest(index, rest)
	return index


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FPE R2 S10 native skeleton pose driver: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FPE R2 S10 native skeleton pose driver: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
