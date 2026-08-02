extends SceneTree

const F = preload("res://tests/construction/fixtures/c23_production_hardening_fixture.gd")
const Service = preload("res://scripts/construction/hardening/construction_production_hardening_service.gd")

const OPERATION_COUNT := 2000
const CHECKPOINT_INTERVAL := 200

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var first := _run_profile()
	var second := _run_profile()
	_assert(String(first["state_checksum"]) == String(second["state_checksum"]), "deterministic final state checksum")
	_assert(String(first["audit_tail"]) == String(second["audit_tail"]), "deterministic audit chain")
	_assert(int(first["writes"]) == OPERATION_COUNT, "all authoritative writes exactly once")
	_assert(int(first["value"]) == OPERATION_COUNT, "authoritative value conserved")
	_assert(int(first["replay_entries"]) == OPERATION_COUNT, "all operations replayable")
	_assert(int(first["accepted"]) == OPERATION_COUNT, "accepted metric")
	_assert(int(first["replayed"]) == OPERATION_COUNT / CHECKPOINT_INTERVAL, "restart replay metric")
	_assert(int(first["audit_events"]) == OPERATION_COUNT + OPERATION_COUNT / CHECKPOINT_INTERVAL, "audit event count")
	_finish()

func _run_profile() -> Dictionary:
	var bundle := F.service(OPERATION_COUNT + 100, OPERATION_COUNT + 100)
	var service = bundle["service"]
	for index in range(OPERATION_COUNT):
		var operation := F.operation(10000 + index, index)
		var result: Dictionary = service.submit(operation)
		_assert(bool(result.get("success", false)), "soak operation %d" % index)
		if (index + 1) % CHECKPOINT_INTERVAL == 0:
			var checkpoint := service.checkpoint(index)
			_assert(bool(checkpoint.get("success", false)), "soak checkpoint %d" % index)
			var replay := service.submit(operation)
			_assert(bool(replay.get("success", false)) and bool(replay.get("replay", false)), "checkpoint boundary replay %d" % index)
	var state: Dictionary = service.export_state()
	var audit: Array = service.get_observability().get_audit_events()
	return {
		"state_checksum": state["checksum"],
		"audit_tail": audit.back()["checksum"],
		"writes": bundle["executor"].authoritative_writes,
		"value": bundle["executor"].value,
		"replay_entries": state["replay"]["entries"].size(),
		"accepted": service.get_observability().get_counter("operations_accepted"),
		"replayed": service.get_observability().get_counter("operations_replayed"),
		"audit_events": audit.size(),
	}

func _assert(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("C23 production hardening soak: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("C23 production hardening soak: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
