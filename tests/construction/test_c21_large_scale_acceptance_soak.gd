extends SceneTree

const F = preload("res://tests/construction/fixtures/c21_large_scale_acceptance_fixture.gd")
const Suite = preload("res://scripts/construction/acceptance/construction_large_scale_suite.gd")
const Report = preload("res://scripts/construction/acceptance/construction_scale_report.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var first := Suite.run(F.soak_profile())
	_ok(first, "first soak")
	var report: Dictionary = first.get("report", {})
	_ok(Report.validate(report), "soak report")
	_assert(String(report.status) == "PASS", "soak pass")
	_assert(report.invariant_failures.is_empty(), "soak invariants")
	var metrics: Dictionary = report.metrics
	_assert(int(metrics.ticks_completed) == 8192, "soak ticks")
	_assert(int(metrics.constructs_registered) == 30000, "soak constructs")
	_assert(int(metrics.item_backed_parts_modeled) == 2880000, "soak item-backed parts")
	_assert(int(metrics.build_plans_completed) == 2000, "soak plans")
	_assert(int(metrics.fabrication_jobs_completed) == 6000, "soak fabrication")
	_assert(int(metrics.procurement_orders_completed) == 8000, "soak orders")
	_assert(int(metrics.shipments_delivered) == 8000, "soak shipments")
	_assert(int(metrics.damage_events_applied) == 5000, "soak damage")
	_assert(int(metrics.collapse_events_completed) == 1500, "soak collapse")
	_assert(int(metrics.repair_events_completed) == 3500, "soak repair")
	_assert(int(metrics.authority_migrations_completed) == 2000, "soak migrations")
	_assert(int(metrics.reconnect_waves_completed) == 64, "soak reconnects")
	_assert(int(metrics.operations_attempted) >= 100000, "soak operations")
	_assert(int(metrics.duplicate_commits) == 0, "soak no duplicate commits")
	_assert(int(metrics.lost_item_identities) == 0, "soak identity")
	_assert(int(metrics.material_balance_delta) == 0, "soak material conservation")
	_assert(int(metrics.max_presented) <= 1024, "soak presentation budget")
	_assert(int(metrics.max_simulated) <= 8192, "soak simulation budget")
	_assert(int(metrics.max_summarized) <= 20000, "soak summary budget")
	_assert(int(metrics.wall_time_ms) <= 180000, "soak wall time")
	_assert(String(report.determinism_checksum).length() == 64, "soak determinism checksum")
	_assert(int(metrics.checkpoint_count) == 1, "soak checkpoint crossed")
	_finish()

func _ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])

func _assert(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("C21 large-scale acceptance soak: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("C21 large-scale acceptance soak: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
