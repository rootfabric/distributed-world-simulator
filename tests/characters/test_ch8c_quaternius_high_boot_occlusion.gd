extends SceneTree

const LabScene = preload("res://scenes/labs/character/quaternius_layered_equipment_lab.tscn")
const LOWER_ITEM_ID := "lab.item.layer.lower.001"
const FEET_ITEM_ID := "lab.item.layer.feet.001"
const LOWER_PROFILE_ID := "equipment.layer.lower.peasant"
const FEET_PROFILE_ID := "equipment.layer.feet.peasant"
const LOWER_PRESENTATION_ID := "wearable.layer.lower.peasant"
const FEET_PRESENTATION_ID := "wearable.layer.feet.peasant"

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var lab = LabScene.instantiate()
	root.add_child(lab)
	await process_frame
	await physics_frame

	_assert(bool(lab.layered_setup_result.get("success", false)), "CH8C high-boot lab setup failed: %s" % JSON.stringify(lab.layered_setup_result))
	_assert(lab.body_topology_catalog != null, "CH8C high-boot topology catalog missing")
	_assert(lab.body_topology_coordinator != null, "CH8C high-boot topology coordinator missing")
	if not bool(lab.layered_setup_result.get("success", false)):
		lab.queue_free()
		_finish()
		return

	var rig_profile_id := String(lab.layered_rig_adapter.rig_profile_id)
	var feet_resolved: Dictionary = lab.body_topology_catalog.resolve(FEET_PRESENTATION_ID, rig_profile_id)
	_assert(bool(feet_resolved.get("success", false)), "CH8C high-boot feet topology metadata missing")
	var feet_details: Dictionary = feet_resolved.get("details", {})
	_assert(String(feet_details.get("coverage_mode", "")) == "HIGH_BOOT", "CH8C footwear did not use HIGH_BOOT coverage")
	_assert(is_equal_approx(float(feet_details.get("threshold_m", 0.0)), 0.045), "CH8C high-boot threshold mismatch")
	_assert(is_equal_approx(float(feet_details.get("boundary_pad_m", 0.0)), 0.006), "CH8C high-boot boundary pad mismatch")
	_assert(is_equal_approx(float(feet_details.get("upper_y_pad_m", 0.0)), 0.012), "CH8C high-boot upper Y pad mismatch")
	_assert(is_equal_approx(float(feet_details.get("upper_bias_fraction", 0.0)), 0.52), "CH8C high-boot upper bias mismatch")

	var lower_resolved: Dictionary = lab.body_topology_catalog.resolve(LOWER_PRESENTATION_ID, rig_profile_id)
	_assert(bool(lower_resolved.get("success", false)), "CH8C lower topology metadata missing")
	var lower_details: Dictionary = lower_resolved.get("details", {})
	_assert(String(lower_details.get("coverage_mode", "")) == "ROBUST", "CH8C trouser topology must remain ROBUST")
	_assert(is_equal_approx(float(lower_details.get("threshold_m", 0.0)), 0.045), "CH8C trouser threshold changed unexpectedly")
	_assert(is_zero_approx(float(lower_details.get("upper_y_pad_m", -1.0))), "CH8C trouser topology gained high-boot Y padding")

	var body_mesh := _find_mesh(lab.avatar, "SuperHero_Male")
	_assert(body_mesh != null, "CH8C high-boot fused body mesh missing")
	if body_mesh == null:
		lab.queue_free()
		_finish()
		return
	var original_mesh: Mesh = body_mesh.mesh
	var original_material: Material = body_mesh.material_override
	var player_position_before: Vector3 = lab.player.position
	var capsule_height_before := float(lab.player_capsule.height)

	# Boots alone must use the high-boot descriptor and remove a non-empty,
	# bounded set of body triangles while preserving the original material.
	var feet_on: Dictionary = lab.call("_toggle_layer", FEET_ITEM_ID, FEET_PROFILE_ID)
	_assert(bool(feet_on.get("success", false)), "CH8C high-boot feet equip failed")
	await process_frame
	var feet_report: Dictionary = lab.body_topology_coordinator.create_report()
	_assert((feet_report.get("active_presentations", []) as Array).size() == 1, "CH8C high-boot feet-only expected one topology presentation")
	_assert(int(feet_report.get("removed_triangles", 0)) > 0, "CH8C high-boot feet removed no body triangles")
	_assert(int(feet_report.get("removed_triangles", 0)) < int(feet_report.get("total_triangles", 0)), "CH8C high-boot feet removed the complete body")
	_assert(body_mesh.mesh != original_mesh, "CH8C high-boot feet kept the original body mesh")
	_assert(body_mesh.material_override == original_material, "CH8C high-boot feet changed base material")
	var feet_descriptor := _find_descriptor(feet_report, FEET_PRESENTATION_ID)
	_assert(not feet_descriptor.is_empty(), "CH8C high-boot descriptor report missing")
	_assert(String(feet_descriptor.get("coverage_mode", "")) == "HIGH_BOOT", "CH8C high-boot descriptor mode mismatch")
	var feet_bounds_min: Vector3 = feet_descriptor.get("bounds_min", Vector3.ZERO)
	var feet_bounds_max: Vector3 = feet_descriptor.get("bounds_max", Vector3.ZERO)
	var aggressive_upper_y_min := float(feet_descriptor.get("aggressive_upper_y_min", INF))
	_assert(aggressive_upper_y_min > feet_bounds_min.y, "CH8C high-boot aggressive band starts below footwear")
	_assert(aggressive_upper_y_min < feet_bounds_max.y, "CH8C high-boot aggressive band did not enter upper shaft")

	var feet_off: Dictionary = lab.call("_toggle_layer", FEET_ITEM_ID, FEET_PROFILE_ID)
	_assert(bool(feet_off.get("success", false)), "CH8C high-boot feet unequip failed")
	await process_frame
	_assert(body_mesh.mesh == original_mesh, "CH8C high-boot feet cleanup did not restore exact original mesh")

	# The already accepted trouser mask stays identical when used alone. Adding
	# boots must contribute additional lower-leg/foot occlusion to the union.
	var lower_on: Dictionary = lab.call("_toggle_layer", LOWER_ITEM_ID, LOWER_PROFILE_ID)
	_assert(bool(lower_on.get("success", false)), "CH8C high-boot lower equip failed")
	await process_frame
	var lower_report: Dictionary = lab.body_topology_coordinator.create_report()
	var lower_removed := int(lower_report.get("removed_triangles", 0))
	_assert(lower_removed > 0, "CH8C high-boot lower baseline removed no triangles")
	var lower_descriptor := _find_descriptor(lower_report, LOWER_PRESENTATION_ID)
	_assert(String(lower_descriptor.get("coverage_mode", "")) == "ROBUST", "CH8C high-boot tuning changed trouser mode")

	var feet_with_lower: Dictionary = lab.call("_toggle_layer", FEET_ITEM_ID, FEET_PROFILE_ID)
	_assert(bool(feet_with_lower.get("success", false)), "CH8C high-boot lower+feet equip failed")
	await process_frame
	var union_report: Dictionary = lab.body_topology_coordinator.create_report()
	_assert((union_report.get("active_presentations", []) as Array).size() == 2, "CH8C high-boot union expected lower+feet")
	_assert(int(union_report.get("removed_triangles", 0)) > lower_removed, "CH8C high-boot feet added no occlusion beyond trousers")
	_assert(String(_find_descriptor(union_report, FEET_PRESENTATION_ID).get("coverage_mode", "")) == "HIGH_BOOT", "CH8C high-boot union lost footwear bias")
	_assert(String(_find_descriptor(union_report, LOWER_PRESENTATION_ID).get("coverage_mode", "")) == "ROBUST", "CH8C high-boot union changed trouser bias")

	var feet_union_off: Dictionary = lab.call("_toggle_layer", FEET_ITEM_ID, FEET_PROFILE_ID)
	_assert(bool(feet_union_off.get("success", false)), "CH8C high-boot union feet unequip failed")
	await process_frame
	var lower_again: Dictionary = lab.body_topology_coordinator.create_report()
	_assert(int(lower_again.get("removed_triangles", -1)) == lower_removed, "CH8C high-boot feet removal did not deterministically restore trouser mask")

	var lower_off: Dictionary = lab.call("_toggle_layer", LOWER_ITEM_ID, LOWER_PROFILE_ID)
	_assert(bool(lower_off.get("success", false)), "CH8C high-boot lower unequip failed")
	await process_frame
	_assert(body_mesh.mesh == original_mesh, "CH8C high-boot final cleanup did not restore exact original mesh")
	_assert(body_mesh.material_override == original_material, "CH8C high-boot final cleanup changed original material")
	_assert(lab.player.position.is_equal_approx(player_position_before), "CH8C high-boot tuning moved gameplay body")
	_assert(is_equal_approx(float(lab.player_capsule.height), capsule_height_before), "CH8C high-boot tuning changed gameplay capsule")

	lab.body_topology_coordinator.clear()
	lab.queue_free()
	_finish()


func _find_descriptor(report: Dictionary, presentation_id: String) -> Dictionary:
	for raw_descriptor in report.get("descriptor_reports", []):
		if raw_descriptor is Dictionary:
			var descriptor := raw_descriptor as Dictionary
			if String(descriptor.get("presentation_id", "")) == presentation_id:
				return descriptor
	return {}


func _find_mesh(root_node: Node, target_name: String) -> MeshInstance3D:
	if root_node is MeshInstance3D and String(root_node.name).to_lower() == target_name.to_lower():
		return root_node as MeshInstance3D
	for child in root_node.get_children():
		var found := _find_mesh(child, target_name)
		if found != null:
			return found
	return null


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH8C Quaternius high-boot calf occlusion: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH8C Quaternius high-boot calf occlusion: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
