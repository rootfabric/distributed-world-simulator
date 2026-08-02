extends SceneTree

const F = preload("res://tests/construction/fixtures/c23_production_hardening_fixture.gd")
const H = preload("res://scripts/construction/hardening/construction_hardening_utils.gd")
const Operation = preload("res://scripts/construction/hardening/construction_production_operation.gd")
const StateEnvelope = preload("res://scripts/construction/hardening/construction_state_envelope.gd")
const Service = preload("res://scripts/construction/hardening/construction_production_hardening_service.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_test_secure_submit_and_exact_replay()
	_test_permission_and_rate_limit_terminal_replay()
	_test_untrusted_dependency_results_are_fenced()
	_test_restart_and_legacy_load()
	_finish()

func _test_secure_submit_and_exact_replay() -> void:
	var bundle := F.service()
	_ok(bundle["setup"], "service setup")
	var service = bundle["service"]
	var executor = bundle["executor"]
	var operation := F.operation(10)
	var accepted: Dictionary = service.submit(operation)
	_ok(accepted, "accepted operation")
	_assert(bool(accepted["accepted"]), "accepted flag")
	_assert(not bool(accepted["replay"]), "first execution not replay")
	_assert(executor.authoritative_writes == 1, "one authoritative write")
	var replay: Dictionary = service.submit(operation)
	_ok(replay, "exact replay")
	_assert(bool(replay["replay"]), "service replay flagged")
	_assert(executor.authoritative_writes == 1, "replay does not write")
	_assert(bundle["authorizer"].calls == 1, "replay bypasses repeated authorization without changing result")
	var conflict := Operation.create("operation/c23-000010", F.SUBJECT_ID, F.CONSTRUCT_ID, "build", F.PERMISSION_EPOCH, F.RELEASE_ID, 10, {"delta": 99})
	_err(service.submit(conflict), "CONSTRUCTION_PRODUCTION_OPERATION_ID_CONFLICT", "id conflict rejected")
	_assert(executor.authoritative_writes == 1, "conflict does not write")
	var audit: Array = service.get_observability().get_audit_events()
	_assert(audit.size() == 3, "accept replay and conflict audited")
	_assert(audit[0]["decision"] == "ACCEPT", "accept audit")
	_assert(audit[1]["decision"] == "REPLAY", "replay audit")
	_assert(audit[2]["decision"] == "DENY", "conflict audit")
	_err(service.setup(executor, bundle["authorizer"], F.release_descriptor()), "CONSTRUCTION_PRODUCTION_SERVICE_ALREADY_INITIALIZED", "service cannot be reinitialized")

func _test_permission_and_rate_limit_terminal_replay() -> void:
	var denied_bundle := F.service()
	denied_bundle["authorizer"].allowed = false
	var denied_operation := F.operation(20)
	var denied: Dictionary = denied_bundle["service"].submit(denied_operation)
	_err(denied, "CONSTRUCTION_PRODUCTION_PERMISSION_DENIED", "permission denied")
	denied_bundle["authorizer"].allowed = true
	var denied_replay: Dictionary = denied_bundle["service"].submit(denied_operation)
	_err(denied_replay, "CONSTRUCTION_PRODUCTION_PERMISSION_DENIED", "terminal denial replayed")
	_assert(bool(denied_replay["replay"]), "denial replay flagged")
	_assert(denied_bundle["executor"].authoritative_writes == 0, "denied operation never writes")
	var limited_bundle := F.service(2, 10)
	_ok(limited_bundle["service"].submit(F.operation(30, 1)), "rate request one")
	_ok(limited_bundle["service"].submit(F.operation(31, 2)), "rate request two")
	var limited := limited_bundle["service"].submit(F.operation(32, 3))
	_err(limited, "CONSTRUCTION_PRODUCTION_RATE_LIMITED", "rate limit enforced")
	_assert(limited_bundle["executor"].authoritative_writes == 2, "limited request does not write")
	_assert(limited_bundle["service"].get_observability().get_counter("operations_rate_limited") == 1, "rate metric")


func _test_untrusted_dependency_results_are_fenced() -> void:
	var denied_bundle := F.service()
	denied_bundle["authorizer"].allowed = false
	denied_bundle["authorizer"].denial_error_code = "contains space"
	denied_bundle["authorizer"].denial_details = {"runtime": Node.new(), "reason": "policy"}
	var denied_operation := F.operation(35)
	var denied: Dictionary = denied_bundle["service"].submit(denied_operation)
	_err(denied, "CONSTRUCTION_PRODUCTION_PERMISSION_DENIED", "unsafe authorizer code replaced")
	_assert(not denied.has("runtime"), "runtime authorizer detail removed")
	_assert(String(denied.get("reason", "")) == "policy", "safe authorizer detail retained")
	var denied_replay := denied_bundle["service"].submit(denied_operation)
	_err(denied_replay, "CONSTRUCTION_PRODUCTION_PERMISSION_DENIED", "sanitized denial replayed")
	_assert(bool(denied_replay["replay"]), "sanitized denial is terminal")
	_ok(Service.validate_state(denied_bundle["service"].export_state()), "sanitized denial state validates")
	var invalid_authorizer_bundle := F.service()
	invalid_authorizer_bundle["authorizer"].return_non_dictionary = true
	var invalid_authorizer_operation := F.operation(37)
	_err(invalid_authorizer_bundle["service"].submit(invalid_authorizer_operation), "CONSTRUCTION_PRODUCTION_AUTHORIZER_RESULT_INVALID", "non-dictionary authorizer result fenced")
	var invalid_authorizer_replay := invalid_authorizer_bundle["service"].submit(invalid_authorizer_operation)
	_err(invalid_authorizer_replay, "CONSTRUCTION_PRODUCTION_AUTHORIZER_RESULT_INVALID", "invalid authorizer result replayed")
	_assert(bool(invalid_authorizer_replay["replay"]), "invalid authorizer result terminal")
	var invalid_executor_bundle := F.service()
	invalid_executor_bundle["executor"].return_non_dictionary = true
	var invalid_executor_operation := F.operation(38)
	_err(invalid_executor_bundle["service"].submit(invalid_executor_operation), "CONSTRUCTION_PRODUCTION_EXECUTOR_RESULT_INVALID", "non-dictionary executor result fenced")
	_assert(invalid_executor_bundle["executor"].total_calls == 1, "invalid executor called once")
	var invalid_executor_replay := invalid_executor_bundle["service"].submit(invalid_executor_operation)
	_err(invalid_executor_replay, "CONSTRUCTION_PRODUCTION_EXECUTOR_RESULT_INVALID", "invalid executor result replayed")
	_assert(bool(invalid_executor_replay["replay"]), "invalid executor result terminal")
	_assert(invalid_executor_bundle["executor"].total_calls == 1, "invalid executor terminal prevents retry call")
	var unsafe_bundle := F.service()
	unsafe_bundle["executor"].return_runtime_result = true
	var unsafe_operation := F.operation(36)
	var unsafe: Dictionary = unsafe_bundle["service"].submit(unsafe_operation)
	_err(unsafe, "CONSTRUCTION_PRODUCTION_EXECUTION_RESULT_NOT_SERIALIZABLE", "unsafe execution result fenced")
	_assert(unsafe_bundle["executor"].authoritative_writes == 1, "unsafe execution wrote once")
	var unsafe_replay := unsafe_bundle["service"].submit(unsafe_operation)
	_err(unsafe_replay, "CONSTRUCTION_PRODUCTION_EXECUTION_RESULT_NOT_SERIALIZABLE", "unsafe terminal replayed")
	_assert(bool(unsafe_replay["replay"]), "unsafe terminal replay flag")
	_assert(unsafe_bundle["executor"].total_calls == 1, "unsafe terminal prevents repeated execution")
	var unsafe_audit: Array = unsafe_bundle["service"].get_observability().get_audit_events()
	_assert(unsafe_audit.size() == 2 and unsafe_audit[0]["decision"] == "FAIL" and unsafe_audit[1]["decision"] == "REPLAY", "unsafe execution audit sequence")
	var valid_state: Dictionary = unsafe_bundle["service"].export_state()
	_ok(Service.validate_state(valid_state), "unsafe terminal state validates")
	var inconsistent_generation := valid_state.duplicate(true)
	inconsistent_generation["generation"] = int(inconsistent_generation["generation"]) + 1
	inconsistent_generation["checksum"] = H.checksum(inconsistent_generation)
	_err(Service.validate_state(inconsistent_generation), "INCONSISTENT_CONSTRUCTION_PRODUCTION_GENERATION", "signed inconsistent generation rejected")
	var inconsistent_gauge := valid_state.duplicate(true)
	inconsistent_gauge["observability"]["gauges"]["replay_entries"] = 99
	inconsistent_gauge["observability"]["checksum"] = H.checksum(inconsistent_gauge["observability"])
	inconsistent_gauge["checksum"] = H.checksum(inconsistent_gauge)
	_err(Service.validate_state(inconsistent_gauge), "INCONSISTENT_CONSTRUCTION_REPLAY_GAUGE", "signed inconsistent replay gauge rejected")

func _test_restart_and_legacy_load() -> void:
	var uninitialized := Service.new()
	_err(uninitialized.checkpoint(0), "CONSTRUCTION_PRODUCTION_SERVICE_NOT_INITIALIZED", "checkpoint before setup rejected")
	var source := F.service()
	_err(source["service"].checkpoint(-1), "INVALID_CONSTRUCTION_PRODUCTION_CHECKPOINT_TICK", "negative checkpoint tick rejected")
	_ok(source["service"].submit(F.operation(40)), "source write")
	var state: Dictionary = source["service"].export_state()
	_ok(Service.validate_state(state), "service state validates")
	var envelope := StateEnvelope.create(state, F.RELEASE_ID, 40)
	var restored := F.service()
	_ok(restored["service"].load_envelope(envelope), "load current envelope")
	_assert(restored["service"].get_generation() == source["service"].get_generation(), "generation restored")
	var replay := restored["service"].submit(F.operation(40))
	_ok(replay, "old operation replay after restart")
	_assert(bool(replay["replay"]), "restart replay flagged")
	_assert(restored["executor"].authoritative_writes == 0, "restart replay does not invoke new executor")
	var legacy := StateEnvelope.create_legacy(state)
	var legacy_restored := F.service()
	var loaded := legacy_restored["service"].load_envelope(legacy)
	_ok(loaded, "legacy envelope loaded")
	_assert(Array(loaded["migration_trace"]).size() == 1, "legacy load migration trace")
	var candidate_executor := F.FakeExecutor.new()
	var candidate_authorizer := F.FakeAuthorizer.new()
	var candidate_service := Service.new()
	_ok(candidate_service.setup(candidate_executor, candidate_authorizer, F.release_descriptor("release/c23-2")), "candidate release setup")
	var rolling_load := candidate_service.load_envelope(envelope)
	_ok(rolling_load, "compatible old checkpoint loads into new release")
	_assert(String(candidate_service.export_state()["release"]["release_id"]) == "release/c23-2", "runtime release retained after rolling load")
	var corrupt := envelope.duplicate(true)
	corrupt["payload"]["generation"] = 999
	_err(restored["service"].load_envelope(corrupt), "CONSTRUCTION_PRODUCTION_STATE_PAYLOAD_CHECKSUM_MISMATCH", "corrupt envelope rejected")

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
		print("C23 production hardening integration: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("C23 production hardening integration: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
