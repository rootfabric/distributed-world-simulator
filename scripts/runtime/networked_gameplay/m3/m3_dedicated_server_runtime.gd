extends Node

signal ready_for_clients(report: Dictionary)

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Boundary = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const Port = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
const Service = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
const Support = preload("res://scripts/runtime/networked_gameplay/m3/m3_process_support.gd")
const RecoveryRepository = preload("res://scripts/persistence/authoritative_recovery_repository.gd")
const RecoveryCoordinator = preload("res://scripts/persistence/authoritative_recovery_coordinator.gd")
const M6AuthorityAdapter = preload("res://scripts/runtime/networked_gameplay/m6/m6_dedicated_gameplay_authority_adapter.gd")
const M6ReplayOutbox = preload("res://scripts/runtime/networked_gameplay/m6/m6_durable_replay_outbox.gd")
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
const FixedTickScheduler = preload("res://scripts/network/simulation/fixed_tick_scheduler.gd")
const FixedTickInputBuffer = preload("res://scripts/network/simulation/fixed_tick_input_buffer.gd")

const SCHEMA := "planet_simulator.m3_dedicated_server_runtime.v1"
const M6_CHECKPOINT := "v16.10.5-persistence-m6-dedicated-recovery"
const M6_BUILD_ID := "m6-dedicated-persistence-recovery"
const M7_CHECKPOINT := "v16.10.6.1-testing-m7-playable-networked-playground"
const M7_BUILD_ID := "m7-playable-networked-playground"
const M7_MOVEMENT_CHECKPOINT_INTERVAL_MS := 1500
const NX2_MOVEMENT_SNAPSHOT_INTERVAL_MS := 50
const NX3_FIXED_TICK_RATE_HZ := 60
const NX3_FIXED_TICK_DELTA_SECONDS := 1.0 / 60.0
const NX3_MOVEMENT_SNAPSHOT_INTERVAL_TICKS := 3

var _boundary
var _service
var _configured := false
var _host := "127.0.0.1"
var _port := 0
var _result_file := ""
var _authority_owner_id := "simulation/m3/dedicated"
var _authority_epoch := 1
var _peer_to_player: Dictionary = {}
var _peer_to_session: Dictionary = {}
var _joins := 0
var _leaves := 0
var _moves := 0
var _presentation_updates := 0
var _rejections := 0
var _broadcasts := 0
var _messages_sent := 0
var _messages_received := 0
var _last_error_code := ""
var _last_two_connected_checksum := ""
var _persistence_root := ""
var _persistence_enabled := false
var _recovery_repository
var _recovery_coordinator
var _recovery_authority
var _replay_outbox
var _checkpoint_generation := 0
var _recovered := false
var _recovery_source := ""
var _last_checkpoint_operation_id := ""
var _persistence_failures := 0
var _last_persistence_error_details: Dictionary = {}
var _durable_commits := 0
var _fatal_persistence_failure := false
var _playable_sandbox := false
var _movement_checkpoint_dirty := false
var _last_movement_checkpoint_ms := 0
var _movement_checkpoints := 0
var _movement_commands_since_checkpoint := 0
var _debug_logging := false
var _last_debug_report_ms := 0
var _fixed_tick_scheduler
var _peer_input_buffers: Dictionary = {}
var _server_tick := 0
var _fixed_ticks_simulated := 0
var _fixed_tick_catch_up_batches := 0
var _fixed_tick_failures := 0
var _input_queue_stale_drops := 0
var _input_hold_expirations := 0
var _last_fixed_tick_duration_ms := 0.0
var _last_movement_snapshot_tick := 0
var _fingerprint: Dictionary = {}
var _protocol_manifest: Dictionary = {}
var _telemetry
var _network_condition_simulator
var _network_condition_profile: Dictionary = {}
var _network_condition_presets_file: String = ConditionProfileStore.DEFAULT_PRESETS_PATH
var _peer_compatibility: Dictionary = {}
var _handshake_attempts := 0
var _handshake_accepts := 0
var _handshake_rejections := 0
var _handshake_replays := 0
var _last_handshake_error_code := ""
var _movement_snapshot_dirty := false
var _movement_batches_received := 0
var _movement_inputs_received := 0
var _movement_inputs_applied := 0
var _movement_inputs_redundant := 0
var _movement_inputs_rejected := 0
var _last_movement_rejection_error_code := ""
var _last_movement_rejection_stage := ""
var _movement_results_suppressed := 0
var _movement_deltas_suppressed := 0
var _movement_full_snapshots_suppressed := 0
var _movement_snapshots_published := 0
var _item_graph_deltas_published := 0
var _item_graph_delta_build_failures := 0
var _item_graph_full_snapshots_published := 0
var _item_graph_resync_requests := 0
var _compact_movement_snapshots_published := 0
var _movement_snapshot_retransmit_requests := 0
var _movement_snapshot_enqueue_failures := 0
var _compact_movement_snapshot_failures := 0

func setup(config: Dictionary) -> Dictionary:
	if _configured:
		return _failure("M3_SERVER_ALREADY_CONFIGURED")
	_host = String(config.get("host", "127.0.0.1")).strip_edges()
	_port = int(config.get("port", 0))
	_result_file = String(config.get("result_file", "")).strip_edges()
	_authority_owner_id = String(config.get("authority_owner_id", _authority_owner_id)).strip_edges()
	_authority_epoch = int(config.get("authority_epoch", 1))
	_persistence_root = String(config.get("persistence_root", "")).strip_edges()
	_persistence_enabled = not _persistence_root.is_empty()
	_playable_sandbox = bool(config.get("playable_sandbox", false))
	_debug_logging = bool(config.get("debug_logging", false))
	if _host.is_empty() or _port < 1 or _port > 65535 or _authority_owner_id.is_empty() or _authority_epoch < 1:
		return _failure("INVALID_M3_SERVER_CONFIGURATION")
	var identity_result: Dictionary = RuntimeIdentity.validate_config(config)
	if not bool(identity_result.get("success", false)):
		return identity_result
	_fingerprint = Dictionary(identity_result.get("details", {}).get("fingerprint", {})).duplicate(true)
	_protocol_manifest = Dictionary(identity_result.get("details", {}).get("protocol_manifest", {})).duplicate(true)
	_telemetry = TelemetryCollector.new()
	var telemetry_setup: Dictionary = _telemetry.configure(
		"server", _fingerprint, int(config.get("telemetry_sample_limit", 512))
	)
	if not bool(telemetry_setup.get("success", false)):
		return telemetry_setup
	_peer_compatibility.clear()
	_handshake_attempts = 0
	_handshake_accepts = 0
	_handshake_rejections = 0
	_handshake_replays = 0
	_last_handshake_error_code = ""
	_service = Service.new()
	var service_setup: Dictionary = _service.setup(_authority_owner_id, _authority_epoch, 0, {
		"profile": Service.PROFILE_MULTIPLAYER_CORE,
		"topology_adapter": "ENET",
		"region_id": "region/m3/single-server",
		"playable_sandbox": _playable_sandbox,
		"fixed_tick_authority": true,
	})
	if not bool(service_setup.get("success", false)):
		return service_setup
	if _persistence_enabled:
		var recovery_setup := _setup_recovery()
		if not bool(recovery_setup.get("success", false)):
			_service.shutdown()
			_service = null
			return recovery_setup
	_fixed_tick_scheduler = FixedTickScheduler.new()
	_server_tick = int(_service.get_report().get("server_tick", 0))
	var fixed_tick_setup: Dictionary = _fixed_tick_scheduler.configure(
		NX3_FIXED_TICK_RATE_HZ, FixedTickScheduler.DEFAULT_MAX_CATCH_UP_TICKS, _server_tick
	)
	if not bool(fixed_tick_setup.get("success", false)):
		_cleanup_setup_failure()
		return fixed_tick_setup
	_peer_input_buffers.clear()
	_last_movement_snapshot_tick = _server_tick
	var condition_setup: Dictionary = _setup_network_condition_simulator(config)
	if not bool(condition_setup.get("success", false)):
		_cleanup_setup_failure()
		return condition_setup
	_boundary = Boundary.new()
	var configured: Dictionary = _boundary.configure(
		_network_condition_simulator, 524288, 64, 2097152, _telemetry
	)
	if not bool(configured.get("success", false)):
		_cleanup_setup_failure()
		return configured
	var started: Dictionary = _boundary.start_server(Support.endpoint(_host, _port, true))
	if not bool(started.get("success", false)):
		_cleanup_setup_failure()
		return started
	_configured = true
	_last_movement_checkpoint_ms = Time.get_ticks_msec()
	_last_movement_snapshot_tick = _server_tick
	_last_debug_report_ms = _last_movement_checkpoint_ms
	set_process(true)
	_debug_event("SERVER_READY", {"host":_host,"port":_port,"persistence_root":_persistence_root,"recovered":_recovered})
	_write_report("READY", false)
	ready_for_clients.emit(get_report())
	return _success({"host": _host, "port": _port})

func _process(delta: float) -> void:
	if not _configured or _boundary == null or _fatal_persistence_failure:
		return
	var process_started_us: int = Time.get_ticks_usec()
	_telemetry.increment("server_process_iterations")
	var polled: Dictionary = _boundary.poll_events(128)
	if not bool(polled.get("success", false)):
		_last_error_code = String(polled.get("error_code", "M3_SERVER_POLL_FAILED"))
		_write_report("FAILED", false)
		return
	for event_value in polled.get("details", {}).get("events", []):
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value
		var event_type := String(event.get("event_type", ""))
		var peer_id := String(event.get("peer_id", ""))
		var session_id := String(event.get("session_id", ""))
		if event_type == "MESSAGE_RECEIVED":
			_messages_received += 1
			_handle_message(peer_id, session_id, event.get("frame", {}).get("payload", {}))
		elif event_type == "PEER_DISCONNECTED":
			_handle_disconnect(peer_id, session_id)
	_advance_fixed_simulation(delta)
	_maybe_publish_movement_snapshot()
	_maybe_persist_movement_checkpoint()
	_update_runtime_telemetry()
	var process_duration_ms: float = float(Time.get_ticks_usec() - process_started_us) / 1000.0
	_telemetry.observe("server_process_duration_ms", process_duration_ms)
	if _debug_logging and Time.get_ticks_msec() - _last_debug_report_ms >= 2000:
		_last_debug_report_ms = Time.get_ticks_msec()
		_debug_event("SERVER_HEALTH", {
			"connected_peers":_peer_to_player.size(),"moves":_moves,"rejections":_rejections,
			"messages_received":_messages_received,"messages_sent":_messages_sent,
			"checkpoint_generation":_checkpoint_generation,"movement_dirty":_movement_checkpoint_dirty,
			"movement_commands_since_checkpoint":_movement_commands_since_checkpoint,
			"last_error_code":_last_error_code,
		})

func _handle_message(peer_id: String, session_id: String, payload: Dictionary) -> void:
	var handled_started_us: int = Time.get_ticks_usec()
	var client_sent_at_ms: int = int(payload.get("client_sent_at_ms", 0))
	if client_sent_at_ms > 0:
		_telemetry.observe("input_age_ms", float(maxi(Time.get_ticks_msec() - client_sent_at_ms, 0)))
	var message_type: String = String(payload.get("type", ""))
	if message_type == "COMPATIBILITY_HELLO":
		_handle_compatibility_hello(peer_id, session_id, payload)
	elif not _is_peer_compatible(peer_id, session_id):
		_reject_pre_handshake_message(peer_id, payload)
	else:
		match message_type:
			"JOIN": _handle_join(peer_id, session_id, payload)
			"MOVE": _handle_move(peer_id, session_id, payload)
			"PLAYER_INPUT": _handle_player_input(peer_id, session_id, payload)
			"PLAYER_INPUT_BATCH": _handle_player_input_batch(peer_id, session_id, payload)
			"PLAYER_STATE": _handle_player_state_rejected(peer_id, session_id, payload)
			"PRESENTATION": _handle_presentation(peer_id, session_id, payload)
			"ITEM_COMMAND": _handle_item_command(peer_id, session_id, payload)
			"ITEM_GRAPH_RESYNC_REQUEST": _handle_item_graph_resync_request(peer_id, session_id, payload)
			"LEAVE": _handle_leave(peer_id, session_id, payload)
			_: _send_result(peer_id, String(payload.get("operation_id", "")), "UNKNOWN", _failure("UNKNOWN_M3_MESSAGE_TYPE"))
	_telemetry.observe("server_message_processing_ms", float(Time.get_ticks_usec() - handled_started_us) / 1000.0)


func _handle_compatibility_hello(peer_id: String, session_id: String, payload: Dictionary) -> void:
	_handshake_attempts += 1
	_telemetry.increment("handshake_attempts")
	var hello_value = payload.get("hello", {})
	var hello: Dictionary = Dictionary(hello_value).duplicate(true) if hello_value is Dictionary else {}
	var received_at_ms: int = Time.get_ticks_msec()
	var evaluation: Dictionary = CompatibilityHandshake.evaluate_server(
		_fingerprint, hello, received_at_ms
	)
	if not bool(evaluation.get("success", false)):
		_reject_handshake(
			peer_id,
			String(hello.get("handshake_id", "")),
			String(evaluation.get("error_code", "FINGERPRINT_MISMATCH"))
		)
		return
	var already_compatible: bool = _is_peer_compatible(peer_id, session_id)
	if not already_compatible:
		var handshaking: Dictionary = _boundary.mark_peer_handshaking(peer_id)
		if not bool(handshaking.get("success", false)) and String(
			handshaking.get("error_code", "")
		) != "INVALID_PEER_STATE_TRANSITION":
			_reject_handshake(peer_id, String(hello.get("handshake_id", "")), "PEER_HANDSHAKE_STATE_FAILED")
			return
	var ack: Dictionary = Dictionary(evaluation.get("details", {}).get("ack", {})).duplicate(true)
	if not _send_control(peer_id, "COMPATIBILITY_ACK", {"ack": ack}):
		_reject_handshake(peer_id, String(hello.get("handshake_id", "")), "FINGERPRINT_ACK_SEND_FAILED")
		return
	if already_compatible:
		_handshake_replays += 1
		_telemetry.increment("handshake_replays")
		return
	_peer_compatibility[peer_id] = {
		"session_id": session_id,
		"handshake_id": String(hello.get("handshake_id", "")),
		"verified_at_ms": Time.get_ticks_msec(),
		"client_fingerprint": Dictionary(hello.get("fingerprint", {})).duplicate(true),
	}
	_handshake_accepts += 1
	_telemetry.increment("handshake_accepts")
	for method_name in ["mark_peer_synchronizing", "mark_peer_ready"]:
		var transition: Dictionary = _boundary.call(method_name, peer_id)
		if not bool(transition.get("success", false)):
			_last_error_code = "NX0_PEER_READY_FAILED"
			return


func _reject_handshake(peer_id: String, handshake_id: String, error_code: String) -> void:
	_handshake_rejections += 1
	_last_handshake_error_code = error_code
	_telemetry.increment("handshake_rejections")
	var safe_handshake_id: String = handshake_id
	if not CompatibilityHandshake.is_valid_handshake_id(safe_handshake_id):
		safe_handshake_id = "handshake/rejected/%s" % peer_id.sha256_text().left(16)
	var rejection: Dictionary = CompatibilityHandshake.create_rejection(
		safe_handshake_id, error_code, Time.get_ticks_msec()
	)
	_send_control(peer_id, "COMPATIBILITY_REJECTED", {"rejection": rejection})


func _reject_pre_handshake_message(peer_id: String, payload: Dictionary) -> void:
	var handshake_id: String = "handshake/prejoin/%s" % peer_id.sha256_text().left(16)
	_reject_handshake(peer_id, handshake_id, "FINGERPRINT_REQUIRED")
	_debug_event("PRE_HANDSHAKE_MESSAGE_REJECTED", {
		"peer_id": peer_id,
		"message_type": String(payload.get("type", "")),
	})


func _is_peer_compatible(peer_id: String, session_id: String) -> bool:
	var value = _peer_compatibility.get(peer_id)
	return value is Dictionary and String(value.get("session_id", "")) == session_id

func _handle_join(peer_id: String, session_id: String, payload: Dictionary) -> void:
	var logical_id := String(payload.get("logical_player_id", "")).strip_edges().to_lower()
	var operation_id := String(payload.get("operation_id", "")).strip_edges()
	if logical_id.is_empty() or not _is_canonical_operation_id(operation_id):
		_send(peer_id, "JOIN_REJECTED", {"operation_id": operation_id, "error_code": "INVALID_JOIN_PAYLOAD"})
		return
	var result: Dictionary = _service.join(logical_id, session_id, operation_id)
	if not _persist_command_result(operation_id, "JOIN", logical_id, result):
		_send(peer_id, "JOIN_REJECTED", {"operation_id": operation_id, "error_code": "M6_DURABLE_COMMIT_FAILED"})
		return
	if not bool(result.get("success", false)):
		_rejections += 1
		var rejection_sent := _send(peer_id, "JOIN_REJECTED", {"operation_id": operation_id, "error_code": String(result.get("error_code", "JOIN_REJECTED"))})
		if rejection_sent:
			_mark_operation_delivered(operation_id)
		_write_report("READY", false)
		return
	_peer_to_player[peer_id] = logical_id
	_peer_to_session[peer_id] = session_id
	_peer_input_buffers.erase(peer_id)
	_ensure_input_buffer(peer_id, logical_id)
	_debug_event("PLAYER_JOINED", {"peer_id":peer_id,"session_id":session_id,"logical_player_id":logical_id})
	var replay := _is_replay_result(result)
	if not replay:
		_joins += 1
	var join_sent := _send_on_channel(peer_id, "JOIN_ACK", {
		"operation_id": operation_id,
		"player": result.get("details", {}).get("player", {}),
		"snapshot": result.get("details", {}).get("snapshot", {}),
		"item_graph_snapshot": _service.create_canonical_item_graph_snapshot(),
	}, RealtimeChannelPolicy.RESYNC, "RELIABLE_ORDERED")
	if join_sent:
		_item_graph_full_snapshots_published += 1
	if not replay:
		_broadcast_delta(result.get("details", {}).get("delta", {}), peer_id)
		_broadcast_snapshot("PLAYER_JOINED")
		_broadcast_item_snapshot("PLAYER_JOINED", peer_id)
		_capture_two_connected_checksum()
	if join_sent:
		_mark_operation_delivered(operation_id)
	_write_report("READY", false)

func _handle_move(peer_id: String, session_id: String, payload: Dictionary) -> void:
	if not _peer_to_player.has(peer_id) or String(_peer_to_session.get(peer_id, "")) != session_id:
		_send_result(peer_id, String(payload.get("operation_id", "")), "MOVE", _failure("STALE_TRANSPORT_SESSION"))
		return
	var logical_id := String(_peer_to_player.get(peer_id, ""))
	var operation_id := String(payload.get("operation_id", "")).strip_edges()
	if not _is_canonical_operation_id(operation_id):
		_reject_uncommitted_command(
			peer_id, operation_id, "MOVE",
			"OPERATION_ID_REQUIRED" if operation_id.is_empty() else "INVALID_OPERATION_ID"
		)
		return
	var result: Dictionary = _service.move_player(
		logical_id,
		session_id,
		int(payload.get("ownership_epoch", 0)),
		int(payload.get("input_sequence", 0)),
		float(payload.get("delta_x", 0.0)),
		float(payload.get("delta_z", 0.0)),
		operation_id
	)
	if not _persist_command_result(operation_id, "MOVE", logical_id, result):
		_send_result(peer_id, operation_id, "MOVE", _failure("M6_DURABLE_COMMIT_FAILED"))
		return
	var result_sent := _send_result(peer_id, operation_id, "MOVE", result)
	if bool(result.get("success", false)):
		if not _is_replay_result(result):
			_moves += 1
			_broadcast_delta(result.get("details", {}).get("delta", {}))
			_broadcast_snapshot("PLAYER_MOVED")
			_capture_two_connected_checksum()
	else:
		_rejections += 1
	if result_sent:
		_mark_operation_delivered(operation_id)
	_write_report("READY", false)


func _handle_player_input(peer_id: String, session_id: String, payload: Dictionary) -> void:
	# Compatibility path for older probes. Production NX2 clients send PLAYER_INPUT_BATCH.
	var intent_value = payload.get("intent", {})
	if not intent_value is Dictionary:
		_reject_uncommitted_command(peer_id, String(payload.get("operation_id", "")), "PLAYER_INPUT", "MOVEMENT_INTENT_REQUIRED")
		return
	var input_entry: Dictionary = {
		"input_sequence": int(payload.get("input_sequence", 0)),
		"operation_id": String(payload.get("operation_id", "")),
		"client_tick": int(payload.get("client_tick", payload.get("input_sequence", 0))),
		"client_sent_at_ms": int(payload.get("client_sent_at_ms", 0)),
		"intent": Dictionary(intent_value).duplicate(true),
	}
	var batch: Dictionary = PlayerInputBatch.create(
		"input-batch/legacy/%s/%d" % [peer_id.sha256_text().left(12), int(input_entry["input_sequence"])],
		String(payload.get("logical_player_id", _peer_to_player.get(peer_id, ""))),
		int(payload.get("ownership_epoch", 0)),
		[input_entry],
		String(payload.get("operation_id", ""))
	)
	_handle_player_input_batch(peer_id, session_id, {"batch": batch})


func _handle_player_input_batch(peer_id: String, session_id: String, payload: Dictionary) -> void:
	_movement_batches_received += 1
	if not _peer_to_player.has(peer_id) or String(_peer_to_session.get(peer_id, "")) != session_id:
		_send_result(peer_id, "operation/nx3/stale/%s" % peer_id.sha256_text().left(12), "PLAYER_INPUT", _failure("STALE_TRANSPORT_SESSION"))
		return
	var batch_value = payload.get("batch", {})
	if not batch_value is Dictionary:
		_send_result(peer_id, "operation/nx3/invalid/%s" % peer_id.sha256_text().left(12), "PLAYER_INPUT", _failure("PLAYER_INPUT_BATCH_REQUIRED"))
		return
	var batch: Dictionary = Dictionary(batch_value).duplicate(true)
	var batch_check: Dictionary = PlayerInputBatch.validate(batch)
	if not bool(batch_check.get("success", false)):
		var invalid_operation_id: String = _latest_batch_operation_id(batch)
		_last_movement_rejection_error_code = String(batch_check.get("error_code", "INVALID_PLAYER_INPUT_BATCH"))
		_last_movement_rejection_stage = "BATCH_VALIDATE"
		_send_result(peer_id, invalid_operation_id, "PLAYER_INPUT", _failure(_last_movement_rejection_error_code))
		_movement_inputs_rejected += 1
		return
	var logical_id: String = String(_peer_to_player.get(peer_id, ""))
	if String(batch.get("logical_player_id", "")) != logical_id:
		_last_movement_rejection_error_code = "PLAYER_INPUT_BATCH_PLAYER_MISMATCH"
		_last_movement_rejection_stage = "PLAYER_MATCH"
		_send_result(peer_id, _latest_batch_operation_id(batch), "PLAYER_INPUT", _failure(_last_movement_rejection_error_code))
		_movement_inputs_rejected += 1
		return
	var player: Dictionary = _service.get_player(logical_id)
	if int(batch.get("ownership_epoch", 0)) != int(player.get("ownership_epoch", 0)):
		_last_movement_rejection_error_code = "STALE_PLAYER_OWNERSHIP_EPOCH"
		_last_movement_rejection_stage = "OWNERSHIP"
		_send_result(peer_id, _latest_batch_operation_id(batch), "PLAYER_INPUT", _failure(_last_movement_rejection_error_code))
		_movement_inputs_rejected += 1
		return
	var expanded_result: Dictionary = PlayerInputBatch.expand_inputs(batch)
	if not bool(expanded_result.get("success", false)):
		_last_movement_rejection_error_code = String(expanded_result.get("error_code", "PLAYER_INPUT_BATCH_EXPAND_FAILED"))
		_last_movement_rejection_stage = "BATCH_EXPAND"
		_send_result(peer_id, _latest_batch_operation_id(batch), "PLAYER_INPUT", expanded_result)
		_movement_inputs_rejected += 1
		return
	var buffer = _ensure_input_buffer(peer_id, logical_id)
	if buffer == null:
		_last_movement_rejection_error_code = "NX3_INPUT_BUFFER_SETUP_FAILED"
		_last_movement_rejection_stage = "INPUT_BUFFER"
		_send_result(peer_id, _latest_batch_operation_id(batch), "PLAYER_INPUT", _failure(_last_movement_rejection_error_code))
		_movement_inputs_rejected += 1
		return
	var inputs: Array = expanded_result.get("details", {}).get("inputs", [])
	_movement_inputs_received += inputs.size()
	var accepted_any: bool = false
	var redundant_any: bool = false
	for input_value in inputs:
		var input: Dictionary = Dictionary(input_value).duplicate(true)
		var queued: Dictionary = buffer.enqueue(input, _server_tick)
		if bool(queued.get("success", false)):
			if bool(queued.get("details", {}).get("accepted", false)):
				accepted_any = true
			else:
				redundant_any = true
				_movement_inputs_redundant += 1
		else:
			_movement_inputs_rejected += 1
			_last_movement_rejection_error_code = String(queued.get("error_code", "NX3_INPUT_QUEUE_REJECTED"))
			_last_movement_rejection_stage = "INPUT_QUEUE"
			_send_result(peer_id, String(input.get("operation_id", _latest_batch_operation_id(batch))), "PLAYER_INPUT", queued)
	if redundant_any and not accepted_any:
		_movement_snapshot_dirty = true
		_movement_snapshot_retransmit_requests += 1

func _ensure_input_buffer(peer_id: String, logical_id: String):
	if _peer_input_buffers.has(peer_id):
		return _peer_input_buffers[peer_id]
	var buffer = FixedTickInputBuffer.new()
	var setup_result: Dictionary = buffer.configure(_last_processed_input_sequence(logical_id))
	if not bool(setup_result.get("success", false)):
		return null
	_peer_input_buffers[peer_id] = buffer
	return buffer

func _advance_fixed_simulation(frame_delta_seconds: float) -> void:
	if _fixed_tick_scheduler == null or _service == null:
		return
	var scheduled: Dictionary = _fixed_tick_scheduler.advance(frame_delta_seconds)
	if not bool(scheduled.get("success", false)):
		_fixed_tick_failures += 1
		_last_error_code = String(scheduled.get("error_code", "NX3_FIXED_TICK_SCHEDULER_FAILED"))
		return
	var tick_count: int = int(scheduled.get("details", {}).get("tick_count", 0))
	if tick_count > 1:
		_fixed_tick_catch_up_batches += 1
	var first_tick: int = int(scheduled.get("details", {}).get("first_tick", _server_tick))
	for offset in range(tick_count):
		_run_fixed_tick(first_tick + offset)

func _run_fixed_tick(server_tick: int) -> void:
	var started_us: int = Time.get_ticks_usec()
	var advanced: Dictionary = _service.advance_fixed_server_tick(server_tick)
	if not bool(advanced.get("success", false)):
		_fixed_tick_failures += 1
		_last_error_code = String(advanced.get("error_code", "NX3_SERVER_TICK_ADVANCE_FAILED"))
		return
	_server_tick = server_tick
	_fixed_ticks_simulated += 1
	var peer_ids: Array[String] = []
	for peer_id_value in _peer_to_player.keys():
		peer_ids.append(String(peer_id_value))
	peer_ids.sort()
	for peer_id in peer_ids:
		var logical_id: String = String(_peer_to_player.get(peer_id, ""))
		var session_id: String = String(_peer_to_session.get(peer_id, ""))
		if logical_id.is_empty() or session_id.is_empty():
			continue
		var buffer = _ensure_input_buffer(peer_id, logical_id)
		if buffer == null:
			continue
		var before_report: Dictionary = buffer.get_report(server_tick)
		var consumed: Dictionary = buffer.consume_for_tick(server_tick)
		if not bool(consumed.get("success", false)):
			_fixed_tick_failures += 1
			continue
		var sequence: int = int(consumed.get("details", {}).get("input_sequence", 0))
		if sequence < 1:
			continue
		var intent: Dictionary = Dictionary(consumed.get("details", {}).get("intent", {})).duplicate(true)
		intent["delta_seconds"] = NX3_FIXED_TICK_DELTA_SECONDS
		var player: Dictionary = _service.get_player(logical_id)
		var result: Dictionary = _service.simulate_fixed_movement_tick(
			logical_id,
			session_id,
			int(player.get("ownership_epoch", 0)),
			sequence,
			intent,
			NX3_FIXED_TICK_DELTA_SECONDS
		)
		var consumed_new: bool = bool(consumed.get("details", {}).get("consumed_new_input", false))
		if not bool(result.get("success", false)):
			_fixed_tick_failures += 1
			if consumed_new:
				_movement_inputs_rejected += 1
				_last_movement_rejection_error_code = String(result.get("error_code", "NX3_FIXED_MOVEMENT_REJECTED"))
				_last_movement_rejection_stage = "FIXED_TICK_SIMULATION"
				_send_result(peer_id, String(consumed.get("details", {}).get("operation_id", "")), "PLAYER_INPUT", result)
			continue
		if consumed_new:
			_moves += 1
			_movement_inputs_applied += 1
			_movement_results_suppressed += 1
			_movement_deltas_suppressed += 1
			_movement_full_snapshots_suppressed += 1
			_movement_commands_since_checkpoint += 1
			_movement_snapshot_dirty = true
		if bool(result.get("details", {}).get("changed", false)):
			_movement_snapshot_dirty = true
			_movement_checkpoint_dirty = true
		var after_report: Dictionary = buffer.get_report(server_tick)
		_input_queue_stale_drops += maxi(
			int(after_report.get("stale_dropped", 0)) - int(before_report.get("stale_dropped", 0)), 0
		)
		_input_hold_expirations += maxi(
			int(after_report.get("hold_expirations", 0)) - int(before_report.get("hold_expirations", 0)), 0
		)
		_telemetry.observe("input_queue_age_ticks", float(consumed.get("details", {}).get("queue_age_ticks", 0)))
	_last_fixed_tick_duration_ms = float(Time.get_ticks_usec() - started_us) / 1000.0
	_telemetry.observe("server_tick_duration_ms", _last_fixed_tick_duration_ms)
	_telemetry.set_gauge("server_tick", float(_server_tick))

func _latest_batch_operation_id(batch: Dictionary) -> String:
	var operation_id: String = String(batch.get("operation_id", ""))
	if _is_canonical_operation_id(operation_id):
		return operation_id
	return "operation/nx2/invalid/%s" % NetworkUtilsScript.canonical_json(batch).sha256_text().left(16)


func _last_processed_input_sequence(logical_id: String) -> int:
	if _service == null:
		return 0
	for player_value in _service.create_snapshot().get("players", []):
		if player_value is Dictionary and String(player_value.get("logical_player_id", "")) == logical_id:
			return int(player_value.get("last_input_sequence", 0))
	return 0


func _maybe_publish_movement_snapshot() -> void:
	if not _movement_snapshot_dirty or _service == null:
		return
	if _server_tick - _last_movement_snapshot_tick < NX3_MOVEMENT_SNAPSHOT_INTERVAL_TICKS:
		return
	_last_movement_snapshot_tick = _server_tick
	var compact_result: Dictionary = CompactGameplaySnapshot.encode(_service.create_snapshot())
	if not bool(compact_result.get("success", false)):
		_compact_movement_snapshot_failures += 1
		_last_error_code = String(compact_result.get("error_code", "COMPACT_GAMEPLAY_SNAPSHOT_BUILD_FAILED"))
		return
	var compact_snapshot: Dictionary = Dictionary(
		compact_result.get("details", {}).get("snapshot", {})
	).duplicate(true)
	var all_enqueued := true
	var target_count := 0
	for peer_id_value in _peer_to_player.keys():
		target_count += 1
		if _send_on_channel(
			String(peer_id_value),
			"COMPACT_GAMEPLAY_SNAPSHOT",
			{"reason": "MOVEMENT_NETWORK_TICK", "snapshot": compact_snapshot},
			RealtimeChannelPolicy.SNAPSHOT,
			"UNRELIABLE_SEQUENCED"
		):
			_broadcasts += 1
			_compact_movement_snapshots_published += 1
		else:
			all_enqueued = false
			_movement_snapshot_enqueue_failures += 1
	_movement_snapshot_dirty = target_count > 0 and not all_enqueued
	if all_enqueued and target_count > 0:
		_movement_snapshots_published += 1


func _handle_player_state_rejected(peer_id: String, session_id: String, payload: Dictionary) -> void:
	var operation_id := String(payload.get("operation_id", "")).strip_edges()
	if not _peer_to_player.has(peer_id) or String(_peer_to_session.get(peer_id, "")) != session_id:
		_send_result(peer_id, operation_id, "PLAYER_STATE", _failure("STALE_TRANSPORT_SESSION"))
		return
	_reject_uncommitted_command(peer_id, operation_id, "PLAYER_STATE", "CLIENT_AUTHORITATIVE_STATE_FORBIDDEN")


func _handle_presentation(peer_id: String, session_id: String, payload: Dictionary) -> void:
	if not _peer_to_player.has(peer_id) or String(_peer_to_session.get(peer_id, "")) != session_id:
		_send_result(peer_id, String(payload.get("operation_id", "")), "PRESENTATION", _failure("STALE_TRANSPORT_SESSION"))
		return
	var logical_id := String(_peer_to_player.get(peer_id, ""))
	var operation_id := String(payload.get("operation_id", "")).strip_edges()
	if not _is_canonical_operation_id(operation_id):
		_reject_uncommitted_command(
			peer_id, operation_id, "PRESENTATION",
			"OPERATION_ID_REQUIRED" if operation_id.is_empty() else "INVALID_OPERATION_ID"
		)
		return
	var result: Dictionary = _service.set_player_presentation(
		logical_id, session_id, int(payload.get("ownership_epoch", 0)),
		float(payload.get("orientation_yaw", 0.0)), bool(payload.get("flashlight_enabled", false)), operation_id
	)
	if not _persist_command_result(operation_id, "PRESENTATION", logical_id, result):
		_send_result(peer_id, operation_id, "PRESENTATION", _failure("M6_DURABLE_COMMIT_FAILED"))
		return
	var result_sent := _send_result(peer_id, operation_id, "PRESENTATION", result)
	if bool(result.get("success", false)):
		if not _is_replay_result(result):
			_presentation_updates += 1
			_broadcast_delta(result.get("details", {}).get("delta", {}))
			_broadcast_snapshot("PLAYER_PRESENTATION_UPDATED")
			_capture_two_connected_checksum()
	else:
		_rejections += 1
	if result_sent:
		_mark_operation_delivered(operation_id)
	_write_report("READY", false)

func _handle_item_graph_resync_request(peer_id: String, session_id: String, payload: Dictionary) -> void:
	if not _peer_to_player.has(peer_id) or String(_peer_to_session.get(peer_id, "")) != session_id:
		return
	_item_graph_resync_requests += 1
	var operation_id: String = String(payload.get("operation_id", ""))
	var sent: bool = _send_on_channel(
		peer_id,
		"ITEM_GRAPH_SNAPSHOT",
		{
			"reason": "EXPLICIT_RESYNC",
			"operation_id": operation_id,
			"snapshot": _service.create_canonical_item_graph_snapshot(),
		},
		RealtimeChannelPolicy.RESYNC,
		"RELIABLE_ORDERED"
	)
	if sent:
		_item_graph_full_snapshots_published += 1


func _broadcast_item_snapshot(reason: String, excluded_peer_id: String = "") -> void:
	var snapshot: Dictionary = _service.create_canonical_item_graph_snapshot()
	for peer_id_value in _peer_to_player.keys():
		var peer_id: String = String(peer_id_value)
		if peer_id == excluded_peer_id:
			continue
		if _send_on_channel(
			peer_id,
			"ITEM_GRAPH_SNAPSHOT",
			{"reason": reason, "snapshot": snapshot},
			RealtimeChannelPolicy.RESYNC,
			"RELIABLE_ORDERED"
		):
			_broadcasts += 1
			_item_graph_full_snapshots_published += 1


func _handle_item_command(peer_id: String, session_id: String, payload: Dictionary) -> void:
	if not _peer_to_player.has(peer_id) or String(_peer_to_session.get(peer_id, "")) != session_id:
		_send_result(peer_id, String(payload.get("operation_id", "")), "ITEM_COMMAND", _failure("STALE_TRANSPORT_SESSION"))
		return
	var logical_id := String(_peer_to_player.get(peer_id, ""))
	var operation_id := String(payload.get("operation_id", "")).strip_edges()
	var command_type := String(payload.get("command_type", "")).strip_edges()
	if not _is_canonical_operation_id(operation_id):
		_reject_uncommitted_command(
			peer_id, operation_id, "ITEM_COMMAND",
			"OPERATION_ID_REQUIRED" if operation_id.is_empty() else "INVALID_OPERATION_ID"
		)
		return
	if command_type.is_empty():
		_reject_uncommitted_command(peer_id, operation_id, "ITEM_COMMAND", "ITEM_COMMAND_TYPE_REQUIRED")
		return
	var command_payload_value = payload.get("payload", {})
	if not command_payload_value is Dictionary:
		_reject_uncommitted_command(peer_id, operation_id, "ITEM_COMMAND", "ITEM_COMMAND_PAYLOAD_REQUIRED")
		return
	var before_item_snapshot: Dictionary = _service.create_canonical_item_graph_snapshot()
	var result: Dictionary = _service.handle_canonical_item_command(
		logical_id, session_id, int(payload.get("ownership_epoch", 0)),
		operation_id, command_type, Dictionary(command_payload_value)
	)
	if not _persist_command_result(operation_id, command_type, logical_id, result):
		_send_result(peer_id, operation_id, command_type, _failure("M6_DURABLE_COMMIT_FAILED"))
		return
	var item_delta: Dictionary = {}
	var item_delta_fallback_required: bool = false
	if bool(result.get("success", false)) and not _is_replay_result(result):
		var after_item_snapshot: Dictionary = _service.create_canonical_item_graph_snapshot()
		var delta_result: Dictionary = CanonicalItemGraphDelta.create(before_item_snapshot, after_item_snapshot)
		if not bool(delta_result.get("success", false)):
			# The authoritative mutation has already committed durably. Never convert it
			# into a rejection after commit; recover replication with a full resync.
			item_delta_fallback_required = true
			_item_graph_delta_build_failures += 1
			_last_error_code = "ITEM_GRAPH_DELTA_BUILD_FAILED"
		else:
			item_delta = Dictionary(delta_result.get("details", {}).get("delta", {})).duplicate(true)
	var result_sent := _send_result(peer_id, operation_id, command_type, result, item_delta)
	if bool(result.get("success", false)):
		if not _is_replay_result(result):
			if item_delta_fallback_required:
				_broadcast_item_snapshot("ITEM_GRAPH_DELTA_BUILD_FALLBACK")
			else:
				_broadcast_item_delta(item_delta, peer_id, command_type)
			# Gameplay metadata still advances; publish one reliable resync snapshot,
			# but never embed the full Item Graph in ordinary results.
			_broadcast_snapshot("ITEM_GRAPH_UPDATED", RealtimeChannelPolicy.RESYNC, "RELIABLE_ORDERED")
			_capture_two_connected_checksum()
	else:
		_rejections += 1
	if result_sent:
		_mark_operation_delivered(operation_id)
	_write_report("READY", false)

func _broadcast_item_delta(delta: Dictionary, excluded_peer_id: String, reason: String) -> void:
	if delta.is_empty():
		return
	for peer_id_value in _peer_to_player.keys():
		var peer_id: String = String(peer_id_value)
		if peer_id == excluded_peer_id:
			continue
		if _send_on_channel(peer_id, "ITEM_GRAPH_DELTA", {"reason": reason, "delta": delta}, RealtimeChannelPolicy.ITEM, "RELIABLE_ORDERED"):
			_broadcasts += 1
			_item_graph_deltas_published += 1

func _handle_leave(peer_id: String, session_id: String, payload: Dictionary) -> void:
	var logical_id := String(_peer_to_player.get(peer_id, payload.get("logical_player_id", "")))
	var operation_id := String(payload.get("operation_id", "")).strip_edges()
	if not _is_canonical_operation_id(operation_id):
		_reject_uncommitted_leave(
			peer_id, operation_id,
			"OPERATION_ID_REQUIRED" if operation_id.is_empty() else "INVALID_OPERATION_ID"
		)
		return
	var result: Dictionary = _service.leave(logical_id, session_id, operation_id)
	if not _persist_command_result(operation_id, "LEAVE", logical_id, result):
		_send(peer_id, "LEAVE_REJECTED", {"operation_id": operation_id, "error_code": "M6_DURABLE_COMMIT_FAILED"})
		return
	var leave_sent := false
	if bool(result.get("success", false)):
		leave_sent = _send(peer_id, "LEAVE_ACK", {"operation_id": operation_id, "logical_player_id": logical_id})
		if not _is_replay_result(result):
			_leaves += 1
			_broadcast_delta(result.get("details", {}).get("delta", {}), peer_id)
		_peer_to_player.erase(peer_id)
		_peer_to_session.erase(peer_id)
		if not _is_replay_result(result):
			_broadcast_snapshot("PLAYER_LEFT")
	else:
		_rejections += 1
		leave_sent = _send(peer_id, "LEAVE_REJECTED", {"operation_id": operation_id, "error_code": String(result.get("error_code", "LEAVE_REJECTED"))})
	if leave_sent:
		_mark_operation_delivered(operation_id)
	_write_report("READY", false)


func _handle_disconnect(peer_id: String, session_id: String) -> void:
	_peer_input_buffers.erase(peer_id)
	_peer_compatibility.erase(peer_id)
	_debug_event("PEER_DISCONNECTED", {"peer_id":peer_id,"session_id":session_id})
	var mapped_session := String(_peer_to_session.get(peer_id, ""))
	if _service == null or session_id.is_empty() or mapped_session != session_id:
		_peer_to_player.erase(peer_id)
		_peer_to_session.erase(peer_id)
		_write_report("READY", false)
		return
	var operation_id := "operation/m3/disconnect/%s" % session_id.sha256_text().left(16)
	var logical_id := String(_peer_to_player.get(peer_id, ""))
	var result: Dictionary = _service.leave_transport_session(session_id, operation_id)
	if not _persist_command_result(operation_id, "DISCONNECT", logical_id, result):
		return
	if bool(result.get("success", false)) and not _is_replay_result(result):
		_leaves += 1
		_broadcast_delta(result.get("details", {}).get("delta", {}), peer_id)
	else:
		_rejections += 1
	_mark_operation_delivered(operation_id)
	_peer_to_player.erase(peer_id)
	_peer_to_session.erase(peer_id)
	_broadcast_snapshot("PEER_DISCONNECTED")
	_write_report("READY", false)

func _reject_uncommitted_command(peer_id: String, operation_id: String, command_type: String, error_code: String) -> void:
	_rejections += 1
	_send_result(peer_id, operation_id, command_type, _failure(error_code))
	_write_report("READY", false)


func _reject_uncommitted_leave(peer_id: String, operation_id: String, error_code: String) -> void:
	_rejections += 1
	_send(peer_id, "LEAVE_REJECTED", {"operation_id": operation_id, "error_code": error_code})
	_write_report("READY", false)


func _send_result(peer_id: String, operation_id: String, command_type: String, result: Dictionary, item_graph_delta: Dictionary = {}) -> bool:
	var wire: Dictionary = _service.create_targeted_command_result("message/m3/result/%s" % operation_id.sha256_text().left(12), operation_id, result)
	var payload := {
		"operation_id": operation_id,
		"command_type": command_type,
		"status": String(wire.get("status", "REJECTED")),
		"error_code": String(wire.get("error_code", "")),
		"details": wire.get("payload", {}),
		"checksum": String(wire.get("checksum", "")),
	}
	if not item_graph_delta.is_empty():
		payload["item_graph_delta"] = item_graph_delta.duplicate(true)
		_item_graph_deltas_published += 1
	var channel: String = RealtimeChannelPolicy.ITEM if _is_item_command_type(command_type) else RealtimeChannelPolicy.CONTROL
	return _send_on_channel(peer_id, "COMMAND_RESULT", payload, channel, "RELIABLE_ORDERED")

func _broadcast_delta(delta: Dictionary, excluded_peer_id: String = "") -> void:
	if delta.is_empty():
		return
	for peer_id_value in _peer_to_player.keys():
		var peer_id: String = String(peer_id_value)
		if peer_id == excluded_peer_id:
			continue
		if _send_on_channel(peer_id, "GAMEPLAY_DELTA", {"delta": delta}, RealtimeChannelPolicy.SNAPSHOT, "UNRELIABLE_SEQUENCED"):
			_broadcasts += 1


func _broadcast_snapshot(
	reason: String,
	channel: String = RealtimeChannelPolicy.RESYNC,
	delivery_mode: String = "RELIABLE_ORDERED"
) -> void:
	var snapshot: Dictionary = _service.create_snapshot()
	for peer_id_value in _peer_to_player.keys():
		if _send_on_channel(String(peer_id_value), "GAMEPLAY_SNAPSHOT", {"reason": reason, "snapshot": snapshot}, channel, delivery_mode):
			_broadcasts += 1


func _send(peer_id: String, message_type: String, data: Dictionary) -> bool:
	return _send_on_channel(peer_id, message_type, data, RealtimeChannelPolicy.CONTROL, "RELIABLE_ORDERED")


func _send_on_channel(
	peer_id: String,
	message_type: String,
	data: Dictionary,
	channel: String,
	delivery_mode: String
) -> bool:
	if _boundary == null or peer_id.is_empty():
		return false
	if not _ensure_peer_ready(peer_id):
		return false
	var payload: Dictionary = data.duplicate(true)
	payload["type"] = message_type
	payload["server_sent_at_ms"] = Time.get_ticks_msec()
	var frame_result: Dictionary = _boundary.create_frame_for_peer(
		peer_id, channel, Support.MESSAGE_SCHEMA, payload, delivery_mode
	)
	if not bool(frame_result.get("success", false)):
		_last_error_code = String(frame_result.get("error_code", "FRAME_CREATE_FAILED"))
		return false
	var sent: Dictionary = _boundary.send_to_peer(peer_id, frame_result.get("details", {}).get("frame", {}))
	if not bool(sent.get("success", false)):
		_last_error_code = String(sent.get("error_code", "SEND_FAILED"))
		return false
	var flushed: Dictionary = _boundary.flush_outbound(32, peer_id)
	if not bool(flushed.get("success", false)):
		_last_error_code = String(flushed.get("error_code", "FLUSH_FAILED"))
		return false
	_messages_sent += 1
	return true


func _is_item_command_type(command_type: String) -> bool:
	return (
		command_type == "ITEM_COMMAND"
		or command_type.begins_with("item.")
		or command_type.begins_with("inventory.")
		or command_type.begins_with("container.")
		or command_type.begins_with("mount.")
	)


func _send_control(peer_id: String, message_type: String, data: Dictionary) -> bool:
	if _boundary == null or peer_id.is_empty():
		return false
	var payload: Dictionary = data.duplicate(true)
	payload["type"] = message_type
	payload["server_sent_at_ms"] = Time.get_ticks_msec()
	var frame_result: Dictionary = _boundary.create_frame_for_peer(
		peer_id, RealtimeChannelPolicy.CONTROL, Support.MESSAGE_SCHEMA, payload, "RELIABLE_ORDERED"
	)
	if not bool(frame_result.get("success", false)):
		_last_error_code = String(frame_result.get("error_code", "CONTROL_FRAME_CREATE_FAILED"))
		return false
	var sent: Dictionary = _boundary.send_to_peer(
		peer_id, frame_result.get("details", {}).get("frame", {})
	)
	if not bool(sent.get("success", false)):
		_last_error_code = String(sent.get("error_code", "CONTROL_SEND_FAILED"))
		return false
	var flushed: Dictionary = _boundary.flush_outbound(32, peer_id)
	if not bool(flushed.get("success", false)):
		_last_error_code = String(flushed.get("error_code", "CONTROL_FLUSH_FAILED"))
		return false
	_messages_sent += 1
	return true


func _ensure_peer_ready(peer_id: String) -> bool:
	if String(_boundary.get_peer_snapshot(peer_id).get("state", "")) == "READY": return true
	for method_name in ["mark_peer_handshaking", "mark_peer_synchronizing", "mark_peer_ready"]:
		var result: Dictionary = _boundary.call(method_name, peer_id)
		if not bool(result.get("success", false)) and String(result.get("error_code", "")) != "INVALID_PEER_STATE_TRANSITION": return false
	return String(_boundary.get_peer_snapshot(peer_id).get("state", "")) == "READY"

func _capture_two_connected_checksum() -> void:
	if _peer_to_player.size() == 2 and _service != null:
		_last_two_connected_checksum = String(_service.create_snapshot().get("checksum", ""))

func _setup_recovery() -> Dictionary:
	_recovery_repository = RecoveryRepository.new()
	var repository_result: Dictionary = _recovery_repository.configure(_persistence_root)
	if not bool(repository_result.get("success", false)):
		return _failure("M6_RECOVERY_REPOSITORY_SETUP_FAILED", {"cause": repository_result})
	_recovery_authority = M6AuthorityAdapter.new()
	var authority_result: Dictionary = _recovery_authority.setup(
		_service,
		"session/m6/%s" % _authority_owner_id.sha256_text().left(16)
	)
	if not bool(authority_result.get("success", false)):
		return authority_result
	_replay_outbox = M6ReplayOutbox.new()
	var replay_result: Dictionary = _replay_outbox.setup(_service)
	if not bool(replay_result.get("success", false)):
		return replay_result
	_recovery_coordinator = RecoveryCoordinator.new()
	var coordinator_result: Dictionary = _recovery_coordinator.configure(
		_recovery_repository, _recovery_authority, _replay_outbox
	)
	if not bool(coordinator_result.get("success", false)):
		return coordinator_result
	var loaded: Dictionary = _recovery_repository.load_committed()
	if bool(loaded.get("success", false)):
		var checkpoint: Dictionary = loaded.get("details", {}).get("checkpoint", {})
		var authority_validation: Dictionary = _recovery_authority.validate_recovery_state(
			Dictionary(checkpoint.get("authority_state", {}))
		)
		if not bool(authority_validation.get("success", false)):
			return _failure("M6_DEDICATED_AUTHORITY_PREVALIDATION_FAILED", {"cause": authority_validation})
		var replay_validation: Dictionary = _replay_outbox.validate(
			Dictionary(checkpoint.get("replay_state", {}))
		)
		if not bool(replay_validation.get("success", false)):
			return _failure("M6_DEDICATED_REPLAY_PREVALIDATION_FAILED", {"cause": replay_validation})
		var recovered: Dictionary = _recovery_coordinator.recover_latest()
		if not bool(recovered.get("success", false)):
			return _failure("M6_DEDICATED_RECOVERY_FAILED", {"cause": recovered})
		checkpoint = recovered.get("details", {}).get("checkpoint", {})
		_checkpoint_generation = int(checkpoint.get("generation", 0))
		_last_checkpoint_operation_id = String(checkpoint.get("committed_operation_id", ""))
		_recovered = true
		_recovery_source = String(recovered.get("details", {}).get("source", ""))
		return _success({"recovered": true, "generation": _checkpoint_generation, "source": _recovery_source})
	var load_error := String(loaded.get("error_code", ""))
	if load_error != "AUTHORITATIVE_CHECKPOINT_NOT_FOUND":
		return _failure("M6_DEDICATED_RECOVERY_LOAD_FAILED", {"cause": loaded})
	var seeded := _persist_checkpoint("")
	if not bool(seeded.get("success", false)):
		return seeded
	return _success({"recovered": false, "generation": _checkpoint_generation, "source": "NEW"})


func _persist_command_result(operation_id: String, command_type: String, logical_player_id: String, result: Dictionary) -> bool:
	if not _persistence_enabled:
		return true
	if not _is_canonical_operation_id(operation_id):
		if bool(result.get("success", false)):
			_enter_persistence_failure("M6_COMMITTED_OPERATION_ID_INVALID")
			return false
		return true
	if _is_replay_result(result) or String(result.get("error_code", "")) == "OPERATION_REPLAY_CONFLICT":
		return true
	var replay_recorded := bool(_service.has_durable_replay_operation(operation_id))
	if not replay_recorded:
		if bool(result.get("success", false)):
			_enter_persistence_failure("M6_SUCCESS_RESULT_NOT_REPLAY_DURABLE")
			return false
		return true
	var staged: Dictionary = _replay_outbox.stage_committed(operation_id, command_type, {
		"logical_player_id": logical_player_id,
		"success": bool(result.get("success", false)),
		"error_code": String(result.get("error_code", "")),
		"result": result.duplicate(true),
		"player_snapshot_checksum": String(_service.create_snapshot().get("checksum", "")),
		"item_graph_checksum": String(_service.create_canonical_item_graph_snapshot().get("checksum", "")),
	})
	if not bool(staged.get("success", false)):
		_enter_persistence_failure(String(staged.get("error_code", "M6_OUTBOX_STAGE_FAILED")))
		return false
	var persisted := _persist_checkpoint(operation_id)
	if not bool(persisted.get("success", false)):
		_enter_persistence_failure(String(persisted.get("error_code", "M6_DURABLE_COMMIT_FAILED")))
		return false
	_durable_commits += 1
	# The command checkpoint contains the latest movement state as well. Do not
	# emit a redundant movement-only checkpoint at the same gameplay revision.
	if _movement_checkpoint_dirty:
		_movement_checkpoint_dirty = false
		_movement_commands_since_checkpoint = 0
		_last_movement_checkpoint_ms = Time.get_ticks_msec()
	return true


func _persist_checkpoint(operation_id: String) -> Dictionary:
	if not _persistence_enabled or _recovery_coordinator == null:
		return _success({"skipped": true})
	var persistence_started_us: int = Time.get_ticks_usec()
	var next_generation := _checkpoint_generation + 1
	var checkpoint_id := "checkpoint/m6/dedicated/%d" % next_generation
	var persisted: Dictionary = _recovery_coordinator.persist_checkpoint(
		checkpoint_id,
		next_generation,
		_checkpoint_generation,
		operation_id
	)
	if not bool(persisted.get("success", false)):
		_last_persistence_error_details = persisted.duplicate(true)
		_debug_event("CHECKPOINT_PERSIST_REJECTED", {
			"operation_id":operation_id,
			"next_generation":next_generation,
			"cause":persisted,
		})
		return _failure("M6_CHECKPOINT_PERSIST_FAILED", {"cause": persisted})
	_checkpoint_generation = next_generation
	_last_checkpoint_operation_id = operation_id
	_telemetry.observe("persistence_duration_ms", float(Time.get_ticks_usec() - persistence_started_us) / 1000.0)
	_telemetry.increment("persistence_commits")
	return _success({"generation": _checkpoint_generation, "checkpoint_id": checkpoint_id})


func _mark_operation_delivered(operation_id: String) -> void:
	if not _persistence_enabled or _replay_outbox == null or operation_id.is_empty():
		return
	var records: Array = _replay_outbox.get_records()
	for index in range(records.size() - 1, -1, -1):
		var record: Dictionary = records[index]
		if String(record.get("operation_id", "")) == operation_id:
			_replay_outbox.mark_delivered(int(record.get("sequence", 0)))
			return


func _is_replay_result(result: Dictionary) -> bool:
	return bool(result.get("replay", false)) or bool(result.get("details", {}).get("replay", false))


func _is_canonical_operation_id(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges().to_lower():
		return false
	for character in value:
		if not (
			(character >= "a" and character <= "z")
			or (character >= "0" and character <= "9")
			or character in ["/", "_", ".", "-"]
		):
			return false
	return true


func _enter_persistence_failure(error_code: String) -> void:
	_persistence_failures += 1
	_last_error_code = error_code if not error_code.is_empty() else "M6_DURABLE_COMMIT_FAILED"
	_fatal_persistence_failure = true
	_debug_event("PERSISTENCE_FATAL", {
		"error_code":_last_error_code,
		"checkpoint_generation":_checkpoint_generation,
		"cause":_last_persistence_error_details,
	})
	set_process(false)
	_write_report("FAILED", false)
	if _boundary != null:
		_boundary.stop()


func _persistence_report() -> Dictionary:
	return {
		"enabled": _persistence_enabled,
		"root_path": _persistence_root,
		"checkpoint_generation": _checkpoint_generation,
		"recovered": _recovered,
		"recovery_source": _recovery_source,
		"last_checkpoint_operation_id": _last_checkpoint_operation_id,
		"durable_commits": _durable_commits,
		"failures": _persistence_failures,
		"fatal_failure": _fatal_persistence_failure,
		"last_error_details": _last_persistence_error_details.duplicate(true),
		"outbox": _replay_outbox.get_report() if _replay_outbox != null else {},
		"service_recovery": _service.get_recovery_report() if _service != null else {},
	}


func _maybe_persist_movement_checkpoint() -> void:
	if (
		not _playable_sandbox
		or not _persistence_enabled
		or not _movement_checkpoint_dirty
		or _fatal_persistence_failure
		or Time.get_ticks_msec() - _last_movement_checkpoint_ms < M7_MOVEMENT_CHECKPOINT_INTERVAL_MS
	):
		return
	var persisted := _persist_checkpoint("")
	if not bool(persisted.get("success", false)):
		_enter_persistence_failure(String(persisted.get("error_code", "M7_MOVEMENT_CHECKPOINT_FAILED")))
		return
	_movement_checkpoint_dirty = false
	_movement_checkpoints += 1
	_movement_commands_since_checkpoint = 0
	_last_movement_checkpoint_ms = Time.get_ticks_msec()
	_debug_event("MOVEMENT_CHECKPOINT_COMMITTED", {"generation":_checkpoint_generation})
	_write_report("READY", false)

func _update_runtime_telemetry() -> void:
	if _telemetry == null:
		return
	_telemetry.set_gauge("connected_gameplay_peers", float(_peer_to_player.size()))
	_telemetry.set_gauge("compatible_transport_peers", float(_peer_compatibility.size()))
	_telemetry.set_gauge("handshake_replay_count", float(_handshake_replays))
	_telemetry.set_gauge("checkpoint_generation", float(_checkpoint_generation))
	_telemetry.set_gauge("fixed_server_tick", float(_server_tick))
	_telemetry.set_gauge("pending_input_count", float(_total_pending_input_count()))
	_telemetry.set_gauge("fixed_tick_failures", float(_fixed_tick_failures))
	var boundary_snapshot: Dictionary = _boundary.get_snapshot() if _boundary != null else {}
	var port_runtime: Dictionary = boundary_snapshot.get("port_runtime", {})
	var peer_statistics: Dictionary = port_runtime.get("peer_statistics", {})
	for stats_value in peer_statistics.values():
		if not stats_value is Dictionary:
			continue
		var stats: Dictionary = stats_value
		_telemetry.observe("peer_rtt_ms", float(stats.get("rtt_ms", 0)))
		_telemetry.observe("peer_jitter_ms", float(stats.get("rtt_variance_ms", 0)))
		_telemetry.observe("peer_packet_loss_percent", float(stats.get("packet_loss_percent", 0.0)))


func _total_pending_input_count() -> int:
	var total: int = 0
	for buffer_value in _peer_input_buffers.values():
		if buffer_value != null:
			total += int(buffer_value.get_pending_count())
	return total


func _telemetry_sample() -> Dictionary:
	if _telemetry == null:
		return {}
	var result: Dictionary = _telemetry.create_sample(Time.get_ticks_msec())
	return Dictionary(result.get("details", {}).get("sample", {})).duplicate(true) if bool(result.get("success", false)) else {}


func _debug_event(event_name: String, details: Dictionary = {}) -> void:
	if not _debug_logging:
		return
	print("[m7_server] %s" % JSON.stringify({
		"event":event_name,"process_id":OS.get_process_id(),"time_msec":Time.get_ticks_msec(),
		"details":details,
	}, "", true, true))

func detach_playable_world() -> Dictionary:
	# M3/M7 dedicated runtime owns gameplay state directly and has no separate
	# presentation world attachment. Keep SimulatorApp lifecycle polymorphic.
	return _success({"detached": false, "reason": "DEDICATED_RUNTIME_OWNS_NO_PLAYABLE_WORLD"})


func get_world_entity_store_for_kernel():
	return null

func _cleanup_setup_failure() -> void:
	set_process(false)
	if _boundary != null:
		_boundary.stop()
	elif _network_condition_simulator != null:
		_network_condition_simulator.stop()
	if _service != null:
		_service.shutdown()
	_boundary = null
	_network_condition_simulator = null
	_service = null


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


func _input_buffer_reports() -> Dictionary:
	var reports: Dictionary = {}
	for peer_id_value in _peer_input_buffers.keys():
		var peer_id: String = String(peer_id_value)
		var buffer = _peer_input_buffers[peer_id]
		if buffer != null:
			reports[peer_id] = buffer.get_report(_server_tick)
	return reports


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"checkpoint": RuntimeIdentity.CHECKPOINT,
		"build_id": RuntimeIdentity.BUILD_ID,
		"gameplay_checkpoint": (
			M7_CHECKPOINT if _playable_sandbox
			else M6_CHECKPOINT if _persistence_enabled
			else Support.CHECKPOINT
		),
		"gameplay_build_id": (
			M7_BUILD_ID if _playable_sandbox
			else M6_BUILD_ID if _persistence_enabled
			else Support.BUILD_ID
		),
		"configured": _configured,
		"host": _host,
		"port": _port,
		"connected_peer_count": _peer_to_player.size(),
		"peer_to_player": _peer_to_player.duplicate(true),
		"joins": _joins,
		"leaves": _leaves,
		"moves": _moves,
		"presentation_updates": _presentation_updates,
		"rejections": _rejections,
		"broadcasts": _broadcasts,
		"messages_sent": _messages_sent,
		"messages_received": _messages_received,
		"last_error_code": _last_error_code,
		"last_two_connected_checksum": _last_two_connected_checksum,
		"snapshot": _service.create_snapshot() if _service != null else {},
		"item_graph_snapshot": _service.create_canonical_item_graph_snapshot() if _service != null else {},
		"service": _service.get_report() if _service != null else {},
		"boundary": _boundary.get_snapshot() if _boundary != null else {},
		"resolved_user_data_dir": OS.get_user_data_dir(),
		"direct_client_authority_references": 0,
		"persistence": _persistence_report(),
		"playable_sandbox": _playable_sandbox,
		"network_fingerprint": _fingerprint.duplicate(true),
		"network_protocol_manifest": _protocol_manifest.duplicate(true),
		"compatibility_handshake": {
			"attempts": _handshake_attempts,
			"accepts": _handshake_accepts,
			"rejections": _handshake_rejections,
			"replays": _handshake_replays,
			"last_error_code": _last_handshake_error_code,
			"compatible_peers": _peer_compatibility.duplicate(true),
		},
		"network_conditions": (
			_network_condition_simulator.get_runtime_snapshot()
			if _network_condition_simulator != null else {}
		),
		"network_telemetry": _telemetry_sample(),
		"realtime_traffic": {
			"channel_policy": RealtimeChannelPolicy.canonical_policy(),
			"movement_snapshot_interval_ms": NX2_MOVEMENT_SNAPSHOT_INTERVAL_MS,
			"movement_snapshot_interval_ticks": NX3_MOVEMENT_SNAPSHOT_INTERVAL_TICKS,
			"movement_snapshot_rate_hz": NX3_FIXED_TICK_RATE_HZ / NX3_MOVEMENT_SNAPSHOT_INTERVAL_TICKS,
			"movement_batches_received": _movement_batches_received,
			"movement_inputs_received": _movement_inputs_received,
			"movement_inputs_applied": _movement_inputs_applied,
			"movement_inputs_redundant": _movement_inputs_redundant,
			"movement_inputs_rejected": _movement_inputs_rejected,
			"last_movement_rejection_error_code": _last_movement_rejection_error_code,
			"last_movement_rejection_stage": _last_movement_rejection_stage,
			"movement_results_suppressed": _movement_results_suppressed,
			"movement_deltas_suppressed": _movement_deltas_suppressed,
			"movement_full_snapshots_suppressed": _movement_full_snapshots_suppressed,
			"movement_snapshots_published": _movement_snapshots_published,
			"item_graph_deltas_published": _item_graph_deltas_published,
			"item_graph_delta_build_failures": _item_graph_delta_build_failures,
			"item_graph_full_snapshots_published": _item_graph_full_snapshots_published,
			"item_graph_resync_requests": _item_graph_resync_requests,
			"compact_movement_snapshots_published": _compact_movement_snapshots_published,
			"movement_snapshot_retransmit_requests": _movement_snapshot_retransmit_requests,
			"movement_snapshot_enqueue_failures": _movement_snapshot_enqueue_failures,
			"compact_movement_snapshot_failures": _compact_movement_snapshot_failures,
		},
		"fixed_tick_simulation": {
			"schema": FixedTickScheduler.SCHEMA,
			"tick_rate_hz": NX3_FIXED_TICK_RATE_HZ,
			"tick_delta_seconds": NX3_FIXED_TICK_DELTA_SECONDS,
			"server_tick": _server_tick,
			"ticks_simulated": _fixed_ticks_simulated,
			"catch_up_batches": _fixed_tick_catch_up_batches,
			"failures": _fixed_tick_failures,
			"last_tick_duration_ms": _last_fixed_tick_duration_ms,
			"pending_input_count": _total_pending_input_count(),
			"stale_input_drops": _input_queue_stale_drops,
			"input_hold_expirations": _input_hold_expirations,
			"scheduler": _fixed_tick_scheduler.get_report() if _fixed_tick_scheduler != null else {},
			"input_buffers": _input_buffer_reports(),
		},
		"movement_persistence": {
			"mode":"THROTTLED_WORLD_CHECKPOINT",
			"interval_ms":M7_MOVEMENT_CHECKPOINT_INTERVAL_MS,
			"dirty":_movement_checkpoint_dirty,
			"checkpoint_count":_movement_checkpoints,
			"commands_since_checkpoint":_movement_commands_since_checkpoint,
		},
	}

func stop() -> Dictionary:
	set_process(false)
	if _persistence_enabled and not _fatal_persistence_failure and _service != null and _recovery_coordinator != null:
		var persisted: Dictionary = _persist_checkpoint("")
		if not bool(persisted.get("success", false)):
			_enter_persistence_failure(String(persisted.get("error_code", "M6_FINAL_CHECKPOINT_FAILED")))
	if _fatal_persistence_failure:
		_write_report("FAILED", false)
	else:
		_write_report("STOPPED", true)
	if _boundary != null:
		_boundary.stop()
	if _service != null:
		_service.shutdown()
	_boundary = null
	_network_condition_simulator = null
	_service = null
	_fixed_tick_scheduler = null
	_peer_input_buffers.clear()
	_configured = false
	if _fatal_persistence_failure:
		return _failure(_last_error_code if not _last_error_code.is_empty() else "M6_DURABLE_COMMIT_FAILED")
	return _success()

func _write_report(state: String, passed: bool) -> void:
	if _result_file.is_empty(): return
	var report := get_report(); report["state"] = state; report["passed"] = passed; report["process_id"] = OS.get_process_id()
	Support.write(_result_file, report)

func _exit_tree() -> void:
	if _configured: stop()

func _success(details: Dictionary = {}) -> Dictionary: return {"success": true, "error_code": "", "details": details.duplicate(true)}
func _failure(error_code: String, details: Dictionary = {}) -> Dictionary: return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
