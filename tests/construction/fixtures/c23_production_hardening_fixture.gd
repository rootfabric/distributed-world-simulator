extends RefCounted

const H = preload("res://scripts/construction/hardening/construction_hardening_utils.gd")
const Operation = preload("res://scripts/construction/hardening/construction_production_operation.gd")
const ReleasePolicy = preload("res://scripts/construction/hardening/construction_release_policy.gd")
const Service = preload("res://scripts/construction/hardening/construction_production_hardening_service.gd")

const RELEASE_ID := "release/c23-1"
const SUBJECT_ID := "subject/c23-builder"
const CONSTRUCT_ID := "construct/c23-station"
const PERMISSION_EPOCH := 7

class FakeAuthorizer:
	extends RefCounted
	var allowed := true
	var required_epoch := PERMISSION_EPOCH
	var denial_error_code := "CONSTRUCTION_PRODUCTION_PERMISSION_DENIED"
	var denial_details: Dictionary = {}
	var return_non_dictionary := false
	var calls := 0

	func authorize(subject_id: String, construct_id: String, action: String, permission_epoch: int):
		calls += 1
		if return_non_dictionary:
			return null
		if not allowed:
			var denied := H.failure(denial_error_code)
			for key in denial_details:
				denied[key] = denial_details[key]
			return denied
		if subject_id != SUBJECT_ID or construct_id != CONSTRUCT_ID or action != "build":
			return H.failure("CONSTRUCTION_PRODUCTION_PERMISSION_DENIED")
		if permission_epoch != required_epoch:
			return H.failure("CONSTRUCTION_PRODUCTION_PERMISSION_EPOCH_MISMATCH")
		return H.success()

class FakeExecutor:
	extends RefCounted
	var terminal: Dictionary = {}
	var authoritative_writes := 0
	var total_calls := 0
	var value := 0
	var return_runtime_result := false
	var return_non_dictionary := false

	func execute_production_operation(operation: Dictionary):
		total_calls += 1
		if return_non_dictionary:
			return null
		var operation_id := String(operation["operation_id"])
		var checksum := String(operation["checksum"])
		if terminal.has(operation_id):
			var row: Dictionary = terminal[operation_id]
			if String(row["checksum"]) != checksum:
				return H.failure("EXECUTOR_OPERATION_ID_CONFLICT")
			var replay: Dictionary = row["result"].duplicate(true)
			replay["executor_replay"] = true
			return replay
		var delta := int(operation["payload"].get("delta", 1))
		value += delta
		authoritative_writes += 1
		if return_runtime_result:
			return H.success({"value": value, "runtime": Node.new()})
		var result := H.success({"value": value, "executor_replay": false})
		terminal[operation_id] = {"checksum": checksum, "result": result.duplicate(true)}
		return result

static func release_descriptor(release_id: String = RELEASE_ID, read_only: bool = false) -> Dictionary:
	return ReleasePolicy.create(
		release_id,
		1,
		2,
		1,
		1,
		["audit", "checksum-recovery", "exact-replay", "rate-limit", "rolling-upgrade"],
		read_only
	)

static func operation(index: int, tick: int = -1, delta: int = 1) -> Dictionary:
	return Operation.create(
		"operation/c23-%06d" % index,
		SUBJECT_ID,
		CONSTRUCT_ID,
		"build",
		PERMISSION_EPOCH,
		RELEASE_ID,
		index if tick < 0 else tick,
		{"delta": delta, "part_id": "part/c23-%06d" % index}
	)

static func service(rate_limit: int = 100000, window_ticks: int = 60) -> Dictionary:
	var executor := FakeExecutor.new()
	var authorizer := FakeAuthorizer.new()
	var hardening := Service.new()
	var setup_result := hardening.setup(executor, authorizer, release_descriptor(), rate_limit, window_ticks)
	return {
		"service": hardening,
		"executor": executor,
		"authorizer": authorizer,
		"setup": setup_result,
	}
