extends SceneTree

const ProfileType = preload("res://scripts/characters/presentation/first_person_hand_asset_profile.gd")
const ProviderType = preload("res://scripts/characters/presentation/calibrated_native_skeleton_first_person_hand_visual_provider.gd")
const RigType = preload("res://scripts/characters/presentation/substitutable_first_person_hand_rig.gd")
const PoseCatalogType = preload("res://scripts/characters/presentation/first_person_hand_pose_catalog.gd")
const PROFILE_PATH := "res://config/characters/hand-assets/wrad-arms-cc0.v1.json"

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var loaded: Dictionary = ProfileType.load_from_path(PROFILE_PATH)
	_assert(bool(loaded.get("success", false)), "WRAD profile failed to load")
	if not bool(loaded.get("success", false)):
		_finish(false)
		return
	var details := Dictionary(loaded.get("details", {}))
	var profile := Dictionary(details.get("profile", {}))
	var scene_path := String(Dictionary(profile.get("asset", {})).get("scene_path", ""))
	if not ResourceLoader.exists(scene_path, "PackedScene"):
		_assert(true, "external WRAD asset is optional in clean repository checkout")
		print("FPE R2 S10 WRAD external probe: PASS (%d assertions, external_asset_present=false)" % assertions)
		quit(0)
		return
	var resource: Resource = load(scene_path)
	_assert(resource is PackedScene, "installed WRAD resource is not a PackedScene")
	if not resource is PackedScene:
		_finish(true)
		return

	var host := Node3D.new()
	get_root().add_child(host)
	for hand in ["right", "left"]:
		var provider = ProviderType.new()
		var provider_setup: Dictionary = provider.setup_profiled(resource as PackedScene, profile, PROFILE_PATH, scene_path)
		_assert(bool(provider_setup.get("success", false)), "WRAD %s calibrated provider setup failed: %s" % [hand, JSON.stringify(provider_setup)])
		var rig = RigType.new()
		host.add_child(rig)
		var rig_setup: Dictionary = rig.setup(hand, 19, provider)
		_assert(bool(rig_setup.get("success", false)), "WRAD %s calibrated rig setup failed: %s" % [hand, JSON.stringify(rig_setup)])
		if bool(rig_setup.get("success", false)):
			var rig_report := rig.create_report()
			var provider_report := Dictionary(rig_report.get("visual_provider", {}))
			_assert(String(rig_report.get("visual_provider_mode", "")) == "RESOURCE_NATIVE_SKELETON_RETARGETED", "WRAD %s native provider mode mismatch" % hand)
			_assert(String(provider_report.get("runtime_driver", "")) == ProfileType.DRIVER_NATIVE_SKELETON_POSE, "WRAD %s native driver marker missing" % hand)
			_assert(String(provider_report.get("rest_space_policy", "")) == ProfileType.REST_SOURCE_NATIVE_BIND_SPACE, "WRAD %s source bind-space marker missing" % hand)
			_assert(bool(provider_report.get("source_skin_preserved", false)), "WRAD %s source Skin was not preserved" % hand)
			_assert(bool(provider_report.get("source_bind_poses_preserved", false)), "WRAD %s source bind poses were not preserved" % hand)
			_assert(bool(provider_report.get("source_skeleton_preserved", false)), "WRAD %s source skeleton was not preserved" % hand)
			_assert(not bool(provider_report.get("canonical_skin_rebind", true)), "WRAD %s still performs canonical Skin rebind" % hand)
			_assert(String(provider_report.get("pose_calibration_mode", "")) == "AUTO_CHAIN_PALM_V1", "WRAD %s pose calibration mode missing" % hand)
			_assert(String(provider_report.get("root_orientation_mode", "")) == "PRESERVE_SOURCE_BASIS", "WRAD %s source root basis is not preserved" % hand)
			_assert(bool(provider_report.get("open_pose_preserves_source_rest", false)), "WRAD %s open/rest preservation marker missing" % hand)
			_assert(int(provider_report.get("native_pose_pair_count", 0)) == 15, "WRAD %s native finger mapping is incomplete" % hand)
			_assert(int(provider_report.get("kept_faces", 0)) > 0, "WRAD %s kept no triangles" % hand)
			_assert(int(provider_report.get("dropped_faces", 0)) > 0, "WRAD %s did not remove opposite-side triangles" % hand)
			_assert(int(provider_report.get("compact_bind_count", 0)) > 0, "WRAD %s compact Skin is empty" % hand)
			_assert(int(provider_report.get("compact_bind_count", 0)) < 50, "WRAD %s did not compact the 50-bind paired Skin" % hand)
			_assert(float(provider_report.get("root_calibration_scale", 0.0)) > 0.0, "WRAD %s root calibration scale is invalid" % hand)
			var source_index_name := "finger_index1.%s" % ("r" if hand == "right" else "l")
			var source_index := provider._native_skeleton.find_bone(source_index_name)
			_assert(source_index >= 0, "WRAD %s source index bone missing" % hand)
			var open_result: Dictionary = rig.apply_pose(PoseCatalogType.new().get_pose("open"))
			_assert(bool(open_result.get("success", false)), "WRAD %s open pose failed" % hand)
			rig._process(0.2)
			var open_rotation := provider._native_skeleton.get_bone_pose_rotation(source_index) if source_index >= 0 else Quaternion.IDENTITY
			_assert(Quaternion.IDENTITY.angle_to(open_rotation) < 0.001, "WRAD %s open pose twists source index bone" % hand)
			var initial_sync_count := int(Dictionary(rig.create_report().get("visual_provider", {})).get("native_pose_sync_count", 0))
			var pose_result: Dictionary = rig.apply_pose(PoseCatalogType.new().get_pose("beacon_pinch"))
			_assert(bool(pose_result.get("success", false)), "WRAD %s beacon pose failed" % hand)
			rig._process(0.2)
			var settled_report := rig.create_report()
			var settled_provider := Dictionary(settled_report.get("visual_provider", {}))
			_assert(String(settled_report.get("settled_pose_id", "")) == "beacon_pinch", "WRAD %s beacon pose did not settle" % hand)
			_assert(int(settled_provider.get("native_pose_sync_count", 0)) > initial_sync_count, "WRAD %s native skeleton was not synced during pose transition" % hand)
			_assert(int(settled_provider.get("last_driven_bone_count", 0)) == 15, "WRAD %s did not drive all 15 finger bones" % hand)
			_assert(float(settled_provider.get("max_native_pose_angle_deg", 999.0)) <= 90.1, "WRAD %s calibrated pose exceeded safe angle bound" % hand)
		host.remove_child(rig)
		rig.free()
	host.queue_free()
	_finish(true)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish(external_present: bool) -> void:
	if failures.is_empty():
		print("FPE R2 S10 WRAD external probe: PASS (%d assertions, external_asset_present=%s)" % [assertions, str(external_present).to_lower()])
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FPE R2 S10 WRAD external probe: FAIL (%d failures, %d assertions, external_asset_present=%s)" % [failures.size(), assertions, str(external_present).to_lower()])
	quit(1)
