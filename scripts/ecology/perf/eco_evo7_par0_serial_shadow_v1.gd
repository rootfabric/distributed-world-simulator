extends SceneTree

## ECO.EVO7 PAR0 shadow runner — hash matrix and serial kernel parity.
##
## Operates WITHOUT the pool (the pool's persistent OS-process prototype is
## blocked in this build by PIPE_TRANSPORT_PARTIAL — see docs/checkpoints).
## This runner executes the complete deterministic simulation in serial and
## proves, for every generation and every supported environment recipe, that
## the extracted pure recruitment kernel produces byte-identical recruitment
## events to the LS3.3 serial oracle (single implementation guarantee).

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const Workbench = preload("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd")
const Kernel = preload("res://scripts/ecology/perf/eco_evo7_par0_recruitment_kernel_v1.gd")

const HASH_FIELDS: Array[String] = [
	"candidate_pool_hash", "dispersal_pool_hash", "recruitment_hash",
	"precompetition_population_hash", "competition_hash",
	"postcompetition_population_hash", "hereditary_pool_hash",
	"ecology_state_hash", "classification_hash", "workbench_hash",
]
const ALL_RECIPES := ["MIXED_PHYSICAL_HETEROGENEITY", "WATER_GRADIENT_STRONG", "RELIEF_DRAINAGE_STRONG"]

func _init() -> void:
	var generations := 12
	if not OS.get_environment("ECO_PAR0_GENERATIONS").is_empty():
		generations = clampi(int(OS.get_environment("ECO_PAR0_GENERATIONS")), 1, 60)
	var recipes := ALL_RECIPES
	if not OS.get_environment("ECO_PAR0_RECIPES").is_empty():
		recipes = OS.get_environment("ECO_PAR0_RECIPES").split(",", false)
	var project_root := ProjectSettings.globalize_path("res://")

	var all_rows: Array[Dictionary] = []
	var failures: Array[String] = []
	for recipe in recipes:
		var run_failures: Array[String] = []
		var rows := _run_serial(recipe, generations, run_failures, project_root)
		all_rows.append_array(rows)
		failures.append_array(run_failures)

	var summary := {
		"schema": "distributed_world_simulator.ecology.evo7_par0.serial_shadow.v1",
		"generations_per_run": generations,
		"recipes": recipes,
		"hash_matrix": all_rows,
		"failures": failures,
		"transport_status": "PIPE_TRANSPORT_PARTIAL: process-pool campaign deferred to PAR0.1; see docs/checkpoints/PERF1_PAR0_RU.md",
	}
	print("PAR0_SERIAL_SUMMARY " + JSON.stringify(_compact(summary)))
	var file := FileAccess.open(project_root.path_join("artifacts/par0_serial_shadow_report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(summary, "  "))
		file.close()
	if failures.is_empty():
		print("ECO.EVO7 PAR0 Serial Shadow: PASS")
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 PAR0 SERIAL SHADOW FAIL: " + failure)
	print("ECO.EVO7 PAR0 Serial Shadow: FAIL (%d failures)" % failures.size())
	quit(1)

func _run_serial(recipe: String, generations: int, failures: Array[String], project_root: String) -> Array[Dictionary]:
	var world = EarthWorld.new()
	root.add_child(world)
	if not world.setup(null):
		failures.append("%s: Earth setup failed" % recipe)
		world.queue_free()
		return []
	var workbench = Workbench.new()
	if not workbench.setup(world, {"environment_recipe": recipe}):
		failures.append("%s: workbench setup failed" % recipe)
		world.queue_free()
		return []
	var rows: Array[Dictionary] = []
	var ls33 = workbench.ecology.core
	for step in generations:
		var snapshot: Dictionary = workbench.advance_generations(1)
		if snapshot.is_empty():
			failures.append("%s gen=%d: generation failed (extinction or validation)" % [recipe, step + 1])
			break
		var row := _hash_row(workbench, snapshot)
		row["recipe"] = recipe
		row["generation"] = step + 1
		row["population"] = int(snapshot.get("record_count", 0))
		# Serial kernel replay: re-evaluate the SAME canonical candidates through
		# the kernel directly (single-implementation proof). Compare event list
		# and recruitment hash to the oracle. Canonical evidence lives in the
		# LS3.3 core snapshot (the LS3.4 snapshot proxies only aggregate hashes).
		var core_snapshot: Dictionary = workbench.ecology.core.get_snapshot()
		var candidates: Array = core_snapshot.get("last_candidates", [])
		var routes: Array = core_snapshot.get("last_routes", [])
		var serial_events: Array = core_snapshot.get("last_recruitment", [])
		var replay_ok := _replay_kernel_parity(ls33, candidates, routes, _typed_events(serial_events), failures, recipe, step + 1)
		row["serial_replay_ok"] = replay_ok
		rows.append(row)
	world.queue_free()
	return rows

func _replay_kernel_parity(
	ls33,
	candidates: Array,
	routes: Array,
	serial_events: Array[Dictionary],
	failures: Array[String],
	recipe: String,
	generation: int
) -> bool:
	if candidates.size() != routes.size() or candidates.size() != serial_events.size():
		failures.append("%s gen=%d kernel replay: candidate/route/event size mismatch %d/%d/%d" % [recipe, generation, candidates.size(), routes.size(), serial_events.size()])
		return false
	var context := Kernel.build_context(
		String(ls33.SCHEMA), String(ls33.VERSION), String(ls33.REVISION),
		int(ls33.environment_seed), String(ls33.environment_field_hash),
		ls33.environment_cells)
	var replay: Array[Dictionary] = []
	for index in candidates.size():
		var event := Kernel.evaluate_recruitment_event(candidates[index], routes[index], context)
		if event.is_empty():
			failures.append("%s gen=%d kernel replay: kernel returned empty for candidate %d" % [recipe, generation, index])
			return false
		event["recruitment_event_hash"] = Kernel.recruitment_event_hash(event, String(ls33.SCHEMA), String(ls33.VERSION))
		replay.append(event)
	replay.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["candidate_hash"]) < String(b["candidate_hash"])
	)
	if not _events_exact(serial_events, replay):
		failures.append("%s gen=%d kernel replay: event-by-event mismatch (single-implementation FAILED)" % [recipe, generation])
		return false
	var serial_hash := String(ls33.call("_recruitment_hash", _typed_events(serial_events)))
	var replay_hash := String(ls33.call("_recruitment_hash", replay))
	if serial_hash != replay_hash:
		failures.append("%s gen=%d kernel replay: recruitment_hash mismatch serial=%s replay=%s" % [recipe, generation, serial_hash, replay_hash])
		return false
	return true

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

func _typed_events(source: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for value in source:
		if not value is Dictionary:
			return []
		out.append(value)
	return out

func _hash_row(workbench, snapshot: Dictionary) -> Dictionary:
	var ecology: Dictionary = workbench.get_ecology_snapshot()
	return {
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
		"ls33_recruitment_ms": float(workbench.get_last_generation_profile().get("ecology", {}).get("ls33", {}).get("recruitment_eval_ms", 0.0)),
	}

func _compact(summary: Dictionary) -> Dictionary:
	var rows: Array = []
	for row in summary["hash_matrix"]:
		rows.append(row)
	summary["hash_matrix"] = rows
	return summary