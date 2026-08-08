extends SceneTree

const LabScene = preload("res://scenes/labs/character/quaternius_equipment_lab.tscn")
const Domain = preload("res://scripts/characters/equipment/character_equipment_domain.gd")
const Factory = preload("res://scripts/characters/equipment/selective_garment_scene_factory.gd")
const Catalog = preload("res://scripts/characters/equipment/wearable_presentation_catalog.gd")
const CoverageCatalog = preload("res://scripts/characters/equipment/wearable_body_coverage_catalog.gd")
const Coordinator = preload("res://scripts/characters/equipment/layered_body_suppression_coordinator.gd")
const LayeredRigAdapter = preload("res://scripts/characters/equipment/quaternius_layered_body_suppression_adapter.gd")
const MALE_PEASANT_PATH := "res://assets/external/quaternius/modular_outfits_fantasy/Modular Character Outfits - Fantasy[Standard]/Exports/glTF (Godot-Unreal)/Outfits/Male_Peasant.gltf"

const REGION_TORSO_CORE := "body.region.torso.core"
const REGION_THIGHS_CORE := "body.region.thighs.core"

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var lab = LabScene.instantiate()
	root.add_child(lab)
	await process_frame
	await physics_frame
	_assert(lab.equipment_source != null, "CH8C equipment source missing")
	_assert(lab.equipment_presenter != null, "CH8C equipment presenter missing")
	_assert(lab.wearable_catalog != null, "CH8C wearable catalog missing")
	if lab.equipment_source == null or lab.equipment_presenter == null or lab.wearable_catalog == null:
		lab.queue_free()
		_finish()
		return

	var loaded = load(MALE_PEASANT_PATH)
	_assert(loaded is PackedScene, "CH8C Male_Peasant source scene missing")
	if not loaded is PackedScene:
		lab.queue_free()
		_finish()
		return
	var source_scene := loaded as PackedScene

	var definitions := [
		{
			"item": "lab.item.layer.upper.001",
			"profile": "equipment.layer.upper.peasant",
			"presentation": "wearable.layer.upper.peasant",
			"channels": ["body.torso.outer", "body.arms.outer"],
			"meshes": ["Male_Peasant_Body", "Male_Peasant_Arms"],
			"regions": [REGION_TORSO_CORE]
		},
		{
			"item": "lab.item.layer.lower.001",
			"profile": "equipment.layer.lower.peasant",
			"presentation": "wearable.layer.lower.peasant",
			"channels": ["body.legs.outer"],
			"meshes": ["Male_Peasant_Legs"],
			"regions": [REGION_THIGHS_CORE]
		},
		{
			"item": "lab.item.layer.feet.001",
			"profile": "equipment.layer.feet.peasant",
			"presentation": "wearable.layer.feet.peasant",
			"channels": ["body.feet"],
			"meshes": ["Male_Peasant_Feet"],
			"regions": []
		}
	]

	var layered_adapter = LayeredRigAdapter.new()
	var bind_result: Dictionary = layered_adapter.bind_presenter(lab.avatar)
	_assert(bool(bind_result.get("success", false)), "CH8C layered Quaternius adapter bind failed")
	_assert(layered_adapter.supports_body_region(REGION_TORSO_CORE), "CH8C layered adapter lacks torso core region")
	_assert(layered_adapter.supports_body_region(REGION_THIGHS_CORE), "CH8C layered adapter lacks thighs core region")
	var coverage = CoverageCatalog.new()
	var coordinator = Coordinator.new()
	var coordinator_setup: Dictionary = coordinator.setup(lab.avatar, layered_adapter, coverage)
	_assert(bool(coordinator_setup.get("success", false)), "CH8C suppression coordinator setup failed")

	for definition in definitions:
		var profile := Domain.Profile.new(
			String(definition["profile"]),
			String(definition["presentation"]),
			"body.root",
			definition["channels"],
			[], [], ["equipment.clothing"]
		)
		_assert(bool(lab.equipment_source.register_profile(profile).get("success", false)), "CH8C profile registration failed")
		var selected: Dictionary = Factory.create(source_scene, definition["meshes"])
		_assert(bool(selected.get("success", false)), "CH8C selective garment scene failed")
		if not bool(selected.get("success", false)):
			continue
		var selected_scene = selected.get("details", {}).get("scene")
		_assert(selected_scene is PackedScene, "CH8C selective garment scene was not packed")
		if selected_scene is PackedScene:
			var registration: Dictionary = lab.wearable_catalog.register_scene(
				String(definition["presentation"]),
				lab.equipment_rig_adapter.rig_profile_id,
				Catalog.STRATEGY_SKINNED_GARMENT,
				selected_scene as PackedScene
			)
			_assert(bool(registration.get("success", false)), "CH8C garment presentation registration failed")
		var coverage_registration: Dictionary = coverage.register_coverage(
			String(definition["presentation"]),
			layered_adapter.rig_profile_id,
			definition["regions"]
		)
		_assert(bool(coverage_registration.get("success", false)), "CH8C body coverage registration failed")

	var body_mesh := _find_mesh(lab.avatar, "SuperHero_Male")
	var eyes := _find_mesh(lab.avatar, "Eyes")
	var eyebrows := _find_mesh(lab.avatar, "Eyebrows")
	_assert(body_mesh != null, "CH8C fused SuperHero_Male mesh missing")
	_assert(eyes != null, "CH8C Eyes mesh missing")
	_assert(eyebrows != null, "CH8C Eyebrows mesh missing")
	if body_mesh == null:
		coordinator.clear()
		layered_adapter.clear()
		lab.queue_free()
		_finish()
		return
	var original_material: Material = body_mesh.material_override
	var body_aabb := body_mesh.get_aabb()
	var player_position_before: Vector3 = lab.player.position
	var capsule_height_before := float(lab.player_capsule.height)

	lab.set_first_person_mode(true)
	await process_frame

	var upper: Dictionary = lab.call("_set_item_equipped", "lab.item.layer.upper.001", "equipment.layer.upper.peasant", true)
	_assert(bool(upper.get("success", false)), "CH8C upper equip failed")
	var upper_suppression: Dictionary = coordinator.apply_snapshot(lab.equipment_source.get_snapshot())
	_assert(bool(upper_suppression.get("success", false)), "CH8C upper suppression failed")
	await process_frame
	_assert(_shader_bool(body_mesh, "hide_torso_core"), "CH8C upper did not suppress torso core")
	_assert(not _shader_bool(body_mesh, "hide_thighs_core"), "CH8C upper unexpectedly suppressed thigh core")
	_assert(not _shader_bool(body_mesh, "hide_torso"), "CH8C upper unexpectedly used coarse torso suppression")
	_assert(not _shader_bool(body_mesh, "hide_arms"), "CH8C upper unexpectedly removed base arms")
	_assert(not _shader_bool(body_mesh, "hide_legs"), "CH8C upper unexpectedly removed base legs")
	_assert(not _shader_bool(body_mesh, "hide_feet"), "CH8C upper unexpectedly removed base feet")
	var torso_core_min_y := _shader_float(body_mesh, "torso_core_min_y")
	_assert(torso_core_min_y >= body_aabb.position.y + body_aabb.size.y * 0.54, "CH8C torso core cuts too low into underwear/pelvis band")
	_assert(torso_core_min_y <= body_aabb.position.y + body_aabb.size.y * 0.60, "CH8C torso core protected band is unexpectedly large")
	var upper_material: Material = body_mesh.material_override
	_assert(upper_material is ShaderMaterial, "CH8C upper did not install protected region clip material")

	var helmet: Dictionary = lab.set_helmet_equipped(true)
	_assert(bool(helmet.get("success", false)), "CH8C unrelated helmet equip failed")
	var unchanged_regions: Dictionary = coordinator.apply_snapshot(lab.equipment_source.get_snapshot())
	_assert(bool(unchanged_regions.get("success", false)), "CH8C unchanged coverage apply failed")
	_assert(not bool(unchanged_regions.get("details", {}).get("changed", true)), "CH8C unrelated item rebuilt unchanged body coverage")
	_assert(body_mesh.material_override == upper_material, "CH8C unchanged coverage replaced material identity")

	var lower: Dictionary = lab.call("_set_item_equipped", "lab.item.layer.lower.001", "equipment.layer.lower.peasant", true)
	_assert(bool(lower.get("success", false)), "CH8C lower equip failed")
	var upper_lower: Dictionary = coordinator.apply_snapshot(lab.equipment_source.get_snapshot())
	_assert(bool(upper_lower.get("success", false)), "CH8C upper+lower suppression failed")
	await process_frame
	_assert(_shader_bool(body_mesh, "hide_torso_core"), "CH8C upper+lower lost torso core suppression")
	_assert(_shader_bool(body_mesh, "hide_thighs_core"), "CH8C lower did not add thigh core suppression")
	_assert(not _shader_bool(body_mesh, "hide_arms"), "CH8C lower composition removed base arms")
	_assert(not _shader_bool(body_mesh, "hide_legs"), "CH8C lower unexpectedly used coarse leg suppression")
	_assert(not _shader_bool(body_mesh, "hide_feet"), "CH8C lower unexpectedly removed base feet")
	var thighs_core_min_y := _shader_float(body_mesh, "thighs_core_min_y")
	var thighs_core_max_y := _shader_float(body_mesh, "thighs_core_max_y")
	_assert(thighs_core_min_y >= body_aabb.position.y + body_aabb.size.y * 0.37, "CH8C thigh core cuts into protected knee/lower-leg band")
	_assert(thighs_core_max_y <= body_aabb.position.y + body_aabb.size.y * 0.58, "CH8C thigh core cuts too high into pelvis/underwear band")
	var upper_lower_material: Material = body_mesh.material_override

	var feet_result: Dictionary = lab.call("_set_item_equipped", "lab.item.layer.feet.001", "equipment.layer.feet.peasant", true)
	_assert(bool(feet_result.get("success", false)), "CH8C feet equip failed")
	var feet_overlay: Dictionary = coordinator.apply_snapshot(lab.equipment_source.get_snapshot())
	_assert(bool(feet_overlay.get("success", false)), "CH8C feet overlay recomposition failed")
	_assert(not bool(feet_overlay.get("details", {}).get("changed", true)), "CH8C overlay-only feet unexpectedly rebuilt body mask")
	_assert(body_mesh.material_override == upper_lower_material, "CH8C overlay-only feet replaced aggregate material")
	_assert(not _shader_bool(body_mesh, "hide_feet"), "CH8C overlay-only feet removed base extremity")

	var coordinator_report: Dictionary = coordinator.create_report()
	var active_regions: Array = coordinator_report.get("active_regions", [])
	_assert(active_regions.size() == 2, "CH8C protected aggregate expected exactly two fine regions")
	_assert(REGION_TORSO_CORE in active_regions, "CH8C aggregate report lost torso core")
	_assert(REGION_THIGHS_CORE in active_regions, "CH8C aggregate report lost thighs core")
	_assert(String(coordinator_report.get("target_name", "")) == "SuperHero_Male", "CH8C aggregate target is not fused body mesh")
	_assert(not bool(coordinator_report.get("moves_gameplay_body", true)), "CH8C coordinator claims gameplay body authority")
	_assert(not bool(coordinator_report.get("owns_network_state", true)), "CH8C coordinator claims network authority")
	_assert(eyes == null or eyes.visible, "CH8C suppression hid Eyes mesh")
	_assert(eyebrows == null or eyebrows.visible, "CH8C suppression hid Eyebrows mesh")

	var lower_off: Dictionary = lab.call("_set_item_equipped", "lab.item.layer.lower.001", "equipment.layer.lower.peasant", false)
	_assert(bool(lower_off.get("success", false)), "CH8C lower unequip failed")
	var without_lower: Dictionary = coordinator.apply_snapshot(lab.equipment_source.get_snapshot())
	_assert(bool(without_lower.get("success", false)), "CH8C suppression recomposition after lower unequip failed")
	await process_frame
	_assert(_shader_bool(body_mesh, "hide_torso_core"), "CH8C removing lower damaged torso core suppression")
	_assert(not _shader_bool(body_mesh, "hide_thighs_core"), "CH8C thigh core remained after lower unequip")
	_assert(not _shader_bool(body_mesh, "hide_arms"), "CH8C removing lower removed base arms")
	_assert(not _shader_bool(body_mesh, "hide_legs"), "CH8C removing lower enabled coarse legs")
	_assert(not _shader_bool(body_mesh, "hide_feet"), "CH8C removing lower removed base feet")

	var upper_off: Dictionary = lab.call("_set_item_equipped", "lab.item.layer.upper.001", "equipment.layer.upper.peasant", false)
	_assert(bool(upper_off.get("success", false)), "CH8C upper unequip failed")
	var feet_only_recompose: Dictionary = coordinator.apply_snapshot(lab.equipment_source.get_snapshot())
	_assert(bool(feet_only_recompose.get("success", false)), "CH8C feet-only body coverage apply failed")
	await process_frame
	_assert(body_mesh.material_override == original_material, "CH8C feet-only overlay did not restore exact original material_override")
	_assert((coordinator.create_report().get("active_regions", []) as Array).is_empty(), "CH8C feet-only overlay retained body suppression regions")

	var feet_off: Dictionary = lab.call("_set_item_equipped", "lab.item.layer.feet.001", "equipment.layer.feet.peasant", false)
	_assert(bool(feet_off.get("success", false)), "CH8C feet cleanup failed")
	var empty_recompose: Dictionary = coordinator.apply_snapshot(lab.equipment_source.get_snapshot())
	_assert(bool(empty_recompose.get("success", false)), "CH8C final empty recomposition failed")
	_assert(body_mesh.material_override == original_material, "CH8C final cleanup changed original material_override")

	var fp_report: Dictionary = lab.first_person_adapter.create_report()
	_assert(bool(fp_report.get("shadow_proxy_active", false)), "CH8C disabled first-person shadow proxy")
	_assert(lab.player.position.is_equal_approx(player_position_before), "CH8C moved gameplay CharacterBody3D")
	_assert(is_equal_approx(float(lab.player_capsule.height), capsule_height_before), "CH8C changed gameplay capsule")

	var helmet_off: Dictionary = lab.set_helmet_equipped(false)
	_assert(bool(helmet_off.get("success", false)), "CH8C helmet cleanup failed")
	coordinator.clear()
	layered_adapter.clear()
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
		print("CH8C Quaternius protected layered body suppression: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH8C Quaternius protected layered body suppression: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
