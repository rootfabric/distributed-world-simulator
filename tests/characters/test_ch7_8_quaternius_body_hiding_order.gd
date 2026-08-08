extends SceneTree

const LabScene = preload("res://scenes/labs/character/quaternius_skinned_garment_lab.tscn")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("CH7.8 body suppression order: phase=instantiate")
	var lab = LabScene.instantiate()
	root.add_child(lab)
	await process_frame
	await physics_frame

	_assert(lab.outfit_available, "Order test outfit is unavailable")
	_assert(lab.body_suppression_available, "Order test fused-body suppression is unavailable")
	_assert(lab.body_suppression_mode == CharacterRigAdapter.BODY_SUPPRESSION_MATERIAL_OVERRIDE, "Order test did not select material suppression")
	_assert(lab.head_clip_local_y > 1.2 and lab.head_clip_local_y < 1.7, "Order test head clip plane is outside plausible character range")
	if not lab.outfit_available or not lab.body_suppression_available:
		lab.queue_free()
		_finish()
		return

	print("CH7.8 body suppression order: phase=rigid_first")
	_assert(bool(lab.set_helmet_equipped(true).get("success", false)), "Helmet-first equip failed")
	_assert(bool(lab.set_backpack_equipped(true).get("success", false)), "Backpack-first equip failed")
	await process_frame

	var helmet: Node3D = lab.equipment_presenter.get_visual(lab.HELMET_ITEM_ID)
	var backpack: Node3D = lab.equipment_presenter.get_visual(lab.BACKPACK_ITEM_ID)
	_assert(helmet != null, "Helmet visual missing before outfit")
	_assert(backpack != null, "Backpack visual missing before outfit")
	var rigid_visuals: Array[GeometryInstance3D] = []
	if helmet != null:
		_collect_geometry_instances(helmet, rigid_visuals)
	if backpack != null:
		_collect_geometry_instances(backpack, rigid_visuals)
	_assert(not rigid_visuals.is_empty(), "Rigid equipment exposes no geometry")
	for rigid_visual in rigid_visuals:
		_assert(rigid_visual.visible, "Rigid equipment was unexpectedly hidden before outfit")

	var resolved_body_visuals: Array = lab.equipment_rig_adapter.resolve_body_region_visuals(
		lab.avatar,
		"body.region.torso"
	)
	_assert(resolved_body_visuals.size() == 1, "Quaternius torso should resolve only the fused base body mesh")
	var base_body: MeshInstance3D = null
	if resolved_body_visuals.size() == 1 and resolved_body_visuals[0] is MeshInstance3D:
		base_body = resolved_body_visuals[0] as MeshInstance3D
	_assert(base_body != null, "Order test resolved no fused base body mesh")
	if base_body == null:
		lab.queue_free()
		_finish()
		return
	_assert(base_body not in rigid_visuals, "Body-region resolver incorrectly included rigid equipment geometry")
	var original_material_override: Material = base_body.material_override

	var eyes := _find_mesh_named(lab.avatar, "Eyes")
	var eyebrows := _find_mesh_named(lab.avatar, "Eyebrows")
	_assert(eyes != null, "Base Eyes mesh missing")
	_assert(eyebrows != null, "Base Eyebrows mesh missing")
	_assert(eyes == null or eyes.visible, "Base Eyes were not visible before outfit")
	_assert(eyebrows == null or eyebrows.visible, "Base Eyebrows were not visible before outfit")

	print("CH7.8 body suppression order: phase=outfit_after_rigid")
	_assert(bool(lab.set_outfit_equipped(true).get("success", false)), "Outfit-after-rigid equip failed")
	await process_frame
	_assert(base_body.visible, "Fused base body mesh should remain rendered for head clipping")
	_assert(base_body.material_override is ShaderMaterial, "Fused base body did not receive head clip ShaderMaterial")
	_assert(base_body.material_override != original_material_override, "Head clip did not replace the base material presentation")
	if base_body.material_override is ShaderMaterial:
		var clip_material := base_body.material_override as ShaderMaterial
		var clip_y := float(clip_material.get_shader_parameter("clip_local_y"))
		_assert(is_equal_approx(clip_y, lab.head_clip_local_y), "Applied head clip plane differs from rig-derived value")
	for rigid_visual in rigid_visuals:
		_assert(rigid_visual.visible, "Head clipping hid existing rigid equipment")
	_assert(eyes == null or eyes.visible, "Head clipping hid separate Eyes geometry")
	_assert(eyebrows == null or eyebrows.visible, "Head clipping hid separate Eyebrows geometry")
	var report: Dictionary = lab.equipment_presenter.create_report()
	_assert(int(report.get("hidden_body_visual_count", -1)) == 0, "Quaternius fused body should not use full-geometry hiding")
	_assert(int(report.get("material_clipped_body_visual_count", 0)) == 1, "Order test expected exactly one material-clipped base body")
	_assert(int(report.get("suppressed_body_target_count", 0)) == 1, "Semantic body regions were not deduplicated onto one fused body target")
	_assert(int(report.get("visual_count", 0)) == 3, "Order test expected outfit + helmet + backpack")

	print("CH7.8 body suppression order: phase=outfit_off")
	_assert(bool(lab.set_outfit_equipped(false).get("success", false)), "Order test outfit unequip failed")
	await process_frame
	_assert(base_body.visible, "Base body mesh visibility changed after outfit removal")
	_assert(base_body.material_override == original_material_override, "Base body material override was not restored exactly")
	for rigid_visual in rigid_visuals:
		_assert(rigid_visual.visible, "Rigid equipment visibility changed after outfit removal")
	_assert(eyes == null or eyes.visible, "Eyes visibility changed after outfit removal")
	_assert(eyebrows == null or eyebrows.visible, "Eyebrows visibility changed after outfit removal")
	var off_report: Dictionary = lab.equipment_presenter.create_report()
	_assert(int(off_report.get("suppressed_body_target_count", -1)) == 0, "Body suppression state leaked after outfit removal")
	_assert(int(off_report.get("visual_count", 0)) == 2, "Rigid equipment was damaged by outfit lifecycle")

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


func _collect_geometry_instances(root_node: Node, output: Array[GeometryInstance3D]) -> void:
	if root_node is GeometryInstance3D:
		output.append(root_node as GeometryInstance3D)
	for child in root_node.get_children():
		_collect_geometry_instances(child, output)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH7.8 Quaternius fused-body suppression order: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH7.8 Quaternius fused-body suppression order: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)