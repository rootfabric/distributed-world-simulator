extends "res://scripts/labs/t1/t1a6_m3_runtime_server_adapter.gd"

const RecoverableRuntimeScript = preload("res://scripts/labs/t1/t1a7/t1_d0_recoverable_runtime_executor.gd")
const InterestBindingScript = preload("res://scripts/labs/t1/t1a7/construction_runtime_interest_binding.gd")

const T1A7_SCHEMA: String = "planet_simulator.t1a7_m3_runtime_server_adapter.v1"
const CONSTRUCT_ID: String = "construct/t1/lunar-outpost/d0"

var _runtime_interest
var _interest_updates: int = 0
var _interest_baselines: int = 0
var _interest_baseline_failures: int = 0
var _interest_suppressed_snapshots: int = 0


func _create_t1_runtime():
	return RecoverableRuntimeScript.new()


func setup(config: Dictionary) -> Dictionary:
	_runtime_interest = InterestBindingScript.new()
	var binding_setup: Dictionary = _runtime_interest.configure(int(config.get("authority_epoch", 1)))
	if not bool(binding_setup.get("success", false)):
		_runtime_interest = null
		return _t1a7_failure("T1A7_INTEREST_BINDING_SETUP_FAILED", {"cause": binding_setup})
	var base_setup: Dictionary = super.setup(config)
	if not bool(base_setup.get("success", false)):
		_runtime_interest = null
		return base_setup
	return _t1a7_success({
		"runtime_snapshot": create_construction_runtime_snapshot(),
		"interest": _runtime_interest.report(),
	})


func apply_runtime_interest(
	client_id: String,
	interest_revision: int,
	selected_construct_ids: Array
) -> Dictionary:
	if _runtime_interest == null:
		return _t1a7_failure("T1A7_INTEREST_BINDING_NOT_READY")
	var client: String = client_id.strip_edges().to_lower()
	var updated: Dictionary = _runtime_interest.update_selection(
		client, interest_revision, selected_construct_ids
	)
	if not bool(updated.get("success", false)):
		return updated
	var details: Dictionary = Dictionary(updated.get("details", {}))
	if bool(details.get("replay", false)):
		return _t1a7_success({
			"mode": "CURRENT_SELECTION",
			"replay": true,
			"interest_revision": interest_revision,
		})
	_interest_updates += 1
	var state: Dictionary = Dictionary(details.get("state", {}))
	var selected: bool = Array(state.get("selected_construct_ids", [])).has(CONSTRUCT_ID)
	var peer_id: String = String(_runtime_interest.active_peer_id(client))
	var session_id: String = String(_runtime_interest.active_session_id(client))
	if not selected or peer_id.is_empty() or session_id.is_empty():
		return _t1a7_success({
			"mode": "OUT_OF_INTEREST" if not selected else "NO_ACTIVE_SESSION",
			"replay": false,
			"interest_revision": interest_revision,
			"selected": selected,
		})
	if not _peer_to_player.has(peer_id) \
			or String(_peer_to_player.get(peer_id, "")) != client \
			or String(_peer_to_session.get(peer_id, "")) != session_id:
		_runtime_interest.restore_client_state(client, Dictionary(details.get("previous_state", {})))
		return _t1a7_failure("T1A7_INTEREST_ACTIVE_SESSION_STALE")
	if not _send_runtime_snapshot(peer_id, "INTEREST_BASELINE"):
		_interest_baseline_failures += 1
		_runtime_interest.restore_client_state(client, Dictionary(details.get("previous_state", {})))
		return _t1a7_failure("T1A7_INTEREST_BASELINE_SEND_FAILED")
	_interest_baselines += 1
	return _t1a7_success({
		"mode": "AUTHORITATIVE_BASELINE",
		"replay": false,
		"interest_revision": interest_revision,
		"selected": true,
		"peer_id": peer_id,
		"session_id": session_id,
		"snapshot_revision": int(create_construction_runtime_snapshot().get("revision", 0)),
	})


func _should_send_runtime_snapshot_to_peer(peer_id: String, _reason: String) -> bool:
	if _runtime_interest == null or not _peer_to_player.has(peer_id):
		_interest_suppressed_snapshots += 1
		return false
	var session_id: String = String(_peer_to_session.get(peer_id, ""))
	var client_id: String = String(_peer_to_player.get(peer_id, ""))
	if session_id.is_empty() or client_id.is_empty():
		_interest_suppressed_snapshots += 1
		return false
	if String(_runtime_interest.active_peer_id(client_id)) != peer_id \
			or String(_runtime_interest.active_session_id(client_id)) != session_id:
		var bound: Dictionary = _runtime_interest.bind_session(peer_id, session_id, client_id)
		if not bool(bound.get("success", false)):
			_interest_suppressed_snapshots += 1
			return false
	var selected: bool = bool(_runtime_interest.is_selected(peer_id, session_id, CONSTRUCT_ID))
	if not selected:
		_interest_suppressed_snapshots += 1
	return selected


func _handle_disconnect(peer_id: String, session_id: String) -> void:
	if _runtime_interest != null:
		_runtime_interest.disconnect_session(peer_id, session_id)
	super._handle_disconnect(peer_id, session_id)


func _handle_leave(peer_id: String, session_id: String, payload: Dictionary) -> void:
	super._handle_leave(peer_id, session_id, payload)
	if _runtime_interest != null and not _peer_to_session.has(peer_id):
		_runtime_interest.disconnect_session(peer_id, session_id)


func get_t1a7_runtime_report() -> Dictionary:
	return {
		"schema": T1A7_SCHEMA,
		"construct_id": CONSTRUCT_ID,
		"interest_updates": _interest_updates,
		"interest_baselines": _interest_baselines,
		"interest_baseline_failures": _interest_baseline_failures,
		"interest_suppressed_snapshots": _interest_suppressed_snapshots,
		"interest": _runtime_interest.report() if _runtime_interest != null else {},
		"t1a6": get_t1a6_runtime_report(),
	}


static func _t1a7_success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _t1a7_failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
