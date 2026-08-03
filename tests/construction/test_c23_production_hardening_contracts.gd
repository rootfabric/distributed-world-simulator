extends SceneTree

const F = preload("res://tests/construction/fixtures/c23_production_hardening_fixture.gd")
const H = preload("res://scripts/construction/hardening/construction_hardening_utils.gd")
const Operation = preload("res://scripts/construction/hardening/construction_production_operation.gd")
const StateEnvelope = preload("res://scripts/construction/hardening/construction_state_envelope.gd")
const ReleasePolicy = preload("res://scripts/construction/hardening/construction_release_policy.gd")
const ReplayStore = preload("res://scripts/construction/hardening/construction_replay_store.gd")
const Observability = preload("res://scripts/construction/hardening/construction_observability.gd")
const RateLimiter = preload("res://scripts/construction/hardening/construction_rate_limiter.gd")
const RecoveryStore = preload("res://scripts/construction/hardening/construction_recovery_store.gd")
const Fuzzer = preload("res://scripts/construction/hardening/construction_dto_fuzzer.gd")
const ContractUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_test_operation_and_fuzzing()
	_test_backward_compatible_state()
	_test_rolling_upgrade()
	_test_replay_metrics_and_rate_contracts()
	_finish()

func _test_operation_and_fuzzing() -> void:
	var operation := F.operation(1)
	_ok(Operation.validate(operation), "valid operation")
	_assert(String(operation["payload_checksum"]).length() == 64, "payload checksum")
	_assert(String(operation["checksum"]).length() == 64, "operation checksum")
	var cases := Fuzzer.operation_cases(operation)
	_assert(cases.size() == Operation.FIELDS.size() * 2 + 2, "deterministic fuzz case count")
	var fuzzed := Fuzzer.verify_rejected(cases)
	_ok(fuzzed, "all malformed DTOs rejected")
	_assert(int(fuzzed["case_count"]) == cases.size(), "all fuzz cases executed")
	var runtime_payload := operation.duplicate(true)
	runtime_payload["payload"] = {"node": Node.new()}
	runtime_payload["payload_checksum"] = ""
	runtime_payload["checksum"] = H.checksum(runtime_payload)
	_err(Operation.validate(runtime_payload), "CONSTRUCTION_PRODUCTION_PAYLOAD_CHECKSUM_MISMATCH", "runtime object rejected")
	_err(H.validate_checksum({"runtime": Node.new(), "checksum": ""}, "INVALID_TEST_CHECKSUM"), "INVALID_TEST_CHECKSUM", "empty checksum cannot validate non-serializable state")

func _test_backward_compatible_state() -> void:
	var payload := {"generation": 12, "construct_checksum": "abc"}
	var legacy := StateEnvelope.create_legacy(payload)
	_ok(StateEnvelope.validate(legacy, 1), "legacy state validates")
	var migrated := StateEnvelope.migrate(legacy, F.RELEASE_ID, 44)
	_ok(migrated, "legacy state migrates")
	_assert(int(migrated["envelope"]["state_version"]) == 2, "migrated to v2")
	_assert(Array(migrated["migration_trace"]).size() == 1, "migration trace")
	_assert(migrated["envelope"]["payload"] == payload, "payload preserved exactly")
	_ok(StateEnvelope.validate(migrated["envelope"]), "migrated envelope validates")
	var corrupt: Dictionary = migrated["envelope"].duplicate(true)
	corrupt["payload"]["generation"] = 13
	_err(StateEnvelope.validate(corrupt), "CONSTRUCTION_PRODUCTION_STATE_PAYLOAD_CHECKSUM_MISMATCH", "corrupt payload rejected")

func _test_rolling_upgrade() -> void:
	var current := F.release_descriptor()
	var candidate := ReleasePolicy.create("release/c23-2", 2, 3, 1, 2, ["audit", "exact-replay", "future-capability"], true)
	_ok(ReleasePolicy.validate(current), "current release")
	_ok(ReleasePolicy.validate(candidate), "candidate release")
	var negotiated := ReleasePolicy.negotiate(current, candidate)
	_ok(negotiated, "rolling release negotiation")
	_assert(int(negotiated["state_version"]) == 2, "highest common state version")
	_assert(int(negotiated["operation_version"]) == 1, "common operation version")
	_assert(negotiated["shared_capabilities"] == ["audit", "exact-replay"], "capability intersection")
	_assert(bool(negotiated["candidate_read_only"]), "read-only candidate fenced")
	var incompatible := ReleasePolicy.create("release/c23-3", 3, 4, 2, 3, ["audit"])
	_err(ReleasePolicy.negotiate(current, incompatible), "INCOMPATIBLE_CONSTRUCTION_ROLLING_UPGRADE", "incompatible release rejected")
	var missing_exact_replay := ReleasePolicy.create("release/c23-4", 1, 2, 1, 1, ["audit"])
	_err(ReleasePolicy.negotiate(current, missing_exact_replay), "INCOMPATIBLE_CONSTRUCTION_ROLLING_UPGRADE_CAPABILITIES", "state-critical capability required")

func _test_replay_metrics_and_rate_contracts() -> void:
	var replay := ReplayStore.new()
	var operation := F.operation(2)
	var result := H.success({"value": 9})
	_ok(replay.record(String(operation["operation_id"]), String(operation["checksum"]), result), "record terminal result")
	var found := replay.lookup(String(operation["operation_id"]), String(operation["checksum"]))
	_ok(found, "lookup replay")
	_assert(bool(found["found"]), "terminal result found")
	var normalized_operation := F.operation(200)
	_ok(replay.record(String(normalized_operation["operation_id"]), String(normalized_operation["checksum"]), {"value": 9.0}), "normalized terminal result")
	var normalized := replay.lookup(String(normalized_operation["operation_id"]), String(normalized_operation["checksum"]))
	_assert(typeof(normalized["result"]["value"]) == TYPE_INT, "replay stores canonical JSON type")
	var conflict := operation.duplicate(true)
	conflict["payload"] = {"delta": 2}
	conflict["payload_checksum"] = ContractUtils.payload_hash(conflict["payload"])
	conflict["checksum"] = H.checksum(conflict)
	_err(replay.lookup(String(conflict["operation_id"]), String(conflict["checksum"])), "CONSTRUCTION_PRODUCTION_OPERATION_ID_CONFLICT", "operation id conflict")
	_ok(ReplayStore.validate_state(replay.export_state()), "replay state")
	var unsafe_operation := F.operation(3)
	_err(replay.record(String(unsafe_operation["operation_id"]), String(unsafe_operation["checksum"]), {"runtime": Node.new()}), "INVALID_CONSTRUCTION_REPLAY_RESULT", "unsafe terminal result rejected")
	var metrics := Observability.new()
	_ok(metrics.increment("operations_accepted"), "counter increment")
	_ok(metrics.append_audit(operation, "ACCEPT", "", 2), "audit append")
	_err(metrics.append_audit(operation, "DENY", "contains space", 3), "INVALID_CONSTRUCTION_AUDIT_ERROR_CODE", "invalid audit error code rejected")
	_err(metrics.append_audit({}, "DENY", "SAFE_CODE", 3), "INVALID_CONSTRUCTION_AUDIT_EVENT", "malformed audit identity rejected before append")
	_ok(Observability.validate_state(metrics.export_state()), "observability state")
	var audit_state := metrics.export_state()
	_assert(not JSON.stringify(audit_state).contains("part/c23-000002"), "audit excludes payload")
	var injected_event: Dictionary = audit_state["audit"][0]
	injected_event["payload"] = {"secret": true}
	injected_event["checksum"] = H.checksum(injected_event)
	audit_state["audit"][0] = injected_event
	audit_state["checksum"] = H.checksum(audit_state)
	_err(Observability.validate_state(audit_state), "INVALID_CONSTRUCTION_AUDIT_FIELDS", "audit payload injection rejected")
	var limiter := RateLimiter.new()
	_ok(limiter.setup(2, 10), "rate limiter setup")
	_ok(limiter.consume(F.SUBJECT_ID, "build", 1), "rate request one")
	_ok(limiter.consume(F.SUBJECT_ID, "build", 2), "rate request two")
	_err(limiter.consume(F.SUBJECT_ID, "build", 3), "CONSTRUCTION_PRODUCTION_RATE_LIMITED", "rate request limited")
	_ok(limiter.consume(F.SUBJECT_ID, "build", 10), "new window")
	_err(limiter.consume(F.SUBJECT_ID, "build", RateLimiter.MAX_SAFE_JSON_INTEGER), "INVALID_CONSTRUCTION_RATE_LIMIT_REQUEST", "unsafe retry tick rejected")
	_ok(RateLimiter.validate_state(limiter.export_state()), "rate limiter state")
	var recovery := RecoveryStore.new()
	_ok(recovery.commit(StateEnvelope.create({"value": 1}, F.RELEASE_ID, 1)), "recovery slot commit")
	var imported := RecoveryStore.new()
	_ok(imported.replace_slots(recovery.get_slots(), 1), "validated recovery state import")
	var invalid_slots := recovery.get_slots()
	invalid_slots[0]["sequence"] = 1
	invalid_slots[0]["checksum"] = H.checksum(invalid_slots[0])
	_err(imported.replace_slots(invalid_slots, 1), "INVALID_CONSTRUCTION_RECOVERY_SEQUENCE", "non-monotonic recovery sequence rejected")

func _ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])

func _err(result: Dictionary, code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [message, result])

func _assert(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("C23 production hardening contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("C23 production hardening contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
