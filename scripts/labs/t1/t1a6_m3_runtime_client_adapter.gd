extends "res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd"

signal construction_runtime_updated(snapshot: Dictionary)

const ReplicaStoreScript = preload("res://scripts/runtime/host_client/construction_runtime_replica_store.gd")
const PresenterScript = preload("res://scripts/labs/t1/t1_d0_runtime_presenter.gd")

const T1A6_SCHEMA: String = "planet_simulator.t1a6_m3_runtime_client_adapter.v1"
const RUNTIME_COMMAND_MESSAGE: String = "CONSTRUCTION_RUNTIME_COMMAND"
const RUNTIME_RESULT_MESSAGE: String = "CONSTRUCTION_RUNTIME_COMMAND_RESULT"
const RUNTIME_SNAPSHOT_MESSAGE: String = "CONSTRUCTION_RUNTIME_SNAPSHOT"

var _construction_replica
var _construction_presenter
var _runtime_command_results: Dictionary = {}
var _runtime_awaited: Dictionary = {}
var _runtime_snapshots_received: int = 0
var _runtime_snapshot_rejections: int = 0
var _runtime_results_received: int = 0
var _presentation_enabled: bool = true


func setup(config: Dictionary) -> Dictionary:
	_construction_replica = ReplicaStoreScript.new()
	_presentation_enabled = bool(config.get("t1a6_presentation", true))
	if _presentation_enabled:
		_construction_presenter = PresenterScript.new()
		add_child(_construction_presenter)
		var presenter_setup: Dictionary = _construction_presenter.setup()
		if not bool(presenter_setup.get("success", false)):
			return presenter_setup
	var base_setup: Dictionary = super.setup(config)
	if not bool(base_setup.get("success", false)):
		return base_setup
	return _success()


func _handle_message(payload: Dictionary) -> void:
	var message_type := String(payload.get("type", ""))
	if message_type == RUNTIME_SNAPSHOT_MESSAGE:
		_accept_construction_runtime_snapshot(Dictionary(payload.get("snapshot", {})))
		return
	if message_type == RUNTIME_RESULT_MESSAGE:
		var operation_id := String(payload.get("operation_id", ""))
		_observe_operation_latency(operation_id)
		_runtime_results_received += 1
		if _runtime_awaited.has(operation_id):
			_runtime_command_results[operation_id] = payload.duplicate(true)
		return
	super._handle_message(payload)


func _accept_construction_runtime_snapshot(snapshot: Dictionary) -> void:
	if _construction_replica == null:
		_runtime_snapshot_rejections += 1
		return
	var accepted: Dictionary = _construction_replica.accept_snapshot(snapshot)
	if not bool(accepted.get("success", false)):
		_runtime_snapshot_rejections += 1
		return
	_runtime_snapshots_received += 1
	var details: Dictionary = Dictionary(accepted.get("details", {}))
	if bool(details.get("accepted", false)) and _construction_presenter != null:
		_construction_presenter.apply_snapshot(_construction_replica.get_snapshot(), false)
	construction_runtime_updated.emit(_construction_replica.get_snapshot())


func execute_construction_runtime_blocking(
	kind: String,
	action_kind: String,
	operation_id: String,
	expected_revision: int,
	payload: Dictionary = {}
) -> Dictionary:
	if not is_ready():
		return _failure("T1A6_CLIENT_NOT_READY")
	if operation_id.strip_edges().is_empty():
		return _failure("T1A6_OPERATION_ID_REQUIRED")
	_runtime_command_results.erase(operation_id)
	_runtime_awaited[operation_id] = true
	var sent := _send_on_channel(
		RUNTIME_COMMAND_MESSAGE,
		{
			"operation_id": operation_id,
			"kind": kind.to_upper(),
			"action_kind": action_kind.to_upper(),
			"expected_revision": expected_revision,
			"payload": payload.duplicate(true),
		},
		RealtimeChannelPolicy.CONTROL,
		"RELIABLE_ORDERED",
		true
	)
	if not sent:
		_runtime_awaited.erase(operation_id)
		return _failure("T1A6_RUNTIME_COMMAND_SEND_FAILED")
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= _command_timeout_ms:
		_poll_blocking_once()
		if _runtime_command_results.has(operation_id):
			var wire: Dictionary = _runtime_command_results[operation_id]
			_runtime_command_results.erase(operation_id)
			_runtime_awaited.erase(operation_id)
			if String(wire.get("status", "")) != "SUCCEEDED":
				return _failure(String(wire.get("error_code", "T1A6_RUNTIME_COMMAND_REJECTED")), wire)
			return _success({"operation_id": operation_id, "result": Dictionary(wire.get("result", {})).duplicate(true)})
		OS.delay_msec(2)
	_runtime_awaited.erase(operation_id)
	_discard_operation_timer(operation_id)
	return _failure("T1A6_RUNTIME_COMMAND_TIMEOUT")


func get_construction_runtime_snapshot() -> Dictionary:
	return _construction_replica.get_snapshot() if _construction_replica != null else {}


func get_construction_runtime_subject(runtime_id: String) -> Dictionary:
	return _construction_replica.get_subject(runtime_id) if _construction_replica != null else {}


func get_t1a6_presentation_report() -> Dictionary:
	return _construction_presenter.get_report() if _construction_presenter != null else {}


func force_t1a6_presentation_sync() -> void:
	if _construction_presenter != null:
		_construction_presenter.force_sync()


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	report["t1a6"] = {
		"schema": T1A6_SCHEMA,
		"runtime_snapshots_received": _runtime_snapshots_received,
		"runtime_snapshot_rejections": _runtime_snapshot_rejections,
		"runtime_results_received": _runtime_results_received,
		"runtime_replica": _construction_replica.get_report() if _construction_replica != null else {},
		"presentation": get_t1a6_presentation_report(),
	}
	return report
