extends SceneTree

const Bridge = preload("res://scripts/runtime/networked_gameplay/m7/m7_network_item_command_bridge.gd")

var failures: Array[String] = []
var assertions := 0


class FakeRuntime:
	extends Node

	signal item_graph_updated(snapshot: Dictionary)

	var _awaited_command_ids: Dictionary = {}
	var _command_results: Dictionary = {}
	var _ownership_epoch := 1
	var snapshot: Dictionary
	var sent: Array[Dictionary] = []
	var consumer_updates := 0
	var raw_runtime_updates := 0

	func _init(value: Dictionary) -> void:
		snapshot = value
		item_graph_updated.connect(_on_consumer_update)

	func is_ready() -> bool:
		return true

	func get_item_graph_snapshot() -> Dictionary:
		return snapshot.duplicate(true)

	func execute_item_command_blocking(
		_command_type: String,
		_payload: Dictionary,
		_operation_id: String = "",
		_ownership_epoch_override: int = 0
	) -> Dictionary:
		return {"success": false, "error_code": "BLOCKING_PATH_USED"}

	func _send_on_channel(
		_message_type: String,
		data: Dictionary,
		_channel: String,
		_delivery: String,
		_track: bool
	) -> bool:
		sent.append(data.duplicate(true))
		return true

	func _discard_operation_timer(_operation_id: String) -> void:
		pass

	func complete(operation_id: String, success: bool, updated: Dictionary = {}) -> void:
		if not updated.is_empty():
			snapshot = updated.duplicate(true)
			item_graph_updated.emit(snapshot.duplicate(true))
		_command_results[operation_id] = {
			"operation_id": operation_id,
			"status": "SUCCEEDED" if success else "REJECTED",
			"error_code": "" if success else "ITEM_ALREADY_CLAIMED",
		}

	func connect_raw_probe() -> void:
		item_graph_updated.connect(_on_raw_runtime_update)

	func _on_consumer_update(_snapshot: Dictionary) -> void:
		consumer_updates += 1

	func _on_raw_runtime_update(_snapshot: Dictionary) -> void:
		raw_runtime_updates += 1


class ServiceBackedClient:
	extends RefCounted

	signal item_graph_updated(snapshot: Dictionary)

	var snapshot: Dictionary
	var blocking_calls := 0

	func _init(value: Dictionary) -> void:
		snapshot = value

	func get_item_graph_snapshot() -> Dictionary:
		return snapshot.duplicate(true)

	func execute_item_command_blocking(
		_command_type: String,
		_payload: Dictionary,
		_operation_id: String = ""
	) -> Dictionary:
		blocking_calls += 1
		return {"success": false, "error_code": "ITEM_ALREADY_CLAIMED"}




class BridgeStopProbe:
	extends RefCounted

	var calls := 0
	var reason := ""

	func stop(error_code: String = "NX6_BRIDGE_STOPPED") -> Dictionary:
		calls += 1
		reason = error_code
		return {"success": true, "error_code": "", "details": {"already_stopped": calls > 1}}


class SelectedProvider:
	extends RefCounted

	var item_id := ""

	func _init(value: String) -> void:
		item_id = value

	func get_selected_item_id() -> String:
		return item_id


func _snapshot(revision: int = 1) -> Dictionary:
	return {
		"schema": "planet_simulator.canonical_multiplayer_item_graph_snapshot.v1",
		"authority_owner_id": "authority",
		"authority_epoch": 1,
		"revision": revision,
		"tick": revision,
		"items": [{
			"item_id": "item/ore",
			"definition_id": "item/ore",
			"quantity": 1,
			"location": {"kind": "WORLD"},
			"mounted": false,
		}],
		"inventories": {
			"a": {
				"inventory": [],
				"hotbar": [],
				"selected_hotbar_index": 0,
			},
		},
		"containers": [],
		"mounts": [],
		"open_containers": {},
		"checksum": "%064d" % revision,
	}


func _placement_snapshot(revision: int = 1) -> Dictionary:
	var value := _snapshot(revision)
	value["items"] = [{
		"item_id": "item/base",
		"definition_id": "item/mount-base",
		"quantity": 1,
		"location": {"kind": "INVENTORY", "player_id": "a"},
		"mounted": false,
	}]
	value["inventories"]["a"]["inventory"] = ["item/base"]
	value["inventories"]["a"]["hotbar"] = ["item/base"]
	return value


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_node_runtime_prediction()
	await _test_authoritative_placement_dependency()
	await _test_lifecycle_cleanup()
	_test_ref_counted_runtime_falls_back_to_blocking()
	await _test_m7_flow_and_unload_contracts()
	_finish()


func _test_node_runtime_prediction() -> void:
	var runtime := FakeRuntime.new(_snapshot())
	root.add_child(runtime)
	var bridge = Bridge.new()
	var setup: Dictionary = bridge.setup(runtime, "a")
	_assert(bool(setup.get("success", false)), "bridge setup")
	_assert(bool(setup.get("details", {}).get("prediction_enabled", false)), "Node runtime enables prediction")
	_assert(
		int(bridge.get_report().get("rewired_item_graph_consumers", 0)) == 1,
		"existing canonical consumer is rewired to projected bridge signal"
	)
	runtime.connect_raw_probe()

	var result: Dictionary = bridge.submit_item_command(
		"item.pickup",
		{"item_id": "item/ore"},
		"operation/nx6/pickup/1"
	)
	_assert(bool(result.get("success", false)), "predicted submit succeeds")
	_assert(bool(result.get("pending", false)), "predicted submit pending")
	_assert(runtime.sent.size() == 1, "one reliable command sent")
	var replica_value = result.get("replica_snapshot", {})
	var projected: Dictionary = (
		Dictionary(replica_value).get("domain_components", {}).get("item_graph", {})
		if replica_value is Dictionary
		else {}
	)
	_assert(not projected.is_empty(), "predicted replica snapshot exists")
	_assert(
		_first_replica_relation_kind(projected) == "CONTAINER",
		"pickup is visible in the replica immediately"
	)
	_assert(
		int(bridge.get_report().get("prediction", {}).get("pending_count", -1)) == 1,
		"prediction journal contains the pending pickup"
	)

	var confirmed := _snapshot(2)
	confirmed["items"][0]["location"] = {"kind": "INVENTORY", "player_id": "a"}
	confirmed["inventories"]["a"]["inventory"].append("item/ore")
	runtime.complete("operation/nx6/pickup/1", true, confirmed)
	var pump = runtime.get_node_or_null("NX6PredictedItemCommandPump")
	_assert(pump != null, "prediction pump is attached only to the compatible Node runtime")
	if pump != null:
		pump._process(0.0)
	_assert(int(bridge.get_report().get("accepted", 0)) == 1, "completion accepted")
	_assert(
		int(bridge.get_report().get("prediction", {}).get("pending_count", -1)) == 0,
		"completion clears pending prediction"
	)
	_assert(runtime.raw_runtime_updates == 1, "bridge does not recursively emit runtime item_graph_updated")
	_assert(runtime.consumer_updates >= 1, "rewired consumer receives projected updates")

	var rejected: Dictionary = bridge.submit_item_command(
		"item.drop",
		{"item_id": "item/ore", "quantity": 1},
		"operation/nx6/drop/1"
	)
	_assert(bool(rejected.get("success", false)), "drop predicted")
	runtime.complete("operation/nx6/drop/1", false)
	if pump != null:
		pump._process(0.0)
	_assert(int(bridge.get_report().get("rejected", 0)) == 1, "rejection counted")
	_assert(
		int(bridge.get_report().get("prediction", {}).get("rolled_back", 0)) == 1,
		"rejection rolls prediction back"
	)
	_assert(runtime.raw_runtime_updates == 1, "rollback uses bridge signal, not recursive runtime emission")
	var stopped: Dictionary = bridge.stop("NX6_TEST_COMPLETE")
	_assert(bool(stopped.get("success", false)), "bridge stops after completed prediction flow")
	runtime.queue_free()
	await process_frame


func _test_authoritative_placement_dependency() -> void:
	var runtime := FakeRuntime.new(_placement_snapshot())
	root.add_child(runtime)
	var selected := SelectedProvider.new("item/base")
	var bridge = Bridge.new()
	var setup: Dictionary = bridge.setup(
		runtime, "a", Callable(selected, "get_selected_item_id")
	)
	_assert(bool(setup.get("success", false)), "placement bridge setup")
	var submission: Dictionary = bridge.submit_item_command(
		"item.place",
		{"transform": {"origin": [2.0, 0.0, 3.0]}},
		"operation/nx6/place/authoritative/1"
	)
	_assert(bool(submission.get("success", false)), "placement prediction succeeds")
	_assert(bool(submission.get("pending", false)), "placement remains explicitly pending")
	var projected_value = submission.get("replica_snapshot", {})
	_assert(projected_value is Dictionary, "placement ghost replica returned immediately")
	var projected_canonical: Dictionary = bridge.project_canonical_snapshot(runtime.get_item_graph_snapshot())
	_assert(
		_latest_mount_id(projected_canonical).begins_with("mount/predicted/"),
		"placement ghost uses presentation-only mount identity"
	)
	var confirmed := _placement_snapshot(2)
	confirmed["items"][0]["location"] = {"kind": "WORLD"}
	confirmed["items"][0]["mount_id"] = "fixture/item/player/a/base-1"
	confirmed["inventories"]["a"]["inventory"] = []
	confirmed["inventories"]["a"]["hotbar"] = []
	confirmed["mounts"] = [{
		"mount_id": "fixture/item/player/a/base-1",
		"item_id": "",
		"parent_item_id": "item/base",
		"socket_id": "beacon_socket",
	}]
	runtime.call_deferred(
		"complete", "operation/nx6/place/authoritative/1", true, confirmed
	)
	var completion: Dictionary = await bridge.wait_for_authoritative_completion(
		"operation/nx6/place/authoritative/1", 2000
	)
	_assert(bool(completion.get("success", false)), "placement authoritative completion succeeds")
	_assert(not bool(completion.get("pending", true)), "placement completion is no longer pending")
	_assert(
		_latest_mount_id(runtime.get_item_graph_snapshot()) == "fixture/item/player/a/base-1",
		"dependent flow reads the server-generated mount identity"
	)
	_assert(
		not _latest_mount_id(runtime.get_item_graph_snapshot()).begins_with("mount/predicted/"),
		"predicted mount identity never becomes canonical authority identity"
	)
	var taken: Dictionary = bridge.take_authoritative_completion(
		"operation/nx6/place/authoritative/1"
	)
	_assert(bool(taken.get("success", false)), "authoritative completion can be consumed by operation id")
	var missing: Dictionary = bridge.poll_authoritative_completion(
		"operation/nx6/place/authoritative/1"
	)
	_assert(
		String(missing.get("error_code", "")) == "NX6_AUTHORITATIVE_OPERATION_NOT_FOUND",
		"consumed authoritative completion is removed from the bounded mailbox"
	)
	bridge.stop("NX6_TEST_COMPLETE")
	runtime.queue_free()
	await process_frame


func _test_lifecycle_cleanup() -> void:
	var runtime := FakeRuntime.new(_snapshot())
	root.add_child(runtime)
	var bridge = Bridge.new()
	var setup: Dictionary = bridge.setup(runtime, "a")
	_assert(bool(setup.get("success", false)), "lifecycle bridge setup")
	var submission: Dictionary = bridge.submit_item_command(
		"item.pickup", {"item_id": "item/ore"}, "operation/nx6/lifecycle/1"
	)
	_assert(bool(submission.get("pending", false)), "lifecycle test leaves a pending prediction")
	_assert(runtime._awaited_command_ids.size() == 1, "runtime mailbox contains pending operation")
	var stopped: Dictionary = bridge.stop("NX6_TEST_UNLOAD")
	_assert(bool(stopped.get("success", false)), "bridge lifecycle stop succeeds")
	_assert(int(bridge.get_report().get("prediction", {}).get("pending_count", -1)) == 0, "stop rolls back every pending prediction")
	_assert(runtime._awaited_command_ids.is_empty(), "stop removes pending operation from runtime mailbox")
	_assert(runtime._command_results.is_empty(), "stop removes buffered results for cancelled operations")
	_assert(runtime.get_node_or_null("NX6PredictedItemCommandPump") == null or runtime.get_node_or_null("NX6PredictedItemCommandPump").is_queued_for_deletion(), "stop releases the prediction pump")
	var consumer := Callable(runtime, "_on_consumer_update")
	_assert(runtime.item_graph_updated.is_connected(consumer), "stop restores canonical item graph consumer")
	_assert(not bridge.projected_item_graph_updated.is_connected(consumer), "stop disconnects restored consumer from bridge projection")
	var completion: Dictionary = bridge.take_authoritative_completion("operation/nx6/lifecycle/1")
	_assert(not bool(completion.get("success", true)), "stop publishes authoritative cancellation completion")
	_assert(String(completion.get("error_code", "")) == "NX6_TEST_UNLOAD", "stop completion preserves lifecycle error code")
	var second: Dictionary = bridge.stop("NX6_TEST_UNLOAD")
	_assert(bool(second.get("details", {}).get("already_stopped", false)), "bridge stop is idempotent")
	var consumer_updates_before := runtime.consumer_updates
	runtime.item_graph_updated.emit(runtime.get_item_graph_snapshot())
	_assert(runtime.consumer_updates == consumer_updates_before + 1, "restored consumer receives exactly one canonical update")
	runtime.queue_free()
	await process_frame


func _test_ref_counted_runtime_falls_back_to_blocking() -> void:
	var runtime := ServiceBackedClient.new(_snapshot())
	var bridge = Bridge.new()
	var setup: Dictionary = bridge.setup(runtime, "a")
	_assert(bool(setup.get("success", false)), "RefCounted service-backed client configures")
	_assert(
		not bool(setup.get("details", {}).get("prediction_enabled", true)),
		"RefCounted service-backed client keeps blocking authority path"
	)
	var result: Dictionary = bridge.submit_item_command(
		"item.pickup",
		{"item_id": "item/ore"},
		"operation/nx6/service/pickup/1"
	)
	_assert(not bool(result.get("success", true)), "blocking server rejection is preserved")
	_assert(String(result.get("error_code", "")) == "ITEM_ALREADY_CLAIMED", "blocking error code is preserved")
	_assert(runtime.blocking_calls == 1, "service-backed runtime executes exactly one blocking command")
	_assert(not bool(bridge.get_report().get("prediction_enabled", true)), "bridge report exposes prediction fallback")


func _test_m7_flow_and_unload_contracts() -> void:
	var client_path := "res://tools/runtime/m7_playable_network_client.gd"
	var scene_path := "res://scenes/testing/playground.tscn"
	var production_path := "res://scripts/world/testing/playground_runtime.gd"
	_assert(FileAccess.file_exists(client_path), "M7 process client is included in fix3")
	_assert(FileAccess.file_exists(scene_path), "real playground scene exists")
	_assert(FileAccess.file_exists(production_path), "production playground runtime exists")
	var client_source := FileAccess.get_file_as_string(client_path)
	_assert(
		client_source.contains('const PlaygroundScene = preload("res://scenes/testing/playground.tscn")'),
		"M7 process flow preloads the real playground scene"
	)
	_assert(
		client_source.contains("playground = PlaygroundScene.instantiate()"),
		"M7 process flow instantiates the real playground scene"
	)
	_assert(
		not client_source.contains("nx6_lifecycle_safe_playground_runtime"),
		"M7 process flow no longer uses the test-only lifecycle wrapper"
	)
	var place_wait := client_source.find(
		"var place: Dictionary = await _await_item_authority(place_submission)"
	)
	var mount_read := client_source.find(
		"var mount_id := _latest_fixture_mount(client.get_item_graph_snapshot())"
	)
	_assert(place_wait >= 0 and mount_read > place_wait, "M7 flow waits for placement authority before reading mount id")
	var complete_start := client_source.find("func _complete(details: Dictionary) -> void:")
	var stop_call := client_source.find("\t_stop_item_bridge()", complete_start)
	var client_stop := client_source.find("\tif client != null:", complete_start)
	_assert(stop_call > complete_start and client_stop > stop_call, "M7 completion stops bridge before client runtime")

	var production_source := FileAccess.get_file_as_string(production_path)
	var unload_start := production_source.find("func prepare_for_unload() -> void:")
	var production_stop := production_source.find(
		'_m7_item_bridge.stop("NX6_PLAYGROUND_UNLOAD")', unload_start
	)
	var runtime_disconnect := production_source.find(
		"if m3_multiplayer_client_runtime != null:", unload_start
	)
	var bridge_release := production_source.find("_m7_item_bridge = null", unload_start)
	_assert(
		unload_start >= 0 and production_stop > unload_start,
		"production playground unload directly stops the NX6 bridge"
	)
	_assert(
		runtime_disconnect > production_stop and bridge_release > runtime_disconnect,
		"production bridge stop precedes runtime signal disconnect and bridge release"
	)

	var packed = load(scene_path)
	_assert(packed is PackedScene, "real playground.tscn loads as PackedScene")
	if not packed is PackedScene:
		return
	var playground = packed.instantiate()
	_assert(playground != null, "real playground.tscn instantiates")
	if playground == null:
		return
	var script = playground.get_script()
	_assert(
		script != null and String(script.resource_path) == production_path,
		"real playground scene is bound to production playground_runtime.gd"
	)
	var probe := BridgeStopProbe.new()
	playground._m7_item_bridge = probe
	playground.prepare_for_unload()
	_assert(probe.calls == 1, "real playground production unload calls bridge.stop exactly once")
	_assert(probe.reason == "NX6_PLAYGROUND_UNLOAD", "real playground production unload preserves cleanup reason")
	_assert(playground._m7_item_bridge == null, "real playground production unload releases bridge after stop")
	playground.free()


func _latest_mount_id(snapshot: Dictionary) -> String:
	var result := ""
	for mount_value in snapshot.get("mounts", []):
		if mount_value is Dictionary:
			result = String(Dictionary(mount_value).get("mount_id", result))
	return result


func _first_replica_relation_kind(graph_snapshot: Dictionary) -> String:
	var registry_value = graph_snapshot.get("items", {})
	if not registry_value is Dictionary:
		return ""
	var rows_value = Dictionary(registry_value).get("items", [])
	var rows: Array = []
	if rows_value is Array:
		rows = Array(rows_value)
	elif rows_value is Dictionary:
		rows = Dictionary(rows_value).values()
	for row_value in rows:
		if not row_value is Dictionary:
			continue
		var relation_value = Dictionary(row_value).get("relation", {})
		if relation_value is Dictionary:
			return String(Dictionary(relation_value).get("kind", ""))
	return ""


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("NX6 predicted item integration: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print(
		"NX6 predicted item integration: FAIL (%d assertions, %d failures)"
		% [assertions, failures.size()]
	)
	quit(1)
