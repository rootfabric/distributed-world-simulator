extends SceneTree

const Coordinator = preload("res://scripts/persistence/authoritative_recovery_coordinator.gd")
const CHECKSUM := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

var assertions := 0
var failures: Array[String] = []


class FakeAuthority extends RefCounted:
	func export_recovery_state() -> Dictionary:
		return {"ready": true}

	func restore_recovery_state(_state: Dictionary) -> Dictionary:
		return {"success": true, "error_code": "", "details": {}}


class FakeReplay extends RefCounted:
	func to_dict() -> Dictionary:
		return {}

	func load_dict(_state: Dictionary, _tick: int) -> Dictionary:
		return {"success": true, "error_code": "", "details": {}}


class FakeRepository extends RefCounted:
	var failures_before_success := 0
	var failure_code := "AUTHORITATIVE_ATOMIC_REPLACE_FAILED"
	var commit_on_reported_failure := false
	var save_attempts := 0
	var cleanup_calls := 0
	var committed: Dictionary = {}

	func save_atomic(checkpoint: Dictionary) -> Dictionary:
		save_attempts += 1
		if commit_on_reported_failure and save_attempts == 1:
			committed = checkpoint.duplicate(true)
			return {
				"success": false,
				"error_code": failure_code,
				"details": {"injected": true},
			}
		if save_attempts <= failures_before_success:
			return {
				"success": false,
				"error_code": failure_code,
				"details": {"injected": true},
			}
		committed = checkpoint.duplicate(true)
		return {
			"success": true,
			"error_code": "",
			"details": {"generation": 2},
		}

	func load_committed() -> Dictionary:
		if committed.is_empty():
			return {
				"success": false,
				"error_code": "AUTHORITATIVE_CHECKPOINT_NOT_FOUND",
				"details": {},
			}
		return {
			"success": true,
			"error_code": "",
			"details": {
				"checkpoint": committed.duplicate(true),
				"source": "ACTIVE",
			},
		}

	func cleanup_pending_files() -> Dictionary:
		cleanup_calls += 1
		return {
			"success": true,
			"error_code": "",
			"details": {"removed": 1},
		}


class FakeCoordinator extends Coordinator:
	func create_checkpoint(
		_checkpoint_id: String,
		generation: int,
		previous_generation: int,
		committed_operation_id: String = ""
	) -> Dictionary:
		return {
			"success": true,
			"error_code": "",
			"details": {
				"checkpoint": {
					"checksum": CHECKSUM,
					"generation": generation,
					"previous_generation": previous_generation,
					"committed_operation_id": committed_operation_id,
				},
			},
		}


func _init() -> void:
	_test_transient_failures_retry()
	_test_reported_failure_after_commit()
	_test_nonretryable_failure_is_not_retried()
	_test_retry_exhaustion_is_diagnostic()
	if failures.is_empty():
		print("M6 final checkpoint retry: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print(
		"M6 final checkpoint retry: FAIL (%d assertions, %d failures)"
		% [assertions, failures.size()]
	)
	quit(1)


func _configured(repository: FakeRepository, attempts: int = 5) -> FakeCoordinator:
	var coordinator := FakeCoordinator.new()
	_assert(
		bool(
			coordinator.configure(
				repository,
				FakeAuthority.new(),
				FakeReplay.new()
			).get("success", false)
		),
		"Coordinator configured"
	)
	coordinator.set("_persist_retry_attempts", attempts)
	coordinator.set("_persist_retry_delay_ms", 0)
	return coordinator


func _test_transient_failures_retry() -> void:
	var repository := FakeRepository.new()
	repository.failures_before_success = 3
	var result: Dictionary = _configured(repository).persist_checkpoint(
		"checkpoint/test/transient", 2, 1, ""
	)
	_assert(bool(result.get("success", false)), "Transient persistence failures recovered")
	_assert(repository.save_attempts == 4, "Transient failures used four save attempts")
	_assert(repository.cleanup_calls == 3, "Transient failures cleaned orphan pending files")
	_assert(
		int(result.get("details", {}).get("save_attempts", 0)) == 4,
		"Retry attempt diagnostics preserved"
	)
	_assert(
		not bool(result.get("details", {}).get("committed_after_reported_error", true)),
		"Normal retry success was not misclassified"
	)


func _test_reported_failure_after_commit() -> void:
	var repository := FakeRepository.new()
	repository.commit_on_reported_failure = true
	var result: Dictionary = _configured(repository).persist_checkpoint(
		"checkpoint/test/observed", 2, 1, ""
	)
	_assert(
		bool(result.get("success", false)),
		"Committed checkpoint accepted after reported I/O failure"
	)
	_assert(repository.save_attempts == 1, "Observed commit did not write twice")
	_assert(repository.cleanup_calls == 1, "Observed commit cleaned pending residue")
	_assert(
		bool(result.get("details", {}).get("committed_after_reported_error", false)),
		"Observed commit classification preserved"
	)
	_assert(
		String(
			result.get("details", {}).get("reported_save_error", {}).get("error_code", "")
		) == "AUTHORITATIVE_ATOMIC_REPLACE_FAILED",
		"Reported save error preserved"
	)


func _test_nonretryable_failure_is_not_retried() -> void:
	var repository := FakeRepository.new()
	repository.failures_before_success = 99
	repository.failure_code = "AUTHORITATIVE_GENERATION_ROLLBACK"
	var result: Dictionary = _configured(repository).persist_checkpoint(
		"checkpoint/test/nonretryable", 2, 1, ""
	)
	_assert(
		not bool(result.get("success", false)),
		"Nonretryable progression rejection remained failure"
	)
	_assert(repository.save_attempts == 1, "Nonretryable rejection was not retried")
	_assert(
		repository.cleanup_calls == 0,
		"Nonretryable rejection did not mutate repository cleanup"
	)


func _test_retry_exhaustion_is_diagnostic() -> void:
	var repository := FakeRepository.new()
	repository.failures_before_success = 99
	var result: Dictionary = _configured(repository, 3).persist_checkpoint(
		"checkpoint/test/exhausted", 2, 1, ""
	)
	_assert(not bool(result.get("success", false)), "Permanent I/O failure remained failure")
	_assert(repository.save_attempts == 3, "Retry budget was bounded")
	_assert(repository.cleanup_calls == 3, "Every failed retry cleaned pending residue")
	_assert(
		bool(result.get("details", {}).get("retry_exhausted", false)),
		"Retry exhaustion is explicit"
	)
	_assert(
		int(result.get("details", {}).get("retry_attempts", 0)) == 3,
		"Retry exhaustion count preserved"
	)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
