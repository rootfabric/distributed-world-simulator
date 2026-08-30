extends SceneTree

## ECO.EVO7 PAR2 — parallel-only recruitment acceptance (v1).
##
## Test matrix (mission section 21):
##   1. serial compatibility — no executor injected: behavior remains the
##      exact accepted serial behavior (replay-identical hashes);
##   2. parallel-only — PAR2 executor injected: generation commits come from
##      the SELECTED parallel backend (PROCESS_POOL per PAR1);
##   3. audit count — >=100-generation campaign (or survival limit):
##      serial_audit_calls << parallel_calls, elision >=80% (target 90%);
##   4. exact external baseline — 3 recipes x wc 1/2/4 x 12 generations,
##      >=108 generation comparisons of ALL canonical hashes vs the pure
##      serial baseline, zero mismatch;
##   5. forced backend failure            -> FAIL CLOSED (no generation commit);
##   6. forced audit mismatch             -> FAIL CLOSED;
##   7. forced parallel corruption        -> FAIL CLOSED;
##   plus parallel-only p50 non-regression vs the PAR1 direct measurement
##   (read from artifacts/par1_backend_benchmark.json when present).

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const PlanetPatch = preload("res://scripts/ecology/shadow/eco_evo7_ls30_planet_patch_v1.gd")
const EnvironmentField = preload("res://scripts/ecology/shadow/eco_evo7_ls31_environment_field_v1.gd")
const LS33 = preload("res://scripts/ecology/shadow/eco_evo7_ls33_dispersal_recruitment_v1.gd")
const Kernel = preload("res://scripts/ecology/perf/eco_evo7_par0_recruitment_kernel_v1.gd")
const Contract = preload("res://scripts/ecology/perf/eco_evo7_par1_recruitment_backend_contract_v1.gd")
const ProcessBackend = preload("res://scripts/ecology/perf/eco_evo7_par1_process_recruitment_backend_v1.gd")
const Par2Executor = preload("res://scripts/ecology/perf/eco_evo7_par2_canonical_recruitment_executor_v1.gd")

const RECIPES := ["MIXED_PHYSICAL_HETEROGENEITY", "WATER_GRADIENT_STRONG", "RELIEF_DRAINAGE_STRONG"]
const WORKER_COUNTS := [1, 2, 4]
const GENERATIONS := 12
const LONG_CAMPAIGN := 100
const FOUNDER_SEED := 20260832
const PLACEMENT_SEED := 320032
const EVOLUTION_SEED := 330033
const ENV_SEED := 20260831
const INITIAL_RECORDS := 64

var assertions := 0
var failures: Array[String] = []
var exact_comparisons := 0
var _project_root := ""
var _godot_bin := ""
var _session_root := ""
var _parallel_ms_samples: Array[float] = []
var _parallel_wc_samples: Array[int] = []
var _candidate_counts: Array[int] = []

func _init() -> void:
	_project_root = ProjectSettings.globalize_path("res://")
	_godot_bin = OS.get_environment("GODOT_BIN")
	if _godot_bin.is_empty():
		_godot_bin = "C:/Godot/godot/bin/godot.windows.editor.double.x86_64.console.exe"
	_session_root = OS.get_environment("ECO_PAR0_SESSION_ROOT")
	if _session_root.is_empty():
		_session_root = _project_root.path_join("artifacts/par0_sessions")

	var world = EarthWorld.new()
	root.add_child(world)
	_check(world.setup(null), "real Earth initializes")
	var patch := PlanetPatch.new().build(world, Vector3(-0.5, -0.86602540378444, 0.0).normalized(), 32, 16.0)
	_check(not patch.is_empty(), "acceptance patch builds")
	var fields := {}
	for recipe in RECIPES:
		fields[recipe] = EnvironmentField.new().generate(patch, recipe, ENV_SEED)
		_check(not fields[recipe].is_empty(), "field builds for %s" % recipe)

	## ---------------- Test 1: serial compatibility (no executor) ---------
	var serial_a = LS33.new()
	_check(serial_a.setup(patch, fields[RECIPES[0]], FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, INITIAL_RECORDS), "serial sim A initializes")
	_check(not serial_a.has_recruitment_executor(), "no executor by default")
	var serial_b = LS33.new()
	_check(serial_b.setup(patch, fields[RECIPES[0]], FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, INITIAL_RECORDS), "serial sim B initializes")
	for step in 6:
		var snap_a := serial_a.step_generation()
		var snap_b := serial_b.step_generation()
		if snap_a.is_empty() or snap_b.is_empty():
			_check(false, "serial replay generation %d completes" % (step + 1))
			break
		_check(_rows_equal(_hash_row(snap_a), _hash_row(snap_b)), "serial replay gen %d byte-identical hashes (accepted serial behavior unchanged)" % (step + 1))

	## ---------------- Baselines for test 4 -------------------------------
	var baselines := {}
	for recipe in RECIPES:
		var sim = LS33.new()
		_check(sim.setup(patch, fields[recipe], FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, INITIAL_RECORDS), "%s baseline initializes" % recipe)
		var rows: Array[Dictionary] = []
		for step in GENERATIONS:
			var snapshot := sim.step_generation()
			if snapshot.is_empty():
				_check(false, "%s baseline generation %d completes" % [recipe, step + 1])
				break
			rows.append(_hash_row(snapshot))
		baselines[recipe] = rows

	## ---------------- Tests 2+4: parallel-only vs external baseline ------
	for recipe in RECIPES:
		if baselines[recipe].size() != GENERATIONS:
			continue
		for worker_count in WORKER_COUNTS:
			var executor := Par2Executor.new()
			_check(executor.setup(_config(worker_count)), "%s executor wc=%d setup" % [recipe, worker_count])
			var sim = LS33.new()
			_check(sim.setup(patch, fields[recipe], FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, INITIAL_RECORDS), "%s parallel sim wc=%d initializes" % [recipe, worker_count])
			_check(sim.set_recruitment_executor(executor), "executor injected (%s wc=%d)" % [recipe, worker_count])
			var mismatch := ""
			for step in GENERATIONS:
				var snapshot := sim.step_generation()
				if snapshot.is_empty():
					mismatch = "generation %d failed (fail-closed or extinction)" % (step + 1)
					break
				var row := _hash_row(snapshot)
				if not _rows_equal(row, baselines[recipe][step]):
					mismatch = "generation %d canonical hash divergence vs serial baseline" % (step + 1)
					break
				exact_comparisons += 1
				var report: Dictionary = executor.get_last_report()
				_parallel_ms_samples.append(float(Dictionary(report.get("timings_ms", {})).get("parallel_ms", 0.0)))
				_parallel_wc_samples.append(worker_count)
				_candidate_counts.append(int(snapshot.get("record_count", 0)) * 2)
			if mismatch.is_empty():
				var telemetry: Dictionary = executor.get_telemetry()
				_check(int(telemetry["parallel_calls"]) == GENERATIONS, "%s wc=%d every generation ran the parallel backend" % [recipe, worker_count])
				_check(int(telemetry["serial_audit_calls"]) == 2, "%s wc=%d audits = gen1 + gen10 only (got %d)" % [recipe, worker_count, int(telemetry["serial_audit_calls"])])
			else:
				_check(false, "%s wc=%d %s" % [recipe, worker_count, mismatch])
			executor.shutdown()
	_check(exact_comparisons >= 108, "external exact comparisons >=108 (got %d)" % exact_comparisons)

	## ---------------- Test 3: long campaign audit fraction ---------------
	var long_executor := Par2Executor.new()
	_check(long_executor.setup(_config(4)), "long-campaign executor setup")
	var long_sim = LS33.new()
	_check(long_sim.setup(patch, fields[RECIPES[0]], FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, INITIAL_RECORDS), "long-campaign sim initializes")
	_check(long_sim.set_recruitment_executor(long_executor), "long-campaign executor injected")
	var completed := 0
	for step in LONG_CAMPAIGN:
		var snapshot := long_sim.step_generation()
		if snapshot.is_empty():
			break
		completed += 1
	var telemetry: Dictionary = long_executor.get_telemetry()
	_check(completed >= 30, "long campaign survived enough generations (%d)" % completed)
	_check(int(telemetry["parallel_calls"]) == completed, "every committed generation used the parallel backend")
	## Deterministic audit schedule proof: generation 1 + every 10th => exactly
	## 1 + floor(N/10) audits over N generations. For N=100 that is 11 (11%);
	## the ~10% oracle target is the asymptotic property of the schedule.
	var expected_audits := 1 + (completed / 10)
	_check(int(telemetry["serial_audit_calls"]) == expected_audits, "audit count matches deterministic schedule (got %d, expected %d)" % [int(telemetry["serial_audit_calls"]), expected_audits])
	_check(int(telemetry["last_audit_generation"]) == (completed / 10) * 10, "last audit generation is the last multiple of 10 (got %d)" % int(telemetry["last_audit_generation"]))
	_check(bool(telemetry["last_audit_pass"]), "last audit passed")
	var audit_fraction := float(telemetry["serial_audit_calls"]) / float(maxi(1, completed))
	_check(audit_fraction <= 0.20, "serial oracle <=20%% of generations (got %.1f%%)" % (audit_fraction * 100.0))
	var elision := float(telemetry["oracle_elided_generations"]) / float(maxi(1, completed))
	_check(elision >= 0.80, "oracle elision >=80%% (got %.1f%%)" % (elision * 100.0))
	long_executor.shutdown()
	print("PAR2 long campaign: gens=%d audits=%d elision=%.1f%%" % [completed, int(telemetry["serial_audit_calls"]), elision * 100.0])

	## ---------------- Tests 5-7: forced failures (fail closed) -----------
	_forced_failure(patch, fields[RECIPES[0]], "FORCE_BACKEND_FAILURE", "PAR2_BACKEND_FAILURE")
	_forced_failure(patch, fields[RECIPES[0]], "FORCE_AUDIT_MISMATCH", "PAR2_AUDIT_PARITY_FAILURE")
	_forced_failure(patch, fields[RECIPES[0]], "FORCE_PARALLEL_CORRUPTION", "PAR2_AUDIT_PARITY_FAILURE")

	## ---------------- Perf gate: parallel-only p50 vs PAR1 direct --------
	_perf_gate(patch, fields[RECIPES[0]])

	world.queue_free()
	_finish()

func _config(worker_count: int) -> Dictionary:
	return {
		"backend": "PROCESS_POOL",
		"worker_count": worker_count,
		"godot_bin": _godot_bin,
		"project_root": _project_root,
		"session_root": _session_root,
		"job_timeout_ms": 240_000,
		"audit_interval": 10,
		"audit_generation_1": true,
	}

func _forced_failure(patch: Dictionary, field: Dictionary, kind: String, expected_code: String) -> void:
	var executor := Par2Executor.new()
	_check(executor.setup(_config(1)), "%s executor setup" % kind)
	executor.set_test_fault_injection(kind, {"index": 0, "field": "shadow_fitness", "value": -777.0})
	var sim = LS33.new()
	_check(sim.setup(patch, field, FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, 32), "%s sim initializes" % kind)
	_check(sim.set_recruitment_executor(executor), "%s executor injected" % kind)
	var snapshot := sim.step_generation()
	_check(snapshot.is_empty(), "%s generation FAILS CLOSED (no commit)" % kind)
	_check(int(sim.generation) == 0, "%s generation counter unchanged" % kind)
	var meta: Dictionary = sim.get_last_profile()
	_check(String(meta.get("failure_code", "")) == expected_code, "%s named failure code %s (got %s)" % [kind, expected_code, String(meta.get("failure_code", ""))])
	executor.shutdown()

func _perf_gate(patch: Dictionary, field: Dictionary) -> void:
	## R2: fresh-checkout reproducible apples-to-apples performance gate.
	## Compare PAR1 direct PROCESS_POOL and PAR2 wrapper on the exact SAME
	## captured candidate/route/context fixture. No dependency on untracked
	## artifacts and no interpolation from post-recruitment population size.
	const PERF_WARMUPS := 2
	const PERF_MEASURED := 7
	var fixture = LS33.new()
	_check(fixture.setup(patch, field, FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, 256), "perf fixture initializes")
	var fixture_snapshot := fixture.step_generation()
	if fixture_snapshot.is_empty():
		_check(false, "perf fixture generation completes")
		return
	var candidates: Array = fixture_snapshot.get("last_candidates", [])
	var routes: Array = fixture_snapshot.get("last_routes", [])
	_check(not candidates.is_empty() and candidates.size() == routes.size(), "perf fixture captures exact candidate/route batch")
	if candidates.is_empty() or candidates.size() != routes.size():
		return
	var context := Kernel.build_context(
		String(fixture.SCHEMA), String(fixture.VERSION), String(fixture.REVISION),
		int(fixture.environment_seed), String(fixture.environment_field_hash),
		fixture.environment_cells)

	var direct := ProcessBackend.new()
	_check(direct.setup({
		"worker_count": 4,
		"godot_bin": _godot_bin,
		"project_root": _project_root,
		"session_root": _session_root,
		"job_timeout_ms": 240_000,
	}), "PAR1 direct perf backend setup")
	var wrapped := Par2Executor.new()
	var wrapped_config := _config(4)
	wrapped_config["audit_interval"] = 1_000_000
	wrapped_config["audit_generation_1"] = false
	_check(wrapped.setup(wrapped_config), "PAR2 same-input perf executor setup")

	var direct_samples: Array[float] = []
	var wrapped_samples: Array[float] = []
	for iteration in PERF_WARMUPS + PERF_MEASURED:
		var direct_started := Time.get_ticks_usec()
		var direct_result: Dictionary = direct.evaluate_generation(2, candidates, routes, context)
		var direct_ms := float(Time.get_ticks_usec() - direct_started) / 1000.0
		var wrapped_started := Time.get_ticks_usec()
		var wrapped_result: Dictionary = wrapped.evaluate_generation(2, candidates, routes, context)
		var wrapped_ms := float(Time.get_ticks_usec() - wrapped_started) / 1000.0
		if not bool(direct_result.get("success", false)):
			_check(false, "PAR1 direct same-input perf evaluation succeeds")
			break
		if not bool(wrapped_result.get("success", false)):
			_check(false, "PAR2 same-input perf evaluation succeeds")
			break
		var direct_events: Array = direct_result.get("canonical_events", [])
		var wrapped_events: Array = wrapped_result.get("canonical_events", [])
		_check(
			String(direct_result.get("canonical_hash", "")) == String(wrapped_result.get("canonical_recruitment_hash", ""))
			and Contract.events_exact(direct_events, wrapped_events),
			"PAR1 direct and PAR2 wrapper remain exact on same perf fixture")
		if iteration >= PERF_WARMUPS:
			direct_samples.append(direct_ms)
			wrapped_samples.append(wrapped_ms)

	direct.shutdown()
	wrapped.shutdown()
	if direct_samples.size() != PERF_MEASURED or wrapped_samples.size() != PERF_MEASURED:
		_check(false, "perf gate collected all measured samples")
		return
	var direct_p50 := _p50(direct_samples)
	var wrapped_p50 := _p50(wrapped_samples)
	print("PAR2 same-input perf gate: candidates=%d direct_p50=%.1fms wrapped_p50=%.1fms" % [
		candidates.size(), direct_p50, wrapped_p50])
	_check(
		wrapped_p50 <= direct_p50 * 1.05,
		"PAR2 wrapper p50 not >5%% above PAR1 direct on identical batch (%.1f vs %.1f)" % [wrapped_p50, direct_p50])

func _p50(values: Array) -> float:
	var sorted_values: Array = values.duplicate()
	sorted_values.sort()
	return float(sorted_values[sorted_values.size() / 2])

func _hash_row(snapshot: Dictionary) -> Dictionary:
	return {
		"candidate_pool_hash": snapshot.get("candidate_pool_hash", ""),
		"dispersal_pool_hash": snapshot.get("dispersal_pool_hash", ""),
		"recruitment_hash": snapshot.get("recruitment_hash", ""),
		"occupied_map_hash": snapshot.get("occupied_map_hash", ""),
		"hereditary_pool_hash": snapshot.get("hereditary_pool_hash", ""),
		"population_hash": snapshot.get("population_hash", ""),
		"state_hash": snapshot.get("state_hash", ""),
	}

func _rows_equal(a: Dictionary, b: Dictionary) -> bool:
	for field in a.keys():
		if String(a[field]) != String(b.get(field, "\u0001")):
			return false
	return true

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
		push_error("PAR2 CHECK FAIL: " + label)

func _finish() -> void:
	print("PAR2 exact generation comparisons: %d" % exact_comparisons)
	if failures.is_empty():
		print("ECO.EVO7 PAR2 Parallel-Only Recruitment: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		print("PAR2 FAIL: " + failure)
	print("ECO.EVO7 PAR2 Parallel-Only Recruitment: FAIL (%d/%d assertions failed)" % [failures.size(), assertions])
	quit(1)
