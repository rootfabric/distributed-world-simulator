extends SceneTree

## ECO.EVO7 PAR3 — parallel deterministic candidate reproduction acceptance.
##
## Gate matrix:
##   A. end-to-end exact parity: 3 recipes x wc 1/2/4 x 12 generations with
##      the PAR3 candidate executor injected (recruitment stays serial) vs a
##      pure serial baseline — ALL canonical hashes exact, >=108 comparisons;
##   B. long campaign audit fraction: deterministic schedule, elision >=80%;
##   C. kernel identity: serial LS3.3 candidates are byte-identical to the
##      shared kernel output (single implementation proof);
##   D. fail-closed fault injections: backend failure / parallel corruption /
##      audit mismatch -> no generation commit, named PAR3 codes;
##   E. performance gate: candidate build serial vs parallel at parent
##      fixtures 64/256/512/1024/2048 (2 warmup + 7 measured);
##      at >=1024 parents parallel p50 must improve >=20%;
##      full generation p50 must not regress >5%.

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const PlanetPatch = preload("res://scripts/ecology/shadow/eco_evo7_ls30_planet_patch_v1.gd")
const EnvironmentField = preload("res://scripts/ecology/shadow/eco_evo7_ls31_environment_field_v1.gd")
const LS33 = preload("res://scripts/ecology/shadow/eco_evo7_ls33_dispersal_recruitment_v1.gd")
const Kernel = preload("res://scripts/ecology/perf/eco_evo7_par3_candidate_kernel_v1.gd")
const Executor = preload("res://scripts/ecology/perf/eco_evo7_par3_candidate_build_executor_v1.gd")

const RECIPES := ["MIXED_PHYSICAL_HETEROGENEITY", "WATER_GRADIENT_STRONG", "RELIEF_DRAINAGE_STRONG"]
const WORKER_COUNTS := [1, 2, 4]
const GENERATIONS := 12
const LONG_CAMPAIGN := 50
const PERF_PARENT_COUNTS := [64, 256, 512, 1024, 2048]
const WARMUPS := 2
const MEASURED := 7
const FOUNDER_SEED := 20260832
const PLACEMENT_SEED := 320032
const EVOLUTION_SEED := 330033
const ENV_SEED := 20260831

var assertions := 0
var failures: Array[String] = []
var exact_comparisons := 0
var _project_root := ""
var _godot_bin := ""
var _session_root := ""

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

	## ---------------- C. kernel identity -------------------------------
	var identity_sim = LS33.new()
	_check(identity_sim.setup(patch, fields[RECIPES[0]], FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, 64), "identity sim initializes")
	## Kernel output over the FOUNDER records (parents of generation 1).
	var kernel_candidates := Kernel.build_all(identity_sim.records, 1, String(identity_sim.SCHEMA), String(identity_sim.VERSION), int(identity_sim.evolution_seed), int(identity_sim.OFFSPRING_PER_PARENT))
	_check(not kernel_candidates.is_empty(), "kernel builds candidates from founders")
	var identity_snapshot := identity_sim.step_generation()
	_check(not identity_snapshot.is_empty(), "identity generation one completes")
	var serial_candidates: Array = identity_snapshot.get("last_candidates", [])
	_check(kernel_candidates.size() == serial_candidates.size(), "kernel reproduces candidate count")
	var identity_exact := true
	if kernel_candidates.size() == serial_candidates.size():
		for index in kernel_candidates.size():
			if String(kernel_candidates[index].get("candidate_hash", "")) != String(serial_candidates[index].get("candidate_hash", "")) or kernel_candidates[index] != serial_candidates[index]:
				identity_exact = false
				break
	_check(identity_exact, "serial LS3.3 candidates byte-identical to shared kernel output (ONE implementation)")

	## ---------------- C2. empty-slice legality --------------------------
	## wc=8 with parent_count 1..7 necessarily creates empty canonical slices.
	## Those workers must return valid zero-result responses, not fail closed.
	for small_parent_count in range(1, 8):
		var small_sim = LS33.new()
		_check(small_sim.setup(patch, fields[RECIPES[0]], FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, small_parent_count),
			"small-parent fixture %d initializes" % small_parent_count)
		var small_executor := Executor.new()
		_check(small_executor.setup(_config(8)), "small-parent wc=8 executor setup (%d)" % small_parent_count)
		var small_parallel: Dictionary = small_executor.build_candidates(small_sim.records, 1)
		_check(bool(small_parallel.get("success", false)),
			"empty worker slices are legal for parents=%d wc=8" % small_parent_count)
		var small_serial := Kernel.build_all(
			small_sim.records, 1, String(LS33.SCHEMA), String(LS33.VERSION),
			EVOLUTION_SEED, int(LS33.OFFSPRING_PER_PARENT))
		var small_candidates: Array = small_parallel.get("candidates", [])
		_check(small_candidates.size() == small_parent_count * int(LS33.OFFSPRING_PER_PARENT),
			"small-parent candidate count exact (%d)" % small_parent_count)
		_check(
			String(small_parallel.get("candidate_pool_hash", "")) == Kernel.candidate_pool_hash(small_serial, String(LS33.SCHEMA), String(LS33.VERSION))
			and small_candidates == small_serial,
			"small-parent parallel candidates byte-exact vs serial (%d)" % small_parent_count)
		small_executor.shutdown()

	## ---------------- A. end-to-end exact parity ------------------------
	var perf_rows: Array[Dictionary] = []
	for recipe in RECIPES:
		var baseline := _serial_baseline(patch, fields[recipe], GENERATIONS)
		if baseline.is_empty():
			_check(false, "%s serial baseline completed" % recipe)
			continue
		for worker_count in WORKER_COUNTS:
			var executor := Executor.new()
			_check(executor.setup(_config(worker_count)), "%s wc=%d executor setup" % [recipe, worker_count])
			var sim = LS33.new()
			_check(sim.setup(patch, fields[recipe], FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, 64), "%s wc=%d parallel sim initializes" % [recipe, worker_count])
			_check(sim.set_candidate_executor(executor), "candidate executor injected (%s wc=%d)" % [recipe, worker_count])
			_check(sim.has_candidate_executor(), "LS3.3 reports candidate executor")
			var mismatch := ""
			for step in GENERATIONS:
				var snapshot := sim.step_generation()
				if snapshot.is_empty():
					mismatch = "generation %d failed (fail-closed or extinction)" % (step + 1)
					break
				if not _rows_equal(_hash_row(snapshot), baseline[step]):
					mismatch = "generation %d canonical hash divergence vs serial baseline" % (step + 1)
					break
				exact_comparisons += 1
			if mismatch.is_empty():
				var telemetry: Dictionary = executor.get_telemetry()
				_check(int(telemetry["parallel_calls"]) == GENERATIONS, "%s wc=%d every generation built candidates in parallel" % [recipe, worker_count])
				_check(int(telemetry["serial_audit_calls"]) == 2, "%s wc=%d candidate audits = gen1 + gen10 (got %d)" % [recipe, worker_count, int(telemetry["serial_audit_calls"])])
			else:
				_check(false, "%s wc=%d %s" % [recipe, worker_count, mismatch])
			executor.shutdown()
	_check(exact_comparisons >= 108, "end-to-end exact comparisons >=108 (got %d)" % exact_comparisons)

	## ---------------- B. long campaign audit fraction -------------------
	var long_executor := Executor.new()
	_check(long_executor.setup(_config(4)), "long-campaign executor setup")
	var long_sim = LS33.new()
	_check(long_sim.setup(patch, fields[RECIPES[0]], FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, 64), "long-campaign sim initializes")
	_check(long_sim.set_candidate_executor(long_executor), "long-campaign executor injected")
	var completed := 0
	for step in LONG_CAMPAIGN:
		if long_sim.step_generation().is_empty():
			break
		completed += 1
	var telemetry: Dictionary = long_executor.get_telemetry()
	_check(completed >= 30, "long campaign survived enough generations (%d)" % completed)
	var expected_audits := 1 + (completed / 10)
	_check(int(telemetry["serial_audit_calls"]) == expected_audits, "candidate audit count matches schedule (got %d expected %d)" % [int(telemetry["serial_audit_calls"]), expected_audits])
	_check(bool(telemetry["last_audit_pass"]), "last candidate audit passed")
	var elision := float(telemetry["oracle_elided_generations"]) / float(maxi(1, completed))
	_check(elision >= 0.80, "candidate oracle elision >=80%% (got %.1f%%)" % (elision * 100.0))
	long_executor.shutdown()
	print("PAR3 long campaign: gens=%d audits=%d elision=%.1f%%" % [completed, int(telemetry["serial_audit_calls"]), elision * 100.0])

	## ---------------- D. fail-closed fault injections ------------------
	_forced_failure(patch, fields[RECIPES[0]], "FORCE_BACKEND_FAILURE", "PAR3_BACKEND_FAILURE")
	_forced_failure(patch, fields[RECIPES[0]], "FORCE_AUDIT_MISMATCH", "PAR3_AUDIT_PARITY_FAILURE")
	_forced_failure(patch, fields[RECIPES[0]], "FORCE_PARALLEL_CORRUPTION", "PAR3_AUDIT_PARITY_FAILURE")

	## ---------------- E. performance gate ------------------------------
	_perf_gate(patch, fields[RECIPES[0]])

	world.queue_free()
	_finish()

func _config(worker_count: int) -> Dictionary:
	return {
		"worker_count": worker_count,
		"ls33_schema": String(LS33.SCHEMA),
		"ls33_version": String(LS33.VERSION),
		"evolution_seed": EVOLUTION_SEED,
		"offspring_per_parent": int(LS33.OFFSPRING_PER_PARENT),
		"godot_bin": _godot_bin,
		"project_root": _project_root,
		"session_root": _session_root,
		"job_timeout_ms": 240_000,
		"audit_interval": 10,
		"audit_generation_1": true,
	}

func _serial_baseline(patch: Dictionary, field: Dictionary, generations: int) -> Array[Dictionary]:
	var sim = LS33.new()
	if not sim.setup(patch, field, FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, 64):
		return []
	var rows: Array[Dictionary] = []
	for step in generations:
		var snapshot := sim.step_generation()
		if snapshot.is_empty():
			return []
		rows.append(_hash_row(snapshot))
	return rows

func _forced_failure(patch: Dictionary, field: Dictionary, kind: String, expected_code: String) -> void:
	var executor := Executor.new()
	_check(executor.setup(_config(1)), "%s executor setup" % kind)
	executor.set_test_fault_injection(kind, {"index": 0, "field": "mutation_seed", "value": -777})
	var sim = LS33.new()
	_check(sim.setup(patch, field, FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, 32), "%s sim initializes" % kind)
	_check(sim.set_candidate_executor(executor), "%s executor injected" % kind)
	var snapshot := sim.step_generation()
	_check(snapshot.is_empty(), "%s generation FAILS CLOSED (no commit)" % kind)
	_check(int(sim.generation) == 0, "%s generation counter unchanged" % kind)
	var meta: Dictionary = sim.get_last_profile()
	_check(String(meta.get("failure_code", "")) == expected_code, "%s named failure code %s (got %s)" % [kind, expected_code, String(meta.get("failure_code", ""))])
	executor.shutdown()

func _perf_gate(patch: Dictionary, field: Dictionary) -> void:
	## Serial vs parallel candidate build on the same parent fixtures;
	## full-generation effect at the largest fixture.
	var perf_executor := Executor.new()
	_check(perf_executor.setup(_config(8)), "perf executor setup (wc=8)")
	var fixture_report: Array[Dictionary] = []
	for parent_count in PERF_PARENT_COUNTS:
		var sim = LS33.new()
		if not sim.setup(patch, field, FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, int(parent_count)):
			_check(false, "perf fixture %d initializes" % parent_count)
			continue
		var parents: Array = sim.records.duplicate(true)
		var serial_samples: Array[float] = []
		var parallel_samples: Array[float] = []
		for iteration in WARMUPS + MEASURED:
			var s0 := Time.get_ticks_usec()
			var serial_built := Kernel.build_all(parents, 1, String(LS33.SCHEMA), String(LS33.VERSION), EVOLUTION_SEED, int(LS33.OFFSPRING_PER_PARENT))
			var serial_ms := float(Time.get_ticks_usec() - s0) / 1000.0
			if serial_built.is_empty():
				_check(false, "perf fixture %d serial build" % parent_count)
				return
			var par_result: Dictionary = perf_executor.build_candidates(parents, 1)
			if not bool(par_result.get("success", false)):
				_check(false, "perf fixture %d parallel build (%s)" % [parent_count, String(par_result.get("failure_detail", ""))])
				return
			var parallel_ms := float(Dictionary(par_result.get("report", {})).get("timings_ms", {}).get("parallel_ms", 0.0))
			if iteration >= WARMUPS:
				serial_samples.append(serial_ms)
				parallel_samples.append(parallel_ms)
			if parent_count == 64 and iteration == 0:
				var parallel_pool_hash := String(par_result.get("candidate_pool_hash", ""))
				var serial_pool_hash := Kernel.candidate_pool_hash(serial_built, String(LS33.SCHEMA), String(LS33.VERSION))
				_check(parallel_pool_hash == serial_pool_hash, "perf fixture candidate_pool_hash exact (parallel == serial)")
		var row := {
			"parents": int(parent_count),
			"serial_p50": _p50(serial_samples),
			"parallel_p50": _p50(parallel_samples),
		}
		row["speedup"] = float(row["serial_p50"]) / maxf(0.001, float(row["parallel_p50"]))
		fixture_report.append(row)
		print("PAR3 perf fixture parents=%d serial_p50=%.1fms parallel_p50=%.1fms speedup=%.2fx" % [row["parents"], row["serial_p50"], row["parallel_p50"], row["speedup"]])

	## Activation gate: >=20% improvement (speedup >= 1.25 implied by >=20%
	## p50 reduction) at parent count >=1024.
	for row in fixture_report:
		if int(row["parents"]) >= 1024:
			var improvement := 1.0 - float(row["parallel_p50"]) / float(row["serial_p50"])
			_check(improvement >= 0.20, "parallel candidate build >=20%% faster at parents=%d (improvement %.1f%%)" % [int(row["parents"]), improvement * 100.0])
	## Full generation effect at the largest fixture: total_ms p50 must not
	## regress >5% (3 iterations each side, recruitment identical serial).
	## Measured on a NON-audit generation configuration: bounded serial audits
	## are a deliberate PAR3 cost on ~10% of generations, not part of the
	## steady-state production path being gated here.
	var full_gen_config := _config(4)
	full_gen_config["audit_interval"] = 1_000_000
	full_gen_config["audit_generation_1"] = false
	var full_gen_executor := Executor.new()
	_check(full_gen_executor.setup(full_gen_config), "full-gen executor setup (no-audit)")
	var largest := int(PERF_PARENT_COUNTS[PERF_PARENT_COUNTS.size() - 1])
	var serial_gen: Array[float] = []
	var parallel_gen: Array[float] = []
	for iteration in 3:
		var plain_sim = LS33.new()
		if not plain_sim.setup(patch, field, FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, largest):
			_check(false, "full-gen serial sim initializes")
			break
		var t0 := Time.get_ticks_usec()
		var snap := plain_sim.step_generation()
		serial_gen.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		if snap.is_empty():
			_check(false, "full-gen serial step completes")
			break
	for iteration in 3:
		var par_sim = LS33.new()
		if not par_sim.setup(patch, field, FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, largest):
			_check(false, "full-gen parallel sim initializes")
			break
		if not par_sim.set_candidate_executor(full_gen_executor):
			_check(false, "full-gen executor injected")
			break
		var t1 := Time.get_ticks_usec()
		var snap2 := par_sim.step_generation()
		parallel_gen.append(float(Time.get_ticks_usec() - t1) / 1000.0)
		if snap2.is_empty():
			_check(false, "full-gen parallel step completes")
			break
	if serial_gen.size() == 3 and parallel_gen.size() == 3:
		var serial_p50 := _p50(serial_gen)
		var parallel_p50 := _p50(parallel_gen)
		print("PAR3 full generation parents=%d serial_p50=%.1fms parallel_p50=%.1fms" % [largest, serial_p50, parallel_p50])
		_check(parallel_p50 <= serial_p50 * 1.05, "full generation p50 not >5%% slower with parallel candidates (%.1f vs %.1f)" % [parallel_p50, serial_p50])
	full_gen_executor.shutdown()
	perf_executor.shutdown()
	var file := FileAccess.open(_project_root.path_join("artifacts/par3_candidate_perf.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({
			"schema": "distributed_world_simulator.ecology.evo7_par3.candidate_perf.v1",
			"fixtures": fixture_report,
		}, "  "))
		file.close()

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
		push_error("PAR3 CHECK FAIL: " + label)

func _finish() -> void:
	print("PAR3 exact generation comparisons: %d" % exact_comparisons)
	if failures.is_empty():
		print("ECO.EVO7 PAR3 Parallel Candidate Reproduction: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		print("PAR3 FAIL: " + failure)
	print("ECO.EVO7 PAR3 Parallel Candidate Reproduction: FAIL (%d/%d assertions failed)" % [failures.size(), assertions])
	quit(1)
