extends RefCounted

const CheckpointScript = preload("res://scripts/persistence/authoritative_checkpoint.gd")

const DEFAULT_PERSIST_RETRY_ATTEMPTS := 20
const DEFAULT_PERSIST_RETRY_DELAY_MS := 10
const RETRYABLE_SAVE_ERRORS: Array[String] = [
	"AUTHORITATIVE_ATOMIC_REPLACE_FAILED",
	"AUTHORITATIVE_PENDING_OPEN_FAILED",
	"AUTHORITATIVE_PENDING_WRITE_FAILED",
	"AUTHORITATIVE_PENDING_VERIFY_FAILED",
	"AUTHORITATIVE_COMMIT_VERIFY_FAILED",
]

var repository
var authority
var replay_service
var _persist_retry_attempts := DEFAULT_PERSIST_RETRY_ATTEMPTS
var _persist_retry_delay_ms := DEFAULT_PERSIST_RETRY_DELAY_MS


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
	var attempts: int = maxi(_persist_retry_attempts, 1)
	var last_saved: Dictionary = {}
	for attempt in range(attempts):
		var saved: Dictionary = repository.save_atomic(checkpoint)
		if bool(saved.get("success", false)):
			return _success({
				"checkpoint": checkpoint,
				"repository": saved["details"],
				"save_attempts": attempt + 1,
				"committed_after_reported_error": false,
			})
		last_saved = saved.duplicate(true)
		var observed: Dictionary = _observe_committed_checkpoint(checkpoint)
		if bool(observed.get("success", false)):
			_cleanup_pending_files()
			return _success({
				"checkpoint": checkpoint,
				"repository": observed.get("details", {}).get("repository", {}),
				"save_attempts": attempt + 1,
				"committed_after_reported_error": true,
				"reported_save_error": saved.duplicate(true),
			})
		if not _is_retryable_save_failure(saved):
			return saved
		_cleanup_pending_files()
		if attempt + 1 < attempts and _persist_retry_delay_ms > 0:
			OS.delay_msec(_persist_retry_delay_ms)
	if last_saved.is_empty():
		return _failure("AUTHORITATIVE_CHECKPOINT_PERSIST_FAILED")
	var exhausted: Dictionary = last_saved.duplicate(true)
	var exhausted_details: Dictionary = Dictionary(exhausted.get("details", {})).duplicate(true)
	exhausted_details["retry_attempts"] = attempts
	exhausted_details["retry_exhausted"] = true
	exhausted["details"] = exhausted_details
	return exhausted


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


func _observe_committed_checkpoint(candidate: Dictionary) -> Dictionary:
	var loaded: Dictionary = repository.load_committed()
	if not bool(loaded.get("success", false)):
		return _failure("AUTHORITATIVE_COMMIT_NOT_OBSERVED", {"cause": loaded})
	var observed_value = loaded.get("details", {}).get("checkpoint", {})
	if not observed_value is Dictionary:
		return _failure("AUTHORITATIVE_COMMIT_NOT_OBSERVED")
	var observed: Dictionary = observed_value
	if String(observed.get("checksum", "")) != String(candidate.get("checksum", "")):
		return _failure("AUTHORITATIVE_COMMIT_CHECKSUM_NOT_OBSERVED", {
			"expected_checksum": String(candidate.get("checksum", "")),
			"observed_checksum": String(observed.get("checksum", "")),
		})
	return _success({
		"checkpoint": observed.duplicate(true),
		"repository": Dictionary(loaded.get("details", {})).duplicate(true),
	})


func _is_retryable_save_failure(saved: Dictionary) -> bool:
	return String(saved.get("error_code", "")) in RETRYABLE_SAVE_ERRORS


func _cleanup_pending_files() -> void:
	if repository != null and repository.has_method("cleanup_pending_files"):
		repository.cleanup_pending_files()


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
