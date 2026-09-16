extends SceneTree

# Initial pickup/drop/correction cases reused from exact external 6b147d03.
const Bridge = preload("res://scripts/runtime/networked_gameplay/m7/m7_network_item_command_bridge.gd")
const IntegrationFixture = preload("res://tests/network/test_nx6_predicted_item_interactions_integration.gd")
const Journal = preload("res://scripts/network/prediction/predicted_item_interaction_journal.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_pickup_rollback_with_duplicate_authority()
	_test_drop_rollback_with_duplicate_authority()
	_test_corrected_authority_survives_later_rollback()
	_test_place_transfer_and_pending_sibling()
	_test_timeout_and_newer_authority()
	await _test_bridge_completion_and_stop()
	_finish()


func _snapshot(revision: int = 1, world_x: float = 1.0) -> Dictionary:
	return {
		"schema": "planet_simulator.canonical_multiplayer_item_graph_snapshot.v1",
		"authority_owner_id": "authority/test/prediction-rollback",
		"authority_epoch": 1,
		"revision": revision,
		"tick": revision,
		"items": [
			{
				"item_id": "item/world/ore",
				"definition_id": "item/ore",
				"quantity": 8,
				"location": {"kind": "WORLD"},
				"mounted": false,
				"transform": {
					"basis": [1,0,0,0,1,0,0,0,1],
					"origin": [world_x,0,0],
				},
			},
			{
				"item_id": "item/player/beacon",
				"definition_id": "item/beacon",
				"quantity": 3,
				"location": {"kind": "INVENTORY", "player_id": "a"},
				"mounted": false,
			},
		],
		"inventories": {
			"a": {
				"inventory": ["item/player/beacon"],
				"hotbar": ["item/player/beacon","","","","","","","","",""],
				"selected_hotbar_index": 0,
			},
		},
		"containers": [],
		"mounts": [],
		"open_containers": {},
		"checksum": ("%064d" % revision),
	}


func _journal(snapshot: Dictionary) -> RefCounted:
	var journal = Journal.new()
	_assert(bool(journal.setup("a", {"timeout_ms": 8000, "max_pending": 8}).get("success", false)), "journal setup")
	_assert(bool(journal.adopt_authoritative(snapshot, 1000).get("success", false)), "adopt authority")
	return journal


func _test_pickup_rollback_with_duplicate_authority() -> void:
	var canonical := _snapshot()
	var journal = _journal(canonical)
	var prediction: Dictionary = journal.begin_prediction(
		"item.pickup", {"item_id": "item/world/ore"}, "prediction/duplicate/pickup", 1010
	)
	_assert(bool(prediction.get("success", false)), "pickup prediction starts")
	_assert(_location(journal.get_presentation_snapshot(), "item/world/ore") == "INVENTORY", "pickup is optimistic")
	var rollback: Dictionary = journal.resolve_prediction(
		"prediction/duplicate/pickup",
		{"success": false, "error_code": "ITEM_ALREADY_CLAIMED"},
		canonical,
		1020
	)
	_assert(bool(rollback.get("success", false)), "pickup rollback resolves")
	_assert(String(rollback.get("details", {}).get("resolution", "")) == "ROLLED_BACK", "pickup rollback resolution explicit")
	_assert(_location(journal.get_presentation_snapshot(), "item/world/ore") == "WORLD", "duplicate authority restores pickup presentation")
	_assert(not journal.get_presentation_snapshot().has("prediction_overlay"), "pickup rollback clears overlay")
	_assert(journal.get_pending_predictions().is_empty(), "pickup rollback removes pending")


func _test_drop_rollback_with_duplicate_authority() -> void:
	var canonical := _snapshot()
	var journal = _journal(canonical)
	var prediction: Dictionary = journal.begin_prediction(
		"item.drop",
		{
			"item_id": "item/player/beacon",
			"quantity": 1,
			"transform": {"basis": [1,0,0,0,1,0,0,0,1], "origin": [3,0,1]},
		},
		"prediction/duplicate/drop",
		2010
	)
	_assert(bool(prediction.get("success", false)), "drop prediction starts")
	_assert(_quantity(journal.get_presentation_snapshot(), "item/player/beacon") == 2, "drop decrements optimistic source")
	_assert(_count_prefix(journal.get_presentation_snapshot(), "item/predicted/") == 1, "drop creates optimistic spawn")
	var rollback: Dictionary = journal.resolve_prediction(
		"prediction/duplicate/drop",
		{"success": false, "error_code": "DROP_REJECTED"},
		canonical,
		2020
	)
	_assert(bool(rollback.get("success", false)), "drop rollback resolves")
	_assert(_quantity(journal.get_presentation_snapshot(), "item/player/beacon") == 3, "duplicate authority restores drop quantity")
	_assert(_count_prefix(journal.get_presentation_snapshot(), "item/predicted/") == 0, "duplicate authority removes optimistic spawn")
	_assert(not journal.get_presentation_snapshot().has("prediction_overlay"), "drop rollback clears overlay")


func _test_corrected_authority_survives_later_rollback() -> void:
	var journal = _journal(_snapshot(1, 1.0))
	_assert(bool(journal.begin_prediction(
		"item.pickup", {"item_id": "item/world/ore"}, "prediction/corrected/pickup", 3010
	).get("success", false)), "corrected pickup starts")
	var corrected := _snapshot(2, 7.0)
	_assert(bool(journal.adopt_authoritative(corrected, 3020).get("success", false)), "new authoritative correction adopted")
	_assert(_location(journal.get_presentation_snapshot(), "item/world/ore") == "INVENTORY", "pending pickup remains projected over correction")
	var rollback: Dictionary = journal.resolve_prediction(
		"prediction/corrected/pickup",
		{"success": false, "error_code": "PICKUP_REJECTED_AFTER_CORRECTION"},
		corrected,
		3030
	)
	_assert(bool(rollback.get("success", false)), "rollback against duplicate corrected authority resolves")
	var view: Dictionary = journal.get_presentation_snapshot()
	_assert(int(view.get("revision", -1)) == 2, "corrected revision retained")
	_assert(_location(view, "item/world/ore") == "WORLD", "rollback exposes corrected canonical location")
	_assert(absf(_origin_x(view, "item/world/ore") - 7.0) < 0.000001, "rollback exposes corrected canonical transform")
	_assert(int(journal.get_authoritative_snapshot().get("revision", -1)) == 2, "canonical correction remains authoritative")


func _item(snapshot: Dictionary, item_id: String) -> Dictionary:
	for value in snapshot.get("items", []):
		if value is Dictionary and String(value.get("item_id", "")) == item_id:
			return Dictionary(value)
	return {}


func _location(snapshot: Dictionary, item_id: String) -> String:
	return String(_item(snapshot, item_id).get("location", {}).get("kind", ""))


func _quantity(snapshot: Dictionary, item_id: String) -> int:
	return int(_item(snapshot, item_id).get("quantity", 0))


func _origin_x(snapshot: Dictionary, item_id: String) -> float:
	var transform := Dictionary(_item(snapshot, item_id).get("transform", {}))
	var origin: Array = transform.get("origin", [])
	return float(origin[0]) if origin.size() >= 1 else NAN


func _count_prefix(snapshot: Dictionary, prefix: String) -> int:
	var count := 0
	for value in snapshot.get("items", []):
		if value is Dictionary and String(value.get("item_id", "")).begins_with(prefix):
			count += 1
	return count


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error("prediction duplicate-authority rollback: %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("MVP6 prediction rollback: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("MVP6 prediction rollback: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)


func _test_place_transfer_and_pending_sibling() -> void:
	for command in ["item.place", "item.transfer"]:
		var canonical := _snapshot()
		canonical["containers"] = [{"container_id":"container/test", "owner_item_id":"", "capacity":8, "slots":[]}]
		canonical["open_containers"] = {"a":"container/test"}
		var journal = _journal(canonical)
		var payload := {"item_id":"item/player/beacon", "quantity":1,
			"transform":{"basis":[1,0,0,0,1,0,0,0,1], "origin":[3,0,1]},
			"target_container_id":"container/test", "target_slot_index":0}
		_assert(bool(journal.begin_prediction(command, payload, "prediction/extra", 1010).get("success", false)), command + " starts")
		_assert(journal.get_presentation_snapshot() != canonical, command + " changes presentation")
		_assert(bool(journal.resolve_prediction("prediction/extra", {"success":false}, canonical, 1020).get("success", false)), command + " resolves")
		_assert(journal.get_presentation_snapshot() == canonical, command + " restores complete snapshot including mounts/container")
		_assert(journal.get_authoritative_snapshot() == canonical, command + " never changes canonical snapshot")
	var canonical := _snapshot()
	var journal = _journal(canonical)
	var reference = _journal(canonical)
	var drop := {"item_id":"item/player/beacon", "quantity":1, "transform":{"basis":[1,0,0,0,1,0,0,0,1], "origin":[3,0,1]}}
	_assert(bool(journal.begin_prediction("item.pickup", {"item_id":"item/world/ore"}, "prediction/rejected", 1010).get("success", false)), "sibling pickup starts")
	_assert(bool(journal.begin_prediction("item.drop", drop, "prediction/survivor", 1011).get("success", false)), "sibling drop starts")
	_assert(bool(reference.begin_prediction("item.drop", drop, "prediction/survivor", 1011).get("success", false)), "independent survivor oracle starts")
	_assert(bool(journal.resolve_prediction("prediction/rejected", {"success":false}, canonical, 1020).get("success", false)), "sibling rejection resolves")
	_assert(journal.get_presentation_snapshot() == reference.get_presentation_snapshot(), "remaining prediction reapplied exactly once")
	_assert(journal.get_pending_predictions().size() == 1, "survivor stays pending")
	_assert(int(journal.get_report().get("confirmed_by_snapshot", -1)) == 0, "unchanged snapshot does not confirm survivor")
	var before: Dictionary = journal.get_presentation_snapshot()
	var duplicate: Dictionary = journal.resolve_prediction("prediction/rejected", {"success":false}, canonical, 1030)
	_assert(bool(duplicate.get("details", {}).get("duplicate", false)), "duplicate response acknowledged")
	_assert(journal.get_presentation_snapshot() == before, "duplicate does not reapply survivor")
	_assert(int(journal.get_report().get("rolled_back", -1)) == 1, "rollback counted once")


func _test_timeout_and_newer_authority() -> void:
	var canonical := _snapshot()
	var journal = _journal(canonical)
	_assert(bool(journal.begin_prediction("item.pickup", {"item_id":"item/world/ore"}, "prediction/timeout", 1010).get("success", false)), "timeout starts")
	_assert(bool(journal.expire(10000).get("success", false)), "timeout expires")
	_assert(journal.get_presentation_snapshot() == canonical, "timeout restores full canonical view")
	var next := _snapshot(2)
	next["items"][0]["location"] = {"kind":"INVENTORY", "player_id":"a"}
	next["items"][0].erase("transform")
	next["inventories"]["a"]["inventory"].append("item/world/ore")
	_assert(bool(journal.begin_prediction("item.pickup", {"item_id":"item/world/ore"}, "prediction/confirmed", 10010).get("success", false)), "confirmation starts")
	_assert(bool(journal.resolve_prediction("prediction/confirmed", {"success":true}, next, 10020).get("success", false)), "newer authoritative success resolves")
	_assert(journal.get_presentation_snapshot() == next, "newer snapshot keeps canonical item and quantity")
	_assert(journal.get_authoritative_snapshot() == next, "newer authority remains source of truth")


class ProjectionSink:
	extends RefCounted
	var snapshot: Dictionary = {}
	func receive(value: Dictionary) -> void:
		snapshot = value.duplicate(true)


func _test_bridge_completion_and_stop() -> void:
	for cancel in [false, true]:
		var canonical := _snapshot()
		var runtime = IntegrationFixture.FakeRuntime.new(canonical)
		root.add_child(runtime)
		var bridge = Bridge.new()
		_assert(bool(bridge.setup(runtime, "a").get("success", false)), "native bridge setup")
		var sink := ProjectionSink.new()
		bridge.projected_item_graph_updated.connect(sink.receive)
		var submitted: Dictionary = bridge.submit_item_command("item.pickup", {"item_id":"item/world/ore"}, "operation/mvp6/rollback")
		_assert(bool(submitted.get("pending", false)), "native pump has pending pickup")
		_assert(_location(bridge.project_canonical_snapshot(canonical), "item/world/ore") == "INVENTORY", "bridge projects optimistic item")
		if cancel:
			_assert(bool(bridge.stop("MVP6_TEST_CANCEL").get("success", false)), "native stop succeeds")
		else:
			runtime.complete("operation/mvp6/rollback", false)
			var pump = runtime.get_node_or_null("NX6PredictedItemCommandPump")
			_assert(pump != null, "native completion pump exists")
			if pump != null:
				pump._process(0.0)
		_assert(sink.snapshot == canonical, "completion/stop publishes restored canonical values")
		_assert(runtime.get_item_graph_snapshot() == canonical, "bridge leaves canonical truth unchanged")
		bridge.stop("MVP6_TEST_COMPLETE")
		runtime.queue_free()
		await process_frame
