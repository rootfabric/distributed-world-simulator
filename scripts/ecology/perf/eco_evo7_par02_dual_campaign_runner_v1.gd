extends SceneTree

## ECO.EVO7 PERF1-PAR0.2 — single-combination dual campaign runner.
##
## One process executes EXACTLY ONE combination:
##   ECO_PAR02_MODE=serial : serial-only baseline   (no executor, no pool)
##   ECO_PAR02_MODE=dual   : dual canonical run     (one persistent pool)
##
## The dual run is the authority run: LS3.3 commits the VERIFIED PARALLEL
## recruitment result every generation. Evidence per generation:
##   - internal parity:  serial oracle == parallel pool (in-executor EXACT)
##   - external parity:  10 canonical downstream hashes equal the serial
##     baseline artifact row-for-row (ECO_PAR02_BASELINE_ARTIFACT)
##
## PAR0.2 IS NOT A SPEEDUP GATE: timings are recorded, never asserted.

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const Workbench = preload("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd")
const DualExecutor = preload("res://scripts/ecology/perf/eco_evo7_par02_dual_recruitment_executor_v1.gd")

const HASH_FIELDS: Array[String] = [
	"candidate_pool_hash", "dispersal_pool_hash", "recruitment_hash",
	"precompetition_population_hash", "competition_hash", "postcompetition_population_hash",
	"hereditary_pool_hash", "ecology_state_hash", "classification_hash", "workbench_hash",
]

func _init() -> void:
	var project_root := ProjectSettings.globalize_path("res://")
	var mode := _env("ECO_PAR02_MODE", "serial")
	var recipe := _env("ECO_PAR02_RECIPE", "MIXED_PHYSICAL_HETEROGENEITY")
	var generations := int(_env("ECO_PAR02_GENERATIONS", "12"))
	var worker_count := int(_env("ECO_PAR02_WORKERS", "2"))
	var artifact_path := _env("ECO_PAR02_ARTIFACT",
		project_root.path_join("artifacts/par02/%s_%s.json" % [mode, recipe.to_lower()]))
	var baseline_path := _env("ECO_PAR02_BASELINE_ARTIFACT", "")

	var world = EarthWorld.new()
	root.add_child(world)
	if not world.setup(null):
		_emit(artifact_path, _result(mode, recipe, worker_count, generations, ["earth setup failed"], [], {}, []))
		quit(1)
		return
	var workbench = Workbench.new()
	if not workbench.setup(world, {"environment_recipe": recipe}):
		_emit(artifact_path, _result(mode, recipe, worker_count, generations, ["workbench setup failed"], [], {}, []))
		quit(1)
		return

	var executor = null
	if mode == "dual":
		executor = DualExecutor.new()
		if not executor.setup({
			"worker_count": worker_count,
			"session_root": _env("ECO_PAR02_SESSION_ROOT",
				_env("ECO_PAR0_SESSION_ROOT", project_root.path_join("artifacts/par02_sessions"))),
			"evidence_dir": project_root.path_join("artifacts/par02/evidence"),
			"job_timeout_ms": int(_env("ECO_PAR02_JOB_TIMEOUT_MS", "180000")),
		}):
			_emit(artifact_path, _result(mode, recipe, worker_count, generations, ["executor setup failed"], [], {}, []))
			quit(1)
			return
		var ls33 = workbench.ecology.core
		if not ls33.set_recruitment_executor(executor):
			_emit(artifact_path, _result(mode, recipe, worker_count, generations, ["executor injection refused"], [], {}, []))
			quit(1)
			return

	var failures: Array[String] = []
	var rows: Array[Dictionary] = []
	var dual_rows: Array = []
	var timings: Array = []
	for step in generations:
		var total_started := Time.get_ticks_usec()
		var snapshot: Dictionary = workbench.advance_generations(1)
		if snapshot.is_empty():
			failures.append("generation %d failed (extinction, parity failure or validation)" % (step + 1))
			break
		var row := _hash_row(workbench, snapshot)
		rows.append(row)
		var generation_row := {"generation": int(row["generation"]), "hashes": row}
		if executor != null:
			var report: Dictionary = executor.get_last_report()
			generation_row["canonical_source"] = String(report.get("canonical_source", ""))
			generation_row["comparison_passed"] = bool(report.get("comparison_passed", false))
			generation_row["serial_hash"] = String(report.get("serial_hash", ""))
			generation_row["parallel_hash"] = String(report.get("parallel_hash", ""))
			generation_row["timings_ms"] = report.get("timings_ms", {}).duplicate(true)
			if String(report.get("canonical_source", "")) != "PARALLEL_VERIFIED":
				failures.append("generation %d canonical source %s != PARALLEL_VERIFIED" % [
					step + 1, String(report.get("canonical_source", ""))])
		generation_row["dual_total_ms"] = float(Time.get_ticks_usec() - total_started) / 1000.0
		dual_rows.append(generation_row)
		print("PAR02 %s %s wc=%d gen=%d OK" % [mode, recipe, worker_count, int(row["generation"])])

	## External baseline parity: dual canonical run vs serial baseline,
	## generation-by-generation over all 10 downstream hashes.
	var external_parity_rows: Array = []
	if mode == "dual":
		var baseline = _load_baseline(baseline_path)
		if baseline.is_empty():
			failures.append("baseline artifact missing or unreadable: %s" % baseline_path)
		else:
			var baseline_rows: Array = baseline.get("rows", [])
			if baseline_rows.size() != dual_rows.size():
				failures.append("baseline row count %d != dual row count %d" % [baseline_rows.size(), dual_rows.size()])
			for index in mini(baseline_rows.size(), dual_rows.size()):
				var parity := {"generation": int(dual_rows[index]["generation"]), "fields": {}}
				var parity_ok := true
				for field in HASH_FIELDS:
					var equal := String(baseline_rows[index].get(field, "")) == String(dual_rows[index]["hashes"].get(field, ""))
					parity["fields"][field] = equal
					parity_ok = parity_ok and equal
				parity["exact"] = parity_ok
				external_parity_rows.append(parity)
				if not parity_ok:
					failures.append("external parity generation %d diverged from serial baseline" % (index + 1))

	if executor != null:
		executor.shutdown()
	world.queue_free()

	## Lifetime counters are read AFTER shutdown so pool_shutdown_count is
	## final (exactly one pool lifecycle per dual coordinator process).
	var counters = executor.get_lifetime_counters() if executor != null else {
		"pool_setup_count": 0, "pool_shutdown_count": 0, "generation_jobs": 0, "worker_count": 0}
	if int(counters["pool_setup_count"]) != 1 and mode == "dual":
		failures.append("pool_setup_count %d != 1" % int(counters["pool_setup_count"]))
	if int(counters["pool_shutdown_count"]) != 1 and mode == "dual":
		failures.append("pool_shutdown_count %d != 1" % int(counters["pool_shutdown_count"]))
	if rows.size() != generations:
		failures.append("committed %d of %d generations" % [rows.size(), generations])

	var result := _result(mode, recipe, worker_count, generations, failures, rows, counters, dual_rows)
	result["external_parity"] = external_parity_rows
	result["base_sha"] = _env("ECO_PAR02_BASE_SHA", "")
	result["candidate_sha"] = _env("ECO_PAR02_CANDIDATE_SHA", "")
	_emit(artifact_path, result)
	if failures.is_empty():
		print("ECO.EVO7 PAR0.2 campaign run %s %s wc=%d: PASS" % [mode, recipe, worker_count])
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 PAR0.2 CAMPAIGN FAIL: " + failure)
	print("ECO.EVO7 PAR0.2 campaign run %s %s wc=%d: FAIL (%d failures)" % [mode, recipe, worker_count, failures.size()])
	quit(1)

## ---------- helpers ----------

func _result(mode: String, recipe: String, worker_count: int, generations: int, failures: Array, rows: Array, counters, dual_rows: Array) -> Dictionary:
	return {
		"schema": "distributed_world_simulator.ecology.evo7_par02.campaign_run.v1",
		"mode": "DUAL_VERIFY" if mode == "dual" else "SERIAL",
		"recipe": recipe,
		"worker_count": worker_count if mode == "dual" else 0,
		"generation_count": generations,
		"committed_generations": rows.size(),
		"pool": {
			"setup_count": int(counters["pool_setup_count"]),
			"shutdown_count": int(counters["pool_shutdown_count"]),
			"generation_jobs": int(counters["generation_jobs"]),
		},
		"canonical_source": "PARALLEL_VERIFIED" if mode == "dual" and failures.is_empty() else ("SERIAL" if mode == "serial" else ""),
		"rows": rows,
		"generation_details": dual_rows,
		"failures": failures,
		"note": "PAR0.2 IS NOT A SPEEDUP GATE",
	}

func _load_baseline(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}

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

func _emit(path: String, result: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "  "))
		file.close()

func _env(key: String, fallback: String) -> String:
	var value := OS.get_environment(key)
	return value if not value.is_empty() else fallback
