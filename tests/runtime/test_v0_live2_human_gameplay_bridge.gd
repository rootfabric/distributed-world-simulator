extends SceneTree

const LiveEarth = preload("res://scripts/app/earth_p3_resource_mining_app.gd")

class FakeRuntime:
	extends RefCounted
	var commands: Array[Dictionary] = []
	func get_local_player_id() -> String:
		return "a"
	func execute_item_command_blocking(
		command_type: String,
		payload: Dictionary,
		operation_id: String = ""
	) -> Dictionary:
		commands.append({
			"type": command_type,
			"payload": payload.duplicate(true),
			"operation_id": operation_id,
		})
		return {
			"success": true,
			"error_code": "",
			"details": {
				"command_type": command_type,
				"payload": payload.duplicate(true),
			},
		}

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_canonical_human_actions()
	_finish()


func _test_canonical_human_actions() -> void:
	var earth = LiveEarth.new()
	var runtime = FakeRuntime.new()
	earth.m3_multiplayer_client_runtime = runtime
	earth._m3_attached = true
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
				"hotbar": ["item/player/a/mount-bases", "", "", "", "", "", "", "", "", ""],
				"selected_hotbar_index": 0,
			},
		},
	}

	var equipped: Dictionary = earth.ensure_live2_mining_tool_equipped()
	_assert(bool(equipped.get("success", false)), "human mining equip succeeds through runtime")
	_assert(runtime.commands.size() == 1, "equip sends exactly one canonical command")
	_assert(String(runtime.commands[0].get("type", "")) == "item.equip", "mining path uses item.equip")
	_assert(
		String(runtime.commands[0].get("payload", {}).get("item_id", ""))
		== "item/player/a/p5-mining-tool",
		"mining path uses the canonical seeded tool identity"
	)
	_assert(
		String(runtime.commands[0].get("payload", {}).get("slot_id", ""))
		== "tool/main",
		"mining tool uses canonical tool/main equipment slot"
	)

	var build_mode: Dictionary = earth._command_live2_build_mode_toggle([])
	_assert(bool(build_mode.get("success", false)), "build mode toggles on")
	_assert(bool(build_mode.get("build_mode", false)), "build mode state is explicit")
	var placed: Dictionary = earth._command_live2_primary([])
	_assert(bool(placed.get("success", false)), "primary action places selected base in build mode")
	_assert(runtime.commands.size() == 2, "placement adds exactly one canonical command")
	_assert(String(runtime.commands[1].get("type", "")) == "item.place", "build mode uses canonical item.place")
	_assert(
		String(runtime.commands[1].get("payload", {}).get("item_id", ""))
		== "item/player/a/mount-bases",
		"build mode places the selected canonical mount-base identity"
	)

	earth.set_network_connection_status("RECONNECTING", {"attempt": 2})
	_assert(earth._live2_connection_state == "RECONNECTING", "connection HUD consumes reconnect state")
	_assert(earth._live2_connection_label != null, "connection HUD is created")
	_assert(
		earth._live2_connection_label.text.contains("попытка 2"),
		"connection HUD exposes reconnect attempt"
	)

	earth.free()


func _assert(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("V0-LIVE.2 human gameplay bridge: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("V0-LIVE.2 human gameplay bridge: FAIL (%d failures, %d assertions)" % failures.size())
	quit(1)
