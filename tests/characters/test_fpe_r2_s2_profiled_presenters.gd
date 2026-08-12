extends SceneTree

const FirstPersonType = preload("res://scripts/characters/presentation/catalogued_first_person_embodiment.gd")
const ThirdPersonType = preload("res://scripts/characters/presentation/catalogued_third_person_held_item_presenter.gd")
const ViewmodelCatalogType = preload("res://scripts/characters/presentation/item_viewmodel_catalog.gd")
const GripCatalogType = preload("res://scripts/characters/presentation/held_item_grip_profile_catalog.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog = ViewmodelCatalogType.new()
	var grips = GripCatalogType.new()
	var descriptor: Dictionary = catalog.resolve("survey_beacon", ["signal"], {}, "", Color(1.0, 0.25, 0.05, 1.0))
	var grip: Dictionary = grips.resolve("survey_beacon", descriptor, ["signal"], {})

	var root := Node3D.new()
	get_root().add_child(root)

	var first = FirstPersonType.new()
	root.add_child(first)
	first.right_held_root = Node3D.new()
	first.right_held_root.name = "RightGrip"
	first.add_child(first.right_held_root)
	var first_result: Dictionary = first.set_catalogued_hand_item(
		"right",
		"item/beacon",
		"Survey Beacon",
		Color(1.0, 0.25, 0.05, 1.0),
		descriptor,
		grip
	)
	_assert(bool(first_result.get("success", false)), "S2 catalogued first-person apply failed")
	_assert(String(first_result.get("details", {}).get("visual_profile", "")) == "beacon", "S2 first-person visual profile mismatch")
	_assert(String(first_result.get("details", {}).get("grip_profile", "")) == "beacon_vertical", "S2 first-person grip profile mismatch")
	var first_proxy_value: Variant = first._authoritative_proxy_by_hand.get("right")
	_assert(first_proxy_value is MeshInstance3D, "S2 first-person proxy missing")
	if first_proxy_value is MeshInstance3D:
		var first_proxy := first_proxy_value as MeshInstance3D
		_assert(first_proxy.mesh is CylinderMesh, "S2 first-person beacon is not catalogued cylinder")
		_assert(String(first_proxy.get_meta("held_visual_profile", "")) == "beacon", "S2 first-person proxy visual metadata mismatch")
		_assert(String(first_proxy.get_meta("held_grip_profile", "")) == "beacon_vertical", "S2 first-person proxy grip metadata mismatch")

	var avatar := Node3D.new()
	avatar.name = "AvatarPresentation"
	root.add_child(avatar)
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	avatar.add_child(skeleton)
	skeleton.add_bone("mixamorig_RightHand")

	var third = ThirdPersonType.new()
	root.add_child(third)
	var third_setup: Dictionary = third.setup(avatar, skeleton, 20)
	_assert(bool(third_setup.get("success", false)), "S2 catalogued third-person setup failed")
	var third_result: Dictionary = third.present_catalogued_item(
		"item/beacon",
		"Survey Beacon",
		Color(1.0, 0.25, 0.05, 1.0),
		descriptor,
		grip
	)
	_assert(bool(third_result.get("success", false)), "S2 catalogued third-person apply failed")
	_assert(String(third_result.get("details", {}).get("visual_profile", "")) == "beacon", "S2 third-person visual profile mismatch")
	_assert(String(third_result.get("details", {}).get("grip_profile", "")) == "beacon_vertical", "S2 third-person grip profile mismatch")
	_assert(String(third_result.get("details", {}).get("attachment_mode", "")) == "BONE_RIGHT_HAND", "S2 third-person lost right-hand attachment")
	_assert(third._proxy != null, "S2 third-person proxy missing")
	if third._proxy != null:
		_assert(third._proxy.mesh is CylinderMesh, "S2 third-person beacon is not catalogued cylinder")
		_assert(third._proxy.get_layer_mask_value(20), "S2 third-person proxy left world render layer")
		_assert(not third._proxy.get_layer_mask_value(1), "S2 third-person proxy leaked to default layer")
		_assert(String(third._proxy.get_meta("held_visual_profile", "")) == "beacon", "S2 third-person proxy visual metadata mismatch")
		_assert(String(third._proxy.get_meta("held_grip_profile", "")) == "beacon_vertical", "S2 third-person proxy grip metadata mismatch")

	var first_report: Dictionary = first.create_report()
	var first_catalog: Dictionary = Dictionary(first_report.get("catalogued_viewmodel", {}))
	_assert(bool(first_catalog.get("enabled", false)), "S2 first-person catalog report disabled")
	_assert(not bool(first_catalog.get("owns_item_state", true)), "S2 first-person catalog claims item authority")
	var third_catalog: Dictionary = Dictionary(third.create_report().get("catalogued", {}))
	_assert(bool(third_catalog.get("enabled", false)), "S2 third-person catalog report disabled")
	_assert(not bool(third_catalog.get("owns_gameplay_transform", true)), "S2 third-person catalog claims gameplay transform authority")

	var first_clear: Dictionary = first.clear_authoritative_hand_item("right")
	var third_clear: Dictionary = third.clear_item()
	_assert(bool(first_clear.get("success", false)), "S2 first-person clear failed")
	_assert(bool(third_clear.get("success", false)), "S2 third-person clear failed")
	_assert(first._authoritative_proxy_by_hand.get("right") == null, "S2 first-person retained stale proxy")
	_assert(third._proxy == null, "S2 third-person retained stale proxy")

	root.queue_free()
	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FPE R2 S2 profiled presenters: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FPE R2 S2 profiled presenters: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
