extends "res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd"

const MovementAuthorityProfile = preload(
	"res://scripts/network/authority/movement_authority_profile.gd"
)
const OwnerMovementService = preload(
	"res://scripts/runtime/networked_gameplay/networked_gameplay_service_owner_movement.gd"
)

# Opt-in dedicated runtime for owner-authored locomotion. The default dedicated
# runtime stays server-predicted. This leaf accepts PLAYER_STATE only from the
# currently bound transport session, validates it in the owner service, and then
# uses the existing canonical snapshot path to relay accepted state to peers.
const OWNER_MOVEMENT_RUNTIME_POLICY: String = \
	"OWNER_LOCAL_TRANSFORM_SERVER_VALIDATE_CANONICAL_RELAY_V1"

var _owner_state_messages_received: int = 0
var _owner_state_messages_accepted: int = 0
var _owner_state_messages_rejected: int = 0


func setup(config: Dictionary) -> Dictionary:
	_owner_state_messages_received = 0
	_owner_state_messages_accepted = 0
	_owner_state_messages_rejected = 0
	if not bool(config.get("playable_sandbox", false)):
		return _failure("OWNER_MOVEMENT_REQUIRES_PLAYABLE_SANDBOX")

	# super.setup() starts the socket and normally emits ready_for_clients. Block
	# local signals until the owner-validation service (and persistence adapters,
	# if enabled) are fully rebound so in-process launchers cannot race the swap.
	var published_result_file := String(config.get("result_file", "")).strip_edges()
	var base_config := config.duplicate(true)
	base_config["result_file"] = ""
	set_block_signals(true)
	var result := super.setup(base_config)
	set_block_signals(false)
	if not bool(result.get("success", false)):
		return result

	var replacement = OwnerMovementService.new()
	var replacement_setup := replacement.setup(
		_authority_owner_id,
		_authority_epoch,
		_server_tick,
		{
			"profile": "MULTIPLAYER_CORE",
			"topology_adapter": "ENET",
			"region_id": "region/m3/single-server",
			"playable_sandbox": true,
			"fixed_tick_authority": true,
		}
	)
	if not bool(replacement_setup.get("success", false)):
		_cleanup_setup_failure()
		return replacement_setup
	if _service != null:
		_service.shutdown()
	_service = replacement

	# Base persistence/recovery objects bind to the service instance that existed
	# during super.setup(). Rebuild them against the replacement so owner movement
	# does not silently disconnect canonical durability/replay semantics.
	if _persistence_enabled:
		var recovery_rebind := _setup_recovery()
		if not bool(recovery_rebind.get("success", false)):
			_cleanup_setup_failure()
			return recovery_rebind

	_peer_input_buffers.clear()
	_result_file = published_result_file
	_write_report("READY", false)
	ready_for_clients.emit(get_report())
	return result


func _handle_player_state_rejected(
	peer_id: String,
	session_id: String,
	payload: Dictionary
) -> void:
	_owner_state_messages_received += 1
	var operation_id := String(payload.get("operation_id", "")).strip_edges()
	if not _peer_to_player.has(peer_id) or String(_peer_to_session.get(peer_id, "")) != session_id:
		_owner_state_messages_rejected += 1
		_send_result(peer_id, operation_id, "PLAYER_STATE", _failure("STALE_TRANSPORT_SESSION"))
		return
	if not _is_canonical_operation_id(operation_id):
		_owner_state_messages_rejected += 1
		_reject_uncommitted_command(
			peer_id,
			operation_id,
			"PLAYER_STATE",
			"OPERATION_ID_REQUIRED" if operation_id.is_empty() else "INVALID_OPERATION_ID"
		)
		return

	var player_state_value = payload.get("player_state", {})
	if not player_state_value is Dictionary:
		_owner_state_messages_rejected += 1
		_send_result(peer_id, operation_id, "PLAYER_STATE", _failure("PLAYER_STATE_REQUIRED"))
		return

	var logical_id := String(_peer_to_player.get(peer_id, ""))
	var result := _service.submit_player_state(
		logical_id,
		session_id,
		int(payload.get("ownership_epoch", 0)),
		int(payload.get("input_sequence", 0)),
		Dictionary(player_state_value),
		float(payload.get("delta_seconds", 0.0)),
		operation_id
	)
	if not bool(result.get("success", false)):
		_owner_state_messages_rejected += 1
		_movement_inputs_rejected += 1
		_last_movement_rejection_error_code = String(
			result.get("error_code", "OWNER_PLAYER_STATE_REJECTED")
		)
		_last_movement_rejection_stage = "OWNER_STATE_VALIDATE"
		_send_result(peer_id, operation_id, "PLAYER_STATE", result)
		return

	_owner_state_messages_accepted += 1
	_moves += 1
	_movement_inputs_received += 1
	_movement_inputs_applied += 1
	_movement_results_suppressed += 1
	_movement_deltas_suppressed += 1
	_movement_full_snapshots_suppressed += 1
	_movement_commands_since_checkpoint += 1
	_movement_checkpoint_dirty = true
	_movement_snapshot_dirty = true


func get_report() -> Dictionary:
	var report := super.get_report()
	report["movement_authority_mode"] = MovementAuthorityProfile.OWNER_AUTHORITATIVE_VALIDATED
	report["movement_authority_policy"] = OWNER_MOVEMENT_RUNTIME_POLICY
	report["owner_state_messages_received"] = _owner_state_messages_received
	report["owner_state_messages_accepted"] = _owner_state_messages_accepted
	report["owner_state_messages_rejected"] = _owner_state_messages_rejected
	return report
