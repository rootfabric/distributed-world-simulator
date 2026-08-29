extends SceneTree

## ECO.EVO7 PERF1-PAR0 — shadow-only deterministic recruitment campaign.
##
## For every recipe and worker count this runner executes the complete
## deterministic simulation with a persistent process pool attached in
## SHADOW-ONLY mode:
##   serial LS3.3 recruitment  -> canonical ecology state (unchanged oracle)
##   parallel pool evaluation  -> shadow evidence only, never feeds state
## Every generation compares, byte-for-byte:
##   candidate_pool_hash, dispersal_pool_hash, recruitment_hash,
##   precompetition_population_hash, competition_hash,
##   postcompetition_population_hash, hereditary_pool_hash,
##   ecology_state_hash, classification_hash, workbench_hash
## and requires EXACT equality of serial vs parallel recruitment events.
##
## Any mismatch, worker timeout, crash or invalid response is FAIL-CLOSED.

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const Workbench = preload("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd")
const Kernel = preload("res://scripts/ecology/perf/eco_evo7_par0_recruitment_kernel_v1.gd")
const Pool = preload("res://scripts/ecology/perf/eco_evo7_par0_process_pool_v1.gd")

const HASH_FIELDS: Array[String] = [
	"candidate_pool_hash", "dispersal_pool_hash", "recruitment_hash",
	"precompetition_population_hash", "competition_hash", "postcompetition_population_hash",
	"hereditary_pool_hash", "ecology_state_hash", "classification_hash", "workbench_hash",
]
const ALL_RECIPES := ["MIXED_PHYSICAL_HETEROGENEITY", "WATER_GRADIENT_STRONG", "RELIEF_DRAINAGE_STRONG"]

func _init() -> void:
	var godot_bin := "C:/Godot/godot/bin/godot.windows.editor.double.x86_64.console.exe"
	var override_bin := OS.get_environment("GODOT_BIN")
	if not override_bin.is_empty():
		godot_bin = override_bin
	var project_root := ProjectSettings.globalize_path("res://")
	var generations := 12
	if not OS.get_environment("ECO_PAR0_GENERATIONS").is_empty():
		generations = clampi(int(OS.get_environment("ECO_PAR0_GENERATIONS")), 1, 60)
	var recipes := ALL_RECIPES
	if not OS.get_environment("ECO_PAR0_RECIPES").is_empty():
		recipes = OS.get_environment("ECO_PAR0_RECIPES").split(",", false)
	var worker_configs := [1, 2, 4]
	if not OS.get_environment("ECO_PAR0_WORKERS").is_empty():
		worker_configs = []
		for part in OS.get_environment("ECO_PAR0_WORKERS").split(",", false):
			worker_configs.append(int(part))
	var job_timeout_ms := 180000
	if not OS.get_environment("ECO_PAR0_JOB_TIMEOUT_MS").is_empty():
		job_timeout_ms = int(OS.get_environment("ECO_PAR0_JOB_TIMEOUT_MS"))
	var session_root := OS.get_environment("ECO_PAR0_SESSION_ROOT")
	if session_root.is_empty():
		session_root = project_root.path_join("artifacts/par0_sessions")
	var log_dir := OS.get_environment("ECO_PAR0_WORKER_LOG_DIR")

	var failures: Array[String] = []
	var baseline: Dictionary = {}
	var parity_rows: Array[Dictionary] = []

	for recipe in recipes:
		## 1) Serial oracle baseline (no pool, no shadow).
		var serial_rows := _run_serial(recipe, generations, failures)
		baseline[recipe] = serial_rows

		## 2) Shadow pool runs per worker count.
		for worker_count_value in worker_configs:
			var worker_count := int(worker_count_value)
			var run_failures := _run_shadow(
				recipe, generations, worker_count, baseline[recipe], parity_rows,
				godot_bin, project_root, session_root, log_dir, job_timeout_ms)
			failures.append_array(run_failures)

	var summary := {
		"schema": "distributed_world_simulator.ecology.evo7_par0.shadow_campaign.v1",
		"generations_per_run": generations,
		"recipes": recipes,
		"worker_configs": worker_configs,
		"parity_rows": parity_rows,
		"failures": failures,
	}
	print("PAR0_CAMPAIGN_SUMMARY " + JSON.stringify(_compact(summary)))
	var file := FileAccess.open(project_root.path_join("artifacts/par0_shadow_campaign_report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(summary, "  "))
		file.close()
	if failures.is_empty():
		print("ECO.EVO7 PAR0 Shadow Campaign: PASS")
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 PAR0 CAMPAIGN FAIL: " + failure)
	print("ECO.EVO7 PAR0 Shadow Campaign: FAIL (%d failures)" % failures.size())
	quit(1)

## ---------- serial oracle run ----------

func _run_serial(recipe: String, generations: int, failures: Array[String]) -> Array[Dictionary]:
	var world = EarthWorld.new()
	root.add_child(world)
	if not world.setup(null):
		failures.append("%s serial: Earth setup failed" % recipe)
		world.queue_free()
		return []
	var workbench = Workbench.new()
	if not workbench.setup(world, {"environment_recipe": recipe}):
		failures.append("%s serial: workbench setup failed" % recipe)
		world.queue_free()
		return []
	var rows: Array[Dictionary] = []
	for step in generations:
		var snapshot: Dictionary = workbench.advance_generations(1)
		if snapshot.is_empty():
			failures.append("%s serial: generation %d failed (extinction or validation)" % [recipe, step + 1])
			break
		rows.append(_hash_row(workbench, snapshot))
	world.queue_free()
	return rows

## ---------- shadow pool run ----------

func _run_shadow(
	recipe: String,
	generations: int,
	worker_count: int,
	serial_rows: Array[Dictionary],
	parity_rows: Array[Dictionary],
	godot_bin: String,
	project_root: String,
	session_root: String,
	log_dir: String,
	job_timeout_ms: int
) -> Array[String]:
	var failures: Array[String] = []
	var world = EarthWorld.new()
	root.add_child(world)
	if not world.setup(null):
		failures.append("%s wc=%d: Earth setup failed" % [recipe, worker_count])
		world.queue_free()
		return []
	var workbench = Workbench.new()
	if not workbench.setup(world, {"environment_recipe": recipe}):
		failures.append("%s wc=%d: workbench setup failed" % [recipe, worker_count])
		world.queue_free()
		return []

	var session_dir := session_root.path_join("shadow_%s_wc%d_%d" % [recipe, worker_count, Time.get_ticks_usec()])
	var pool := Pool.new()
	if not pool.setup(godot_bin, project_root, session_dir, worker_count, _pool_context(workbench), job_timeout_ms):
		failures.append("%s wc=%d: pool setup failed: %s" % [recipe, worker_count, pool.last_error()])
		pool.shutdown()
		world.queue_free()
		return []

	var workers_active := true
	for step in generations:
		var total_started := Time.get_ticks_usec()
		var snapshot: Dictionary = workbench.advance_generations(1)
		if snapshot.is_empty():
			failures.append("%s wc=%d: generation %d failed (extinction or validation)" % [recipe, worker_count, step + 1])
			break
		var row := _hash_row(workbench, snapshot)
		var serial_row: Dictionary = serial_rows[step]
		var hashes_ok := true
		for field in HASH_FIELDS:
			if String(row[field]) != String(serial_row[field]):
				hashes_ok = false
				failures.append("%s wc=%d gen=%d %s mismatch (parallel run diverged from serial baseline)" % [recipe, worker_count, step + 1, field])
		if not workers_active:
			continue

		## Shadow-only parallel recruitment over the canonical candidates.
		var ecology: Dictionary = workbench.get_ecology_snapshot()
		var candidates: Array = ecology.get("last_candidates", [])
		var routes: Array = ecology.get("last_routes", [])
		var ls33 = workbench.ecology.core
		var serial_events: Array = ecology.get("last_recruitment", [])
		var generation := int(ecology.get("generation", -1))
		if candidates.size() != routes.size() or candidates.size() != serial_events.size():
			failures.append("%s wc=%d gen=%d canonical evidence size mismatch" % [recipe, worker_count, generation])
			continue

		var items := _build_items(candidates, routes)
		var bounds: Array[int] = Pool.partition(items.size(), worker_count)
		var slices: Array = []
		for index in worker_count:
			slices.append(items.slice(bounds[index], bounds[index + 1]))

		var serialize_started := Time.get_ticks_usec()
		var base_id := pool.submit_generation(generation, slices)
		var serialize_us := Time.get_ticks_usec() - serialize_started
		if base_id.is_empty():
			failures.append("%s wc=%d gen=%d submit failed: %s" % [recipe, worker_count, generation, pool.last_error()])
			workers_active = false
			continue
		var collect_started := Time.get_ticks_usec()
		var collected: Dictionary = pool.collect_all()
		var ipc_us := Time.get_ticks_usec() - collect_started
		if collected.is_empty():
			failures.append("%s wc=%d gen=%d collect failed: %s" % [recipe, worker_count, generation, pool.last_error()])
			workers_active = false
			continue

		var merge_started := Time.get_ticks_usec()
		var parallel_events := _merge_responses(collected["responses"], items.size())
		var merge_us := Time.get_ticks_usec() - merge_started
		if parallel_events.is_empty():
			failures.append("%s wc=%d gen=%d merge/validation failed" % [recipe, worker_count, generation])
			workers_active = false
			continue

		var serial_hash := String(ls33.call("_recruitment_hash", _typed_events(serial_events)))
		var parallel_hash := String(ls33.call("_recruitment_hash", parallel_events))
		var exact := _events_exact(_typed_events(serial_events), parallel_events)
		if not exact or serial_hash != parallel_hash:
			var first_mismatch := _first_mismatch(_typed_events(serial_events), parallel_events)
			failures.append("%s wc=%d gen=%d PAR0 FAIL-CLOSED serial/parallel recruitment mismatch (%s) serial=%s parallel=%s" % [
				recipe, worker_count, generation, first_mismatch, serial_hash, parallel_hash])
			workers_active = false
			continue

		var worker_compute_us := 0
		for response in collected["responses"]:
			worker_compute_us += int(response.get("worker_compute_us", 0))
		var total_us := Time.get_ticks_usec() - total_started
		parity_rows.append({
			"recipe": recipe, "worker_count": worker_count, "generation": generation,
			"population": int(ecology.get("record_count", 0)),
			"candidates": items.size(),
			"serial_recruitment_ms": _ls33_recruitment_ms(workbench),
			"worker_compute_ms": float(worker_compute_us) / 1000.0,
			"serialize_ms": float(serialize_us) / 1000.0,
			"ipc_ms": float(ipc_us) / 1000.0,
			"merge_ms": float(merge_us) / 1000.0,
			"total_parallel_ms": float(total_us) / 1000.0,
			"generation_total_ms": float(workbench.get_last_generation_profile().get("total_ms", 0.0)),
			"exact_parity": true,
		})
		print("PAR0 %s wc=%d gen=%d pop=%d candidates=%d serial=%.1fms parallel=%.1fms (ipc=%.1f merge=%.1f) EXACT" % [
			recipe, worker_count, generation, int(ecology.get("record_count", 0)), items.size(),
			_ls33_recruitment_ms(workbench), float(total_us) / 1000.0, float(ipc_us) / 1000.0, float(merge_us) / 1000.0])

	pool.shutdown()
	world.queue_free()
	return failures

## ---------- helpers ----------

func _pool_context(workbench) -> Dictionary:
	var ls33 = workbench.ecology.core
	return Kernel.build_context(
		String(ls33.SCHEMA), String(ls33.VERSION), String(ls33.REVISION),
		int(ls33.environment_seed), String(ls33.environment_field_hash),
		ls33.environment_cells)

func _build_items(candidates: Array, routes: Array) -> Array:
	## Candidates and routes are already canonically sorted by candidate_hash.
	var items: Array = []
	for index in candidates.size():
		items.append({
			"candidate": candidates[index],
			"route": routes[index],
		})
	return items

func _merge_responses(responses: Array, expected_count: int) -> Array[Dictionary]:
	## Canonical merge: never trust arrival order; concatenate, sort by
	## candidate_hash, validate every event hash.
	var events: Array[Dictionary] = []
	for response in responses:
		var response_events: Array = response.get("events", [])
		for event_value in response_events:
			if not event_value is Dictionary:
				return []
			events.append(event_value)
	if events.size() != expected_count:
		return []
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["candidate_hash"]) < String(b["candidate_hash"])
	)
	return events

func _typed_events(source: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for value in source:
		if not value is Dictionary:
			return []
		out.append(value)
	return out

func _events_exact(a: Array[Dictionary], b: Array[Dictionary]) -> bool:
	if a.size() != b.size():
		return false
	for index in a.size():
		var left: Dictionary = a[index]
		var right: Dictionary = b[index]
		for key in left.keys():
			if not right.has(key) or left[key] != right[key]:
				return false
		if left.keys().size() != right.keys().size():
			return false
	return true

func _first_mismatch(a: Array[Dictionary], b: Array[Dictionary]) -> String:
	for index in mini(a.size(), b.size()):
		if a[index].get("candidate_hash", "") != b[index].get("candidate_hash", ""):
			return "position %d candidate order" % index
		for key in a[index].keys():
			if not b[index].has(key) or a[index][key] != b[index][key]:
				return "candidate %s field %s" % [String(a[index].get("candidate_hash", "")), key]
	return "count %d vs %d" % [a.size(), b.size()]

func _hash_row(workbench, snapshot: Dictionary) -> Dictionary:
	var ecology: Dictionary = workbench.get_ecology_snapshot()
	var row := {
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
	return row

func _ls33_recruitment_ms(workbench) -> float:
	var profile: Dictionary = workbench.get_last_generation_profile()
	var ecology: Dictionary = profile.get("ecology", {})
	var ls33: Dictionary = ecology.get("ls33", {})
	return float(ls33.get("recruitment_eval_ms", 0.0))

func _compact(summary: Dictionary) -> Dictionary:
	var rows: Array = []
	for row in summary["parity_rows"]:
		rows.append(row)
	summary["parity_rows"] = rows
	return summary
