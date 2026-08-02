extends SceneTree

const F = preload("res://tests/construction/fixtures/c23_production_hardening_fixture.gd")
const H = preload("res://scripts/construction/hardening/construction_hardening_utils.gd")
const Service = preload("res://scripts/construction/hardening/construction_production_hardening_service.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_test_lost_terminal_write_boundary()
	_test_lost_response_boundary()
	_test_corruption_fallback()
	_finish()

func _test_lost_terminal_write_boundary() -> void:
	var bundle := F.service()
	var operation := F.operation(100)
	_err(bundle["service"].submit(operation, Service.FAILURE_AFTER_EXECUTION_BEFORE_TERMINAL), "INJECTED_CONSTRUCTION_PRODUCTION_FAILURE_AFTER_EXECUTION", "failure after authoritative execution")
	_assert(bundle["executor"].authoritative_writes == 1, "first execution committed once")
	var retry := bundle["service"].submit(operation)
	_ok(retry, "retry after lost terminal write")
	_assert(bundle["executor"].authoritative_writes == 1, "executor idempotence prevents duplicate write")
	_assert(bool(retry["execution_result"]["executor_replay"]), "executor replay observed")
	var exact := bundle["service"].submit(operation)
	_ok(exact, "terminal replay after repair")
	_assert(bool(exact["replay"]), "service terminal replay")
	_assert(bundle["executor"].authoritative_writes == 1, "all retries still one write")

func _test_lost_response_boundary() -> void:
	var bundle := F.service()
	var operation := F.operation(110)
	_err(bundle["service"].submit(operation, Service.FAILURE_AFTER_TERMINAL_BEFORE_RESPONSE), "INJECTED_CONSTRUCTION_PRODUCTION_FAILURE_AFTER_TERMINAL", "failure after terminal record")
	_assert(bundle["executor"].authoritative_writes == 1, "terminal failure committed once")
	var retry := bundle["service"].submit(operation)
	_ok(retry, "retry after lost response")
	_assert(bool(retry["replay"]), "lost response recovered by replay")
	_assert(bundle["executor"].authoritative_writes == 1, "lost response no duplicate")

func _test_corruption_fallback() -> void:
	var bundle := F.service()
	var service = bundle["service"]
	_ok(service.submit(F.operation(120)), "checkpoint one operation")
	var first := service.checkpoint(120)
	_ok(first, "checkpoint one")
	_ok(service.submit(F.operation(121)), "checkpoint two operation")
	var second := service.checkpoint(121)
	_ok(second, "checkpoint two")
	_assert(int(second["sequence"]) > int(first["sequence"]), "checkpoint sequence monotonic")
	_ok(service.get_recovery_store().corrupt_latest_for_test("checksum", "0"), "corrupt latest slot")
	var recovered := service.recover()
	_ok(recovered, "recover previous checkpoint")
	_assert(bool(recovered["fallback_used"]), "fallback reported")
	_assert(service.get_generation() == 1, "previous generation restored")
	_assert(service.get_recovery_store().get_quarantine().size() == 1, "corrupt slot quarantined")
	var old_replay := service.submit(F.operation(120))
	_ok(old_replay, "previous operation replay after recovery")
	_assert(bool(old_replay["replay"]), "previous replay preserved")
	var rolled_back := service.submit(F.operation(121))
	_ok(rolled_back, "rolled-back operation safely reapplied")
	_assert(bundle["executor"].authoritative_writes == 2, "executor preserves its own exact operation result")

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
		print("C23 production hardening chaos: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("C23 production hardening chaos: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
