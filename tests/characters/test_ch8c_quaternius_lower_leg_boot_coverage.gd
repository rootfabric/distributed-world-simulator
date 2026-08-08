extends SceneTree

const LabScene = preload("res://scenes/labs/character/quaternius_layered_equipment_lab.tscn")

const REGION_TORSO_CORE := "body.region.torso.core"
const REGION_THIGHS_CORE := "body.region.thighs.core"
const REGION_SHINS_CORE := "body.region.shins.core"
const REGION_FEET_CORE := "body.region.feet.core"

const UPPER_ITEM_ID := "lab.item.layer.upper.001"
const LOWER_ITEM_ID := "lab.item.layer.lower.001"
const FEET_ITEM_ID := "lab.item.layer.feet.001"
const UPPER_PROFILE_ID := "equipment.layer.upper.peasant"
const LOWER_PROFILE_ID := "equipment.layer.lower.peasant"
const FEET_PROFILE_ID := "equipment.layer.feet.peasant"

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var lab = LabScene.instantiate()
	root.add_child(lab)
	await process_frame
	await physics_frame

	_assert(bool(lab.layered_setup_result.get("success", false)), "CH8C fix5 lab setup failed")
	_assert(lab.layered_rig_adapter != null, "CH8C fix5 layered rig adapter missing")
	_assert(lab.body_suppression_coordinator != null, "CH8C fix5 coordinator missing")
	if not bool(lab.layered_setup_result.get("success", false)):
		lab.queue_free()
		_finish()
		return

	for region_id in [REGION_TORSO_CORE, REGION_THIGHS_CORE, REGION_SHINS_CORE, REGION_FEET_CORE]:
		_assert(lab.layered_rig_adapter.supports_body_region(String(region_id)), "CH8C fix5 unsupported fine region: %s" % String(region_id))

	var body_mesh := _find_mesh(lab.avatar, "SuperHero_Male")
	_assert(body_mesh != null, "CH8C fix5 fused body mesh missing")
	if body_mesh == null:
		lab.queue_free()
		_finish()
		return

	var original_material: Material = body_mesh.material_override
	var body_aabb := body_mesh.get_aabb()
	var min_y := body_aabb.position.y
	var height := body_aabb.size.y
	var player_position_before: Vector3 = lab.player.position
	var capsule_height_before := float(lab.player_capsule.height)

	# Lower only: hide enclosed thigh and shin cores, but keep the explicit
	# knee band between them and never use the old coarse whole-leg clip.
	var lower_on: Dictionary = lab.call("_toggle_layer", LOWER_ITEM_ID, LOWER_PROFILE_ID)
	_assert(bool(lower_on.get("success", false)), "CH8C fix5 lower equip failed")
	await process_frame
	var lower_regions: Array = lab.body_suppression_coordinator.create_report().get("active_regions", [])
	_assert(lower_regions.size() == 2, "CH8C fix5 lower expected two fine regions")
	_assert(REGION_THIGHS_CORE in lower_regions, "CH8C fix5 lower lost thigh core")
	_assert(REGION_SHINS_CORE in lower_regions, "CH8C fix5 lower lost shin core")
	_assert(_shader_bool(body_mesh, "hide_thighs_core"), "CH8C fix5 lower did not hide thigh core")
	_assert(_shader_bool(body_mesh, "hide_shins_core"), "CH8C fix5 lower did not hide shin core")
	_assert(not _shader_bool(body_mesh, "hide_feet_core"), "CH8C fix5 lower unexpectedly hid foot core")
	_assert(not _shader_bool(body_mesh, "hide_legs"), "CH8C fix5 lower used coarse whole-leg suppression")
	_assert(not _shader_bool(body_mesh, "hide_feet"), "CH8C fix5 lower used coarse feet suppression")

	var shins_min := _shader_float(body_mesh, "shins_core_min_y")
	var shins_max := _shader_float(body_mesh, "shins_core_max_y")
	var thighs_min := _shader_float(body_mesh, "thighs_core_min_y")
	var thighs_max := _shader_float(body_mesh, "thighs_core_max_y")
	_assert(shins_min >= min_y + height * 0.22 and shins_min <= min_y + height * 0.26, "CH8C fix5 shin core starts outside garment overlap")
	_assert(shins_max >= min_y + height * 0.31 and shins_max <= min_y + height * 0.35, "CH8C fix5 shin core ends outside protected knee boundary")
	_assert(thighs_min >= min_y + height * 0.37 and thighs_min <= min_y + height * 0.41, "CH8C fix5 thigh core starts outside protected knee boundary")
	_assert(thighs_max <= min_y + height * 0.58, "CH8C fix5 thigh core reaches into underwear/pelvis band")
	_assert(thighs_min > shins_max, "CH8C fix5 knee band collapsed")
	_assert(thighs_min - shins_max >= height * 0.04, "CH8C fix5 knee band is too narrow")

	# Boots/feet add their own fine core. The foot cut overlaps the lower end of
	# the shin cut slightly so base geometry cannot poke through the seam.
	var feet_on: Dictionary = lab.call("_toggle_layer", FEET_ITEM_ID, FEET_PROFILE_ID)
	_assert(bool(feet_on.get("success", false)), "CH8C fix5 feet equip failed")
	await process_frame
	var lower_feet_regions: Array = lab.body_suppression_coordinator.create_report().get("active_regions", [])
	_assert(lower_feet_regions.size() == 3, "CH8C fix5 lower+feet expected three fine regions")
	_assert(REGION_FEET_CORE in lower_feet_regions, "CH8C fix5 boots lost foot core")
	_assert(_shader_bool(body_mesh, "hide_feet_core"), "CH8C fix5 boots did not hide foot/ankle core")
	_assert(not _shader_bool(body_mesh, "hide_feet"), "CH8C fix5 boots used coarse feet suppression")
	var feet_max := _shader_float(body_mesh, "feet_core_max_y")
	_assert(feet_max >= min_y + height * 0.23 and feet_max <= min_y + height * 0.27, "CH8C fix5 boot core height is outside real garment overlap")
	_assert(feet_max >= shins_min, "CH8C fix5 boot/shin cores leave a vertical poke-through seam")

	# Remove trousers: boots must retain only their own body coverage.
	var lower_off: Dictionary = lab.call("_toggle_layer", LOWER_ITEM_ID, LOWER_PROFILE_ID)
	_assert(bool(lower_off.get("success", false)), "CH8C fix5 lower unequip failed")
	await process_frame
	var feet_only_regions: Array = lab.body_suppression_coordinator.create_report().get("active_regions", [])
	_assert(feet_only_regions.size() == 1 and REGION_FEET_CORE in feet_only_regions, "CH8C fix5 feet-only coverage is not isolated")
	_assert(not _shader_bool(body_mesh, "hide_thighs_core"), "CH8C fix5 thigh core remained after lower removal")
	_assert(not _shader_bool(body_mesh, "hide_shins_core"), "CH8C fix5 shin core remained after lower removal")
	_assert(_shader_bool(body_mesh, "hide_feet_core"), "CH8C fix5 foot core disappeared with lower removal")

	# Upper remains independent and still protects underwear/pelvis by using only
	# the torso core.
	var upper_on: Dictionary = lab.call("_toggle_layer", UPPER_ITEM_ID, UPPER_PROFILE_ID)
	_assert(bool(upper_on.get("success", false)), "CH8C fix5 upper equip failed")
	await process_frame
	var upper_feet_regions: Array = lab.body_suppression_coordinator.create_report().get("active_regions", [])
	_assert(upper_feet_regions.size() == 2, "CH8C fix5 upper+feet region count mismatch")
	_assert(REGION_TORSO_CORE in upper_feet_regions, "CH8C fix5 upper lost torso core")
	_assert(REGION_FEET_CORE in upper_feet_regions, "CH8C fix5 upper composition lost foot core")
	_assert(not _shader_bool(body_mesh, "hide_arms"), "CH8C fix5 upper removed base arms")
	_assert(not _shader_bool(body_mesh, "hide_legs"), "CH8C fix5 upper composition enabled coarse legs")

	var upper_off: Dictionary = lab.call("_toggle_layer", UPPER_ITEM_ID, UPPER_PROFILE_ID)
	_assert(bool(upper_off.get("success", false)), "CH8C fix5 upper cleanup failed")
	var feet_off: Dictionary = lab.call("_toggle_layer", FEET_ITEM_ID, FEET_PROFILE_ID)
	_assert(bool(feet_off.get("success", false)), "CH8C fix5 feet cleanup failed")
	await process_frame
	_assert((lab.body_suppression_coordinator.create_report().get("active_regions", []) as Array).is_empty(), "CH8C fix5 retained coverage after cleanup")
	_assert(body_mesh.material_override == original_material, "CH8C fix5 did not restore exact original material")
	_assert(lab.player.position.is_equal_approx(player_position_before), "CH8C fix5 moved gameplay body")
	_assert(is_equal_approx(float(lab.player_capsule.height), capsule_height_before), "CH8C fix5 changed gameplay capsule")

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


func _shader_bool(mesh: MeshInstance3D, parameter: String) -> bool:
	if mesh == null or not mesh.material_override is ShaderMaterial:
		return false
	return bool((mesh.material_override as ShaderMaterial).get_shader_parameter(parameter))


func _shader_float(mesh: MeshInstance3D, parameter: String) -> float:
	if mesh == null or not mesh.material_override is ShaderMaterial:
		return NAN
	return float((mesh.material_override as ShaderMaterial).get_shader_parameter(parameter))


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH8C Quaternius lower-leg boot coverage: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH8C Quaternius lower-leg boot coverage: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
