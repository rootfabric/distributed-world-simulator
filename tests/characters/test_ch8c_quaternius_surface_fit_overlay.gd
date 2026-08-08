extends SceneTree

const LabScene = preload("res://scenes/labs/character/quaternius_layered_equipment_lab.tscn")
const UPPER_ITEM_ID := "lab.item.layer.upper.001"
const LOWER_ITEM_ID := "lab.item.layer.lower.001"
const FEET_ITEM_ID := "lab.item.layer.feet.001"
const UPPER_PROFILE_ID := "equipment.layer.upper.peasant"
const LOWER_PROFILE_ID := "equipment.layer.lower.peasant"
const FEET_PROFILE_ID := "equipment.layer.feet.peasant"
const REGION_TORSO_CORE := "body.region.torso.core"
const LOWER_GROW_M := 0.010
const FEET_GROW_M := 0.008

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var lab = LabScene.instantiate()
	root.add_child(lab)
	await process_frame
	await physics_frame

	_assert(lab.player is CharacterBody3D, "CH8C surface-fit lab gameplay body missing")
	_assert(lab.body_suppression_coordinator != null, "CH8C surface-fit coordinator missing")
	_assert(bool(lab.layered_setup_result.get("success", false)), "CH8C surface-fit lab setup failed")
	if not bool(lab.layered_setup_result.get("success", false)):
		lab.queue_free()
		_finish()
		return

	var body_mesh := _find_mesh(lab.avatar, "SuperHero_Male")
	_assert(body_mesh != null, "CH8C surface-fit base body missing")
	if body_mesh == null:
		lab.queue_free()
		_finish()
		return
	var original_material: Material = body_mesh.material_override
	var player_position_before: Vector3 = lab.player.position
	var capsule_height_before := float(lab.player_capsule.height)

	# Lower alone must leave the entire base body material untouched. The pants
	# solve penetration by outward presentation fit, not by deleting the leg.
	var lower_on: Dictionary = lab.call("_toggle_layer", LOWER_ITEM_ID, LOWER_PROFILE_ID)
	_assert(bool(lower_on.get("success", false)), "CH8C surface-fit lower equip failed")
	await process_frame
	var lower_report: Dictionary = lab.body_suppression_coordinator.create_report()
	_assert((lower_report.get("active_regions", []) as Array).is_empty(), "CH8C lower still suppresses base leg regions")
	_assert(not bool(lower_report.get("material_applied", true)), "CH8C lower still installs base-body clip material")
	_assert(body_mesh.material_override == original_material, "CH8C lower changed base body material")
	_assert(_has_fitted_mesh(lab, "Male_Peasant_Legs", LOWER_GROW_M), "CH8C lower runtime visual lacks surface grow")

	# Feet alone follow the same open-overlay rule.
	var feet_on: Dictionary = lab.call("_toggle_layer", FEET_ITEM_ID, FEET_PROFILE_ID)
	_assert(bool(feet_on.get("success", false)), "CH8C surface-fit feet equip failed")
	await process_frame
	var lower_feet_report: Dictionary = lab.body_suppression_coordinator.create_report()
	_assert((lower_feet_report.get("active_regions", []) as Array).is_empty(), "CH8C lower+feet unexpectedly suppress base body")
	_assert(body_mesh.material_override == original_material, "CH8C feet changed intact base body material")
	_assert(_has_fitted_mesh(lab, "Male_Peasant_Feet", FEET_GROW_M), "CH8C feet runtime visual lacks surface grow")

	# Upper retains the accepted protected torso-core suppression. Adding it must
	# not cause lower/feet to reintroduce any leg clipping.
	var upper_on: Dictionary = lab.call("_toggle_layer", UPPER_ITEM_ID, UPPER_PROFILE_ID)
	_assert(bool(upper_on.get("success", false)), "CH8C surface-fit upper equip failed")
	await process_frame
	var all_report: Dictionary = lab.body_suppression_coordinator.create_report()
	var regions: Array = all_report.get("active_regions", [])
	_assert(regions.size() == 1, "CH8C U+L+K expected exactly one suppressed region")
	_assert(REGION_TORSO_CORE in regions, "CH8C U+L+K lost torso core suppression")
	_assert(bool(all_report.get("material_applied", false)), "CH8C upper did not install torso-core material")
	var torso_material: Material = body_mesh.material_override
	_assert(torso_material is ShaderMaterial, "CH8C upper body suppression is not a ShaderMaterial")

	# Toggling lower while upper remains equipped changes garment presentation but
	# must not rebuild the body mask, because lower contributes no coverage.
	var lower_off: Dictionary = lab.call("_toggle_layer", LOWER_ITEM_ID, LOWER_PROFILE_ID)
	_assert(bool(lower_off.get("success", false)), "CH8C surface-fit lower unequip failed")
	await process_frame
	_assert(body_mesh.material_override == torso_material, "CH8C lower toggle rebuilt unchanged torso mask")
	var after_lower_regions: Array = lab.body_suppression_coordinator.create_report().get("active_regions", [])
	_assert(after_lower_regions.size() == 1 and REGION_TORSO_CORE in after_lower_regions, "CH8C lower toggle changed torso-only coverage")

	var lower_reon: Dictionary = lab.call("_toggle_layer", LOWER_ITEM_ID, LOWER_PROFILE_ID)
	_assert(bool(lower_reon.get("success", false)), "CH8C surface-fit lower re-equip failed")
	await process_frame
	_assert(body_mesh.material_override == torso_material, "CH8C lower re-equip rebuilt unchanged torso mask")
	_assert(_has_fitted_mesh(lab, "Male_Peasant_Legs", LOWER_GROW_M), "CH8C lower re-equip lost surface fit")

	# Removing the upper leaves only overlay garments; the exact original base
	# material must return while lower/feet remain equipped.
	var upper_off: Dictionary = lab.call("_toggle_layer", UPPER_ITEM_ID, UPPER_PROFILE_ID)
	_assert(bool(upper_off.get("success", false)), "CH8C surface-fit upper unequip failed")
	await process_frame
	var overlay_only_report: Dictionary = lab.body_suppression_coordinator.create_report()
	_assert((overlay_only_report.get("active_regions", []) as Array).is_empty(), "CH8C overlay-only state retained body suppression")
	_assert(not bool(overlay_only_report.get("material_applied", true)), "CH8C overlay-only state retained clip material")
	_assert(body_mesh.material_override == original_material, "CH8C overlay-only state did not restore original material")
	_assert(lab.equipment_source.has_item(LOWER_ITEM_ID), "CH8C overlay-only lower item disappeared")
	_assert(lab.equipment_source.has_item(FEET_ITEM_ID), "CH8C overlay-only feet item disappeared")
	_assert(_has_fitted_mesh(lab, "Male_Peasant_Legs", LOWER_GROW_M), "CH8C overlay-only lower lost fitted visual")
	_assert(_has_fitted_mesh(lab, "Male_Peasant_Feet", FEET_GROW_M), "CH8C overlay-only feet lost fitted visual")

	var lower_cleanup: Dictionary = lab.call("_toggle_layer", LOWER_ITEM_ID, LOWER_PROFILE_ID)
	var feet_cleanup: Dictionary = lab.call("_toggle_layer", FEET_ITEM_ID, FEET_PROFILE_ID)
	_assert(bool(lower_cleanup.get("success", false)), "CH8C lower cleanup failed")
	_assert(bool(feet_cleanup.get("success", false)), "CH8C feet cleanup failed")
	await process_frame
	_assert(body_mesh.material_override == original_material, "CH8C final cleanup changed base material")
	_assert(lab.player.position.is_equal_approx(player_position_before), "CH8C surface fit moved gameplay body")
	_assert(is_equal_approx(float(lab.player_capsule.height), capsule_height_before), "CH8C surface fit changed gameplay capsule")

	lab.queue_free()
	_finish()


func _has_fitted_mesh(root_node: Node, mesh_name: String, expected_grow: float) -> bool:
	var meshes: Array[MeshInstance3D] = []
	_collect_named_meshes(root_node, mesh_name, meshes)
	for mesh in meshes:
		if mesh.mesh == null:
			continue
		var all_surfaces_fit := mesh.mesh.get_surface_count() > 0
		for surface_index in range(mesh.mesh.get_surface_count()):
			var material: Material = mesh.get_surface_override_material(surface_index)
			if material == null:
				material = mesh.mesh.surface_get_material(surface_index)
			if not material is BaseMaterial3D:
				all_surfaces_fit = false
				break
			var base := material as BaseMaterial3D
			if not base.is_grow_enabled() or not is_equal_approx(base.get_grow(), expected_grow):
				all_surfaces_fit = false
				break
		if all_surfaces_fit:
			return true
	return false


func _find_mesh(root_node: Node, target_name: String) -> MeshInstance3D:
	if root_node is MeshInstance3D and String(root_node.name) == target_name:
		return root_node as MeshInstance3D
	for child in root_node.get_children():
		var found := _find_mesh(child, target_name)
		if found != null:
			return found
	return null


func _collect_named_meshes(root_node: Node, target_name: String, output: Array[MeshInstance3D]) -> void:
	if root_node is MeshInstance3D and String(root_node.name) == target_name:
		output.append(root_node as MeshInstance3D)
	for child in root_node.get_children():
		_collect_named_meshes(child, target_name, output)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH8C Quaternius surface-fit overlay: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH8C Quaternius surface-fit overlay: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
