extends RefCounted

const H = preload("res://scripts/construction/hardening/construction_hardening_utils.gd")
const Operation = preload("res://scripts/construction/hardening/construction_production_operation.gd")
const StateEnvelope = preload("res://scripts/construction/hardening/construction_state_envelope.gd")
const ReleasePolicy = preload("res://scripts/construction/hardening/construction_release_policy.gd")
const ReplayStore = preload("res://scripts/construction/hardening/construction_replay_store.gd")
const Observability = preload("res://scripts/construction/hardening/construction_observability.gd")
const RateLimiter = preload("res://scripts/construction/hardening/construction_rate_limiter.gd")
const RecoveryStore = preload("res://scripts/construction/hardening/construction_recovery_store.gd")
const ContractUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const STATE_SCHEMA := "planet_simulator.construction_production_hardening_service.v1"
const STATE_FIELDS: Array[String] = [
	"schema", "generation", "release", "replay", "observability", "rate_limiter", "checksum",
]
const FAILURE_AFTER_EXECUTION_BEFORE_TERMINAL := "AFTER_EXECUTION_BEFORE_TERMINAL"
const FAILURE_AFTER_TERMINAL_BEFORE_RESPONSE := "AFTER_TERMINAL_BEFORE_RESPONSE"

var _executor
var _authorizer
var _release: Dictionary = {}
var _replay := ReplayStore.new()
var _observability := Observability.new()
var _rate_limiter := RateLimiter.new()
var _recovery := RecoveryStore.new()
var _generation := 0

func setup(executor, authorizer, release: Dictionary, rate_limit: int = 100, rate_window_ticks: int = 60) -> Dictionary:
	if _executor != null or _authorizer != null or not _release.is_empty():
		return H.failure("CONSTRUCTION_PRODUCTION_SERVICE_ALREADY_INITIALIZED")
	if executor == null or not executor.has_method("execute_production_operation"):
		return H.failure("CONSTRUCTION_PRODUCTION_EXECUTOR_REQUIRED")
	if authorizer == null or not authorizer.has_method("authorize"):
		return H.failure("CONSTRUCTION_PRODUCTION_AUTHORIZER_REQUIRED")
	var checked := ReleasePolicy.validate(release)
	if not bool(checked.get("success", false)):
		return checked
	checked = _rate_limiter.setup(rate_limit, rate_window_ticks)
	if not bool(checked.get("success", false)):
		return checked
	_executor = executor
	_authorizer = authorizer
	_release = release.duplicate(true)
	return H.success()

func submit(operation: Dictionary, failure_point: String = "") -> Dictionary:
	if _executor == null or _authorizer == null or _release.is_empty():
		return H.failure("CONSTRUCTION_PRODUCTION_SERVICE_NOT_INITIALIZED")
	if not failure_point.is_empty() and not [FAILURE_AFTER_EXECUTION_BEFORE_TERMINAL, FAILURE_AFTER_TERMINAL_BEFORE_RESPONSE].has(failure_point):
		return H.failure("UNKNOWN_CONSTRUCTION_PRODUCTION_FAILURE_POINT")
	var checked := Operation.validate(operation)
	if not bool(checked.get("success", false)):
		_observability.increment("operations_denied")
		return checked
	var operation_id := String(operation["operation_id"])
	var operation_checksum := String(operation["checksum"])
	var replay := _replay.lookup(operation_id, operation_checksum)
	if not bool(replay.get("success", false)):
		_observability.increment("operations_denied")
		_observability.append_audit(operation, "DENY", String(replay["error_code"]), int(operation["tick"]))
		return replay
	if bool(replay.get("found", false)):
		_observability.increment("operations_replayed")
		_observability.append_audit(operation, "REPLAY", "", int(operation["tick"]))
		var replay_result: Dictionary = replay["result"]
		replay_result["replay"] = true
		return replay_result
	if String(operation["release_id"]) != String(_release["release_id"]):
		return _terminal_rejection(operation, "CONSTRUCTION_PRODUCTION_RELEASE_MISMATCH")
	if bool(_release["read_only"]):
		return _terminal_rejection(operation, "CONSTRUCTION_PRODUCTION_RELEASE_READ_ONLY")
	var limited := _rate_limiter.consume(String(operation["subject_id"]), String(operation["action"]), int(operation["tick"]))
	_observability.set_gauge("rate_limit_subjects", _rate_limiter.get_subject_count())
	if not bool(limited.get("success", false)):
		_observability.increment("operations_rate_limited")
		return _terminal_rejection(operation, String(limited["error_code"]), limited)
	var authorized_raw = _authorizer.authorize(
		String(operation["subject_id"]),
		String(operation["construct_id"]),
		String(operation["action"]),
		int(operation["permission_epoch"])
	)
	if typeof(authorized_raw) != TYPE_DICTIONARY:
		return _terminal_rejection(operation, "CONSTRUCTION_PRODUCTION_AUTHORIZER_RESULT_INVALID")
	var authorized: Dictionary = authorized_raw
	if not bool(authorized.get("success", false)):
		return _terminal_rejection(operation, _safe_error_code(authorized.get("error_code"), "CONSTRUCTION_PRODUCTION_PERMISSION_DENIED"), authorized)
	var executed_raw = _executor.execute_production_operation(operation)
	if typeof(executed_raw) != TYPE_DICTIONARY:
		_observability.increment("operations_failed")
		return _terminal_rejection(operation, "CONSTRUCTION_PRODUCTION_EXECUTOR_RESULT_INVALID", {}, "FAIL")
	var executed: Dictionary = executed_raw
	if not bool(executed.get("success", false)):
		_observability.increment("operations_failed")
		return _terminal_rejection(operation, _safe_error_code(executed.get("error_code"), "CONSTRUCTION_PRODUCTION_EXECUTION_FAILED"), executed, "FAIL")
	if not bool(ContractUtils.canonicalize(executed).get("success", false)):
		_observability.increment("operations_failed")
		return _terminal_rejection(operation, "CONSTRUCTION_PRODUCTION_EXECUTION_RESULT_NOT_SERIALIZABLE", {}, "FAIL")
	if failure_point == FAILURE_AFTER_EXECUTION_BEFORE_TERMINAL:
		return H.failure("INJECTED_CONSTRUCTION_PRODUCTION_FAILURE_AFTER_EXECUTION")
	var result := H.success({
		"accepted": true,
		"replay": false,
		"operation_id": operation_id,
		"operation_checksum": operation_checksum,
		"execution_result": executed.duplicate(true),
	})
	var recorded := _replay.record(operation_id, operation_checksum, result)
	if not bool(recorded.get("success", false)):
		_observability.increment("operations_failed")
		return recorded
	_generation += 1
	_observability.increment("operations_accepted")
	_observability.set_gauge("replay_entries", _replay.get_entry_count())
	_observability.append_audit(operation, "ACCEPT", "", int(operation["tick"]))
	if failure_point == FAILURE_AFTER_TERMINAL_BEFORE_RESPONSE:
		return H.failure("INJECTED_CONSTRUCTION_PRODUCTION_FAILURE_AFTER_TERMINAL")
	return result

func checkpoint(created_tick: int) -> Dictionary:
	if _release.is_empty():
		return H.failure("CONSTRUCTION_PRODUCTION_SERVICE_NOT_INITIALIZED")
	if not H.is_non_negative_integer(created_tick):
		return H.failure("INVALID_CONSTRUCTION_PRODUCTION_CHECKPOINT_TICK")
	var envelope := StateEnvelope.create(export_state(), String(_release["release_id"]), created_tick)
	var committed := _recovery.commit(envelope)
	if not bool(committed.get("success", false)):
		return committed
	return H.success({"envelope": envelope, "sequence": committed["sequence"]})

func recover() -> Dictionary:
	var recovered := _recovery.recover()
	if not bool(recovered.get("success", false)):
		return recovered
	var loaded := load_envelope(recovered["envelope"])
	if not bool(loaded.get("success", false)):
		return loaded
	if bool(recovered.get("fallback_used", false)):
		_observability.increment("checkpoints_recovered")
	return H.success({
		"fallback_used": bool(recovered["fallback_used"]),
		"sequence": int(recovered["sequence"]),
		"migration_trace": loaded["migration_trace"],
	})

func load_envelope(envelope: Dictionary) -> Dictionary:
	if _release.is_empty():
		return H.failure("CONSTRUCTION_PRODUCTION_SERVICE_NOT_INITIALIZED")
	var runtime_release := _release.duplicate(true)
	var migrated := StateEnvelope.migrate(envelope, String(runtime_release["release_id"]), int(envelope.get("created_tick", 0)))
	if not bool(migrated.get("success", false)):
		return migrated
	var payload: Dictionary = migrated["envelope"]["payload"]
	var compatibility := ReleasePolicy.negotiate(runtime_release, payload.get("release", {}))
	if not bool(compatibility.get("success", false)):
		return compatibility
	var loaded := load_state(payload)
	if not bool(loaded.get("success", false)):
		return loaded
	_release = runtime_release
	return H.success({"migration_trace": migrated["migration_trace"], "compatibility": compatibility})

func export_state() -> Dictionary:
	var state := {
		"schema": STATE_SCHEMA,
		"generation": _generation,
		"release": _release.duplicate(true),
		"replay": _replay.export_state(),
		"observability": _observability.export_state(),
		"rate_limiter": _rate_limiter.export_state(),
		"checksum": "",
	}
	state["checksum"] = H.checksum(state)
	return state

func load_state(state: Dictionary) -> Dictionary:
	var checked := validate_state(state)
	if not bool(checked.get("success", false)):
		return checked
	var runtime_release := _release.duplicate(true)
	if not runtime_release.is_empty():
		checked = ReleasePolicy.negotiate(runtime_release, state["release"])
		if not bool(checked.get("success", false)):
			return checked
	checked = _replay.load_state(state["replay"])
	if not bool(checked.get("success", false)):
		return checked
	checked = _observability.load_state(state["observability"])
	if not bool(checked.get("success", false)):
		return checked
	checked = _rate_limiter.load_state(state["rate_limiter"])
	if not bool(checked.get("success", false)):
		return checked
	_generation = int(state["generation"])
	_release = runtime_release if not runtime_release.is_empty() else Dictionary(state["release"]).duplicate(true)
	return H.success()

func get_observability():
	return _observability

func get_recovery_store():
	return _recovery

func get_generation() -> int:
	return _generation

static func validate_state(state: Dictionary) -> Dictionary:
	var exact := H.exact_fields(state, STATE_FIELDS)
	if not bool(exact.get("success", false)):
		return H.failure("INVALID_CONSTRUCTION_PRODUCTION_SERVICE_STATE_FIELDS")
	if state.get("schema") != STATE_SCHEMA or not H.is_non_negative_integer(state.get("generation")):
		return H.failure("INVALID_CONSTRUCTION_PRODUCTION_SERVICE_STATE")
	var checked := ReleasePolicy.validate(state.get("release", {}))
	if not bool(checked.get("success", false)):
		return checked
	checked = ReplayStore.validate_state(state.get("replay", {}))
	if not bool(checked.get("success", false)):
		return checked
	checked = Observability.validate_state(state.get("observability", {}))
	if not bool(checked.get("success", false)):
		return checked
	checked = RateLimiter.validate_state(state.get("rate_limiter", {}))
	if not bool(checked.get("success", false)):
		return checked
	if int(state["generation"]) != int(state["replay"]["generation"]):
		return H.failure("INCONSISTENT_CONSTRUCTION_PRODUCTION_GENERATION")
	if int(state["observability"]["gauges"]["replay_entries"]) != state["replay"]["entries"].size():
		return H.failure("INCONSISTENT_CONSTRUCTION_REPLAY_GAUGE")
	if int(state["observability"]["gauges"]["rate_limit_subjects"]) != state["rate_limiter"]["subjects"].size():
		return H.failure("INCONSISTENT_CONSTRUCTION_RATE_LIMIT_GAUGE")
	return H.validate_checksum(state, "CONSTRUCTION_PRODUCTION_SERVICE_STATE_CHECKSUM_MISMATCH")

func _terminal_rejection(operation: Dictionary, error_code: String, details: Dictionary = {}, decision_override: String = "") -> Dictionary:
	var result := H.failure(error_code, {
		"accepted": false,
		"replay": false,
		"operation_id": String(operation["operation_id"]),
		"operation_checksum": String(operation["checksum"]),
	})
	for key in details:
		if typeof(key) != TYPE_STRING or not H.is_token(key) or result.has(key):
			continue
		var normalized := ContractUtils.canonicalize(details[key])
		if bool(normalized.get("success", false)):
			result[key] = normalized.get("value")
	var recorded := _replay.record(String(operation["operation_id"]), String(operation["checksum"]), result)
	if not bool(recorded.get("success", false)):
		_observability.increment("operations_failed")
		return recorded
	_generation += 1
	_observability.increment("operations_denied")
	_observability.set_gauge("replay_entries", _replay.get_entry_count())
	var decision := decision_override
	if decision.is_empty():
		decision = "RATE_LIMIT" if error_code == "CONSTRUCTION_PRODUCTION_RATE_LIMITED" else "DENY"
	_observability.append_audit(operation, decision, error_code, int(operation["tick"]))
	return result

func _safe_error_code(value, fallback: String) -> String:
	var candidate := String(value)
	return candidate if H.is_token(candidate) else fallback
