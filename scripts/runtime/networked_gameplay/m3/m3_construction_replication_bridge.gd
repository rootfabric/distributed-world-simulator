extends RefCounted

# M3 boundary adapter. It owns no construct data: the supplied canonical gateway
# remains the sole writer, while clients receive its verified bundle/event stream.
const CommandScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_command.gd")
const EventScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_event.gd")
const BundleScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_state_bundle.gd")

const SNAPSHOT_TYPE := "CONSTRUCTION_SNAPSHOT"
const EVENT_TYPE := "CONSTRUCTION_EVENT"

var _gateway
var _players: Dictionary = {}


func setup(gateway) -> Dictionary:
	if gateway == null or not gateway.has_method("connect_client") or not gateway.has_method("disconnect_client") or not gateway.has_method("submit") or not gateway.has_method("get_state_bundle"):
		return _failure("M3_CONSTRUCTION_GATEWAY_REQUIRED")
	_gateway = gateway
	return _success()


func connect_player(logical_player_id: String, ownership_epoch: int, last_seen_event_index: int = -1) -> Dictionary:
	if _gateway == null:
		return _failure("M3_CONSTRUCTION_BRIDGE_NOT_READY")
	if logical_player_id.is_empty() or ownership_epoch < 1:
		return _failure("INVALID_M3_CONSTRUCTION_PLAYER")
	var client_id := "client/m3/%s" % logical_player_id
	var session_id := "session/m3/%s/%d" % [logical_player_id, ownership_epoch]
	var connected: Dictionary = _gateway.connect_client(client_id, session_id, last_seen_event_index)
	if not bool(connected.get("success", false)):
		return connected
	var session: Dictionary = Dictionary(connected.get("session", {})).duplicate(true)
	_players[logical_player_id] = {
		"client_id": client_id,
		"session_id": session_id,
		"session_epoch": int(session.get("session_epoch", 0)),
		"permission_epoch": int(session.get("permission_epoch", 0)),
		"ownership_epoch": ownership_epoch,
	}
	return _success({
		"client_id": client_id,
		"session": session,
		"reconnect": bool(connected.get("reconnect", false)),
		"snapshot": _snapshot_packet(Dictionary(connected.get("state_bundle", {})), int(connected.get("last_event_index", -1))),
		"events": Array(connected.get("events", [])).duplicate(true),
	})


func disconnect_player(logical_player_id: String) -> Dictionary:
	if not _players.has(logical_player_id):
		return _failure("M3_CONSTRUCTION_PLAYER_NOT_CONNECTED")
	var player: Dictionary = _players[logical_player_id]
	var result: Dictionary = _gateway.disconnect_client(String(player["session_id"]), int(player["session_epoch"]))
	if bool(result.get("success", false)):
		_players.erase(logical_player_id)
	return result


func submit_player_command(logical_player_id: String, command: Dictionary) -> Dictionary:
	if _gateway == null:
		return _failure("M3_CONSTRUCTION_BRIDGE_NOT_READY")
	if not _players.has(logical_player_id):
		return _failure("M3_CONSTRUCTION_PLAYER_NOT_CONNECTED")
	var checked: Dictionary = CommandScript.validate(command)
	if not bool(checked.get("success", false)):
		return checked
	var player: Dictionary = _players[logical_player_id]
	if String(command.get("client_id", "")) != String(player["client_id"]) or String(command.get("session_id", "")) != String(player["session_id"]) or int(command.get("session_epoch", -1)) != int(player["session_epoch"]):
		return _failure("M3_CONSTRUCTION_COMMAND_OWNERSHIP_MISMATCH")
	var result: Dictionary = _gateway.submit(command)
	if not bool(result.get("success", false)):
		return result
	var event_value = result.get("event", {})
	if not event_value is Dictionary or not bool(EventScript.validate(Dictionary(event_value)).get("success", false)):
		return _failure("M3_CONSTRUCTION_GATEWAY_EVENT_REQUIRED")
	return _success({
		"result": result.duplicate(true),
		"event_packet": {"type": EVENT_TYPE, "event": Dictionary(event_value).duplicate(true)},
	})


func get_snapshot_packet() -> Dictionary:
	if _gateway == null:
		return {}
	return _snapshot_packet(_gateway.get_state_bundle(), int(_gateway.get_last_event_index()))


func get_player_session(logical_player_id: String) -> Dictionary:
	return Dictionary(_players.get(logical_player_id, {})).duplicate(true)


func _snapshot_packet(bundle: Dictionary, last_event_index: int) -> Dictionary:
	if not bool(BundleScript.validate(bundle).get("success", false)):
		return {}
	return {"type": SNAPSHOT_TYPE, "state_bundle": bundle.duplicate(true), "last_event_index": last_event_index}


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": {}}
