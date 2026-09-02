extends SceneTree

const Fabric = preload("res://scripts/research/fabric0/fabric0_event_sparse_islands_v1.gd")
const Experiments = preload("res://scripts/research/fabric0/fabric0_event_sparse_islands_experiments_v1.gd")

func close(a: float, b: float, tolerance: float = 1.0e-9) -> bool:
	return absf(a - b) <= tolerance

func close_vec(a: Vector3, b: Vector3, tolerance: float = 1.0e-9) -> bool:
	return (a - b).length() <= tolerance

func _init() -> void:
	var checks := 0

	# ---------------------------------------------------------------------
	# Sparse numerical backend itself: no contact semantics are needed to
	# prove that the linear path is a real sparse PCG solve.
	# ---------------------------------------------------------------------
	var matrix := [{0:4.0,1:1.0},{0:1.0,1:3.0}]
	var pcg := Fabric._pcg(matrix, [1.0,2.0], [0.0,0.0], [4.0,3.0], 1.0e-13, 10)
	assert(bool(pcg["ok"])); checks += 1
	assert(int(pcg["iterations"]) == 2); checks += 1
	assert(close(float(pcg["x"][0]), 1.0/11.0, 1.0e-13)); checks += 1
	assert(close(float(pcg["x"][1]), 7.0/11.0, 1.0e-13)); checks += 1
	assert(float(pcg["residual"]) <= 1.0e-13); checks += 1

	# ---------------------------------------------------------------------
	# Two independent islands can be scheduled in the opposite order without
	# changing world semantics. This is the deterministic parallelization contract.
	# ---------------------------------------------------------------------
	var two_forward := Experiments.solve_two_stacks(false,false,false)
	var two_reverse := Experiments.solve_two_stacks(true,true,true)
	assert(bool(two_forward["result"]["ok"])); checks += 1
	assert(bool(two_reverse["result"]["ok"])); checks += 1
	assert(int(two_forward["result"]["solver_stats"]["island_count"]) == 2); checks += 1
	assert(int(two_forward["result"]["solver_stats"]["max_island_count"]) == 2); checks += 1
	assert(int(two_forward["result"]["solver_stats"]["island_solve_count"]) == 2); checks += 1
	assert(String(two_forward["result"]["solver_stats"]["linear_backend"]) == "SPARSE_PCG"); checks += 1
	assert(int(two_forward["result"]["solver_stats"]["dense_materializations"]) == 0); checks += 1
	assert(int(two_forward["result"]["solver_stats"]["sparse_effective_mass_entries"]) == 24); checks += 1
	assert(int(two_forward["result"]["solver_stats"]["dense_effective_mass_capacity"]) == 72); checks += 1
	assert(int(two_forward["result"]["solver_stats"]["pcg_calls"]) == 34); checks += 1
	assert(int(two_forward["result"]["solver_stats"]["pcg_iterations"]) == 68); checks += 1
	assert(two_forward["result"]["islands"].size() == 2); checks += 1
	assert(two_forward["result"]["islands"][0]["body_ids"] == ["A","B"]); checks += 1
	assert(two_forward["result"]["islands"][1]["body_ids"] == ["D","E"]); checks += 1
	assert(String(two_forward["hash"]) == "e50cceb70dc4ecbd0100e5207ca5a58a2285c90a5085a6556b19db8ce8699078"); checks += 1
	assert(String(two_forward["hash"]) == String(two_reverse["hash"])); checks += 1
	assert(JSON.stringify(two_forward["result"]["lifecycle"]) == JSON.stringify(two_reverse["result"]["lifecycle"])); checks += 1
	for id in ["A","B","D","E"]:
		assert(close_vec(two_forward["world"]["bodies"][id]["position"], two_reverse["world"]["bodies"][id]["position"], 1.0e-12)); checks += 1
		assert(close_vec(two_forward["world"]["bodies"][id]["linear_velocity"], two_reverse["world"]["bodies"][id]["linear_velocity"], 1.0e-12)); checks += 1

	# ---------------------------------------------------------------------
	# Main FABRIC0.11 falsification experiment.
	# A/B is already a persistent constrained stack when incoming C appears.
	# ---------------------------------------------------------------------
	var run := Experiments.run_impact_sequence(false,false,false)
	var world: Dictionary = run["world"]
	var event: Dictionary = run["event"]
	var warm_results: Array = run["warm_results"]
	assert(warm_results.size() == 4); checks += 1
	assert(int(warm_results[0]["solver_stats"]["iterations"]) == 17); checks += 1
	assert(int(warm_results[0]["solver_stats"]["warm_start_contacts"]) == 0); checks += 1
	assert(int(warm_results[1]["solver_stats"]["iterations"]) == 1); checks += 1
	assert(int(warm_results[1]["solver_stats"]["warm_start_contacts"]) == 2); checks += 1
	assert(int(warm_results[1]["solver_stats"]["pcg_max_iterations_one_call"]) == 2); checks += 1
	assert(int(warm_results[1]["solver_stats"]["dense_materializations"]) == 0); checks += 1

	assert(bool(event["event_found"])); checks += 1
	assert(close(float(event["macrostep_start_time"]), 0.04, 1.0e-12)); checks += 1
	assert(close(float(event["macrostep_dt"]), 0.6, 1.0e-12)); checks += 1
	assert(int(event["localization_probes"]) == 36); checks += 1
	assert(event["start_contact_ids"] == ["pair:A|B","plane:floor|body:A"]); checks += 1
	assert(event["appeared"] == ["pair:B|C"]); checks += 1
	assert(event["disappeared"].is_empty()); checks += 1
	assert(close(float(event["event_dt"]), 0.35709945939307, 2.0e-12)); checks += 1
	assert(close(float(event["event_time"]), 0.39709945939307, 2.0e-12)); checks += 1

	# Continuous free-fall reference is deliberately reported as a numerical
	# integration audit, not falsely equated with the semi-implicit substep root.
	var continuous_reference := (-1.0 + sqrt(20.62)) / 9.81
	assert(close(continuous_reference, 0.3609505622728941, 1.0e-15)); checks += 1
	assert(float(event["event_dt"]) < continuous_reference); checks += 1
	assert(absf(float(event["event_dt"]) - continuous_reference) < 0.004); checks += 1

	# Old constrained graph stayed valid throughout localization.
	assert(absf(float(event["old_contact_gap_audit"]["pair:A|B"])) <= 1.0e-10); checks += 1
	assert(absf(float(event["old_contact_gap_audit"]["plane:floor|body:A"])) <= 1.0e-10); checks += 1
	assert(float(event["appeared_contact_gap_audit"]["pair:B|C"]) >= -1.0e-9); checks += 1
	assert(float(event["appeared_contact_gap_audit"]["pair:B|C"]) <= 1.01e-7); checks += 1

	# Graph recompiled at the same event instant: [A,B] -> [A,B,C].
	assert(event["start_islands"].size() == 1); checks += 1
	assert(event["start_islands"][0]["body_ids"] == ["A","B"]); checks += 1
	assert(event["start_islands"][0]["contact_ids"] == ["pair:A|B","plane:floor|body:A"]); checks += 1
	assert(event["event_islands"].size() == 1); checks += 1
	assert(event["event_islands"][0]["body_ids"] == ["A","B","C"]); checks += 1
	assert(event["event_islands"][0]["contact_ids"] == ["pair:A|B","pair:B|C","plane:floor|body:A"]); checks += 1
	assert(event["warm_contacts_preserved"] == ["pair:A|B","plane:floor|body:A"]); checks += 1

	var resolve: Dictionary = event["event_resolve"]
	assert(resolve["lifecycle"]["appeared"] == ["pair:B|C"]); checks += 1
	assert(resolve["lifecycle"]["persisted"] == ["pair:A|B","plane:floor|body:A"]); checks += 1
	assert(close(float(resolve["lifecycle"]["time"]), float(event["event_time"]), 1.0e-12)); checks += 1
	assert(int(resolve["solver_stats"]["island_count"]) == 1); checks += 1
	assert(int(resolve["solver_stats"]["warm_start_contacts"]) == 2); checks += 1
	assert(int(resolve["solver_stats"]["iterations"]) == 31); checks += 1
	assert(int(resolve["solver_stats"]["pcg_calls"]) == 31); checks += 1
	assert(int(resolve["solver_stats"]["pcg_iterations"]) == 93); checks += 1
	assert(int(resolve["solver_stats"]["pcg_max_iterations_one_call"]) == 3); checks += 1
	assert(int(resolve["solver_stats"]["sparse_effective_mass_entries"]) == 21); checks += 1
	assert(int(resolve["solver_stats"]["dense_effective_mass_capacity"]) == 81); checks += 1
	assert(int(resolve["solver_stats"]["sparse_effective_mass_entries"]) < int(resolve["solver_stats"]["dense_effective_mass_capacity"])); checks += 1
	assert(String(resolve["solver_stats"]["linear_backend"]) == "SPARSE_PCG"); checks += 1
	assert(int(resolve["solver_stats"]["dense_materializations"]) == 0); checks += 1
	assert(int(resolve["islands"][0]["active_contacts"]) == 3); checks += 1

	# Event impulse transfers incoming momentum through the whole existing stack.
	var event_impulses: Dictionary = resolve["islands"][0]["impulse_by_id"]
	assert(float(event_impulses["pair:B|C"].x) > 4.0); checks += 1
	assert(float(event_impulses["pair:A|B"].x) > 4.0); checks += 1
	assert(float(event_impulses["plane:floor|body:A"].x) > 4.0); checks += 1
	assert(resolve["islands"][0]["post_velocities"]["A"]["linear"].length() <= 2.0e-8); checks += 1
	assert(resolve["islands"][0]["post_velocities"]["B"]["linear"].length() <= 2.0e-8); checks += 1
	assert(resolve["islands"][0]["post_velocities"]["C"]["linear"].length() <= 2.0e-8); checks += 1

	# Only one lifecycle record at the event timestamp: no artificial same-time
	# "persist" record is emitted when remaining flow starts.
	var event_time_records := 0
	for history in world["contact_history"]:
		if absf(float(history["time"]) - float(event["event_time"])) <= 1.0e-12:
			event_time_records += 1
			assert(history["appeared"] == ["pair:B|C"]); checks += 1
	assert(event_time_records == 1); checks += 1

	# Remaining time uses the recompiled three-body island and stays sparse.
	assert(close(float(event["remaining_dt"]), 0.24290054060693, 2.0e-12)); checks += 1
	assert(int(event["continuation"]["substeps"]) == 25); checks += 1
	assert(int(event["continuation"]["aggregate"]["max_island_count"]) == 1); checks += 1
	assert(int(event["continuation"]["aggregate"]["island_solve_count"]) == 25); checks += 1
	assert(int(event["continuation"]["aggregate"]["pcg_calls"]) == 80); checks += 1
	assert(int(event["continuation"]["aggregate"]["pcg_iterations"]) == 234); checks += 1
	assert(int(event["continuation"]["aggregate"]["dense_materializations"]) == 0); checks += 1
	assert(String(event["continuation"]["aggregate"]["linear_backend"]) == "SPARSE_PCG"); checks += 1

	assert(close(float(world["time"]), 0.64, 1.0e-12)); checks += 1
	assert(close_vec(world["bodies"]["A"]["position"], Vector3(0.0,0.50000000002449,0.0), 3.0e-11)); checks += 1
	assert(close_vec(world["bodies"]["B"]["position"], Vector3(0.0,1.50000000004311,0.0), 3.0e-11)); checks += 1
	assert(close_vec(world["bodies"]["C"]["position"], Vector3(0.0,2.50000010002817,0.0), 3.0e-10)); checks += 1
	assert(world["bodies"]["A"]["linear_velocity"].length() <= 2.0e-8); checks += 1
	assert(world["bodies"]["B"]["linear_velocity"].length() <= 2.0e-8); checks += 1
	assert(world["bodies"]["C"]["linear_velocity"].length() <= 2.0e-8); checks += 1
	assert(world["contact_cache"].has("pair:A|B")); checks += 1
	assert(world["contact_cache"].has("pair:B|C")); checks += 1
	assert(world["contact_cache"].has("plane:floor|body:A")); checks += 1
	assert(int(world["contact_cache"]["pair:B|C"]["age_steps"]) >= 20); checks += 1
	assert(String(run["hash"]) == "86d76fc7a4b93bdd27030e1b343151d008e2c2e62ddfa72bdc11cf46d4f6133b"); checks += 1

	# ---------------------------------------------------------------------
	# Full event-localized history remains order-invariant under body insertion,
	# provider contact order and island scheduling permutations.
	# ---------------------------------------------------------------------
	var reversed := Experiments.run_impact_sequence(true,true,true)
	assert(String(reversed["hash"]) == String(run["hash"])); checks += 1
	assert(close(float(reversed["event"]["event_time"]), float(event["event_time"]), 1.0e-12)); checks += 1
	assert(reversed["event"]["appeared"] == event["appeared"]); checks += 1
	assert(reversed["event"]["event_islands"] == event["event_islands"]); checks += 1
	assert(JSON.stringify(reversed["world"]["contact_history"]) == JSON.stringify(world["contact_history"])); checks += 1
	for id in ["A","B","C"]:
		assert(close_vec(reversed["world"]["bodies"][id]["position"], world["bodies"][id]["position"], 1.0e-12)); checks += 1
		assert(close_vec(reversed["world"]["bodies"][id]["linear_velocity"], world["bodies"][id]["linear_velocity"], 1.0e-12)); checks += 1

	# ---------------------------------------------------------------------
	# Fail closed instead of silently using the generalized event API outside
	# the checkpoint's supported semantics.
	# ---------------------------------------------------------------------
	var empty_world := Fabric.new_world(Vector3(0.0,-9.81,0.0))
	assert(Fabric.add_body(empty_world, Fabric.new_sphere_body("free",1.0,0.5,Vector3(0,3,0),Vector3.ZERO))); checks += 1
	var no_existing := Fabric.advance_event_localized(empty_world, Experiments.floor_planes(), 0.2)
	assert(not bool(no_existing["ok"])); checks += 1
	assert(String(no_existing["code"]) == "EVENT011_REQUIRES_EXISTING_CONTACT_ISLAND"); checks += 1

	var bad_sparse := Experiments.build_resting_stack(false)
	var bad_contacts := Fabric.compile_contacts(bad_sparse, Experiments.floor_planes(), 1.0e-6)
	assert(bool(bad_contacts["ok"])); checks += 1
	var bad_result := Fabric.step_sparse(bad_sparse, bad_contacts["contacts"], 0.01, {"pcg_max_iterations":0})
	assert(not bool(bad_result["ok"])); checks += 1
	assert(String(bad_result["code"]) == "BAD_SPARSE_SOLVER_OPTIONS"); checks += 1

	print("FABRIC0.11 Event-Localized Sparse Islands Acceptance: PASS (%d assertions) event_t=%.12f event_dt=%.12f probes=%d warm=%d sparse=%d/%d pcg=%d/%d continuation_pcg=%d hash=%s schedule_hash=%s" % [
		checks,
		float(event["event_time"]),
		float(event["event_dt"]),
		int(event["localization_probes"]),
		int(resolve["solver_stats"]["warm_start_contacts"]),
		int(resolve["solver_stats"]["sparse_effective_mass_entries"]),
		int(resolve["solver_stats"]["dense_effective_mass_capacity"]),
		int(resolve["solver_stats"]["pcg_calls"]),
		int(resolve["solver_stats"]["pcg_iterations"]),
		int(event["continuation"]["aggregate"]["pcg_iterations"]),
		String(run["hash"]),
		String(two_forward["hash"]),
	])
	quit(0)
