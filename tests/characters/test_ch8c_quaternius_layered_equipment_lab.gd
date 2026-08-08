extends SceneTree

const LabScene = preload("res://scenes/labs/character/quaternius_layered_equipment_lab.tscn")
const UPPER_ITEM_ID := "lab.item.layer.upper.001"
const LOWER_ITEM_ID := "lab.item.layer.lower.001"
const FEET_ITEM_ID := "lab.item.layer.feet.001"
const UPPER_PROFILE_ID := "equipment.layer.upper.peasant"
const LOWER_PROFILE_ID := "equipment.layer.lower.peasant"
const FEET_PROFILE_ID := "equipment.layer.feet.peasant"
const REGION_TORSO_CORE := "body.region.torso.core"

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var lab = LabScene.instantiate()
	root.add_child(lab)
	await process_frame
	await physics_frame
	_assert(lab.player is CharacterBody3D, "CH8C graphical lab gameplay body missing")
	_assert(lab.equipment_source != null, "CH8C graphical lab equipment source missing")
	_assert(lab.equipment_presenter != null, "CH8C graphical lab presenter missing")
	_assert(lab.body_suppression_coordinator != null, "CH8C graphical lab coordinator missing")
	_assert(bool(lab.layered_setup_result.get("success", false)), "CH8C graphical lab setup failed: %s" % JSON.stringify(lab.layered_setup_result))
	_assert(lab.status_label != null and String(lab.status_label.text).contains("CH8C — Layered Garments"), "CH8C graphical lab status extension failed")
	_assert(lab.status_label != null and String(lab.status_label.text).contains("surface fit: lower 0.010 m | feet 0.008 m"), "CH8C graphical lab surface-fit status missing")
	if not bool(lab.layered_setup_result.get("success", false)):
		lab.queue_free()
		_finish()
		return

	var player_position_before: Vector3 = lab.player.position
	var capsule_height_before := float(lab.player_capsule.height)
	for pair in [
		[UPPER_ITEM_ID, UPPER_PROFILE_ID],
		[LOWER_ITEM_ID, LOWER_PROFILE_ID],
		[FEET_ITEM_ID, FEET_PROFILE_ID],
	]:
		var on_result: Dictionary = lab.call("_toggle_layer", String(pair[0]), String(pair[1]))
		_assert(bool(on_result.get("success", false)), "CH8C graphical lab layer toggle-on failed")
		await process_frame

	_assert(lab.equipment_source.has_item(UPPER_ITEM_ID), "CH8C graphical lab upper missing")
	_assert(lab.equipment_source.has_item(LOWER_ITEM_ID), "CH8C graphical lab lower missing")
	_assert(lab.equipment_source.has_item(FEET_ITEM_ID), "CH8C graphical lab feet missing")
	_assert(String(lab.status_label.text).contains("upper: ON | lower: ON | feet: ON"), "CH8C graphical lab status did not reflect equipped layers")
	var peak_report: Dictionary = lab.body_suppression_coordinator.create_report()
	var active_regions: Array = peak_report.get("active_regions", [])
	_assert(active_regions.size() == 1, "CH8C surface-fit lab expected torso-only body suppression")
	_assert(REGION_TORSO_CORE in active_regions, "CH8C surface-fit lab lost protected torso core")
	_assert(bool(peak_report.get("material_applied", false)), "CH8C graphical lab did not apply torso-core material")

	# Lower/feet are presentation-shell fits and must not add body suppression.
	var lower_off: Dictionary = lab.call("_toggle_layer", LOWER_ITEM_ID, LOWER_PROFILE_ID)
	_assert(bool(lower_off.get("success", false)), "CH8C graphical lab lower toggle-off failed")
	await process_frame
	var after_lower: Array = lab.body_suppression_coordinator.create_report().get("active_regions", [])
	_assert(after_lower.size() == 1 and REGION_TORSO_CORE in after_lower, "CH8C lower toggle changed body coverage")

	var feet_off: Dictionary = lab.call("_toggle_layer", FEET_ITEM_ID, FEET_PROFILE_ID)
	_assert(bool(feet_off.get("success", false)), "CH8C graphical lab feet toggle-off failed")
	await process_frame
	var after_feet: Array = lab.body_suppression_coordinator.create_report().get("active_regions", [])
	_assert(after_feet.size() == 1 and REGION_TORSO_CORE in after_feet, "CH8C feet toggle changed body coverage")

	var upper_off: Dictionary = lab.call("_toggle_layer", UPPER_ITEM_ID, UPPER_PROFILE_ID)
	_assert(bool(upper_off.get("success", false)), "CH8C graphical lab upper toggle-off failed")
	await process_frame

	_assert(not lab.equipment_source.has_item(UPPER_ITEM_ID), "CH8C graphical lab upper remained equipped")
	_assert(not lab.equipment_source.has_item(LOWER_ITEM_ID), "CH8C graphical lab lower remained equipped")
	_assert(not lab.equipment_source.has_item(FEET_ITEM_ID), "CH8C graphical lab feet remained equipped")
	_assert(String(lab.status_label.text).contains("upper: OFF | lower: OFF | feet: OFF"), "CH8C graphical lab status did not reflect cleared layers")
	var final_report: Dictionary = lab.body_suppression_coordinator.create_report()
	_assert((final_report.get("active_regions", []) as Array).is_empty(), "CH8C graphical lab retained body regions after clear")
	_assert(not bool(final_report.get("material_applied", true)), "CH8C graphical lab retained suppression material after clear")
	_assert(lab.player.position.is_equal_approx(player_position_before), "CH8C graphical lab moved gameplay body")
	_assert(is_equal_approx(float(lab.player_capsule.height), capsule_height_before), "CH8C graphical lab changed gameplay capsule")

	lab.queue_free()
	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH8C Quaternius surface-fit layered equipment lab: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH8C Quaternius surface-fit layered equipment lab: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
