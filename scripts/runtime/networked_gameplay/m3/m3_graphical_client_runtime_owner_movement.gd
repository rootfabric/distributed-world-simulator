extends "res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd"

const OwnerPlayableStateCodec = preload(
	"res://scripts/runtime/listen_host/playable_state_codec.gd"
)

# Experimental owner-authoritative locomotion leaf, analogous to an owner-
# authoritative NetworkTransform. The local prediction kernel is the only writer
# of the owning player's visible transform. At the existing semantic cadence the
# already-simulated local state is sent to the server for validation and relay.
# Routine server snapshots still update the replica/remote world but never rewind
# the owner's locomotion. A rejected PLAYER_STATE remains observable as an async
# server rejection and can later drive an explicit recovery policy.
const OWNER_MOVEMENT_AUTHORITY_MODE: String = "OWNER_AUTHORITATIVE_VALIDATED"
const OWNER_MOVEMENT_CLIENT_POLICY: String = \
	"LOCAL_TRANSFORM_SINGLE_WRITER_STATE_POSTFACTUM_TO_SERVER_V1"

var _owner_state_submissions: int = 0
var _owner_state_send_failures: int = 0
var _owner_snapshot_reconciliations_skipped: int = 0
var _owner_last_state_send_ms: int = 0
var _owner_last_state_sequence: int = 0


func setup(config: Dictionary) -> Dictionary:
	_owner_state_submissions = 0
	_owner_state_send_failures = 0
	_owner_snapshot_reconciliations_skipped = 0
	_owner_last_state_send_ms = 0
	_owner_last_state_sequence = 0
	return super.setup(config)


func submit_movement_intent_nonblocking(
	intent: Dictionary,
	_client_tick: int = 0
) -> Dictionary:
	# Preserve the accepted semantic cadence and prediction sequence identity, but
	# do not send an input batch in owner-authoritative mode. The caller advances
	# the local fixed simulation immediately; advance_local_prediction() below then
	# sends the resulting state using the same sequence.
	if not is_ready():
		return _failure("M7_CLIENT_NOT_READY")
	_input_sequence = InputSequence.next(_input_sequence)
	var operation_id: String = "operation/m7/%s/owner-state/%d/%d" % [
		_logical_player_id, OS.get_process_id(), _input_sequence
	]
	if _prediction_reconciler != null and _prediction_reconciler.is_configured():
		var prediction_input: Dictionary = _prediction_reconciler.set_input(
			_input_sequence, intent
		)
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
	var result: Dictionary = super.advance_local_prediction(intent, frame_delta_seconds)
	if not bool(result.get("success", false)):
		return result
	var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
	if not bool(details.get("submission_attempted", false)):
		return result
	var predicted_state: Dictionary = Dictionary(details.get("predicted_state", {}))
	if predicted_state.is_empty():
		_owner_state_send_failures += 1
		return _failure("OWNER_PREDICTED_STATE_REQUIRED")
	var player_state: Dictionary = _owner_playable_state(predicted_state)
	if player_state.is_empty():
		_owner_state_send_failures += 1
		return _failure("OWNER_PLAYER_STATE_BUILD_FAILED")
	var state_submission: Dictionary = submit_player_state_nonblocking(
		player_state,
		_owner_state_delta_seconds()
	)
	details["submission"] = state_submission.duplicate(true)
	details["owner_state_submission"] = state_submission.duplicate(true)
	result["details"] = details
	if not bool(state_submission.get("success", false)):
		_owner_state_send_failures += 1
		return state_submission
	_owner_state_submissions += 1
	_owner_last_state_sequence = int(player_state.get("last_input_sequence", 0))
	return result


func submit_player_state_nonblocking(
	player_state: Dictionary,
	delta_seconds: float
) -> Dictionary:
	if not is_ready():
		return _failure("M7_CLIENT_NOT_READY")
	var validation: Dictionary = OwnerPlayableStateCodec.validate_player_state(player_state)
	if not bool(validation.get("success", false)):
		return _failure(String(validation.get("error_code", "INVALID_OWNER_PLAYER_STATE")))
	var input_sequence: int = int(player_state.get("last_input_sequence", 0))
	if input_sequence < 1:
		return _failure("OWNER_STATE_INPUT_SEQUENCE_REQUIRED")
	var operation_id: String = "operation/m7/%s/owner-state/%d/%d" % [
		_logical_player_id, OS.get_process_id(), input_sequence
	]
	var sent: bool = _send_on_channel(
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
		"movement_authority_mode": OWNER_MOVEMENT_AUTHORITY_MODE,
	}) if sent else _failure("M7_OWNER_PLAYER_STATE_SEND_FAILED")


func submit_player_state_blocking(
	player_state: Dictionary,
	delta_seconds: float
) -> Dictionary:
	# Owner locomotion is a realtime state stream. A blocking request/response path
	# would reintroduce latency into the controller, so the compatibility method is
	# intentionally a nonblocking send with explicit classification.
	var result: Dictionary = submit_player_state_nonblocking(player_state, delta_seconds)
	if bool(result.get("success", false)):
		var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
		details["blocking_semantics"] = "REALTIME_SEND_ONLY"
		result["details"] = details
	return result


func _reconcile_prediction_from_snapshot(_snapshot: Dictionary) -> void:
	# This is the core owner-authority invariant: routine server snapshots cannot
	# move the camera/body underneath the owning player. The same snapshot still
	# enters the canonical replica store and therefore updates remote players,
	# items, checksums and acknowledgement/pruning state outside this method.
	_owner_snapshot_reconciliations_skipped += 1


func _owner_playable_state(predicted_state: Dictionary) -> Dictionary:
	var position_value: Dictionary = Dictionary(predicted_state.get("position", {}))
	var velocity_value: Dictionary = Dictionary(predicted_state.get("velocity", {}))
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
	var yaw: float = float(predicted_state.get("orientation_yaw", 0.0))
	var local_record: Dictionary = get_local_player_record()
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
	var now_ms: int = Time.get_ticks_msec()
	var delta_seconds: float = NX4_INPUT_SEND_INTERVAL_SECONDS
	if _owner_last_state_send_ms > 0:
		delta_seconds = float(maxi(now_ms - _owner_last_state_send_ms, 1)) / 1000.0
	_owner_last_state_send_ms = now_ms
	return clampf(delta_seconds, 0.001, 0.25)


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	report["movement_authority_mode"] = OWNER_MOVEMENT_AUTHORITY_MODE
	report["movement_authority_policy"] = OWNER_MOVEMENT_CLIENT_POLICY
	report["owner_state_submissions"] = _owner_state_submissions
	report["owner_state_send_failures"] = _owner_state_send_failures
	report["owner_snapshot_reconciliations_skipped"] = \
		_owner_snapshot_reconciliations_skipped
	report["owner_last_state_sequence"] = _owner_last_state_sequence
	return report
