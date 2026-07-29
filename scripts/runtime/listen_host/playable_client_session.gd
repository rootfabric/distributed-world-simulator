extends RefCounted

const NetworkCommand = preload("res://scripts/network/contracts/network_command_envelope.gd")
const NetworkResult = preload("res://scripts/network/contracts/network_command_result_envelope.gd")
const PlayableStateCodec = preload("res://scripts/runtime/listen_host/playable_state_codec.gd")

const SCHEMA: String = "planet_simulator.playable_client_session.v1"
const PLAYER_ENTITY_ID: String = "player/local-astronaut"

var _client_runtime
var _item_bridge
var _session_id: String = ""
var _message_sequence: int = 0
var _command_count: int = 0
var _delta_count: int = 0
var _rejection_count: int = 0


func setup(client_runtime_reference, item_bridge_reference, session_id: String) -> Dictionary:
	if client_runtime_reference == null or not client_runtime_reference is RefCounted:
		return _failure("INVALID_CLIENT_RUNTIME")
	for method_name in ["get_snapshot", "submit_command", "accept_delta"]:
		if not client_runtime_reference.has_method(method_name):
			return _failure("CLIENT_RUNTIME_METHOD_MISSING", {"method": method_name})
	if item_bridge_reference == null or not item_bridge_reference is RefCounted:
		return _failure("INVALID_ITEM_COMMAND_BRIDGE")
	for method_name in ["submit_item_command", "get_report", "invalidate"]:
		if not item_bridge_reference.has_method(method_name):
			return _failure("ITEM_BRIDGE_METHOD_MISSING", {"method": method_name})
	_session_id = session_id.strip_edges()
	if _session_id.is_empty():
		return _failure("PLAYABLE_SESSION_ID_REQUIRED")
	_client_runtime = client_runtime_reference
	_item_bridge = item_bridge_reference
	_message_sequence = 0
	_command_count = 0
	_delta_count = 0
	_rejection_count = 0
	return _success()


func get_item_bridge():
	return _item_bridge


func get_snapshot(entity_id: String) -> Dictionary:
	if _client_runtime == null:
		return {}
	return _client_runtime.get_snapshot(entity_id)


func submit_player_state(
	player_state: Dictionary,
	delta_seconds: float,
	operation_id: String
) -> Dictionary:
	if _client_runtime == null:
		return _failure("PLAYABLE_CLIENT_SESSION_NOT_CONFIGURED")
	if operation_id.strip_edges().is_empty():
		return _failure("PLAYABLE_OPERATION_ID_REQUIRED")
	var state_validation: Dictionary = PlayableStateCodec.validate_player_state(player_state)
	if not bool(state_validation.get("success", false)):
		return _failure(
			String(state_validation.get("error_code", "INVALID_PLAYER_STATE")),
			state_validation.get("details", {})
		)
	var snapshot: Dictionary = get_snapshot(PLAYER_ENTITY_ID)
	if snapshot.is_empty():
		return _failure("PLAYER_REPLICA_MISSING")
	_message_sequence += 1
	var command: Dictionary = NetworkCommand.create(
		"message/h1/player/%d" % _message_sequence,
		operation_id,
		PLAYER_ENTITY_ID,
		"player.move",
		{
			"session_id": _session_id,
			"player_state": player_state.duplicate(true),
			"delta_seconds": delta_seconds,
		},
		int(snapshot.get("state_revision", -1)),
		int(snapshot.get("authority_epoch", -1)),
		int(snapshot.get("server_tick", 0)),
		Time.get_ticks_msec()
	)
	var submitted: Dictionary = _client_runtime.submit_command(command)
	_command_count += 1
	if not bool(submitted.get("success", false)):
		return submitted
	var result_value = submitted.get("details", {}).get("result", {})
	if not result_value is Dictionary:
		return _failure("INVALID_PLAYER_COMMAND_RESULT")
	var result: Dictionary = Dictionary(result_value)
	var result_validation: Dictionary = NetworkResult.validate(result)
	if not bool(result_validation.get("success", false)):
		return _failure("INVALID_PLAYER_COMMAND_RESULT", {
			"validation_error_code": String(result_validation.get("error_code", "")),
		})
	var payload: Dictionary = Dictionary(result.get("payload", {}))
	var delta_value = payload.get("replication_delta", {})
	var delivery: Dictionary = _success()
	if delta_value is Dictionary and not Dictionary(delta_value).is_empty():
		delivery = _client_runtime.accept_delta(Dictionary(delta_value))
		if not bool(delivery.get("success", false)):
			return delivery
		_delta_count += 1
	if String(result.get("status", "")) != "SUCCEEDED":
		_rejection_count += 1
		return _failure(
			String(result.get("error_code", "PLAYER_COMMAND_REJECTED")),
			{
				"result": result.duplicate(true),
				"snapshot": get_snapshot(PLAYER_ENTITY_ID),
			}
		)
	return _success({
		"result": result.duplicate(true),
		"delivery": delivery,
		"snapshot": get_snapshot(PLAYER_ENTITY_ID),
	})


func get_report() -> Dictionary:
	var client_report: Dictionary = (
		_client_runtime.get_report()
		if _client_runtime != null
		else {}
	)
	return {
		"schema": SCHEMA,
		"configured": _client_runtime != null,
		"session_id": _session_id,
		"command_count": _command_count,
		"delta_count": _delta_count,
		"rejection_count": _rejection_count,
		"client_runtime": client_report,
		"item_bridge": _item_bridge.get_report() if _item_bridge != null else {},
		"direct_authority_references": 0,
		"direct_domain_references": 0,
	}


func invalidate() -> void:
	_client_runtime = null
	_item_bridge = null
	_session_id = ""


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
