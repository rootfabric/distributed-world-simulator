extends SceneTree

const LabScene = preload("res://scenes/labs/character/quaternius_layered_equipment_lab.tscn")
const UPPER_ITEM_ID := "lab.item.layer.upper.001"
const LOWER_ITEM_ID := "lab.item.layer.lower.001"
const FEET_ITEM_ID := "lab.item.layer.feet.001"
const UPPER_PROFILE_ID := "equipment.layer.upper.peasant"
const LOWER_PROFILE_ID := "equipment.layer.lower.peasant"
const FEET_PROFILE_ID := "equipment.layer.feet.peasant"
const UPPER_PRESENTATION_ID := "wearable.layer.upper.peasant"
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

	_assert(lab.player is CharacterBody3D, "CH8C graphical lab gameplay body missing")
	_assert(lab.equipment_source != null, "CH8C graphical lab equipment source missing")
	_assert(lab.equipment_presenter != null, "CH8C graphical lab presenter missing")
	_assert(bool(lab.layered_setup_result.get("success", false)), "CH8C graphical lab setup failed: %s" % JSON.stringify(lab.layered_setup_result))
	_assert(String(lab.body_fit_policy) == "BODY_VISIBLE_INFLATED_OVERLAY", "CH8C graphical lab did not default to body-visible overlay")
	_assert(lab.status_label != null and String(lab.status_label.text).contains("fit policy: BODY_VISIBLE_INFLATED_OVERLAY"), "CH8C graphical lab status policy missing")
	_assert(lab.inflation_reports.has(UPPER_PRESENTATION_ID), "CH8C graphical lab upper inflation report missing")
	_assert(lab.inflation_reports.has(LOWER_PRESENTATION_ID), "CH8C graphical lab lower inflation report missing")
	_assert(lab.inflation_reports.has(FEET_PRESENTATION_ID), "CH8C graphical lab feet inflation report missing")
	if not bool(lab.layered_setup_result.get("success", false)):
		lab.queue_free()
		_finish()
		return

	var body_mesh := _find_mesh(lab.avatar, "SuperHero_Male")
	_assert(body_mesh != null, "CH8C graphical lab base body missing")
	if body_mesh == null:
		lab.queue_free()
		_finish()
		return
	var original_mesh: Mesh = body_mesh.mesh
	var original_material: Material = body_mesh.material_override
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

	_assert(String(lab.status_label.text).contains("upper: ON | lower: ON | feet: ON"), "CH8C graphical lab status did not reflect equipped layers")
	_assert(body_mesh.mesh == original_mesh, "CH8C graphical lab changed base-body mesh")
	_assert(body_mesh.material_override == original_material, "CH8C graphical lab changed base-body material")
	_assert((lab.body_suppression_coordinator.create_report().get("active_regions", []) as Array).is_empty(), "CH8C graphical lab activated body suppression")
	_assert((lab.body_topology_coordinator.create_report().get("active_presentations", []) as Array).is_empty(), "CH8C graphical lab activated topology occlusion")
	_assert(not bool(lab.body_topology_coordinator.create_report().get("mesh_applied", false)), "CH8C graphical lab applied derived body mesh")

	for pair in [
		[FEET_ITEM_ID, FEET_PROFILE_ID],
		[LOWER_ITEM_ID, LOWER_PROFILE_ID],
		[UPPER_ITEM_ID, UPPER_PROFILE_ID],
	]:
		var off_result: Dictionary = lab.call("_toggle_layer", String(pair[0]), String(pair[1]))
		_assert(bool(off_result.get("success", false)), "CH8C graphical lab layer toggle-off failed")
		await process_frame

	_assert(String(lab.status_label.text).contains("upper: OFF | lower: OFF | feet: OFF"), "CH8C graphical lab status did not reflect cleared layers")
	_assert(body_mesh.mesh == original_mesh, "CH8C graphical lab cleanup changed base-body mesh")
	_assert(body_mesh.material_override == original_material, "CH8C graphical lab cleanup changed base-body material")
	_assert(lab.player.position.is_equal_approx(player_position_before), "CH8C graphical lab moved gameplay body")
	_assert(is_equal_approx(float(lab.player_capsule.height), capsule_height_before), "CH8C graphical lab changed gameplay capsule")

	lab.queue_free()
	_finish()

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
		print("CH8C Quaternius body-visible inflated layered equipment lab: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH8C Quaternius body-visible inflated layered equipment lab: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
