extends SceneTree

const EmbodimentType = preload("res://scripts/characters/presentation/skinned_resource_configurable_two_hand_first_person_embodiment.gd")
const ViewmodelCatalogType = preload("res://scripts/characters/presentation/item_viewmodel_catalog.gd")
const GripCatalogType = preload("res://scripts/characters/presentation/held_item_grip_profile_catalog.gd")
const FixtureScene = preload("res://tests/fixtures/fpe_s8_skinned_hand_visual.tscn")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var viewmodel := Node3D.new()
	root.add_child(viewmodel)
	var embodiment = EmbodimentType.new()
	root.add_child(embodiment)
	embodiment.viewmodel_root = viewmodel

	embodiment.left_hand_root = Node3D.new()
	embodiment.left_hand_root.name = "LeftHandViewmodel"
	viewmodel.add_child(embodiment.left_hand_root)
	embodiment.left_held_root = Node3D.new()
	embodiment.left_held_root.name = "LeftGrip"
	embodiment.left_hand_root.add_child(embodiment.left_held_root)

	embodiment.right_hand_root = Node3D.new()
	embodiment.right_hand_root.name = "RightHandViewmodel"
	viewmodel.add_child(embodiment.right_hand_root)
	embodiment.right_held_root = Node3D.new()
	embodiment.right_held_root.name = "RightGrip"
	embodiment.right_hand_root.add_child(embodiment.right_held_root)

	for hand in ["left", "right"]:
		var configure_result: Dictionary = embodiment.configure_skinned_hand_visual_resource(
			hand,
			FixtureScene,
			"res://tests/fixtures/fpe_s8_skinned_hand_visual.tscn"
		)
		_assert(bool(configure_result.get("success", false)), "S8 skinned viewmodel resource configuration failed for %s" % hand)

	var left_setup: Dictionary = embodiment._install_hand_rig("left", embodiment.left_hand_root, 19)
	var right_setup: Dictionary = embodiment._install_hand_rig("right", embodiment.right_hand_root, 19)
	_assert(bool(left_setup.get("success", false)), "S8 configurable left skinned rig setup failed")
	_assert(bool(right_setup.get("success", false)), "S8 configurable right skinned rig setup failed")
	embodiment._capture_left_default()

	var left_rig = embodiment._hand_rig_by_hand.get("left")
	var right_rig = embodiment._hand_rig_by_hand.get("right")
	_assert(left_rig != null, "S8 configurable left rig missing")
	_assert(right_rig != null, "S8 configurable right rig missing")
	if left_rig != null:
		_assert(String(left_rig.create_report().get("visual_provider_mode", "")) == "RESOURCE_SKINNED_RETARGETED", "S8 left rig did not use skinned provider")
	if right_rig != null:
		_assert(String(right_rig.create_report().get("visual_provider_mode", "")) == "RESOURCE_SKINNED_RETARGETED", "S8 right rig did not use skinned provider")

	var config_report: Dictionary = embodiment.get_skinned_hand_visual_report()
	var configured: Dictionary = Dictionary(config_report.get("configured", {}))
	_assert(bool(Dictionary(configured.get("left", {})).get("configured", false)), "S8 left skinned config not surfaced")
	_assert(bool(Dictionary(configured.get("right", {})).get("configured", false)), "S8 right skinned config not surfaced")
	_assert(bool(config_report.get("skinned_resource_supported", false)), "S8 configurable viewmodel did not declare skinned resource support")

	var visuals = ViewmodelCatalogType.new()
	var grips = GripCatalogType.new()
	var mount_visual: Dictionary = visuals.resolve(
		"beacon_mount_base",
		["assembly_root", "placeable", "mount_socket"],
		{},
		"",
		Color(0.15, 0.45, 0.65, 1.0)
	)
	var mount_grip: Dictionary = grips.resolve(
		"beacon_mount_base",
		mount_visual,
		["assembly_root", "placeable", "mount_socket"],
		{}
	)
	var mount_result: Dictionary = embodiment.set_catalogued_hand_item(
		"right",
		"item/player/a/mount-bases",
		"Mount Base",
		Color(0.15, 0.45, 0.65, 1.0),
		mount_visual,
		mount_grip
	)
	_assert(bool(mount_result.get("success", false)), "S8 skinned viewmodel broke mount-base held item application")
	_assert(bool(mount_result.get("details", {}).get("two_hand_required", false)), "S8 skinned viewmodel lost two-hand mount-base contract")
	_assert(bool(embodiment.get_two_hand_report().get("active", false)), "S8 skinned viewmodel did not activate left support hand")
	if left_rig != null:
		left_rig._process(0.2)
		_assert(String(left_rig.create_report().get("current_pose_id", "")) == "support_cradle", "S8 skinned left hand did not receive support_cradle pose")
	if right_rig != null:
		right_rig._process(0.2)
		_assert(String(right_rig.create_report().get("current_pose_id", "")) == "bulky_carry", "S8 skinned right hand did not receive bulky_carry pose")

	var clear_result: Dictionary = embodiment.clear_authoritative_hand_item("right")
	_assert(bool(clear_result.get("success", false)), "S8 skinned viewmodel clear failed")
	_assert(not bool(embodiment.get_two_hand_report().get("active", true)), "S8 skinned viewmodel stayed two-hand active after clear")

	var default_viewmodel := EmbodimentType.new()
	root.add_child(default_viewmodel)
	var fallback_root := Node3D.new()
	root.add_child(fallback_root)
	var fallback_setup: Dictionary = default_viewmodel._install_hand_rig("right", fallback_root, 19)
	_assert(bool(fallback_setup.get("success", false)), "S8 unconfigured viewmodel did not preserve fallback provider")
	var fallback_rig = default_viewmodel._hand_rig_by_hand.get("right")
	_assert(fallback_rig != null, "S8 fallback rig missing")
	if fallback_rig != null:
		_assert(String(fallback_rig.create_report().get("visual_provider_mode", "")) == "PROCEDURAL_SEGMENTS", "S8 unconfigured viewmodel did not preserve procedural fallback")

	var final_report: Dictionary = embodiment.create_report()
	var skinned_report: Dictionary = Dictionary(final_report.get("skinned_hand_visual", {}))
	_assert(bool(skinned_report.get("presentation_only", false)), "S8 skinned configuration is not presentation-only")
	_assert(not bool(skinned_report.get("owns_item_state", true)), "S8 skinned configuration claims item ownership")
	_assert(not bool(skinned_report.get("owns_network_state", true)), "S8 skinned configuration claims network ownership")
	_assert(not bool(skinned_report.get("owns_gameplay_transform", true)), "S8 skinned configuration claims gameplay transform ownership")

	root.queue_free()
	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FPE R2 S8 skinned configurable viewmodel: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FPE R2 S8 skinned configurable viewmodel: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
