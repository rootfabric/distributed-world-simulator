extends SceneTree

const CanonicalItemGraph = preload(
	"res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd"
)
const SlotAwareAdapter = preload(
	"res://scripts/runtime/networked_gameplay/m7/m7_item_graph_replica_adapter_slot_aware.gd"
)
const SlotAwareJournal = preload(
	"res://scripts/network/prediction/predicted_item_interaction_journal_slot_aware.gd"
)

const PLAYER_ID := "player-a"
const INVENTORY_ID := "inventory/player-a"
const CRATE_ID := "container/shared/crate/1"
const TEST_STACK_ID := "item/test/player-a/ore-stack"

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	_run()
	_finish()


func _run() -> void:
	_test_authoritative_sparse_slots_and_same_container_split()
	_test_replica_uses_authoritative_inventory_slot()
	_test_partial_transfer_prediction_confirms_exact_authority_child()
	_test_same_inventory_reorder_is_not_confirmed_by_unrelated_revision()


func _test_authoritative_sparse_slots_and_same_container_split() -> void:
	var graph = _graph_with_test_stack()
	var baseline: Dictionary = graph.create_snapshot()
	var battery := _item(baseline, "item/player/player-a/battery")
	_assert(int(battery.get("location", {}).get("slot_index", -1)) == 2, "starter battery keeps deterministic inventory slot 2")

	var reorder: Dictionary = graph.execute(
		PLAYER_ID,
		1,
		"slot-aware/reorder-battery",
		"item.transfer",
		{
			"item_id": "item/player/player-a/battery",
			"quantity": -1,
			"target_container_id": INVENTORY_ID,
			"target_slot_index": 10,
			"target_item_id": "",
		}
	)
	_assert_success(reorder, "same-inventory whole-stack reorder")
	var after_reorder: Dictionary = Dictionary(reorder.get("snapshot", {}))
	battery = _item(after_reorder, "item/player/player-a/battery")
	_assert(int(battery.get("location", {}).get("slot_index", -1)) == 10, "same-inventory reorder persists requested slot")
	_assert(not bool(Dictionary(reorder.get("details", {})).get("no_op", false)), "same-inventory reorder is not reported as no-op")

	var split_inventory: Dictionary = graph.execute(
		PLAYER_ID,
		1,
		"slot-aware/split-inventory",
		"item.transfer",
		{
			"item_id": TEST_STACK_ID,
			"quantity": 2,
			"target_container_id": INVENTORY_ID,
			"target_slot_index": 7,
			"target_item_id": "",
		}
	)
	_assert_success(split_inventory, "same-inventory partial transfer")
	var first_child_id := String(Dictionary(split_inventory.get("details", {})).get("item_id", ""))
	_assert(not first_child_id.is_empty() and first_child_id != TEST_STACK_ID, "partial inventory transfer creates authoritative child id")
	var after_split_inventory: Dictionary = Dictionary(split_inventory.get("snapshot", {}))
	_assert(int(_item(after_split_inventory, TEST_STACK_ID).get("quantity", 0)) == 2, "inventory split decrements source quantity")
	_assert(int(_item(after_split_inventory, TEST_STACK_ID).get("location", {}).get("slot_index", -1)) == 4, "inventory split preserves source slot")
	_assert(int(_item(after_split_inventory, first_child_id).get("quantity", 0)) == 2, "inventory split child has requested quantity")
	_assert(int(_item(after_split_inventory, first_child_id).get("location", {}).get("slot_index", -1)) == 7, "inventory split child occupies requested empty slot")

	var to_sparse_crate: Dictionary = graph.execute(
		PLAYER_ID,
		1,
		"slot-aware/to-crate-slot-6",
		"item.transfer",
		{
			"item_id": first_child_id,
			"quantity": -1,
			"target_container_id": CRATE_ID,
			"target_slot_index": 6,
			"target_item_id": "",
		}
	)
	_assert_success(to_sparse_crate, "inventory to sparse external-container slot")
	var after_crate: Dictionary = Dictionary(to_sparse_crate.get("snapshot", {}))
	_assert(_location_slot(after_crate, first_child_id, "CONTAINER", CRATE_ID) == 6, "external container preserves sparse slot 6 instead of compacting to slot 0")

	var same_container_reorder: Dictionary = graph.execute(
		PLAYER_ID,
		1,
		"slot-aware/crate-reorder",
		"item.transfer",
		{
			"item_id": first_child_id,
			"quantity": -1,
			"target_container_id": CRATE_ID,
			"target_slot_index": 1,
			"target_item_id": "",
		}
	)
	_assert_success(same_container_reorder, "same-container reorder")
	var after_container_reorder: Dictionary = Dictionary(same_container_reorder.get("snapshot", {}))
	_assert(_location_slot(after_container_reorder, first_child_id, "CONTAINER", CRATE_ID) == 1, "same-container reorder persists requested slot 1")
	_assert(not bool(Dictionary(same_container_reorder.get("details", {})).get("no_op", false)), "same-container reorder is not reported as no-op")

	var split_same_container: Dictionary = graph.execute(
		PLAYER_ID,
		1,
		"slot-aware/crate-split",
		"item.transfer",
		{
			"item_id": first_child_id,
			"quantity": 1,
			"target_container_id": CRATE_ID,
			"target_slot_index": 5,
			"target_item_id": "",
		}
	)
	_assert_success(split_same_container, "same-container partial transfer")
	var second_child_id := String(Dictionary(split_same_container.get("details", {})).get("item_id", ""))
	var after_container_split: Dictionary = Dictionary(split_same_container.get("snapshot", {}))
	_assert(second_child_id != first_child_id and not second_child_id.is_empty(), "same-container split creates second authoritative child")
	_assert(int(_item(after_container_split, first_child_id).get("quantity", 0)) == 1, "same-container split decrements source")
	_assert(_location_slot(after_container_split, first_child_id, "CONTAINER", CRATE_ID) == 1, "same-container split preserves source slot")
	_assert(int(_item(after_container_split, second_child_id).get("quantity", 0)) == 1, "same-container split child has requested quantity")
	_assert(_location_slot(after_container_split, second_child_id, "CONTAINER", CRATE_ID) == 5, "same-container split child occupies requested slot")

	var back_to_inventory: Dictionary = graph.execute(
		PLAYER_ID,
		1,
		"slot-aware/back-to-inventory",
		"item.transfer",
		{
			"item_id": second_child_id,
			"quantity": -1,
			"target_container_id": INVENTORY_ID,
			"target_slot_index": 12,
			"target_item_id": "",
		}
	)
	_assert_success(back_to_inventory, "external container to sparse inventory slot")
	var after_back: Dictionary = Dictionary(back_to_inventory.get("snapshot", {}))
	_assert(_location_slot(after_back, second_child_id, "INVENTORY", PLAYER_ID) == 12, "container-to-inventory transfer preserves requested slot 12")

	var occupied: Dictionary = graph.execute(
		PLAYER_ID,
		1,
		"slot-aware/occupied-target",
		"item.transfer",
		{
			"item_id": second_child_id,
			"quantity": -1,
			"target_container_id": INVENTORY_ID,
			"target_slot_index": 10,
			"target_item_id": "",
		}
	)
	_assert(not bool(occupied.get("success", false)), "occupied inventory target is rejected without overwriting")
	_assert(String(occupied.get("error_code", "")) == "TARGET_SLOT_OCCUPIED", "occupied inventory target reports TARGET_SLOT_OCCUPIED")
	_assert(_location_slot(graph.create_snapshot(), second_child_id, "INVENTORY", PLAYER_ID) == 12, "rejected occupied transfer preserves source slot")

	var battery_to_last_crate_slot: Dictionary = graph.execute(
		PLAYER_ID,
		1,
		"slot-aware/battery-to-crate-7",
		"item.transfer",
		{
			"item_id": "item/player/player-a/battery",
			"quantity": -1,
			"target_container_id": CRATE_ID,
			"target_slot_index": 7,
			"target_item_id": "",
		}
	)
	_assert_success(battery_to_last_crate_slot, "sparse last container slot accepts an item while compact membership is not full")
	_assert(_location_slot(Dictionary(battery_to_last_crate_slot.get("snapshot", {})), "item/player/player-a/battery", "CONTAINER", CRATE_ID) == 7, "container capacity is evaluated by slot occupancy, not compact array insertion index")


func _test_replica_uses_authoritative_inventory_slot() -> void:
	var graph = _graph_with_test_stack()
	var moved: Dictionary = graph.execute(
		PLAYER_ID,
		1,
		"slot-aware/adapter-source",
		"item.transfer",
		{
			"item_id": TEST_STACK_ID,
			"quantity": -1,
			"target_container_id": INVENTORY_ID,
			"target_slot_index": 13,
			"target_item_id": "",
		}
	)
	_assert_success(moved, "adapter fixture reorder")
	var snapshot: Dictionary = Dictionary(moved.get("snapshot", {}))
	var row := _item(snapshot, TEST_STACK_ID)
	var adapter = SlotAwareAdapter.new()
	_assert_success(adapter.setup(PLAYER_ID), "slot-aware replica adapter setup")
	var relation_result: Dictionary = adapter._relation_for_item(
		row,
		Dictionary(row.get("location", {})),
		Dictionary(snapshot.get("inventories", {})),
		{}
	)
	_assert_success(relation_result, "slot-aware replica relation conversion")
	var relation: Dictionary = Dictionary(Dictionary(relation_result.get("details", {})).get("relation", {}))
	_assert(String(relation.get("container_id", "")) == "player_inventory", "replica maps local canonical inventory to player_inventory")
	_assert(int(relation.get("slot_index", -1)) == 13, "replica uses canonical location.slot_index instead of compact membership index")


func _test_partial_transfer_prediction_confirms_exact_authority_child() -> void:
	var graph = _graph_with_test_stack()
	var authoritative: Dictionary = graph.create_snapshot()
	var journal = SlotAwareJournal.new()
	_assert_success(journal.setup(PLAYER_ID, {"timeout_ms": 8000, "max_pending": 8}), "slot-aware prediction journal setup")
	_assert_success(journal.adopt_authoritative(authoritative, 1000), "prediction adopts canonical slot-aware baseline")

	var prediction: Dictionary = journal.begin_prediction(
		"item.transfer",
		{
			"item_id": TEST_STACK_ID,
			"quantity": 2,
			"target_container_id": CRATE_ID,
			"target_slot_index": 6,
			"target_item_id": "",
		},
		"prediction/partial-to-crate",
		1010
	)
	_assert_success(prediction, "partial transfer prediction begins")
	_assert(journal.get_pending_predictions().size() == 1, "partial transfer remains pending before authority")
	var predicted_snapshot: Dictionary = journal.get_presentation_snapshot()
	_assert(int(_item(predicted_snapshot, TEST_STACK_ID).get("quantity", 0)) == 2, "partial prediction decrements presentation source")
	_assert(_count_items_at_slot(predicted_snapshot, "CONTAINER", CRATE_ID, 6, "item/ore", 2) == 1, "partial prediction creates exactly one presentation child at target slot")

	var authority_result: Dictionary = graph.execute(
		PLAYER_ID,
		1,
		"prediction/partial-to-crate",
		"item.transfer",
		{
			"item_id": TEST_STACK_ID,
			"quantity": 2,
			"target_container_id": CRATE_ID,
			"target_slot_index": 6,
			"target_item_id": "",
		}
	)
	_assert_success(authority_result, "authority accepts partial transfer")
	var authority_snapshot: Dictionary = Dictionary(authority_result.get("snapshot", {}))
	_assert_success(journal.adopt_authoritative(authority_snapshot, 1020), "prediction rebases onto authoritative split")
	_assert(journal.get_pending_predictions().is_empty(), "authoritative partial split satisfies pending prediction exactly once")
	_assert(int(journal.get_report().get("confirmed_by_snapshot", 0)) == 1, "partial transfer is confirmed by authoritative child")
	var projected: Dictionary = journal.get_presentation_snapshot()
	_assert(_item_ids(projected) == _item_ids(authority_snapshot), "confirmed partial transfer removes temporary projection item")
	_assert(_count_items_at_slot(projected, "CONTAINER", CRATE_ID, 6, "item/ore", 2) == 1, "confirmed projection contains only authoritative target child")


func _test_same_inventory_reorder_is_not_confirmed_by_unrelated_revision() -> void:
	var graph = _graph_with_test_stack()
	var baseline: Dictionary = graph.create_snapshot()
	var journal = SlotAwareJournal.new()
	_assert_success(journal.setup(PLAYER_ID, {"timeout_ms": 8000, "max_pending": 8}), "same-inventory journal setup")
	_assert_success(journal.adopt_authoritative(baseline, 2000), "same-inventory journal adopts baseline")

	var prediction: Dictionary = journal.begin_prediction(
		"item.transfer",
		{
			"item_id": TEST_STACK_ID,
			"quantity": -1,
			"target_container_id": INVENTORY_ID,
			"target_slot_index": 11,
			"target_item_id": "",
		},
		"prediction/reorder-slot-11",
		2010
	)
	_assert_success(prediction, "same-inventory reorder prediction begins")
	_assert(journal.get_pending_predictions().size() == 1, "same-inventory reorder starts pending")
	_assert(_location_slot(journal.get_presentation_snapshot(), TEST_STACK_ID, "INVENTORY", PLAYER_ID) == 11, "presentation immediately shows requested inventory slot")

	var unrelated: Dictionary = graph.execute(
		PLAYER_ID,
		1,
		"prediction/unrelated-revision",
		"inventory.select_hotbar",
		{"selected_hotbar_index": 2}
	)
	_assert_success(unrelated, "unrelated authority revision succeeds")
	var unrelated_snapshot: Dictionary = Dictionary(unrelated.get("snapshot", {}))
	_assert(_location_slot(unrelated_snapshot, TEST_STACK_ID, "INVENTORY", PLAYER_ID) == 4, "unrelated authority revision leaves source in original slot")
	_assert_success(journal.adopt_authoritative(unrelated_snapshot, 2020), "prediction rebases over unrelated authority revision")
	_assert(journal.get_pending_predictions().size() == 1, "same-inventory reorder is not falsely confirmed by broad INVENTORY location match")
	_assert(_location_slot(journal.get_presentation_snapshot(), TEST_STACK_ID, "INVENTORY", PLAYER_ID) == 11, "pending reorder is reapplied after unrelated revision")

	var authority_move: Dictionary = graph.execute(
		PLAYER_ID,
		1,
		"prediction/reorder-slot-11",
		"item.transfer",
		{
			"item_id": TEST_STACK_ID,
			"quantity": -1,
			"target_container_id": INVENTORY_ID,
			"target_slot_index": 11,
			"target_item_id": "",
		}
	)
	_assert_success(authority_move, "authority performs requested same-inventory reorder")
	_assert_success(journal.adopt_authoritative(Dictionary(authority_move.get("snapshot", {})), 2030), "prediction adopts actual reordered authority state")
	_assert(journal.get_pending_predictions().is_empty(), "same-inventory reorder confirms only after requested slot becomes authoritative")
	_assert(_location_slot(journal.get_presentation_snapshot(), TEST_STACK_ID, "INVENTORY", PLAYER_ID) == 11, "confirmed same-inventory reorder remains in slot 11")


func _graph_with_test_stack():
	var graph = CanonicalItemGraph.new()
	_assert_success(graph.setup("authority/slot-aware-test", 1, {"playable_sandbox": true}), "canonical slot-aware fixture setup")
	_assert_success(graph.ensure_player_for_join(PLAYER_ID), "canonical slot-aware fixture player materialization")
	var inventory: Dictionary = Dictionary(graph._inventories[PLAYER_ID]).duplicate(true)
	var membership: Array = Array(inventory.get("inventory", [])).duplicate()
	membership.append(TEST_STACK_ID)
	inventory["inventory"] = membership
	graph._inventories[PLAYER_ID] = inventory
	graph._items[TEST_STACK_ID] = {
		"item_id": TEST_STACK_ID,
		"definition_id": "item/ore",
		"quantity": 4,
		"location": {
			"kind": "INVENTORY",
			"player_id": PLAYER_ID,
			"slot_index": 4,
		},
		"mounted": false,
	}
	graph._open_containers[PLAYER_ID] = CRATE_ID
	graph.create_snapshot()
	return graph


func _item(snapshot: Dictionary, item_id: String) -> Dictionary:
	for item_value in snapshot.get("items", []):
		if item_value is Dictionary and String(item_value.get("item_id", "")) == item_id:
			return Dictionary(item_value).duplicate(true)
	return {}


func _location_slot(
	snapshot: Dictionary,
	item_id: String,
	expected_kind: String,
	expected_owner: String
) -> int:
	var row := _item(snapshot, item_id)
	var location: Dictionary = Dictionary(row.get("location", {}))
	if String(location.get("kind", "")) != expected_kind:
		return -1
	if expected_kind == "INVENTORY" and String(location.get("player_id", "")) != expected_owner:
		return -1
	if expected_kind == "CONTAINER" and String(location.get("container_id", "")) != expected_owner:
		return -1
	return int(location.get("slot_index", -1))


func _count_items_at_slot(
	snapshot: Dictionary,
	kind: String,
	owner_id: String,
	slot_index: int,
	definition_id: String,
	quantity: int
) -> int:
	var count := 0
	for item_value in snapshot.get("items", []):
		if not item_value is Dictionary:
			continue
		var row: Dictionary = item_value
		if String(row.get("definition_id", "")) != definition_id or int(row.get("quantity", 0)) != quantity:
			continue
		var location: Dictionary = Dictionary(row.get("location", {}))
		if String(location.get("kind", "")) != kind or int(location.get("slot_index", -1)) != slot_index:
			continue
		if kind == "INVENTORY" and String(location.get("player_id", "")) != owner_id:
			continue
		if kind == "CONTAINER" and String(location.get("container_id", "")) != owner_id:
			continue
		count += 1
	return count


func _item_ids(snapshot: Dictionary) -> Array:
	var ids: Array = []
	for item_value in snapshot.get("items", []):
		if item_value is Dictionary:
			ids.append(String(item_value.get("item_id", "")))
	ids.sort()
	return ids


func _assert_success(result: Dictionary, message: String) -> void:
	_assert(
		bool(result.get("success", false)),
		"%s: %s" % [message, String(result.get("error_code", "UNKNOWN"))]
	)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("M7 slot-aware item transfer tests: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("M7 slot-aware item transfer tests: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
