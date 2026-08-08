extends SceneTree

const LabScene = preload("res://scenes/labs/character/quaternius_skinned_garment_lab.tscn")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("CH7.8 garment lab: phase=instantiate")
	var lab = LabScene.instantiate()
	print("CH7.8 garment lab: phase=add_child")
	root.add_child(lab)
	print("CH7.8 garment lab: phase=after_add_child")
	await process_frame
	print("CH7.8 garment lab: phase=after_process_frame")
	await physics_frame
	print("CH7.8 garment lab: phase=ready")

	_assert(lab.player is CharacterBody3D, "CH7.8 gameplay body missing")
	_assert(lab.avatar != null, "CH7.8 avatar missing")
	_assert(lab.equipment_source != null, "CH7.8 equipment source missing")
	_assert(lab.equipment_presenter != null, "CH7.8 equipment presenter missing")
	_assert(lab.outfit_available, "CH7.8 Male_Peasant outfit is not available")
	_assert(lab.body_replacement_available, "CH7.8 compatible base head replacement was not found")
	_assert(not String(lab.body_replacement_path).is_empty(), "CH7.8 head replacement path is empty")
	if not lab.outfit_available or not lab.body_replacement_available:
		print("CH7.8 garment lab: phase=setup_failed details=%s" % JSON.stringify(lab.outfit_last_result))
		lab.queue_free()
		_finish()
		return

	var model_root: Node = lab.avatar.get_node_or_null("AvatarYawRoot/QuaterniusModel")
	_assert(model_root != null, "CH7.8 QuaterniusModel missing")
	var base_visuals: Array[GeometryInstance3D] = []
	if model_root != null:
		_collect_geometry_instances(model_root, base_visuals)
	_assert(not base_visuals.is_empty(), "CH7.8 base body has no geometry to replace")
	var original_visibility: Dictionary = {}
	for base_visual in base_visuals:
		original_visibility[base_visual.get_instance_id()] = base_visual.visible

	var player_position_before: Vector3 = lab.player.position
	var capsule_height_before: float = float(lab.player_capsule.height)
	print("CH7.8 garment lab: phase=enter_first_person")
	lab.set_first_person_mode(true)
	print("CH7.8 garment lab: phase=after_enter_first_person")
	await process_frame
	var fp_before: Dictionary = lab.first_person_adapter.create_report()
	var base_world_visual_count := int(fp_before.get("world_visual_count", 0))
	var base_shadow_proxy_count := int(fp_before.get("shadow_proxy_count", 0))
	print("CH7.8 garment lab: phase=equip_call")

	var equip_result: Dictionary = lab.set_outfit_equipped(true)
	print("CH7.8 garment lab: phase=after_equip_call result=%s" % JSON.stringify(equip_result))
	await process_frame
	print("CH7.8 garment lab: phase=after_equip_frame1")
	await process_frame
	print("CH7.8 garment lab: phase=after_equip_frame2")
	_assert(bool(equip_result.get("success", false)), "CH7.8 Male_Peasant equip failed")
	_assert(lab.equipment_source.has_item(lab.OUTFIT_ITEM_ID), "CH7.8 canonical outfit state was not equipped")
	var visual: Node3D = lab.equipment_presenter.get_visual(lab.OUTFIT_ITEM_ID)
	_assert(visual != null, "CH7.8 skinned garment visual missing")
	_assert(visual != null and visual.has_method("create_report"), "CH7.8 outfit visual is not a pose bridge")
	if visual != null and visual.has_method("create_report"):
		var bridge_report: Dictionary = visual.call("create_report")
		_assert(String(bridge_report.get("schema", "")) == "planet_simulator.skinned_garment_pose_bridge.v1", "Unexpected CH7.8 bridge schema")
		_assert(int(bridge_report.get("source_bone_count", 0)) == 65, "CH7.8 source skeleton is not probed 65-bone rig")
		_assert(int(bridge_report.get("matched_bones", 0)) == 65, "CH7.8 garment does not match all 65 source bones")
		_assert(int(bridge_report.get("garment_skeleton_count", 0)) == 1, "CH7.8 garment has unexpected skeleton count")
		_assert(int(bridge_report.get("skinned_mesh_count", 0)) == 4, "CH7.8 Male_Peasant does not expose four skinned meshes")
		_assert(not bool(bridge_report.get("moves_gameplay_body", true)), "CH7.8 garment claims gameplay movement authority")

	var replacement: Node = visual.get_node_or_null("BodyReplacement") if visual != null else null
	_assert(replacement != null, "CH7.8 head body-replacement bridge missing")
	_assert(replacement != null and replacement.has_method("create_report"), "CH7.8 head replacement is not pose-driven")
	if replacement != null and replacement.has_method("create_report"):
		var replacement_report: Dictionary = replacement.call("create_report")
		_assert(int(replacement_report.get("source_bone_count", 0)) == 65, "CH7.8 head replacement source rig changed")
		_assert(int(replacement_report.get("matched_bones", 0)) == 65, "CH7.8 head replacement is not exact-rig compatible")
		_assert(int(replacement_report.get("skinned_mesh_count", 0)) >= 1, "CH7.8 head replacement has no skinned visual")

	for base_visual in base_visuals:
		_assert(not base_visual.visible, "CH7.8 base body geometry stayed visible under outfit: %s" % base_visual.name)

	var yaw_root: Node = lab.avatar.get_node_or_null("AvatarYawRoot")
	_assert(yaw_root != null, "CH7.8 AvatarYawRoot missing")
	_assert(visual != null and visual.get_parent() == yaw_root, "CH7.8 garment is outside yaw/crouch presentation root")
	var presenter_report: Dictionary = lab.equipment_presenter.create_report()
	var strategies: Dictionary = presenter_report.get("visual_strategies", {})
	_assert(String(strategies.get(lab.OUTFIT_ITEM_ID, "")) == "SKINNED_GARMENT", "CH7.8 presenter did not record SKINNED_GARMENT strategy")
	_assert(int(presenter_report.get("hidden_body_visual_count", 0)) == base_visuals.size(), "CH7.8 coarse body replacement did not hide each unique base visual exactly once")
	_assert(int(presenter_report.get("body_replacement_item_count", 0)) == 1, "CH7.8 presenter did not report one body replacement item")
	_assert((presenter_report.get("body_replacement_item_ids", []) as Array).has(lab.OUTFIT_ITEM_ID), "CH7.8 replacement report lost outfit item ID")

	var fp_outfit: Dictionary = lab.first_person_adapter.create_report()
	_assert(int(fp_outfit.get("world_visual_count", 0)) >= base_world_visual_count + 4, "CH7.8 garment meshes were not captured by CH6 world visuals")
	_assert(int(fp_outfit.get("shadow_proxy_count", 0)) >= base_shadow_proxy_count + 4, "CH7.8 garment meshes were not captured by CH6 shadow proxy")
	_assert(bool(fp_outfit.get("shadow_proxy_active", false)), "CH7.8 outfit disabled first-person shadow proxy")
	_assert(lab.player.position.is_equal_approx(player_position_before), "CH7.8 outfit moved gameplay CharacterBody3D")
	_assert(is_equal_approx(float(lab.player_capsule.height), capsule_height_before), "CH7.8 outfit modified gameplay capsule")

	print("CH7.8 garment lab: phase=motion")
	lab.avatar.apply_motion(Vector3(2.0, 0.0, 0.0), Vector3.UP, Vector3.RIGHT, {"grounded": true, "crouching": false})
	await process_frame
	if visual != null and visual.has_method("sync_pose_now"):
		var sync_result: Dictionary = visual.call("sync_pose_now")
		_assert(bool(sync_result.get("success", false)), "CH7.8 garment manual pose sync failed after locomotion")
		_assert(int(sync_result.get("details", {}).get("copied_bones", 0)) == 65, "CH7.8 locomotion sync did not copy all 65 bones")

	lab.avatar.apply_motion(Vector3.ZERO, Vector3.UP, Vector3.FORWARD, {"grounded": true, "crouching": true})
	lab.avatar.call("_update_ground_compensation", 1.0)
	await process_frame
	_assert(yaw_root is Node3D and is_equal_approx((yaw_root as Node3D).position.y, -0.35), "CH7.8 crouch presentation ground compensation changed")
	_assert(visual != null and _has_ancestor(visual, yaw_root), "CH7.8 garment escaped crouch-compensated hierarchy")

	print("CH7.8 garment lab: phase=rigid_composition")
	_assert(bool(lab.set_helmet_equipped(true).get("success", false)), "CH7.8 helmet did not coexist with skinned outfit")
	_assert(bool(lab.set_backpack_equipped(true).get("success", false)), "CH7.8 backpack did not coexist with skinned outfit")
	await process_frame
	_assert(int(lab.equipment_presenter.create_report().get("visual_count", 0)) == 3, "CH7.8 rigid + skinned composition has unexpected visual count")
	_assert(lab.equipment_presenter.get_visual(lab.OUTFIT_ITEM_ID) != null, "CH7.8 rigid equip removed skinned outfit")
	for base_visual in base_visuals:
		_assert(not base_visual.visible, "CH7.8 rigid composition restored hidden base body unexpectedly")

	print("CH7.8 garment lab: phase=unequip")
	var off_result: Dictionary = lab.set_outfit_equipped(false)
	print("CH7.8 garment lab: phase=after_unequip_call result=%s" % JSON.stringify(off_result))
	await process_frame
	_assert(bool(off_result.get("success", false)), "CH7.8 outfit unequip failed")
	_assert(not lab.equipment_source.has_item(lab.OUTFIT_ITEM_ID), "CH7.8 canonical outfit state remained equipped")
	_assert(lab.equipment_presenter.get_visual(lab.OUTFIT_ITEM_ID) == null, "CH7.8 skinned visual remained registered after unequip")
	_assert(int(lab.equipment_presenter.create_report().get("visual_count", 0)) == 2, "CH7.8 outfit removal damaged rigid equipment composition")
	_assert(int(lab.equipment_presenter.create_report().get("hidden_body_visual_count", -1)) == 0, "CH7.8 body hide state remained after outfit removal")
	_assert(int(lab.equipment_presenter.create_report().get("body_replacement_item_count", -1)) == 0, "CH7.8 head replacement remained registered after outfit removal")
	for base_visual in base_visuals:
		var expected_visible := bool(original_visibility.get(base_visual.get_instance_id(), true))
		_assert(base_visual.visible == expected_visible, "CH7.8 base body visibility was not restored exactly: %s" % base_visual.name)
	_assert(lab.player.position.is_equal_approx(player_position_before), "CH7.8 lifecycle moved gameplay body")
	_assert(is_equal_approx(float(lab.player_capsule.height), capsule_height_before), "CH7.8 lifecycle modified gameplay capsule")

	print("CH7.8 garment lab: phase=finish")
	lab.queue_free()
	_finish()


func _collect_geometry_instances(root_node: Node, output: Array[GeometryInstance3D]) -> void:
	if root_node is GeometryInstance3D:
		output.append(root_node as GeometryInstance3D)
	for child in root_node.get_children():
		_collect_geometry_instances(child, output)


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
		print("CH7.8 Quaternius skinned garment lab: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH7.8 Quaternius skinned garment lab: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
