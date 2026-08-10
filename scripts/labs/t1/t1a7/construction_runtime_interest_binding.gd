extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.construction_runtime_interest_binding.v1"

var _configured: bool = false
var _authority_epoch: int = 0
var _states_by_client_id: Dictionary = {}
var _session_by_peer_id: Dictionary = {}
var _active_peer_by_client_id: Dictionary = {}
var _selection_updates: int = 0
var _selection_replays: int = 0
var _selection_conflicts: int = 0
var _stale_revisions: int = 0
var _session_binds: int = 0
var _reconnect_binds: int = 0
var _session_disconnects: int = 0


func configure(authority_epoch: int) -> Dictionary:
	if _configured:
		return _failure("T1A7_INTEREST_BINDING_ALREADY_CONFIGURED")
	if authority_epoch < 1:
		return _failure("T1A7_INTEREST_AUTHORITY_EPOCH_INVALID")
	_authority_epoch = authority_epoch
	_states_by_client_id.clear()
	_session_by_peer_id.clear()
	_active_peer_by_client_id.clear()
	_configured = true
	return _success({"authority_epoch": _authority_epoch})


func bind_session(peer_id: String, session_id: String, client_id: String) -> Dictionary:
	if not _configured:
		return _failure("T1A7_INTEREST_BINDING_NOT_CONFIGURED")
	var peer := peer_id.strip_edges().to_lower()
	var session := session_id.strip_edges().to_lower()
	var client := client_id.strip_edges().to_lower()
	if peer.is_empty() or session.is_empty() or client.is_empty():
		return _failure("T1A7_INTEREST_SESSION_BINDING_INVALID")
	var reconnect := _states_by_client_id.has(client)
	var old_peer := String(_active_peer_by_client_id.get(client, ""))
	if not old_peer.is_empty() and old_peer != peer:
		_session_by_peer_id.erase(old_peer)
	_session_by_peer_id[peer] = {
		"peer_id": peer,
		"session_id": session,
		"client_id": client,
	}
	_active_peer_by_client_id[client] = peer
	if not _states_by_client_id.has(client):
		_states_by_client_id[client] = _empty_client_state(client)
	_session_binds += 1
	if reconnect:
		_reconnect_binds += 1
	return _success({
		"client_id": client,
		"peer_id": peer,
		"session_id": session,
		"reconnect": reconnect,
		"interest_revision": int(Dictionary(_states_by_client_id[client]).get("interest_revision", 0)),
	})


func update_selection(client_id: String, interest_revision: int, selected_construct_ids: Array) -> Dictionary:
	if not _configured:
		return _failure("T1A7_INTEREST_BINDING_NOT_CONFIGURED")
	var client := client_id.strip_edges().to_lower()
	if client.is_empty() or interest_revision < 1:
		return _failure("T1A7_INTEREST_SELECTION_INVALID")
	var normalized_result := _normalize_construct_ids(selected_construct_ids)
	if not bool(normalized_result.get("success", false)):
		return normalized_result
	var normalized: Array = normalized_result["construct_ids"]
	var checksum := _selection_checksum(client, interest_revision, normalized)
	var existing: Dictionary = Dictionary(_states_by_client_id.get(client, _empty_client_state(client))).duplicate(true)
	var previous_revision := int(existing.get("interest_revision", 0))
	if interest_revision < previous_revision:
		_stale_revisions += 1
		return _failure("STALE_CONSTRUCTION_RUNTIME_INTEREST_REVISION", {
			"current_revision": previous_revision,
			"incoming_revision": interest_revision,
		})
	if interest_revision == previous_revision:
		if String(existing.get("selection_checksum", "")) != checksum:
			_selection_conflicts += 1
			return _failure("SAME_REVISION_CONSTRUCTION_RUNTIME_INTEREST_CONFLICT")
		_selection_replays += 1
		return _success({
			"replay": true,
			"changed": false,
			"previous_state": existing.duplicate(true),
			"state": existing.duplicate(true),
		})
	var next_state := {
		"client_id": client,
		"authority_epoch": _authority_epoch,
		"interest_revision": interest_revision,
		"selected_construct_ids": normalized.duplicate(),
		"selection_checksum": checksum,
	}
	_states_by_client_id[client] = next_state
	_selection_updates += 1
	return _success({
		"replay": false,
		"changed": true,
		"previous_state": existing.duplicate(true),
		"state": next_state.duplicate(true),
	})


func restore_client_state(client_id: String, state: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("T1A7_INTEREST_BINDING_NOT_CONFIGURED")
	var client := client_id.strip_edges().to_lower()
	if client.is_empty():
		return _failure("T1A7_INTEREST_CLIENT_ID_REQUIRED")
	if state.is_empty():
		_states_by_client_id.erase(client)
		return _success({"removed": true})
	if String(state.get("client_id", "")) != client \
			or int(state.get("authority_epoch", 0)) != _authority_epoch:
		return _failure("T1A7_INTEREST_RESTORE_STATE_MISMATCH")
	var normalized_result := _normalize_construct_ids(Array(state.get("selected_construct_ids", [])))
	if not bool(normalized_result.get("success", false)):
		return normalized_result
	var normalized: Array = normalized_result["construct_ids"]
	var revision := int(state.get("interest_revision", 0))
	var expected_checksum := "" if revision == 0 else _selection_checksum(client, revision, normalized)
	if String(state.get("selection_checksum", "")) != expected_checksum:
		return _failure("T1A7_INTEREST_RESTORE_CHECKSUM_MISMATCH")
	_states_by_client_id[client] = state.duplicate(true)
	return _success()


func disconnect_session(peer_id: String, session_id: String) -> Dictionary:
	if not _configured:
		return _failure("T1A7_INTEREST_BINDING_NOT_CONFIGURED")
	var peer := peer_id.strip_edges().to_lower()
	var session := session_id.strip_edges().to_lower()
	if not _session_by_peer_id.has(peer):
		return _success({"replay": true})
	var bound: Dictionary = _session_by_peer_id[peer]
	if String(bound.get("session_id", "")) != session:
		return _failure("STALE_CONSTRUCTION_RUNTIME_INTEREST_SESSION")
	var client := String(bound.get("client_id", ""))
	_session_by_peer_id.erase(peer)
	if String(_active_peer_by_client_id.get(client, "")) == peer:
		_active_peer_by_client_id.erase(client)
	_session_disconnects += 1
	return _success({"replay": false, "client_id": client})


func is_selected(peer_id: String, session_id: String, construct_id: String) -> bool:
	if not _configured:
		return false
	var peer := peer_id.strip_edges().to_lower()
	if not _session_by_peer_id.has(peer):
		return false
	var bound: Dictionary = _session_by_peer_id[peer]
	if String(bound.get("session_id", "")) != session_id.strip_edges().to_lower():
		return false
	var client := String(bound.get("client_id", ""))
	var state: Dictionary = _states_by_client_id.get(client, {})
	return Array(state.get("selected_construct_ids", [])).has(construct_id.strip_edges().to_lower())


func active_peer_id(client_id: String) -> String:
	return String(_active_peer_by_client_id.get(client_id.strip_edges().to_lower(), ""))


func active_session_id(client_id: String) -> String:
	var peer := active_peer_id(client_id)
	return String(Dictionary(_session_by_peer_id.get(peer, {})).get("session_id", ""))


func client_state(client_id: String) -> Dictionary:
	return Dictionary(_states_by_client_id.get(client_id.strip_edges().to_lower(), {})).duplicate(true)


func report() -> Dictionary:
	var selected_clients := 0
	for state_value in _states_by_client_id.values():
		if state_value is Dictionary and not Array(state_value.get("selected_construct_ids", [])).is_empty():
			selected_clients += 1
	return {
		"schema": SCHEMA,
		"authority_epoch": _authority_epoch,
		"client_states": _states_by_client_id.size(),
		"active_sessions": _session_by_peer_id.size(),
		"selected_clients": selected_clients,
		"selection_updates": _selection_updates,
		"selection_replays": _selection_replays,
		"selection_conflicts": _selection_conflicts,
		"stale_revisions": _stale_revisions,
		"session_binds": _session_binds,
		"reconnect_binds": _reconnect_binds,
		"session_disconnects": _session_disconnects,
	}


func _empty_client_state(client_id: String) -> Dictionary:
	return {
		"client_id": client_id,
		"authority_epoch": _authority_epoch,
		"interest_revision": 0,
		"selected_construct_ids": [],
		"selection_checksum": "",
	}


func _normalize_construct_ids(values: Array) -> Dictionary:
	var seen: Dictionary = {}
	var normalized: Array[String] = []
	for value in values:
		var construct_id := String(value).strip_edges().to_lower()
		if construct_id.is_empty():
			return _failure("T1A7_INTEREST_CONSTRUCT_ID_REQUIRED")
		if not seen.has(construct_id):
			seen[construct_id] = true
			normalized.append(construct_id)
	normalized.sort()
	return _success({"construct_ids": normalized})


func _selection_checksum(client_id: String, interest_revision: int, selected_construct_ids: Array) -> String:
	return UtilsScript.payload_hash({
		"authority_epoch": _authority_epoch,
		"client_id": client_id,
		"interest_revision": interest_revision,
		"selected_construct_ids": selected_construct_ids.duplicate(),
	})


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
