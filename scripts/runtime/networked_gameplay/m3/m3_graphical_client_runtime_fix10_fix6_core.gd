extends "res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_fix10_fix5.gd"

# FIX10 fix6 is a leaf over the accepted FIX5 graphical runtime. Snapshot ACKs
# are registered before canonical replica acceptance, while standalone ACK packets
# terminate locally instead of reaching the NX6 unknown-message default branch.
#
# Accepted source-contract anchors retained on the canonical path:
# res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_fix9.gd
# set_authoritative_input_ack
# COMPACT_ARRAY_V1
# SEPARATE_TELEMETRY_CHANNEL_WHEN_SNAPSHOT_ACK_OMITTED_V1
# VALIDATED_WIRE_SNAPSHOT_PRESENTATION_LANE_V1
# remote_presentation_snapshot
# M7_CLIENT_PEER_TELEMETRY_INTERVAL_MS
# _fix6_peer_telemetry_skips += 1
# _boundary.get_snapshot()
# client_process_max_duration_ms
# peer_telemetry_max_duration_ms

const FIX10_FIX6_PREDICTION_ACK_WIRE_POLICY: String = "COMPACT_TRANSITION_ARRAY_V2"
const FIX10_FIX6_PREDICTION_ACK_WIRE_VALUES: int = 23
const FIX10_FIX6_TRANSITION_POLICY: String = "PRE_POST_INPUT_TRANSITION_WITH_HOLD_TICKS_V1"
const FIX10_FIX6_ACK_DISPATCH_POLICY: String = "REGISTER_BEFORE_CANONICAL_ACCEPT_AND_TERMINATE_STANDALONE_V1"
const FIX10_FIX6_SEMANTIC_INPUT_LATCH_POLICY: String = "ONE_SEQUENCE_PER_CLIENT_FIXED_TICK_V1"

var _fix10_fix6_deferred_snapshot_ack: Dictionary = {}
var _fix10_fix6_snapshot_ack_registered_before_canonical: int = 0
var _fix10_fix6_snapshot_ack_deferred: int = 0
var _fix10_fix6_snapshot_ack_deferred_flushes: int = 0
var _fix10_fix6_prediction_ack_base_dispatch_suppressed: int = 0
var _fix10_fix6_transition_wire_received: int = 0
var _fix10_fix6_last_latched_client_tick: int = 0
var _fix10_fix6_semantic_input_submissions: int = 0
var _fix10_fix6_same_tick_input_update_suppressions: int = 0


func setup(config: Dictionary) -> Dictionary:
	_fix10_fix6_deferred_snapshot_ack.clear()
	_fix10_fix6_snapshot_ack_registered_before_canonical = 0
	_fix10_fix6_snapshot_ack_deferred = 0
	_fix10_fix6_snapshot_ack_deferred_flushes = 0
	_fix10_fix6_prediction_ack_base_dispatch_suppressed = 0
	_fix10_fix6_transition_wire_received = 0
	_fix10_fix6_last_latched_client_tick = 0
	_fix10_fix6_semantic_input_submissions = 0
	_fix10_fix6_same_tick_input_update_suppressions = 0
	return super.setup(config)


func _handle_message(payload: Dictionary) -> void:
	var message_type: String = String(payload.get("type", ""))

	if message_type == "PREDICTION_ACK":
		var standalone_ack: Dictionary = _fix10_extract_prediction_ack(payload, message_type)
		if not standalone_ack.is_empty():
			_fix10_ack_sidecars_received += 1
			_fix10_fix3_standalone_ack_received += 1
			_fix10_fix3_register_standalone_ack(standalone_ack)
		# Standalone prediction ACK is metadata only. The accepted NX6 parent does
		# not define this message type and would otherwise set UNKNOWN_M3_SERVER_MESSAGE.
		_fix10_fix6_prediction_ack_base_dispatch_suppressed += 1
		return

	if message_type in ["GAMEPLAY_SNAPSHOT", "COMPACT_GAMEPLAY_SNAPSHOT"]:
		var snapshot_ack: Dictionary = _fix10_extract_prediction_ack(payload, message_type)
		if not snapshot_ack.is_empty():
			_fix10_ack_sidecars_received += 1
			_fix10_fix6_register_snapshot_ack(snapshot_ack)
		# The FIX5 parent also knows how to extract snapshot ACKs. Strip only the
		# already-registered sidecar before parent dispatch so canonical snapshot and
		# remote-presentation behavior stays identical without double registration.
		var parent_payload: Dictionary = payload.duplicate(true)
		parent_payload.erase("prediction_ack")
		parent_payload.erase("prediction_ack_policy")
		super._handle_message(parent_payload)
		return

	super._handle_message(payload)


func _reconcile_prediction_from_snapshot(snapshot: Dictionary) -> void:
	_fix10_fix6_flush_deferred_snapshot_ack()
	super._reconcile_prediction_from_snapshot(snapshot)


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
	var target_client_tick: int = _prediction_reconciler.get_prediction_tick() + 1
	var submission: Dictionary = _success()
	var submission_attempted: bool = false

	# A render loop can run several times before the next 60 Hz prediction tick.
	# The old path created a fresh input_sequence on every changed render intent,
	# stamping all of them with the same future client_tick. The client can only
	# simulate the newest sequence at that tick, while authority may already have
	# consumed an earlier packet. Freeze the first sampled intent for this fixed
	# tick and let later render changes become the next tick's semantic transition.
	if should_submit:
		if target_client_tick == _fix10_fix6_last_latched_client_tick:
			_fix10_fix6_same_tick_input_update_suppressions += 1
		else:
			submission_attempted = true
			submission = submit_movement_intent_nonblocking(canonical, target_client_tick)
			var submission_error: String = String(submission.get("error_code", ""))
			var semantic_latched: bool = (
				bool(submission.get("success", false))
				or submission_error == "M7_PLAYER_INPUT_SEND_FAILED"
			)
			if semantic_latched:
				# Even if the immediate transport flush failed, set_input() and the
				# pending batch already own this semantic sequence. The regular network
				# process will retry that batch; creating another sequence for the same
				# client tick would reintroduce the ambiguity this latch removes.
				_fix10_fix6_last_latched_client_tick = target_client_tick
				_fix10_fix6_semantic_input_submissions += 1
				_prediction_input_accumulator = 0.0
				_prediction_last_network_intent = canonical.duplicate(true)
			elif not submission_error.is_empty():
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
		"fix10_fix6_target_client_tick": target_client_tick,
		"fix10_fix6_semantic_input_latch_policy": FIX10_FIX6_SEMANTIC_INPUT_LATCH_POLICY,
	})


func _fix10_fix6_register_snapshot_ack(ack: Dictionary) -> void:
	if ack.is_empty():
		return
	if (
		_prediction_reconciler == null
		or not _prediction_reconciler.is_configured()
		or not _prediction_reconciler.has_method("set_authoritative_input_ack")
	):
		_fix10_fix6_deferred_snapshot_ack = ack.duplicate(true)
		_fix10_fix6_snapshot_ack_deferred += 1
		return
	var registered: Dictionary = _prediction_reconciler.call(
		"set_authoritative_input_ack",
		ack,
		int(ack.get("transport_snapshot_server_tick", -1))
	)
	if bool(registered.get("success", false)):
		_fix10_ack_sidecars_registered += 1
		_fix10_fix6_snapshot_ack_registered_before_canonical += 1
		_fix10_last_ack_error_code = ""
	else:
		_fix10_ack_sidecars_rejected += 1
		_fix10_last_ack_error_code = String(
			registered.get("error_code", "FIX10_FIX6_SNAPSHOT_ACK_REGISTRATION_FAILED")
		)


func _fix10_fix6_flush_deferred_snapshot_ack() -> void:
	if _fix10_fix6_deferred_snapshot_ack.is_empty():
		return
	if _prediction_reconciler == null or not _prediction_reconciler.is_configured():
		return
	var pending: Dictionary = _fix10_fix6_deferred_snapshot_ack.duplicate(true)
	_fix10_fix6_deferred_snapshot_ack.clear()
	_fix10_fix6_snapshot_ack_deferred_flushes += 1
	_fix10_fix6_register_snapshot_ack(pending)


func _fix10_extract_prediction_ack(
	payload: Dictionary,
	message_type: String
) -> Dictionary:
	var ack_value = payload.get("prediction_ack", null)
	var ack: Dictionary = {}
	if ack_value is Array:
		var wire: Array = ack_value
		if wire.size() not in [FIX10_PREDICTION_ACK_WIRE_VALUES, FIX10_FIX6_PREDICTION_ACK_WIRE_VALUES]:
			return {}
		for value in wire:
			if not (value is int or value is float):
				return {}
		ack = {
			"input_sequence": int(wire[0]),
			"client_tick": int(wire[1]),
			"applied_server_tick": int(wire[2]),
			"position": {"x": float(wire[3]), "y": float(wire[4]), "z": float(wire[5])},
			"velocity": {"x": float(wire[6]), "y": float(wire[7]), "z": float(wire[8])},
			"orientation_yaw": float(wire[9]),
			"state_revision": int(wire[10]),
		}
		if wire.size() == FIX10_FIX6_PREDICTION_ACK_WIRE_VALUES:
			ack["semantic_transition_policy"] = FIX10_FIX6_TRANSITION_POLICY
			ack["previous_input_sequence"] = int(wire[11])
			ack["previous_client_tick"] = int(wire[12])
			ack["previous_applied_server_tick"] = int(wire[13])
			ack["server_hold_ticks_before_input"] = int(wire[14])
			ack["pre_position"] = {"x": float(wire[15]), "y": float(wire[16]), "z": float(wire[17])}
			ack["pre_velocity"] = {"x": float(wire[18]), "y": float(wire[19]), "z": float(wire[20])}
			ack["pre_orientation_yaw"] = float(wire[21])
			ack["transition_metadata_complete"] = int(wire[22]) != 0
			_fix10_fix6_transition_wire_received += 1
		_fix10_compact_ack_sidecars_received += 1
	elif ack_value is Dictionary:
		if String(payload.get("prediction_ack_policy", "")) != FIX10_PREDICTION_ACK_POLICY:
			return {}
		ack = Dictionary(ack_value).duplicate(true)
	else:
		return {}
	if ack.is_empty():
		return {}

	var snapshot_tick: int = -1
	if message_type == "PREDICTION_ACK":
		snapshot_tick = int(payload.get("snapshot_server_tick", -1))
	else:
		var snapshot_value = payload.get("snapshot", {})
		if not snapshot_value is Dictionary:
			return {}
		var raw_snapshot: Dictionary = snapshot_value
		snapshot_tick = (
			int(raw_snapshot.get("t", -1))
			if message_type == "COMPACT_GAMEPLAY_SNAPSHOT"
			else int(raw_snapshot.get("server_tick", -1))
		)
	if snapshot_tick < 0:
		return {}
	ack["transport_snapshot_server_tick"] = snapshot_tick
	return ack


func _emit_prediction_health_if_due() -> void:
	var previous_health_ms: int = _last_prediction_health_ms
	super._emit_prediction_health_if_due()
	if _last_prediction_health_ms == previous_health_ms:
		return
	if _prediction_reconciler == null or not _prediction_reconciler.is_configured():
		return
	var prediction: Dictionary = _prediction_reconciler.get_report()
	_debug_event("FIX10_FIX6_TRANSITION_HEALTH", {
		"prediction_tick": int(prediction.get("prediction_tick", 0)),
		"corrections": int(prediction.get("corrections", 0)),
		"corrections_per_1000_prediction_ticks": float(prediction.get("fix10_corrections_per_1000_prediction_ticks", 0.0)),
		"phase_mismatch_authority_reconciliations": int(prediction.get("fix10_fix6_phase_mismatch_authority_reconciliations", 0)),
		"phase_matched_ack_reconciliations": int(prediction.get("fix10_fix6_phase_matched_ack_reconciliations", 0)),
		"transition_history_misses": int(prediction.get("fix10_fix6_transition_history_misses", 0)),
		"max_server_hold_ticks": int(prediction.get("fix10_fix6_max_server_hold_ticks", 0)),
		"max_client_hold_ticks": int(prediction.get("fix10_fix6_max_client_hold_ticks", 0)),
		"max_hold_delta_ticks": int(prediction.get("fix10_fix6_max_hold_delta_ticks", 0)),
		"max_raw_phase_baseline_offset_m": float(prediction.get("fix10_fix6_max_raw_phase_baseline_offset_m", 0.0)),
		"max_transition_delta_error_m": float(prediction.get("fix10_fix6_max_transition_delta_error_m", 0.0)),
		"max_same_clock_authority_error_m": float(prediction.get("fix10_fix6_max_same_clock_authority_error_m", 0.0)),
		"semantic_input_latch_policy": FIX10_FIX6_SEMANTIC_INPUT_LATCH_POLICY,
		"semantic_input_submissions": _fix10_fix6_semantic_input_submissions,
		"same_tick_input_update_suppressions": _fix10_fix6_same_tick_input_update_suppressions,
		"snapshot_ack_registered_before_canonical": _fix10_fix6_snapshot_ack_registered_before_canonical,
		"prediction_ack_base_dispatch_suppressed": _fix10_fix6_prediction_ack_base_dispatch_suppressed,
	})


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	var transport: Dictionary = Dictionary(report.get("fix10_prediction_ack_transport", {})).duplicate(true)
	transport["fix6_wire_policy"] = FIX10_FIX6_PREDICTION_ACK_WIRE_POLICY
	transport["fix6_transition_policy"] = FIX10_FIX6_TRANSITION_POLICY
	transport["fix6_ack_dispatch_policy"] = FIX10_FIX6_ACK_DISPATCH_POLICY
	transport["fix6_deferred_snapshot_ack_pending"] = not _fix10_fix6_deferred_snapshot_ack.is_empty()
	transport["fix6_snapshot_ack_registered_before_canonical"] = _fix10_fix6_snapshot_ack_registered_before_canonical
	transport["fix6_snapshot_ack_deferred"] = _fix10_fix6_snapshot_ack_deferred
	transport["fix6_snapshot_ack_deferred_flushes"] = _fix10_fix6_snapshot_ack_deferred_flushes
	transport["fix6_prediction_ack_base_dispatch_suppressed"] = _fix10_fix6_prediction_ack_base_dispatch_suppressed
	transport["fix6_transition_wire_received"] = _fix10_fix6_transition_wire_received
	transport["fix6_semantic_input_latch_policy"] = FIX10_FIX6_SEMANTIC_INPUT_LATCH_POLICY
	transport["fix6_last_latched_client_tick"] = _fix10_fix6_last_latched_client_tick
	transport["fix6_semantic_input_submissions"] = _fix10_fix6_semantic_input_submissions
	transport["fix6_same_tick_input_update_suppressions"] = _fix10_fix6_same_tick_input_update_suppressions
	report["fix10_prediction_ack_transport"] = transport
	return report