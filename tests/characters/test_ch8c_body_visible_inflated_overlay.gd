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

	_assert(String(lab.body_fit_policy) == "BODY_VISIBLE_INFLATED_OVERLAY", "CH8C fix10 graphical lab did not default to body-visible overlay")
	_assert(bool(lab.layered_setup_result.get("success", false)), "CH8C fix10 setup failed: %s" % JSON.stringify(lab.layered_setup_result))
	if not bool(lab.layered_setup_result.get("success", false)):
		lab.queue_free()
		_finish()
		return

	var body_mesh := _find_mesh(lab.avatar, "SuperHero_Male")
	_assert(body_mesh != null, "CH8C fix10 fused base-body mesh missing")
	if body_mesh == null:
		lab.queue_free()
		_finish()
		return
	var original_mesh: Mesh = body_mesh.mesh
	var original_material: Material = body_mesh.material_override
	var player_position_before: Vector3 = lab.player.position
	var capsule_height_before := float(lab.player_capsule.height)

	_assert(lab.inflation_reports.has(UPPER_PRESENTATION_ID), "CH8C fix10 upper inflation report missing")
	_assert(lab.inflation_reports.has(LOWER_PRESENTATION_ID), "CH8C fix10 lower inflation report missing")
	_assert(lab.inflation_reports.has(FEET_PRESENTATION_ID), "CH8C fix10 feet inflation report missing")
	_assert(is_equal_approx(_profile_max(lab, UPPER_PRESENTATION_ID), 0.008), "CH8C fix10 upper inflation max mismatch")
	_assert(is_equal_approx(_profile_max(lab, LOWER_PRESENTATION_ID), 0.014), "CH8C fix10 lower inflation max mismatch")
	_assert(is_equal_approx(_profile_max(lab, FEET_PRESENTATION_ID), 0.016), "CH8C fix10 feet inflation max mismatch")
	var upper_inflation: Dictionary = lab.inflation_reports[UPPER_PRESENTATION_ID]
	_assert(int(upper_inflation.get("filtered_surface_count", 0)) >= 1, "CH8C fix10 upper did not filter embedded skin surface")
	_assert((upper_inflation.get("included_material_names", []) as Array).has("MI_Peasant"), "CH8C fix10 upper clothing material filter missing")
	_assert(String(lab.status_label.text).contains("fit policy: BODY_VISIBLE_INFLATED_OVERLAY"), "CH8C fix10 status does not expose fit policy")

	_assert_body_intact(lab, body_mesh, original_mesh, original_material, "initial")
	for pair in [[UPPER_ITEM_ID, UPPER_PROFILE_ID], [LOWER_ITEM_ID, LOWER_PROFILE_ID], [FEET_ITEM_ID, FEET_PROFILE_ID]]:
		var on_result: Dictionary = lab.call("_toggle_layer", String(pair[0]), String(pair[1]))
		_assert(bool(on_result.get("success", false)), "CH8C fix10 equip failed for %s" % String(pair[0]))
		await process_frame
		_assert_body_intact(lab, body_mesh, original_mesh, original_material, "after %s" % String(pair[0]))

	_assert(lab.equipment_source.has_item(UPPER_ITEM_ID), "CH8C fix10 upper item missing")
	_assert(lab.equipment_source.has_item(LOWER_ITEM_ID), "CH8C fix10 lower item missing")
	_assert(lab.equipment_source.has_item(FEET_ITEM_ID), "CH8C fix10 feet item missing")
	_assert(String(lab.status_label.text).contains("upper: ON | lower: ON | feet: ON"), "CH8C fix10 status did not reflect all layers")

	for pair in [[FEET_ITEM_ID, FEET_PROFILE_ID], [LOWER_ITEM_ID, LOWER_PROFILE_ID], [UPPER_ITEM_ID, UPPER_PROFILE_ID]]:
		var off_result: Dictionary = lab.call("_toggle_layer", String(pair[0]), String(pair[1]))
		_assert(bool(off_result.get("success", false)), "CH8C fix10 unequip failed for %s" % String(pair[0]))
		await process_frame
		_assert_body_intact(lab, body_mesh, original_mesh, original_material, "after unequip %s" % String(pair[0]))

	_assert(not lab.equipment_source.has_item(UPPER_ITEM_ID), "CH8C fix10 upper remained equipped")
	_assert(not lab.equipment_source.has_item(LOWER_ITEM_ID), "CH8C fix10 lower remained equipped")
	_assert(not lab.equipment_source.has_item(FEET_ITEM_ID), "CH8C fix10 feet remained equipped")
	_assert(lab.player.position.is_equal_approx(player_position_before), "CH8C fix10 moved gameplay CharacterBody3D")
	_assert(is_equal_approx(float(lab.player_capsule.height), capsule_height_before), "CH8C fix10 changed gameplay capsule")
	lab.queue_free()
	_finish()

func _assert_body_intact(lab, body_mesh: MeshInstance3D, original_mesh: Mesh, original_material: Material, phase: String) -> void:
	_assert(body_mesh.mesh == original_mesh, "CH8C fix10 body mesh changed %s" % phase)
	_assert(body_mesh.material_override == original_material, "CH8C fix10 body material changed %s" % phase)
	var suppression_report: Dictionary = lab.body_suppression_coordinator.create_report()
	_assert((suppression_report.get("active_regions", []) as Array).is_empty(), "CH8C fix10 body suppression active %s" % phase)
	_assert(not bool(suppression_report.get("material_applied", false)), "CH8C fix10 suppression material applied %s" % phase)
	var topology_report: Dictionary = lab.body_topology_coordinator.create_report()
	_assert((topology_report.get("active_presentations", []) as Array).is_empty(), "CH8C fix10 topology presentation active %s" % phase)
	_assert(not bool(topology_report.get("mesh_applied", false)), "CH8C fix10 topology mesh applied %s" % phase)
	_assert(int(topology_report.get("removed_triangles", 0)) == 0, "CH8C fix10 removed body triangles %s" % phase)

func _profile_max(lab, presentation_id: String) -> float:
	if not lab.inflation_reports.has(presentation_id):
		return 0.0
	return float((lab.inflation_reports[presentation_id] as Dictionary).get("profile_max_offset_m", 0.0))

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
		print("CH8C body-visible inflated overlay: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH8C body-visible inflated overlay: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
