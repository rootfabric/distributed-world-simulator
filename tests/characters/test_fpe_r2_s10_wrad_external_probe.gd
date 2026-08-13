extends SceneTree

const ProfileType = preload("res://scripts/characters/presentation/first_person_hand_asset_profile.gd")
const ProviderType = preload("res://scripts/characters/presentation/profiled_skinned_first_person_hand_visual_provider_fix2.gd")
const RigType = preload("res://scripts/characters/presentation/substitutable_first_person_hand_rig.gd")
const PoseCatalogType = preload("res://scripts/characters/presentation/first_person_hand_pose_catalog.gd")
const PROFILE_PATH := "res://config/characters/hand-assets/wrad-arms-cc0.v1.json"
const EXPECTED_BIND_SPACE_FIX := "BAKE_SOURCE_TO_TARGET_BEFORE_CANONICAL_IBM"

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
		var provider_setup: Dictionary = provider.setup_profiled(
			resource as PackedScene,
			profile,
			PROFILE_PATH,
			scene_path
		)
		_assert(bool(provider_setup.get("success", false)), "WRAD %s provider setup failed: %s" % [hand, JSON.stringify(provider_setup)])
		var rig = RigType.new()
		host.add_child(rig)
		var rig_setup: Dictionary = rig.setup(hand, 19, provider)
		_assert(bool(rig_setup.get("success", false)), "WRAD %s rig setup failed: %s" % [hand, JSON.stringify(rig_setup)])
		if bool(rig_setup.get("success", false)):
			var rig_report := rig.create_report()
			var provider_report := Dictionary(rig_report.get("visual_provider", {}))
			var adaptation := Dictionary(provider_report.get("adaptation", {}))
			_assert(String(rig_report.get("visual_provider_mode", "")) == "RESOURCE_SKINNED_RETARGETED", "WRAD %s provider mode mismatch" % hand)
			_assert(bool(adaptation.get("paired_single_mesh_split", false)), "WRAD %s paired split marker missing" % hand)
			_assert(bool(adaptation.get("auto_canonical_rebind", false)), "WRAD %s auto rebind marker missing" % hand)
			_assert(bool(adaptation.get("calibration_baked_into_vertices", false)), "WRAD %s calibration was not baked into vertices" % hand)
			_assert(bool(adaptation.get("canonical_ibm_applied_after_vertex_bake", false)), "WRAD %s canonical IBM ordering marker missing" % hand)
			_assert(String(adaptation.get("bind_space_fix", "")) == EXPECTED_BIND_SPACE_FIX, "WRAD %s bind-space fix marker mismatch" % hand)
			_assert(int(adaptation.get("kept_faces", 0)) > 0, "WRAD %s kept no triangles" % hand)
			_assert(int(adaptation.get("dropped_faces", 0)) > 0, "WRAD %s did not remove opposite-side triangles" % hand)
			_assert(int(adaptation.get("compact_bind_count", 0)) > 0, "WRAD %s compact Skin is empty" % hand)
			_assert(int(adaptation.get("compact_bind_count", 0)) < 50, "WRAD %s did not compact the 50-bind paired Skin" % hand)
			_assert(float(adaptation.get("calibration_scale", 0.0)) > 0.0, "WRAD %s calibration scale is invalid" % hand)
			var pre_size := _vector3_from_report(adaptation.get("pre_bake_aabb_size", []))
			var post_size := _vector3_from_report(adaptation.get("post_bake_aabb_size", []))
			_assert(pre_size.length() > 0.0, "WRAD %s pre-bake AABB missing" % hand)
			_assert(post_size.length() > 0.0, "WRAD %s post-bake AABB missing" % hand)
			_assert(post_size.length() < pre_size.length(), "WRAD %s vertex bake did not apply calibration scale" % hand)
			var pose_result: Dictionary = rig.apply_pose(PoseCatalogType.new().get_pose("beacon_pinch"))
			_assert(bool(pose_result.get("success", false)), "WRAD %s beacon pose failed" % hand)
			rig._process(0.2)
			_assert(String(rig.create_report().get("settled_pose_id", "")) == "beacon_pinch", "WRAD %s beacon pose did not settle" % hand)
		host.remove_child(rig)
		rig.free()
	host.queue_free()
	_finish(true)


func _vector3_from_report(value: Variant) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


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