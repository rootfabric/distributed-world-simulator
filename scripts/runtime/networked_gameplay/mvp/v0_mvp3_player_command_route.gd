extends RefCounted

# Adapter around accepted P6 routing. Owns no identity, authority, gameplay or
# replay ledger. The native M3 Service is the only mutation/receipt source.
const AcceptedRoute = preload("res://scripts/runtime/networked_gameplay/p6/p6_gateway_command_route.gd")
const InputDTO = preload("res://scripts/runtime/networked_gameplay/contracts/player_input_command.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
var _service_ref: WeakRef
var _player := ""
var _session := ""
var _client_session := ""
var _admission = null
var _route = null
var _executions := 0


func configure(service, player: String, session: String, registry, ledger, admission, closure) -> Dictionary:
	if _route != null or service == null or player.is_empty():
		return _failure("MVP3_COMMAND_ROUTE_CONFIGURATION_INVALID")
	_service_ref = weakref(service)
	_player = player
	_session = session
	_client_session = "client-session/mvp3/" + player
	_admission = admission
	_route = AcceptedRoute.new()
	return _route.configure(registry, ledger, self, closure, self)


func _preflight(operation_id: String, command: Dictionary) -> Dictionary:
	var service = _service_ref.get_ref() if _service_ref != null else null
	if service == null or not service.get_live_player_transfer_port().actor_ready(_player):
		return _failure("LIVE_PLAYER_AUTHORITY_NOT_READY")
	if not command.get("wire") is Dictionary:
		return _failure("MVP3_CANONICAL_INPUT_REQUIRED")
	var wire: Dictionary = command["wire"]
	var validated := InputDTO.validate(wire)
	if not bool(validated.get("success", false)):
		return validated
	if wire.get("logical_player_id") != _player or wire.get("transport_session_id") != _session or wire.get("operation_id") != operation_id or command.get("operation_id") != operation_id or wire.get("input_kind") != "MOVEMENT_DELTA":
		return _failure("MVP3_CANONICAL_INPUT_BINDING_MISMATCH")
	var receipt: Dictionary = service.export_live_player_replay(_player).get(operation_id, {})
	if not receipt.is_empty() and receipt.get("fingerprint") != Utils.payload_hash(wire):
		return _failure("OPERATION_REPLAY_CONFLICT")
	return _success()


func route_command(client_session: String, operation_id: String, command: Dictionary) -> Dictionary:
	if client_session != _client_session:
		return _failure("MVP3_CLIENT_SESSION_MISMATCH")
	var check := _preflight(operation_id, command)
	if not bool(check.get("success", false)):
		return check
	return _route.route_command(client_session, operation_id, command)


func admit(player_alias: String, operation_id: String, domain: String, command: Dictionary) -> Dictionary:
	if player_alias != "player/mvp3/" + _player:
		return _failure("MVP3_P6_IDENTITY_ALIAS_MISMATCH")
	var check := _preflight(operation_id, command)
	if not bool(check.get("success", false)):
		return check
	return _admission.admit(player_alias, operation_id, domain, command)


func execute_command(command: Dictionary) -> Dictionary:
	var checked := _preflight(String(command.get("operation_id", "")), command)
	if not bool(checked.get("success", false)):
		return checked
	var result: Dictionary = _service_ref.get_ref().handle_live_player_input(command["wire"])
	if bool(result.get("success", false)) and not bool(result.get("replay", false)):
		_executions += 1
	return result


func complete(player_alias: String, operation_id: String) -> Dictionary:
	var service = _service_ref.get_ref() if _service_ref != null else null
	if service == null or player_alias != "player/mvp3/" + _player:
		return _failure("MVP3_CANONICAL_COMMIT_NOT_PROVEN")
	var receipt: Dictionary = service.export_live_player_replay(_player).get(operation_id, {})
	var result: Dictionary = receipt.get("result", {})
	var actor: Dictionary = result.get("details", {}).get("player", {})
	if result.get("success") != true or actor.get("logical_player_id") != _player or actor.get("player_entity_id") != "player/" + _player:
		return _failure("MVP3_CANONICAL_COMMIT_NOT_PROVEN")
	return _admission.complete(player_alias, operation_id)


func get_report() -> Dictionary:
	return {"canonical_state_owned": false, "canonical_owner_executions": _executions, "p6_route": _route.get_report() if _route != null else {}}


func shutdown() -> void:
	_route = null
	_service_ref = null
	_admission = null


static func _success() -> Dictionary:
	return {"success": true, "error_code": "", "details": {}}


static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "details": {}}
