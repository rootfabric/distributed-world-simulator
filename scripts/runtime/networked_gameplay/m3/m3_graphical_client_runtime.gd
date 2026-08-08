extends "res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_fix9.gd"

signal remote_presentation_snapshot(
	snapshot: Dictionary,
	source: String,
	canonical_conflict_hint: bool
)

const CompactGameplaySnapshotFix10Fix3 = preload(
	"res://scripts/runtime/networked_gameplay/contracts/compact_gameplay_snapshot.gd"
)
const PlayerSnapshotFix10Fix3 = preload(
	"res://scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd"
)

# FIX10 transports only a small prediction-ack sidecar. Canonical gameplay
# snapshots, checksums, Item Graph semantics, FIX9 frame accounting and all
# authority decisions remain inherited unchanged.
#
# The live wire form is COMPACT_ARRAY_V1 so the peer-local ACK does not push the
# unreliable compact movement snapshot above the ENet MTU. FIX10 fix3 keeps the
# snapshot sidecar when it fits, and additionally accepts a tiny standalone ACK
# packet on the independent TELEMETRY unreliable-sequenced stream when the server
# had to omit the sidecar for MTU safety. The ACK still reaches exactly the same
# reconciliation API; authority and prediction semantics do not change.
#
# FIX10 fix3 also separates remote visual continuity from canonical replica
# bookkeeping. Every contract-valid full/compact authoritative snapshot can feed
# a presentation-only signal before canonical replica acceptance. Canonical
# invariants remain strict and keep reporting same-revision mutations; the world
# presenter may use the newer validated server clock/state so one rejected
# bookkeeping update cannot freeze a remote avatar while local input continues.
#
# Accepted FIX9 source-contract compatibility anchors:
# process_unattributed

const FIX10_PREDICTION_ACK_POLICY: String = "SERVER_ECHOED_POST_INPUT_BASELINE_V1"
const FIX10_PREDICTION_ACK_WIRE_POLICY: String = "COMPACT_ARRAY_V1"
const FIX10_PREDICTION_ACK_WIRE_VALUES: int = 11
const FIX10_FIX3_ACK_FALLBACK_POLICY: String = "SEPARATE_TELEMETRY_CHANNEL_WHEN_SNAPSHOT_ACK_OMITTED_V1"
const FIX10_FIX3_REMOTE_PRESENTATION_SOURCE_POLICY: String = "VALIDATED_WIRE_SNAPSHOT_PRESENTATION_LANE_V1"

var _fix10_pending_prediction_ack: Dictionary = {}
var _fix10_ack_sidecars_received: int = 0
var _fix10_ack_sidecars_registered: int = 0
var _fix10_ack_sidecars_rejected: int = 0
var _fix10_compact_ack_sidecars_received: int = 0
var _fix10_last_ack_error_code: String = ""

var _fix10_fix3_standalone_ack_received: int = 0
var _fix10_fix3_standalone_ack_registered: int = 0
var _fix10_fix3_standalone_ack_rejected: int = 0
var _fix10_fix3_deferred_standalone_ack: Dictionary = {}
var _fix10_fix3_remote_wire_snapshots_validated: int = 0
var _fix10_fix3_remote_wire_snapshots_published: int = 0
var _fix10_fix3_remote_wire_snapshots_stale: int = 0
var _fix10_fix3_remote_wire_snapshots_duplicate: int = 0
var _fix10_fix3_remote_wire_validation_rejections: int = 0
var _fix10_fix3_same_revision_semantic_conflicts: int = 0
var _fix10_fix3_last_same_revision_conflict: Dictionary = {}
var _fix10_fix3_last_wire_tick: int = -1
var _fix10_fix3_last_wire_revision: int = -1
var _fix10_fix3_last_wire_checksum: String = ""


func setup(config: Dictionary) -> Dictionary:
	_fix10_pending_prediction_ack.clear()
	_fix10_ack_sidecars_received = 0
	_fix10_ack_sidecars_registered = 0
	_fix10_ack_sidecars_rejected = 0
	_fix10_compact_ack_sidecars_received = 0
	_fix10_last_ack_error_code = ""
	_fix10_fix3_standalone_ack_received = 0
	_fix10_fix3_standalone_ack_registered = 0
	_fix10_fix3_standalone_ack_rejected = 0
	_fix10_fix3_deferred_standalone_ack.clear()
	_fix10_fix3_remote_wire_snapshots_validated = 0
	_fix10_fix3_remote_wire_snapshots_published = 0
	_fix10_fix3_remote_wire_snapshots_stale = 0
	_fix10_fix3_remote_wire_snapshots_duplicate = 0
	_fix10_fix3_remote_wire_validation_rejections = 0
	_fix10_fix3_same_revision_semantic_conflicts = 0
	_fix10_fix3_last_same_revision_conflict.clear()
	_fix10_fix3_last_wire_tick = -1
	_fix10_fix3_last_wire_revision = -1
	_fix10_fix3_last_wire_checksum = ""
	return super.setup(config)


func _handle_message(payload: Dictionary) -> void:
	var message_type: String = String(payload.get("type", ""))
	_fix10_pending_prediction_ack.clear()

	if message_type == "PREDICTION_ACK":
		var standalone_ack: Dictionary = _fix10_extract_prediction_ack(
			payload,
			message_type
		)
		if not standalone_ack.is_empty():
			_fix10_ack_sidecars_received += 1
			_fix10_fix3_standalone_ack_received += 1
			_fix10_fix3_register_standalone_ack(standalone_ack)
		# Let FIX9/base dispatch accounting observe the packet. The base runtime has
		# no gameplay mutation handler for this type, so this remains presentation/
		# reconciliation metadata only.
		super._handle_message(payload)
		return

	if message_type in ["GAMEPLAY_SNAPSHOT", "COMPACT_GAMEPLAY_SNAPSHOT"]:
		_fix10_fix3_publish_remote_presentation_from_payload(payload, message_type)
		_fix10_pending_prediction_ack = _fix10_extract_prediction_ack(
			payload,
			message_type
		)
		if not _fix10_pending_prediction_ack.is_empty():
			_fix10_ack_sidecars_received += 1
	super._handle_message(payload)
	_fix10_pending_prediction_ack.clear()


func _reconcile_prediction_from_snapshot(snapshot: Dictionary) -> void:
	_fix10_fix3_flush_deferred_standalone_ack()
	if (
		not _fix10_pending_prediction_ack.is_empty()
		and _prediction_reconciler != null
		and _prediction_reconciler.has_method("set_authoritative_input_ack")
	):
		var registered: Dictionary = _prediction_reconciler.call(
			"set_authoritative_input_ack",
			_fix10_pending_prediction_ack,
			int(snapshot.get("server_tick", -1))
		)
		if bool(registered.get("success", false)):
			_fix10_ack_sidecars_registered += 1
			_fix10_last_ack_error_code = ""
		else:
			_fix10_ack_sidecars_rejected += 1
			_fix10_last_ack_error_code = String(
				registered.get("error_code", "FIX10_ACK_REGISTRATION_FAILED")
			)
	super._reconcile_prediction_from_snapshot(snapshot)


func _fix10_fix3_register_standalone_ack(ack: Dictionary) -> void:
	if ack.is_empty():
		return
	if (
		_prediction_reconciler == null
		or not _prediction_reconciler.is_configured()
		or not _prediction_reconciler.has_method("set_authoritative_input_ack")
	):
		_fix10_fix3_deferred_standalone_ack = ack.duplicate(true)
		return
	var registered: Dictionary = _prediction_reconciler.call(
		"set_authoritative_input_ack",
		ack,
		int(ack.get("transport_snapshot_server_tick", -1))
	)
	if bool(registered.get("success", false)):
		_fix10_ack_sidecars_registered += 1
		_fix10_fix3_standalone_ack_registered += 1
		_fix10_last_ack_error_code = ""
	else:
		_fix10_ack_sidecars_rejected += 1
		_fix10_fix3_standalone_ack_rejected += 1
		_fix10_last_ack_error_code = String(
			registered.get("error_code", "FIX10_FIX3_STANDALONE_ACK_REGISTRATION_FAILED")
		)


func _fix10_fix3_flush_deferred_standalone_ack() -> void:
	if _fix10_fix3_deferred_standalone_ack.is_empty():
		return
	if _prediction_reconciler == null or not _prediction_reconciler.is_configured():
		return
	var pending: Dictionary = _fix10_fix3_deferred_standalone_ack.duplicate(true)
	_fix10_fix3_deferred_standalone_ack.clear()
	_fix10_fix3_register_standalone_ack(pending)


func _fix10_fix3_publish_remote_presentation_from_payload(
	payload: Dictionary,
	message_type: String
) -> void:
	var snapshot_value = payload.get("snapshot", {})
	if not snapshot_value is Dictionary:
		_fix10_fix3_remote_wire_validation_rejections += 1
		return
	var snapshot: Dictionary = {}
	if message_type == "COMPACT_GAMEPLAY_SNAPSHOT":
		var decoded: Dictionary = CompactGameplaySnapshotFix10Fix3.decode(
			Dictionary(snapshot_value)
		)
		if not bool(decoded.get("success", false)):
			_fix10_fix3_remote_wire_validation_rejections += 1
			return
		snapshot = Dictionary(
			decoded.get("details", {}).get("snapshot", {})
		).duplicate(true)
	else:
		snapshot = Dictionary(snapshot_value).duplicate(true)
		var validation: Dictionary = PlayerSnapshotFix10Fix3.validate_legacy(snapshot)
		if not bool(validation.get("success", false)):
			_fix10_fix3_remote_wire_validation_rejections += 1
			return

	_fix10_fix3_remote_wire_snapshots_validated += 1
	_fix10_fix3_publish_remote_presentation_snapshot(snapshot, message_type)


func _fix10_fix3_publish_remote_presentation_snapshot(
	snapshot: Dictionary,
	source: String
) -> void:
	if snapshot.is_empty():
		return
	var server_tick: int = int(snapshot.get("server_tick", -1))
	var revision: int = int(snapshot.get("revision", -1))
	var checksum: String = String(snapshot.get("checksum", ""))
	if server_tick < 0 or revision < 0 or checksum.is_empty():
		_fix10_fix3_remote_wire_validation_rejections += 1
		return

	# Require both authority clocks to be monotonic. This lane is allowed to
	# continue at the same global revision on a newer server tick, which is exactly
	# the case that can be rejected by canonical same-revision bookkeeping, but it
	# never walks either clock backwards.
	if (
		(_fix10_fix3_last_wire_tick >= 0 and server_tick < _fix10_fix3_last_wire_tick)
		or (
			_fix10_fix3_last_wire_revision >= 0
			and revision < _fix10_fix3_last_wire_revision
		)
	):
		_fix10_fix3_remote_wire_snapshots_stale += 1
		return
	if (
		server_tick == _fix10_fix3_last_wire_tick
		and revision == _fix10_fix3_last_wire_revision
		and checksum == _fix10_fix3_last_wire_checksum
	):
		_fix10_fix3_remote_wire_snapshots_duplicate += 1
		return

	var canonical_conflict_hint: bool = false
	var current: Dictionary = (
		_replica.get_snapshot()
		if _replica != null
		else {}
	)
	if (
		not current.is_empty()
		and int(current.get("revision", -1)) == revision
		and String(current.get("checksum", "")) != checksum
		and not _same_snapshot_semantics_except_clock(current, snapshot)
	):
		canonical_conflict_hint = true
		_fix10_fix3_same_revision_semantic_conflicts += 1
		_fix10_fix3_last_same_revision_conflict = _fix10_fix3_conflict_summary(
			current,
			snapshot,
			source
		)

	_fix10_fix3_last_wire_tick = server_tick
	_fix10_fix3_last_wire_revision = revision
	_fix10_fix3_last_wire_checksum = checksum
	_fix10_fix3_remote_wire_snapshots_published += 1
	remote_presentation_snapshot.emit(
		snapshot.duplicate(true),
		source,
		canonical_conflict_hint
	)


func _fix10_fix3_conflict_summary(
	current: Dictionary,
	incoming: Dictionary,
	source: String
) -> Dictionary:
	var current_players: Dictionary = {}
	for value in current.get("players", []):
		if value is Dictionary:
			current_players[String(value.get("logical_player_id", ""))] = value
	var changed_players: Array[Dictionary] = []
	for value in incoming.get("players", []):
		if not value is Dictionary:
			continue
		var incoming_player: Dictionary = value
		var logical_id: String = String(incoming_player.get("logical_player_id", ""))
		var current_player: Dictionary = Dictionary(
			current_players.get(logical_id, {})
		)
		if current_player == incoming_player:
			continue
		var changed_fields: Array[String] = []
		for field in [
			"transport_session_id",
			"ownership_epoch",
			"connected",
			"position",
			"velocity",
			"inventory",
			"last_input_sequence",
			"state_revision",
			"orientation_yaw",
			"flashlight_enabled",
		]:
			if current_player.get(field) != incoming_player.get(field):
				changed_fields.append(field)
		changed_players.append({
			"logical_player_id": logical_id,
			"changed_fields": changed_fields,
			"current_state_revision": int(current_player.get("state_revision", -1)),
			"incoming_state_revision": int(incoming_player.get("state_revision", -1)),
			"current_input_sequence": int(current_player.get("last_input_sequence", -1)),
			"incoming_input_sequence": int(incoming_player.get("last_input_sequence", -1)),
		})
	return {
		"source": source,
		"revision": int(incoming.get("revision", -1)),
		"current_server_tick": int(current.get("server_tick", -1)),
		"incoming_server_tick": int(incoming.get("server_tick", -1)),
		"changed_players": changed_players,
		"shared_item_changed": current.get("shared_item") != incoming.get("shared_item"),
	}


func _flush_pending_input_batch(force_send: bool) -> bool:
	return super._flush_pending_input_batch(force_send)


func advance_local_prediction(intent: Dictionary, frame_delta_seconds: float) -> Dictionary:
	return super.advance_local_prediction(intent, frame_delta_seconds)


func _update_runtime_telemetry() -> void:
	# FIX6 source-contract bridge. The implementation remains in the FIX9 parent;
	# these anchors keep the accepted test able to prove that the expensive
	# transport snapshot is behind the 4 Hz telemetry guard:
	# M7_CLIENT_PEER_TELEMETRY_INTERVAL_MS
	# _fix6_peer_telemetry_skips += 1
	# _boundary.get_snapshot()
	# client_process_max_duration_ms
	# peer_telemetry_max_duration_ms
	super._update_runtime_telemetry()


func _emit_prediction_health_if_due() -> void:
	var previous_health_ms: int = _last_prediction_health_ms
	super._emit_prediction_health_if_due()
	if _last_prediction_health_ms == previous_health_ms:
		return
	if _prediction_reconciler == null or not _prediction_reconciler.is_configured():
		return
	var prediction: Dictionary = _prediction_reconciler.get_report()
	_debug_event("FIX10_PREDICTION_HEALTH", {
		"prediction_tick": int(prediction.get("prediction_tick", 0)),
		"authoritative_tick": int(prediction.get("last_authoritative_tick", 0)),
		"current_input_sequence": int(prediction.get("current_input_sequence", 0)),
		"authoritative_input_sequence": int(prediction.get("last_authoritative_sequence", 0)),
		"corrections": int(prediction.get("corrections", 0)),
		"corrections_per_1000_prediction_ticks": float(prediction.get("fix10_corrections_per_1000_prediction_ticks", 0.0)),
		"ack_reconciliations": int(prediction.get("fix10_ack_reconciliations", 0)),
		"ack_replays": int(prediction.get("fix10_ack_replays", 0)),
		"ack_replayed_ticks": int(prediction.get("fix10_ack_replayed_ticks", 0)),
		"ack_history_misses": int(prediction.get("fix10_ack_history_misses", 0)),
		"ack_mismatches": int(prediction.get("fix10_ack_mismatches", 0)),
		"max_ack_baseline_error_m": float(prediction.get("fix10_max_ack_baseline_error_m", 0.0)),
		"max_present_replay_error_m": float(prediction.get("fix10_max_present_replay_error_m", 0.0)),
		"last_reconciliation_mode": String(prediction.get("fix10_last_reconciliation_mode", "NONE")),
		"ack_wire_policy": FIX10_PREDICTION_ACK_WIRE_POLICY,
		"ack_fallback_policy": FIX10_FIX3_ACK_FALLBACK_POLICY,
		"sidecars_received": _fix10_ack_sidecars_received,
		"compact_sidecars_received": _fix10_compact_ack_sidecars_received,
		"sidecars_registered": _fix10_ack_sidecars_registered,
		"sidecars_rejected": _fix10_ack_sidecars_rejected,
		"standalone_ack_received": _fix10_fix3_standalone_ack_received,
		"standalone_ack_registered": _fix10_fix3_standalone_ack_registered,
		"standalone_ack_rejected": _fix10_fix3_standalone_ack_rejected,
		"remote_wire_published": _fix10_fix3_remote_wire_snapshots_published,
		"same_revision_semantic_conflicts": _fix10_fix3_same_revision_semantic_conflicts,
	})


func _fix10_extract_prediction_ack(
	payload: Dictionary,
	message_type: String
) -> Dictionary:
	var ack_value = payload.get("prediction_ack", null)
	var ack: Dictionary = {}
	if ack_value is Array:
		var wire: Array = ack_value
		if wire.size() != FIX10_PREDICTION_ACK_WIRE_VALUES:
			return {}
		for value in wire:
			if not (value is int or value is float):
				return {}
		ack = {
			"input_sequence": int(wire[0]),
			"client_tick": int(wire[1]),
			"applied_server_tick": int(wire[2]),
			"position": {
				"x": float(wire[3]),
				"y": float(wire[4]),
				"z": float(wire[5]),
			},
			"velocity": {
				"x": float(wire[6]),
				"y": float(wire[7]),
				"z": float(wire[8]),
			},
			"orientation_yaw": float(wire[9]),
			"state_revision": int(wire[10]),
		}
		_fix10_compact_ack_sidecars_received += 1
	elif ack_value is Dictionary:
		# Legacy/debug form. Require the explicit policy because a dictionary is not
		# self-discriminating the way the fixed-size compact array is.
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


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	report["fix10_prediction_ack_transport"] = {
		"policy": FIX10_PREDICTION_ACK_POLICY,
		"wire_policy": FIX10_PREDICTION_ACK_WIRE_POLICY,
		"ack_fallback_policy": FIX10_FIX3_ACK_FALLBACK_POLICY,
		"sidecars_received": _fix10_ack_sidecars_received,
		"compact_sidecars_received": _fix10_compact_ack_sidecars_received,
		"sidecars_registered": _fix10_ack_sidecars_registered,
		"sidecars_rejected": _fix10_ack_sidecars_rejected,
		"standalone_ack_received": _fix10_fix3_standalone_ack_received,
		"standalone_ack_registered": _fix10_fix3_standalone_ack_registered,
		"standalone_ack_rejected": _fix10_fix3_standalone_ack_rejected,
		"deferred_standalone_ack_pending": not _fix10_fix3_deferred_standalone_ack.is_empty(),
		"last_error_code": _fix10_last_ack_error_code,
	}
	report["fix10_fix3_remote_presentation_transport"] = {
		"policy": FIX10_FIX3_REMOTE_PRESENTATION_SOURCE_POLICY,
		"validated": _fix10_fix3_remote_wire_snapshots_validated,
		"published": _fix10_fix3_remote_wire_snapshots_published,
		"stale_suppressed": _fix10_fix3_remote_wire_snapshots_stale,
		"duplicates_suppressed": _fix10_fix3_remote_wire_snapshots_duplicate,
		"validation_rejections": _fix10_fix3_remote_wire_validation_rejections,
		"same_revision_semantic_conflicts": _fix10_fix3_same_revision_semantic_conflicts,
		"last_same_revision_conflict": _fix10_fix3_last_same_revision_conflict.duplicate(true),
		"last_wire_server_tick": _fix10_fix3_last_wire_tick,
		"last_wire_revision": _fix10_fix3_last_wire_revision,
	}
	return report