extends "res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd"

const HandoffPlayerSnapshot = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd")

# Server-internal authority operation. It is not a client command and does not
# create another player store: the imported state is validated and written to
# the inherited canonical PlayerRegistry owned by NetworkedGameplayService.
func import_handoff_player_state(
	logical_player_id: String,
	transport_session_id: String,
	ownership_epoch: int,
	handoff_state: Dictionary,
	operation_id: String
) -> Dictionary:
	if not _configured:
		return _failure("NETWORKED_GAMEPLAY_SERVICE_NOT_READY")
	var owner_check: Dictionary = _validate_owner(
		logical_player_id,
		transport_session_id,
		ownership_epoch
	)
	if not bool(owner_check.get("success", false)):
		return owner_check
	if operation_id.strip_edges().is_empty():
		return _failure("OPERATION_ID_REQUIRED")

	var record: Dictionary = _players.get_player(logical_player_id)
	if record.is_empty():
		return _failure("PLAYER_STATE_NOT_FOUND")
	if String(handoff_state.get("player_entity_id", "")) != String(record.get("player_entity_id", "")):
		return _failure("HANDOFF_PLAYER_ENTITY_MISMATCH")
	if not handoff_state.get("position") is Dictionary or not handoff_state.get("velocity") is Dictionary:
		return _failure("HANDOFF_SPATIAL_STATE_REQUIRED")

	var source_input_sequence := int(handoff_state.get("last_input_sequence", -1))
	var current_input_sequence := int(record.get("last_input_sequence", 0))
	if source_input_sequence < current_input_sequence:
		return _failure("STALE_HANDOFF_INPUT_SEQUENCE", {
			"source_input_sequence": source_input_sequence,
			"current_input_sequence": current_input_sequence,
		})
	var source_state_revision := int(handoff_state.get("source_state_revision", 0))
	if source_state_revision < 1:
		return _failure("INVALID_HANDOFF_SOURCE_STATE_REVISION")

	var fingerprint := Utils.payload_hash({
		"logical_player_id": logical_player_id,
		"transport_session_id": transport_session_id,
		"ownership_epoch": ownership_epoch,
		"handoff_state": handoff_state.duplicate(true),
	})
	if fingerprint.is_empty():
		return _failure("HANDOFF_STATE_NOT_JSON_SAFE")
	var replay := _replay(operation_id, fingerprint)
	if not replay.is_empty():
		return replay

	var candidate := record.duplicate(true)
	candidate["position"] = Dictionary(handoff_state.get("position", {})).duplicate(true)
	candidate["velocity"] = Dictionary(handoff_state.get("velocity", {})).duplicate(true)
	candidate["orientation_yaw"] = float(handoff_state.get("orientation_yaw", 0.0))
	candidate["last_input_sequence"] = source_input_sequence
	candidate["state_revision"] = maxi(
		int(record.get("state_revision", 0)),
		source_state_revision
	) + 1

	var validation := HandoffPlayerSnapshot.validate_player_record(candidate)
	if not bool(validation.get("success", false)):
		return _record_failure(
			operation_id,
			fingerprint,
			"INVALID_HANDOFF_PLAYER_STATE",
			{"cause": validation}
		)

	var before_revision := _revision
	var upsert: Dictionary = _players.upsert(candidate)
	if not bool(upsert.get("success", false)):
		return _record_failure(
			operation_id,
			fingerprint,
			"HANDOFF_PLAYER_UPSERT_FAILED",
			{"cause": upsert}
		)
	_advance()
	var player: Dictionary = _players.get_player(logical_player_id)
	var result := _success({
		"replay": false,
		"player": player,
		"delta": _create_delta(before_revision, "PLAYER_HANDOFF_IMPORTED", player, {}),
		"snapshot": create_snapshot(),
	})
	_record(operation_id, fingerprint, result)
	return result
