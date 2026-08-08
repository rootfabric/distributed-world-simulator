extends SceneTree

const Journal = preload("res://scripts/network/prediction/predicted_item_interaction_journal.gd")
const CursorController = preload("res://scripts/ui/inventory/interactions/inventory_cursor_controller.gd")
const TransferSession = preload("res://scripts/ui/inventory/interactions/inventory_transfer_session.gd")
const SlotProjection = preload("res://scripts/ui/inventory/interactions/inventory_slot_projection.gd")
const CommandFacade = preload("res://scripts/ui/inventory/inventory_command_facade.gd")

class FakeReplicaItem:
	extends RefCounted
	var instance_id: String
	var quantity: int
	var revision: int

	func _init(configured_id: String, configured_quantity: int, configured_revision: int) -> void:
		instance_id = configured_id
		quantity = configured_quantity
		revision = configured_revision


class FakeReplicaController:
	extends RefCounted
	var profile_id: String = "playground"
	var runtime_mode: String = "replica"
	var network_command_bridge = RefCounted.new()
	var item
	var cursor_carry_calls: int = 0
	var drop_calls: Array[Dictionary] = []
	var transfer_calls: Array[Dictionary] = []

	func _init(item_id: String) -> void:
		item = FakeReplicaItem.new(item_id, 4, 7)

	func get_item(item_id: String):
		return item if item != null and String(item.instance_id) == item_id else null

	func begin_inventory_cursor_carry(
		_item_id: String,
		_requested_quantity: int,
		_cursor_container_id: String
	) -> Dictionary:
		cursor_carry_calls += 1
		return {"success": false, "error_code": "LOCAL_CURSOR_MUTATION_MUST_NOT_RUN"}

	func drop_item_quantity(
		item_id: String,
		quantity: int,
		_override_transform: Transform3D = Transform3D.IDENTITY
	) -> Dictionary:
		drop_calls.append({"item_id": item_id, "quantity": quantity})
		return {"success": true, "item_id": item_id, "moved_quantity": quantity}

	func move_item_quantity_to_container(
		item_id: String,
		quantity: int,
		target_container_id: String,
		target_slot_index: int = -1,
		target_item_id: String = ""
	) -> Dictionary:
		transfer_calls.append({
			"item_id": item_id,
			"quantity": quantity,
			"target_container_id": target_container_id,
			"target_slot_index": target_slot_index,
			"target_item_id": target_item_id,
		})
		return {"success": true, "item_id": item_id, "moved_quantity": quantity}


var failures: Array[String] = []
var assertions := 0

func _init() -> void:
	_test_pickup_and_rollback()
	_test_pickup_confirmation()
	_test_drop_place_transfer()
	_test_concurrent_rebase()
	_test_clocks_and_timeout()
	_test_network_replica_cursor_identity()
	_property_sequence()
	_finish()

func _snapshot(revision: int = 1) -> Dictionary:
	return {
		"schema": "planet_simulator.canonical_multiplayer_item_graph_snapshot.v1",
		"authority_owner_id": "authority/nx6",
		"authority_epoch": 1,
		"revision": revision,
		"tick": revision,
		"items": [
			{"item_id":"item/world/ore","definition_id":"item/ore","quantity":8,"location":{"kind":"WORLD"},"mounted":false,"transform":{"basis":[1,0,0,0,1,0,0,0,1],"origin":[1,0,0]}},
			{"item_id":"item/player/beacon","definition_id":"item/beacon","quantity":3,"location":{"kind":"INVENTORY","player_id":"a"},"mounted":false},
			{"item_id":"item/player/base","definition_id":"item/mount-base","quantity":2,"location":{"kind":"INVENTORY","player_id":"a"},"mounted":false},
			{"item_id":"item/player/battery","definition_id":"item/battery","quantity":2,"location":{"kind":"INVENTORY","player_id":"a"},"mounted":false},
		],
		"inventories": {"a":{"inventory":["item/player/beacon","item/player/base","item/player/battery"],"hotbar":["item/player/beacon","item/player/base","","","","","","","",""],"selected_hotbar_index":0}},
		"containers": [{"container_id":"container/crate","owner_item_id":"","capacity":8,"slots":[]}],
		"mounts": [],
		"open_containers": {"a":"container/crate"},
		"checksum": ("%064d" % revision),
	}

func _journal(options: Dictionary = {}) -> RefCounted:
	var journal = Journal.new()
	var setup := journal.setup("a", options)
	_assert(bool(setup.get("success", false)), "journal setup")
	_assert(bool(journal.adopt_authoritative(_snapshot()).get("success", false)), "adopt base")
	return journal

func _test_pickup_and_rollback() -> void:
	var journal = _journal()
	var predicted: Dictionary = journal.begin_prediction("item.pickup", {"item_id":"item/world/ore"}, "prediction/pickup/1", 100)
	_assert(bool(predicted.get("success", false)), "pickup predicted")
	var view: Dictionary = predicted.get("details", {}).get("presentation_snapshot", {})
	_assert(_location(view, "item/world/ore") == "INVENTORY", "pickup enters optimistic inventory")
	_assert(view.has("prediction_overlay"), "pickup overlay marked presentation-only")
	_assert(_location(journal.get_authoritative_snapshot(), "item/world/ore") == "WORLD", "authority stays unchanged")
	var rollback: Dictionary = journal.resolve_prediction("prediction/pickup/1", {"success":false,"error_code":"ITEM_ALREADY_CLAIMED"}, {}, 110)
	_assert(bool(rollback.get("success", false)), "pickup rejection resolved")
	_assert(_location(journal.get_presentation_snapshot(), "item/world/ore") == "WORLD", "pickup rolls back")
	_assert(not journal.get_presentation_snapshot().has("prediction_overlay"), "rollback clears overlay")

func _test_pickup_confirmation() -> void:
	var journal = _journal()
	_assert(bool(journal.begin_prediction("item.pickup", {"item_id":"item/world/ore"}, "prediction/pickup/2", 100).get("success", false)), "second pickup predicted")
	var confirmed := _snapshot(2)
	var items: Array = confirmed["items"]
	var ore: Dictionary = items[0]
	ore["location"] = {"kind":"INVENTORY","player_id":"a"}
	ore.erase("transform")
	items[0] = ore
	confirmed["items"] = items
	confirmed["inventories"]["a"]["inventory"].append("item/world/ore")
	var adopted: Dictionary = journal.adopt_authoritative(confirmed, 120)
	_assert(bool(adopted.get("success", false)), "confirmation snapshot adopted")
	_assert(journal.get_pending_predictions().is_empty(), "snapshot confirms pending pickup")
	_assert(_location(journal.get_presentation_snapshot(), "item/world/ore") == "INVENTORY", "confirmed pickup retained")
	_assert(int(journal.get_report().get("confirmed_by_snapshot", 0)) == 1, "snapshot confirmation counted")

func _test_drop_place_transfer() -> void:
	var journal = _journal()
	var transform := {"basis":[1,0,0,0,1,0,0,0,1],"origin":[4,0,2]}
	var drop: Dictionary = journal.begin_prediction("item.drop", {"item_id":"item/player/beacon","quantity":1,"transform":transform}, "prediction/drop/1", 100)
	_assert(bool(drop.get("success", false)), "partial drop predicted")
	var drop_view: Dictionary = drop.get("details", {}).get("presentation_snapshot", {})
	_assert(_quantity(drop_view, "item/player/beacon") == 2, "partial drop decrements source")
	_assert(_count_prefix(drop_view, "item/predicted/") == 1, "partial drop creates temporary spawn")
	var place: Dictionary = journal.begin_prediction("item.place", {"item_id":"item/player/base","transform":transform}, "prediction/place/1", 101)
	_assert(bool(place.get("success", false)), "placement predicted")
	var place_view: Dictionary = place.get("details", {}).get("presentation_snapshot", {})
	_assert(_quantity(place_view, "item/player/base") == 1, "placement decrements source")
	_assert(Array(place_view.get("mounts", [])).size() == 1, "placement creates predicted mount ghost")
	var transfer: Dictionary = journal.begin_prediction("item.transfer", {"item_id":"item/player/battery","quantity":1,"target_container_id":"container/crate","target_slot_index":0,"target_item_id":""}, "prediction/transfer/1", 102)
	_assert(bool(transfer.get("success", false)), "inventory transfer predicted")
	var transfer_view: Dictionary = transfer.get("details", {}).get("presentation_snapshot", {})
	_assert(_quantity(transfer_view, "item/player/battery") == 1, "partial transfer decrements source")
	_assert(Array(Dictionary(Array(transfer_view["containers"])[0]).get("slots", [])).size() == 1, "predicted item enters container slot")
	_assert(journal.get_pending_predictions().size() == 3, "three independent predictions retained")

func _test_concurrent_rebase() -> void:
	var journal = _journal()
	_assert(bool(journal.begin_prediction("item.drop", {"item_id":"item/player/beacon","quantity":1}, "prediction/rebase/drop", 100).get("success", false)), "rebase drop predicted")
	_assert(bool(journal.begin_prediction("item.transfer", {"item_id":"item/player/battery","quantity":1,"target_container_id":"container/crate","target_slot_index":0}, "prediction/rebase/transfer", 101).get("success", false)), "rebase transfer predicted")
	var newer := _snapshot(2)
	newer["tick"] = 9
	var adopted: Dictionary = journal.adopt_authoritative(newer, 105)
	_assert(bool(adopted.get("success", false)), "new authority rebases pending")
	_assert(journal.get_pending_predictions().size() == 2, "unrelated pending survive rebase")
	var view: Dictionary = journal.get_presentation_snapshot()
	_assert(_quantity(view, "item/player/beacon") == 2, "drop replayed after rebase")
	_assert(_quantity(view, "item/player/battery") == 1, "transfer replayed after rebase")

func _test_clocks_and_timeout() -> void:
	var journal = _journal({"timeout_ms":100,"max_pending":2})
	_assert(not bool(journal.adopt_authoritative(_snapshot(0)).get("success", true)), "stale authority rejected")
	var conflict := _snapshot(1); conflict["checksum"] = "f".repeat(64)
	_assert(String(journal.adopt_authoritative(conflict).get("error_code", "")) == "CONFLICTING_AUTHORITATIVE_ITEM_GRAPH_REVISION", "same revision mutation rejected")
	_assert(bool(journal.begin_prediction("item.pickup", {"item_id":"item/world/ore"}, "prediction/timeout", 100).get("success", false)), "timeout prediction accepted")
	var expired: Dictionary = journal.expire(201)
	_assert(bool(expired.get("success", false)), "expiration succeeds")
	_assert(journal.get_pending_predictions().is_empty(), "expired prediction removed")
	_assert(_location(journal.get_presentation_snapshot(), "item/world/ore") == "WORLD", "timeout rolls back presentation")

func _test_network_replica_cursor_identity() -> void:
	var source_id := "item/replica/server-backed"
	var controller = FakeReplicaController.new(source_id)
	var facade = CommandFacade.new()
	facade.setup(controller)
	var session = TransferSession.new()
	var projection = SlotProjection.new()
	var cursor = CursorController.new()
	cursor.setup(controller, facade, session, projection, Callable())
	var payload := {
		"item_id": source_id,
		"quantity": 4,
		"revision": 7,
		"display_name": "Server backed stack",
		"definition_id": "survey_beacon",
		"source_container_id": "player_inventory",
		"source_slot_index": 2,
	}
	var begun: Dictionary = cursor.begin(payload, 2)
	_assert(bool(begun.get("success", false)), "network replica half-carry begins")
	_assert(bool(begun.get("network_virtual", false)), "network replica carry is virtual")
	_assert(controller.cursor_carry_calls == 0, "network replica carry must not mutate local cursor domain")
	_assert(session.item_id == source_id, "network replica carry preserves server-backed replica id")
	_assert(session.remaining_quantity == 2, "network replica virtual carry tracks requested quantity")
	_assert(int(controller.item.quantity) == 4, "network replica carry leaves local source quantity unchanged")
	var dropped: Dictionary = cursor.drop_to_world(1)
	_assert(bool(dropped.get("success", false)), "network replica virtual drop succeeds")
	_assert(controller.drop_calls.size() == 1, "network replica virtual drop reaches command facade once")
	_assert(String(controller.drop_calls[0].get("item_id", "")) == source_id, "network replica drop uses original server-backed id")
	_assert(int(controller.drop_calls[0].get("quantity", 0)) == 1, "network replica drop preserves requested quantity")
	_assert(session.is_active() and session.remaining_quantity == 1, "partial network drop keeps one virtual item on cursor")
	var placed: Dictionary = cursor.place({
		"target_container_id": "player_hotbar",
		"target_slot_index": 4,
		"target_item_id": "",
	}, 1)
	_assert(bool(placed.get("success", false)), "network replica virtual transfer succeeds")
	_assert(controller.transfer_calls.size() == 1, "network replica virtual transfer reaches command facade once")
	_assert(String(controller.transfer_calls[0].get("item_id", "")) == source_id, "network replica transfer uses original server-backed id")
	_assert(not session.is_active(), "network replica cursor clears after final virtual quantity")
	_assert(not bool(cursor.debug_snapshot().get("network_virtual", true)), "network virtual mode clears after completion")
	_assert(controller.cursor_carry_calls == 0, "network replica path never creates local split item id")

func _property_sequence() -> void:
	for seed in range(128):
		var journal = _journal({"timeout_ms":500,"max_pending":8})
		var id := "prediction/property/%d" % seed
		var predicted: Dictionary = journal.begin_prediction("item.drop", {"item_id":"item/player/beacon","quantity":1}, id, seed)
		_assert(bool(predicted.get("success", false)), "property prediction accepted %d" % seed)
		_assert(_quantity(journal.get_presentation_snapshot(), "item/player/beacon") == 2, "property quantity deterministic %d" % seed)
		var duplicate: Dictionary = journal.begin_prediction("item.drop", {"item_id":"item/player/beacon","quantity":1}, id, seed + 1)
		_assert(bool(duplicate.get("success", false)) and bool(duplicate.get("details", {}).get("duplicate", false)), "property duplicate idempotent %d" % seed)
		var rollback: Dictionary = journal.resolve_prediction(id, {"success":false,"error_code":"PROBE"}, {}, seed + 2)
		_assert(bool(rollback.get("success", false)), "property rollback accepted %d" % seed)
		_assert(_quantity(journal.get_presentation_snapshot(), "item/player/beacon") == 3, "property rollback exact %d" % seed)

func _location(snapshot: Dictionary, item_id: String) -> String:
	for value in snapshot.get("items", []):
		if value is Dictionary and String(value.get("item_id", "")) == item_id:
			return String(value.get("location", {}).get("kind", ""))
	return ""
func _quantity(snapshot: Dictionary, item_id: String) -> int:
	for value in snapshot.get("items", []):
		if value is Dictionary and String(value.get("item_id", "")) == item_id:
			return int(value.get("quantity", 0))
	return 0
func _count_prefix(snapshot: Dictionary, prefix: String) -> int:
	var count := 0
	for value in snapshot.get("items", []):
		if value is Dictionary and String(value.get("item_id", "")).begins_with(prefix): count += 1
	return count
func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)
func _finish() -> void:
	if failures.is_empty():
		print("NX6 predicted item interaction contracts: PASS (%d assertions)" % assertions)
		quit(0)
	else:
		for failure in failures: push_error(failure)
		print("NX6 predicted item interaction contracts: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
		quit(1)
