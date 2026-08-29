extends SceneTree

## ECO.EVO7 PAR1 — direct parallel backend benchmark (v1).
##
## Fair comparison of two DIRECT parallel recruitment backends (no serial
## oracle inside either backend) against a pure serial reference, on
## deterministic LS3.3-derived fixtures:
##
##   fixtures  : initial parent counts 64/256/512/1024/2048 (LS3.3 setup,
##               one generation, captured immutable candidates/routes/context;
##               fixture build time is NOT part of any measured timing)
##   backends  : SERIAL (kernel loop), PROCESS_POOL, WORKER_THREAD_POOL
##   workers   : 1/2/4/8 for parallel backends
##   iterations: 2 warmups + 7 measured per cell
##   stats     : p50/p95/min/max per stage (schedule/serialize, compute/ipc,
##               merge, total recruitment wall time) + speedups
##
## Exact parity is enforced on EVERY measured iteration (canonical hash and
## event equality vs the serial reference). Any mismatch fails the run.
##
## Output: artifacts/par1_backend_benchmark.json + PAR1_BENCHMARK_SUMMARY.

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const PlanetPatch = preload("res://scripts/ecology/shadow/eco_evo7_ls30_planet_patch_v1.gd")
const EnvironmentField = preload("res://scripts/ecology/shadow/eco_evo7_ls31_environment_field_v1.gd")
const LS33 = preload("res://scripts/ecology/shadow/eco_evo7_ls33_dispersal_recruitment_v1.gd")
const Kernel = preload("res://scripts/ecology/perf/eco_evo7_par0_recruitment_kernel_v1.gd")
const Contract = preload("res://scripts/ecology/perf/eco_evo7_par1_recruitment_backend_contract_v1.gd")
const ProcessBackend = preload("res://scripts/ecology/perf/eco_evo7_par1_process_recruitment_backend_v1.gd")
const WorkerThreadBackend = preload("res://scripts/ecology/perf/eco_evo7_par1_worker_thread_recruitment_backend_v1.gd")

const FOUNDER_SEED := 20260832
const PLACEMENT_SEED := 320032
const EVOLUTION_SEED := 330033
const ENV_SEED := 20260831
const RECIPE := "MIXED_PHYSICAL_HETEROGENEITY"
const PARENT_COUNTS := [64, 256, 512, 1024, 2048]
const WORKER_COUNTS := [1, 2, 4, 8]
const WARMUPS := 2
const MEASURED := 7
const LARGE_FIXTURES := [512, 1024, 2048]

func _init() -> void:
	var project_root := ProjectSettings.globalize_path("res://")
	var godot_bin := OS.get_environment("GODOT_BIN")
	if godot_bin.is_empty():
		godot_bin = "C:/Godot/godot/bin/godot.windows.editor.double.x86_64.console.exe"
	var session_root := OS.get_environment("ECO_PAR0_SESSION_ROOT")
	if session_root.is_empty():
		session_root = project_root.path_join("artifacts/par0_sessions")

	var world = EarthWorld.new()
	root.add_child(world)
	if not world.setup(null):
		print("ECO.EVO7 PAR1 Benchmark: FAIL (Earth setup failed)")
		quit(1)
		return
	var patch := PlanetPatch.new().build(world, Vector3(-0.5, -0.86602540378444, 0.0).normalized(), 32, 16.0)
	var field := EnvironmentField.new().generate(patch, RECIPE, ENV_SEED)
	if patch.is_empty() or field.is_empty():
		print("ECO.EVO7 PAR1 Benchmark: FAIL (patch/field build failed)")
		quit(1)
		return

	var fixtures: Array[Dictionary] = []
	for parent_count in PARENT_COUNTS:
		var fixture := _build_fixture(patch, field, int(parent_count))
		if fixture.is_empty():
			print("ECO.EVO7 PAR1 Benchmark: FAIL (fixture %d build failed)" % parent_count)
			quit(1)
			return
		fixtures.append(fixture)

	var failures: Array[String] = []
	var rows: Array[Dictionary] = []
	var process_backends := {}  # worker_count -> backend (persistent pool per wc)

	for fixture in fixtures:
		var parent_count := int(fixture["parent_count"])
		var items: Array = fixture["items"]
		var context: Dictionary = fixture["context"]
		var serial_events: Array[Dictionary] = fixture["serial_events"]
		var serial_hash := String(fixture["serial_hash"])

		## SERIAL reference (once per fixture, warmups + measured).
		var serial_samples: Array[float] = []
		for iteration in WARMUPS + MEASURED:
			var started := Time.get_ticks_usec()
			var events := Contract.serial_evaluate(items, context)
			var total_ms := float(Time.get_ticks_usec() - started) / 1000.0
			if events.is_empty() or Contract.recruitment_hash(events, context) != serial_hash:
				failures.append("serial fixture %d diverged" % parent_count)
				break
			if iteration >= WARMUPS:
				serial_samples.append(total_ms)
		if serial_samples.size() == MEASURED:
			rows.append(_row(parent_count, "SERIAL", 0, serial_samples, {}, items.size(), true))

		## WORKER_THREAD_POOL.
		for worker_count in WORKER_COUNTS:
			var backend := WorkerThreadBackend.new()
			if not backend.setup({"worker_count": worker_count}):
				failures.append("WTP wc=%d setup failed" % worker_count)
				continue
			var samples: Array[Dictionary] = []
			var exact := _measure_backend(backend, fixture, serial_hash, samples)
			backend.shutdown()
			if not exact.ok:
				failures.append("WTP fixture %d wc=%d: %s" % [parent_count, worker_count, exact.detail])
				continue
			rows.append(_row(parent_count, "WORKER_THREAD_POOL", worker_count,
				_stage_totals(samples), _stage_stats(samples), items.size(), true))

		## PROCESS_POOL (persistent pool per worker_count across fixtures).
		for worker_count in WORKER_COUNTS:
			if not process_backends.has(worker_count):
				var backend := ProcessBackend.new()
				if not backend.setup({
					"worker_count": worker_count,
					"godot_bin": godot_bin,
					"project_root": project_root,
					"session_root": session_root,
					"job_timeout_ms": 240_000,
				}):
					failures.append("process wc=%d setup failed" % worker_count)
					continue
				process_backends[worker_count] = backend
			var backend: Object = process_backends[worker_count]
			var samples: Array[Dictionary] = []
			var exact := _measure_backend(backend, fixture, serial_hash, samples)
			if not exact.ok:
				failures.append("PROCESS fixture %d wc=%d: %s" % [parent_count, worker_count, exact.detail])
				continue
			rows.append(_row(parent_count, "PROCESS_POOL", worker_count,
				_stage_totals(samples), _stage_stats(samples), items.size(), true))

	for worker_count in process_backends.keys():
		(process_backends[worker_count] as Object).call("shutdown")

	world.queue_free()

	var summary := {
		"schema": "distributed_world_simulator.ecology.evo7_par1.backend_benchmark.v1",
		"cpu": OS.get_processor_name(),
		"logical_processors": OS.get_processor_count(),
		"godot_version": Engine.get_version_info().get("string", ""),
		"recipe": RECIPE,
		"warmups": WARMUPS,
		"measured": MEASURED,
		"parent_counts": PARENT_COUNTS,
		"worker_counts": WORKER_COUNTS,
		"rows": rows,
		"failures": failures,
		"selection": _selection(rows),
	}
	var file := FileAccess.open(project_root.path_join("artifacts/par1_backend_benchmark.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(summary, "  "))
		file.close()
	print("PAR1_BENCHMARK_SUMMARY " + JSON.stringify(_compact(summary)))
	if failures.is_empty():
		print("ECO.EVO7 PAR1 Backend Benchmark: PASS")
		quit(0)
		return
	for failure in failures:
		push_error("PAR1 BENCHMARK FAIL: " + failure)
	print("ECO.EVO7 PAR1 Backend Benchmark: FAIL (%d failures)" % failures.size())
	quit(1)

## ---------- fixtures ----------

func _build_fixture(patch: Dictionary, field: Dictionary, parent_count: int) -> Dictionary:
	## Fixture build only — NOT part of measured timings.
	var sim = LS33.new()
	if not sim.setup(patch, field, FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, parent_count):
		return {}
	var snapshot := sim.step_generation()
	if snapshot.is_empty():
		return {}
	var candidates: Array = snapshot.get("last_candidates", [])
	var routes: Array = snapshot.get("last_routes", [])
	if candidates.is_empty() or candidates.size() != routes.size():
		return {}
	var context := Kernel.build_context(
		String(sim.SCHEMA), String(sim.VERSION), String(sim.REVISION),
		int(sim.environment_seed), String(sim.environment_field_hash),
		sim.environment_cells)
	var items: Array = Contract.canonical_items(candidates, routes)
	if items.size() != candidates.size():
		return {}
	var serial_events := Contract.serial_evaluate(items, context)
	if serial_events.is_empty():
		return {}
	return {
		"parent_count": parent_count,
		"items": items,
		"context": context,
		"serial_events": serial_events,
		"serial_hash": Contract.recruitment_hash(serial_events, context),
	}

## ---------- measurement ----------

func _measure_backend(backend: Object, fixture: Dictionary, serial_hash: String, samples: Array[Dictionary]) -> Dictionary:
	var items: Array = fixture["items"]
	var context: Dictionary = fixture["context"]
	var serial_events: Array[Dictionary] = fixture["serial_events"]
	var candidates: Array[Dictionary] = []
	var routes: Array[Dictionary] = []
	for item_value in items:
		var item: Dictionary = item_value
		candidates.append(item["candidate"])
		routes.append(item["route"])
	for iteration in WARMUPS + MEASURED:
		var result: Dictionary = backend.call("evaluate_generation", 1, candidates, routes, context)
		if not bool(result.get("success", false)):
			return {"ok": false, "detail": "backend failure %s" % String(result.get("failure_code", ""))}
		var events: Array = result.get("canonical_events", [])
		if String(result.get("canonical_hash", "")) != serial_hash or not Contract.events_exact(serial_events, events):
			return {"ok": false, "detail": "canonical divergence vs serial reference"}
		if iteration >= WARMUPS:
			var timings: Dictionary = result.get("timings_ms", {})
			samples.append({
				"total_ms": float(timings.get("total_ms", 0.0)),
				"stage_a_ms": float(timings.get("schedule_ms", timings.get("serialize_ms", 0.0))),
				"stage_b_ms": float(timings.get("compute_ms", timings.get("ipc_ms", 0.0))),
				"merge_ms": float(timings.get("merge_ms", 0.0)),
			})
	return {"ok": true, "detail": ""}

## ---------- stats ----------

func _stage_totals(samples: Array[Dictionary]) -> Array[float]:
	var out: Array[float] = []
	for sample in samples:
		out.append(float(sample["total_ms"]))
	return out

func _stage_stats(samples: Array[Dictionary]) -> Dictionary:
	return {
		"stage_a_ms": _stats(samples.map(func(s): return float(s["stage_a_ms"]))),
		"stage_b_ms": _stats(samples.map(func(s): return float(s["stage_b_ms"]))),
		"merge_ms": _stats(samples.map(func(s): return float(s["merge_ms"]))),
	}

func _row(parent_count: int, backend: String, worker_count: int, totals: Array[float], stages: Dictionary, candidate_count: int, exact: bool) -> Dictionary:
	return {
		"parent_count": parent_count,
		"backend": backend,
		"worker_count": worker_count,
		"candidates": candidate_count,
		"total_ms": _stats(totals),
		"stages": stages,
		"exact_parity": exact,
	}

func _stats(values: Array) -> Dictionary:
	if values.is_empty():
		return {"p50": 0.0, "p95": 0.0, "min": 0.0, "max": 0.0}
	var sorted_values: Array = values.duplicate()
	sorted_values.sort()
	return {
		"p50": _percentile(sorted_values, 0.50),
		"p95": _percentile(sorted_values, 0.95),
		"min": float(sorted_values[0]),
		"max": float(sorted_values[sorted_values.size() - 1]),
	}

func _percentile(sorted_values: Array, q: float) -> float:
	var index := int(ceil(q * sorted_values.size())) - 1
	index = clampi(index, 0, sorted_values.size() - 1)
	return float(sorted_values[index])

## ---------- selection policy (PAR1 section 12) ----------

func _selection(rows: Array[Dictionary]) -> Dictionary:
	## Geometric-mean total recruitment wall time over the large fixtures
	## (512/1024/2048), best worker count per backend; p95 guard.
	var p50_by_backend := {"PROCESS_POOL": {}, "WORKER_THREAD_POOL": {}}
	var p95_by_backend := {"PROCESS_POOL": {}, "WORKER_THREAD_POOL": {}}
	for row in rows:
		if not LARGE_FIXTURES.has(int(row["parent_count"])):
			continue
		var backend := String(row["backend"])
		if not p50_by_backend.has(backend):
			continue
		var wc := int(row["worker_count"])
		p50_by_backend[backend][wc] = float(row["total_ms"]["p50"])
		p95_by_backend[backend][wc] = float(row["total_ms"]["p95"])
	var best := {}
	for backend in p50_by_backend.keys():
		var best_wc := -1
		var best_mean := -1.0
		for wc in p50_by_backend[backend].keys():
			## Best wc = lowest mean p50 across the large fixtures.
			var mean_p50 := 0.0
			var have := 0
			for row in rows:
				if String(row["backend"]) == backend and int(row["worker_count"]) == wc and LARGE_FIXTURES.has(int(row["parent_count"])):
					mean_p50 += float(row["total_ms"]["p50"])
					have += 1
			if have == LARGE_FIXTURES.size():
				mean_p50 /= have
				if best_wc < 0 or mean_p50 < best_mean:
					best_wc = wc
					best_mean = mean_p50
		if best_wc >= 0:
			best[backend] = {"worker_count": best_wc, "mean_p50_large": best_mean,
				"p95_large_worst": p95_by_backend[backend][best_wc]}
	var out := {
		"policy": "geomean>=15% faster on 512/1024/2048 wins; within 15% prefer WORKER_THREAD_POOL if thread-safe and stable",
		"candidates": best,
	}
	if best.has("PROCESS_POOL") and best.has("WORKER_THREAD_POOL"):
		var process_p50 := float(best["PROCESS_POOL"]["mean_p50_large"])
		var wtp_p50 := float(best["WORKER_THREAD_POOL"]["mean_p50_large"])
		var advantage := (process_p50 - wtp_p50) / process_p50 if process_p50 > 0.0 else 0.0
		out["wtp_advantage_vs_process"] = advantage
		if advantage >= 0.15:
			out["selected_backend"] = "WORKER_THREAD_POOL"
			out["reason"] = "WTP >=15%% faster in mean p50 on large fixtures (advantage %.1f%%)" % (advantage * 100.0)
		elif advantage <= -0.15:
			out["selected_backend"] = "PROCESS_POOL"
			out["reason"] = "PROCESS_POOL >=15%% faster in mean p50 on large fixtures (advantage %.1f%%)" % (-advantage * 100.0)
		else:
			out["selected_backend"] = "WORKER_THREAD_POOL"
			out["reason"] = "within 15%% on large fixtures (advantage %.1f%%); tie-break prefers WORKER_THREAD_POOL pending thread-safety/contention PASS" % (advantage * 100.0)
	elif best.has("WORKER_THREAD_POOL"):
		out["selected_backend"] = "WORKER_THREAD_POOL"
		out["reason"] = "only WORKER_THREAD_POOL has complete large-fixture measurements"
	elif best.has("PROCESS_POOL"):
		out["selected_backend"] = "PROCESS_POOL"
		out["reason"] = "only PROCESS_POOL has complete large-fixture measurements"
	return out

func _compact(summary: Dictionary) -> Dictionary:
	var rows: Array = []
	for row in summary["rows"]:
		rows.append({
			"parents": row["parent_count"], "backend": row["backend"],
			"wc": row["worker_count"], "candidates": row["candidates"],
			"p50": row["total_ms"]["p50"], "p95": row["total_ms"]["p95"],
			"exact": row["exact_parity"],
		})
	return {"rows": rows, "failures": summary["failures"], "selection": summary["selection"]}
