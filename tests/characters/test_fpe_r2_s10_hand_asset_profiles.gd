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
	_assert("wrad-arms-cc0" in ids, "WRAD profile template missing")

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
	var provider_setup: Dictionary = provider.setup_profiled(
		s9_scene_value as PackedScene,
		s9_profile,
		String(s9_details.get("profile_path", "")),
		s9_scene_path
	)
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
	_assert(bool(wrad_resolved.get("success", false)), "WRAD template did not resolve")
	var wrad_details := Dictionary(wrad_resolved.get("details", {}))
	var wrad_profile := Dictionary(wrad_details.get("profile", {}))
	_assert(String(wrad_profile.get("status", "")).contains("INSPECTION_PENDING"), "WRAD template status is not inspection pending")
	_assert(String(Dictionary(wrad_profile.get("license", {})).get("spdx", "")) == "CC0-1.0", "WRAD license metadata mismatch")
	_assert(String(Dictionary(wrad_profile.get("license", {})).get("source_url", "")).contains("wriks.itch.io/wrad-arms"), "WRAD source metadata missing")
	_assert(String(Dictionary(wrad_profile.get("retarget", {})).get("rest_space_policy", "")) == ProfileType.REST_INSPECT_REQUIRED, "WRAD should remain fail-closed pending inspection")
	_assert(Dictionary(Dictionary(wrad_profile.get("retarget", {})).get("bone_map", {})).is_empty(), "WRAD template must not invent a bone map before inspection")
	var wrad_probe_provider = ProviderType.new()
	var wrad_probe: Dictionary = wrad_probe_provider.setup_profiled(
		s9_scene_value as PackedScene,
		wrad_profile,
		String(wrad_details.get("profile_path", "")),
		String(Dictionary(wrad_profile.get("asset", {})).get("scene_path", ""))
	)
	_assert(not bool(wrad_probe.get("success", true)), "uncalibrated WRAD profile must fail closed")
	_assert(String(wrad_probe.get("error_code", "")) == "FPE_HAND_PROFILE_REST_SPACE_NOT_CALIBRATED", "WRAD fail-closed reason mismatch")

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
