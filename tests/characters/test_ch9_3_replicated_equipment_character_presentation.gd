extends SceneTree

const LabScene = preload("res://scenes/labs/character/quaternius_layered_equipment_lab.tscn")
const Service = preload("res://scripts/runtime/networked_gameplay/ch9/ch9_3_networked_gameplay_service.gd")
const EquipmentCatalog = preload("res://scripts/characters/equipment/network_character_equipment_catalog.gd")
const EquipmentProjection = preload("res://scripts/characters/equipment/network_character_equipment_projection.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var lab = LabScene.instantiate()
	root.add_child(lab)
	await process_frame
	await physics_frame
	_assert(bool(lab.layered_setup_result.get("success", false)), "CH9.3 presentation lab CH8 setup failed")
	_assert(lab.equipment_presenter != null, "CH9.3 presentation lab presenter missing")
	if not bool(lab.layered_setup_result.get("success", false)):
		lab.queue_free()
		_finish()
		return

	var service = Service.new()
	var setup: Dictionary = service.setup("simulation/ch9-3/presentation", 1, 0, {
		"profile": "MULTIPLAYER_CORE",
		"topology_adapter": "LOOPBACK",
		"region_id": "region/ch9-3/presentation",
		"playable_sandbox": true,
	})
	_assert(bool(setup.get("success", false)), "CH9.3 presentation authority setup failed")
	var joined := service.join("a", "transport-session/ch9-3/presentation/a", "operation/ch9-3/presentation/join/a")
	_assert(bool(joined.get("success", false)), "CH9.3 presentation player join failed")
	var epoch := int(joined.get("details", {}).get("player", {}).get("ownership_epoch", 0))

	for spec in EquipmentCatalog.wearable_specs():
		var item_id := "item/player/a/wearable/%s" % String(spec.get("suffix", ""))
		var slot_index := int(spec.get("slot_index", -1))
		var result: Dictionary = service.handle_canonical_item_command(
			"a",
			"transport-session/ch9-3/presentation/a",
			epoch,
			"operation/ch9-3/presentation/equip/%s" % String(spec.get("suffix", "")),
			"equipment.equip",
			{"item_id": item_id, "slot_index": slot_index}
		)
		_assert(bool(result.get("success", false)), "CH9.3 presentation equip failed for slot %d" % slot_index)

	var canonical := service.create_canonical_item_graph_snapshot()
	var projection = EquipmentProjection.new()
	var projected: Dictionary = projection.project(canonical, "a")
	_assert(bool(projected.get("success", false)), "CH9.3 presentation projection failed: %s" % JSON.stringify(projected))
	var snapshot = projected.get("details", {}).get("snapshot")
	_assert(snapshot is CharacterEquipmentDomain.Snapshot, "CH9.3 presentation projection snapshot type invalid")
	if not snapshot is CharacterEquipmentDomain.Snapshot:
		service.shutdown()
		lab.queue_free()
		_finish()
		return
	_assert(snapshot.entries().size() == EquipmentCatalog.EQUIPMENT_SLOT_COUNT, "CH9.3 projected full equipment count mismatch")

	var presenter_result: Dictionary = lab.equipment_presenter.apply_snapshot(snapshot)
	_assert(bool(presenter_result.get("success", false)), "CH9.3 accepted CharacterEquipmentPresenter rejected replicated snapshot: %s" % JSON.stringify(presenter_result))
	var suppression_result: Dictionary = lab.body_suppression_coordinator.apply_snapshot(snapshot)
	var topology_result: Dictionary = lab.body_topology_coordinator.apply_snapshot(snapshot)
	_assert(bool(suppression_result.get("success", false)), "CH9.3 replicated body suppression sync failed")
	_assert(bool(topology_result.get("success", false)), "CH9.3 replicated topology sync failed")
	await process_frame

	var report: Dictionary = lab.equipment_presenter.create_report()
	_assert(int(report.get("visual_count", 0)) == EquipmentCatalog.EQUIPMENT_SLOT_COUNT, "CH9.3 replicated presentation did not create five equipment visuals")
	for spec in EquipmentCatalog.wearable_specs():
		var item_id := "item/player/a/wearable/%s" % String(spec.get("suffix", ""))
		_assert(lab.equipment_presenter.get_visual(item_id) != null, "CH9.3 replicated presenter missing %s" % item_id)
	_assert(not bool(report.get("owns_network_state", true)), "CH9.3 character presenter acquired network ownership")
	_assert(not bool(report.get("moves_gameplay_body", true)), "CH9.3 replicated equipment presenter moved gameplay body")
	_assert((lab.body_suppression_coordinator.create_report().get("active_regions", []) as Array).is_empty(), "CH9.3 body-visible network garments unexpectedly enabled material suppression")
	_assert((lab.body_topology_coordinator.create_report().get("active_presentations", []) as Array).is_empty(), "CH9.3 body-visible network garments unexpectedly enabled topology occlusion")

	var cleared = CharacterEquipmentDomain.Snapshot.new(
		EquipmentCatalog.owner_entity_id("a"),
		EquipmentCatalog.layout().layout_id,
		int(canonical.get("revision", 0)) + 1,
		[]
	)
	var clear_result: Dictionary = lab.equipment_presenter.apply_snapshot(cleared)
	_assert(bool(clear_result.get("success", false)), "CH9.3 replicated presentation clear failed")
	_assert(int(lab.equipment_presenter.create_report().get("visual_count", -1)) == 0, "CH9.3 replicated presentation retained visuals after clear")

	service.shutdown()
	lab.queue_free()
	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH9.3 replicated character equipment presentation: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH9.3 replicated character equipment presentation: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
