extends "res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd"

const MovementAuthorityProfile = preload(
	"res://scripts/network/authority/movement_authority_profile.gd"
)
const OwnerPlayableStateCodec = preload(
	"res://scripts/runtime/listen_host/playable_state_codec.gd"
)

# The local prediction kernel is the only writer of the owning player's
# locomotion presentation. After local fixed simulation, the resulting state is
# sent to the server for validation and relay. Routine accepted snapshots update
# replicas/remote players without rewinding the local owner. An explicit server
# rejection arms exactly one authoritative reconciliation so invalid local state
# cannot diverge forever.
const OWNER_MOVEMENT_CLIENT_POLICY: String = \
	"LOCAL_TRANSFORM_SINGLE_WRITER_RECONCILE_ON_REJECTION_V1"

var _owner_state_submissions: int = 0
var _owner_state_send_failures: int = 0
var _owner_state_rejections_received: int = 0
var _owner_snapshot_reconciliations_skipped: int = 0
var _owner_rejection_reconciliations: int = 0
var _owner_reconciliation_required: bool = false
var _owner_last_state_send_ms: int = 0
var _owner_last_state_sequence: int = 0
var _owner_pending_state_sequence: int = 0
var _owner_state_submit_deferrals: int = 0


func setup(config: Dictionary) -> Dictionary:
	_owner_state_submissions = 0
	_owner_state_send_failures = 0
	_owner_state_rejections_received = 0
	_owner_snapshot_reconciliations_skipped = 0
	_owner_rejection_reconciliations = 0
	_owner_reconciliation_required = false
	_owner_last_state_send_ms = 0
	_owner_last_state_sequence = 0
	_owner_pending_state_sequence = 0
	_owner_state_submit_deferrals = 0
	return super.setup(config)


func submit_movement_intent_nonblocking(
	intent: Dictionary,
	_client_tick: int = 0
) -> Dictionary:
	if not is_ready():
		return _failure("NX_C1_CLIENT_NOT_READY")

	# Keep the existing input sequence as semantic identity, but do not send the
	# server-predicted input batch. advance_local_prediction() simulates locally
	# and then submits the state carrying this exact sequence.
	_input_sequence = InputSequence.next(_input_sequence)
	_owner_pending_state_sequence = _input_sequence
	var operation_id := "operation/nx-c1/%s/owner-state/%d/%d" % [
		_logical_player_id,
		OS.get_process_id(),
		_input_sequence,
	]
	if _prediction_reconciler != null and _prediction_reconciler.is_configured():
		var prediction_input := _prediction_reconciler.set_input(_input_sequence, intent)
		if not bool(prediction_input.get("success", false)):
			_prediction_submit_failures += 1
			return prediction_input
	return _success({
		"operation_id": operation_id,
		"input_sequence": _input_sequence,
		"expect_result": false,
		"owner_local_only_until_state_submit": true,
	})


func advance_local_prediction(
	intent: Dictionary,
	frame_delta_seconds: float
) -> Dictionary:
	var result := super.advance_local_prediction(intent, frame_delta_seconds)
	if not bool(result.get("success", false)) or _owner_pending_state_sequence < 1:
		return result

	var details := Dictionary(result.get("details", {})).duplicate(true)
	var predicted_state := Dictionary(details.get("predicted_state", {}))
	if predicted_state.is_empty():
		_owner_state_submit_deferrals += 1
		return result
	var predicted_sequence := int(predicted_state.get("last_input_sequence", 0))
	if predicted_sequence != _owner_pending_state_sequence:
		_owner_state_submit_deferrals += 1
		return result

	var player_state := _owner_playable_state(predicted_state)
	if player_state.is_empty():
		_owner_state_send_failures += 1
		return _failure("OWNER_PLAYER_STATE_BUILD_FAILED")
	var state_submission := submit_player_state_nonblocking(
		player_state,
		_owner_state_delta_seconds()
	)
	details["owner_state_submission"] = state_submission.duplicate(true)
	if bool(details.get("submission_attempted", false)):
		details["submission"] = state_submission.duplicate(true)
	result["details"] = details
	if not bool(state_submission.get("success", false)):
		_owner_state_send_failures += 1
		return state_submission

	_owner_state_submissions += 1
	_owner_last_state_sequence = predicted_sequence
	_owner_pending_state_sequence = 0
	return result


func submit_player_state_nonblocking(
	player_state: Dictionary,
	delta_seconds: float
) -> Dictionary:
	if not is_ready():
		return _failure("NX_C1_CLIENT_NOT_READY")
	var validation := OwnerPlayableStateCodec.validate_player_state(player_state)
	if not bool(validation.get("success", false)):
		return _failure(String(validation.get("error_code", "INVALID_OWNER_PLAYER_STATE")))
	var input_sequence := int(player_state.get("last_input_sequence", 0))
	if input_sequence < 1:
		return _failure("OWNER_STATE_INPUT_SEQUENCE_REQUIRED")

	var operation_id := "operation/nx-c1/%s/owner-state/%d/%d" % [
		_logical_player_id,
		OS.get_process_id(),
		input_sequence,
	]
	var sent := _send_on_channel(
		"PLAYER_STATE",
		{
			"logical_player_id": _logical_player_id,
			"ownership_epoch": _ownership_epoch,
			"input_sequence": input_sequence,
			"operation_id": operation_id,
			"player_state": player_state.duplicate(true),
			"delta_seconds": clampf(delta_seconds, 0.001, 0.25),
		},
		RealtimeChannelPolicy.INPUT,
		"UNRELIABLE_SEQUENCED",
		false
	)
	return _success({
		"operation_id": operation_id,
		"input_sequence": input_sequence,
		"expect_result": false,
		"movement_authority_mode": MovementAuthorityProfile.OWNER_AUTHORITATIVE_VALIDATED,
	}) if sent else _failure("NX_C1_OWNER_PLAYER_STATE_SEND_FAILED")


func submit_player_state_blocking(
	player_state: Dictionary,
	delta_seconds: float
) -> Dictionary:
	# Realtime locomotion must never wait on an RTT. Keep this compatibility entry
	# point nonblocking and make its semantics explicit in the result.
	var result := submit_player_state_nonblocking(player_state, delta_seconds)
	if bool(result.get("success", false)):
		var details := Dictionary(result.get("details", {})).duplicate(true)
		details["blocking_semantics"] = "REALTIME_SEND_ONLY"
		result["details"] = details
	return result


func _handle_message(payload: Dictionary) -> void:
	if (
		String(payload.get("type", "")) == "COMMAND_RESULT"
		and String(payload.get("command_type", "")) == "PLAYER_STATE"
		and String(payload.get("status", "")) != "SUCCEEDED"
		and _is_owner_state_operation(String(payload.get("operation_id", "")))
	):
		_owner_state_rejections_received += 1
		_owner_reconciliation_required = true
	super._handle_message(payload)


func _reconcile_prediction_from_snapshot(snapshot: Dictionary) -> void:
	if _owner_reconciliation_required:
		# The server explicitly rejected an owner-authored state. Apply one normal
		# authoritative reconciliation on the next usable snapshot, then resume
		# the no-routine-rewind policy.
		var local_player := _player_from_snapshot(snapshot, _logical_player_id)
		if not local_player.is_empty():
			super._reconcile_prediction_from_snapshot(snapshot)
			_owner_reconciliation_required = false
			_owner_rejection_reconciliations += 1
			return
	_owner_snapshot_reconciliations_skipped += 1


func _is_owner_state_operation(operation_id: String) -> bool:
	return operation_id.begins_with("operation/nx-c1/%s/owner-state/" % _logical_player_id)


func _owner_playable_state(predicted_state: Dictionary) -> Dictionary:
	var position_value := Dictionary(predicted_state.get("position", {}))
	var velocity_value := Dictionary(predicted_state.get("velocity", {}))
	var position := Vector3(
		float(position_value.get("x", 0.0)),
		float(position_value.get("y", 0.0)),
		float(position_value.get("z", 0.0))
	)
	var velocity := Vector3(
		float(velocity_value.get("x", 0.0)),
		float(velocity_value.get("y", 0.0)),
		float(velocity_value.get("z", 0.0))
	)
	var yaw := float(predicted_state.get("orientation_yaw", 0.0))
	var local_record := get_local_player_record()
	return OwnerPlayableStateCodec.create_player_state(
		position,
		Basis(Vector3.UP, yaw),
		velocity,
		position,
		"flat_humanoid",
		"first_person",
		bool(local_record.get("flashlight_enabled", false)),
		int(predicted_state.get("last_input_sequence", _input_sequence)),
		"scenario/playground/local",
		"main",
		"playground",
		"scenario-playground",
		float(Time.get_ticks_msec()) / 1000.0
	)


func _owner_state_delta_seconds() -> float:
	var now_ms := Time.get_ticks_msec()
	var delta_seconds := NX4_INPUT_SEND_INTERVAL_SECONDS
	if _owner_last_state_send_ms > 0:
		delta_seconds = float(maxi(now_ms - _owner_last_state_send_ms, 1)) / 1000.0
	_owner_last_state_send_ms = now_ms
	return clampf(delta_seconds, 0.001, 0.25)


func get_report() -> Dictionary:
	var report := super.get_report()
	report["movement_authority_mode"] = MovementAuthorityProfile.OWNER_AUTHORITATIVE_VALIDATED
	report["movement_authority_policy"] = OWNER_MOVEMENT_CLIENT_POLICY
	report["owner_state_submissions"] = _owner_state_submissions
	report["owner_state_send_failures"] = _owner_state_send_failures
	report["owner_state_rejections_received"] = _owner_state_rejections_received
	report["owner_snapshot_reconciliations_skipped"] = _owner_snapshot_reconciliations_skipped
	report["owner_rejection_reconciliations"] = _owner_rejection_reconciliations
	report["owner_reconciliation_required"] = _owner_reconciliation_required
	report["owner_last_state_sequence"] = _owner_last_state_sequence
	report["owner_pending_state_sequence"] = _owner_pending_state_sequence
	report["owner_state_submit_deferrals"] = _owner_state_submit_deferrals
	return report
