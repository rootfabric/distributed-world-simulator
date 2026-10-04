extends SceneTree

const LiveEarth = preload("res://scripts/app/earth_p3_resource_mining_app.gd")
const OutpostAdapter = preload("res://scripts/runtime/networked_gameplay/m3/m3_mvp_outpost_client_adapter.gd")
const LiveClient = preload("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd")

class FakeGameplayRuntime:
	extends RefCounted
	signal command_result_received(result: Dictionary)

	var item_async_calls: Array[Dictionary] = []
	var resource_async_calls: Array[Dictionary] = []
	var blocking_calls := 0
	var _next_operation := 0

	func get_local_player_id() -> String:
		return "a"

	func execute_item_command_async(
		command_type: String,
		payload: Dictionary,
		operation_id: String = ""
	) -> Dictionary:
		_next_operation += 1
		var op := operation_id if not operation_id.is_empty() else "operation/fake/item/%d" % _next_operation
		item_async_calls.append({
			"operation_id": op,
			"command_type": command_type,
			"payload": payload.duplicate(true),
		})
		return {
			"success": true,
			"error_code": "",
			"details": {"operation_id": op, "pending": true},
		}

	func execute_item_command_blocking(
		_command_type: String,
		_payload: Dictionary,
		_operation_id: String = ""
	) -> Dictionary:
		blocking_calls += 1
		return {"success": false, "error_code": "BLOCKING_PATH_FORBIDDEN", "details": {}}

	func execute_resource_mine_async(
		resource_node_id: String,
		requested_units: int = 1,
		operation_id: String = ""
	) -> Dictionary:
		_next_operation += 1
		var op := operation_id if not operation_id.is_empty() else "operation/fake/mine/%d" % _next_operation
		resource_async_calls.append({
			"operation_id": op,
			"resource_node_id": resource_node_id,
			"requested_units": requested_units,
		})
		return {
			"success": true,
			"error_code": "",
			"details": {"operation_id": op, "pending": true},
		}


class FakeConstructionRuntime:
	extends RefCounted
	signal command_result_received(result: Dictionary)

	var async_calls: Array[Dictionary] = []
	var blocking_calls := 0

	func get_construction_session() -> Dictionary:
		return {
			"client_id": "client/a",
			"session_id": "construction-session/a",
			"session_epoch": 1,
			"next_sequence": 0,
			"permission_epoch": 1,
		}

	func get_construction_bundle() -> Dictionary:
		return {
			"server_generation": 0,
			"constructs": [],
		}

	func execute_construction_command_async(
		command: Dictionary,
		operation_id: String = ""
	) -> Dictionary:
		async_calls.append({
			"operation_id": operation_id,
			"command": command.duplicate(true),
		})
		return {
			"success": true,
			"error_code": "",
			"details": {"operation_id": operation_id, "pending": true},
		}

	func execute_construction_command_blocking(
		_command: Dictionary,
		_operation_id: String = ""
	) -> Dictionary:
		blocking_calls += 1
		return {"success": false, "error_code": "BLOCKING_PATH_FORBIDDEN", "details": {}}


var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_runtime_surface()
	_test_earth_place_and_mining_are_async()
	_test_construction_is_async()
	_finish()


func _test_runtime_surface() -> void:
	var runtime = LiveClient.new()
	_assert(runtime.has_signal("command_result_received"), "runtime exposes async command result signal")
	_assert(runtime.has_method("execute_item_command_async"), "runtime exposes async Item Graph command")
	_assert(runtime.has_method("execute_resource_mine_async"), "runtime exposes async ResourceMining command")
	_assert(runtime.has_method("execute_construction_command_async"), "runtime exposes async Construction command")
	_assert(runtime.has_method("execute_item_command_blocking"), "blocking Item Graph compatibility seam remains")
	_assert(runtime.has_method("execute_resource_mine_blocking"), "blocking ResourceMining compatibility seam remains")
	_assert(runtime.has_method("execute_construction_command_blocking"), "blocking Construction compatibility seam remains")
	runtime.free()


func _test_earth_place_and_mining_are_async() -> void:
	var earth = LiveEarth.new()
	var runtime = FakeGameplayRuntime.new()
	earth.m3_multiplayer_client_runtime = runtime
	earth._m3_attached = true
	runtime.command_result_received.connect(earth._on_live2_async_command_result)
	earth._m4_item_graph_snapshot = {
		"items": [
			{
				"item_id": "item/player/a/p5-mining-tool",
				"definition_id": "item/tool/mining",
				"quantity": 1,
				"location": {"kind": "INVENTORY", "player_id": "a"},
				"mounted": false,
			},
			{
				"item_id": "item/player/a/mount-bases",
				"definition_id": "item/mount-base",
				"quantity": 3,
				"location": {"kind": "INVENTORY", "player_id": "a"},
				"mounted": false,
			},
		],
		"inventories": {
			"a": {
				"inventory": [
					"item/player/a/p5-mining-tool",
					"item/player/a/mount-bases",
				],
				"hotbar": ["item/player/a/mount-bases", "", "", "", "", "", "", ""],
				"selected_hotbar_index": 0,
			},
		},
	}

	earth._command_live2_build_mode_toggle([])
	var placed: Dictionary = earth._command_live2_primary([])
	_assert(bool(placed.get("success", false)), "placement send succeeds")
	_assert(bool(placed.get("pending", false)), "placement returns immediately as pending")
	_assert(runtime.item_async_calls.size() == 1, "placement sends one async item command")
	_assert(runtime.blocking_calls == 0, "placement never enters blocking item API")
	_assert(String(runtime.item_async_calls[0].get("command_type", "")) == "item.place", "placement keeps canonical item.place")
	var place_op := String(runtime.item_async_calls[0].get("operation_id", ""))
	_assert(earth._live2_pending_actions.has(place_op), "placement is tracked until server result")

	runtime.command_result_received.emit({
		"type": "COMMAND_RESULT",
		"operation_id": place_op,
		"command_type": "item.place",
		"status": "SUCCEEDED",
		"error_code": "",
		"details": {},
		"async": true,
	})
	_assert(not earth._live2_pending_actions.has(place_op), "placement pending clears on server ACK")
	_assert(earth._live2_last_action_text == "Основание установлено", "placement success feedback waits for server ACK")

	var mining: Dictionary = earth._mine_p3_resource("resource/earth/ore/1")
	_assert(bool(mining.get("success", false)), "mining chain starts")
	_assert(bool(mining.get("pending", false)), "mining returns without blocking")
	_assert(runtime.item_async_calls.size() == 2, "mining first queues async tool equip")
	_assert(runtime.resource_async_calls.is_empty(), "mine waits for equip ACK without blocking")
	_assert(runtime.blocking_calls == 0, "mining auto-equip never uses blocking item API")
	var equip_op := String(runtime.item_async_calls[1].get("operation_id", ""))

	runtime.command_result_received.emit({
		"type": "COMMAND_RESULT",
		"operation_id": equip_op,
		"command_type": "item.equip",
		"status": "SUCCEEDED",
		"error_code": "",
		"details": {},
		"async": true,
	})
	_assert(runtime.resource_async_calls.size() == 1, "equip ACK chains exactly one async mine")
	var mine_op := String(runtime.resource_async_calls[0].get("operation_id", ""))
	_assert(earth._live2_pending_actions.has(mine_op), "resource mine is tracked pending")

	runtime.command_result_received.emit({
		"type": "COMMAND_RESULT",
		"operation_id": mine_op,
		"command_type": "resource.mine",
		"status": "SUCCEEDED",
		"error_code": "",
		"details": {},
		"async": true,
	})
	_assert(not earth._live2_pending_actions.has(mine_op), "resource mine pending clears on ACK")
	_assert(
		earth._live2_last_action_text == "Руда добыта · материал добавлен в инвентарь",
		"mining final feedback is server-result driven"
	)
	earth.free()


func _test_construction_is_async() -> void:
	var runtime = FakeConstructionRuntime.new()
	var adapter = OutpostAdapter.new()
	var completed: Array[Dictionary] = []
	adapter.build_completed.connect(func(result: Dictionary) -> void:
		completed.append(result.duplicate(true))
	)
	var setup: Dictionary = adapter.setup(runtime)
	_assert(bool(setup.get("success", false)), "Construction adapter accepts async runtime")
	var sent: Dictionary = adapter.build_next_stage_async()
	_assert(bool(sent.get("success", false)), "Construction stage send succeeds")
	_assert(bool(sent.get("details", {}).get("pending", false)), "Construction returns immediately pending")
	_assert(runtime.async_calls.size() == 1, "Construction sends exactly one async command")
	_assert(runtime.blocking_calls == 0, "Construction human path never calls blocking API")
	var op := String(runtime.async_calls[0].get("operation_id", ""))
	runtime.command_result_received.emit({
		"type": "COMMAND_RESULT",
		"operation_id": op,
		"command_type": "CONSTRUCTION_COMMAND",
		"status": "SUCCEEDED",
		"error_code": "",
		"details": {},
		"async": true,
	})
	_assert(completed.size() == 1, "Construction completion signal fires once")
	_assert(bool(completed[0].get("success", false)), "Construction ACK is surfaced as success")


func _assert(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("V0-LIVE.2 R3.1 async gameplay: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("V0-LIVE.2 R3.1 async gameplay: FAIL (%d failures, %d assertions)" % [
		failures.size(), assertions
	])
	quit(1)
