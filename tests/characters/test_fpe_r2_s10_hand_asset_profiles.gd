extends SceneTree

const RegistryType = preload("res://scripts/characters/presentation/first_person_hand_asset_registry.gd")
const ProfileType = preload("res://scripts/characters/presentation/first_person_hand_asset_profile.gd")
const ProviderType = preload("res://scripts/characters/presentation/profiled_skinned_first_person_hand_visual_provider.gd")
const RigType = preload("res://scripts/characters/presentation/substitutable_first_person_hand_rig.gd")
const PoseCatalogType = preload("res://scripts/characters/presentation/first_person_hand_pose_catalog.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = RegistryType.new()
	var load_result: Dictionary = registry.load_directory()
	_assert(bool(load_result.get("success", false)), "hand asset registry failed to load")
	var registry_report := registry.create_report()
	_assert(int(registry_report.get("profile_count", 0)) >= 2, "hand asset registry did not discover profiles")
	_assert(bool(registry_report.get("drop_in_profile_registration", false)), "registry does not advertise drop-in registration")
	_assert(int(registry_report.get("load_failure_count", -1)) == 0, "hand asset registry has load failures")
	var ids: Array = registry_report.get("profile_ids", [])
	_assert("s9-rounded-internal" in ids, "internal S9 profile missing")
	_assert("wrad-arms-cc0" in ids, "WRAD profile missing")

	var s9_resolved: Dictionary = registry.resolve("s9-rounded-internal")
	_assert(bool(s9_resolved.get("success", false)), "S9 profile did not resolve by id")
	var s9_details := Dictionary(s9_resolved.get("details", {}))
	var s9_profile := Dictionary(s9_details.get("profile", {}))
	_assert(String(s9_profile.get("schema", "")) == ProfileType.PROFILE_SCHEMA, "S9 profile schema mismatch")
	_assert(String(s9_profile.get("provider", "")) == ProfileType.PROVIDER_SKINNED_NAMED_BIND, "S9 provider kind mismatch")
	_assert(String(s9_profile.get("hand_layout", "")) == "BOTH_COMPATIBLE", "S9 hand layout mismatch")
	var s9_asset := Dictionary(s9_profile.get("asset", {}))
	var s9_scene_path := String(s9_asset.get("scene_path", ""))
	_assert(ResourceLoader.exists(s9_scene_path, "PackedScene"), "S9 profile asset scene missing")
	var s9_scene_value: Resource = load(s9_scene_path)
	_assert(s9_scene_value is PackedScene, "S9 profile asset is not PackedScene")

	var root := Node3D.new()
	get_root().add_child(root)
	var provider = ProviderType.new()
	var provider_setup: Dictionary = provider.setup_profiled(s9_scene_value as PackedScene, s9_profile, String(s9_details.get("profile_path", "")), s9_scene_path)
	_assert(bool(provider_setup.get("success", false)), "profiled S9 provider setup failed")
	var rig = RigType.new()
	root.add_child(rig)
	var rig_setup: Dictionary = rig.setup("right", 19, provider)
	_assert(bool(rig_setup.get("success", false)), "profiled S9 rig setup failed")
	var rig_report := rig.create_report()
	var provider_report := Dictionary(rig_report.get("visual_provider", {}))
	_assert(int(rig_report.get("bone_count", 0)) == 17, "profile layer changed canonical bone count")
	_assert(String(rig_report.get("visual_provider_mode", "")) == "RESOURCE_SKINNED_RETARGETED", "profiled provider mode mismatch")
	_assert(String(provider_report.get("profile_id", "")) == "s9-rounded-internal", "profile id not retained in provider report")
	_assert(bool(provider_report.get("portable_profile", false)), "provider does not advertise portable profile")
	_assert(String(provider_report.get("source_license", "")) == "LicenseRef-Project-Internal", "profile license metadata lost")
	_assert(not bool(provider_report.get("owns_item_state", true)), "profiled provider claims item state")
	_assert(not bool(provider_report.get("owns_network_state", true)), "profiled provider claims network state")
	_assert(not bool(provider_report.get("owns_gameplay_transform", true)), "profiled provider claims gameplay transform")
	var pose_catalog = PoseCatalogType.new()
	for pose_id in ["open", "beacon_pinch", "bulky_carry", "support_cradle"]:
		var pose_result: Dictionary = rig.apply_pose(pose_catalog.get_pose(pose_id))
		_assert(bool(pose_result.get("success", false)), "profiled hand pose failed: %s" % pose_id)
		rig._process(0.2)
		_assert(String(rig.create_report().get("settled_pose_id", "")) == pose_id, "profiled pose did not settle: %s" % pose_id)

	var wrad_resolved: Dictionary = registry.resolve("wrad-arms-cc0")
	_assert(bool(wrad_resolved.get("success", false)), "WRAD profile did not resolve")
	var wrad_details := Dictionary(wrad_resolved.get("details", {}))
	var wrad_profile := Dictionary(wrad_details.get("profile", {}))
	_assert(String(wrad_profile.get("status", "")) == "IMPORTED_INSPECTED_NATIVE_CALIBRATION_PROBE_READY", "WRAD profile status is not calibration-probe ready")
	_assert(String(wrad_profile.get("hand_layout", "")) == "PAIRED_SINGLE_MESH", "WRAD layout is not paired single mesh")
	_assert(String(Dictionary(wrad_profile.get("license", {})).get("spdx", "")) == "CC0-1.0", "WRAD license metadata mismatch")
	_assert(String(Dictionary(wrad_profile.get("license", {})).get("source_url", "")).contains("wriks.itch.io/wrad-arms"), "WRAD source metadata missing")
	var wrad_selection := Dictionary(wrad_profile.get("selection", {}))
	_assert(not bool(wrad_selection.get("inspection_required_before_runtime", true)), "WRAD still marked inspection-pending")
	_assert(Array(wrad_selection.get("mesh_node_paths", [])).has("arms/Skeleton3D/arms_mesh"), "WRAD inspected mesh path missing")
	var split := Dictionary(wrad_selection.get("paired_split", {}))
	_assert(String(split.get("strategy", "")) == "SKIN_BIND_SUFFIX", "WRAD paired split strategy mismatch")
	_assert(String(Dictionary(split.get("suffix_by_hand", {})).get("right", "")) == ".r", "WRAD right suffix mismatch")
	_assert(String(Dictionary(split.get("suffix_by_hand", {})).get("left", "")) == ".l", "WRAD left suffix mismatch")
	var wrad_retarget := Dictionary(wrad_profile.get("retarget", {}))
	_assert(String(wrad_retarget.get("rest_space_policy", "")) == ProfileType.REST_SOURCE_NATIVE_BIND_SPACE, "WRAD source-native bind-space policy missing")
	_assert(String(wrad_retarget.get("runtime_driver", "")) == ProfileType.DRIVER_NATIVE_SKELETON_POSE, "WRAD native skeleton runtime driver missing")
	var native_driver := Dictionary(wrad_retarget.get("native_pose_driver", {}))
	_assert(bool(native_driver.get("preserve_source_skin", false)), "WRAD native driver does not preserve source Skin")
	_assert(bool(native_driver.get("preserve_source_bind_poses", false)), "WRAD native driver does not preserve source bind poses")
	_assert(bool(native_driver.get("preserve_source_rest_hierarchy", false)), "WRAD native driver does not preserve source rest hierarchy")
	_assert(bool(native_driver.get("axis_calibrated_semantic_pose", false)), "WRAD native driver does not enable semantic axis calibration")
	_assert(not bool(native_driver.get("local_rest_basis_conversion", true)), "WRAD still enables incompatible local-rest conjugation")
	var by_hand := Dictionary(wrad_retarget.get("bone_map_by_hand", {}))
	_assert(Dictionary(by_hand.get("right", {})).size() >= 17, "WRAD right bone mapping incomplete")
	_assert(Dictionary(by_hand.get("left", {})).size() >= 17, "WRAD left bone mapping incomplete")
	_assert(String(Dictionary(Dictionary(by_hand.get("right", {}))).get("finger_index1.r", "")) == "IndexProximal", "WRAD right index mapping mismatch")
	_assert(String(Dictionary(Dictionary(by_hand.get("left", {}))).get("finger_index1.l", "")) == "IndexProximal", "WRAD left index mapping mismatch")
	var calibration := Dictionary(wrad_retarget.get("auto_calibration", {}))
	_assert(String(Dictionary(calibration.get("source_anchor_by_hand", {})).get("right", "")) == "wrist.r", "WRAD right calibration anchor mismatch")
	_assert(String(Dictionary(calibration.get("source_anchor_by_hand", {})).get("left", "")) == "wrist.l", "WRAD left calibration anchor mismatch")
	_assert(String(calibration.get("orientation_mode", "")) == "PRESERVE_SOURCE_BASIS", "WRAD root calibration does not preserve source basis")
	var pose_calibration := Dictionary(wrad_retarget.get("native_pose_calibration", {}))
	_assert(String(pose_calibration.get("mode", "")) == "AUTO_CHAIN_PALM_V1", "WRAD pose calibration mode missing")
	_assert(float(Dictionary(pose_calibration.get("default", {})).get("curl_scale", 0.0)) > 0.0, "WRAD default curl scale missing")
	_assert(Dictionary(pose_calibration.get("by_hand", {})).has("left"), "WRAD left calibration slot missing")
	_assert(Dictionary(pose_calibration.get("by_hand", {})).has("right"), "WRAD right calibration slot missing")
	var presentation := Dictionary(wrad_profile.get("presentation", {}))
	_assert(Dictionary(presentation.get("by_hand", {})).has("left"), "WRAD left presentation calibration slot missing")
	_assert(Dictionary(presentation.get("by_hand", {})).has("right"), "WRAD right presentation calibration slot missing")

	root.queue_free()
	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FPE R2 S10 portable hand asset profiles: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FPE R2 S10 portable hand asset profiles: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
