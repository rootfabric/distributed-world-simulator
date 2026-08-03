extends RefCounted

const CheckpointScript = preload("res://scripts/persistence/authoritative_checkpoint.gd")

var repository
var authority
var replay_service


func configure(repository_reference, authority_reference, replay_service_reference) -> Dictionary:
	if repository_reference == null or not repository_reference.has_method("save_atomic") or not repository_reference.has_method("load_committed"):
		return _failure("AUTHORITATIVE_REPOSITORY_REQUIRED")
	if authority_reference == null or not authority_reference.has_method("export_recovery_state") or not authority_reference.has_method("restore_recovery_state"):
		return _failure("AUTHORITATIVE_DOMAIN_REQUIRED")
	if replay_service_reference == null or not replay_service_reference.has_method("to_dict") or not replay_service_reference.has_method("load_dict"):
		return _failure("AUTHORITATIVE_REPLAY_SERVICE_REQUIRED")
	repository = repository_reference
	authority = authority_reference
	replay_service = replay_service_reference
	return _success()


func create_checkpoint(
	checkpoint_id: String,
	generation: int,
	previous_generation: int,
	committed_operation_id: String = ""
) -> Dictionary:
	if repository == null or authority == null or replay_service == null:
		return _failure("AUTHORITATIVE_RECOVERY_NOT_CONFIGURED")
	var authority_state: Dictionary = authority.export_recovery_state()
	if authority_state.is_empty():
		return _failure("AUTHORITATIVE_STATE_NOT_READY")
	var replay_state: Dictionary = replay_service.to_dict()
	var checkpoint: Dictionary = CheckpointScript.create(
		checkpoint_id,
		generation,
		previous_generation,
		authority_state,
		replay_state,
		committed_operation_id,
		int(authority_state["server_tick"])
	)
	var validation: Dictionary = CheckpointScript.validate(checkpoint)
	if not bool(validation.get("success", false)):
		return _failure(String(validation.get("error_code", "INVALID_AUTHORITATIVE_CHECKPOINT")), {"message": String(validation.get("message", ""))})
	return _success({"checkpoint": checkpoint})


func persist_checkpoint(
	checkpoint_id: String,
	generation: int,
	previous_generation: int,
	committed_operation_id: String = ""
) -> Dictionary:
	var created: Dictionary = create_checkpoint(checkpoint_id, generation, previous_generation, committed_operation_id)
	if not bool(created.get("success", false)):
		return created
	var checkpoint: Dictionary = created["details"]["checkpoint"]
	var saved: Dictionary = repository.save_atomic(checkpoint)
	if not bool(saved.get("success", false)):
		return saved
	return _success({"checkpoint": checkpoint, "repository": saved["details"]})


func recover_latest() -> Dictionary:
	if repository == null or authority == null or replay_service == null:
		return _failure("AUTHORITATIVE_RECOVERY_NOT_CONFIGURED")
	var loaded: Dictionary = repository.load_committed()
	if not bool(loaded.get("success", false)):
		return loaded
	var checkpoint: Dictionary = loaded["details"]["checkpoint"]
	var authority_result: Dictionary = authority.restore_recovery_state(checkpoint["authority_state"])
	if not bool(authority_result.get("success", false)):
		return _failure("AUTHORITATIVE_DOMAIN_RECOVERY_FAILED", {"cause": authority_result})
	var replay_result: Dictionary = replay_service.load_dict(checkpoint["replay_state"], int(checkpoint["server_tick"]))
	if not bool(replay_result.get("success", false)):
		return _failure("AUTHORITATIVE_REPLAY_RECOVERY_FAILED", {"cause": replay_result})
	var restored_state: Dictionary = authority.export_recovery_state()
	if String(restored_state.get("current_snapshot", {}).get("checksum", "")) != String(checkpoint["authority_state"]["current_snapshot"]["checksum"]):
		return _failure("AUTHORITATIVE_RECOVERY_CHECKSUM_MISMATCH")
	return _success({
		"checkpoint": checkpoint,
		"source": String(loaded["details"].get("source", "")),
		"pending_files": loaded["details"].get("pending_files", []),
		"authority": authority_result["details"],
		"replay": replay_result["details"],
	})


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
