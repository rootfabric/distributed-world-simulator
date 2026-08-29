extends SceneTree

## ECO.EVO7 PAR1 — backend selection acceptance (v1).
##
## Proves for BOTH direct parallel backends (PROCESS_POOL reusing the PAR0
## pool/protocol, WORKER_THREAD_POOL via add_group_task):
##   A. contract shape + exact fixture parity vs the serial kernel on the
##      SAME immutable candidate/route/context input, worker counts 1/2/4/8;
##   B. canonical correctness campaign: 3 recipes x wc 1/2/4 x 12 generations
##      per backend — every generation the backend's events and aggregate
##      hash must match the serial canonical recruitment EXACTLY, and the
##      canonical ecology (serial run, no executor injected) must reproduce
##      the serial baseline downstream hashes exactly;
##   C. FAIL-CLOSED behavior on invalid inputs (size mismatch, identity
##      mismatch, context divergence) — success=false, no canonical result.
##
## PAR1 does NOT activate parallel recruitment canonically: the canonical
## path stays SERIAL (no executor injected); backends are exercised
## shadow-style exactly like the accepted PAR0 campaign.

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const PlanetPatch = preload("res://scripts/ecology/shadow/eco_evo7_ls30_planet_patch_v1.gd")
const EnvironmentField = preload("res://scripts/ecology/shadow/eco_evo7_ls31_environment_field_v1.gd")
const LS33 = preload("res://scripts/ecology/shadow/eco_evo7_ls33_dispersal_recruitment_v1.gd")
const Kernel = preload("res://scripts/ecology/perf/eco_evo7_par0_recruitment_kernel_v1.gd")
const Contract = preload("res://scripts/ecology/perf/eco_evo7_par1_recruitment_backend_contract_v1.gd")
const ProcessBackend = preload("res://scripts/ecology/perf/eco_evo7_par1_process_recruitment_backend_v1.gd")
const WorkerThreadBackend = preload("res://scripts/ecology/perf/eco_evo7_par1_worker_thread_recruitment_backend_v1.gd")

const RECIPES := ["MIXED_PHYSICAL_HETEROGENEITY", "WATER_GRADIENT_STRONG", "RELIEF_DRAINAGE_STRONG"]
const WORKER_COUNTS := [1, 2, 4]
const FIXTURE_WORKER_COUNTS := [1, 2, 4, 8]
const GENERATIONS := 12
const FOUNDER_SEED := 20260832
const PLACEMENT_SEED := 320032
const EVOLUTION_SEED := 330033
const ENV_SEED := 20260831
const INITIAL_RECORDS := 64

var assertions := 0
var failures: Array[String] = []
var exact_comparisons := 0

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
	_check(world.setup(null), "real Earth initializes")
	var patch := PlanetPatch.new().build(world, Vector3(-0.5, -0.86602540378444, 0.0).normalized(), 32, 16.0)
	_check(not patch.is_empty(), "acceptance patch builds")
	var fields := {}
	for recipe in RECIPES:
		fields[recipe] = EnvironmentField.new().generate(patch, recipe, ENV_SEED)
		_check(not fields[recipe].is_empty(), "field builds for %s" % recipe)

	## ---------------- Phase A: fixture parity + contract (wc 1/2/4/8) ----
	var fixture_sim = LS33.new()
	_check(fixture_sim.setup(patch, fields[RECIPES[0]], FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, 256), "fixture LS3.3 initializes (256 parents)")
	var fixture_snapshot := fixture_sim.step_generation()
	_check(not fixture_snapshot.is_empty(), "fixture generation one completes")
	var fixture_candidates: Array = fixture_snapshot.get("last_candidates", [])
	var fixture_routes: Array = fixture_snapshot.get("last_routes", [])
	var fixture_recruitment: Array = fixture_snapshot.get("last_recruitment", [])
	var fixture_context := Kernel.build_context(
		String(fixture_sim.SCHEMA), String(fixture_sim.VERSION), String(fixture_sim.REVISION),
		int(fixture_sim.environment_seed), String(fixture_sim.environment_field_hash),
		fixture_sim.environment_cells)
	var fixture_serial_hash := Contract.recruitment_hash(fixture_recruitment, fixture_context)
	_check(not fixture_serial_hash.is_empty(), "fixture serial reference hash builds")

	for worker_count in FIXTURE_WORKER_COUNTS:
		var wtp := WorkerThreadBackend.new()
		_check(wtp.setup({"worker_count": worker_count}), "WTP backend setup wc=%d" % worker_count)
		var wtp_result: Dictionary = wtp.evaluate_generation(1, fixture_candidates, fixture_routes, fixture_context)
		_check(Contract.validate_result(wtp_result, Contract.BACKEND_WORKER_THREAD), "WTP result matches contract wc=%d" % worker_count)
		_check(bool(wtp_result.get("success", false)), "WTP fixture succeeds wc=%d" % worker_count)
		_check(String(wtp_result.get("canonical_hash", "")) == fixture_serial_hash, "WTP fixture hash exact wc=%d" % worker_count)
		_check(Contract.events_exact(fixture_recruitment, wtp_result.get("canonical_events", [])), "WTP fixture events exact wc=%d" % worker_count)
		exact_comparisons += 1
		wtp.shutdown()

	for worker_count in FIXTURE_WORKER_COUNTS:
		var proc := ProcessBackend.new()
		_check(proc.setup({
			"worker_count": worker_count, "godot_bin": godot_bin,
			"project_root": project_root, "session_root": session_root,
			"job_timeout_ms": 240_000,
		}), "process backend setup wc=%d" % worker_count)
		var proc_result: Dictionary = proc.evaluate_generation(1, fixture_candidates, fixture_routes, fixture_context)
		_check(Contract.validate_result(proc_result, Contract.BACKEND_PROCESS), "process result matches contract wc=%d" % worker_count)
		_check(bool(proc_result.get("success", false)), "process fixture succeeds wc=%d (%s)" % [worker_count, String(proc_result.get("failure_detail", ""))])
		_check(String(proc_result.get("canonical_hash", "")) == fixture_serial_hash, "process fixture hash exact wc=%d" % worker_count)
		_check(Contract.events_exact(fixture_recruitment, proc_result.get("canonical_events", [])), "process fixture events exact wc=%d" % worker_count)
		exact_comparisons += 1
		proc.shutdown()

	## ---------------- Phase B: canonical correctness campaign ------------
	## Serial baseline per recipe (canonical serial path, no executor).
	var baselines := {}
	for recipe in RECIPES:
		var sim = LS33.new()
		_check(sim.setup(patch, fields[recipe], FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, INITIAL_RECORDS), "%s serial baseline initializes" % recipe)
		var rows: Array[Dictionary] = []
		var evidence: Array[Dictionary] = []
		for step in GENERATIONS:
			var snapshot := sim.step_generation()
			if snapshot.is_empty():
				_check(false, "%s serial generation %d completes" % [recipe, step + 1])
				break
			rows.append(_hash_row(snapshot))
			evidence.append({
				"candidates": snapshot.get("last_candidates", []),
				"routes": snapshot.get("last_routes", []),
				"recruitment": snapshot.get("last_recruitment", []),
				"context": _context_for(sim),
			})
		baselines[recipe] = {"rows": rows, "evidence": evidence}

	## Shadow evaluation of every generation through every backend/wc.
	for recipe in RECIPES:
		var baseline: Dictionary = baselines[recipe]
		if baseline["rows"].size() != GENERATIONS:
			continue
		## Canonical serial replay must reproduce baseline hashes (proves
		## determinism of the comparison base).
		var replay = LS33.new()
		_check(replay.setup(patch, fields[recipe], FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, INITIAL_RECORDS), "%s replay initializes" % recipe)
		for step in GENERATIONS:
			var snapshot := replay.step_generation()
			if snapshot.is_empty():
				_check(false, "%s replay generation %d completes" % [recipe, step + 1])
				break
			var row := _hash_row(snapshot)
			var base_row: Dictionary = baseline["rows"][step]
			var all_equal := true
			for field in row.keys():
				if String(row[field]) != String(base_row[field]):
					all_equal = false
			_check(all_equal, "%s replay gen %d reproduces serial baseline hashes" % [recipe, step + 1])

		for worker_count in WORKER_COUNTS:
			## WORKER_THREAD_POOL shadow pass.
			var wtp := WorkerThreadBackend.new()
			_check(wtp.setup({"worker_count": worker_count}), "%s WTP wc=%d setup" % [recipe, worker_count])
			_shadow_campaign(wtp, recipe, worker_count, "WORKER_THREAD_POOL", baseline)
			wtp.shutdown()

			## PROCESS_POOL shadow pass (fresh pool per pass).
			var proc := ProcessBackend.new()
			_check(proc.setup({
				"worker_count": worker_count, "godot_bin": godot_bin,
				"project_root": project_root, "session_root": session_root,
				"job_timeout_ms": 240_000,
			}), "%s process wc=%d setup" % [recipe, worker_count])
			_shadow_campaign(proc, recipe, worker_count, "PROCESS_POOL", baseline)
			proc.shutdown()

	_check(exact_comparisons >= 108, "campaign reached >=108 exact comparisons (got %d)" % exact_comparisons)

	## ---------------- Phase C: fail-closed -------------------------------
	_fail_closed_checks(project_root, session_root, godot_bin, patch)

	world.queue_free()
	_finish()

func _shadow_campaign(backend: Object, recipe: String, worker_count: int, backend_name: String, baseline: Dictionary) -> void:
	var evidence: Array = baseline["evidence"]
	for step in evidence.size():
		var entry: Dictionary = evidence[step]
		var candidates: Array = entry["candidates"]
		var routes: Array = entry["routes"]
		var recruitment: Array = entry["recruitment"]
		var context: Dictionary = entry["context"]
		var result: Dictionary = backend.call("evaluate_generation", step + 1, candidates, routes, context)
		if not bool(result.get("success", false)):
			_check(false, "%s %s wc=%d gen %d succeeds (%s)" % [recipe, backend_name, worker_count, step + 1, String(result.get("failure_detail", ""))])
			return
		var events: Array = result.get("canonical_events", [])
		var expected_hash := Contract.recruitment_hash(recruitment, context)
		if String(result.get("canonical_hash", "")) != expected_hash or not Contract.events_exact(recruitment, events):
			_check(false, "%s %s wc=%d gen %d EXACT parity" % [recipe, backend_name, worker_count, step + 1])
			return
		exact_comparisons += 1
	_check(true, "%s %s wc=%d shadow campaign exact (%d generations)" % [recipe, backend_name, worker_count, evidence.size()])

func _fail_closed_checks(project_root: String, session_root: String, godot_bin: String, patch: Dictionary) -> void:
	var candidates: Array[Dictionary] = []
	var routes: Array[Dictionary] = []
	for index in 8:
		candidates.append({"candidate_hash": "c%032d" % index})
		routes.append({"candidate_hash": "c%032d" % index})

	## WTP: size mismatch and identity mismatch fail closed.
	var wtp := WorkerThreadBackend.new()
	_check(wtp.setup({"worker_count": 2}), "WTP fail-closed setup")
	var wtp_size: Dictionary = wtp.evaluate_generation(1, candidates, routes.slice(0, 4), {})
	_check(not bool(wtp_size.get("success", true)) and String(wtp_size.get("failure_code", "")) == "PAR1_INPUTS_INVALID", "WTP size mismatch fails closed")
	var foreign_routes: Array[Dictionary] = []
	for index in 8:
		foreign_routes.append({"candidate_hash": "r%032d" % index})
	var wtp_identity: Dictionary = wtp.evaluate_generation(1, candidates, foreign_routes, {})
	_check(not bool(wtp_identity.get("success", true)) and String(wtp_identity.get("failure_code", "")) == "PAR1_INPUTS_INVALID", "WTP identity mismatch fails closed")
	wtp.shutdown()

	## Process backend: size mismatch fails closed without spawning a pool.
	var proc := ProcessBackend.new()
	_check(proc.setup({
		"worker_count": 1, "godot_bin": godot_bin,
		"project_root": project_root, "session_root": session_root,
	}), "process fail-closed setup")
	var proc_size: Dictionary = proc.evaluate_generation(1, candidates, routes.slice(0, 4), {})
	_check(not bool(proc_size.get("success", true)) and String(proc_size.get("failure_code", "")) == "PAR1_INPUTS_INVALID", "process size mismatch fails closed")
	proc.shutdown()

	## Process backend context pinning: a pool set up with one context must
	## reject evaluation with a diverged context (fail closed, no fallback).
	if patch.is_empty():
		return
	var sim_a = LS33.new()
	var sim_b = LS33.new()
	var field_a := EnvironmentField.new().generate(patch, "MIXED_PHYSICAL_HETEROGENEITY", ENV_SEED)
	var field_b := EnvironmentField.new().generate(patch, "WATER_GRADIENT_STRONG", ENV_SEED)
	_check(sim_a.setup(patch, field_a, FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, 32), "context-A sim initializes")
	_check(sim_b.setup(patch, field_b, FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, 32), "context-B sim initializes")
	var snap_a := sim_a.step_generation()
	var snap_b := sim_b.step_generation()
	_check(not snap_a.is_empty() and not snap_b.is_empty(), "context fail-closed sims step")
	var pin := ProcessBackend.new()
	_check(pin.setup({
		"worker_count": 1, "godot_bin": godot_bin,
		"project_root": project_root, "session_root": session_root,
	}), "context-pinned process backend setup")
	var first: Dictionary = pin.evaluate_generation(1, snap_a.get("last_candidates", []), snap_a.get("last_routes", []), _context_for(sim_a))
	_check(bool(first.get("success", false)), "context-pinned first evaluation succeeds")
	var diverged: Dictionary = pin.evaluate_generation(2, snap_b.get("last_candidates", []), snap_b.get("last_routes", []), _context_for(sim_b))
	_check(not bool(diverged.get("success", true)) and String(diverged.get("failure_code", "")) == "PAR1_CONTEXT_MISMATCH", "context divergence fails closed")
	pin.shutdown()

func _context_for(sim) -> Dictionary:
	return Kernel.build_context(
		String(sim.SCHEMA), String(sim.VERSION), String(sim.REVISION),
		int(sim.environment_seed), String(sim.environment_field_hash),
		sim.environment_cells)

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

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
		push_error("PAR1 CHECK FAIL: " + label)

func _finish() -> void:
	var world = root.get_node_or_null("EarthWorld")
	if world != null:
		world.queue_free()
	print("PAR1 exact comparisons: %d" % exact_comparisons)
	if failures.is_empty():
		print("ECO.EVO7 PAR1 Backend Selection: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		print("PAR1 FAIL: " + failure)
	print("ECO.EVO7 PAR1 Backend Selection: FAIL (%d/%d assertions failed)" % [failures.size(), assertions])
	quit(1)
