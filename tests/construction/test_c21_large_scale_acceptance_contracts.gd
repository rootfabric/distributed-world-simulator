extends SceneTree

const F = preload("res://tests/construction/fixtures/c21_large_scale_acceptance_fixture.gd")
const Profile = preload("res://scripts/construction/acceptance/construction_scale_profile.gd")
const Metrics = preload("res://scripts/construction/acceptance/construction_scale_metrics.gd")
const Report = preload("res://scripts/construction/acceptance/construction_scale_report.gd")
const State = preload("res://scripts/construction/acceptance/construction_scale_state.gd")
const Generator = preload("res://scripts/construction/acceptance/construction_scale_workload_generator.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_test_profile()
	_test_metrics()
	_test_state()
	_test_report()
	_test_generator()
	_finish()

func _test_profile() -> void:
	var profile := F.acceptance_profile()
	_ok(Profile.validate(profile), "acceptance profile")
	_assert(int(profile.construct_count) == 20000, "twenty thousand constructs")
	_assert(int(profile.construct_count) * int(profile.parts_per_construct) == 1280000, "million item-backed parts")
	_assert(int(profile.build_plan_count) == 1000, "one thousand build plans")
	_assert(int(profile.authority_migration_count) == 1000, "migration load")
	_assert(int(profile.reconnect_wave_count) == 32, "reconnect waves")
	var unknown := profile.duplicate(true)
	unknown["unknown_field"] = true
	_err(Profile.validate(unknown), "UNEXPECTED_FIELD", "unknown profile field")
	var bad_checksum := profile.duplicate(true)
	bad_checksum.construct_count = 19999
	_err(Profile.validate(bad_checksum), "CONSTRUCTION_SCALE_PROFILE_CHECKSUM_MISMATCH", "profile checksum")
	var bad_budget := Profile.create("bad-budget", {"construct_count": 100, "build_plan_count": 10, "agent_count": 2, "server_count": 2, "warehouse_count": 2, "soak_ticks": 10, "commands_per_tick": 1, "presentation_budget": 20, "simulation_budget": 10, "summary_budget": 50})
	_err(Profile.validate(bad_budget), "CONSTRUCTION_SCALE_PROFILE_PRESENTATION_BUDGET_INVALID", "budget ordering")
	var too_many_plans := Profile.create("bad-plans", {"construct_count": 10, "build_plan_count": 11, "agent_count": 2, "server_count": 2, "warehouse_count": 2, "soak_ticks": 10, "commands_per_tick": 1, "presentation_budget": 1, "simulation_budget": 2, "summary_budget": 5})
	_err(Profile.validate(too_many_plans), "CONSTRUCTION_SCALE_PROFILE_BUILD_PLAN_COUNT_INVALID", "plan count")

func _test_metrics() -> void:
	var metrics := Metrics.create()
	metrics.operations_attempted = 100
	metrics.operations_committed = 90
	metrics.exact_replays = 10
	metrics = Metrics.seal(metrics)
	_ok(Metrics.validate(metrics), "metrics")
	_assert(int(metrics.operations_attempted) == 100, "metrics attempts")
	var tampered := metrics.duplicate(true)
	tampered.duplicate_commits = 1
	_err(Metrics.validate(tampered), "CONSTRUCTION_SCALE_METRICS_CHECKSUM_MISMATCH", "metrics checksum")
	var negative := metrics.duplicate(true)
	negative.wall_time_ms = -1
	negative.checksum = Metrics.compute_checksum(negative)
	_err(Metrics.validate(negative), "CONSTRUCTION_SCALE_METRICS_FIELD_INVALID", "negative metric")

func _test_state() -> void:
	var state := State.create(F.persistence_profile())
	state.constructs[Generator.construct_id(0)] = {"owner_server_id": Generator.server_id(0), "authority_epoch": 1}
	state.metrics = Metrics.seal(state.metrics)
	state = State.seal(state)
	_ok(State.validate(state), "state")
	var tampered := state.duplicate(true)
	tampered.tick = 1
	_err(State.validate(tampered), "CONSTRUCTION_SCALE_STATE_CHECKSUM_MISMATCH", "state checksum")
	var bad_map := state.duplicate(true)
	bad_map.constructs = []
	bad_map.checksum = State.compute_checksum(bad_map)
	_err(State.validate(bad_map), "CONSTRUCTION_SCALE_STATE_MAP_INVALID", "state map")

func _test_report() -> void:
	var profile := F.persistence_profile()
	var metrics := Metrics.create()
	metrics.ticks_completed = int(profile.soak_ticks)
	var report := Report.create("large-scale-report/test", profile, "PASS", metrics, [], "state-checksum", "determinism-checksum", int(profile.soak_ticks))
	_ok(Report.validate(report), "report")
	_assert(String(report.status) == "PASS", "report pass")
	var bad_status := report.duplicate(true)
	bad_status.status = "UNKNOWN"
	bad_status.checksum = Report.compute_checksum(bad_status)
	_err(Report.validate(bad_status), "CONSTRUCTION_SCALE_REPORT_STATUS_INVALID", "report status")
	var bad_nested := report.duplicate(true)
	bad_nested.metrics.operations_attempted = 1
	bad_nested.checksum = Report.compute_checksum(bad_nested)
	_err(Report.validate(bad_nested), "CONSTRUCTION_SCALE_REPORT_METRICS_INVALID", "nested metrics")

func _test_generator() -> void:
	_assert(Generator.construct_id(7) == "construct/c21/000007", "construct id")
	_assert(Generator.plan_id(7) == "build-plan/c21/00007", "plan id")
	_assert(Generator.agent_id(7) == "agent/c21/0007", "agent id")
	_assert(Generator.deterministic_index(21, 100, 4, 1000) == Generator.deterministic_index(21, 100, 4, 1000), "deterministic index")
	_assert(Generator.deterministic_index(21, 100, 4, 1000) != Generator.deterministic_index(21, 101, 4, 1000), "tick changes index")

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
		print("C21 large-scale acceptance contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("C21 large-scale acceptance contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
