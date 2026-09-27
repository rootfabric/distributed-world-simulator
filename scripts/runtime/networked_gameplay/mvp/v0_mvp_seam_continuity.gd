extends RefCounted

# Read-only receipt validator. Never creates, transfers or mutates canonical state.
const Support = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")
const MAX_STEP_M := 0.25
const MAX_OBSERVATIONS := 256
const IDENTITY_KEYS := ["product_session_id", "logical_player_id", "player_entity_id", "spawn_generation"]

var _expected: Dictionary = {}
var _last: Dictionary = {}
var _owner := ""
var _epoch := 0
var _checksum := ""
var _error := ""
var _routes: Array[String] = []
var _epochs: Array[int] = []
var _samples: Array[Dictionary] = []
var _movement_steps: Dictionary = {}
var _max_step := 0.0
var _connections := 0
var _disconnects := 0
var _transport_events: Array[Dictionary] = []


func configure(expected: Dictionary) -> Dictionary:
	if not _expected.is_empty():
		return _reject("ALREADY_CONFIGURED")
	for key in IDENTITY_KEYS + ["gateway_endpoint_id"]:
		if not expected.has(key) or str(expected[key]).is_empty():
			return _reject("EXPECTED_IDENTITY_REQUIRED")
	if not _integer(expected["spawn_generation"]) or int(expected["spawn_generation"]) < 1:
		return _reject("EXPECTED_SPAWN_INVALID")
	_expected = expected.duplicate(true)
	return {"success": true}


func note_transport(event_type: String) -> Dictionary:
	if event_type not in ["PEER_CONNECTED", "PEER_DISCONNECTED"]:
		return _reject("TRANSPORT_EVENT_INVALID")
	if _transport_events.size() < 4:
		_transport_events.append({"event_type": event_type, "observed_ms": Time.get_ticks_msec()})
	if event_type == "PEER_CONNECTED":
		_connections += 1
		if _connections != 1:
			return _reject("RECONNECT_FORBIDDEN")
	else:
		_disconnects += 1
		return _reject("DISCONNECT_FORBIDDEN")
	return {"success": _error.is_empty(), "error_code": _error}


func accept_state(payload: Dictionary) -> Dictionary:
	if not _error.is_empty():
		return {"success": false, "error_code": _error}
	if _expected.is_empty():
		return _reject("NOT_CONFIGURED")
	if payload.get("type") != "STATE" or not payload.get("shared_state") is Dictionary:
		return _reject("STATE_REQUIRED")
	var state: Dictionary = payload["shared_state"]
	for key in IDENTITY_KEYS:
		if not state.has(key) or state[key] != _expected[key]:
			return _reject("IDENTITY_CHANGED:" + key)
	if payload.get("gateway_endpoint_id") != _expected["gateway_endpoint_id"] or payload.get("product_session_id") != _expected["product_session_id"]:
		return _reject("GATEWAY_OR_SESSION_CHANGED")
	for number in [payload.get("authority_epoch"), state.get("world_revision"), state.get("last_input_sequence")]:
		if not _integer(number) or float(number) < 0.0:
			return _reject("INVALID_SEQUENCE")
	var position_value = state.get("position_x")
	if typeof(position_value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(position_value)):
		return _reject("INVALID_POSITION")
	var owner: String = str(payload.get("active_authority_id", ""))
	var epoch: int = int(payload["authority_epoch"])
	var revision: int = int(state["world_revision"])
	var checksum: String = str(payload.get("state_checksum", ""))
	if owner not in [Support.AUTHORITY_A, Support.AUTHORITY_B] or epoch < 1:
		return _reject("INVALID_AUTHORITY")
	if checksum.length() != 64 or checksum != Support.checksum(state):
		return _reject("STATE_CHECKSUM_MISMATCH")
	if _last.is_empty():
		if owner != Support.AUTHORITY_A or epoch != 1 or not is_zero_approx(float(position_value)):
			return _reject("INITIAL_STATE_MISMATCH")
	else:
		var previous_revision: int = int(_last["world_revision"])
		if epoch < _epoch or revision < previous_revision or int(state["last_input_sequence"]) < int(_last["last_input_sequence"]):
			return _reject("STALE_STATE")
		if revision == previous_revision:
			if checksum != _checksum or epoch != _epoch or owner != _owner:
				return _reject("REVISION_EQUIVOCATION")
			return {"success": true, "duplicate": true}
		if owner == _owner and epoch != _epoch:
			return _reject("EPOCH_WITHOUT_ROUTE_CHANGE")
		if owner != _owner and epoch != _epoch + 1:
			return _reject("ROUTE_WITHOUT_NEXT_EPOCH")
		if int(state["last_input_sequence"]) <= int(_last["last_input_sequence"]):
			return _reject("INPUT_SEQUENCE_NOT_ADVANCED")
		var step: float = absf(float(position_value) - float(_last["position_x"]))
		if step > MAX_STEP_M + 0.000001:
			return _reject("UNBOUNDED_POSITION_JUMP")
		if _routes.size() == 3 and owner != _owner:
			return _reject("ROUTE_OUTSIDE_BOUNDED_MVP3")
		_max_step = maxf(_max_step, step)
		if owner == _owner and step > 0.000001:
			_movement_steps[str(epoch)] = int(_movement_steps.get(str(epoch), 0)) + 1
	if _samples.size() >= MAX_OBSERVATIONS:
		return _reject("OBSERVATION_BUDGET_EXCEEDED")
	if owner != _owner:
		_routes.append(owner)
		_epochs.append(epoch)
	_owner = owner
	_epoch = epoch
	_checksum = checksum
	_last = state.duplicate(true)
	_samples.append({"authority_id": owner, "authority_epoch": epoch, "state_checksum": checksum, "state": state.duplicate(true)})
	return {"success": true, "duplicate": false}


func report() -> Dictionary:
	var route_ok: bool = _routes == [Support.AUTHORITY_A, Support.AUTHORITY_B, Support.AUTHORITY_A] and _epochs == [1, 2, 3]
	return {
		"canonical_state_owned": false, "error": _error,
		"route_history": _routes.duplicate(), "epochs": _epochs.duplicate(),
		"last_state": _last.duplicate(true), "state_checksum": _checksum,
		"movement_steps_by_epoch": _movement_steps.duplicate(), "max_step_m": _max_step,
		"connect_count": _connections, "reconnect_count": maxi(0, _connections - 1),
		"disconnect_count": _disconnects, "transport_events": _transport_events.duplicate(true),
		"samples": _samples.duplicate(true),
		"goal_reached": _error.is_empty() and route_ok and _connections == 1 and _disconnects == 0 and int(_movement_steps.get("1", 0)) >= 2 and int(_movement_steps.get("2", 0)) >= 2 and int(_movement_steps.get("3", 0)) >= 2,
	}


func _reject(code: String) -> Dictionary:
	if _error.is_empty():
		_error = code
	return {"success": false, "error_code": _error}


static func _integer(value) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floorf(float(value)) and absf(float(value)) <= 9007199254740991.0
