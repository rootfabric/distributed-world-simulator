extends RefCounted

# P6 command adapter for a canonical M3 owner living in another process.
# The gateway owns admission only; a signed native owner receipt is required
# before the existing P6 ledger may be completed.
const AcceptedRoute = preload("res://scripts/runtime/networked_gameplay/p6/p6_gateway_command_route.gd")
const InputDTO = preload("res://scripts/runtime/networked_gameplay/contracts/player_input_command.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

var _dispatcher_ref: WeakRef
var _authority := ""
var _player := ""
var _session := ""
var _client_session := ""
var _admission = null
var _route = null
var _receipts: Dictionary = {}
var _fingerprints: Dictionary = {}
var _executions := 0


func configure(dispatcher, authority: String, player: String, session: String, registry, ledger, admission, closure) -> Dictionary:
	if _route != null or dispatcher == null or not dispatcher.has_method("call_authority") or authority.is_empty() or player.is_empty():
		return _failure("MVP3_REMOTE_ROUTE_CONFIGURATION_INVALID")
	_dispatcher_ref = weakref(dispatcher)
	_authority = authority
	_player = player
	_session = session
	_client_session = "client-session/mvp3/" + player
	_admission = admission
	_route = AcceptedRoute.new()
	return _route.configure(registry, ledger, self, closure, self)


func _preflight(operation_id: String, command: Dictionary) -> Dictionary:
	if not command.get("wire") is Dictionary:
		return _failure("MVP3_CANONICAL_INPUT_REQUIRED")
	var wire: Dictionary = command["wire"]
	var validated := InputDTO.validate(wire)
	if not bool(validated.get("success", false)):
		return validated
	if wire.get("logical_player_id") != _player or wire.get("transport_session_id") != _session or wire.get("operation_id") != operation_id or command.get("operation_id") != operation_id or wire.get("input_kind") not in ["MOVEMENT_DELTA", "MOVEMENT_INTENT"]:
		return _failure("MVP3_CANONICAL_INPUT_BINDING_MISMATCH")
	var known_fingerprint := String(_fingerprints.get(operation_id, ""))
	var dispatcher = _dispatcher_ref.get_ref() if _dispatcher_ref != null else null
	if known_fingerprint.is_empty() and dispatcher != null and dispatcher.has_method("operation_fingerprint"):
		known_fingerprint = String(dispatcher.operation_fingerprint(_player, operation_id))
	if not known_fingerprint.is_empty() and known_fingerprint != Utils.payload_hash(wire):
		return _failure("OPERATION_REPLAY_CONFLICT")
	return _success()


func route_command(client_session: String, operation_id: String, command: Dictionary) -> Dictionary:
	if client_session != _client_session:
		return _failure("MVP3_CLIENT_SESSION_MISMATCH")
	var checked := _preflight(operation_id, command)
	if not bool(checked.get("success", false)):
		return checked
	return _route.route_command(client_session, operation_id, command)


func admit(player_alias: String, operation_id: String, domain: String, command: Dictionary) -> Dictionary:
	if player_alias != "player/mvp3/" + _player:
		return _failure("MVP3_P6_IDENTITY_ALIAS_MISMATCH")
	var checked := _preflight(operation_id, command)
	if not bool(checked.get("success", false)):
		return checked
	return _admission.admit(player_alias, operation_id, domain, command)


func execute_command(command: Dictionary) -> Dictionary:
	var operation_id := String(command.get("operation_id", ""))
	var checked := _preflight(operation_id, command)
	if not bool(checked.get("success", false)):
		return checked
	var dispatcher = _dispatcher_ref.get_ref() if _dispatcher_ref != null else null
	if dispatcher == null:
		return _failure("MVP3_REMOTE_DISPATCHER_UNAVAILABLE")
	var rpc: Dictionary = dispatcher.call_authority(_authority, {"kind": "MOVE", "actor": _player, "wire": command["wire"]})
	if not bool(rpc.get("success", false)):
		return rpc
	var native: Dictionary = rpc.get("details", {}).get("result", {})
	var receipt: Dictionary = rpc.get("details", {}).get("receipt", {})
	if not bool(native.get("success", false)):
		return native
	if receipt.get("fingerprint") != Utils.payload_hash(command["wire"]) or receipt.get("live_player_id") != _player:
		return _failure("MVP3_NATIVE_RECEIPT_INVALID")
	# New graphical input must have executed the real fixed movement method,
	# not just advanced a clock next to a direct coordinate mutation. Historical
	# replay is already bound to its canonical fingerprint/outcome and adds no tick.
	if command["wire"].get("input_kind") == "MOVEMENT_INTENT" and not bool(native.get("replay", false)):
		var simulation: Dictionary = native.get("details", {}).get("server_simulation", {})
		if simulation.get("fixed_tick") != true or not is_equal_approx(float(simulation.get("delta_seconds", 0.0)), 1.0 / 60.0):
			return _failure("MVP3_NATIVE_FIXED_TICK_NOT_PROVEN")
	_receipts[operation_id] = receipt.duplicate(true)
	_fingerprints[operation_id] = String(receipt["fingerprint"])
	if dispatcher.has_method("record_operation_fingerprint"):
		dispatcher.record_operation_fingerprint(_player, operation_id, String(receipt["fingerprint"]))
	if not bool(native.get("replay", false)):
		_executions += 1
	return native


func complete(player_alias: String, operation_id: String) -> Dictionary:
	if player_alias != "player/mvp3/" + _player or not _receipts.has(operation_id):
		return _failure("MVP3_CANONICAL_COMMIT_NOT_PROVEN")
	var receipt: Dictionary = _receipts[operation_id]
	var result: Dictionary = receipt.get("result", {})
	var actor: Dictionary = result.get("details", {}).get("player", {})
	if result.get("success") != true or actor.get("logical_player_id") != _player or actor.get("player_entity_id") != "player/" + _player:
		return _failure("MVP3_CANONICAL_COMMIT_NOT_PROVEN")
	return _admission.complete(player_alias, operation_id)


func get_report() -> Dictionary:
	return {"canonical_state_owned": false, "authority_id": _authority, "canonical_owner_executions": _executions, "receipt_count": _receipts.size(), "p6_route": _route.get_report() if _route != null else {}}


func shutdown() -> void:
	_route = null
	_dispatcher_ref = null
	_admission = null


static func _success() -> Dictionary:
	return {"success": true, "error_code": "", "details": {}}


static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "details": {}}
