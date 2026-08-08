extends SceneTree

const LabScene = preload("res://scenes/labs/character/quaternius_layered_equipment_lab.tscn")

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
	if not bool(lab.layered_setup_result.get("success", false)):
		lab.queue_free()
		_finish()
		return

	var player_position_before: Vector3 = lab.player.position
	var capsule_height_before := float(lab.player_capsule.height)
	for pair in [
		[lab.UPPER_ITEM_ID, lab.UPPER_PROFILE_ID],
		[lab.LOWER_ITEM_ID, lab.LOWER_PROFILE_ID],
		[lab.FEET_ITEM_ID, lab.FEET_PROFILE_ID],
	]:
		var on_result: Dictionary = lab.call("_toggle_layer", String(pair[0]), String(pair[1]))
		_assert(bool(on_result.get("success", false)), "CH8C graphical lab layer toggle-on failed")
		await process_frame

	_assert(lab.equipment_source.has_item(lab.UPPER_ITEM_ID), "CH8C graphical lab upper missing")
	_assert(lab.equipment_source.has_item(lab.LOWER_ITEM_ID), "CH8C graphical lab lower missing")
	_assert(lab.equipment_source.has_item(lab.FEET_ITEM_ID), "CH8C graphical lab feet missing")
	var peak_report: Dictionary = lab.body_suppression_coordinator.create_report()
	_assert((peak_report.get("active_regions", []) as Array).size() == 4, "CH8C graphical lab did not aggregate four body regions")
	_assert(bool(peak_report.get("material_applied", false)), "CH8C graphical lab did not apply aggregate material")

	for pair in [
		[lab.LOWER_ITEM_ID, lab.LOWER_PROFILE_ID],
		[lab.UPPER_ITEM_ID, lab.UPPER_PROFILE_ID],
		[lab.FEET_ITEM_ID, lab.FEET_PROFILE_ID],
	]:
		var off_result: Dictionary = lab.call("_toggle_layer", String(pair[0]), String(pair[1]))
		_assert(bool(off_result.get("success", false)), "CH8C graphical lab layer toggle-off failed")
		await process_frame

	_assert(not lab.equipment_source.has_item(lab.UPPER_ITEM_ID), "CH8C graphical lab upper remained equipped")
	_assert(not lab.equipment_source.has_item(lab.LOWER_ITEM_ID), "CH8C graphical lab lower remained equipped")
	_assert(not lab.equipment_source.has_item(lab.FEET_ITEM_ID), "CH8C graphical lab feet remained equipped")
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
		print("CH8C Quaternius layered equipment lab: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH8C Quaternius layered equipment lab: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
