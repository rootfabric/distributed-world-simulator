extends "res://scripts/simulation/matter/persistence/matter_state_coordinator.gd"

# Read-only native MW5 preflight before admitting any gameplay or replica. The
# caller owns the quiescent cut; this class adds no store, receiver or journal.
func preflight_exact7(expected_checksum: String) -> Dictionary:
	if not _configured or not MatterUtilsScript.is_lower_hex_64(expected_checksum):
		return MatterUtilsScript.failure("MVP7_MATTER_CUT_BINDING_REQUIRED")
	var loaded: Dictionary = _repository.load_committed()
	if not bool(loaded.get("success", false)): return loaded
	var checkpoint: Dictionary = loaded.get("details", {}).get("checkpoint", {})
	var valid: Dictionary = CheckpointScript.validate(checkpoint)
	if not bool(valid.get("success", false)): return valid
	if String(checkpoint.get("checksum", "")) != expected_checksum:
		return MatterUtilsScript.failure("MVP7_MATTER_CUT_CHECKSUM_MISMATCH")
	var identity_error := _validate_checkpoint_identity(checkpoint)
	if not identity_error.is_empty(): return MatterUtilsScript.failure(identity_error)
	for pair in [[_store, "store_state"], [_receiver, "receiver_state"], [_journal, "journal_state"]]:
		var checked: Dictionary = pair[0].validate_restore_state(checkpoint[pair[1]])
		if not bool(checked.get("success", false)): return checked
	return MatterUtilsScript.success({"checkpoint": checkpoint, "source": loaded.get("details", {}).get("source", "")})

func restore_exact7(expected_checksum: String) -> Dictionary:
	var checked := preflight_exact7(expected_checksum)
	if not bool(checked.get("success", false)): return checked
	var restored: Dictionary = super.restore_latest()
	if not bool(restored.get("success", false)): return restored
	if String(restored.get("details", {}).get("checkpoint", {}).get("checksum", "")) != expected_checksum:
		return MatterUtilsScript.failure("MVP7_MATTER_CUT_CHANGED_DURING_RESTORE")
	return restored
