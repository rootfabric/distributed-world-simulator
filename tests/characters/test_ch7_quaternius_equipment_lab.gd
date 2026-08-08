extends SceneTree

const LabScene = preload("res://scenes/labs/character/quaternius_equipment_lab.tscn")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var lab = LabScene.instantiate()
	root.add_child(lab)
	await process_frame
	await physics_frame

	_assert(lab.player is CharacterBody3D, "CH7 lab gameplay body missing")
	_assert(lab.avatar != null, "CH7 lab avatar missing")
	_assert(lab.equipment_source != null, "CH7 lab equipment source missing")
	_assert(lab.equipment_presenter != null, "CH7 lab equipment presenter missing")
	_assert(lab.equipment_rig_adapter != null, "CH7 lab rig adapter missing")
	_assert(lab.wearable_catalog != null, "CH7 lab wearable catalog missing")
	_assert(lab.first_person_adapter != null and lab.first_person_adapter.has_method("refresh_presentation_visuals"), "CH7 lab did not upgrade to equipment-aware view adapter")
	_assert(lab.equipment_source.get_snapshot().entries().is_empty(), "CH7 lab must start with no equipment")

	var player_position_before: Vector3 = lab.player.position
	var capsule_height_before: float = float(lab.player_capsule.height)
	lab.set_first_person_mode(true)
	await process_frame
	var fp_before: Dictionary = lab.first_person_adapter.create_report()
	var base_world_visual_count: int = int(fp_before.get("world_visual_count", 0))
	var base_shadow_proxy_count: int = int(fp_before.get("shadow_proxy_count", 0))
	_assert(bool(fp_before.get("world_hidden_from_first_person", false)), "CH7 first-person policy does not hide own world presentation")
	_assert(bool(fp_before.get("shadow_proxy_active", false)), "CH7 first-person shadow proxy is not active before equipment")

	var helmet_result: Dictionary = lab.set_helmet_equipped(true)
	_assert(bool(helmet_result.get("success", false)), "Helmet equip failed in CH7 lab")
	_assert(lab.equipment_source.has_item(lab.HELMET_ITEM_ID), "Helmet canonical lab state was not equipped")
	var helmet_visual: Node3D = lab.equipment_presenter.get_visual(lab.HELMET_ITEM_ID)
	_assert(helmet_visual != null, "Helmet presentation visual missing")
	_assert(_count_nodes_of_type(helmet_visual, MeshInstance3D) == 2, "Helmet synthetic visual must contain shell and visor")
	_assert(_has_ancestor(helmet_visual, lab.avatar), "Helmet visual is outside avatar presentation hierarchy")
	var helmet_parent: Node = helmet_visual.get_parent()
	var rig_mode: String = String(lab.equipment_rig_adapter.create_report().get("mode", ""))
	if rig_mode == "SKELETON":
		_assert(helmet_parent is BoneAttachment3D, "Quaternius helmet is not attached through BoneAttachment3D")
	else:
		_assert(helmet_parent is Node3D and String(helmet_parent.name) == "Head", "Fallback helmet did not attach to Head pivot")

	var fp_helmet: Dictionary = lab.first_person_adapter.create_report()
	var world_mask: int = int(fp_helmet.get("world_render_layer_mask", 0))
	_assert(world_mask != 0, "CH7 world render layer mask is invalid")
	_assert(_all_visuals_use_layer(helmet_visual, world_mask), "Helmet visuals were not recaptured into CH6 world render layer")
	_assert((lab.first_person_camera.cull_mask & world_mask) == 0, "First-person camera can render equipped helmet")
	_assert((lab.third_person_camera.cull_mask & world_mask) != 0, "Third-person camera cannot render equipped helmet")
	_assert(int(fp_helmet.get("world_visual_count", 0)) >= base_world_visual_count + 2, "Dynamic helmet visuals were not added to CH6 world visual capture")
	_assert(int(fp_helmet.get("shadow_proxy_count", 0)) >= base_shadow_proxy_count + 2, "Dynamic helmet visuals were not added to first-person shadow proxy")
	_assert(bool(fp_helmet.get("shadow_proxy_active", false)), "Helmet refresh disabled first-person shadow proxy")

	var backpack_result: Dictionary = lab.set_backpack_equipped(true)
	_assert(bool(backpack_result.get("success", false)), "Backpack equip failed in CH7 lab")
	_assert(lab.equipment_source.has_item(lab.BACKPACK_ITEM_ID), "Backpack canonical lab state was not equipped")
	var backpack_visual: Node3D = lab.equipment_presenter.get_visual(lab.BACKPACK_ITEM_ID)
	_assert(backpack_visual != null, "Backpack presentation visual missing")
	_assert(_count_nodes_of_type(backpack_visual, MeshInstance3D) == 3, "Backpack synthetic visual must contain pack and two tanks")
	_assert(_has_ancestor(backpack_visual, lab.avatar), "Backpack visual is outside avatar presentation hierarchy")
	_assert(_all_visuals_use_layer(backpack_visual, world_mask), "Backpack visuals were not recaptured into CH6 world render layer")
	var fp_full: Dictionary = lab.first_person_adapter.create_report()
	_assert(int(fp_full.get("world_visual_count", 0)) >= base_world_visual_count + 5, "Helmet + backpack visual capture is incomplete")
	_assert(int(fp_full.get("shadow_proxy_count", 0)) >= base_shadow_proxy_count + 5, "Helmet + backpack shadow capture is incomplete")
	_assert((lab.first_person_camera.cull_mask & world_mask) == 0, "First-person camera regained equipped world visuals after backpack equip")

	_assert(lab.player.position.is_equal_approx(player_position_before), "Equipment changes moved gameplay CharacterBody3D")
	_assert(is_equal_approx(float(lab.player_capsule.height), capsule_height_before), "Equipment changes modified gameplay collision capsule")

	var helmet_off: Dictionary = lab.set_helmet_equipped(false)
	_assert(bool(helmet_off.get("success", false)), "Helmet unequip failed in CH7 lab")
	_assert(not lab.equipment_source.has_item(lab.HELMET_ITEM_ID), "Helmet canonical lab state remained equipped")
	_assert(lab.equipment_presenter.get_visual(lab.HELMET_ITEM_ID) == null, "Helmet visual remained registered after unequip")
	var fp_without_helmet: Dictionary = lab.first_person_adapter.create_report()
	_assert(int(fp_without_helmet.get("world_visual_count", 0)) < int(fp_full.get("world_visual_count", 0)), "Unequipped helmet remained in CH6 world visual capture")
	_assert(int(fp_without_helmet.get("shadow_proxy_count", 0)) < int(fp_full.get("shadow_proxy_count", 0)), "Unequipped helmet remained in CH6 shadow proxy")

	for cycle in range(25):
		_assert(bool(lab.set_backpack_equipped(false).get("success", false)), "Backpack lifecycle unequip failed at cycle %d" % cycle)
		_assert(lab.equipment_presenter.get_visual(lab.BACKPACK_ITEM_ID) == null, "Backpack visual leaked after unequip at cycle %d" % cycle)
		_assert(bool(lab.set_backpack_equipped(true).get("success", false)), "Backpack lifecycle equip failed at cycle %d" % cycle)
		_assert(lab.equipment_presenter.get_visual(lab.BACKPACK_ITEM_ID) != null, "Backpack visual missing after re-equip at cycle %d" % cycle)
	await process_frame
	var lifecycle_report: Dictionary = lab.equipment_presenter.create_report()
	_assert(int(lifecycle_report.get("visual_count", 0)) == 1, "Lifecycle stress left duplicate equipment visuals")
	_assert((lifecycle_report.get("visual_item_ids", []) as Array).has(lab.BACKPACK_ITEM_ID), "Lifecycle stress lost canonical backpack presentation")
	_assert(lab.player.position.is_equal_approx(player_position_before), "Equipment lifecycle stress moved gameplay CharacterBody3D")
	_assert(is_equal_approx(float(lab.player_capsule.height), capsule_height_before), "Equipment lifecycle stress modified collision capsule")

	lab.set_first_person_mode(false)
	await process_frame
	var tp_report: Dictionary = lab.first_person_adapter.create_report()
	_assert(not bool(tp_report.get("shadow_proxy_active", true)), "First-person shadow proxy stayed active in third person")
	_assert((lab.third_person_camera.cull_mask & world_mask) != 0, "Third-person camera lost equipment world render layer")
	_assert(lab.equipment_presenter.get_visual(lab.BACKPACK_ITEM_ID) != null, "View switch removed equipped backpack")

	var lab_source: String = FileAccess.get_file_as_string("res://scripts/characters/lab/quaternius_equipment_lab.gd")
	_assert(not lab_source.contains("move_and_slide"), "CH7 equipment lab extension gained independent gameplay movement")
	_assert(not lab_source.contains("multiplayer"), "CH7 equipment lab extension gained network dependency")
	_assert(not lab_source.contains("ItemGraph"), "CH7 lab pretends to be production Item Graph integration")

	lab.queue_free()
	_finish()


func _all_visuals_use_layer(root_node: Node, expected_layer: int) -> bool:
	var visuals: Array[VisualInstance3D] = []
	_collect_visuals(root_node, visuals)
	if visuals.is_empty():
		return false
	for visual in visuals:
		if visual.layers != expected_layer:
			return false
	return true


func _collect_visuals(root_node: Node, output: Array[VisualInstance3D]) -> void:
	if root_node is VisualInstance3D:
		output.append(root_node as VisualInstance3D)
	for child in root_node.get_children():
		_collect_visuals(child, output)


func _count_nodes_of_type(node: Node, type_value: Variant) -> int:
	var count := 0
	for child in node.get_children():
		if is_instance_of(child, type_value):
			count += 1
		count += _count_nodes_of_type(child, type_value)
	return count


func _has_ancestor(node: Node, expected_ancestor: Node) -> bool:
	var current: Node = node
	while current != null:
		if current == expected_ancestor:
			return true
		current = current.get_parent()
	return false


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH7 Quaternius equipment lab: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH7 Quaternius equipment lab: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
