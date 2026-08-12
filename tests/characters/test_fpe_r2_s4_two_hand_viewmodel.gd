extends SceneTree

const TwoHandType = preload("res://scripts/characters/presentation/two_hand_posed_first_person_embodiment.gd")
const ViewmodelCatalogType = preload("res://scripts/characters/presentation/item_viewmodel_catalog.gd")
const GripCatalogType = preload("res://scripts/characters/presentation/held_item_grip_profile_catalog.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var viewmodel := Node3D.new()
	viewmodel.name = "ViewmodelRoot"
	root.add_child(viewmodel)
	var posed = TwoHandType.new()
	root.add_child(posed)
	posed.viewmodel_root = viewmodel

	posed.left_hand_root = Node3D.new()
	posed.left_hand_root.name = "LeftHandViewmodel"
	posed.left_hand_root.position = Vector3(-0.26, -0.24, -0.48)
	viewmodel.add_child(posed.left_hand_root)
	posed.left_held_root = Node3D.new()
	posed.left_held_root.name = "LeftGrip"
	posed.left_hand_root.add_child(posed.left_held_root)

	posed.right_hand_root = Node3D.new()
	posed.right_hand_root.name = "RightHandViewmodel"
	posed.right_hand_root.position = Vector3(0.26, -0.24, -0.48)
	viewmodel.add_child(posed.right_hand_root)
	posed.right_held_root = Node3D.new()
	posed.right_held_root.name = "RightGrip"
	posed.right_hand_root.add_child(posed.right_held_root)

	var left_setup: Dictionary = posed._install_hand_rig("left", posed.left_hand_root, 19)
	var right_setup: Dictionary = posed._install_hand_rig("right", posed.right_hand_root, 19)
	_assert(bool(left_setup.get("success", false)), "S4 two-hand left rig setup failed")
	_assert(bool(right_setup.get("success", false)), "S4 two-hand right rig setup failed")
	posed._capture_left_default()
	_assert(posed._left_default_captured, "S4 left default transform was not captured")
	_assert(posed.left_hand_root.get_parent() == viewmodel, "S4 left hand did not start under viewmodel root")

	var visuals = ViewmodelCatalogType.new()
	var grips = GripCatalogType.new()
	# Use the actual M7 replica definition and tags. This guards the graphical
	# slot-2 path where `beacon_mount_base` previously collapsed to beacon_pinch.
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
	var mount_result: Dictionary = posed.set_catalogued_hand_item(
		"right",
		"item/player/a/mount-bases",
		"Mount Base",
		Color(0.15, 0.45, 0.65, 1.0),
		mount_visual,
		mount_grip
	)
	_assert(bool(mount_result.get("success", false)), "S4 mount-base two-hand apply failed")
	_assert(bool(mount_result.get("details", {}).get("two_hand_required", false)), "S4 mount-base result did not disclose two-hand requirement")
	_assert(bool(mount_result.get("details", {}).get("secondary_hand_active", false)), "S4 left secondary hand did not activate")
	_assert(posed._secondary_anchor != null, "S4 secondary grip anchor missing")
	_assert(posed.left_hand_root.get_parent() == posed._secondary_anchor, "S4 left hand was not parented under secondary grip anchor")
	_assert(posed._authoritative_proxy_by_hand.get("right") is MeshInstance3D, "S4 primary item proxy missing")

	var left_rig = posed._hand_rig_by_hand.get("left")
	var right_rig = posed._hand_rig_by_hand.get("right")
	_assert(left_rig != null, "S4 left articulated rig missing")
	_assert(right_rig != null, "S4 right articulated rig missing")
	if left_rig != null:
		left_rig._process(0.2)
		_assert(String(left_rig.create_report().get("current_pose_id", "")) == "support_cradle", "S4 left hand did not use support_cradle pose")
	if right_rig != null:
		right_rig._process(0.2)
		_assert(String(right_rig.create_report().get("current_pose_id", "")) == "bulky_carry", "S4 right hand did not switch from beacon_pinch to bulky_carry on replica mount-base")

	var active_report: Dictionary = posed.get_two_hand_report()
	_assert(bool(active_report.get("active", false)), "S4 two-hand report is not active")
	_assert(String(active_report.get("secondary_hand", "")) == "left", "S4 two-hand report secondary hand mismatch")
	_assert(String(active_report.get("secondary_pose_id", "")) == "support_cradle", "S4 report secondary pose mismatch")
	_assert(int(active_report.get("activations", 0)) == 1, "S4 activation counter mismatch")

	var reserved_result: Dictionary = posed.try_grab("left")
	_assert(not bool(reserved_result.get("success", true)), "S4 reserved left support hand incorrectly accepted a local grab")
	_assert(String(reserved_result.get("error_code", "")) == "FPE_S4_SECONDARY_HAND_RESERVED", "S4 reserved-hand failure code mismatch")

	var beacon_visual: Dictionary = visuals.resolve("survey_beacon", ["beacon", "mountable", "electronic"], {}, "", Color(1.0, 0.3, 0.05, 1.0))
	var beacon_grip: Dictionary = grips.resolve("survey_beacon", beacon_visual, ["beacon", "mountable", "electronic"], {})
	var beacon_result: Dictionary = posed.set_catalogued_hand_item(
		"right",
		"item/player/a/beacons",
		"Beacon",
		Color(1.0, 0.3, 0.05, 1.0),
		beacon_visual,
		beacon_grip
	)
	_assert(bool(beacon_result.get("success", false)), "S4 switch from two-hand mount-base to one-hand beacon failed")
	_assert(not bool(beacon_result.get("details", {}).get("two_hand_required", true)), "S4 beacon unexpectedly remains two-hand")
	_assert(posed.left_hand_root.get_parent() == viewmodel, "S4 switching to one-hand item did not restore left hand parent")
	var inactive_report: Dictionary = posed.get_two_hand_report()
	_assert(not bool(inactive_report.get("active", true)), "S4 report remained active after one-hand switch")
	_assert(int(inactive_report.get("releases", 0)) >= 1, "S4 release counter did not advance")
	if left_rig != null:
		left_rig._process(0.2)
		_assert(String(left_rig.create_report().get("current_pose_id", "")) == "open", "S4 released left hand did not return to open pose")

	var mount_again: Dictionary = posed.set_catalogued_hand_item(
		"right",
		"item/player/a/mount-bases",
		"Mount Base",
		Color(0.15, 0.45, 0.65, 1.0),
		mount_visual,
		mount_grip
	)
	_assert(bool(mount_again.get("success", false)), "S4 second mount-base activation failed")
	_assert(bool(posed.get_two_hand_report().get("active", false)), "S4 second mount-base activation did not reserve left hand")
	var clear_result: Dictionary = posed.clear_authoritative_hand_item("right")
	_assert(bool(clear_result.get("success", false)), "S4 clearing primary item failed")
	_assert(posed.left_hand_root.get_parent() == viewmodel, "S4 primary clear did not restore left hand parent")
	_assert(not bool(posed.get_two_hand_report().get("active", true)), "S4 primary clear left two-hand state active")
	_assert(posed._authoritative_proxy_by_hand.get("right") == null, "S4 primary proxy survived clear")

	var final_report: Dictionary = posed.get_two_hand_report()
	_assert(bool(final_report.get("presentation_only", false)), "S4 two-hand coordinator is not presentation-only")
	_assert(not bool(final_report.get("owns_item_state", true)), "S4 two-hand coordinator claims item ownership")
	_assert(not bool(final_report.get("owns_network_state", true)), "S4 two-hand coordinator claims network ownership")
	_assert(not bool(final_report.get("owns_gameplay_transform", true)), "S4 two-hand coordinator claims gameplay transform ownership")

	root.queue_free()
	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FPE R2 S4 two-hand viewmodel: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FPE R2 S4 two-hand viewmodel: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
