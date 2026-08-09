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
	lab.body_fit_policy = "TOPOLOGY_OCCLUSION"
	root.add_child(lab)
	await process_frame
	await physics_frame

	_assert(bool(lab.layered_setup_result.get("success", false)), "CH8C topology lab setup failed: %s" % JSON.stringify(lab.layered_setup_result))
	_assert(lab.body_topology_catalog != null, "CH8C topology catalog missing")
	_assert(lab.body_topology_coordinator != null, "CH8C topology coordinator missing")
	if not bool(lab.layered_setup_result.get("success", false)):
		lab.queue_free()
		_finish()
		return

	var body_mesh := _find_mesh(lab.avatar, "SuperHero_Male")
	_assert(body_mesh != null, "CH8C topology fused body mesh missing")
	if body_mesh == null:
		lab.queue_free()
		_finish()
		return
	var original_mesh: Mesh = body_mesh.mesh
	var original_material: Material = body_mesh.material_override
	_assert(original_mesh is ArrayMesh, "CH8C topology original body is not ArrayMesh")
	if not original_mesh is ArrayMesh:
		lab.queue_free()
		_finish()
		return
	var original_arrays: Array = (original_mesh as ArrayMesh).surface_get_arrays(0)
	var original_indices: PackedInt32Array = original_arrays[Mesh.ARRAY_INDEX]
	var original_bones: PackedInt32Array = original_arrays[Mesh.ARRAY_BONES]
	var original_weights: PackedFloat32Array = original_arrays[Mesh.ARRAY_WEIGHTS]
	_assert(not original_indices.is_empty(), "CH8C topology original body has no indices")
	_assert(not original_bones.is_empty(), "CH8C topology original body has no bone array")
	_assert(not original_weights.is_empty(), "CH8C topology original body has no weight array")

	var player_position_before: Vector3 = lab.player.position
	var capsule_height_before := float(lab.player_capsule.height)
	var lower_on: Dictionary = lab.call("_toggle_layer", LOWER_ITEM_ID, LOWER_PROFILE_ID)
	_assert(bool(lower_on.get("success", false)), "CH8C topology lower equip failed")
	await process_frame
	var lower_report: Dictionary = lab.body_topology_coordinator.create_report()
	_assert(bool(lower_report.get("mesh_applied", false)), "CH8C topology lower did not apply a derived body mesh")
	_assert((lower_report.get("active_presentations", []) as Array).size() == 1, "CH8C topology lower expected one occlusion presentation")
	_assert(int(lower_report.get("removed_triangles", 0)) > 0, "CH8C topology lower removed no body triangles")
	_assert(int(lower_report.get("removed_triangles", 0)) < int(lower_report.get("total_triangles", 0)), "CH8C topology lower removed the complete body")
	_assert(body_mesh.mesh != original_mesh, "CH8C topology lower kept the original body mesh")
	_assert(body_mesh.material_override == original_material, "CH8C topology lower changed base-body material")
	_assert((lab.body_suppression_coordinator.create_report().get("active_regions", []) as Array).is_empty(), "CH8C topology lower unexpectedly enabled material body suppression")

	if body_mesh.mesh is ArrayMesh:
		var masked_arrays: Array = (body_mesh.mesh as ArrayMesh).surface_get_arrays(0)
		var masked_indices: PackedInt32Array = masked_arrays[Mesh.ARRAY_INDEX]
		var masked_bones: PackedInt32Array = masked_arrays[Mesh.ARRAY_BONES]
		var masked_weights: PackedFloat32Array = masked_arrays[Mesh.ARRAY_WEIGHTS]
		_assert(masked_indices.size() < original_indices.size(), "CH8C topology lower index count was not reduced")
		_assert(masked_bones.size() == original_bones.size(), "CH8C topology lower changed bone array size")
		_assert(masked_weights.size() == original_weights.size(), "CH8C topology lower changed weight array size")

	var lower_removed := int(lower_report.get("removed_triangles", 0))
	var feet_on: Dictionary = lab.call("_toggle_layer", FEET_ITEM_ID, FEET_PROFILE_ID)
	_assert(bool(feet_on.get("success", false)), "CH8C topology feet equip failed")
	await process_frame
	var lower_feet_report: Dictionary = lab.body_topology_coordinator.create_report()
	_assert((lower_feet_report.get("active_presentations", []) as Array).size() == 2, "CH8C topology lower+feet expected two occlusion presentations")
	_assert(int(lower_feet_report.get("removed_triangles", 0)) >= lower_removed, "CH8C topology adding feet unexpectedly restored covered body triangles")
	_assert(body_mesh.material_override == original_material, "CH8C topology lower+feet changed base-body material")

	var lower_off: Dictionary = lab.call("_toggle_layer", LOWER_ITEM_ID, LOWER_PROFILE_ID)
	_assert(bool(lower_off.get("success", false)), "CH8C topology lower unequip failed")
	await process_frame
	var feet_only_report: Dictionary = lab.body_topology_coordinator.create_report()
	_assert((feet_only_report.get("active_presentations", []) as Array).size() == 1, "CH8C topology feet-only expected one occlusion presentation")
	_assert(int(feet_only_report.get("removed_triangles", 0)) > 0, "CH8C topology feet-only removed no body triangles")
	_assert(body_mesh.mesh != original_mesh, "CH8C topology feet-only unexpectedly restored original mesh")

	var feet_off: Dictionary = lab.call("_toggle_layer", FEET_ITEM_ID, FEET_PROFILE_ID)
	_assert(bool(feet_off.get("success", false)), "CH8C topology feet unequip failed")
	await process_frame
	_assert(body_mesh.mesh == original_mesh, "CH8C topology final lower/feet removal did not restore exact original mesh")
	_assert((lab.body_topology_coordinator.create_report().get("active_presentations", []) as Array).is_empty(), "CH8C topology coordinator retained presentations after clear")

	var upper_on: Dictionary = lab.call("_toggle_layer", UPPER_ITEM_ID, UPPER_PROFILE_ID)
	_assert(bool(upper_on.get("success", false)), "CH8C topology upper equip failed")
	await process_frame
	_assert(body_mesh.mesh == original_mesh, "CH8C topology upper unexpectedly changed body mesh")
	var upper_regions: Array = lab.body_suppression_coordinator.create_report().get("active_regions", [])
	_assert(upper_regions.size() == 1 and REGION_TORSO_CORE in upper_regions, "CH8C topology upper lost torso-core suppression")
	_assert((lab.body_topology_coordinator.create_report().get("active_presentations", []) as Array).is_empty(), "CH8C topology upper unexpectedly contributed a topology mask")

	var upper_off: Dictionary = lab.call("_toggle_layer", UPPER_ITEM_ID, UPPER_PROFILE_ID)
	_assert(bool(upper_off.get("success", false)), "CH8C topology upper unequip failed")
	await process_frame
	_assert(body_mesh.mesh == original_mesh, "CH8C topology upper cleanup changed original mesh")
	_assert(body_mesh.material_override == original_material, "CH8C topology upper cleanup did not restore original material")
	_assert(lab.player.position.is_equal_approx(player_position_before), "CH8C topology moved gameplay CharacterBody3D")
	_assert(is_equal_approx(float(lab.player_capsule.height), capsule_height_before), "CH8C topology changed gameplay capsule")

	lab.body_topology_coordinator.clear()
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
		print("CH8C Quaternius topology-aware occlusion fallback: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH8C Quaternius topology-aware occlusion fallback: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
