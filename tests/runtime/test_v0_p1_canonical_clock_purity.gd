extends SceneTree

const ClockProbe = preload(
	"res://tests/runtime/support/v0_p1_clock_purity_probe.gd"
)

const BEACON_ID := "item/shared/beacon/1"
const BATTERY_ID := "item/player/a/battery"
const BEACON_STACK_ID := "item/player/a/beacons"

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_run()


func _run() -> void:
	_test_existing_player_ensure_is_mutation_free()
	_test_pickup_publishes_slot_before_pure_snapshot()
	_test_split_publishes_slot_before_pure_snapshot()
	_test_rejected_transfer_does_not_normalize()
	_finish()


func _new_graph(authority_suffix: String):
	var graph = ClockProbe.new()
	_assert(
		_ok(graph.setup("authority/v0-p1/clock/%s" % authority_suffix, 1, {"playable_sandbox": true})),
		"%s graph configures" % authority_suffix
	)
	graph.ensure_player("a")
	return graph


func _test_existing_player_ensure_is_mutation_free() -> void:
	var graph = _new_graph("ensure")
	var battery: Dictionary = Dictionary(graph._items[BATTERY_ID]).duplicate(true)
	var location: Dictionary = Dictionary(battery.get("location", {})).duplicate(true)
	_assert(int(location.get("slot_index", -1)) >= 0, "first materialization assigns canonical battery slot")
	location.erase("slot_index")
	battery["location"] = location
	graph._items[BATTERY_ID] = battery
	var before := graph.create_snapshot()
	var before_revision := int(before.get("revision", -1))
	var before_tick := int(before.get("tick", -1))
	var before_checksum := String(before.get("checksum", ""))
	graph.ensure_player("a")
	var after := graph.create_snapshot()
	_assert(int(after.get("revision", -2)) == before_revision, "existing-player ensure preserves revision")
	_assert(int(after.get("tick", -2)) == before_tick, "existing-player ensure preserves tick")
	_assert(String(after.get("checksum", "changed")) == before_checksum, "existing-player ensure does not repair canonical representation")
	_assert(int(_item_location(after, BATTERY_ID).get("slot_index", -1)) < 0, "existing-player ensure leaves migration work to explicit recovery boundary")


func _test_pickup_publishes_slot_before_pure_snapshot() -> void:
	var graph = _new_graph("pickup")
	var pickup := graph.execute(
		"a",
		1,
		"operation/v0-p1/clock/pickup/1",
		"item.pickup",
		{"item_id": BEACON_ID},
		_pickup_context()
	)
	_assert(_ok(pickup), "pickup succeeds through canonical execute")
	var snapshot: Dictionary = pickup.get("snapshot", {})
	var location := _item_location(snapshot, BEACON_ID)
	_assert(String(location.get("kind", "")) == "INVENTORY", "pickup publishes INVENTORY location")
	_assert(String(location.get("player_id", "")) == "a", "pickup publishes canonical inventory owner")
	_assert(int(location.get("slot_index", -1)) >= 0, "pickup publishes slot_index before pure snapshot")
	var before_revision := int(snapshot.get("revision", -1))
	var before_tick := int(snapshot.get("tick", -1))
	var before_checksum := String(snapshot.get("checksum", ""))
	var duplicate := graph.execute(
		"a",
		1,
		"operation/v0-p1/clock/pickup/duplicate",
		"item.pickup",
		{"item_id": BEACON_ID},
		_pickup_context()
	)
	_assert(String(duplicate.get("error_code", "")) == "ITEM_ALREADY_CLAIMED", "duplicate pickup is rejected")
	var after := graph.create_snapshot()
	_assert(int(after.get("revision", -2)) == before_revision, "duplicate pickup rejection preserves revision")
	_assert(int(after.get("tick", -2)) == before_tick, "duplicate pickup rejection preserves tick")
	_assert(String(after.get("checksum", "changed")) == before_checksum, "duplicate pickup rejection preserves canonical checksum")


func _test_split_publishes_slot_before_pure_snapshot() -> void:
	var graph = _new_graph("split")
	var split := graph.execute(
		"a",
		1,
		"operation/v0-p1/clock/split/1",
		"item.split",
		{"item_id": BEACON_STACK_ID, "quantity": 1}
	)
	_assert(_ok(split), "split succeeds through canonical execute")
	var details: Dictionary = Dictionary(split.get("details", {}))
	var split_item_id := String(details.get("item_id", ""))
	_assert(not split_item_id.is_empty(), "split returns canonical new item identity")
	var snapshot: Dictionary = split.get("snapshot", {})
	var location := _item_location(snapshot, split_item_id)
	_assert(String(location.get("kind", "")) == "INVENTORY", "split output is canonical INVENTORY item")
	_assert(int(location.get("slot_index", -1)) >= 0, "split publishes slot_index before pure snapshot")
	var before_revision := int(snapshot.get("revision", -1))
	var before_tick := int(snapshot.get("tick", -1))
	var before_checksum := String(snapshot.get("checksum", ""))
	var rejected := graph.execute(
		"a",
		1,
		"operation/v0-p1/clock/split/rejected",
		"item.split",
		{"item_id": split_item_id, "quantity": 1}
	)
	_assert(String(rejected.get("error_code", "")) == "INVALID_SPLIT_QUANTITY", "invalid split is rejected after successful split")
	var after := graph.create_snapshot()
	_assert(int(after.get("revision", -2)) == before_revision, "rejected split preserves revision")
	_assert(int(after.get("tick", -2)) == before_tick, "rejected split preserves tick")
	_assert(String(after.get("checksum", "changed")) == before_checksum, "rejected split preserves canonical checksum")


func _test_rejected_transfer_does_not_normalize() -> void:
	var graph = _new_graph("transfer-reject")
	var battery: Dictionary = Dictionary(graph._items[BATTERY_ID]).duplicate(true)
	var location: Dictionary = Dictionary(battery.get("location", {})).duplicate(true)
	location.erase("slot_index")
	battery["location"] = location
	graph._items[BATTERY_ID] = battery
	var before := graph.create_snapshot()
	var rejected := graph.execute(
		"a",
		1,
		"operation/v0-p1/clock/transfer/rejected",
		"item.transfer",
		{
			"item_id": BATTERY_ID,
			"quantity": -1,
			"target_container_id": "inventory/a",
			"target_slot_index": 99,
			"target_item_id": "",
		}
	)
	_assert(String(rejected.get("error_code", "")) == "CONTAINER_FULL", "invalid target slot is rejected")
	var after := graph.create_snapshot()
	_assert(int(after.get("revision", -2)) == int(before.get("revision", -1)), "rejected transfer preserves revision")
	_assert(int(after.get("tick", -2)) == int(before.get("tick", -1)), "rejected transfer preserves tick")
	_assert(String(after.get("checksum", "changed")) == String(before.get("checksum", "")), "rejected transfer does not normalize slotless canonical state")


func _pickup_context() -> Dictionary:
	var player_position := Vector3(0.0, 0.4, 0.0)
	var target := Vector3(1.2, 0.4, -3.4)
	var view := (target - player_position).normalized()
	return {
		"player_position": _vector_dto(player_position),
		"interaction_origin": _vector_dto(player_position),
		"view_direction": _vector_dto(view),
		"orientation_yaw": 0.0,
	}


func _item_location(snapshot: Dictionary, item_id: String) -> Dictionary:
	for item_value in snapshot.get("items", []):
		if item_value is Dictionary and String(item_value.get("item_id", "")) == item_id:
			return Dictionary(item_value.get("location", {})).duplicate(true)
	return {}


func _vector_dto(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}


func _ok(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)


func _finish() -> void:
	print("V0-P1 canonical clock purity: %d assertions, %d failures" % [
		assertions,
		failures.size(),
	])
	quit(0 if failures.is_empty() else 1)
