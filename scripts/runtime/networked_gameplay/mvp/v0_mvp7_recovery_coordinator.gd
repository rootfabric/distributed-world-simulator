extends "res://scripts/persistence/authoritative_recovery_coordinator.gd"

# M6 storage and native owner adapters remain unchanged. Preflight BOTH durable
# state and replay before the first mutation; restore exactly the object that
# was preflighted, not a second filesystem read. Admission opens only on success.
var _minimum_generation7 := 0
var _recovered7 := false

func require_minimum_generation7(generation: int) -> Dictionary:
	if generation < 0 or _recovered7: return _failure("MVP7_INVALID_RECOVERY_GENERATION_FLOOR")
	_minimum_generation7 = maxi(_minimum_generation7, generation)
	return _success()

func preflight_checkpoint7(checkpoint: Dictionary) -> Dictionary:
	if repository == null or authority == null or replay_service == null:
		return _failure("AUTHORITATIVE_RECOVERY_NOT_CONFIGURED")
	var valid: Dictionary = CheckpointScript.validate(checkpoint)
	if not bool(valid.get("success", false)): return valid
	if int(checkpoint.get("generation", -1)) < _minimum_generation7:
		return _failure("MVP7_RECOVERY_GENERATION_ROLLBACK")
	if not authority.has_method("validate_recovery_state") or not replay_service.has_method("validate"):
		return _failure("MVP7_NATIVE_PREFLIGHT_PORTS_REQUIRED")
	var current: Dictionary = authority.export_recovery_state()
	if current.is_empty(): return _failure("MVP7_FRESH_OR_SEALED_OWNER_REQUIRED")
	var incoming: Dictionary = checkpoint.get("authority_state", {})
	for field in ["authority_owner_id", "authority_epoch", "session_id"]:
		if incoming.get(field) != current.get(field): return _failure("MVP7_RECOVERY_IDENTITY_MISMATCH", {"field": field})
	var state_check: Dictionary = authority.validate_recovery_state(incoming)
	if not bool(state_check.get("success", false)): return state_check
	var replay_check: Dictionary = replay_service.validate(checkpoint.get("replay_state", {}))
	if not bool(replay_check.get("success", false)): return replay_check
	return _success({"generation": int(checkpoint["generation"]), "checkpoint_checksum": String(checkpoint["checksum"])})

func recover_latest() -> Dictionary:
	if _recovered7: return _failure("MVP7_RECOVERY_ALREADY_APPLIED")
	if repository == null: return _failure("AUTHORITATIVE_RECOVERY_NOT_CONFIGURED")
	var loaded: Dictionary = repository.load_committed()
	if not bool(loaded.get("success", false)): return loaded
	var checkpoint: Dictionary = loaded.get("details", {}).get("checkpoint", {})
	var checked := preflight_checkpoint7(checkpoint)
	if not bool(checked.get("success", false)): return checked
	var restored: Dictionary = authority.restore_recovery_state(checkpoint["authority_state"])
	if not bool(restored.get("success", false)):
		return _failure("AUTHORITATIVE_DOMAIN_RECOVERY_FAILED", {"cause": restored})
	var replayed: Dictionary = replay_service.load_dict(checkpoint["replay_state"], int(checkpoint["server_tick"]))
	if not bool(replayed.get("success", false)):
		return _failure("AUTHORITATIVE_REPLAY_RECOVERY_FAILED", {"cause": replayed})
	var observed: Dictionary = authority.export_recovery_state()
	if observed.get("current_snapshot", {}).get("checksum") != checkpoint["authority_state"]["current_snapshot"]["checksum"]:
		return _failure("AUTHORITATIVE_RECOVERY_CHECKSUM_MISMATCH")
	if replay_service.to_dict().get("checksum") != checkpoint["replay_state"].get("checksum"):
		return _failure("MVP7_RECOVERED_REPLAY_CHECKSUM_MISMATCH")
	_recovered7 = true
	return _success({"checkpoint": checkpoint, "source": loaded.get("details", {}).get("source", ""), "pending_files": loaded.get("details", {}).get("pending_files", []), "authority": restored.get("details", {}), "replay": replayed.get("details", {}), "preflight_before_mutation": true, "admission_ready": true})
