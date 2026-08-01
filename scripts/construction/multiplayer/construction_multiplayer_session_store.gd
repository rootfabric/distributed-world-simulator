extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")

const STATE_SCHEMA := "planet_simulator.construction_multiplayer_session_store.v1"
const SESSION_SCHEMA := "planet_simulator.construction_multiplayer_session.v1"
const SESSION_FIELDS: Array[String] = ["schema", "session_id", "client_id", "session_epoch", "permission_epoch", "next_sequence", "last_acknowledged_event_index", "connected", "checksum"]
const STATE_FIELDS: Array[String] = ["schema", "generation", "sessions", "checksum"]
var _sessions: Dictionary = {}
var _generation := 0

func connect_session(client_id: String, session_id: String, permission_epoch: int, last_acknowledged_event_index: int) -> Dictionary:
	if not _id(client_id, "client/") or not _id(session_id, "session/") or permission_epoch < 0 or last_acknowledged_event_index < -1: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_SESSION_CONNECT")
	var session_epoch := 1
	var next_sequence := 0
	if _sessions.has(session_id):
		var previous: Dictionary = _sessions[session_id]
		if String(previous["client_id"]) != client_id: return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_SESSION_CLIENT_CONFLICT")
		session_epoch = int(previous["session_epoch"]) + 1
		next_sequence = int(previous["next_sequence"])
	var session := _create_session(session_id, client_id, session_epoch, permission_epoch, next_sequence, last_acknowledged_event_index, true)
	_sessions[session_id] = session; _generation += 1
	return ParametricUtils.success({"session": session.duplicate(true), "reconnect": session_epoch > 1, "generation": _generation})

func disconnect_session(session_id: String, session_epoch: int) -> Dictionary:
	var checked := require_active(session_id, session_epoch)
	if not bool(checked.get("success", false)): return checked
	var session: Dictionary = _sessions[session_id].duplicate(true); session["connected"] = false; session["checksum"] = compute_session_checksum(session)
	_sessions[session_id] = session; _generation += 1
	return ParametricUtils.success({"session": session.duplicate(true), "generation": _generation})

func require_active(session_id: String, session_epoch: int) -> Dictionary:
	if not _sessions.has(session_id): return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_SESSION_NOT_FOUND")
	var session: Dictionary = _sessions[session_id]
	if int(session["session_epoch"]) != session_epoch: return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_SESSION_EPOCH_MISMATCH")
	if not bool(session["connected"]): return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_SESSION_DISCONNECTED")
	return ParametricUtils.success({"session": session.duplicate(true)})

func consume_sequence(session_id: String, session_epoch: int, sequence: int) -> Dictionary:
	var active := require_active(session_id, session_epoch); if not bool(active.get("success", false)): return active
	var session: Dictionary = active["session"]
	if int(session["next_sequence"]) != sequence: return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_COMMAND_SEQUENCE_MISMATCH")
	session["next_sequence"] = sequence + 1; session["checksum"] = compute_session_checksum(session); _sessions[session_id] = session; _generation += 1
	return ParametricUtils.success({"session": session.duplicate(true), "generation": _generation})

func acknowledge(session_id: String, session_epoch: int, event_index: int) -> Dictionary:
	var active := require_active(session_id, session_epoch); if not bool(active.get("success", false)): return active
	var session: Dictionary = active["session"]
	if event_index < int(session["last_acknowledged_event_index"]): return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_EVENT_ACK_ROLLBACK")
	if event_index == int(session["last_acknowledged_event_index"]): return ParametricUtils.success({"replay": true, "session": session})
	session["last_acknowledged_event_index"] = event_index; session["checksum"] = compute_session_checksum(session); _sessions[session_id] = session; _generation += 1
	return ParametricUtils.success({"replay": false, "session": session.duplicate(true), "generation": _generation})

func get_session(session_id: String) -> Dictionary: return Dictionary(_sessions.get(session_id, {})).duplicate(true)
func get_generation() -> int: return _generation

func export_state() -> Dictionary:
	var ids: Array = _sessions.keys(); ids.sort(); var sessions: Array = []
	for id in ids: sessions.append(Dictionary(_sessions[id]).duplicate(true))
	var state := {"schema": STATE_SCHEMA, "generation": _generation, "sessions": sessions, "checksum": ""}; state["checksum"] = compute_state_checksum(state); return state

func load_state(state: Dictionary) -> Dictionary:
	var checked := validate_state(state); if not bool(checked.get("success", false)): return checked
	var sessions := {}
	for session in state["sessions"]: sessions[String(session["session_id"])] = Dictionary(session).duplicate(true)
	_generation = int(state["generation"]); _sessions = sessions; return ParametricUtils.success()

static func validate_session(session: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(session, SESSION_FIELDS); if not bool(exact.get("success", false)): return exact
	if session.get("schema") != SESSION_SCHEMA: return ParametricUtils.failure("UNSUPPORTED_CONSTRUCTION_MULTIPLAYER_SESSION_SCHEMA")
	if not _id(String(session.get("session_id", "")), "session/") or not _id(String(session.get("client_id", "")), "client/"): return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_SESSION_IDENTITY")
	for field in ["session_epoch", "permission_epoch", "next_sequence"]:
		if not UtilsScript.is_json_integer(session.get(field)) or int(session[field]) < 0: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_SESSION_COUNTER")
	if not UtilsScript.is_json_integer(session.get("last_acknowledged_event_index")) or int(session["last_acknowledged_event_index"]) < -1: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_SESSION_ACK")
	if typeof(session.get("connected")) != TYPE_BOOL: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_SESSION_CONNECTED")
	if String(session.get("checksum", "")) != compute_session_checksum(session): return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_SESSION_CHECKSUM_MISMATCH")
	return ParametricUtils.success()

static func validate_state(state: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(state, STATE_FIELDS); if not bool(exact.get("success", false)): return exact
	if state.get("schema") != STATE_SCHEMA or not UtilsScript.is_json_integer(state.get("generation")) or int(state["generation"]) < 0 or typeof(state.get("sessions")) != TYPE_ARRAY: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_SESSION_STORE")
	var previous := ""; var ids := {}
	for session in state["sessions"]:
		if typeof(session) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_SESSION")
		var checked := validate_session(session); if not bool(checked.get("success", false)): return checked
		var id := String(session["session_id"])
		if ids.has(id) or (not previous.is_empty() and id < previous): return ParametricUtils.failure("NON_CANONICAL_CONSTRUCTION_MULTIPLAYER_SESSIONS")
		ids[id] = true; previous = id
	if String(state.get("checksum", "")) != compute_state_checksum(state): return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_SESSION_STORE_CHECKSUM_MISMATCH")
	return ParametricUtils.success()

static func compute_session_checksum(session: Dictionary) -> String:
	var payload := session.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
static func compute_state_checksum(state: Dictionary) -> String:
	var payload := state.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
static func _create_session(session_id: String, client_id: String, session_epoch: int, permission_epoch: int, next_sequence: int, ack: int, connected: bool) -> Dictionary:
	var session := {"schema": SESSION_SCHEMA, "session_id": session_id, "client_id": client_id, "session_epoch": session_epoch, "permission_epoch": permission_epoch, "next_sequence": next_sequence, "last_acknowledged_event_index": ack, "connected": connected, "checksum": ""}; session["checksum"] = compute_session_checksum(session); return session
static func _id(value: String, prefix: String) -> bool: return value.begins_with(prefix) and value.length() > prefix.length() and value == value.strip_edges()
