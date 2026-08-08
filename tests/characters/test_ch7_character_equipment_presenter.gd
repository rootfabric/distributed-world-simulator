extends SceneTree

const Domain = preload("res://scripts/characters/equipment/character_equipment_domain.gd")
const RigAdapter = preload("res://scripts/characters/equipment/character_rig_adapter.gd")
const Catalog = preload("res://scripts/characters/equipment/wearable_presentation_catalog.gd")
const Presenter = preload("res://scripts/characters/equipment/character_equipment_presenter.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var helmet_scene := _packed_visual("HelmetVisual")
	var backpack_scene := _packed_visual("BackpackVisual")
	_assert(helmet_scene != null, "Helmet synthetic presentation scene could not be packed")
	_assert(backpack_scene != null, "Backpack synthetic presentation scene could not be packed")

	var catalog = Catalog.new()
	_assert(bool(catalog.register_scene("wearable.helmet.mk1", "test.humanoid", Catalog.STRATEGY_RIGID_ATTACHMENT, helmet_scene).get("success", false)), "Humanoid helmet catalog registration failed")
	_assert(bool(catalog.register_scene("wearable.backpack.mk1", "test.humanoid", Catalog.STRATEGY_RIGID_ATTACHMENT, backpack_scene).get("success", false)), "Humanoid backpack catalog registration failed")
	_assert(bool(catalog.register_scene("wearable.helmet.mk1", "test.robot", Catalog.STRATEGY_RIGID_ATTACHMENT, helmet_scene).get("success", false)), "Robot helmet catalog registration failed")
	_assert(bool(catalog.register_scene("wearable.backpack.mk1", "test.robot", Catalog.STRATEGY_RIGID_ATTACHMENT, backpack_scene).get("success", false)), "Robot backpack catalog registration failed")
	_assert(catalog.entry_count() == 4, "Unexpected wearable catalog entry count")

	var human_root := Node3D.new()
	human_root.name = "HumanVisualRoot"
	root.add_child(human_root)
	var human_head := Node3D.new()
	human_head.name = "HeadSocket"
	human_root.add_child(human_head)
	var human_back := Node3D.new()
	human_back.name = "BackSocket"
	human_root.add_child(human_back)

	var human_adapter = RigAdapter.new()
	var human_adapter_setup: Dictionary = human_adapter.setup("test.humanoid", {
		"body.head": NodePath("HeadSocket"),
		"gear.back": NodePath("BackSocket"),
	})
	_assert(bool(human_adapter_setup.get("success", false)), "Humanoid rig adapter setup failed")
	_assert(human_adapter.resolve_anchor(human_root, "body.head") == human_head, "Humanoid semantic head anchor resolved incorrectly")
	_assert(human_adapter.resolve_anchor(human_root, "gear.back") == human_back, "Humanoid semantic back anchor resolved incorrectly")

	var presenter = Presenter.new()
	human_root.add_child(presenter)
	var presenter_setup: Dictionary = presenter.setup(human_root, human_adapter, catalog)
	_assert(bool(presenter_setup.get("success", false)), "Generic equipment presenter setup failed")

	var helmet_entry := Domain.Entry.new("item.helmet.001", "equipment.helmet.mk1", "wearable.helmet.mk1", "body.head", ["body.head.outer"])
	var backpack_entry := Domain.Entry.new("item.backpack.001", "equipment.backpack.mk1", "wearable.backpack.mk1", "gear.back", ["gear.back"])
	var snapshot := Domain.Snapshot.new("entity.human.001", "humanoid.standard", 1, [helmet_entry, backpack_entry])
	var apply_result: Dictionary = presenter.apply_snapshot(snapshot)
	_assert(bool(apply_result.get("success", false)), "Initial equipment snapshot presentation failed")
	_assert(int((apply_result.get("details", {}) as Dictionary).get("created", -1)) == 2, "Initial snapshot did not create two visuals")
	_assert(presenter.get_visual("item.helmet.001") != null, "Helmet visual missing")
	_assert(presenter.get_visual("item.backpack.001") != null, "Backpack visual missing")
	_assert(presenter.get_visual("item.helmet.001").get_parent() == human_head, "Helmet did not attach to semantic head anchor")
	_assert(presenter.get_visual("item.backpack.001").get_parent() == human_back, "Backpack did not attach to semantic back anchor")

	var repeated: Dictionary = presenter.apply_snapshot(snapshot)
	_assert(bool(repeated.get("success", false)), "Repeated identical snapshot failed")
	_assert(not bool((repeated.get("details", {}) as Dictionary).get("changed", true)), "Repeated identical snapshot was not idempotent")
	_assert(int((repeated.get("details", {}) as Dictionary).get("created", -1)) == 0, "Repeated identical snapshot created duplicate visuals")
	_assert((presenter.create_report().get("visual_item_ids", []) as Array).size() == 2, "Presenter report contains duplicate or missing visuals")

	var helmet_only := Domain.Snapshot.new("entity.human.001", "humanoid.standard", 2, [helmet_entry])
	var remove_result: Dictionary = presenter.apply_snapshot(helmet_only)
	_assert(bool(remove_result.get("success", false)), "Helmet-only snapshot failed")
	_assert(int((remove_result.get("details", {}) as Dictionary).get("removed", -1)) == 1, "Backpack removal was not detected")
	_assert(presenter.get_visual("item.backpack.001") == null, "Removed backpack still exposed by presenter")
	await process_frame
	_assert(human_back.get_child_count() == 0, "Removed backpack node leaked under its anchor")

	# Lifecycle stress belongs here, where no full Quaternius WORLD_PROXY rebuild is involved.
	# This proves presenter create/remove/idempotency cheaply and deterministically.
	for cycle in range(100):
		var revision_base := 1000 + cycle * 2
		var with_backpack := Domain.Snapshot.new(
			"entity.human.001",
			"humanoid.standard",
			revision_base,
			[helmet_entry, backpack_entry]
		)
		var stress_equip: Dictionary = presenter.apply_snapshot(with_backpack)
		_assert(bool(stress_equip.get("success", false)), "Generic lifecycle equip failed at cycle %d" % cycle)
		_assert(presenter.get_visual("item.backpack.001") != null, "Generic lifecycle backpack visual missing at cycle %d" % cycle)
		var without_backpack := Domain.Snapshot.new(
			"entity.human.001",
			"humanoid.standard",
			revision_base + 1,
			[helmet_entry]
		)
		var stress_unequip: Dictionary = presenter.apply_snapshot(without_backpack)
		_assert(bool(stress_unequip.get("success", false)), "Generic lifecycle unequip failed at cycle %d" % cycle)
		_assert(presenter.get_visual("item.backpack.001") == null, "Generic lifecycle backpack visual leaked at cycle %d" % cycle)
		if cycle % 10 == 9:
			await process_frame
	await process_frame
	var stress_report: Dictionary = presenter.create_report()
	_assert(int(stress_report.get("visual_count", 0)) == 1, "Generic lifecycle stress left duplicate visuals")
	_assert((stress_report.get("visual_item_ids", []) as Array).has("item.helmet.001"), "Generic lifecycle stress lost helmet presentation")
	_assert(human_back.get_child_count() == 0, "Generic lifecycle stress left detached backpack nodes")

	var robot_root := Node3D.new()
	robot_root.name = "RobotVisualRoot"
	root.add_child(robot_root)
	var robot_head := Node3D.new()
	robot_head.name = "RobotHeadMount"
	robot_root.add_child(robot_head)
	var robot_payload := Node3D.new()
	robot_payload.name = "RearPayloadMount"
	robot_root.add_child(robot_payload)

	var robot_adapter = RigAdapter.new()
	var robot_adapter_setup: Dictionary = robot_adapter.setup("test.robot", {
		"body.head": NodePath("RobotHeadMount"),
		"gear.back": NodePath("RearPayloadMount"),
	})
	_assert(bool(robot_adapter_setup.get("success", false)), "Robot rig adapter setup failed")
	_assert(robot_adapter.resolve_anchor(robot_root, "body.head") == robot_head, "Robot semantic head anchor resolved incorrectly")
	_assert(robot_adapter.resolve_anchor(robot_root, "gear.back") == robot_payload, "Robot semantic back anchor resolved incorrectly")

	var robot_presenter = Presenter.new()
	robot_root.add_child(robot_presenter)
	_assert(bool(robot_presenter.setup(robot_root, robot_adapter, catalog).get("success", false)), "Robot equipment presenter setup failed")
	var robot_snapshot := Domain.Snapshot.new("entity.robot.001", "robot.humanoid", 1, [helmet_entry, backpack_entry])
	var robot_apply: Dictionary = robot_presenter.apply_snapshot(robot_snapshot)
	_assert(bool(robot_apply.get("success", false)), "Same semantic equipment snapshot failed on independent robot rig")
	_assert(robot_presenter.get_visual("item.helmet.001").get_parent() == robot_head, "Robot helmet used humanoid concrete node path")
	_assert(robot_presenter.get_visual("item.backpack.001").get_parent() == robot_payload, "Robot backpack used humanoid concrete node path")

	var missing_entry := Domain.Entry.new("item.unsupported.001", "equipment.unsupported", "wearable.unsupported", "body.head", ["body.head.outer"])
	var missing_snapshot := Domain.Snapshot.new("entity.robot.001", "robot.humanoid", 2, [missing_entry])
	var missing_result: Dictionary = robot_presenter.apply_snapshot(missing_snapshot)
	_assert(not bool(missing_result.get("success", true)), "Unsupported presentation was silently accepted")
	_assert(String(missing_result.get("code", "")) == "UNSUPPORTED_PRESENTATION", "Unsupported presentation returned wrong code")
	_assert(robot_presenter.get_visual("item.helmet.001") != null, "Failed snapshot mutated previously valid presentation")

	var presenter_source := FileAccess.get_file_as_string("res://scripts/characters/equipment/character_equipment_presenter.gd")
	for forbidden in ["CharacterBody3D", "Input.", "multiplayer", "quaternius", "human", "robot"]:
		_assert(not presenter_source.to_lower().contains(String(forbidden).to_lower()), "Generic equipment presenter gained concrete gameplay/character dependency: %s" % forbidden)

	var human_report: Dictionary = presenter.create_report()
	_assert(not bool(human_report.get("moves_gameplay_body", true)), "Equipment presenter claims gameplay movement authority")
	_assert(not bool(human_report.get("reads_input", true)), "Equipment presenter claims input authority")
	_assert(not bool(human_report.get("owns_network_state", true)), "Equipment presenter claims network authority")

	human_root.queue_free()
	robot_root.queue_free()
	_finish()


func _packed_visual(node_name: String) -> PackedScene:
	var visual := Node3D.new()
	visual.name = node_name
	var packed := PackedScene.new()
	var error := packed.pack(visual)
	visual.free()
	return packed if error == OK else null


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH7 character equipment presenter: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH7 character equipment presenter: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
