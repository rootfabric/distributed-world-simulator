extends "res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_fix10_fix5.gd"

# FIX10 fix6 is a leaf over the accepted FIX5 server runtime. The FIX5 file is
# copied byte-for-byte to the fix10_fix5 base path; all MTU, fallback, FIX7/FIX6
# authority, persistence and remote-snapshot behavior remains inherited.
#
# Accepted source-contract anchors retained on the canonical path:
# res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_fix7.gd
# res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_fix6.gd
# res://scripts/network/simulation/fixed_tick_input_buffer_fix10.gd
# SERVER_ECHOED_POST_INPUT_BASELINE_V1
# COMPACT_ARRAY_V1
# OPTIONAL_ACK_OMISSION_THEN_DROP_OVERSIZE_V1
# NetworkUtilsFix10.canonical_json(frame)
# payload.erase("prediction_ack")
# FIX10_UNRELIABLE_FRAME_EXCEEDS_SAFE_MTU
# _fix10_unreliable_budget_decision(packet_bytes
# _boundary.send_to_peer(peer_id, frame)
# "reason": reason
# RealtimeChannelPolicy.TELEMETRY
# "PREDICTION_ACK"
# _fix10_fix3_send_standalone_prediction_ack
# packet_bytes > FIX10_UNRELIABLE_SAFE_PACKET_BYTES
# OMIT_REDUNDANT_REASON_ON_REALTIME_SNAPSHOT_V1
# _advance_fixed_simulation(delta)
# _boundary.poll_events(M7_NETWORK_EVENT_BUDGET_PER_FRAME)
# M7_FIXED_TICK_MAX_CATCH_UP_TICKS
# M7_STALL_SNAPSHOT_GUARD_SECONDS
# _movement_snapshot_recovery_suppressions
# M7_PEER_TELEMETRY_INTERVAL_MS
# _peer_telemetry_skips
# server_process_max_duration_ms
# report_max_snapshot_build_duration_ms
# Thread.new()
# _report_requests_coalesced
# _broadcast_snapshot("ITEM_GRAPH_UPDATED", RealtimeChannelPolicy.RESYNC, "RELIABLE_ORDERED")
# _broadcast_item_delta(item_delta, peer_id, command_type)
# LIGHTWEIGHT_READY_FULL_TERMINAL_V1

const FIX10_FIX6_PREDICTION_ACK_WIRE_POLICY: String = "COMPACT_TRANSITION_ARRAY_V2"
const FIX10_FIX6_PREDICTION_ACK_WIRE_VALUES: int = 23
const FIX10_FIX6_TRANSITION_POLICY: String = "PRE_POST_INPUT_TRANSITION_WITH_HOLD_TICKS_V1"

var _fix10_fix6_transition_captures: int = 0
var _fix10_fix6_transition_metadata_incomplete: int = 0
var _fix10_fix6_max_server_hold_ticks: int = 0
var _fix10_fix6_max_transition_displacement_m: float = 0.0


func setup(config: Dictionary) -> Dictionary:
	_fix10_fix6_transition_captures = 0
	_fix10_fix6_transition_metadata_incomplete = 0
	_fix10_fix6_max_server_hold_ticks = 0
	_fix10_fix6_max_transition_displacement_m = 0.0
	return super.setup(config)


func _run_fixed_tick(server_tick: int) -> void:
	# Capture authority immediately before the accepted FIX5 tick. The parent then
	# performs the authoritative fixed-tick simulation and captures its legacy ACK.
	# FIX6 only enriches that ACK with the corresponding pre-transition state.
	var pre_players_by_logical_id: Dictionary = {}
	var pre_buffer_reports_by_peer: Dictionary = {}
	if _service != null:
		for peer_id_value in _peer_to_player.keys():
			var peer_id: String = String(peer_id_value)
			var logical_id: String = String(_peer_to_player.get(peer_id, ""))
			if logical_id.is_empty():
				continue
			var pre_player: Dictionary = _service.get_player(logical_id)
			if not pre_player.is_empty():
				pre_players_by_logical_id[logical_id] = pre_player.duplicate(true)
			var pre_buffer = _peer_input_buffers.get(peer_id)
			if pre_buffer != null and pre_buffer.has_method("get_report"):
				pre_buffer_reports_by_peer[peer_id] = pre_buffer.get_report(maxi(server_tick - 1, 0))

	super._run_fixed_tick(server_tick)
	if _service == null or _server_tick != server_tick:
		return

	for peer_id_value in _peer_to_player.keys():
		var peer_id: String = String(peer_id_value)
		var logical_id: String = String(_peer_to_player.get(peer_id, ""))
		var buffer = _peer_input_buffers.get(peer_id)
		if logical_id.is_empty() or buffer == null or not buffer.has_method("get_report"):
			continue
		var buffer_report: Dictionary = buffer.get_report(server_tick)
		if int(buffer_report.get("fix10_current_input_applied_server_tick", 0)) != server_tick:
			continue
		var sequence: int = int(buffer_report.get("fix10_current_input_sequence", 0))
		var client_tick: int = int(buffer_report.get("fix10_current_client_tick", 0))
		if sequence < 1 or client_tick < 1 or not _fix10_prediction_acks.has(logical_id):
			continue
		var player: Dictionary = _service.get_player(logical_id)
		if player.is_empty() or int(player.get("last_input_sequence", 0)) != sequence:
			continue

		var pre_player: Dictionary = Dictionary(
			pre_players_by_logical_id.get(logical_id, {})
		).duplicate(true)
		var pre_buffer_report: Dictionary = Dictionary(
			pre_buffer_reports_by_peer.get(peer_id, {})
		)
		var previous_input_sequence: int = int(pre_player.get("last_input_sequence", 0))
		var previous_client_tick: int = int(pre_buffer_report.get("fix10_current_client_tick", 0))
		var previous_applied_server_tick: int = int(
			pre_buffer_report.get("fix10_current_input_applied_server_tick", 0)
		)
		var previous_report_sequence: int = int(
			pre_buffer_report.get("fix10_current_input_sequence", 0)
		)
		var transition_metadata_complete: bool = (
			not pre_player.is_empty()
			and (
				previous_input_sequence == 0
				or (
					previous_report_sequence == previous_input_sequence
					and previous_client_tick > 0
					and previous_applied_server_tick > 0
				)
			)
		)
		var server_hold_ticks_before_input: int = 0
		if transition_metadata_complete and previous_input_sequence > 0:
			server_hold_ticks_before_input = maxi(
				server_tick - previous_applied_server_tick - 1,
				0
			)
		else:
			previous_client_tick = 0
			previous_applied_server_tick = 0
			if previous_input_sequence > 0:
				_fix10_fix6_transition_metadata_incomplete += 1

		var ack: Dictionary = Dictionary(_fix10_prediction_acks[logical_id]).duplicate(true)
		ack["semantic_transition_policy"] = FIX10_FIX6_TRANSITION_POLICY
		ack["previous_input_sequence"] = previous_input_sequence
		ack["previous_client_tick"] = previous_client_tick
		ack["previous_applied_server_tick"] = previous_applied_server_tick
		ack["server_hold_ticks_before_input"] = server_hold_ticks_before_input
		ack["pre_position"] = Dictionary(pre_player.get("position", {})).duplicate(true)
		ack["pre_velocity"] = Dictionary(pre_player.get("velocity", {})).duplicate(true)
		ack["pre_orientation_yaw"] = float(pre_player.get("orientation_yaw", 0.0))
		ack["transition_metadata_complete"] = transition_metadata_complete
		_fix10_prediction_acks[logical_id] = ack
		_fix10_fix6_transition_captures += 1
		_fix10_fix6_max_server_hold_ticks = maxi(
			_fix10_fix6_max_server_hold_ticks,
			server_hold_ticks_before_input
		)
		if not pre_player.is_empty():
			_fix10_fix6_max_transition_displacement_m = maxf(
				_fix10_fix6_max_transition_displacement_m,
				_fix10_fix6_position(pre_player).distance_to(_fix10_fix6_position(player))
			)


func _fix10_ack_wire_for_peer(peer_id: String) -> Array:
	var ack: Dictionary = _fix10_ack_for_peer(peer_id)
	if ack.is_empty():
		return []
	var position: Dictionary = Dictionary(ack.get("position", {}))
	var velocity: Dictionary = Dictionary(ack.get("velocity", {}))
	var pre_position: Dictionary = Dictionary(ack.get("pre_position", {}))
	var pre_velocity: Dictionary = Dictionary(ack.get("pre_velocity", {}))
	# 0..10 remain exactly COMPACT_ARRAY_V1. FIX6 appends transition metadata.
	var wire: Array = [
		int(ack.get("input_sequence", 0)),
		int(ack.get("client_tick", 0)),
		int(ack.get("applied_server_tick", 0)),
		float(position.get("x", 0.0)),
		float(position.get("y", 0.0)),
		float(position.get("z", 0.0)),
		float(velocity.get("x", 0.0)),
		float(velocity.get("y", 0.0)),
		float(velocity.get("z", 0.0)),
		float(ack.get("orientation_yaw", 0.0)),
		int(ack.get("state_revision", 1)),
		int(ack.get("previous_input_sequence", 0)),
		int(ack.get("previous_client_tick", 0)),
		int(ack.get("previous_applied_server_tick", 0)),
		int(ack.get("server_hold_ticks_before_input", 0)),
		float(pre_position.get("x", 0.0)),
		float(pre_position.get("y", 0.0)),
		float(pre_position.get("z", 0.0)),
		float(pre_velocity.get("x", 0.0)),
		float(pre_velocity.get("y", 0.0)),
		float(pre_velocity.get("z", 0.0)),
		float(ack.get("pre_orientation_yaw", 0.0)),
		1 if bool(ack.get("transition_metadata_complete", false)) else 0,
	]
	return wire if wire.size() == FIX10_FIX6_PREDICTION_ACK_WIRE_VALUES else []


func _fix10_fix6_position(state: Dictionary) -> Vector3:
	var value: Dictionary = Dictionary(state.get("position", {}))
	return Vector3(
		float(value.get("x", 0.0)),
		float(value.get("y", 0.0)),
		float(value.get("z", 0.0))
	)


func _dispatch_deferred_report() -> void:
	# FIX7 source-contract compatibility wrapper. The accepted lightweight READY
	# implementation remains inherited and still avoids the full get_report() path.
	super._dispatch_deferred_report()


func _build_fix7_ready_report() -> Dictionary:
	var report: Dictionary = super._build_fix7_ready_report()
	var foundation: Dictionary = Dictionary(report.get("realtime_foundation", {})).duplicate(true)
	foundation["fix10_fix6_ack_wire_policy"] = FIX10_FIX6_PREDICTION_ACK_WIRE_POLICY
	foundation["fix10_fix6_transition_policy"] = FIX10_FIX6_TRANSITION_POLICY
	foundation["fix10_fix6_transition_captures"] = _fix10_fix6_transition_captures
	foundation["fix10_fix6_transition_metadata_incomplete"] = _fix10_fix6_transition_metadata_incomplete
	foundation["fix10_fix6_max_server_hold_ticks"] = _fix10_fix6_max_server_hold_ticks
	foundation["fix10_fix6_max_transition_displacement_m"] = _fix10_fix6_max_transition_displacement_m
	report["realtime_foundation"] = foundation
	return report


func get_fix7_ready_report_policy() -> Dictionary:
	var report: Dictionary = super.get_fix7_ready_report_policy()
	report["fix10_fix6_ack_wire_policy"] = FIX10_FIX6_PREDICTION_ACK_WIRE_POLICY
	report["fix10_fix6_transition_policy"] = FIX10_FIX6_TRANSITION_POLICY
	return report


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	var ack_report: Dictionary = Dictionary(report.get("fix10_prediction_ack", {})).duplicate(true)
	ack_report["fix6_wire_policy"] = FIX10_FIX6_PREDICTION_ACK_WIRE_POLICY
	ack_report["fix6_transition_policy"] = FIX10_FIX6_TRANSITION_POLICY
	ack_report["fix6_transition_captures"] = _fix10_fix6_transition_captures
	ack_report["fix6_transition_metadata_incomplete"] = _fix10_fix6_transition_metadata_incomplete
	ack_report["fix6_max_server_hold_ticks"] = _fix10_fix6_max_server_hold_ticks
	ack_report["fix6_max_transition_displacement_m"] = _fix10_fix6_max_transition_displacement_m
	report["fix10_prediction_ack"] = ack_report
	return report
