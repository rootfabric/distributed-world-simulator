extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const CommandScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_command.gd")
const EventScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_event.gd")
const PermissionStoreScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_permission_store.gd")
const SessionStoreScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_session_store.gd")

const STATE_SCHEMA := "planet_simulator.construction_multiplayer_gateway.v1"
const STATE_FIELDS: Array[String] = ["schema", "generation", "permission_store", "session_store", "events", "terminal_commands", "checksum"]
const FAILURE_AFTER_EXECUTION_BEFORE_EVENT := "AFTER_EXECUTION_BEFORE_EVENT"
var _executor
var _permissions
var _sessions
var _events: Array = []
var _terminal_commands: Dictionary = {}
var _generation := 0

func setup(executor, permission_store = null, session_store = null) -> Dictionary:
	if executor == null or not executor.has_method("execute") or not executor.has_method("get_generation") or not executor.has_method("get_construct_snapshot") or not executor.has_method("export_state_bundle") or not executor.has_method("has_committed_operation"):
		return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_GATEWAY_EXECUTOR_REQUIRED")
	_executor = executor; _permissions = permission_store if permission_store != null else PermissionStoreScript.new(); _sessions = session_store if session_store != null else SessionStoreScript.new()
	if not _permissions.has_method("authorize") or not _sessions.has_method("connect_session"): return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_GATEWAY_STORE_REQUIRED")
	return ParametricUtils.success()

func connect_client(client_id: String, session_id: String, last_seen_event_index: int = -1) -> Dictionary:
	if last_seen_event_index < -1 or last_seen_event_index >= _events.size(): return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_CONNECT_EVENT_INDEX")
	var connected: Dictionary = _sessions.connect_session(client_id, session_id, _permissions.get_epoch(), last_seen_event_index)
	if not bool(connected.get("success", false)): return connected
	var missing: Array = []
	for index in range(last_seen_event_index + 1, _events.size()): missing.append(Dictionary(_events[index]).duplicate(true))
	return ParametricUtils.success({"session": connected["session"], "reconnect": connected["reconnect"], "state_bundle": _executor.export_state_bundle(), "events": missing, "last_event_index": _events.size() - 1})

func disconnect_client(session_id: String, session_epoch: int) -> Dictionary: return _sessions.disconnect_session(session_id, session_epoch)
func acknowledge(session_id: String, session_epoch: int, event_index: int) -> Dictionary:
	if event_index >= _events.size(): return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_EVENT_ACK_OUT_OF_RANGE")
	return _sessions.acknowledge(session_id, session_epoch, event_index)

func submit(command: Dictionary, failure_point: String = "") -> Dictionary:
	var checked := CommandScript.validate(command); if not bool(checked.get("success", false)): return checked
	var command_id := String(command["command_id"]); var command_checksum := String(command["checksum"])
	if _terminal_commands.has(command_id):
		var terminal: Dictionary = _terminal_commands[command_id]
		if String(terminal["command_checksum"]) != command_checksum: return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_COMMAND_ID_CONFLICT")
		var replay: Dictionary = terminal["result"].duplicate(true); replay["replay"] = true; return replay
	var active: Dictionary = _sessions.require_active(String(command["session_id"]), int(command["session_epoch"])); if not bool(active.get("success", false)): return active
	if String(active["session"]["client_id"]) != String(command["client_id"]): return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_SESSION_CLIENT_MISMATCH")
	if int(active["session"]["next_sequence"]) != int(command["sequence"]): return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_COMMAND_SEQUENCE_MISMATCH")
	var authorized: Dictionary = _permissions.authorize(String(command["client_id"]), String(command["construct_id"]), String(command["action"]), int(command["permission_epoch"]))
	if not bool(authorized.get("success", false)): return _terminal_rejection(command, authorized)
	var committed_replay: bool = _executor.has_committed_operation(command)
	if not committed_replay:
		var expected_generation := int(command["expected_server_generation"])
		if expected_generation >= 0 and expected_generation != _executor.get_generation(): return _terminal_rejection(command, ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_SERVER_GENERATION_PRECONDITION_MISMATCH"))
		var current: Dictionary = _executor.get_construct_snapshot(String(command["construct_id"]))
		var current_checksum := String(current.get("checksum", ""))
		if String(command["expected_construct_checksum"]) != current_checksum: return _terminal_rejection(command, ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_CONSTRUCT_PRECONDITION_MISMATCH"))
	var executed: Dictionary = _executor.execute(command)
	if not bool(executed.get("success", false)): return _terminal_rejection(command, executed)
	if failure_point == FAILURE_AFTER_EXECUTION_BEFORE_EVENT: return ParametricUtils.failure("INJECTED_CONSTRUCTION_MULTIPLAYER_GATEWAY_FAILURE_AFTER_EXECUTION")
	if not failure_point.is_empty(): return ParametricUtils.failure("UNKNOWN_CONSTRUCTION_MULTIPLAYER_GATEWAY_FAILURE_POINT")
	var bundle: Dictionary = _executor.export_state_bundle(); var event := EventScript.create(_events.size(), command, bundle); _events.append(event)
	var result := ParametricUtils.success({"accepted": true, "replay": false, "command_id": command_id, "command_checksum": command_checksum, "event_index": int(event["event_index"]), "event": event.duplicate(true), "state_bundle": bundle.duplicate(true), "execution_result": executed.duplicate(true)})
	_terminal_commands[command_id] = {"command_checksum": command_checksum, "result": result.duplicate(true)}
	var consumed: Dictionary = _sessions.consume_sequence(String(command["session_id"]), int(command["session_epoch"]), int(command["sequence"])); if not bool(consumed.get("success", false)): return consumed
	_generation += 1; return result

func get_events_after(event_index: int) -> Array:
	var output: Array = []
	for index in range(event_index + 1, _events.size()): output.append(Dictionary(_events[index]).duplicate(true))
	return output
func get_state_bundle() -> Dictionary: return _executor.export_state_bundle()
func get_last_event_index() -> int: return _events.size() - 1
func get_generation() -> int: return _generation
func get_permission_store(): return _permissions
func get_session_store(): return _sessions

func export_state() -> Dictionary:
	var command_ids: Array = _terminal_commands.keys(); command_ids.sort(); var terminal: Array = []
	for command_id in command_ids: terminal.append({"command_id": String(command_id), "command_checksum": String(_terminal_commands[command_id]["command_checksum"]), "result": Dictionary(_terminal_commands[command_id]["result"]).duplicate(true)})
	var state := {"schema": STATE_SCHEMA, "generation": _generation, "permission_store": _permissions.export_state(), "session_store": _sessions.export_state(), "events": _events.duplicate(true), "terminal_commands": terminal, "checksum": ""}; state["checksum"] = compute_state_checksum(state); return state

func load_state(state: Dictionary) -> Dictionary:
	var checked := validate_state(state); if not bool(checked.get("success", false)): return checked
	var permission_result: Dictionary = _permissions.load_state(state["permission_store"]); if not bool(permission_result.get("success", false)): return permission_result
	var session_result: Dictionary = _sessions.load_state(state["session_store"]); if not bool(session_result.get("success", false)): return session_result
	var terminal := {}; for entry in state["terminal_commands"]: terminal[String(entry["command_id"])] = {"command_checksum": String(entry["command_checksum"]), "result": Dictionary(entry["result"]).duplicate(true)}
	_generation = int(state["generation"]); _events = Array(state["events"]).duplicate(true); _terminal_commands = terminal; return ParametricUtils.success()

static func validate_state(state: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(state, STATE_FIELDS); if not bool(exact.get("success", false)): return exact
	if state.get("schema") != STATE_SCHEMA or not UtilsScript.is_json_integer(state.get("generation")) or int(state["generation"]) < 0: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_GATEWAY_STATE")
	var checked := PermissionStoreScript.validate_state(state.get("permission_store", {})); if not bool(checked.get("success", false)): return checked
	checked = SessionStoreScript.validate_state(state.get("session_store", {})); if not bool(checked.get("success", false)): return checked
	if typeof(state.get("events")) != TYPE_ARRAY or typeof(state.get("terminal_commands")) != TYPE_ARRAY: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_GATEWAY_COLLECTION")
	var expected_index := 0
	for event in state["events"]:
		if typeof(event) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_EVENT")
		checked = EventScript.validate(event); if not bool(checked.get("success", false)): return checked
		if int(event["event_index"]) != expected_index: return ParametricUtils.failure("NON_CONTIGUOUS_CONSTRUCTION_MULTIPLAYER_EVENTS")
		expected_index += 1
	var previous := ""
	for entry in state["terminal_commands"]:
		if typeof(entry) != TYPE_DICTIONARY or entry.keys().size() != 3 or not entry.has("command_id") or not entry.has("command_checksum") or not entry.has("result"): return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_TERMINAL_COMMAND")
		var id := String(entry["command_id"]); if id.is_empty() or (not previous.is_empty() and id <= previous): return ParametricUtils.failure("NON_CANONICAL_CONSTRUCTION_MULTIPLAYER_TERMINAL_COMMANDS")
		if String(entry["command_checksum"]).length() != 64 or typeof(entry["result"]) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_TERMINAL_COMMAND")
		previous = id
	if String(state.get("checksum", "")) != compute_state_checksum(state): return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_GATEWAY_STATE_CHECKSUM_MISMATCH")
	return ParametricUtils.success()

static func compute_state_checksum(state: Dictionary) -> String:
	var payload := state.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)

func _terminal_rejection(command: Dictionary, failure: Dictionary) -> Dictionary:
	var result := failure.duplicate(true); result["accepted"] = false; result["replay"] = false; result["command_id"] = String(command["command_id"]); result["command_checksum"] = String(command["checksum"]); result["event_index"] = -1
	_terminal_commands[String(command["command_id"])] = {"command_checksum": String(command["checksum"]), "result": result.duplicate(true)}
	var consumed: Dictionary = _sessions.consume_sequence(String(command["session_id"]), int(command["session_epoch"]), int(command["sequence"])); if bool(consumed.get("success", false)): _generation += 1
	return result
