extends SceneTree

# Test driver only: every mutation uses the same M3 client commands as product
# gameplay. This script owns no world state and cannot access server objects.
const Runtime = preload("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd")
const Command = preload("res://scripts/construction/multiplayer/construction_multiplayer_command.gd")
const Grant = preload("res://scripts/construction/multiplayer/construction_multiplayer_permission_grant.gd")
const Outpost = preload("res://scripts/construction/mvp/v0_p4_mvp_earth_outpost_authority.gd")
var client
var cfg: Dictionary = {}
var transitions: Array = []
var results: Dictionary = {}
var last_snapshot: Dictionary = {}

func _init() -> void:
	call_deferred("run")

func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func save(phase: String) -> bool:
	if phase != "STOPPED":
		last_snapshot = {
			"runtime": client.get_report(),
			"player": client.get_local_player_record(),
			"players": {"a": client.get_player("a"), "b": client.get_player("b")},
			"items": client.get_item_graph_snapshot(),
			"resources": client.get_resource_mining_snapshot(),
			"construction": client.get_construction_bundle(),
		}
	var report := {
		"schema": "dws.live3.network_probe.v1", "phase": phase,
		"process_id": OS.get_process_id(), "identity": cfg.get("identity", ""),
		"transitions": transitions, "results": results, "snapshot": last_snapshot,
	}
	var file := FileAccess.open(String(cfg["report"]), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(report, "", true, true))
	file.close()
	return true

func run() -> void:
	var raw = JSON.parse_string(OS.get_environment("DWS_LIVE3_PROBE"))
	if not raw is Dictionary:
		quit(2)
		return
	cfg = raw
	client = Runtime.new()
	root.add_child(client)
	client.connection_state_changed.connect(func(state: String, _details: Dictionary):
		transitions.append({"state": state, "time_msec": Time.get_ticks_msec()})
	)
	var configured: Dictionary = client.setup({
		"host": "127.0.0.1", "port": int(cfg["port"]),
		"logical_player_id": String(cfg["identity"]),
		"connect_timeout_ms": 30000, "command_timeout_ms": 15000,
		"automated_acceptance": false, "playable_sandbox": true,
		"world_id": "earth", "debug_logging": true,
	})
	if not bool(configured.get("success", false)):
		printerr(configured)
		quit(3)
		return
	var deadline := Time.get_ticks_msec() + 300000
	while Time.get_ticks_msec() < deadline:
		var request := read_json(String(cfg["control"]))
		var id := String(request.get("id", ""))
		if not id.is_empty() and not results.has(id):
			if request.get("action") == "quit":
				save("STOPPING")
				client.stop()
				results[id] = {"success": true}
				save("STOPPED")
				client.queue_free()
				quit(0)
				return
			results[id] = execute(request)
		if not save("RUNNING"):
			client.stop()
			quit(4)
			return
		await create_timer(0.2).timeout
	client.stop()
	quit(5)

func execute(request: Dictionary) -> Dictionary:
	match String(request.get("action", "")):
		"equip":
			var actor := String(cfg["identity"])
			for item in client.get_item_graph_snapshot().get("items", []):
				if item.get("definition_id") == "item/tool/mining" and item.get("location", {}).get("player_id") == actor:
					return client.execute_item_command_blocking("item.equip", {"item_id": item["item_id"], "slot_id": "tool/main"})
			return {"success": false, "error_code": "PROBE_MINING_TOOL_NOT_FOUND"}
		"mine":
			return client.execute_resource_mine_blocking("resource/earth/ore-demo/1", int(request.get("amount", 1)), String(request["operation_id"]))
		"build":
			var session: Dictionary = client.get_construction_session()
			var bundle: Dictionary = client.get_construction_bundle()
			var checksum := ""
			for construct in bundle.get("constructs", []):
				if construct.get("construct_id") == Outpost.CONSTRUCT_ID:
					checksum = String(construct.get("checksum", ""))
			var command: Dictionary = Command.create(
				"multiplayer-command/live3/" + String(request["id"]),
				String(session.get("client_id", "")), String(session.get("session_id", "")),
				int(session.get("session_epoch", 0)), int(session.get("next_sequence", 0)),
				Grant.ACTION_BUILD, Outpost.CONSTRUCT_ID, checksum,
				int(bundle.get("server_generation", 0)), int(session.get("permission_epoch", 0)),
				{"build_plan_id": Outpost.BUILD_PLAN_ID, "stage_index": int(request["stage"]),
				"operation_id": String(request["operation_id"]), "provided_capabilities": ["FASTEN"], "options": {}}
			)
			return client.execute_construction_command_blocking(command, String(request["operation_id"]))
		"move":
			var result: Dictionary = client.submit_movement_intent_blocking({"move_x": 0.0, "move_z": 1.0, "look_yaw": 0.0, "look_pitch": 0.0, "jump_pressed": false, "sprint": false, "delta_seconds": 0.25})
			if not bool(result.get("success", false)):
				return result
			return client.submit_movement_intent_blocking({"move_x": 0.0, "move_z": 0.0, "look_yaw": 0.0, "look_pitch": 0.0, "jump_pressed": false, "sprint": false, "delta_seconds": 0.05})
	return {"success": false, "error_code": "PROBE_ACTION_UNKNOWN"}
