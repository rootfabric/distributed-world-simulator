extends SceneTree

const ViewmodelCatalogType = preload("res://scripts/characters/presentation/item_viewmodel_catalog.gd")
const GripCatalogType = preload("res://scripts/characters/presentation/held_item_grip_profile_catalog.gd")
const VisualFactoryType = preload("res://scripts/characters/presentation/held_item_visual_factory.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog = ViewmodelCatalogType.new()
	var grips = GripCatalogType.new()
	var factory = VisualFactoryType.new()

	var beacon: Dictionary = catalog.resolve(
		"survey_beacon",
		["signal", "equipment"],
		{},
		"",
		Color(1.0, 0.25, 0.05, 1.0)
	)
	_assert(String(beacon.get("profile_id", "")) == "beacon", "S2 beacon did not resolve beacon profile")
	_assert(String(beacon.get("visual_kind", "")) == "CYLINDER", "S2 beacon did not resolve cylinder silhouette")
	_assert(String(beacon.get("resolution_source", "")) == "HEURISTIC", "S2 beacon resolution source mismatch")
	_assert(not bool(beacon.get("owns_item_state", true)), "S2 viewmodel catalog incorrectly owns item state")
	_assert(not bool(beacon.get("owns_network_state", true)), "S2 viewmodel catalog incorrectly owns network state")

	var beacon_grip: Dictionary = grips.resolve("survey_beacon", beacon, ["signal"], {})
	_assert(String(beacon_grip.get("profile_id", "")) == "beacon_vertical", "S2 beacon grip profile mismatch")
	_assert(not bool(beacon_grip.get("owns_gameplay_transform", true)), "S2 grip catalog incorrectly owns gameplay transform")

	var flashlight: Dictionary = catalog.resolve("utility_flashlight", ["tool", "light"], {}, "")
	_assert(String(flashlight.get("profile_id", "")) == "flashlight", "S2 flashlight did not resolve flashlight profile")
	_assert(String(flashlight.get("visual_kind", "")) == "CYLINDER", "S2 flashlight silhouette mismatch")
	var flashlight_grip: Dictionary = grips.resolve("utility_flashlight", flashlight, ["tool", "light"], {})
	_assert(String(flashlight_grip.get("profile_id", "")) == "flashlight_forward", "S2 flashlight grip profile mismatch")
	_assert(String(flashlight_grip.get("profile_id", "")) != String(beacon_grip.get("profile_id", "")), "S2 distinct items collapsed to one grip profile")

	var metadata_profile: Dictionary = catalog.resolve(
		"custom_tool",
		[],
		{
			"held_visual_kind": "BOX",
			"held_visual_profile": "custom_panel",
			"held_dimensions": [0.31, 0.12, 0.07],
			"held_color": [0.2, 0.4, 0.8, 1.0],
			"held_grip_profile": "custom_grip",
			"held_fp_position": [0.01, 0.02, -0.25],
			"held_tp_rotation_deg": [1.0, 2.0, 3.0],
		},
		"res://unused_scene.tscn"
	)
	_assert(String(metadata_profile.get("profile_id", "")) == "custom_panel", "S2 metadata visual profile override failed")
	_assert(String(metadata_profile.get("resolution_source", "")) == "METADATA", "S2 metadata resolution source mismatch")
	_assert(String(metadata_profile.get("preferred_scene_path", "")) == "res://unused_scene.tscn", "S2 preferred scene path was not retained")
	var custom_grip: Dictionary = grips.resolve("custom_tool", metadata_profile, [], {
		"held_grip_profile": "custom_grip",
		"held_fp_position": [0.01, 0.02, -0.25],
		"held_tp_rotation_deg": [1.0, 2.0, 3.0],
	})
	_assert(String(custom_grip.get("profile_id", "")) == "custom_grip", "S2 metadata grip profile override failed")
	_assert(Array(Dictionary(custom_grip.get("first_person", {})).get("position", [])).size() == 3, "S2 first-person grip position missing")
	_assert(Array(Dictionary(custom_grip.get("third_person", {})).get("rotation_deg", [])).size() == 3, "S2 third-person grip rotation missing")

	var built: Dictionary = factory.create_proxy(beacon, Color.WHITE, "BeaconProxy", 20)
	_assert(bool(built.get("success", false)), "S2 visual factory failed to build beacon")
	var proxy_value: Variant = Dictionary(built.get("details", {})).get("proxy")
	_assert(proxy_value is MeshInstance3D, "S2 visual factory did not return MeshInstance3D")
	if proxy_value is MeshInstance3D:
		var proxy := proxy_value as MeshInstance3D
		_assert(proxy.mesh is CylinderMesh, "S2 beacon factory mesh is not CylinderMesh")
		_assert(proxy.get_layer_mask_value(20), "S2 factory did not apply requested render layer")
		_assert(not proxy.get_layer_mask_value(1), "S2 world proxy leaked onto default render layer")
		proxy.free()

	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FPE R2 S2 item viewmodel catalog: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FPE R2 S2 item viewmodel catalog: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
