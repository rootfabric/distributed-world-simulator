extends Node

signal session_ready(runtime)
signal replica_updated(snapshot: Dictionary)
signal item_graph_updated(snapshot: Dictionary)
signal construction_updated(bundle: Dictionary)
signal connection_failed(error_code: String, details: Dictionary)
signal server_disconnected(report: Dictionary)
signal prediction_updated(predicted_state: Dictionary, presentation_state: Dictionary, report: Dictionary)

const Boundary = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const Port = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
const Replica = preload("res://scripts/runtime/host_client/multiplayer_gameplay_replica_store.gd")
const Support = preload("res://scripts/runtime/networked_gameplay/m3/m3_process_support.gd")
const RuntimeIdentity = preload("res://scripts/network/observability/network_runtime_identity.gd")
const ProtocolManifest = preload("res://scripts/network/observability/network_protocol_manifest.gd")
const CompatibilityHandshake = preload("res://scripts/network/observability/network_compatibility_handshake.gd")
const TelemetryCollector = preload("res://scripts/network/observability/network_telemetry_collector.gd")
const ConditionSimulatorPort = preload("res://scripts/network/conditions/network_condition_simulator_port.gd")
const ConditionProfileStore = preload("res://scripts/network/conditions/network_condition_profile_store.gd")
const RealtimeChannelPolicy = preload("res://scripts/network/realtime/realtime_channel_policy.gd")
const PlayerInputBatch = preload("res://scripts/runtime/networked_gameplay/contracts/player_input_batch.gd")
const CanonicalItemGraphDelta = preload("res://scripts/runtime/networked_gameplay/contracts/canonical_item_graph_delta.gd")
const CompactGameplaySnapshot = preload("res://scripts/runtime/networked_gameplay/contracts/compact_gameplay_snapshot.gd")
const InputSequence = preload("res://scripts/network/simulation/input_sequence.gd")
const ClientPredictionReconciler = preload("res://scripts/network/prediction/client_prediction_reconciler.gd")
const ConstructionReplica = preload("res://scripts/construction/multiplayer/construction_multiplayer_replica.gd")

const SCHEMA := "planet_simulator.m3_graphical_client_runtime.v1"
const NX2_INPUT_SEND_INTERVAL_MS := 33
const NX4_INPUT_SEND_INTERVAL_SECONDS := 1.0 / 30.0
const SERVER_PEER_ID := "peer/enet/m3-dedicated-server"
const M7_CHECKPOINT := "v16.10.6.1-testing-m7-playable-networked-playground"
const M7_BUILD_ID := "m7-playable-networked-playground"

var _boundary
var _replica
var _configured := false
var _joined := false
var _join_sent := false
var _join_operation_id := ""
var _host := "127.0.0.1"
var _port := 0
var _logical_player_id := "a"
var _transport_session_id := ""
var _player_entity_id := ""
var _ownership_epoch := 0
var _input_sequence := 0
var _result_file := ""
var _connect_timeout_ms := 30000
var _command_timeout_ms := 8000
var _started_ms := 0
var _message_sequence := 0
var _messages_sent := 0
var _messages_received := 0
var _snapshot_updates := 0
var _delta_updates := 0
var _command_results: Dictionary = {}
var _awaited_command_ids: Dictionary = {}
var _async_command_results := 0
var _async_command_rejections := 0
var _debug_logging := false
var _last_debug_report_ms := 0
var _leave_acknowledged := false
var _last_error_code := ""
var _server_disconnects := 0
var _automated_acceptance := false
var _item_graph_snapshot: Dictionary = {}
var _item_snapshot_updates := 0
var _playable_sandbox := false
var _fingerprint: Dictionary = {}
var _protocol_manifest: Dictionary = {}
var _telemetry
var _network_condition_simulator
var _network_condition_profile: Dictionary = {}
var _network_condition_presets_file: String = ConditionProfileStore.DEFAULT_PRESETS_PATH
var _handshake_id := ""
var _handshake_hello: Dictionary = {}
var _handshake_sent := false
var _handshake_verified := false
var _handshake_rejections := 0
var _handshake_rtt_ms := 0.0
var _operation_started_ms: Dictionary = {}
var _operation_types: Dictionary = {}
var _input_history: Array[Dictionary] = []
var _input_batches_sent := 0
var _input_entries_sent := 0
var _input_redundancy_entries_sent := 0
var _input_batches_coalesced := 0
var _input_batch_retransmissions := 0
var _input_history_pruned := 0
var _pending_input_batch_dirty := false
var _pending_input_operation_id := ""
var _last_input_batch_sent_ms := 0
var _movement_acknowledged_by_snapshot := 0
var _item_delta_updates := 0
var _item_delta_rejections := 0
var _item_resync_requests_sent := 0
var _item_resync_pending := false
var _compact_snapshot_updates := 0
var _compact_snapshot_rejections := 0
var _compact_snapshot_clock_updates := 0
var _prediction_reconciler
var _prediction_input_accumulator: float = 0.0
var _prediction_last_network_intent: Dictionary = {}
var _prediction_frames: int = 0
var _prediction_submit_failures: int = 0
var _prediction_advance_failures: int = 0
var _prediction_reconcile_failures: int = 0
var _prediction_updates_emitted: int = 0
var _construction_replica
var _construction_snapshot_updates := 0
var _construction_event_updates := 0
var _construction_rejections := 0

func setup(config: Dictionary) -> Dictionary:
	if _configured: return _failure("M3_CLIENT_ALREADY_CONFIGURED")
	_host = String(config.get("host", "127.0.0.1")).strip_edges()
	_port = int(config.get("port", 0))
	_logical_player_id = String(config.get("logical_player_id", "a")).strip_edges().to_lower()
	_result_file = String(config.get("result_file", "")).strip_edges()
	_connect_timeout_ms = int(config.get("connect_timeout_ms", 30000))
	_command_timeout_ms = int(config.get("command_timeout_ms", 8000))
	_automated_acceptance = bool(config.get("automated_acceptance", false))
	_playable_sandbox = bool(config.get("playable_sandbox", false))
	_debug_logging = bool(config.get("debug_logging", false))
	_join_operation_id = ""
	_handshake_id = ""
	_handshake_hello.clear()
	_handshake_sent = false
	_handshake_verified = false
	_handshake_rejections = 0
	_handshake_rtt_ms = 0.0
	_operation_started_ms.clear()
	_operation_types.clear()
	_input_history.clear()
	_input_batches_sent = 0
	_input_entries_sent = 0
	_input_redundancy_entries_sent = 0
	_input_batches_coalesced = 0
	_input_batch_retransmissions = 0
	_input_history_pruned = 0
	_pending_input_batch_dirty = false
	_pending_input_operation_id = ""
	_last_input_batch_sent_ms = 0
	_movement_acknowledged_by_snapshot = 0
	_item_delta_updates = 0
	_item_delta_rejections = 0
	_item_resync_requests_sent = 0
	_item_resync_pending = false
	_compact_snapshot_updates = 0
	_compact_snapshot_rejections = 0
	_compact_snapshot_clock_updates = 0
	_prediction_reconciler = ClientPredictionReconciler.new()
	_construction_replica = ConstructionReplica.new()
	_construction_snapshot_updates = 0
	_construction_event_updates = 0
	_construction_rejections = 0
	_prediction_input_accumulator = 0.0
	_prediction_last_network_intent.clear()
	_prediction_frames = 0
	_prediction_submit_failures = 0
	_prediction_advance_failures = 0
	_prediction_reconcile_failures = 0
	_prediction_updates_emitted = 0
	if _host.is_empty() or _port < 1 or _port > 65535 or _logical_player_id.is_empty():
		return _failure("INVALID_M3_CLIENT_CONFIGURATION")
	var identity_result: Dictionary = RuntimeIdentity.validate_config(config)
	if not bool(identity_result.get("success", false)):
		return identity_result
	_fingerprint = Dictionary(identity_result.get("details", {}).get("fingerprint", {})).duplicate(true)
	_protocol_manifest = Dictionary(identity_result.get("details", {}).get("protocol_manifest", {})).duplicate(true)
	_telemetry = TelemetryCollector.new()
	var telemetry_setup: Dictionary = _telemetry.configure(
		"client", _fingerprint, int(config.get("telemetry_sample_limit", 512))
	)
	if not bool(telemetry_setup.get("success", false)):
		return telemetry_setup
	_replica = Replica.new()
	var condition_setup: Dictionary = _setup_network_condition_simulator(config)
	if not bool(condition_setup.get("success", false)):
		_cleanup_setup_failure()
		return condition_setup
	_boundary = Boundary.new()
	var configured: Dictionary = _boundary.configure(
		_network_condition_simulator, 524288, 32, 1048576, _telemetry
	)
	if not bool(configured.get("success", false)):
		_cleanup_setup_failure()
		return configured
	_transport_session_id = "transport-session/m3/%s/%d/%d" % [_logical_player_id, OS.get_process_id(), Time.get_ticks_msec()]
	var connected: Dictionary = _boundary.connect_client(
		Support.endpoint(_host, _port, false), SERVER_PEER_ID, _transport_session_id,
		"route/m3/server/%s" % _logical_player_id, 1
	)
	if not bool(connected.get("success", false)):
		_cleanup_setup_failure()
		return connected
	_started_ms = Time.get_ticks_msec(); _configured = true; set_process(true)
	_last_debug_report_ms = _started_ms
	_debug_event("CLIENT_CONNECTING", {"host":_host,"port":_port,"player":_logical_player_id,"transport_session_id":_transport_session_id})
	_write_report("CONNECTING", false)
	return _success()

func _process(_delta: float) -> void:
	if not _configured or _boundary == null: return
	var process_started_us: int = Time.get_ticks_usec()
	_telemetry.increment("client_process_iterations")
	var polled: Dictionary = _boundary.poll_events(128)
	if not bool(polled.get("success", false)):
		_fail_connection(String(polled.get("error_code", "M3_CLIENT_POLL_FAILED"))); return
	var peer_state: String = String(_boundary.get_peer_snapshot(SERVER_PEER_ID).get("state", ""))
	if not _handshake_sent and peer_state == "TRANSPORT_CONNECTED":
		if not _mark_peer_handshaking():
			_fail_connection("NX0_PEER_HANDSHAKING_FAILED")
			return
		_handshake_id = "handshake/m3/%s/%d/%d" % [
			_logical_player_id, OS.get_process_id(), Time.get_ticks_msec()
		]
		_handshake_hello = CompatibilityHandshake.create_hello(
			_handshake_id, _fingerprint, Time.get_ticks_msec()
		)
		if not _send_control("COMPATIBILITY_HELLO", {"hello": _handshake_hello}):
			_fail_connection("NX0_FINGERPRINT_HELLO_SEND_FAILED")
			return
		_handshake_sent = true
		_telemetry.increment("handshake_hello_sent")
	if _handshake_verified and not _join_sent and String(
		_boundary.get_peer_snapshot(SERVER_PEER_ID).get("state", "")
	) == "READY":
		_join_operation_id = Support.transport_bound_operation_id(_logical_player_id, "join", _transport_session_id)
		if _join_operation_id.is_empty():
			_fail_connection("INVALID_M3_JOIN_OPERATION_ID")
			return
		if not _send("JOIN", {"logical_player_id": _logical_player_id, "operation_id": _join_operation_id}):
			_fail_connection("M3_JOIN_SEND_FAILED")
			return
		_join_sent = true
	for event_value in polled.get("details", {}).get("events", []):
		if not event_value is Dictionary: continue
		var event: Dictionary = event_value
		if String(event.get("event_type", "")) == "MESSAGE_RECEIVED":
			_messages_received += 1
			_handle_message(event.get("frame", {}).get("payload", {}))
		elif String(event.get("event_type", "")) == "PEER_DISCONNECTED":
			_server_disconnects += 1
			_joined = false
			_debug_event("SERVER_DISCONNECTED", event)
			_write_report("DISCONNECTED", false)
			server_disconnected.emit(get_report())
	if not _joined and Time.get_ticks_msec() - _started_ms > _connect_timeout_ms:
		_fail_connection("M3_CLIENT_CONNECT_TIMEOUT")
	_flush_pending_input_batch(false)
	_update_runtime_telemetry()
	var process_duration_ms: float = float(Time.get_ticks_usec() - process_started_us) / 1000.0
	_telemetry.observe("client_process_duration_ms", process_duration_ms)
	_telemetry.observe("client_tick_duration_ms", process_duration_ms)
	if _debug_logging and Time.get_ticks_msec() - _last_debug_report_ms >= 2000:
		_last_debug_report_ms = Time.get_ticks_msec()
		_debug_event("CLIENT_HEALTH", {
			"joined":_joined,"messages_sent":_messages_sent,"messages_received":_messages_received,
			"snapshot_updates":_snapshot_updates,"item_updates":_item_snapshot_updates,
			"pending_blocking":_awaited_command_ids.size(),"buffered_results":_command_results.size(),
			"async_results":_async_command_results,"async_rejections":_async_command_rejections,
			"last_error_code":_last_error_code,
		})

func _handle_message(payload: Dictionary) -> void:
	var server_sent_at_ms: int = int(payload.get("server_sent_at_ms", 0))
	var message_type: String = String(payload.get("type", ""))
	if server_sent_at_ms > 0:
		var message_age_ms: float = float(maxi(Time.get_ticks_msec() - server_sent_at_ms, 0))
		_telemetry.observe("server_message_age_ms", message_age_ms)
		if message_type == "GAMEPLAY_SNAPSHOT":
			_telemetry.observe("snapshot_age_ms", message_age_ms)
		elif message_type == "GAMEPLAY_DELTA":
			_telemetry.observe("delta_age_ms", message_age_ms)
		elif message_type == "ITEM_GRAPH_SNAPSHOT":
			_telemetry.observe("item_snapshot_age_ms", message_age_ms)
	match message_type:
		"COMPATIBILITY_ACK": _handle_compatibility_ack(payload)
		"COMPATIBILITY_REJECTED": _handle_compatibility_rejection(payload)
		"JOIN_ACK":
			_observe_operation_latency(String(payload.get("operation_id", "")))
			_handle_join_ack(payload)
		"JOIN_REJECTED":
			_observe_operation_latency(String(payload.get("operation_id", "")))
			_fail_connection(String(payload.get("error_code", "JOIN_REJECTED")), payload)
		"GAMEPLAY_DELTA": _accept_delta(payload.get("delta", {}))
		"GAMEPLAY_SNAPSHOT": _accept_snapshot(payload.get("snapshot", {}))
		"COMPACT_GAMEPLAY_SNAPSHOT": _accept_compact_snapshot(payload.get("snapshot", {}))
		"ITEM_GRAPH_SNAPSHOT": _accept_item_snapshot(payload.get("snapshot", {}))
		"ITEM_GRAPH_DELTA": _accept_item_delta(payload.get("delta", {}))
		"CONSTRUCTION_SNAPSHOT": _accept_construction_snapshot(payload)
		"CONSTRUCTION_EVENT": _accept_construction_event(payload.get("event", {}))
		"COMMAND_RESULT":
			var result_operation_id: String = String(payload.get("operation_id", ""))
			_observe_operation_latency(result_operation_id)
			var item_delta_value = payload.get("item_graph_delta", {})
			if item_delta_value is Dictionary and not Dictionary(item_delta_value).is_empty():
				_accept_item_delta(Dictionary(item_delta_value))
			var operation_id := String(payload.get("operation_id", ""))
			if not operation_id.is_empty() and _awaited_command_ids.has(operation_id):
				_command_results[operation_id] = payload.duplicate(true)
			else:
				_async_command_results += 1
				if String(payload.get("status", "")) != "SUCCEEDED":
					_async_command_rejections += 1
					_last_error_code = String(payload.get("error_code", "ASYNC_COMMAND_REJECTED"))
					_debug_event("ASYNC_COMMAND_REJECTED", payload)
		"LEAVE_ACK":
			_observe_operation_latency(String(payload.get("operation_id", "")))
			_leave_acknowledged = true
			_joined = false
			_write_report("LEFT", true)
		"LEAVE_REJECTED":
			_observe_operation_latency(String(payload.get("operation_id", "")))
			_last_error_code = String(payload.get("error_code", "LEAVE_REJECTED"))
		_: _last_error_code = "UNKNOWN_M3_SERVER_MESSAGE"

func _handle_compatibility_ack(payload: Dictionary) -> void:
	var ack_value = payload.get("ack", {})
	if not ack_value is Dictionary:
		_fail_connection("NX0_INVALID_FINGERPRINT_ACK")
		return
	var ack: Dictionary = ack_value
	var validation: Dictionary = CompatibilityHandshake.validate_client_ack(
		_fingerprint, _handshake_hello, ack
	)
	if not bool(validation.get("success", false)):
		_fail_connection(String(validation.get("error_code", "NX0_FINGERPRINT_ACK_REJECTED")), validation)
		return
	_handshake_verified = true
	_handshake_rtt_ms = float(maxi(
		Time.get_ticks_msec() - int(_handshake_hello.get("client_sent_at_ms", Time.get_ticks_msec())),
		0
	))
	_telemetry.increment("handshake_ack_received")
	_telemetry.observe("handshake_rtt_ms", _handshake_rtt_ms)
	if not _mark_peer_ready():
		_fail_connection("NX0_PEER_READY_FAILED")


func _handle_compatibility_rejection(payload: Dictionary) -> void:
	_handshake_rejections += 1
	_telemetry.increment("handshake_rejections")
	var rejection_value = payload.get("rejection", {})
	if not rejection_value is Dictionary:
		_fail_connection("NX0_INVALID_FINGERPRINT_REJECTION", payload)
		return
	var rejection: Dictionary = rejection_value
	var validation: Dictionary = CompatibilityHandshake.validate_rejection(rejection)
	if not bool(validation.get("success", false)):
		_fail_connection("NX0_INVALID_FINGERPRINT_REJECTION", validation)
		return
	_fail_connection(String(rejection.get("error_code", "NX0_FINGERPRINT_REJECTED")), rejection)


func _handle_join_ack(payload: Dictionary) -> void:
	var player_value = payload.get("player", {})
	if not player_value is Dictionary:
		_fail_connection("INVALID_M3_JOIN_ACK"); return
	var player: Dictionary = player_value
	_player_entity_id = String(player.get("player_entity_id", ""))
	_ownership_epoch = int(player.get("ownership_epoch", 0))
	_adopt_authoritative_input_sequence(int(player.get("last_input_sequence", 0)))
	if _player_entity_id != "player/%s" % _logical_player_id or _ownership_epoch < 1:
		_fail_connection("INVALID_M3_JOIN_IDENTITY", {"player": player}); return
	var accepted: Dictionary = _replica.accept_snapshot(payload.get("snapshot", {}))
	if not bool(accepted.get("success", false)):
		_fail_connection(String(accepted.get("error_code", "M3_JOIN_SNAPSHOT_REJECTED"))); return
	_snapshot_updates += 1
	_accept_item_snapshot(payload.get("item_graph_snapshot", {}))
	_initialize_prediction_from_snapshot(_replica.get_snapshot())
	_joined = true; _last_error_code = ""; _write_report("READY", false)
	_debug_event("CLIENT_READY", {"player_entity_id":_player_entity_id,"ownership_epoch":_ownership_epoch})
	replica_updated.emit(_replica.get_snapshot()); session_ready.emit(self)

func _accept_snapshot(snapshot: Dictionary) -> void:
	var accepted: Dictionary = _replica.accept_snapshot(snapshot)
	if not bool(accepted.get("success", false)):
		_last_error_code = String(accepted.get("error_code", "M3_SNAPSHOT_REJECTED")); return
	if not bool(accepted.get("details", {}).get("replay", false)): _snapshot_updates += 1
	_reconcile_prediction_from_snapshot(_replica.get_snapshot())
	_prune_acknowledged_inputs()
	replica_updated.emit(_replica.get_snapshot())

func _accept_compact_snapshot(snapshot: Dictionary) -> void:
	var decoded: Dictionary = CompactGameplaySnapshot.decode(snapshot)
	if not bool(decoded.get("success", false)):
		_compact_snapshot_rejections += 1
		_last_error_code = String(decoded.get("error_code", "COMPACT_GAMEPLAY_SNAPSHOT_REJECTED"))
		return
	var decoded_snapshot: Dictionary = Dictionary(decoded.get("details", {}).get("snapshot", {}))
	var accepted: Dictionary = _replica.accept_snapshot(decoded_snapshot)
	if not bool(accepted.get("success", false)):
		var error_code: String = String(accepted.get("error_code", "M3_COMPACT_SNAPSHOT_REJECTED"))
		if (
			error_code == "MULTIPLAYER_SAME_REVISION_MUTATION"
			and _same_snapshot_state_except_clock(_replica.get_snapshot(), decoded_snapshot)
		):
			_compact_snapshot_clock_updates += 1
			_reconcile_prediction_from_snapshot(decoded_snapshot)
			if _last_error_code == "MULTIPLAYER_SAME_REVISION_MUTATION":
				_last_error_code = ""
			return
		_compact_snapshot_rejections += 1
		_last_error_code = error_code
		return
	if not bool(accepted.get("details", {}).get("replay", false)):
		_snapshot_updates += 1
		_compact_snapshot_updates += 1
	_reconcile_prediction_from_snapshot(_replica.get_snapshot())
	_prune_acknowledged_inputs()
	replica_updated.emit(_replica.get_snapshot())


func _same_snapshot_state_except_clock(current: Dictionary, incoming: Dictionary) -> bool:
	if current.is_empty() or incoming.is_empty():
		return false
	if int(incoming.get("revision", -1)) != int(current.get("revision", -2)):
		return false
	if int(incoming.get("server_tick", -1)) <= int(current.get("server_tick", -1)):
		return false
	var current_state: Dictionary = current.duplicate(true)
	var incoming_state: Dictionary = incoming.duplicate(true)
	for key in ["server_tick", "checksum"]:
		current_state.erase(key)
		incoming_state.erase(key)
	return current_state == incoming_state


func _accept_delta(delta: Dictionary) -> void:
	var accepted: Dictionary = _replica.accept_delta(delta)
	if not bool(accepted.get("success", false)):
		_last_error_code = String(accepted.get("error_code", "M3_DELTA_REJECTED")); return
	if not bool(accepted.get("details", {}).get("replay", false)): _delta_updates += 1
	replica_updated.emit(_replica.get_snapshot())

func move_nonblocking(delta_x: float, delta_z: float) -> Dictionary:
	if not is_ready(): return _failure("M3_CLIENT_NOT_READY")
	_input_sequence = InputSequence.next(_input_sequence)
	var operation_id := "operation/m3/%s/move/%d/%d" % [_logical_player_id, OS.get_process_id(), _input_sequence]
	var sent := _send("MOVE", {
		"logical_player_id": _logical_player_id,
		"ownership_epoch": _ownership_epoch,
		"input_sequence": _input_sequence,
		"delta_x": delta_x,
		"delta_z": delta_z,
		"operation_id": operation_id,
	})
	return _success({"operation_id": operation_id, "input_sequence": _input_sequence}) if sent else _failure("M3_MOVE_SEND_FAILED")


func move_blocking(delta_x: float, delta_z: float) -> Dictionary:
	if not is_ready(): return _failure("M3_CLIENT_NOT_READY")
	_input_sequence = InputSequence.next(_input_sequence)
	var operation_id := "operation/m3/%s/move/%d/%d" % [_logical_player_id, OS.get_process_id(), _input_sequence]
	_command_results.erase(operation_id)
	_awaited_command_ids[operation_id] = true
	if not _send("MOVE", {
		"logical_player_id": _logical_player_id,
		"ownership_epoch": _ownership_epoch,
		"input_sequence": _input_sequence,
		"delta_x": delta_x,
		"delta_z": delta_z,
		"operation_id": operation_id,
	}):
		_awaited_command_ids.erase(operation_id)
		return _failure("M3_MOVE_SEND_FAILED")
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= _command_timeout_ms:
		_poll_blocking_once()
		_flush_pending_input_batch(false)
		if _command_results.has(operation_id):
			var result: Dictionary = _command_results[operation_id]; _command_results.erase(operation_id); _awaited_command_ids.erase(operation_id)
			if String(result.get("status", "")) != "SUCCEEDED": return _failure(String(result.get("error_code", "M3_MOVE_REJECTED")), result)
			return _success({"operation_id": operation_id, "result": result})
		OS.delay_msec(2)
	_awaited_command_ids.erase(operation_id)
	_discard_operation_timer(operation_id)
	return _failure("M3_MOVE_TIMEOUT")


func submit_movement_intent_nonblocking(intent: Dictionary, client_tick: int = 0) -> Dictionary:
	if not is_ready():
		return _failure("M7_CLIENT_NOT_READY")
	_input_sequence = InputSequence.next(_input_sequence)
	var operation_id: String = "operation/m7/%s/input/%d/%d" % [
		_logical_player_id, OS.get_process_id(), _input_sequence
	]
	var resolved_client_tick: int = client_tick
	if resolved_client_tick < 1 and _prediction_reconciler != null and _prediction_reconciler.is_configured():
		resolved_client_tick = _prediction_reconciler.get_prediction_tick() + 1
	if resolved_client_tick < 1:
		resolved_client_tick = _input_sequence
	if _prediction_reconciler != null and _prediction_reconciler.is_configured():
		var prediction_input: Dictionary = _prediction_reconciler.set_input(_input_sequence, intent)
		if not bool(prediction_input.get("success", false)):
			_prediction_submit_failures += 1
			return prediction_input
	var sent: bool = _queue_input_batch(intent, operation_id, _input_sequence, false, resolved_client_tick)
	if not sent:
		_prediction_submit_failures += 1
	return _success({
		"operation_id": operation_id,
		"input_sequence": _input_sequence,
		"expect_result": false,
	}) if sent else _failure("M7_PLAYER_INPUT_SEND_FAILED")


func submit_movement_intent_blocking(intent: Dictionary) -> Dictionary:
	if not is_ready():
		return _failure("M7_CLIENT_NOT_READY")
	_input_sequence = InputSequence.next(_input_sequence)
	var target_sequence: int = _input_sequence
	var operation_id: String = "operation/m7/%s/input/%d/%d" % [
		_logical_player_id, OS.get_process_id(), target_sequence
	]
	_command_results.erase(operation_id)
	_awaited_command_ids[operation_id] = true
	var prediction_tick: int = (
		_prediction_reconciler.get_prediction_tick() + 1
		if _prediction_reconciler != null and _prediction_reconciler.is_configured()
		else target_sequence
	)
	if _prediction_reconciler != null and _prediction_reconciler.is_configured():
		var prediction_input: Dictionary = _prediction_reconciler.set_input(target_sequence, intent)
		if not bool(prediction_input.get("success", false)):
			_prediction_submit_failures += 1
			_awaited_command_ids.erase(operation_id)
			return prediction_input
	if not _queue_input_batch(intent, operation_id, target_sequence, true, prediction_tick):
		_prediction_submit_failures += 1
		_awaited_command_ids.erase(operation_id)
		return _failure("M7_PLAYER_INPUT_SEND_FAILED")
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= _command_timeout_ms:
		_poll_blocking_once()
		_flush_pending_input_batch(false)
		if _command_results.has(operation_id):
			var result: Dictionary = _command_results[operation_id]
			_command_results.erase(operation_id)
			_awaited_command_ids.erase(operation_id)
			return _failure(String(result.get("error_code", "M7_PLAYER_INPUT_REJECTED")), result)
		var player: Dictionary = get_player(_logical_player_id)
		if _sequence_acknowledges(int(player.get("last_input_sequence", 0)), target_sequence):
			_awaited_command_ids.erase(operation_id)
			_movement_acknowledged_by_snapshot += 1
			return _success({
				"operation_id": operation_id,
				"input_sequence": target_sequence,
				"acknowledged_by": "AUTHORITATIVE_SNAPSHOT",
			})
		OS.delay_msec(2)
	_awaited_command_ids.erase(operation_id)
	return _failure("M7_PLAYER_INPUT_TIMEOUT")


func _queue_input_batch(
	intent: Dictionary,
	operation_id: String,
	input_sequence: int,
	force_send: bool,
	client_tick: int = 0
) -> bool:
	var canonical_intent: Dictionary = {
		"move_x": float(intent.get("move_x", 0.0)),
		"move_z": float(intent.get("move_z", 0.0)),
		"look_yaw": float(intent.get("look_yaw", 0.0)),
		"look_pitch": float(intent.get("look_pitch", 0.0)),
		"jump_pressed": bool(intent.get("jump_pressed", false)),
		"sprint": bool(intent.get("sprint", false)),
		"delta_seconds": float(intent.get("delta_seconds", 1.0 / 60.0)),
	}
	var entry: Dictionary = {
		"input_sequence": input_sequence,
		"operation_id": operation_id,
		"client_tick": client_tick if client_tick > 0 else input_sequence,
		"client_sent_at_ms": Time.get_ticks_msec(),
		"intent": canonical_intent,
	}
	_input_history = PlayerInputBatch.append_to_history(_input_history, entry)
	if _pending_input_batch_dirty:
		_input_batches_coalesced += 1
	_pending_input_batch_dirty = true
	_pending_input_operation_id = operation_id
	return _flush_pending_input_batch(force_send)


func _flush_pending_input_batch(force_send: bool) -> bool:
	if _input_history.is_empty() or _pending_input_operation_id.is_empty():
		return true
	var latest_sequence: int = int(_input_history.back().get("input_sequence", 0))
	var acknowledged_sequence: int = int(get_player(_logical_player_id).get("last_input_sequence", 0))
	if not _pending_input_batch_dirty and _sequence_acknowledges(acknowledged_sequence, latest_sequence):
		return true
	var retransmission: bool = not _pending_input_batch_dirty
	var now_ms: int = Time.get_ticks_msec()
	if not force_send and _last_input_batch_sent_ms > 0 and now_ms - _last_input_batch_sent_ms < NX2_INPUT_SEND_INTERVAL_MS:
		return true
	var batch: Dictionary = PlayerInputBatch.create(
		"input-batch/m7/%s/%d/%d" % [_logical_player_id, OS.get_process_id(), latest_sequence],
		_logical_player_id,
		_ownership_epoch,
		_input_history,
		_pending_input_operation_id
	)
	var sent: bool = _send_on_channel(
		"PLAYER_INPUT_BATCH",
		{"batch": batch},
		RealtimeChannelPolicy.INPUT,
		"UNRELIABLE_SEQUENCED",
		false
	)
	if sent:
		_input_batches_sent += 1
		if retransmission:
			_input_batch_retransmissions += 1
		_input_entries_sent += _input_history.size()
		_input_redundancy_entries_sent += maxi(_input_history.size() - 1, 0)
		_pending_input_batch_dirty = false
		_last_input_batch_sent_ms = now_ms
	return sent


func _prune_acknowledged_inputs() -> void:
	if _input_history.is_empty():
		return
	var acknowledged_sequence: int = int(get_player(_logical_player_id).get("last_input_sequence", 0))
	while (
		not _input_history.is_empty()
		and _sequence_acknowledges(
			acknowledged_sequence, int(_input_history.front().get("input_sequence", 0))
		)
	):
		_input_history.pop_front()
		_input_history_pruned += 1
	if _input_history.is_empty():
		_pending_input_batch_dirty = false
		_pending_input_operation_id = ""
	else:
		_pending_input_operation_id = String(_input_history.back().get("operation_id", ""))


func _sequence_acknowledges(acknowledged_sequence: int, target_sequence: int) -> bool:
	if not InputSequence.is_valid(acknowledged_sequence) or not InputSequence.is_valid(target_sequence):
		return false
	return acknowledged_sequence == target_sequence \
		or InputSequence.is_newer(acknowledged_sequence, target_sequence)


func _adopt_authoritative_input_sequence(authoritative_sequence: int) -> void:
	if not InputSequence.is_valid(authoritative_sequence):
		return
	if _input_sequence == 0 or InputSequence.is_newer(authoritative_sequence, _input_sequence):
		_input_sequence = authoritative_sequence


func advance_local_prediction(intent: Dictionary, frame_delta_seconds: float) -> Dictionary:
	if not is_ready():
		return _failure("M7_CLIENT_NOT_READY")
	if _prediction_reconciler == null or not _prediction_reconciler.is_configured():
		_initialize_prediction_from_snapshot(get_snapshot())
	if _prediction_reconciler == null or not _prediction_reconciler.is_configured():
		return _failure("NX4_PREDICTION_NOT_READY")
	var canonical: Dictionary = _canonical_prediction_intent(intent)
	_prediction_input_accumulator += maxf(frame_delta_seconds, 0.0)
	var changed: bool = not _same_prediction_intent(_prediction_last_network_intent, canonical)
	var should_submit: bool = (
		_prediction_last_network_intent.is_empty()
		or changed
		or _prediction_input_accumulator >= NX4_INPUT_SEND_INTERVAL_SECONDS
	)
	var submission: Dictionary = _success()
	var submission_attempted: bool = false
	if should_submit:
		submission_attempted = true
		submission = submit_movement_intent_nonblocking(
			canonical,
			_prediction_reconciler.get_prediction_tick() + 1
		)
		if bool(submission.get("success", false)):
			_prediction_input_accumulator = 0.0
			_prediction_last_network_intent = canonical.duplicate(true)
		elif String(submission.get("error_code", "")) != "M7_PLAYER_INPUT_SEND_FAILED":
			return submission
	var advanced: Dictionary = _prediction_reconciler.advance_frame(frame_delta_seconds)
	if not bool(advanced.get("success", false)):
		_prediction_advance_failures += 1
		return advanced
	_prediction_frames += 1
	var predicted_state: Dictionary = _prediction_reconciler.get_predicted_state()
	var presentation_state: Dictionary = _prediction_reconciler.sample_presentation(frame_delta_seconds)
	_prediction_updates_emitted += 1
	prediction_updated.emit(
		predicted_state.duplicate(true),
		presentation_state.duplicate(true),
		_prediction_reconciler.get_report()
	)
	return _success({
		"submission_attempted": submission_attempted,
		"submission": submission,
		"predicted_state": predicted_state,
		"presentation_state": presentation_state,
		"prediction": _prediction_reconciler.get_report(),
	})

func get_predicted_local_player() -> Dictionary:
	return (
		_prediction_reconciler.get_predicted_state()
		if _prediction_reconciler != null and _prediction_reconciler.is_configured()
		else get_local_player_record()
	)

func get_prediction_presentation_player(frame_delta_seconds: float = 0.0) -> Dictionary:
	return (
		_prediction_reconciler.sample_presentation(frame_delta_seconds)
		if _prediction_reconciler != null and _prediction_reconciler.is_configured()
		else get_local_player_record()
	)

func is_prediction_ready() -> bool:
	return _prediction_reconciler != null and _prediction_reconciler.is_configured()

func _initialize_prediction_from_snapshot(snapshot: Dictionary) -> void:
	if _prediction_reconciler == null or snapshot.is_empty():
		return
	var local_player: Dictionary = _player_from_snapshot(snapshot, _logical_player_id)
	if local_player.is_empty():
		return
	var configured: Dictionary = _prediction_reconciler.configure(
		local_player,
		int(snapshot.get("server_tick", 0))
	)
	if not bool(configured.get("success", false)):
		_prediction_reconcile_failures += 1

func _reconcile_prediction_from_snapshot(snapshot: Dictionary) -> void:
	if _prediction_reconciler == null:
		return
	if not _prediction_reconciler.is_configured():
		_initialize_prediction_from_snapshot(snapshot)
		return
	var local_player: Dictionary = _player_from_snapshot(snapshot, _logical_player_id)
	if local_player.is_empty():
		return
	var reconciled: Dictionary = _prediction_reconciler.reconcile(
		local_player,
		int(snapshot.get("server_tick", 0))
	)
	if not bool(reconciled.get("success", false)):
		_prediction_reconcile_failures += 1
		return
	var details: Dictionary = Dictionary(reconciled.get("details", {}))
	_telemetry.observe("prediction_error_m", float(details.get("prediction_error_m", 0.0)))
	_telemetry.observe("prediction_replayed_ticks", float(details.get("replayed_ticks", 0)))
	if String(details.get("correction_mode", "NONE")) != "NONE":
		_telemetry.increment("prediction_corrections")
	if bool(details.get("hard_correction", false)):
		_telemetry.increment("prediction_hard_corrections")
	var predicted_state: Dictionary = _prediction_reconciler.get_predicted_state()
	var presentation_state: Dictionary = _prediction_reconciler.sample_presentation(0.0)
	prediction_updated.emit(
		predicted_state.duplicate(true),
		presentation_state.duplicate(true),
		_prediction_reconciler.get_report()
	)

func _player_from_snapshot(snapshot: Dictionary, logical_player_id: String) -> Dictionary:
	for player_value in snapshot.get("players", []):
		if player_value is Dictionary and String(player_value.get("logical_player_id", "")) == logical_player_id:
			return Dictionary(player_value).duplicate(true)
	return {}

func _canonical_prediction_intent(intent: Dictionary) -> Dictionary:
	return {
		"move_x": float(intent.get("move_x", 0.0)),
		"move_z": float(intent.get("move_z", 0.0)),
		"look_yaw": float(intent.get("look_yaw", 0.0)),
		"look_pitch": float(intent.get("look_pitch", 0.0)),
		"jump_pressed": bool(intent.get("jump_pressed", false)),
		"sprint": bool(intent.get("sprint", false)),
		"delta_seconds": 1.0 / 60.0,
	}

func _same_prediction_intent(left: Dictionary, right: Dictionary) -> bool:
	if left.is_empty() or right.is_empty():
		return false
	if bool(left.get("jump_pressed", false)) or bool(right.get("jump_pressed", false)):
		return false
	return is_equal_approx(float(left.get("move_x", 0.0)), float(right.get("move_x", 0.0))) \
		and is_equal_approx(float(left.get("move_z", 0.0)), float(right.get("move_z", 0.0))) \
		and is_equal_approx(float(left.get("look_yaw", 0.0)), float(right.get("look_yaw", 0.0))) \
		and is_equal_approx(float(left.get("look_pitch", 0.0)), float(right.get("look_pitch", 0.0))) \
		and bool(left.get("sprint", false)) == bool(right.get("sprint", false))

func submit_player_state_nonblocking(_player_state: Dictionary, _delta_seconds: float) -> Dictionary:
	return _failure("M7_CLIENT_AUTHORITATIVE_STATE_FORBIDDEN")

func submit_player_state_blocking(_player_state: Dictionary, _delta_seconds: float) -> Dictionary:
	return _failure("M7_CLIENT_AUTHORITATIVE_STATE_FORBIDDEN")


func set_presentation_blocking(orientation_yaw: float, flashlight_enabled: bool) -> Dictionary:
	if not is_ready(): return _failure("M3_CLIENT_NOT_READY")
	var operation_id := "operation/m3/%s/presentation/%d/%d" % [_logical_player_id, OS.get_process_id(), Time.get_ticks_msec()]
	_command_results.erase(operation_id)
	_awaited_command_ids[operation_id] = true
	if not _send("PRESENTATION", {
		"logical_player_id": _logical_player_id,
		"ownership_epoch": _ownership_epoch,
		"orientation_yaw": orientation_yaw,
		"flashlight_enabled": flashlight_enabled,
		"operation_id": operation_id,
	}):
		_awaited_command_ids.erase(operation_id)
		return _failure("M3_PRESENTATION_SEND_FAILED")
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= _command_timeout_ms:
		_poll_blocking_once()
		if _command_results.has(operation_id):
			var result: Dictionary = _command_results[operation_id]; _command_results.erase(operation_id); _awaited_command_ids.erase(operation_id)
			if String(result.get("status", "")) != "SUCCEEDED": return _failure(String(result.get("error_code", "M3_PRESENTATION_REJECTED")), result)
			return _success({"operation_id": operation_id, "result": result})
		OS.delay_msec(2)
	_awaited_command_ids.erase(operation_id)
	_discard_operation_timer(operation_id)
	return _failure("M3_PRESENTATION_TIMEOUT")

func _accept_item_snapshot(snapshot: Dictionary) -> void:
	if snapshot.is_empty(): return
	_item_graph_snapshot = snapshot.duplicate(true)
	_item_snapshot_updates += 1
	_item_resync_pending = false
	if _last_error_code.begins_with("ITEM_GRAPH_"):
		_last_error_code = ""
	item_graph_updated.emit(_item_graph_snapshot.duplicate(true))

func _accept_item_delta(delta: Dictionary) -> void:
	if delta.is_empty() or _item_graph_snapshot.is_empty():
		_item_delta_rejections += 1
		_last_error_code = "ITEM_GRAPH_DELTA_WITHOUT_BASE"
		_request_item_graph_resync(_last_error_code)
		return
	var applied: Dictionary = CanonicalItemGraphDelta.apply(_item_graph_snapshot, delta)
	if not bool(applied.get("success", false)):
		_item_delta_rejections += 1
		_last_error_code = String(applied.get("error_code", "ITEM_GRAPH_DELTA_REJECTED"))
		_request_item_graph_resync(_last_error_code)
		return
	_item_graph_snapshot = Dictionary(applied.get("details", {}).get("snapshot", {})).duplicate(true)
	_item_delta_updates += 1
	if _last_error_code.begins_with("ITEM_GRAPH_"):
		_last_error_code = ""
	item_graph_updated.emit(_item_graph_snapshot.duplicate(true))


func _request_item_graph_resync(reason: String) -> void:
	if _item_resync_pending or not _joined:
		return
	var operation_id: String = "operation/nx2/%s/item-resync/%d" % [
		_logical_player_id, Time.get_ticks_msec()
	]
	if _send_on_channel(
		"ITEM_GRAPH_RESYNC_REQUEST",
		{
			"operation_id": operation_id,
			"logical_player_id": _logical_player_id,
			"current_revision": int(_item_graph_snapshot.get("revision", 0)),
			"current_checksum": String(_item_graph_snapshot.get("checksum", "")),
			"reason": reason,
		},
		RealtimeChannelPolicy.RESYNC,
		"RELIABLE_ORDERED",
		false
	):
		_item_resync_pending = true
		_item_resync_requests_sent += 1

func execute_item_command_blocking(
	command_type: String,
	payload: Dictionary,
	operation_id: String = "",
	ownership_epoch_override: int = 0
) -> Dictionary:
	if not is_ready(): return _failure("M4_CLIENT_NOT_READY")
	var command_epoch := ownership_epoch_override if ownership_epoch_override > 0 else _ownership_epoch
	var op := operation_id if not operation_id.is_empty() else "operation/m4/%s/%s/%d/%d" % [_logical_player_id, command_type.replace(".", "-"), OS.get_process_id(), Time.get_ticks_msec()]
	_command_results.erase(op)
	_awaited_command_ids[op] = true
	if not _send_on_channel("ITEM_COMMAND", {"logical_player_id":_logical_player_id,"ownership_epoch":command_epoch,"operation_id":op,"command_type":command_type,"payload":payload.duplicate(true)}, RealtimeChannelPolicy.ITEM, "RELIABLE_ORDERED", true):
		_awaited_command_ids.erase(op)
		return _failure("M4_ITEM_COMMAND_SEND_FAILED")
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= _command_timeout_ms:
		_poll_blocking_once()
		if _command_results.has(op):
			var result: Dictionary = _command_results[op]; _command_results.erase(op); _awaited_command_ids.erase(op)
			if String(result.get("status", "")) != "SUCCEEDED": return _failure(String(result.get("error_code", "M4_ITEM_COMMAND_REJECTED")), result)
			return _success({"operation_id":op,"result":result})
		OS.delay_msec(2)
	_awaited_command_ids.erase(op)
	_discard_operation_timer(op)
	return _failure("M4_ITEM_COMMAND_TIMEOUT")

func get_item_graph_snapshot() -> Dictionary: return _item_graph_snapshot.duplicate(true)

func _accept_construction_snapshot(payload: Dictionary) -> void:
	if _construction_replica == null:
		_construction_rejections += 1
		_last_error_code = "CONSTRUCTION_REPLICA_NOT_READY"
		return
	var bundle_value = payload.get("state_bundle", {})
	if not bundle_value is Dictionary:
		_construction_rejections += 1
		_last_error_code = "INVALID_CONSTRUCTION_SNAPSHOT"
		return
	var initialized: Dictionary = _construction_replica.initialize(Dictionary(bundle_value), int(payload.get("last_event_index", -1)))
	if not bool(initialized.get("success", false)):
		_construction_rejections += 1
		_last_error_code = String(initialized.get("error_code", "CONSTRUCTION_SNAPSHOT_REJECTED"))
		return
	_construction_snapshot_updates += 1
	construction_updated.emit(_construction_replica.get_bundle())

func _accept_construction_event(event_value) -> void:
	if _construction_replica == null or not event_value is Dictionary:
		_construction_rejections += 1
		_last_error_code = "INVALID_CONSTRUCTION_EVENT"
		return
	var applied: Dictionary = _construction_replica.apply_event(Dictionary(event_value))
	if not bool(applied.get("success", false)):
		_construction_rejections += 1
		_last_error_code = String(applied.get("error_code", "CONSTRUCTION_EVENT_REJECTED"))
		return
	_construction_event_updates += 1
	construction_updated.emit(_construction_replica.get_bundle())

func execute_construction_command_blocking(command: Dictionary, operation_id: String = "") -> Dictionary:
	if not is_ready(): return _failure("M3_CONSTRUCTION_CLIENT_NOT_READY")
	var op := operation_id if not operation_id.is_empty() else "operation/m3/%s/construction/%d" % [_logical_player_id, Time.get_ticks_msec()]
	_command_results.erase(op)
	_awaited_command_ids[op] = true
	if not _send_on_channel("CONSTRUCTION_COMMAND", {"operation_id": op, "command": command.duplicate(true)}, RealtimeChannelPolicy.CONTROL, "RELIABLE_ORDERED", true):
		_awaited_command_ids.erase(op)
		return _failure("M3_CONSTRUCTION_COMMAND_SEND_FAILED")
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= _command_timeout_ms:
		_poll_blocking_once()
		if _command_results.has(op):
			var result: Dictionary = _command_results[op]; _command_results.erase(op); _awaited_command_ids.erase(op)
			if String(result.get("status", "")) != "SUCCEEDED": return _failure(String(result.get("error_code", "M3_CONSTRUCTION_COMMAND_REJECTED")), result)
			return _success({"operation_id": op, "result": result})
		OS.delay_msec(2)
	_awaited_command_ids.erase(op)
	_discard_operation_timer(op)
	return _failure("M3_CONSTRUCTION_COMMAND_TIMEOUT")

func get_construction_bundle() -> Dictionary: return _construction_replica.get_bundle() if _construction_replica != null else {}

func request_graceful_leave(timeout_ms: int = 2500) -> Dictionary:
	if not _joined: return _success({"already_left": true})
	_leave_acknowledged = false
	var operation_id := Support.transport_bound_operation_id(_logical_player_id, "leave", _transport_session_id)
	if operation_id.is_empty():
		return _failure("INVALID_M3_LEAVE_OPERATION_ID")
	if not _send("LEAVE", {"logical_player_id": _logical_player_id, "operation_id": operation_id}):
		return _failure("M3_LEAVE_SEND_FAILED")
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= timeout_ms:
		_poll_blocking_once()
		if _leave_acknowledged: return _success({"operation_id": operation_id})
		OS.delay_msec(2)
	_discard_operation_timer(operation_id)
	return _failure("M3_LEAVE_TIMEOUT")

func _poll_blocking_once() -> void:
	if _boundary == null: return
	var polled: Dictionary = _boundary.poll_events(128)
	if not bool(polled.get("success", false)): return
	for event_value in polled.get("details", {}).get("events", []):
		if event_value is Dictionary and String(event_value.get("event_type", "")) == "MESSAGE_RECEIVED":
			_messages_received += 1; _handle_message(event_value.get("frame", {}).get("payload", {}))

func _send(message_type: String, data: Dictionary) -> bool:
	return _send_on_channel(
		message_type,
		data,
		RealtimeChannelPolicy.CONTROL,
		"RELIABLE_ORDERED",
		true
	)


func _send_on_channel(
	message_type: String,
	data: Dictionary,
	channel: String,
	delivery_mode: String,
	track_operation: bool
) -> bool:
	if _boundary == null:
		return false
	var payload: Dictionary = data.duplicate(true)
	payload["type"] = message_type
	payload["client_sent_at_ms"] = Time.get_ticks_msec()
	_message_sequence += 1
	payload["client_message_sequence"] = _message_sequence
	var operation_id: String = String(payload.get("operation_id", ""))
	if track_operation and not operation_id.is_empty():
		_operation_started_ms[operation_id] = int(payload["client_sent_at_ms"])
		_operation_types[operation_id] = message_type
	var frame_result: Dictionary = _boundary.create_frame_for_peer(
		SERVER_PEER_ID, channel, Support.MESSAGE_SCHEMA, payload, delivery_mode
	)
	if not bool(frame_result.get("success", false)):
		if track_operation:
			_discard_operation_timer(operation_id)
		return false
	var sent: Dictionary = _boundary.send_to_peer(
		SERVER_PEER_ID, frame_result.get("details", {}).get("frame", {})
	)
	if not bool(sent.get("success", false)):
		if track_operation:
			_discard_operation_timer(operation_id)
		return false
	var flushed: Dictionary = _boundary.flush_outbound(16, SERVER_PEER_ID)
	if not bool(flushed.get("success", false)):
		if track_operation:
			_discard_operation_timer(operation_id)
		return false
	_messages_sent += 1
	return true


func _send_control(message_type: String, data: Dictionary) -> bool:
	if _boundary == null:
		return false
	var payload: Dictionary = data.duplicate(true)
	payload["type"] = message_type
	_message_sequence += 1
	payload["client_message_sequence"] = _message_sequence
	var frame_result: Dictionary = _boundary.create_frame_for_peer(
		SERVER_PEER_ID, RealtimeChannelPolicy.CONTROL, Support.MESSAGE_SCHEMA, payload, "RELIABLE_ORDERED"
	)
	if not bool(frame_result.get("success", false)):
		return false
	var sent: Dictionary = _boundary.send_to_peer(
		SERVER_PEER_ID, frame_result.get("details", {}).get("frame", {})
	)
	if not bool(sent.get("success", false)):
		return false
	var flushed: Dictionary = _boundary.flush_outbound(16, SERVER_PEER_ID)
	if not bool(flushed.get("success", false)):
		return false
	_messages_sent += 1
	return true


func _mark_peer_handshaking() -> bool:
	var result: Dictionary = _boundary.mark_peer_handshaking(SERVER_PEER_ID)
	return bool(result.get("success", false))


func _mark_peer_ready() -> bool:
	for method_name in ["mark_peer_synchronizing", "mark_peer_ready"]:
		var result: Dictionary = _boundary.call(method_name, SERVER_PEER_ID)
		if not bool(result.get("success", false)):
			return false
	return true


func _observe_operation_latency(operation_id: String) -> void:
	if operation_id.is_empty() or not _operation_started_ms.has(operation_id):
		return
	var latency_ms: float = float(maxi(Time.get_ticks_msec() - int(_operation_started_ms[operation_id]), 0))
	var message_type: String = String(_operation_types.get(operation_id, ""))
	_operation_started_ms.erase(operation_id)
	_operation_types.erase(operation_id)
	_telemetry.observe("command_latency_ms", latency_ms)
	match message_type:
		"ITEM_COMMAND": _telemetry.observe("item_command_latency_ms", latency_ms)
		"MOVE", "PLAYER_INPUT": _telemetry.observe("movement_command_latency_ms", latency_ms)
		"PRESENTATION": _telemetry.observe("presentation_command_latency_ms", latency_ms)
		"JOIN": _telemetry.observe("join_latency_ms", latency_ms)
		"LEAVE": _telemetry.observe("leave_latency_ms", latency_ms)


func _discard_operation_timer(operation_id: String) -> void:
	if not operation_id.is_empty():
		_operation_started_ms.erase(operation_id)
		_operation_types.erase(operation_id)


func _update_runtime_telemetry() -> void:
	if _telemetry == null:
		return
	_telemetry.set_gauge("pending_blocking_commands", float(_awaited_command_ids.size()))
	_telemetry.set_gauge("buffered_command_results", float(_command_results.size()))
	_telemetry.set_gauge("pending_operation_timers", float(_operation_started_ms.size()))
	_telemetry.set_gauge("handshake_verified", 1.0 if _handshake_verified else 0.0)
	if _prediction_reconciler != null and _prediction_reconciler.is_configured():
		var prediction_report: Dictionary = _prediction_reconciler.get_report()
		_telemetry.set_gauge("prediction_buffer_size", float(prediction_report.get("history_size", 0)))
		_telemetry.set_gauge("prediction_visual_offset_m", float(prediction_report.get("visual_offset_m", 0.0)))
		_telemetry.set_gauge("prediction_tick", float(prediction_report.get("prediction_tick", 0)))
	var boundary_snapshot: Dictionary = _boundary.get_snapshot() if _boundary != null else {}
	var port_runtime: Dictionary = boundary_snapshot.get("port_runtime", {})
	var peer_statistics: Dictionary = port_runtime.get("peer_statistics", {})
	var server_stats: Dictionary = peer_statistics.get(SERVER_PEER_ID, {})
	if not server_stats.is_empty():
		_telemetry.set_gauge("rtt_ms", float(server_stats.get("rtt_ms", 0)))
		_telemetry.set_gauge("jitter_ms", float(server_stats.get("rtt_variance_ms", 0)))
		_telemetry.set_gauge("packet_loss_percent", float(server_stats.get("packet_loss_percent", 0.0)))


func _telemetry_sample() -> Dictionary:
	if _telemetry == null:
		return {}
	var result: Dictionary = _telemetry.create_sample(Time.get_ticks_msec())
	return Dictionary(result.get("details", {}).get("sample", {})).duplicate(true) if bool(result.get("success", false)) else {}

func get_player(logical_player_id: String) -> Dictionary:
	return _replica.get_player(logical_player_id) if _replica != null else {}
func get_snapshot() -> Dictionary: return _replica.get_snapshot() if _replica != null else {}
func get_local_player_id() -> String: return _logical_player_id
func get_local_player_record() -> Dictionary: return get_player(_logical_player_id)
func get_remote_player_ids() -> Array[String]:
	var ids: Array[String] = []
	for player in get_snapshot().get("players", []):
		var logical_id := String(player.get("logical_player_id", ""))
		if logical_id != _logical_player_id and bool(player.get("connected", false)): ids.append(logical_id)
	return ids
func is_ready() -> bool: return _joined and _replica != null and not _replica.get_snapshot().is_empty()
func is_automated_acceptance() -> bool: return _automated_acceptance

func _cleanup_setup_failure() -> void:
	set_process(false)
	if _boundary != null:
		_boundary.stop()
	elif _network_condition_simulator != null:
		_network_condition_simulator.stop()
	_boundary = null
	_network_condition_simulator = null
	_replica = null


func _setup_network_condition_simulator(config: Dictionary) -> Dictionary:
	_network_condition_presets_file = String(
		config.get("network_condition_presets_file", ConditionProfileStore.DEFAULT_PRESETS_PATH)
	).strip_edges()
	var profile_id: String = String(config.get("network_condition_profile", "LOCAL")).strip_edges().to_upper()
	var loaded: Dictionary = ConditionProfileStore.load_profile(
		profile_id, _network_condition_presets_file
	)
	if not bool(loaded.get("success", false)):
		return loaded
	_network_condition_profile = Dictionary(loaded.get("details", {}).get("profile", {})).duplicate(true)
	_network_condition_simulator = ConditionSimulatorPort.new()
	return _network_condition_simulator.setup(
		Port.new(), _network_condition_profile, _telemetry
	)


func set_network_condition_profile(profile_id: String) -> Dictionary:
	if _network_condition_simulator == null:
		return _failure("NETWORK_CONDITION_SIMULATOR_NOT_READY")
	var loaded: Dictionary = ConditionProfileStore.load_profile(
		profile_id.strip_edges().to_upper(), _network_condition_presets_file
	)
	if not bool(loaded.get("success", false)):
		return loaded
	_network_condition_profile = Dictionary(loaded.get("details", {}).get("profile", {})).duplicate(true)
	return _network_condition_simulator.set_profile(_network_condition_profile)


func trigger_network_lag_spike(direction: String = "BOTH", duration_ms: int = -1) -> Dictionary:
	if _network_condition_simulator == null:
		return _failure("NETWORK_CONDITION_SIMULATOR_NOT_READY")
	return _network_condition_simulator.trigger_lag_spike(direction, duration_ms)


func trigger_network_disconnect_blackout(direction: String = "BOTH", duration_ms: int = -1) -> Dictionary:
	if _network_condition_simulator == null:
		return _failure("NETWORK_CONDITION_SIMULATOR_NOT_READY")
	return _network_condition_simulator.trigger_disconnect_blackout(direction, duration_ms)


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"checkpoint": RuntimeIdentity.CHECKPOINT,
		"build_id": RuntimeIdentity.BUILD_ID,
		"gameplay_checkpoint": M7_CHECKPOINT if _playable_sandbox else Support.CHECKPOINT,
		"gameplay_build_id": M7_BUILD_ID if _playable_sandbox else Support.BUILD_ID,
		"configured": _configured, "joined": _joined, "logical_player_id": _logical_player_id,
		"player_entity_id": _player_entity_id, "ownership_epoch": _ownership_epoch,
		"transport_session_id": _transport_session_id, "join_operation_id": _join_operation_id, "input_sequence": _input_sequence,
		"messages_sent": _messages_sent, "messages_received": _messages_received,
		"snapshot_updates": _snapshot_updates, "delta_updates": _delta_updates,
		"server_disconnects": _server_disconnects, "last_error_code": _last_error_code,
		"display_server": DisplayServer.get_name(), "replica": _replica.get_report() if _replica != null else {},
		"snapshot_checksum": String(get_snapshot().get("checksum", "")),
		"item_graph_checksum": String(_item_graph_snapshot.get("checksum", "")),
		"item_snapshot_updates": _item_snapshot_updates,
		"pending_blocking_command_count": _awaited_command_ids.size(),
		"buffered_command_result_count": _command_results.size(),
		"pending_operation_timer_count": _operation_started_ms.size(),
		"async_command_results": _async_command_results,
		"async_command_rejections": _async_command_rejections,
		"realtime_traffic": {
			"channel_policy": RealtimeChannelPolicy.canonical_policy(),
			"input_batches_sent": _input_batches_sent,
			"input_entries_sent": _input_entries_sent,
			"input_redundancy_entries_sent": _input_redundancy_entries_sent,
			"input_batches_coalesced": _input_batches_coalesced,
			"input_batch_retransmissions": _input_batch_retransmissions,
			"input_history_pruned": _input_history_pruned,
			"pending_input_batch_dirty": _pending_input_batch_dirty,
			"input_send_interval_ms": NX2_INPUT_SEND_INTERVAL_MS,
			"movement_acknowledged_by_snapshot": _movement_acknowledged_by_snapshot,
			"item_delta_updates": _item_delta_updates,
			"item_delta_rejections": _item_delta_rejections,
			"item_resync_requests_sent": _item_resync_requests_sent,
			"item_resync_pending": _item_resync_pending,
			"compact_snapshot_updates": _compact_snapshot_updates,
			"compact_snapshot_rejections": _compact_snapshot_rejections,
			"compact_snapshot_clock_updates": _compact_snapshot_clock_updates,
		},
		"client_prediction": {
			"enabled": _prediction_reconciler != null and _prediction_reconciler.is_configured(),
			"frames": _prediction_frames,
			"submit_failures": _prediction_submit_failures,
			"advance_failures": _prediction_advance_failures,
			"reconcile_failures": _prediction_reconcile_failures,
			"updates_emitted": _prediction_updates_emitted,
			"runtime": (
				_prediction_reconciler.get_report()
				if _prediction_reconciler != null else {}
			),
		},
		"direct_authority_references": 0, "direct_domain_references": 0,
		"resolved_user_data_dir": OS.get_user_data_dir(),
		"automated_acceptance": _automated_acceptance,
		"playable_sandbox": _playable_sandbox,
		"network_fingerprint": _fingerprint.duplicate(true),
		"network_protocol_manifest": _protocol_manifest.duplicate(true),
		"compatibility_handshake": {
			"handshake_id": _handshake_id,
			"hello_sent": _handshake_sent,
			"verified": _handshake_verified,
			"rejections": _handshake_rejections,
			"rtt_ms": _handshake_rtt_ms,
		},
		"network_conditions": (
			_network_condition_simulator.get_runtime_snapshot()
			if _network_condition_simulator != null else {}
		),
		"network_telemetry": _telemetry_sample(),
	}

func stop() -> Dictionary:
	set_process(false)
	_operation_started_ms.clear()
	_operation_types.clear()
	var leave_result := request_graceful_leave(1000) if _joined else _success()
	if _boundary != null: _boundary.stop()
	_boundary = null; _network_condition_simulator = null; _joined = false; _configured = false; _write_report("STOPPED", bool(leave_result.get("success", false)))
	return leave_result

func _fail_connection(error_code: String, details: Dictionary = {}) -> void:
	_operation_started_ms.clear()
	_operation_types.clear()
	_last_error_code = error_code
	_debug_event("CLIENT_CONNECTION_FAILED", {"error_code":error_code,"details":details})
	_write_report("FAILED", false, details)
	connection_failed.emit(error_code, details.duplicate(true))
	set_process(false)

func _debug_event(event_name: String, details: Dictionary = {}) -> void:
	if not _debug_logging:
		return
	print("[m7_client] %s" % JSON.stringify({
		"event":event_name,"process_id":OS.get_process_id(),"player":_logical_player_id,
		"time_msec":Time.get_ticks_msec(),"details":details,
	}, "", true, true))

func _write_report(state: String, passed: bool, details: Dictionary = {}) -> void:
	if _result_file.is_empty(): return
	var report := get_report(); report["state"] = state; report["passed"] = passed; report["details"] = details.duplicate(true); report["process_id"] = OS.get_process_id()
	Support.write(_result_file, report)

func _exit_tree() -> void:
	if _configured: stop()
func _success(details: Dictionary = {}) -> Dictionary: return {"success": true, "error_code": "", "details": details.duplicate(true)}
func _failure(error_code: String, details: Dictionary = {}) -> Dictionary: return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
