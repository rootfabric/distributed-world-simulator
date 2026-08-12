extends SceneTree

const RigType = preload("res://scripts/characters/presentation/substitutable_first_person_hand_rig.gd")
const ProviderType = preload("res://scripts/characters/presentation/skinned_first_person_hand_visual_provider.gd")
const PoseCatalogType = preload("res://scripts/characters/presentation/first_person_hand_pose_catalog.gd")
const FixtureScene = preload("res://tests/fixtures/fpe_s8_skinned_hand_visual.tscn")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := Node3D.new()
	get_root().add_child(root)

	_assert(FixtureScene != null, "S8 skinned fixture PackedScene failed to preload")
	var provider = ProviderType.new()
	var provider_setup: Dictionary = provider.setup(
		FixtureScene,
		"res://tests/fixtures/fpe_s8_skinned_hand_visual.tscn"
	)
	_assert(bool(provider_setup.get("success", false)), "S8 skinned provider setup failed")

	var rig = RigType.new()
	root.add_child(rig)
	var setup_result: Dictionary = rig.setup("right", 19, provider)
	_assert(bool(setup_result.get("success", false)), "S8 skinned rig setup failed")
	var report: Dictionary = rig.create_report()
	var provider_report: Dictionary = Dictionary(report.get("visual_provider", {}))
	_assert(int(report.get("bone_count", 0)) == 17, "S8 changed canonical 17-bone skeleton")
	_assert(int(report.get("visual_segments", 0)) == 1, "S8 expected one weighted skinned mesh")
	_assert(String(report.get("visual_provider_mode", "")) == "RESOURCE_SKINNED_RETARGETED", "S8 provider mode mismatch")
	_assert(String(provider_report.get("asset_schema", "")) == "planet_simulator.fpe_skinned_hand_visual_asset.v1", "S8 asset schema mismatch")
	_assert(String(provider_report.get("compatible_skeleton_schema", "")) == "planet_simulator.fpe_hand_skeleton.v1", "S8 skeleton schema mismatch")
	_assert(String(provider_report.get("rest_space_policy", "")) == "CANONICAL_COMPATIBLE_BIND_SPACE", "S8 rest-space policy mismatch")
	_assert(bool(provider_report.get("skinned", false)), "S8 provider did not declare skinned geometry")
	_assert(bool(provider_report.get("retargeted", false)), "S8 provider did not declare bind retargeting")
	_assert(int(provider_report.get("skin_bind_count", 0)) == 3, "S8 source skin bind count mismatch")
	_assert(int(provider_report.get("retargeted_bind_count", 0)) == 3, "S8 did not retarget all fixture binds")
	_assert(int(provider_report.get("identity_bind_count", -1)) == 0, "S8 fixture unexpectedly used identity binds")
	_assert(int(provider_report.get("weighted_surface_count", 0)) == 1, "S8 weighted mesh validation did not observe one surface")
	_assert(int(provider_report.get("skinned_mesh_count", 0)) == 1, "S8 skinned mesh count mismatch")

	var bindings: Dictionary = Dictionary(provider_report.get("resolved_bindings", {}))
	_assert(String(bindings.get("source_hand_palm", "")) == "Palm", "S8 palm retarget mismatch")
	_assert(String(bindings.get("source_index_01", "")) == "IndexProximal", "S8 index retarget mismatch")
	_assert(String(bindings.get("source_thumb_01", "")) == "ThumbProximal", "S8 thumb retarget mismatch")

	var visual: MeshInstance3D = rig._visual_segments[0] if not rig._visual_segments.is_empty() else null
	_assert(visual != null, "S8 skinned visual was not installed")
	if visual != null:
		_assert(visual.mesh is ArrayMesh, "S8 installed visual is not ArrayMesh")
		_assert(visual.skin != null, "S8 installed visual lost Skin")
		_assert(visual.skeleton == NodePath(".."), "S8 MeshInstance3D is not explicitly bound to canonical skeleton parent")
		_assert(visual.get_parent() == rig.skeleton, "S8 skinned mesh is not parented under canonical Skeleton3D")
		_assert(visual.get_layer_mask_value(19), "S8 skinned mesh missed viewmodel render layer")
		_assert(not visual.get_layer_mask_value(1), "S8 skinned mesh leaked onto default world layer")
		if visual.skin != null:
			_assert(visual.skin.get_bind_count() == 3, "S8 retargeted skin bind count changed")
			_assert(String(visual.skin.get_bind_name(0)) == "Palm", "S8 retargeted skin palm bind name mismatch")
			_assert(String(visual.skin.get_bind_name(1)) == "IndexProximal", "S8 retargeted skin index bind name mismatch")
			_assert(String(visual.skin.get_bind_name(2)) == "ThumbProximal", "S8 retargeted skin thumb bind name mismatch")
			_assert(visual.skin.get_bind_bone(0) == rig.skeleton.find_bone("Palm"), "S8 palm bind index does not target canonical bone")
			_assert(visual.skin.get_bind_bone(1) == rig.skeleton.find_bone("IndexProximal"), "S8 index bind index does not target canonical bone")
			_assert(visual.skin.get_bind_bone(2) == rig.skeleton.find_bone("ThumbProximal"), "S8 thumb bind index does not target canonical bone")
		if visual.mesh is ArrayMesh:
			var arrays: Array = (visual.mesh as ArrayMesh).surface_get_arrays(0)
			var bones_value: Variant = arrays[Mesh.ARRAY_BONES]
			var weights_value: Variant = arrays[Mesh.ARRAY_WEIGHTS]
			_assert(typeof(bones_value) == TYPE_PACKED_INT32_ARRAY, "S8 weighted mesh lost integer bone indices")
			_assert(typeof(weights_value) in [TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY], "S8 weighted mesh lost weights")

	var poses = PoseCatalogType.new()
	var pose_result: Dictionary = rig.apply_pose(poses.get_pose("support_cradle"))
	_assert(bool(pose_result.get("success", false)), "S8 skinned provider broke pose application")
	rig._process(0.2)
	var posed_report: Dictionary = rig.create_report()
	_assert(String(posed_report.get("settled_pose_id", "")) == "support_cradle", "S8 skinned rig did not settle support pose")
	_assert(not bool(posed_report.get("transitioning", true)), "S8 skinned rig kept processing after pose settled")

	var bad_root := Node3D.new()
	bad_root.set_meta("fpe_hand_visual_schema", "planet_simulator.fpe_skinned_hand_visual_asset.v1")
	bad_root.set_meta("fpe_compatible_skeleton_schema", "planet_simulator.fpe_hand_skeleton.v1")
	bad_root.set_meta("fpe_rest_space_policy", "CANONICAL_COMPATIBLE_BIND_SPACE")
	bad_root.set_meta("fpe_hand", "both")
	var bad_scene := PackedScene.new()
	var pack_error := bad_scene.pack(bad_root)
	_assert(pack_error == OK, "S8 failed to construct invalid no-mesh fixture")
	bad_root.free()
	var bad_provider = ProviderType.new()
	_assert(bool(bad_provider.setup(bad_scene).get("success", false)), "S8 invalid fixture provider setup unexpectedly failed early")
	var bad_result: Dictionary = bad_provider.install_visuals(rig.skeleton, "right", 19)
	_assert(not bool(bad_result.get("success", true)), "S8 invalid no-mesh asset did not fail closed")
	_assert(String(bad_result.get("error_code", "")) == "FPE_S8_SKINNED_HAND_NO_DIRECT_SKINNED_MESHES", "S8 invalid no-mesh error code mismatch")

	_assert(bool(provider_report.get("presentation_only", false)), "S8 provider is not presentation-only")
	_assert(not bool(provider_report.get("owns_item_state", true)), "S8 provider claims item ownership")
	_assert(not bool(provider_report.get("owns_network_state", true)), "S8 provider claims network ownership")
	_assert(not bool(provider_report.get("owns_gameplay_transform", true)), "S8 provider claims gameplay transform ownership")

	root.queue_free()
	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FPE R2 S8 skinned hand retarget provider: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FPE R2 S8 skinned hand retarget provider: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
