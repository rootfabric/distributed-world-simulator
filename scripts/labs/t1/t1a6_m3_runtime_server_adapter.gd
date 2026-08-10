extends "res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd"

const T1RuntimeScript = preload("res://scripts/labs/t1/t1_d0_interactive_runtime_executor.gd")
const RuntimeSnapshotScript = preload("res://scripts/runtime/networked_gameplay/contracts/construction_runtime_snapshot.gd")

const T1A6_SCHEMA: String = "planet_simulator.t1a6_m3_runtime_server_adapter.v1"
const RUNTIME_COMMAND_MESSAGE: String = "CONSTRUCTION_RUNTIME_COMMAND"
const RUNTIME_RESULT_MESSAGE: String = "CONSTRUCTION_RUNTIME_COMMAND_RESULT"
const RUNTIME_SNAPSHOT_MESSAGE: String = "CONSTRUCTION_RUNTIME_SNAPSHOT"

var _t1_runtime
var _runtime_commands: int = 0
var _runtime_results: int = 0
var _runtime_snapshots: int = 0
var _runtime_rejections: int = 0


func setup(config: Dictionary) -> Dictionary:
	var m0_root := String(config.get("t1a6_m0_root", "")).strip_edges()
	if m0_root.is_empty():
		return _failure("T1A6_M0_ROOT_REQUIRED")
	_t1_runtime = T1RuntimeScript.new()
	var runtime_setup: Dictionary = _t1_runtime.setup(m0_root)
	if not bool(runtime_setup.get("success", false)):
		_t1_runtime = null
		return _failure("T1A6_RUNTIME_SETUP_FAILED", {"cause": runtime_setup})
	var base_setup: Dictionary = super.setup(config)
	if not bool(base_setup.get("success", false)):
		_t1_runtime = null
		return base_setup
	return _success({"runtime_snapshot": create_construction_runtime_snapshot()})


func _handle_message(peer_id: String, session_id: String, payload: Dictionary) -> void:
	if String(payload.get("type", "")) != RUNTIME_COMMAND_MESSAGE:
		super._handle_message(peer_id, session_id, payload)
		return
	if not _is_peer_compatible(peer_id, session_id):
		super._handle_message(peer_id, session_id, payload)
		return
	_handle_construction_runtime_command(peer_id, session_id, payload)


func _handle_join(peer_id: String, session_id: String, payload: Dictionary) -> void:
	super._handle_join(peer_id, session_id, payload)
	if _peer_to_player.has(peer_id) and String(_peer_to_session.get(peer_id, "")) == session_id:
		_send_runtime_snapshot(peer_id, "JOIN_BASELINE")


func _handle_construction_runtime_command(peer_id: String, session_id: String, payload: Dictionary) -> void:
	_runtime_commands += 1
	var operation_id := String(payload.get("operation_id", "")).strip_edges()
	if not _peer_to_player.has(peer_id) or String(_peer_to_session.get(peer_id, "")) != session_id:
		_runtime_rejections += 1
		_send_runtime_result(peer_id, operation_id, _failure("STALE_TRANSPORT_SESSION"))
		return
	if _t1_runtime == null:
		_runtime_rejections += 1
		_send_runtime_result(peer_id, operation_id, _failure("T1A6_RUNTIME_NOT_READY"))
		return
	var before_report: Dictionary = _t1_runtime.get_report()
	var before_revision := int(Dictionary(before_report.get("runtime_state", {})).get("generation", 0))
	var command_payload_value = payload.get("payload", {})
	var command_payload: Dictionary = Dictionary(command_payload_value).duplicate(true) if command_payload_value is Dictionary else {}
	var result: Dictionary = _t1_runtime.execute(
		String(payload.get("kind", "")),
		String(payload.get("action_kind", "")),
		operation_id,
		int(payload.get("expected_revision", -1)),
		command_payload
	)
	if not bool(result.get("success", false)):
		_runtime_rejections += 1
	_send_runtime_result(peer_id, operation_id, result)
	var after_report: Dictionary = _t1_runtime.get_report()
	var after_revision := int(Dictionary(after_report.get("runtime_state", {})).get("generation", 0))
	if after_revision > before_revision:
		_broadcast_runtime_snapshot("RUNTIME_MUTATION")


func create_construction_runtime_snapshot() -> Dictionary:
	if _t1_runtime == null:
		return {}
	var report: Dictionary = _t1_runtime.get_report()
	return RuntimeSnapshotScript.create(
		String(report.get("construct_id", "")),
		_authority_epoch,
		_server_tick,
		Dictionary(report.get("runtime_state", {}))
	)


func _send_runtime_result(peer_id: String, operation_id: String, result: Dictionary) -> bool:
	var sent := _send_on_channel(
		peer_id,
		RUNTIME_RESULT_MESSAGE,
		{
			"operation_id": operation_id,
			"status": String(result.get("status", "REJECTED")),
			"error_code": String(result.get("error_code", "")),
			"result": result.duplicate(true),
		},
		RealtimeChannelPolicy.CONTROL,
		"RELIABLE_ORDERED"
	)
	if sent:
		_runtime_results += 1
	return sent


func _send_runtime_snapshot(peer_id: String, reason: String) -> bool:
	var snapshot: Dictionary = create_construction_runtime_snapshot()
	var validation: Dictionary = RuntimeSnapshotScript.validate(snapshot)
	if not bool(validation.get("success", false)):
		return false
	# T1A.6 intentionally sends the full low-rate runtime state over the existing
	# reliable RESYNC channel. A future scale checkpoint may introduce deltas or
	# periodic unreliable snapshots, but correctness cannot depend on a later event.
	var sent := _send_on_channel(
		peer_id,
		RUNTIME_SNAPSHOT_MESSAGE,
		{"reason": reason, "snapshot": snapshot},
		RealtimeChannelPolicy.RESYNC,
		"RELIABLE_ORDERED"
	)
	if sent:
		_runtime_snapshots += 1
	return sent


func _broadcast_runtime_snapshot(reason: String) -> void:
	for peer_id_value in _peer_to_player.keys():
		_send_runtime_snapshot(String(peer_id_value), reason)


func get_t1a6_runtime_report() -> Dictionary:
	return {
		"schema": T1A6_SCHEMA,
		"runtime_commands": _runtime_commands,
		"runtime_results": _runtime_results,
		"runtime_snapshots": _runtime_snapshots,
		"runtime_rejections": _runtime_rejections,
		"runtime_snapshot": create_construction_runtime_snapshot(),
		"runtime": _t1_runtime.get_report() if _t1_runtime != null else {},
	}
