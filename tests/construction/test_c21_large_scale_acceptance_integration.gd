extends SceneTree

const F = preload("res://tests/construction/fixtures/c21_large_scale_acceptance_fixture.gd")
const Harness = preload("res://scripts/construction/acceptance/construction_large_scale_harness.gd")
const Suite = preload("res://scripts/construction/acceptance/construction_large_scale_suite.gd")
const Report = preload("res://scripts/construction/acceptance/construction_scale_report.gd")
const Persistence = preload("res://scripts/construction/acceptance/construction_scale_persistence.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_test_large_acceptance()
	_test_operation_replay()
	_test_persistence_resume()
	_finish()

func _test_large_acceptance() -> void:
	var result := Suite.run(F.acceptance_profile())
	_ok(result, "suite run")
	var report: Dictionary = result.get("report", {})
	_ok(Report.validate(report), "report validation")
	_assert(String(report.status) == "PASS", "acceptance pass")
	_assert(report.invariant_failures.is_empty(), "no invariant failures")
	var metrics: Dictionary = report.metrics
	_assert(int(metrics.constructs_registered) == 20000, "construct population")
	_assert(int(metrics.item_backed_parts_modeled) == 1280000, "item-backed part scale")
	_assert(int(metrics.build_plans_created) == 1000, "plan population")
	_assert(int(metrics.build_plans_completed) == 1000, "plans completed")
	_assert(int(metrics.agent_goals_completed) == 1000, "agent goals completed")
	_assert(int(metrics.fabrication_jobs_completed) == 3000, "fabrication completed")
	_assert(int(metrics.procurement_orders_completed) == 4000, "orders completed")
	_assert(int(metrics.shipments_delivered) == 4000, "shipments delivered")
	_assert(int(metrics.damage_events_applied) == 2000, "damage events")
	_assert(int(metrics.collapse_events_completed) == 500, "collapse events")
	_assert(int(metrics.repair_events_completed) == 1500, "repair events")
	_assert(int(metrics.authority_migrations_completed) == 1000, "migrations completed")
	_assert(int(metrics.stale_epoch_rejections) == 1000, "stale epoch fenced")
	_assert(int(metrics.reconnect_waves_completed) == 32, "reconnect storms completed")
	_assert(int(metrics.operations_attempted) >= 50000, "operation volume")
	_assert(int(metrics.exact_replays) > 0, "exact replays observed")
	_assert(int(metrics.operation_conflicts) > 0, "operation conflicts observed")
	_assert(int(metrics.duplicate_commits) == 0, "no duplicate commits")
	_assert(int(metrics.lost_item_identities) == 0, "no lost item identities")
	_assert(int(metrics.material_balance_delta) == 0, "material conserved")
	_assert(int(metrics.max_presented) <= 512, "presentation budget")
	_assert(int(metrics.max_simulated) <= 4096, "simulation budget")
	_assert(int(metrics.max_summarized) <= 12000, "summary budget")
	_assert(int(metrics.wall_time_ms) <= 120000, "wall time budget")
	_assert(String(report.determinism_checksum).length() == 64, "determinism checksum")

func _test_operation_replay() -> void:
	var harness := Harness.new()
	_ok(harness.setup(F.persistence_profile()), "replay setup")
	var payload := {"construct_id": "construct/c21/manual", "authority_epoch": 1, "command": "BUILD_STAGE"}
	var first := harness.submit_operation("operation/c21/manual", payload)
	_ok(first, "first operation")
	_assert(not bool(first.replay), "first not replay")
	var replay := harness.submit_operation("operation/c21/manual", payload)
	_ok(replay, "operation replay")
	_assert(bool(replay.replay), "replay marker")
	var changed := payload.duplicate(true)
	changed.authority_epoch = 2
	_err(harness.submit_operation("operation/c21/manual", changed), "CONSTRUCTION_SCALE_OPERATION_ID_CONFLICT", "operation conflict")
	var state := harness.get_state()
	_assert(int(state.metrics.operations_committed) == 1, "one authoritative commit")
	_assert(int(state.metrics.exact_replays) == 1, "one exact replay")
	_assert(int(state.metrics.operation_conflicts) == 1, "one conflict")

func _test_persistence_resume() -> void:
	var profile := F.persistence_profile()
	var baseline := Harness.new()
	_ok(baseline.setup(profile), "baseline setup")
	var baseline_result := baseline.finish()
	_ok(baseline_result, "baseline finish")
	var interrupted := Harness.new()
	_ok(interrupted.setup(profile), "interrupted setup")
	_ok(interrupted.run_to_tick(int(profile.persistence_checkpoint_tick)), "run to checkpoint")
	var store := F.MemoryStore.new()
	_ok(Persistence.save(store, "c21/state", interrupted.export_state()), "save checkpoint")
	var loaded := Persistence.load(store, "c21/state")
	_ok(loaded, "load checkpoint")
	var resumed := Harness.new()
	_ok(resumed.load_state(loaded.state), "resume load")
	var resumed_result := resumed.finish()
	_ok(resumed_result, "resume finish")
	_assert(String(resumed_result.report.status) == "PASS", "resumed pass")
	_assert(String(resumed_result.report.determinism_checksum) == String(baseline_result.report.determinism_checksum), "restart deterministic")
	_assert(int(resumed_result.report.metrics.duplicate_commits) == 0, "restart no duplicates")
	_assert(int(resumed_result.report.metrics.material_balance_delta) == 0, "restart material conserved")
	_assert(int(resumed_result.state.metrics.checkpoint_count) >= 0, "checkpoint metrics available")
	var corrupted: Dictionary = Dictionary(loaded.state).duplicate(true)
	corrupted.tick = int(corrupted.tick) + 1
	_err(resumed.load_state(corrupted), "CONSTRUCTION_SCALE_HARNESS_STATE_INVALID", "corrupt state rejected")

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
		print("C21 large-scale acceptance integration: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("C21 large-scale acceptance integration: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
