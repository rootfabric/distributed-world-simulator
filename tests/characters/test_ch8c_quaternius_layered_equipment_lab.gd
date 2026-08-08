extends SceneTree

const LabScene = preload("res://scenes/labs/character/quaternius_layered_equipment_lab.tscn")
const UPPER_ITEM_ID := "lab.item.layer.upper.001"
const LOWER_ITEM_ID := "lab.item.layer.lower.001"
const FEET_ITEM_ID := "lab.item.layer.feet.001"
const UPPER_PROFILE_ID := "equipment.layer.upper.peasant"
const LOWER_PROFILE_ID := "equipment.layer.lower.peasant"
const FEET_PROFILE_ID := "equipment.layer.feet.peasant"
const FEET_PRESENTATION_ID := "wearable.layer.feet.peasant"
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
	_assert(lab.body_suppression_coordinator != null, "CH8C graphical lab material coordinator missing")
	_assert(lab.body_topology_coordinator != null, "CH8C graphical lab topology coordinator missing")
	_assert(bool(lab.layered_setup_result.get("success", false)), "CH8C graphical lab setup failed: %s" % JSON.stringify(lab.layered_setup_result))
	_assert(lab.status_label != null and String(lab.status_label.text).contains("CH8C — Layered Garments"), "CH8C graphical lab status extension failed")
	_assert(lab.status_label != null and String(lab.status_label.text).contains("topology:"), "CH8C graphical lab topology status missing")
	_assert(lab.status_label != null and String(lab.status_label.text).contains("feet topology: HIGH_BOOT"), "CH8C graphical lab high-boot status missing")
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

	var material_report: Dictionary = lab.body_suppression_coordinator.create_report()
	var active_regions: Array = material_report.get("active_regions", [])
	_assert(active_regions.size() == 1, "CH8C topology lab expected torso-only material suppression")
	_assert(REGION_TORSO_CORE in active_regions, "CH8C topology lab lost torso-core material suppression")
	_assert(bool(material_report.get("material_applied", false)), "CH8C topology lab did not apply torso-core material")

	var topology_report: Dictionary = lab.body_topology_coordinator.create_report()
	_assert(bool(topology_report.get("mesh_applied", false)), "CH8C graphical lab did not apply topology body mesh")
	_assert((topology_report.get("active_presentations", []) as Array).size() == 2, "CH8C graphical lab expected lower+feet topology presentations")
	_assert(int(topology_report.get("removed_triangles", 0)) > 0, "CH8C graphical lab topology removed no body triangles")
	var feet_descriptor := _find_descriptor(topology_report, FEET_PRESENTATION_ID)
	_assert(not feet_descriptor.is_empty(), "CH8C graphical lab feet descriptor report missing")
	_assert(String(feet_descriptor.get("coverage_mode", "")) == "HIGH_BOOT", "CH8C graphical lab lost HIGH_BOOT footwear mode")
	_assert(is_equal_approx(float(feet_descriptor.get("threshold_m", 0.0)), 0.045), "CH8C graphical lab high-boot threshold mismatch")
	_assert(is_equal_approx(float(feet_descriptor.get("upper_y_pad_m", 0.0)), 0.012), "CH8C graphical lab high-boot upper pad mismatch")

	# Removing lower must keep the feet topology mask while leaving upper material
	# suppression unchanged.
	var lower_off: Dictionary = lab.call("_toggle_layer", LOWER_ITEM_ID, LOWER_PROFILE_ID)
	_assert(bool(lower_off.get("success", false)), "CH8C graphical lab lower toggle-off failed")
	await process_frame
	var after_lower_material: Array = lab.body_suppression_coordinator.create_report().get("active_regions", [])
	_assert(after_lower_material.size() == 1 and REGION_TORSO_CORE in after_lower_material, "CH8C lower toggle changed upper body coverage")
	var after_lower_topology: Dictionary = lab.body_topology_coordinator.create_report()
	_assert((after_lower_topology.get("active_presentations", []) as Array).size() == 1, "CH8C lower toggle did not leave feet topology")
	_assert(int(after_lower_topology.get("removed_triangles", 0)) > 0, "CH8C feet topology removed no body triangles")
	_assert(String(_find_descriptor(after_lower_topology, FEET_PRESENTATION_ID).get("coverage_mode", "")) == "HIGH_BOOT", "CH8C feet-only topology lost HIGH_BOOT mode")

	# Removing feet must restore the exact unmasked base mesh while upper remains.
	var feet_off: Dictionary = lab.call("_toggle_layer", FEET_ITEM_ID, FEET_PROFILE_ID)
	_assert(bool(feet_off.get("success", false)), "CH8C graphical lab feet toggle-off failed")
	await process_frame
	var after_feet_topology: Dictionary = lab.body_topology_coordinator.create_report()
	_assert((after_feet_topology.get("active_presentations", []) as Array).is_empty(), "CH8C feet toggle retained topology presentations")
	_assert(not bool(after_feet_topology.get("mesh_applied", true)), "CH8C feet toggle retained topology mesh")
	var after_feet_material: Array = lab.body_suppression_coordinator.create_report().get("active_regions", [])
	_assert(after_feet_material.size() == 1 and REGION_TORSO_CORE in after_feet_material, "CH8C feet toggle changed upper body coverage")

	var upper_off: Dictionary = lab.call("_toggle_layer", UPPER_ITEM_ID, UPPER_PROFILE_ID)
	_assert(bool(upper_off.get("success", false)), "CH8C graphical lab upper toggle-off failed")
	await process_frame

	_assert(not lab.equipment_source.has_item(UPPER_ITEM_ID), "CH8C graphical lab upper remained equipped")
	_assert(not lab.equipment_source.has_item(LOWER_ITEM_ID), "CH8C graphical lab lower remained equipped")
	_assert(not lab.equipment_source.has_item(FEET_ITEM_ID), "CH8C graphical lab feet remained equipped")
	_assert(String(lab.status_label.text).contains("upper: OFF | lower: OFF | feet: OFF"), "CH8C graphical lab status did not reflect cleared layers")
	var final_material: Dictionary = lab.body_suppression_coordinator.create_report()
	_assert((final_material.get("active_regions", []) as Array).is_empty(), "CH8C graphical lab retained body material regions after clear")
	_assert(not bool(final_material.get("material_applied", true)), "CH8C graphical lab retained suppression material after clear")
	var final_topology: Dictionary = lab.body_topology_coordinator.create_report()
	_assert((final_topology.get("active_presentations", []) as Array).is_empty(), "CH8C graphical lab retained topology presentations after clear")
	_assert(not bool(final_topology.get("mesh_applied", true)), "CH8C graphical lab retained topology mesh after clear")
	_assert(lab.player.position.is_equal_approx(player_position_before), "CH8C graphical lab moved gameplay body")
	_assert(is_equal_approx(float(lab.player_capsule.height), capsule_height_before), "CH8C graphical lab changed gameplay capsule")

	lab.queue_free()
	_finish()


func _find_descriptor(report: Dictionary, presentation_id: String) -> Dictionary:
	for raw_descriptor in report.get("descriptor_reports", []):
		if raw_descriptor is Dictionary:
			var descriptor := raw_descriptor as Dictionary
			if String(descriptor.get("presentation_id", "")) == presentation_id:
				return descriptor
	return {}


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH8C Quaternius topology-aware layered equipment lab: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH8C Quaternius topology-aware layered equipment lab: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
