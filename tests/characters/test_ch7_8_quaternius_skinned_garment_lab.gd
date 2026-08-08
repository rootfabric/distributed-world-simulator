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
	_assert(lab.body_suppression_available, "CH7.8 fused-body suppression is not available")
	_assert(lab.body_suppression_mode == CharacterRigAdapter.BODY_SUPPRESSION_MATERIAL_OVERRIDE, "CH7.8 did not select material head clipping")
	_assert(lab.head_clip_local_y > 1.2 and lab.head_clip_local_y < 1.7, "CH7.8 derived head clip plane is implausible")
	if not lab.outfit_available or not lab.body_suppression_available:
		print("CH7.8 garment lab: phase=setup_failed details=%s" % JSON.stringify(lab.outfit_last_result))
		lab.queue_free()
		_finish()
		return

	var resolved_body_visuals: Array = lab.equipment_rig_adapter.resolve_body_region_visuals(
		lab.avatar,
		"body.region.torso"
	)
	_assert(resolved_body_visuals.size() == 1, "CH7.8 expected one fused SuperHero_Male body mesh")
	var base_body: MeshInstance3D = null
	if resolved_body_visuals.size() == 1 and resolved_body_visuals[0] is MeshInstance3D:
		base_body = resolved_body_visuals[0] as MeshInstance3D
	_assert(base_body != null, "CH7.8 fused base body mesh missing")
	if base_body == null:
		lab.queue_free()
		_finish()
		return
	_assert(String(base_body.name).to_lower().contains("superhero"), "CH7.8 body resolver selected unexpected mesh")
	var original_material_override: Material = base_body.material_override
	var eyes := _find_mesh_named(lab.avatar, "Eyes")
	var eyebrows := _find_mesh_named(lab.avatar, "Eyebrows")
	_assert(eyes != null, "CH7.8 separate Eyes mesh missing")
	_assert(eyebrows != null, "CH7.8 separate Eyebrows mesh missing")
	_assert(eyes == null or eyes.visible, "CH7.8 Eyes are not initially visible")
	_assert(eyebrows == null or eyebrows.visible, "CH7.8 Eyebrows are not initially visible")

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

	_assert(base_body.visible, "CH7.8 fused base mesh should stay visible for head-only clipping")
	_assert(base_body.material_override is ShaderMaterial, "CH7.8 fused base mesh did not receive head clip material")
	_assert(base_body.material_override != original_material_override, "CH7.8 head clip did not replace base presentation material")
	if base_body.material_override is ShaderMaterial:
		var clip_material := base_body.material_override as ShaderMaterial
		_assert(is_equal_approx(float(clip_material.get_shader_parameter("clip_local_y")), lab.head_clip_local_y), "CH7.8 applied clip plane differs from rig-derived value")
	_assert(eyes == null or eyes.visible, "CH7.8 head clip hid Eyes")
	_assert(eyebrows == null or eyebrows.visible, "CH7.8 head clip hid Eyebrows")

	var yaw_root: Node = lab.avatar.get_node_or_null("AvatarYawRoot")
	_assert(yaw_root != null, "CH7.8 AvatarYawRoot missing")
	_assert(visual != null and visual.get_parent() == yaw_root, "CH7.8 garment is outside yaw/crouch presentation root")
	var presenter_report: Dictionary = lab.equipment_presenter.create_report()
	var strategies: Dictionary = presenter_report.get("visual_strategies", {})
	_assert(String(strategies.get(lab.OUTFIT_ITEM_ID, "")) == "SKINNED_GARMENT", "CH7.8 presenter did not record SKINNED_GARMENT strategy")
	_assert(int(presenter_report.get("hidden_body_visual_count", -1)) == 0, "CH7.8 fused body unexpectedly used whole-mesh hiding")
	_assert(int(presenter_report.get("material_clipped_body_visual_count", 0)) == 1, "CH7.8 did not report one material-clipped fused body")
	_assert(int(presenter_report.get("suppressed_body_target_count", 0)) == 1, "CH7.8 semantic regions did not deduplicate onto one fused body target")
	_assert(int(presenter_report.get("body_replacement_item_count", -1)) == 0, "CH7.8 should not instantiate a second head skeleton")

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
	_assert(base_body.material_override is ShaderMaterial, "CH7.8 motion/crouch lost fused-body head clip")

	print("CH7.8 garment lab: phase=rigid_composition")
	_assert(bool(lab.set_helmet_equipped(true).get("success", false)), "CH7.8 helmet did not coexist with skinned outfit")
	_assert(bool(lab.set_backpack_equipped(true).get("success", false)), "CH7.8 backpack did not coexist with skinned outfit")
	await process_frame
	_assert(int(lab.equipment_presenter.create_report().get("visual_count", 0)) == 3, "CH7.8 rigid + skinned composition has unexpected visual count")
	_assert(lab.equipment_presenter.get_visual(lab.OUTFIT_ITEM_ID) != null, "CH7.8 rigid equip removed skinned outfit")
	_assert(base_body.material_override is ShaderMaterial, "CH7.8 rigid composition restored full fused body unexpectedly")
	_assert(eyes == null or eyes.visible, "CH7.8 rigid composition hid Eyes")
	_assert(eyebrows == null or eyebrows.visible, "CH7.8 rigid composition hid Eyebrows")

	print("CH7.8 garment lab: phase=unequip")
	var off_result: Dictionary = lab.set_outfit_equipped(false)
	print("CH7.8 garment lab: phase=after_unequip_call result=%s" % JSON.stringify(off_result))
	await process_frame
	_assert(bool(off_result.get("success", false)), "CH7.8 outfit unequip failed")
	_assert(not lab.equipment_source.has_item(lab.OUTFIT_ITEM_ID), "CH7.8 canonical outfit state remained equipped")
	_assert(lab.equipment_presenter.get_visual(lab.OUTFIT_ITEM_ID) == null, "CH7.8 skinned visual remained registered after unequip")
	var off_report: Dictionary = lab.equipment_presenter.create_report()
	_assert(int(off_report.get("visual_count", 0)) == 2, "CH7.8 outfit removal damaged rigid equipment composition")
	_assert(int(off_report.get("suppressed_body_target_count", -1)) == 0, "CH7.8 fused-body suppression remained after outfit removal")
	_assert(int(off_report.get("material_clipped_body_visual_count", -1)) == 0, "CH7.8 material clip remained registered after outfit removal")
	_assert(base_body.visible, "CH7.8 base body mesh visibility changed after lifecycle")
	_assert(base_body.material_override == original_material_override, "CH7.8 base material override was not restored exactly")
	_assert(eyes == null or eyes.visible, "CH7.8 Eyes visibility changed after lifecycle")
	_assert(eyebrows == null or eyebrows.visible, "CH7.8 Eyebrows visibility changed after lifecycle")
	_assert(lab.player.position.is_equal_approx(player_position_before), "CH7.8 lifecycle moved gameplay body")
	_assert(is_equal_approx(float(lab.player_capsule.height), capsule_height_before), "CH7.8 lifecycle modified gameplay capsule")

	print("CH7.8 garment lab: phase=finish")
	lab.queue_free()
	_finish()


func _find_mesh_named(root_node: Node, target_name: String) -> MeshInstance3D:
	if root_node is MeshInstance3D and String(root_node.name) == target_name:
		return root_node as MeshInstance3D
	for child in root_node.get_children():
		var found := _find_mesh_named(child, target_name)
		if found != null:
			return found
	return null


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