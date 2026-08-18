extends "res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd"

const MovementAuthorityProfile = preload(
	"res://scripts/network/authority/movement_authority_profile.gd"
)
const OwnerPlayableStateCodec = preload(
	"res://scripts/runtime/listen_host/playable_state_codec.gd"
)

# This leaf changes only realtime locomotion authorship. The server still owns
# player identity/session fencing and all durable gameplay truth. A submitted
# owner pose becomes canonical only after the existing movement validator accepts
# sequence, speed and displacement bounds.
const OWNER_MOVEMENT_AUTHORITY_POLICY: String = \
	"OWNER_AUTHORS_TRANSFORM_SERVER_VALIDATES_AND_RELAYS_V1"
const OWNER_BASIS_YAW_ROUNDTRIP_POLICY: String = \
	"GODOT_FORWARD_MINUS_Z_BASIS_TO_YAW_V1"

var _owner_state_accepts: int = 0
var _owner_state_rejections: int = 0


func setup(
	authority_owner_id: String,
	authority_epoch: int,
	server_tick: int = 0,
	config: Dictionary = {}
) -> Dictionary:
	_owner_state_accepts = 0
	_owner_state_rejections = 0
	return super.setup(authority_owner_id, authority_epoch, server_tick, config)


func submit_player_state(
	logical_player_id: String,
	transport_session_id: String,
	ownership_epoch: int,
	input_sequence: int,
	player_state: Dictionary,
	delta_seconds: float,
	_operation_id: String
) -> Dictionary:
	if not _configured or not _fixed_tick_authority:
		return _reject_owner_state("FIXED_TICK_AUTHORITY_NOT_ENABLED")
	if not _playable_sandbox:
		return _reject_owner_state("OWNER_MOVEMENT_REQUIRES_PLAYABLE_SANDBOX")

	var owner_check := _validate_owner(
		logical_player_id,
		transport_session_id,
		ownership_epoch
	)
	if not bool(owner_check.get("success", false)):
		_owner_state_rejections += 1
		return owner_check
	if input_sequence < 1 or int(player_state.get("last_input_sequence", 0)) != input_sequence:
		return _reject_owner_state("OWNER_STATE_INPUT_SEQUENCE_MISMATCH")

	var record: Dictionary = _players.get_player(logical_player_id)
	if record.is_empty():
		return _reject_owner_state("PLAYER_STATE_NOT_FOUND")

	var validation := _movement.apply_authoritative_state(
		_record_to_playable_state(record),
		player_state,
		delta_seconds
	)
	if not bool(validation.get("success", false)):
		_owner_state_rejections += 1
		return validation

	var accepted_state := Dictionary(
		validation.get("details", {}).get("player_state", {})
	).duplicate(true)
	var next_record := _apply_playable_state_to_record(record, accepted_state)
	_players.upsert(next_record)
	_revision += 1
	_owner_state_accepts += 1
	return _success({
		"replay": false,
		"changed": true,
		"player": next_record.duplicate(true),
		"server_tick": _tick,
		"movement_authority_mode": MovementAuthorityProfile.OWNER_AUTHORITATIVE_VALIDATED,
		"movement_authority_policy": OWNER_MOVEMENT_AUTHORITY_POLICY,
	})


# Godot's forward vector is -Basis.z. Recovering yaw with atan2(forward.x,
# forward.z) maps identity to PI. This inverse keeps identity at zero and makes
# server-side item drop/place use the validated owner's real facing direction.
func _apply_playable_state_to_record(
	record: Dictionary,
	player_state: Dictionary
) -> Dictionary:
	var next := record.duplicate(true)
	var position := OwnerPlayableStateCodec.player_position(player_state)
	var velocity := OwnerPlayableStateCodec.player_velocity(player_state)
	var forward := -OwnerPlayableStateCodec.player_basis(player_state).z
	next["position"] = {"x": position.x, "y": position.y, "z": position.z}
	next["velocity"] = {"x": velocity.x, "y": velocity.y, "z": velocity.z}

	var horizontal_forward := forward.slide(Vector3.UP)
	if horizontal_forward.length_squared() > 0.000001:
		horizontal_forward = horizontal_forward.normalized()
		next["orientation_yaw"] = atan2(-horizontal_forward.x, -horizontal_forward.z)
	next["flashlight_enabled"] = bool(player_state.get("flashlight_enabled", false))
	next["last_input_sequence"] = int(player_state.get("last_input_sequence", 0))
	next["state_revision"] = int(next.get("state_revision", 0)) + 1
	return next


func get_report() -> Dictionary:
	var report := super.get_report()
	report["movement_authority_mode"] = MovementAuthorityProfile.OWNER_AUTHORITATIVE_VALIDATED
	report["movement_authority_policy"] = OWNER_MOVEMENT_AUTHORITY_POLICY
	report["owner_basis_yaw_roundtrip_policy"] = OWNER_BASIS_YAW_ROUNDTRIP_POLICY
	report["owner_state_accepts"] = _owner_state_accepts
	report["owner_state_rejections"] = _owner_state_rejections
	report["direct_client_authority_references"] = 1
	return report


func _reject_owner_state(error_code: String) -> Dictionary:
	_owner_state_rejections += 1
	return _failure(error_code)
