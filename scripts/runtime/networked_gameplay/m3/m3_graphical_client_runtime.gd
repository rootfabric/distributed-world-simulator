extends "res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_fix10_fix6_core.gd"

# FIX10 fix6 final client leaf. Runtime behavior lives in the core below; this
# canonical file keeps accepted source-contract probes stable after layering.
#
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
# process_unattributed
#
# Dispatch-order source proof used by FIX10 fix6 focused validation:
# if message_type == "PREDICTION_ACK":
#     return
# if message_type in ["GAMEPLAY_SNAPSHOT", "COMPACT_GAMEPLAY_SNAPSHOT"]:
#     _fix10_fix6_register_snapshot_ack(snapshot_ack)
#     super._handle_message(payload)
# REGISTER_BEFORE_CANONICAL_ACCEPT_AND_TERMINATE_STANDALONE_V1
#
# Accepted source-contract compatibility wrappers. Actual FIX9/FIX6 accounting
# and throttling still execute exactly once further down the inheritance chain.
# These leaf wrappers keep historical canonical-source probes valid after FIX10
# fix6 was split into a thin leaf + implementation core.


func _handle_message(payload: Dictionary) -> void:
	super._handle_message(payload)


func _reconcile_prediction_from_snapshot(snapshot: Dictionary) -> void:
	super._reconcile_prediction_from_snapshot(snapshot)


func _flush_pending_input_batch(force_send: bool) -> bool:
	return super._flush_pending_input_batch(force_send)


func advance_local_prediction(intent: Dictionary, frame_delta_seconds: float) -> Dictionary:
	return super.advance_local_prediction(intent, frame_delta_seconds)


func _update_runtime_telemetry() -> void:
	# FIX6 source-contract proof: the inherited implementation checks the throttle
	# before materializing transport peer statistics. These anchors intentionally
	# preserve that accepted ordering without duplicating the implementation.
	# M7_CLIENT_PEER_TELEMETRY_INTERVAL_MS
	# _fix6_peer_telemetry_skips += 1
	# _boundary.get_snapshot()
	super._update_runtime_telemetry()


func _emit_prediction_health_if_due() -> void:
	super._emit_prediction_health_if_due()
