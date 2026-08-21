extends Node

signal finished(exit_code: int)

const Contract = preload("res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_contract.gd")
const Authority = preload("res://scripts/runtime/host_client/multiplayer_gameplay_authority.gd")

const INNER_AUTHORITY_EPOCH := 1
const LOCAL_MOVE_INTERVAL_MS := 50
const VIEW_INTERVAL_MS := 50
const STOP_POLL_INTERVAL_MS := 100
const LOCAL_STEP_X := 0.025
const LOCAL_STEP_Z := 0.010

var _anchor_host := "127.0.0.1"
var _anchor_port := 0
var _view_host := "127.0.0.1"
var _view_port := 0
var _stop_file := ""
var _auto_local_motion := true
var _anchor_socket: PacketPeerUDP
var _view_socket: PacketPeerUDP
var _authority
var _session_id := "transport-session/sm0/p8/ship-01/a"
var _anchor: Dictionary = {}
var _last_move_ms := 0
var _last_view_ms := 0
var _last_stop_poll_ms := 0
var _view_sequence := 0
var _owner_change_count := 0
var _anchor_accept_count := 0
var _anchor_reject_count := 0

func setup(config: Dictionary) -> Dictionary:
	_anchor_host = String(config.get("anchor_host", "127.0.0.1")).strip_edges()
	_anchor_port = int(config.get("anchor_port", 0))
	_view_host = String(config.get("view_host", "127.0.0.1")).strip_edges()
	_view_port = int(config.get("view_port", 0))
	_stop_file = String(config.get("stop_file", "")).strip_edges()
	_auto_local_motion = bool(config.get("auto_local_motion", true))
	if _anchor_host.is_empty() or _anchor_port < 1: return _failure("SM0_P8_NESTED_CONFIGURATION_INVALID")
	_authority = Authority.new()
	var authority_setup: Dictionary = _authority.setup(Contract.ISLAND_AUTHORITY_ID, INNER_AUTHORITY_EPOCH, 0)
	if not bool(authority_setup.get("success", false)): return _failure("SM0_P8_NESTED_AUTHORITY_SETUP_FAILED", {"cause":authority_setup})
	var join: Dictionary = _authority.join(Contract.LOGICAL_PLAYER_ID, _session_id, "operation/sm0/p8/nested/join")
	if not bool(join.get("success", false)): return _failure("SM0_P8_NESTED_PLAYER_JOIN_FAILED", {"cause":join})
	_anchor_socket = PacketPeerUDP.new()
	var bind_result := _anchor_socket.bind(_anchor_port, _anchor_host)
	if bind_result != OK: return _failure("SM0_P8_NESTED_ANCHOR_BIND_FAILED", {"error":bind_result})
	if _view_port > 0: _view_socket = PacketPeerUDP.new()
	set_process(true)
	var player: Dictionary = _authority.get_player(Contract.LOGICAL_PLAYER_ID)
	_event("SM0_P8_NESTED_READY", {"island_id":Contract.ISLAND_ID,"island_entity_id":Contract.ISLAND_ENTITY_ID,"island_authority_id":Contract.ISLAND_AUTHORITY_ID,"inner_authority_epoch":INNER_AUTHORITY_EPOCH,"player_entity_id":String(player.get("player_entity_id","")),"anchor_port":_anchor_port,"view_port":_view_port,"command_channel":false})
	return _success()

func _process(_delta: float) -> void:
	_poll_anchor_socket()
	var now := Time.get_ticks_msec()
	if _auto_local_motion and now - _last_move_ms >= LOCAL_MOVE_INTERVAL_MS:
		_last_move_ms = now; move_inner_for_tests(LOCAL_STEP_X, LOCAL_STEP_Z)
	if now - _last_view_ms >= VIEW_INTERVAL_MS:
		_last_view_ms = now; _publish_view()
	if not _stop_file.is_empty() and now - _last_stop_poll_ms >= STOP_POLL_INTERVAL_MS:
		_last_stop_poll_ms = now
		if FileAccess.file_exists(_stop_file): shutdown(0,"stop-file")

func move_inner_for_tests(delta_x: float = LOCAL_STEP_X, delta_z: float = LOCAL_STEP_Z) -> Dictionary:
	var current: Dictionary = _authority.get_player(Contract.LOGICAL_PLAYER_ID) if _authority != null else {}
	if current.is_empty(): return _failure("SM0_P8_NESTED_PLAYER_MISSING")
	var next_sequence := int(current.get("last_input_sequence",0)) + 1
	var result: Dictionary = _authority.move_player(Contract.LOGICAL_PLAYER_ID, _session_id, int(current.get("ownership_epoch",INNER_AUTHORITY_EPOCH)), next_sequence, delta_x, delta_z, "operation/sm0/p8/nested/move/%d" % next_sequence)
	if not bool(result.get("success",false)): return _failure("SM0_P8_NESTED_MOVE_FAILED", {"cause":result})
	var player := Dictionary(result.get("details",{}).get("player",{}))
	_event("SM0_P8_NESTED_PLAYER_MOVED", {"player_entity_id":String(player.get("player_entity_id","")),"input_sequence":int(player.get("last_input_sequence",0)),"local_position":player.get("position",{}),"inner_authority_epoch":INNER_AUTHORITY_EPOCH})
	_publish_view()
	return _success({"player":player})

func accept_anchor_for_tests(anchor: Dictionary) -> Dictionary:
	return _accept_anchor(anchor)

func _poll_anchor_socket() -> void:
	if _anchor_socket == null: return
	while _anchor_socket.get_available_packet_count() > 0:
		var decoded = JSON.parse_string(_anchor_socket.get_packet().get_string_from_utf8())
		if not decoded is Dictionary:
			_reject_anchor("SM0_P8_ANCHOR_JSON_INVALID", {}); continue
		_accept_anchor(Dictionary(decoded))

func _accept_anchor(anchor: Dictionary) -> Dictionary:
	var validation := Contract.validate_anchor(anchor)
	if not bool(validation.get("success",false)): return _reject_anchor(String(validation.get("error_code","SM0_P8_ANCHOR_INVALID")),anchor)
	if not _anchor.is_empty():
		var current_epoch := int(_anchor.get("outer_authority_epoch",0)); var incoming_epoch := int(anchor.get("outer_authority_epoch",0))
		var current_tick := int(_anchor.get("simulation_tick",0)); var incoming_tick := int(anchor.get("simulation_tick",0))
		if incoming_epoch < current_epoch or (incoming_epoch == current_epoch and incoming_tick < current_tick): return _reject_anchor("SM0_P8_ANCHOR_STALE",anchor)
		if incoming_epoch == current_epoch and incoming_tick == current_tick:
			if String(anchor.get("checksum","")) != String(_anchor.get("checksum","")): return _reject_anchor("SM0_P8_ANCHOR_SAME_TICK_MUTATION",anchor)
			return _success({"replay":true})
	var previous_owner := String(_anchor.get("outer_owner_authority_id",""))
	_anchor = anchor.duplicate(true); _anchor_accept_count += 1
	var next_owner := String(_anchor.get("outer_owner_authority_id",""))
	if not previous_owner.is_empty() and next_owner != previous_owner:
		_owner_change_count += 1
		var player: Dictionary = _authority.get_player(Contract.LOGICAL_PLAYER_ID)
		_event("SM0_P8_OUTER_OWNER_CHANGED", {"previous_outer_owner_authority_id":previous_owner,"outer_owner_authority_id":next_owner,"outer_authority_epoch":int(_anchor.get("outer_authority_epoch",0)),"simulation_tick":int(_anchor.get("simulation_tick",0)),"island_authority_id":Contract.ISLAND_AUTHORITY_ID,"inner_authority_epoch":INNER_AUTHORITY_EPOCH,"player_entity_id":String(player.get("player_entity_id",""))})
	_event("SM0_P8_ANCHOR_ACCEPTED", {"outer_owner_authority_id":next_owner,"outer_authority_epoch":int(_anchor.get("outer_authority_epoch",0)),"simulation_tick":int(_anchor.get("simulation_tick",0)),"linear_velocity":_anchor.get("linear_velocity",{}),"angular_velocity_yaw":float(_anchor.get("angular_velocity_yaw",0.0)),"inner_authority_epoch":INNER_AUTHORITY_EPOCH})
	_publish_view()
	return _success({"replay":false})

func _publish_view() -> void:
	if _anchor.is_empty() or _authority == null: return
	var player: Dictionary = _authority.get_player(Contract.LOGICAL_PLAYER_ID)
	if player.is_empty(): return
	_view_sequence += 1
	var view := Contract.create_view(_view_sequence,_anchor,INNER_AUTHORITY_EPOCH,player)
	var check := Contract.validate_view(view)
	if not bool(check.get("success",false)):
		_event("SM0_P8_VIEW_BUILD_REJECTED", {"error_code":String(check.get("error_code","SM0_P8_VIEW_INVALID"))}); return
	if _view_socket != null and _view_port > 0:
		if _view_socket.set_dest_address(_view_host,_view_port) == OK: _view_socket.put_packet(JSON.stringify(view,"",false,true).to_utf8_buffer())
	_event("SM0_P8_NESTED_FRAME", {"view_sequence":_view_sequence,"outer_owner_authority_id":String(_anchor.get("outer_owner_authority_id","")),"outer_authority_epoch":int(_anchor.get("outer_authority_epoch",0)),"ship_simulation_tick":int(_anchor.get("simulation_tick",0)),"ship_world_position":_anchor.get("world_position",{}),"ship_linear_velocity":_anchor.get("linear_velocity",{}),"player_entity_id":String(player.get("player_entity_id","")),"player_input_sequence":int(player.get("last_input_sequence",0)),"player_local_position":player.get("position",{}),"player_world_position":view.get("player_world_position",{}),"inner_authority_epoch":INNER_AUTHORITY_EPOCH})

func status_for_tests() -> Dictionary:
	var player: Dictionary = _authority.get_player(Contract.LOGICAL_PLAYER_ID) if _authority != null else {}
	return {"island_id":Contract.ISLAND_ID,"island_entity_id":Contract.ISLAND_ENTITY_ID,"island_authority_id":Contract.ISLAND_AUTHORITY_ID,"inner_authority_epoch":INNER_AUTHORITY_EPOCH,"writer_count":1 if not player.is_empty() and bool(player.get("connected",false)) else 0,"authority_scope":"inner/island/ship/01/player","player":player,"anchor":_anchor.duplicate(true),"owner_change_count":_owner_change_count,"anchor_accept_count":_anchor_accept_count,"anchor_reject_count":_anchor_reject_count,"view_sequence":_view_sequence}

func shutdown(exit_code: int, reason: String) -> void:
	_event("SM0_P8_NESTED_EXIT", {"exit_code":exit_code,"reason":reason,"inner_authority_epoch":INNER_AUTHORITY_EPOCH})
	if _anchor_socket != null: _anchor_socket.close()
	if _view_socket != null: _view_socket.close()
	set_process(false); finished.emit(exit_code)

func _reject_anchor(error_code: String, anchor: Dictionary) -> Dictionary:
	_anchor_reject_count += 1
	_event("SM0_P8_ANCHOR_REJECTED", {"error_code":error_code,"outer_owner_authority_id":String(anchor.get("outer_owner_authority_id","")),"outer_authority_epoch":int(anchor.get("outer_authority_epoch",0)),"simulation_tick":int(anchor.get("simulation_tick",0))})
	return _failure(error_code)

func _event(event_name: String, details: Dictionary = {}) -> void:
	var event := {"schema":"distributed_world_simulator.sm0_event.v1","event":event_name,"severity":"INFO","process_role":"p8-nested-ship-01","process_id":OS.get_process_id(),"time_msec":Time.get_ticks_msec(),"authority_id":Contract.ISLAND_AUTHORITY_ID,"writer_count":1 if _authority != null and not _authority.get_player(Contract.LOGICAL_PLAYER_ID).is_empty() else 0,"authority_scope":"inner/island/ship/01/player"}
	for key in details.keys(): event[key]=details[key]
	print("[SM0_EVENT] %s" % JSON.stringify(event,"",false,true))
static func _success(details: Dictionary = {}) -> Dictionary: return {"success":true,"error_code":"","details":details.duplicate(true)}
static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary: return {"success":false,"error_code":error_code,"details":details.duplicate(true)}