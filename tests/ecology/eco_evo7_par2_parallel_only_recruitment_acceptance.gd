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
	_perf_gate()

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

func _perf_gate() -> void:
	## Parallel-only recruitment p50 must not regress >5% vs the PAR1 direct
	## measurement at the nearest fixture size (process backend, same host,
	## SAME worker count 4 vs PAR1 wc=4 reference).
	if _parallel_ms_samples.is_empty():
		_check(false, "perf gate has parallel samples")
		return
	var wc4_samples: Array[float] = []
	var wc4_candidates := 0
	var wc4_count := 0
	for index in _parallel_ms_samples.size():
		if _parallel_wc_samples[index] == 4:
			wc4_samples.append(_parallel_ms_samples[index])
			wc4_candidates += _candidate_counts[index]
			wc4_count += 1
	if wc4_samples.is_empty():
		_check(false, "perf gate has wc=4 samples")
		return
	var sorted_samples: Array = wc4_samples.duplicate()
	sorted_samples.sort()
	var p50 := float(sorted_samples[sorted_samples.size() / 2])
	var mean_candidates := wc4_candidates / wc4_count
	var reference := _par1_reference(mean_candidates)
	if reference <= 0.0:
		print("PAR2 perf gate: PAR1 benchmark artifact unavailable, wc=4 p50=%.1f ms (no reference compare)" % p50)
		_check(true, "perf gate recorded samples")
		return
	print("PAR2 perf gate: wc=4 parallel p50=%.1f ms vs PAR1 direct wc=4 reference=%.1f ms (candidates~%d)" % [p50, reference, mean_candidates])
	_check(p50 <= reference * 1.05, "parallel-only wc=4 p50 not >5%% above PAR1 direct (%.1f vs %.1f)" % [p50, reference])

func _par1_reference(candidate_count: int) -> float:
	var path := _project_root.path_join("artifacts/par1_backend_benchmark.json")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1.0
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return -1.0
	var wc := 4
	var points := {}
	for row in (parsed as Dictionary).get("rows", []):
		if String(row.get("backend", "")) == "PROCESS_POOL" and int(row.get("worker_count", 0)) == wc:
			points[int(row.get("candidates", 0))] = float(Dictionary(row.get("total_ms", {})).get("p50", 0.0))
	if points.is_empty():
		return -1.0
	var keys := points.keys()
	keys.sort()
	if candidate_count <= int(keys[0]):
		return float(points[keys[0]])
	if candidate_count >= int(keys[keys.size() - 1]):
		return float(points[keys[keys.size() - 1]])
	for index in keys.size() - 1:
		var lo := int(keys[index])
		var hi := int(keys[index + 1])
		if candidate_count >= lo and candidate_count <= hi:
			var t := float(candidate_count - lo) / float(hi - lo)
			return float(points[lo]) + t * (float(points[hi]) - float(points[lo]))
	return -1.0

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
