extends SceneTree

const RigType = preload("res://scripts/characters/presentation/substitutable_first_person_hand_rig.gd")
const ProviderType = preload("res://scripts/characters/presentation/skinned_first_person_hand_visual_provider.gd")
const PoseCatalogType = preload("res://scripts/characters/presentation/first_person_hand_pose_catalog.gd")
const VolumetricFixture = preload("res://tests/fixtures/fpe_s9_volumetric_skinned_hand_visual.tscn")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := Node3D.new()
	get_root().add_child(root)

	var fixture: Node = VolumetricFixture.instantiate()
	_assert(fixture is Node3D, "S9 volumetric fixture did not instantiate as Node3D")
	root.add_child(fixture)
	_assert(String(fixture.get_meta("fpe_visual_quality", "")) == "ROUNDED_VOLUMETRIC_V2", "S9 Fix1 rounded visual-quality marker missing")
	var fixture_visual := fixture.get_node_or_null("VolumetricSkinnedHand") as MeshInstance3D
	_assert(fixture_visual != null, "S9 volumetric fixture MeshInstance3D missing")
	if fixture_visual != null:
		_assert(fixture_visual.mesh is ArrayMesh, "S9 volumetric fixture is not ArrayMesh")
		_assert(fixture_visual.skin != null, "S9 volumetric fixture Skin missing")
		if fixture_visual.mesh != null:
			var aabb := fixture_visual.mesh.get_aabb()
			_assert(aabb.size.x > 0.10, "S9 hand mesh width is unexpectedly flat")
			_assert(aabb.size.y > 0.045, "S9 rounded hand mesh thickness is unexpectedly flat")
			_assert(aabb.size.z > 0.20, "S9 hand mesh length is unexpectedly short")
			var arrays: Array = (fixture_visual.mesh as ArrayMesh).surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			_assert(vertices.size() >= 650, "S9 Fix1 full-hand mesh does not contain enough rounded volumetric vertices")
			_assert(normals.size() == vertices.size(), "S9 Fix1 rounded hand normal count mismatch")
			_assert(bones.size() == vertices.size() * 4, "S9 full-hand bone array is not four influences per vertex")
			_assert(weights.size() == vertices.size() * 4, "S9 full-hand weight array is not four influences per vertex")
		if fixture_visual.skin != null:
			_assert(fixture_visual.skin.get_bind_count() == 16, "S9 full-hand Skin must bind palm plus 15 finger bones")
	fixture.queue_free()

	var provider = ProviderType.new()
	var provider_setup: Dictionary = provider.setup(
		VolumetricFixture,
		"res://tests/fixtures/fpe_s9_volumetric_skinned_hand_visual.tscn"
	)
	_assert(bool(provider_setup.get("success", false)), "S9 skinned provider setup failed")

	var rig = RigType.new()
	root.add_child(rig)
	var rig_setup: Dictionary = rig.setup("right", 19, provider)
	_assert(bool(rig_setup.get("success", false)), "S9 volumetric skinned rig setup failed")
	var report: Dictionary = rig.create_report()
	var provider_report: Dictionary = Dictionary(report.get("visual_provider", {}))
	_assert(int(report.get("bone_count", 0)) == 17, "S9 changed canonical hand bone count")
	_assert(int(report.get("visual_segments", 0)) == 1, "S9 should install one weighted hand MeshInstance3D")
	_assert(String(report.get("visual_provider_mode", "")) == "RESOURCE_SKINNED_RETARGETED", "S9 provider mode mismatch")
	_assert(String(report.get("visual_provider_id", "")) == "fpe_s9_rounded_volumetric_skinned_hand_v2", "S9 Fix1 provider id mismatch")
	_assert(int(provider_report.get("skin_bind_count", 0)) == 16, "S9 retargeted Skin bind count mismatch")
	_assert(int(provider_report.get("retargeted_bind_count", 0)) == 16, "S9 all source hand binds must retarget")
	_assert(int(provider_report.get("weighted_surface_count", 0)) == 1, "S9 weighted surface count mismatch")
	_assert(bool(provider_report.get("skinned", false)), "S9 provider did not report skinned geometry")
	_assert(bool(provider_report.get("bone_driven", false)), "S9 provider did not report bone-driven geometry")
	_assert(bool(provider_report.get("presentation_only", false)), "S9 provider is not presentation-only")
	_assert(not bool(provider_report.get("owns_item_state", true)), "S9 provider claims item ownership")
	_assert(not bool(provider_report.get("owns_network_state", true)), "S9 provider claims network ownership")
	_assert(not bool(provider_report.get("owns_gameplay_transform", true)), "S9 provider claims gameplay transform ownership")
	var resolved: Dictionary = Dictionary(provider_report.get("resolved_bindings", {}))
	_assert(String(resolved.get("src_palm", "")) == "Palm", "S9 palm retarget missing")
	_assert(String(resolved.get("src_index_1", "")) == "IndexProximal", "S9 index proximal retarget missing")
	_assert(String(resolved.get("src_middle_2", "")) == "MiddleMiddle", "S9 middle chain retarget missing")
	_assert(String(resolved.get("src_ring_3", "")) == "RingDistal", "S9 ring distal retarget missing")
	_assert(String(resolved.get("src_pinky_3", "")) == "PinkyDistal", "S9 pinky distal retarget missing")
	_assert(String(resolved.get("src_thumb_2", "")) == "ThumbMiddle", "S9 thumb chain retarget missing")

	var poses = PoseCatalogType.new()
	for pose_id in ["open", "beacon_pinch", "bulky_carry", "support_cradle"]:
		var pose_result: Dictionary = rig.apply_pose(poses.get_pose(pose_id))
		_assert(bool(pose_result.get("success", false)), "S9 pose failed: %s" % pose_id)
		rig._process(0.2)
		_assert(String(rig.create_report().get("settled_pose_id", "")) == pose_id, "S9 pose did not settle: %s" % pose_id)

	root.queue_free()
	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FPE R2 S9 volumetric skinned hand asset: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FPE R2 S9 volumetric skinned hand asset: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
