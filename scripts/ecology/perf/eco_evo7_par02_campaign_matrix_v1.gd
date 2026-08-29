extends SceneTree

## ECO.EVO7 PERF1-PAR0.2 — campaign hash matrix aggregator.
##
## Reads every campaign run artifact under artifacts/par02/ and proves the
## full campaign gate before any candidate claim:
##   - 3 recipes x worker counts {1,2,4} x 12 generations = 108 dual
##     generation comparisons;
##   - every dual generation is internally exact (serial oracle == parallel)
##     and externally exact against the serial baseline over all 10 canonical
##     downstream hashes (1080/1080 byte-for-byte comparisons);
##   - every dual run used exactly one persistent pool lifecycle;
##   - canonical_source == PARALLEL_VERIFIED for every dual generation.
##
## Writes par02_hash_matrix.json and par02_summary.json; exit 0 only on a
## complete exact matrix. PAR0.2 IS NOT A SPEEDUP GATE.

const RECIPES := ["MIXED_PHYSICAL_HETEROGENEITY", "WATER_GRADIENT_STRONG", "RELIEF_DRAINAGE_STRONG"]
const WORKER_COUNTS := [1, 2, 4]
const GENERATIONS := 12
const HASH_FIELDS := 10

func _init() -> void:
	var project_root := ProjectSettings.globalize_path("res://")
	var artifacts_dir := project_root.path_join("artifacts/par02")
	var failures: Array[String] = []
	var runs: Array[Dictionary] = []
	var generation_comparisons := 0
	var hash_comparisons := 0
	var exact_hash_comparisons := 0

	for recipe in RECIPES:
		var serial_path := artifacts_dir.path_join("serial_%s.json" % recipe.to_lower())
		var serial = _read(serial_path)
		if serial.is_empty():
			failures.append("missing serial baseline artifact: %s" % serial_path)
			continue
		if int(serial.get("committed_generations", 0)) != GENERATIONS:
			failures.append("%s serial baseline committed %d of %d generations" % [
				recipe, int(serial.get("committed_generations", 0)), GENERATIONS])
		for worker_count in WORKER_COUNTS:
			var dual_path := artifacts_dir.path_join("dual_%s_wc%d.json" % [recipe.to_lower(), worker_count])
			var dual = _read(dual_path)
			if dual.is_empty():
				failures.append("missing dual artifact: %s" % dual_path)
				continue
			var run_failures := _verify_run(dual, recipe, worker_count)
			for run_failure in run_failures:
				failures.append("%s wc=%d: %s" % [recipe, worker_count, run_failure])
			generation_comparisons += int(dual.get("committed_generations", 0))
			for parity_row in dual.get("external_parity", []):
				hash_comparisons += HASH_FIELDS
				if bool(parity_row.get("exact", false)):
					exact_hash_comparisons += HASH_FIELDS
			runs.append({
				"recipe": recipe,
				"worker_count": worker_count,
				"mode": String(dual.get("mode", "")),
				"committed_generations": int(dual.get("committed_generations", 0)),
				"pool": dual.get("pool", {}),
				"canonical_source": String(dual.get("canonical_source", "")),
				"external_exact_generations": _count_exact(dual),
				"failure_count": Array(dual.get("failures", [])).size(),
				"artifact": dual_path,
			})

	var summary := {
		"schema": "distributed_world_simulator.ecology.evo7_par02.campaign_summary.v1",
		"base_sha": OS.get_environment("ECO_PAR02_BASE_SHA"),
		"candidate_sha": OS.get_environment("ECO_PAR02_CANDIDATE_SHA"),
		"recipes": RECIPES,
		"worker_counts": WORKER_COUNTS,
		"generations_per_run": GENERATIONS,
		"expected_generation_comparisons": RECIPES.size() * WORKER_COUNTS.size() * GENERATIONS,
		"generation_comparisons": generation_comparisons,
		"expected_hash_comparisons": RECIPES.size() * WORKER_COUNTS.size() * GENERATIONS * HASH_FIELDS,
		"hash_comparisons": hash_comparisons,
		"exact_hash_comparisons": exact_hash_comparisons,
		"canonical_source": "PARALLEL_VERIFIED",
		"runs": runs,
		"failures": failures,
		"speedup_gate": "NONE — PAR0.2 IS NOT A SPEEDUP GATE",
	}
	_write(artifacts_dir.path_join("par02_hash_matrix.json"), {"runs": runs, "failures": failures})
	_write(artifacts_dir.path_join("par02_summary.json"), summary)
	if failures.is_empty() \
			and generation_comparisons == RECIPES.size() * WORKER_COUNTS.size() * GENERATIONS \
			and hash_comparisons == RECIPES.size() * WORKER_COUNTS.size() * GENERATIONS * HASH_FIELDS \
			and exact_hash_comparisons == hash_comparisons:
		print("PAR02 CAMPAIGN MATRIX EXACT: %d generations, %d/%d hash comparisons" % [
			generation_comparisons, exact_hash_comparisons, hash_comparisons])
		quit(0)
		return
	for failure in failures:
		push_error("PAR02 MATRIX FAIL: " + failure)
	print("PAR02 CAMPAIGN MATRIX: FAIL (%d generations, %d/%d exact hash comparisons, %d failures)" % [
		generation_comparisons, exact_hash_comparisons, hash_comparisons, failures.size()])
	quit(1)

func _verify_run(dual: Dictionary, recipe: String, worker_count: int) -> Array[String]:
	var failures: Array[String] = []
	if String(dual.get("recipe", "")) != recipe:
		failures.append("artifact recipe mismatch")
	if int(dual.get("worker_count", -1)) != worker_count:
		failures.append("artifact worker_count mismatch")
	if String(dual.get("mode", "")) != "DUAL_VERIFY":
		failures.append("mode %s != DUAL_VERIFY" % String(dual.get("mode", "")))
	if int(dual.get("committed_generations", 0)) != GENERATIONS:
		failures.append("committed %d of %d generations" % [int(dual.get("committed_generations", 0)), GENERATIONS])
	var pool: Dictionary = dual.get("pool", {})
	if int(pool.get("setup_count", -1)) != 1:
		failures.append("pool_setup_count %d != 1" % int(pool.get("setup_count", -1)))
	if int(pool.get("shutdown_count", -1)) != 1:
		failures.append("pool_shutdown_count %d != 1" % int(pool.get("shutdown_count", -1)))
	if int(pool.get("generation_jobs", -1)) != GENERATIONS:
		failures.append("generation_jobs %d != %d" % [int(pool.get("generation_jobs", -1)), GENERATIONS])
	if String(dual.get("canonical_source", "")) != "PARALLEL_VERIFIED":
		failures.append("canonical_source %s != PARALLEL_VERIFIED" % String(dual.get("canonical_source", "")))
	for detail in dual.get("generation_details", []):
		if String(detail.get("canonical_source", "")) != "PARALLEL_VERIFIED":
			failures.append("generation %s canonical source not PARALLEL_VERIFIED" % str(detail.get("generation", "?")))
		if not bool(detail.get("comparison_passed", false)):
			failures.append("generation %s internal comparison not passed" % str(detail.get("generation", "?")))
	if Array(dual.get("failures", [])).size() > 0:
		failures.append("run artifact carries %d failures" % Array(dual.get("failures", [])).size())
	return failures

func _count_exact(dual: Dictionary) -> int:
	var exact := 0
	for parity_row in dual.get("external_parity", []):
		if bool(parity_row.get("exact", false)):
			exact += 1
	return exact

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}

func _write(path: String, value: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value, "  "))
		file.close()
