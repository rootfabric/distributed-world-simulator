extends "res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd"

# Experimental owner-authoritative locomotion service.
#
# Only the owned player's realtime transform is accepted from the client. The
# existing ownership/session epoch remains server-validated and every other
# gameplay subsystem (items, inventory, spawn/despawn, durable state) remains
# server-authoritative. Candidate locomotion is validated by the existing
# PlayerMovementService before it replaces transform fields in the canonical
# server record.

const PlayableStateCodec = preload("res://scripts/runtime/listen_host/playable_state_codec.gd")

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
		_owner_state_rejections += 1
		return _failure("FIXED_TICK_AUTHORITY_NOT_ENABLED")
	if not _playable_sandbox:
		_owner_state_rejections += 1
		return _failure("OWNER_MOVEMENT_REQUIRES_PLAYABLE_SANDBOX")
	var owner_check: Dictionary = _validate_owner(
		logical_player_id, transport_session_id, ownership_epoch
	)
	if not bool(owner_check.get("success", false)):
		_owner_state_rejections += 1
		return owner_check
	if input_sequence < 1 or int(player_state.get("last_input_sequence", 0)) != input_sequence:
		_owner_state_rejections += 1
		return _failure("OWNER_STATE_INPUT_SEQUENCE_MISMATCH")

	var record: Dictionary = _players.get_player(logical_player_id)
	if record.is_empty():
		_owner_state_rejections += 1
		return _failure("PLAYER_STATE_NOT_FOUND")
	var previous_state: Dictionary = _record_to_playable_state(record)
	var validation: Dictionary = _movement.apply_authoritative_state(
		previous_state,
		player_state,
		delta_seconds
	)
	if not bool(validation.get("success", false)):
		_owner_state_rejections += 1
		return validation

	var accepted_state: Dictionary = Dictionary(
		validation.get("details", {}).get("player_state", {})
	).duplicate(true)
	var next_record: Dictionary = _apply_playable_state_to_record(record, accepted_state)
	_players.upsert(next_record)
	_revision += 1
	_owner_state_accepts += 1
	return _success({
		"replay": false,
		"changed": true,
		"player": next_record.duplicate(true),
		"server_tick": _tick,
		"movement_authority_policy": OWNER_MOVEMENT_AUTHORITY_POLICY,
	})


# The base service historically reconstructed yaw with atan2(forward.x,
# forward.z). That maps Godot's identity forward (-Z) to PI and flips the
# validated owner's server-side facing by 180 degrees. Server-authoritative
# item drop/place then derives its transform from that inverted facing.
#
# Owner locomotion is the only path that currently imports an arbitrary client
# Basis into the canonical player record, so keep this correction isolated in
# the owner-authority leaf. For a Godot forward vector produced by
# -Basis(Vector3.UP, yaw).z, the inverse is atan2(-forward.x, -forward.z).
func _apply_playable_state_to_record(record: Dictionary, player_state: Dictionary) -> Dictionary:
	var next := record.duplicate(true)
	var position := PlayableStateCodec.player_position(player_state)
	var velocity := PlayableStateCodec.player_velocity(player_state)
	var forward := -PlayableStateCodec.player_basis(player_state).z
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
	var report: Dictionary = super.get_report()
	report["movement_authority_mode"] = "OWNER_AUTHORITATIVE_VALIDATED"
	report["movement_authority_policy"] = OWNER_MOVEMENT_AUTHORITY_POLICY
	report["owner_basis_yaw_roundtrip_policy"] = OWNER_BASIS_YAW_ROUNDTRIP_POLICY
	report["owner_state_accepts"] = _owner_state_accepts
	report["owner_state_rejections"] = _owner_state_rejections
	report["direct_client_authority_references"] = 1
	return report
