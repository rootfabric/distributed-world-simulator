extends "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_p4_closure.gd"

var captured_fast_committed: Array[Dictionary] = []
var fake_activation_count := 0
var force_target_player_truth := false
var pretend_target_commit_durable := true


func configure_proof_fixture(recovery_root: String, directory: Dictionary) -> Dictionary:
	_p4_enabled = true
	_authority_id = Contracts.AUTHORITY_B
	_zone_id = Contracts.ZONE_B
	_peer_authority_id = Contracts.AUTHORITY_A
	_peer_zone_id = Contracts.ZONE_A
	_directory = directory.duplicate(true)
	_peer_synced = true
	_recovery_root = recovery_root
	_recovery_authority_dir = recovery_root.path_join("authority-b")
	var make_error := DirAccess.make_dir_recursive_absolute(_recovery_authority_dir)
	if make_error != OK:
		return _failure("SM0_P4_TEST_RECOVERY_DIRECTORY_CREATE_FAILED", {
			"error": make_error,
			"path": _recovery_authority_dir,
		})
	return _success()


func install_durable_proof(prewarm: Dictionary, accepted_at_unix_usec: int) -> void:
	_p4_durable_prewarm_proofs[String(prewarm.get("prewarm_id", ""))] = {
		"prewarm": prewarm.duplicate(true),
		"accepted_at_unix_usec": accepted_at_unix_usec,
	}


func persist_proofs(phase: String, subject_id: String) -> Dictionary:
	return _p4_persist_proofs(phase, subject_id)


func restore_latest_proofs() -> Dictionary:
	return _p4_restore_latest_proofs()


func proof_count() -> int:
	return _p4_durable_prewarm_proofs.size()


func has_live_reservation(prewarm_id: String) -> bool:
	return _prewarmed_transfers.has(prewarm_id)


func has_committed_transfer(transfer_id: String) -> bool:
	return _committed_transfers.has(transfer_id)


func invoke_fast_commit(payload: Dictionary) -> void:
	captured_fast_committed.clear()
	_handle_p4_fast_commit("fast-commit/durable-proof-test", payload.duplicate(true))


func last_fast_commit_success() -> bool:
	if captured_fast_committed.is_empty():
		return false
	return bool(captured_fast_committed[-1].get("success", false))


func last_fast_commit_error() -> String:
	if captured_fast_committed.is_empty():
		return ""
	return String(captured_fast_committed[-1].get("error_code", ""))


func _p4_target_has_player_truth() -> bool:
	return force_target_player_truth


func _activate_imported_player(package: Dictionary) -> Dictionary:
	fake_activation_count += 1
	return _success({
		"session_id": "transport-session/sm0/a/test-proof-recovery",
		"player": {
			"logical_player_id": String(package.get("logical_player_id", "")),
			"player_entity_id": String(package.get("player_entity_id", "")),
			"ownership_epoch": int(package.get("target_authority_epoch", 0)),
			"position": Dictionary(package.get("position", {})).duplicate(true),
			"velocity": Dictionary(package.get("velocity", {})).duplicate(true),
			"orientation_yaw": float(package.get("orientation_yaw", 0.0)),
			"last_input_sequence": int(package.get("last_input_sequence", 0)),
			"state_revision": int(package.get("state_revision", 0)),
			"connected": true,
		},
	})


func _send_p4_fast_committed(_request_id: String, transfer_id: String, success: bool, error_code: String) -> void:
	if success and pretend_target_commit_durable:
		_recovery_persisted_commits[transfer_id] = 1
	captured_fast_committed.append({
		"transfer_id": transfer_id,
		"success": success,
		"error_code": error_code,
	})
