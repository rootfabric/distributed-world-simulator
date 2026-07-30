extends SceneTree

const Client = preload("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd")

var _client
var _result_file := ""
var _peer_file := ""
var _client_id := "a"
var _phase := 1
var _started := 0
var _done := false

func _init() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	_result_file = String(args.get("result-file", ""))
	_peer_file = String(args.get("peer-file", ""))
	_client_id = String(args.get("client-id", "a"))
	_phase = int(args.get("phase", "1"))
	_client = Client.new()
	root.add_child(_client)
	var setup: Dictionary = _client.setup({
		"host": String(args.get("host", "127.0.0.1")),
		"port": int(args.get("port", "0")),
		"logical_player_id": _client_id,
		"connect_timeout_ms": 30000,
		"command_timeout_ms": 10000,
		"automated_acceptance": true,
	})
	if not bool(setup.get("success", false)):
		_finish(false, "SETUP_FAILED", {"setup": setup})
		return
	_started = Time.get_ticks_msec()
	process_frame.connect(_tick)

func _tick() -> void:
	if _done: return
	if Time.get_ticks_msec() - _started > 90000:
		_finish(false, "TIMEOUT", {})
		return
	if not _client.is_ready(): return
	match _phase:
		1: _phase_a()
		2: _phase_b()
		3: _phase_replay()

func _phase_a() -> void:
	var op := "operation/m4/contention/shared"
	var pickup: Dictionary = _client.execute_item_command_blocking("item.pickup", {"item_id":"item/shared/beacon/1"}, op)
	_write({"state":"A_PICKUP_DONE","passed":true,"pickup":pickup,"snapshot":_client.get_item_graph_snapshot(),"client":_client.get_report()})
	_wait_for_peer("B_PICKUP_DONE")
	var split_pick: Dictionary = _client.execute_item_command_blocking("item.pickup", {"item_id":"item/shared/ore/1"})
	var split: Dictionary = _client.execute_item_command_blocking("item.split", {"item_id":"item/shared/ore/1","quantity":3})
	var split_id := String(split.get("details", {}).get("result", {}).get("details", {}).get("item_id", ""))
	var stack: Dictionary = _client.execute_item_command_blocking("item.stack", {"source_item_id":split_id,"target_item_id":"item/shared/ore/1"})
	var drop: Dictionary = _client.execute_item_command_blocking("item.drop", {"item_id":"item/shared/ore/1","quantity":2})
	var dropped_id := String(drop.get("details", {}).get("result", {}).get("details", {}).get("item_id", ""))
	var repick: Dictionary = _client.execute_item_command_blocking("item.pickup", {"item_id":dropped_id})
	var hotbar: Dictionary = _client.execute_item_command_blocking("inventory.select_hotbar", {"selected_hotbar_index":2})
	var mount: Dictionary = _client.execute_item_command_blocking("item.mount", {"item_id":"item/shared/beacon/1","mount_id":"mount/shared/socket/1"})
	var detach: Dictionary = _client.execute_item_command_blocking("item.detach", {"mount_id":"mount/shared/socket/1"})
	var open: Dictionary = _client.execute_item_command_blocking("container.open", {"container_id":"container/shared/crate/1"})
	var move: Dictionary = _client.execute_item_command_blocking("item.move_to_container", {"item_id":"item/shared/beacon/1","container_id":"container/shared/crate/1"})
	var close: Dictionary = _client.execute_item_command_blocking("container.close", {"container_id":"container/shared/crate/1"})
	_wait_item_revision(12)
	_finish(true, "COMPLETE", {"pickup":pickup,"split_pick":split_pick,"split":split,"stack":stack,"drop":drop,"repick":repick,"hotbar":hotbar,"mount":mount,"detach":detach,"open":open,"move":move,"close":close})

func _phase_b() -> void:
	var op := "operation/m4/contention/b"
	var pickup: Dictionary = _client.execute_item_command_blocking("item.pickup", {"item_id":"item/shared/beacon/1"}, op)
	_write({"state":"B_PICKUP_DONE","passed":not bool(pickup.get("success", false)),"pickup":pickup,"snapshot":_client.get_item_graph_snapshot(),"client":_client.get_report()})
	_wait_for_peer("A_PICKUP_DONE")
	var permission: Dictionary = _client.execute_item_command_blocking("inventory.permission_probe", {"target_player_id":"a"})
	_wait_item_revision(12)
	_finish(not bool(permission.get("success", false)), "COMPLETE", {"pickup":pickup,"permission":permission})

func _phase_replay() -> void:
	var op := "operation/m4/replay/%d" % OS.get_process_id()
	var first: Dictionary = _client.execute_item_command_blocking("inventory.select_hotbar", {"selected_hotbar_index":1}, op)
	var replay: Dictionary = _client.execute_item_command_blocking("inventory.select_hotbar", {"selected_hotbar_index":1}, op)
	var conflict: Dictionary = _client.execute_item_command_blocking("inventory.select_hotbar", {"selected_hotbar_index":3}, op)
	_finish(bool(first.get("success",false)) and bool(replay.get("success",false)) and not bool(conflict.get("success",true)), "COMPLETE", {"first":first,"replay":replay,"conflict":conflict})


func _wait_item_revision(revision: int) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 20000:
		_client._poll_blocking_once()
		if int(_client.get_item_graph_snapshot().get("revision", 0)) >= revision:
			return
		OS.delay_msec(5)

func _wait_for_peer(state: String) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 15000:
		var peer := _read(_peer_file)
		if String(peer.get("state", "")) == state: return
		OS.delay_msec(10)

func _finish(passed: bool, state: String, details: Dictionary) -> void:
	if _done: return
	_done = true
	var report := {"schema":"planet_simulator.m4_graphical_item_client_report.v1","state":state,"passed":passed,"client_id":_client_id,"phase":_phase,"display_server":DisplayServer.get_name(),"item_graph":_client.get_item_graph_snapshot() if _client != null else {},"client":_client.get_report() if _client != null else {},"details":details}
	_write(report)
	if _client != null:
		_client.request_graceful_leave(2000)
		_client.stop()
	quit(0 if passed else 1)

func _write(value: Dictionary) -> void:
	if _result_file.is_empty(): return
	DirAccess.make_dir_recursive_absolute(_result_file.get_base_dir())
	var file := FileAccess.open(_result_file, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(value, "  ")); file.close()
func _read(path:String)->Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path): return {}
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path)); return Dictionary(parsed) if parsed is Dictionary else {}
func _parse_args(values: PackedStringArray)->Dictionary:
	var out:Dictionary={}
	for value in values:
		var text:=String(value)
		if text.begins_with("--") and text.contains("="):
			var parts:=text.substr(2).split("=",true,1); out[parts[0]]=parts[1]
	return out
