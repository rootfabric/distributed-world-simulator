extends SceneTree

const LabScene = preload("res://scenes/labs/character/quaternius_skinned_garment_lab.tscn")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("CH7.8 body hiding order: phase=instantiate")
	var lab = LabScene.instantiate()
	root.add_child(lab)
	await process_frame
	await physics_frame

	_assert(lab.outfit_available, "Order test outfit is unavailable")
	_assert(lab.body_replacement_available, "Order test head replacement is unavailable")
	if not lab.outfit_available or not lab.body_replacement_available:
		lab.queue_free()
		_finish()
		return

	print("CH7.8 body hiding order: phase=rigid_first")
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

	var base_visuals: Array[GeometryInstance3D] = lab.equipment_rig_adapter.resolve_body_region_visuals(
		lab.avatar,
		"body.region.torso"
	)
	_assert(not base_visuals.is_empty(), "Order test resolved no base-body geometry")
	for base_visual in base_visuals:
		_assert(base_visual not in rigid_visuals, "Body-region resolver incorrectly included rigid equipment geometry")

	print("CH7.8 body hiding order: phase=outfit_after_rigid")
	_assert(bool(lab.set_outfit_equipped(true).get("success", false)), "Outfit-after-rigid equip failed")
	await process_frame
	for base_visual in base_visuals:
		_assert(not base_visual.visible, "Base body stayed visible after outfit-after-rigid")
	for rigid_visual in rigid_visuals:
		_assert(rigid_visual.visible, "Body replacement hid existing rigid equipment")
	var report: Dictionary = lab.equipment_presenter.create_report()
	_assert(int(report.get("hidden_body_visual_count", 0)) == base_visuals.size(), "Order test hidden-body count includes non-body geometry")
	_assert(int(report.get("visual_count", 0)) == 3, "Order test expected outfit + helmet + backpack")

	print("CH7.8 body hiding order: phase=outfit_off")
	_assert(bool(lab.set_outfit_equipped(false).get("success", false)), "Order test outfit unequip failed")
	await process_frame
	for base_visual in base_visuals:
		_assert(base_visual.visible, "Base body was not restored after outfit removal")
	for rigid_visual in rigid_visuals:
		_assert(rigid_visual.visible, "Rigid equipment visibility changed after outfit removal")
	_assert(int(lab.equipment_presenter.create_report().get("visual_count", 0)) == 2, "Rigid equipment was damaged by outfit lifecycle")

	lab.queue_free()
	_finish()


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
		print("CH7.8 Quaternius body hiding order: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH7.8 Quaternius body hiding order: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
