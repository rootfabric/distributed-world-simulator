extends SceneTree

## ECO.EVO7 PERF1-PAR0.2 — focused dual recruitment executor acceptance.
##
## Proves the execution-authority handover:
##   - serial default is untouched (no injection -> SERIAL, no pool);
##   - an injected executor routes the SAME immutable generation input
##     through serial oracle + PAR0 process pool;
##   - an EXACT match promotes the PARALLEL result to the canonical source
##     that LS3.3 commits (canonical_source == PARALLEL_VERIFIED);
##   - any divergence (parity mismatch, stale job, wrong generation, wrong
##     input hash, duplicate/missing response, context divergence) is
##     FAIL-CLOSED: no generation commit, evidence persisted;
##   - one persistent pool per coordinator process (setup/shutdown exactly
##     once across many generations);
##   - dual-mode telemetry never enters canonical hashes.
##
## PAR0.2 IS NOT A SPEEDUP GATE: no timing threshold is asserted here.

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const Workbench = preload("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd")
const Kernel = preload("res://scripts/ecology/perf/eco_evo7_par0_recruitment_kernel_v1.gd")
const DualExecutor = preload("res://scripts/ecology/perf/eco_evo7_par02_dual_recruitment_executor_v1.gd")

const RECIPE := "MIXED_PHYSICAL_HETEROGENEITY"
const HASH_FIELDS: Array[String] = [
	"candidate_pool_hash", "dispersal_pool_hash", "recruitment_hash",
	"precompetition_population_hash", "competition_hash", "postcompetition_population_hash",
	"hereditary_pool_hash", "ecology_state_hash", "classification_hash", "workbench_hash",
]
const FORBIDDEN_SNAPSHOT_KEYS := ["recruitment_mode", "dual_executor_calls", "canonical_source", "parallel_hash", "serial_hash"]

var assertions := 0
var hash_comparisons := 0
var failures: Array[String] = []
var executor = null
var project_root := ""

func _init() -> void:
	project_root = ProjectSettings.globalize_path("res://")
	_serial_default_isolation()
	_executor_injection()
	_dual_generations_and_baseline_parity()
	_mismatch_fail_closed()
	_identity_rejections()
	_context_divergence_rejected()
	_telemetry_excluded_from_canonical_state()
	_clean_shutdown()
	_write_fixtures()
	_finish()

## ---------- phase A: serial default isolation ----------

func _serial_default_isolation() -> void:
	var pair := _build_workbench()
	if pair.is_empty():
		_fail("serial-default workbench setup failed")
		return
	var workbench: Object = pair["workbench"]
	var world: Object = pair["world"]
	var ls33: Object = workbench.ecology.core
	_check(not ls33.has_recruitment_executor(), "serial default: no executor injected")
	for step in 3:
		var snapshot: Dictionary = workbench.advance_generations(1)
		_check(not snapshot.is_empty(), "serial default: generation %d commits" % (step + 1))
		if snapshot.is_empty():
			return
		_serial_rows.append(_hash_row(workbench, snapshot))
	var profile: Dictionary = ls33.get_last_profile()
	_check(String(profile.get("recruitment_mode", "")) == "SERIAL", "serial default: recruitment mode is SERIAL")
	_check(int(profile.get("dual_executor_calls", -1)) == 0, "serial default: dual executor calls == 0")
	_check(not profile.has("canonical_source"), "serial default: no canonical_source telemetry")
	_check(not profile.has("failure_code"), "serial default: no failure telemetry")
	world.queue_free()

## ---------- phase B: executor setup + injection ----------

func _executor_injection() -> void:
	executor = DualExecutor.new()
	var ok: bool = executor.setup({
		"worker_count": 2,
		"session_root": project_root.path_join("artifacts/par02_sessions"),
		"evidence_dir": project_root.path_join("artifacts/par02/evidence"),
		"job_timeout_ms": 120_000,
	})
	_check(ok, "executor setup accepted (wc=2)")
	_check(not executor.is_pool_active(), "executor setup alone spawns no pool (lazy lifecycle)")
	var counters: Dictionary = executor.get_lifetime_counters()
	_check(int(counters["pool_setup_count"]) == 0, "no pool setup before first generation")
	var pair := _build_workbench()
	if pair.is_empty():
		_fail("dual workbench setup failed")
		return
	_dual_workbench = pair["workbench"]
	_dual_world = pair["world"]
	var ls33: Object = _dual_workbench.ecology.core
	_check(ls33.set_recruitment_executor(executor), "executor can be injected into LS3.3")
	_check(ls33.has_recruitment_executor(), "LS3.3 reports injected executor")

var _dual_workbench: Object = null
var _dual_world: Object = null
var _serial_rows: Array[Dictionary] = []

## ---------- phase C: dual generations, canonical source, baseline parity ----------

func _dual_generations_and_baseline_parity() -> void:
	if _dual_workbench == null:
		_fail("dual workbench unavailable")
		return
	var ls33: Object = _dual_workbench.ecology.core
	for step in 3:
		var snapshot: Dictionary = _dual_workbench.advance_generations(1)
		_check(not snapshot.is_empty(), "dual generation %d commits via verified parallel result" % (step + 1))
		if snapshot.is_empty():
			return
		var dual_row := _hash_row(_dual_workbench, snapshot)
		if _serial_rows.size() > step:
			_check(_rows_exact(_serial_rows[step], dual_row),
				"external baseline parity: serial == dual generation %d (10 canonical hashes)" % (step + 1))
		var profile: Dictionary = ls33.get_last_profile()
		_check(String(profile.get("canonical_source", "")) == "PARALLEL_VERIFIED",
			"generation %d canonical source is PARALLEL_VERIFIED" % (step + 1))
	var report: Dictionary = executor.get_last_report()
	_check(bool(report.get("serial_oracle_used", false)), "executor ran the serial oracle")
	_check(bool(report.get("parallel_used", false)), "executor ran the parallel pool")
	_check(bool(report.get("comparison_passed", false)), "executor comparison passed")
	_check(String(report.get("canonical_source", "")) == "PARALLEL_VERIFIED", "executor reports PARALLEL_VERIFIED source")
	_check(String(report.get("serial_hash", "a")) == String(report.get("parallel_hash", "b")) and not String(report.get("serial_hash", "")).is_empty(),
		"executor serial and parallel recruitment hashes match")
	_check(String(report.get("serial_hash", "")) == String(ls33.last_recruitment_hash),
		"LS3.3 canonical recruitment hash equals executor parallel hash")
	var counters: Dictionary = executor.get_lifetime_counters()
	_check(int(counters["pool_setup_count"]) == 1, "pool setup exactly once across generations")
	_check(executor.is_pool_active(), "pool stays active across generations")
	_check(int(counters["generation_jobs"]) == 3, "three generation jobs used the same pool")

## ---------- phase D: mismatch fail-closed ----------

func _mismatch_fail_closed() -> void:
	if _dual_workbench == null:
		return
	var ls33: Object = _dual_workbench.ecology.core
	var generation_before := int(ls33.generation)
	var population_before := String(ls33.population_hash)
	executor.set_test_fault_injection("ALTER_PARALLEL_EVENT", {"index": 0, "field": "shadow_fitness", "value": -123.0})
	var snapshot: Dictionary = _dual_workbench.advance_generations(1)
	_check(snapshot.is_empty(), "mismatch: generation did NOT commit")
	_check(int(ls33.generation) == generation_before, "mismatch: generation counter did not advance")
	_check(String(ls33.population_hash) == population_before, "mismatch: population hash did not advance")
	var profile: Dictionary = ls33.get_last_profile()
	_check(String(profile.get("failure_code", "")) == "PAR02_RECRUITMENT_PARITY_FAILURE",
		"mismatch: PAR02_RECRUITMENT_PARITY_FAILURE surfaced")
	_check(bool(profile.get("comparison_passed", true)) == false, "mismatch: comparison_passed false in LS3.3 profile")
	var evidence_path := String(profile.get("evidence_path", ""))
	_check(not evidence_path.is_empty() and FileAccess.file_exists(evidence_path), "mismatch: evidence dump persisted")
	var evidence := _read_json(evidence_path)
	_check(not String(evidence.get("first_mismatch", "")).is_empty(), "mismatch evidence carries first mismatch")
	_check(String(evidence.get("serial_recruitment_hash", "a")) != String(evidence.get("parallel_recruitment_hash", "a")),
		"mismatch evidence carries divergent serial/parallel hashes")
	evidence["fixture"] = "par02_mismatch"
	_mismatch_fixture = evidence
	executor.set_test_fault_injection("")
	var recovery: Dictionary = _dual_workbench.advance_generations(1)
	_check(not recovery.is_empty(), "test-only fault removed: simulation continues (no hidden fallback involved)")
	var profile_after: Dictionary = ls33.get_last_profile()
	_check(String(profile_after.get("canonical_source", "")) == "PARALLEL_VERIFIED",
		"post-fault generation is again PARALLEL_VERIFIED")

## ---------- phase E: stale / identity rejections ----------

func _identity_rejections() -> void:
	if _dual_workbench == null:
		return
	var ls33: Object = _dual_workbench.ecology.core
	var cases := [
		["INJECT_STALE_RESPONSE", "STALE_WORKER_RESULT", "stale job_id rejected before merge"],
		["INJECT_WRONG_GENERATION", "GENERATION_MISMATCH", "wrong generation rejected"],
		["INJECT_WRONG_INPUT_HASH", "INPUT_HASH_MISMATCH", "wrong input hash rejected"],
		["INJECT_DUPLICATE_RESPONSE", "DUPLICATE_WORKER_RESULT", "duplicate worker result rejected"],
	]
	for case in cases:
		var generation_before := int(ls33.generation)
		executor.set_test_fault_injection(String(case[0]), {"worker_index": 0})
		var snapshot: Dictionary = _dual_workbench.advance_generations(1)
		_check(snapshot.is_empty(), "%s: no generation commit" % case[2])
		var profile: Dictionary = ls33.get_last_profile()
		_check(String(profile.get("failure_code", "")) == String(case[1]),
			"%s: %s" % [case[2], case[1]])
		_check(int(ls33.generation) == generation_before, "%s: state did not advance" % case[2])
		if String(case[0]) == "INJECT_STALE_RESPONSE":
			var stale_fixture := {
				"fixture": "par02_stale_response",
				"injected_generation": generation_before,
				"response_generation": generation_before - 1,
				"failure_code": String(profile.get("failure_code", "")),
			}
			_stale_fixture = stale_fixture
	executor.set_test_fault_injection("")

## ---------- phase F: context divergence ----------

func _context_divergence_rejected() -> void:
	if _dual_workbench == null:
		return
	var ls33: Object = _dual_workbench.ecology.core
	var snapshot: Dictionary = ls33.get_snapshot()
	var candidates := _typed(snapshot.get("last_candidates", []))
	var routes := _typed(snapshot.get("last_routes", []))
	var context := Kernel.build_context(
		String(ls33.SCHEMA), String(ls33.VERSION), String(ls33.REVISION),
		int(ls33.environment_seed) + 1, String(ls33.environment_field_hash),
		ls33.environment_cells)
	var result: Dictionary = executor.evaluate_generation(int(ls33.generation) + 1, candidates, routes, context)
	_check(not bool(result.get("success", true)), "diverged context rejected (fail-closed)")
	_check(String(result.get("failure_code", "")) == "CONTEXT_MISMATCH", "context divergence code CONTEXT_MISMATCH")
	_check(int(executor.get_lifetime_counters()["pool_setup_count"]) == 1, "context divergence: pool untouched")

## ---------- phase G: telemetry exclusion ----------

func _telemetry_excluded_from_canonical_state() -> void:
	if _dual_workbench == null:
		return
	var ls33: Object = _dual_workbench.ecology.core
	var snapshot: Dictionary = ls33.get_snapshot()
	var leaked := false
	for forbidden in FORBIDDEN_SNAPSHOT_KEYS:
		if snapshot.has(forbidden):
			leaked = true
	_check(not leaked, "dual telemetry keys never enter the ecology snapshot")
	_check(String(snapshot.get("state_hash", "")).length() == 64, "state hash remains canonical under dual mode")

## ---------- phase H: clean shutdown ----------

func _clean_shutdown() -> void:
	if executor == null:
		_fail("executor missing for shutdown phase")
		return
	executor.shutdown()
	var counters: Dictionary = executor.get_lifetime_counters()
	_check(int(counters["pool_shutdown_count"]) == 1, "pool shutdown exactly once")
	_check(not executor.is_pool_active(), "pool inactive after shutdown")
	executor.shutdown()
	_check(int(executor.get_lifetime_counters()["pool_shutdown_count"]) == 1, "second shutdown is a no-op")
	if _dual_world != null:
		_dual_world.queue_free()

## ---------- helpers ----------

func _build_workbench() -> Dictionary:
	var world = EarthWorld.new()
	root.add_child(world)
	if not world.setup(null):
		world.queue_free()
		return {}
	var workbench = Workbench.new()
	if not workbench.setup(world, {"environment_recipe": RECIPE}):
		world.queue_free()
		return {}
	return {"world": world, "workbench": workbench}

func _hash_row(workbench: Object, snapshot: Dictionary) -> Dictionary:
	var ecology: Dictionary = workbench.get_ecology_snapshot()
	return {
		"generation": int(snapshot.get("generation", -1)),
		"candidate_pool_hash": String(ecology.get("candidate_pool_hash", "")),
		"dispersal_pool_hash": String(ecology.get("dispersal_pool_hash", "")),
		"recruitment_hash": String(ecology.get("recruitment_hash", "")),
		"precompetition_population_hash": String(ecology.get("precompetition_population_hash", "")),
		"competition_hash": String(ecology.get("competition_hash", "")),
		"postcompetition_population_hash": String(ecology.get("postcompetition_population_hash", "")),
		"hereditary_pool_hash": String(ecology.get("hereditary_pool_hash", "")),
		"ecology_state_hash": String(snapshot.get("ecology_state_hash", "")),
		"classification_hash": String(snapshot.get("classification_hash", "")),
		"workbench_hash": String(snapshot.get("workbench_hash", "")),
	}

func _rows_exact(a: Dictionary, b: Dictionary) -> bool:
	for field in HASH_FIELDS:
		hash_comparisons += 1
		if String(a.get(field, "")) != String(b.get(field, "")):
			return false
	return int(a.get("generation", -1)) == int(b.get("generation", -1))

func _typed(source: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for value in source:
		if not value is Dictionary:
			return []
		out.append(value)
	return out

func _read_json(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}

var _mismatch_fixture: Dictionary = {}
var _stale_fixture: Dictionary = {}

func _write_fixtures() -> void:
	var dir := project_root.path_join("artifacts/par02")
	DirAccess.make_dir_recursive_absolute(dir)
	if not _mismatch_fixture.is_empty():
		var file := FileAccess.open(dir.path_join("par02_mismatch_fixture.json"), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(_mismatch_fixture, "  "))
			file.close()
	if not _stale_fixture.is_empty():
		var file := FileAccess.open(dir.path_join("par02_stale_response_fixture.json"), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(_stale_fixture, "  "))
			file.close()

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
		push_error("PAR02 ACCEPTANCE FAIL: " + label)

func _fail(message: String) -> void:
	assertions += 1
	failures.append(message)
	push_error("PAR02 ACCEPTANCE FAIL: " + message)

func _finish() -> void:
	_check(hash_comparisons == 30, "external baseline parity compared 30 canonical hash pairs (3 generations x 10)")
	print("PAR02 hash comparisons exact: %d/30" % hash_comparisons)
	if failures.is_empty():
		print("ECO.EVO7 PAR0.2 Dual Recruitment: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 PAR0.2 Dual Recruitment FAIL: " + failure)
	print("ECO.EVO7 PAR0.2 Dual Recruitment: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
