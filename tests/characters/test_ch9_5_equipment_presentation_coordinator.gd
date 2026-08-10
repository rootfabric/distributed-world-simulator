extends SceneTree

const Service = preload("res://scripts/runtime/networked_gameplay/ch9/ch9_3_networked_gameplay_service.gd")
const Coordinator = preload("res://scripts/characters/equipment/network_character_equipment_presentation_coordinator.gd")
const EquipmentCatalog = preload("res://scripts/characters/equipment/network_character_equipment_catalog.gd")

var failures: Array[String] = []
var assertions := 0


class RuntimeProbe extends Node:
	signal item_graph_updated(snapshot: Dictionary)
	var snapshot: Dictionary = {}

	func get_item_graph_snapshot() -> Dictionary:
		return snapshot.duplicate(true)

	func publish(value: Dictionary) -> void:
		snapshot = value.duplicate(true)
		item_graph_updated.emit(snapshot.duplicate(true))


class PresenterProbe extends RefCounted:
	var apply_count := 0
	var change_count := 0
	var clear_count := 0
	var last_state_fingerprint := ""
	var visible_item_ids: Array[String] = []

	func apply_snapshot(snapshot) -> Dictionary:
		apply_count += 1
		var fingerprint: String = String(snapshot.state_fingerprint())
		var changed: bool = fingerprint != last_state_fingerprint
		if changed:
			change_count += 1
		last_state_fingerprint = fingerprint
		visible_item_ids.clear()
		for entry in snapshot.entries():
			visible_item_ids.append(String(entry.item_id))
		visible_item_ids.sort()
		return {
			"success": true,
			"code": "OK",
			"details": {
				"changed": changed,
				"visual_count": visible_item_ids.size(),
				"created": visible_item_ids.size() if changed else 0,
				"removed": 0,
				"reused": visible_item_ids.size() if not changed else 0,
			},
		}

	func clear() -> Dictionary:
		clear_count += 1
		visible_item_ids.clear()
		last_state_fingerprint = ""
		return {"success": true, "code": "OK", "details": {"changed": true}}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var service = Service.new()
	var setup: Dictionary = service.setup("simulation/ch9-5/coordinator", 1, 0, {
		"profile": Service.PROFILE_MULTIPLAYER_CORE,
		"topology_adapter": "LOOPBACK",
		"region_id": "region/ch9-5/coordinator",
		"playable_sandbox": true,
	})
	_assert_ok(setup, "service setup")
	if not bool(setup.get("success", false)):
		_finish()
		return
	var join_a: Dictionary = service.join("a", "transport-session/ch9-5/coordinator/a", "operation/ch9-5/coordinator/join/a")
	var join_b: Dictionary = service.join("b", "transport-session/ch9-5/coordinator/b", "operation/ch9-5/coordinator/join/b")
	_assert_ok(join_a, "join A")
	_assert_ok(join_b, "join B")
	var epoch_a := int(join_a.get("details", {}).get("player", {}).get("ownership_epoch", 0))

	var runtime := RuntimeProbe.new()
	root.add_child(runtime)
	runtime.snapshot = service.create_canonical_item_graph_snapshot()
	var coordinator = Coordinator.new()
	_assert_ok(coordinator.setup(runtime), "coordinator setup")
	var presenter_a := PresenterProbe.new()
	var presenter_b := PresenterProbe.new()
	_assert_ok(coordinator.bind_presenter("a", presenter_a), "bind presenter A")
	_assert_ok(coordinator.bind_presenter("b", presenter_b), "bind presenter B")
	_assert(presenter_a.visible_item_ids.is_empty(), "A started with unexpected equipment presentation")
	_assert(presenter_b.visible_item_ids.is_empty(), "B started with unexpected equipment presentation")

	var lower_id := "item/player/a/wearable/lower"
	var helmet_id := "item/player/a/wearable/helmet"
	var equip_lower: Dictionary = service.handle_canonical_item_command(
		"a", "transport-session/ch9-5/coordinator/a", epoch_a,
		"operation/ch9-5/coordinator/equip/lower", "equipment.equip",
		{"item_id": lower_id, "slot_index": EquipmentCatalog.SLOT_LOWER}
	)
	_assert_ok(equip_lower, "equip lower")
	runtime.publish(service.create_canonical_item_graph_snapshot())
	_assert(presenter_a.visible_item_ids == [lower_id], "A lower did not reach bound presenter")
	_assert(presenter_b.visible_item_ids.is_empty(), "A equipment leaked into B presenter")
	var a_changes_after_lower := presenter_a.change_count
	var a_applies_after_lower := presenter_a.apply_count

	# Replaying the exact same canonical Item Graph may cause another signal, but
	# must not create another semantic presentation state.
	runtime.publish(service.create_canonical_item_graph_snapshot())
	_assert(presenter_a.apply_count == a_applies_after_lower + 1, "same snapshot was not observed by coordinator")
	_assert(presenter_a.change_count == a_changes_after_lower, "same snapshot produced duplicate presentation change")

	var equip_helmet: Dictionary = service.handle_canonical_item_command(
		"a", "transport-session/ch9-5/coordinator/a", epoch_a,
		"operation/ch9-5/coordinator/equip/helmet", "equipment.equip",
		{"item_id": helmet_id, "slot_index": EquipmentCatalog.SLOT_HEAD}
	)
	_assert_ok(equip_helmet, "equip helmet")
	runtime.publish(service.create_canonical_item_graph_snapshot())
	_assert(presenter_a.visible_item_ids == [helmet_id, lower_id], "layered A equipment did not compose in presenter")
	_assert(presenter_b.visible_item_ids.is_empty(), "B presenter changed from A layered equipment")

	var unequip_lower: Dictionary = service.handle_canonical_item_command(
		"a", "transport-session/ch9-5/coordinator/a", epoch_a,
		"operation/ch9-5/coordinator/unequip/lower", "equipment.unequip",
		{"item_id": lower_id}
	)
	_assert_ok(unequip_lower, "unequip lower")
	runtime.publish(service.create_canonical_item_graph_snapshot())
	_assert(presenter_a.visible_item_ids == [helmet_id], "unequip did not remove lower from presentation")
	_assert(coordinator.get_binding_report("a").get("last_revision", -1) == int(runtime.snapshot.get("revision", -2)), "binding revision did not follow Item Graph")
	var report: Dictionary = coordinator.create_report()
	_assert(bool(report.get("presentation_only", false)), "coordinator did not declare presentation-only ownership")
	_assert(not bool(report.get("owns_item_truth", true)), "coordinator claimed Item truth")
	_assert(not bool(report.get("owns_transport", true)), "coordinator claimed transport")
	_assert(not bool(report.get("owns_persistence", true)), "coordinator claimed persistence")
	_assert(int(report.get("projection_failures", -1)) == 0, "coordinator recorded projection failures")
	_assert(int(report.get("presentation_failures", -1)) == 0, "coordinator recorded presentation failures")
	_assert_ok(coordinator.stop(true), "coordinator stop")
	_assert(presenter_a.clear_count == 1 and presenter_b.clear_count == 1, "coordinator stop did not clear bound presenters exactly once")

	service.shutdown()
	_finish()


func _assert_ok(result: Dictionary, label: String) -> void:
	_assert(bool(result.get("success", false)), "%s failed: %s" % [label, JSON.stringify(result)])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH9.5 equipment presentation coordinator: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH9.5 equipment presentation coordinator: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
