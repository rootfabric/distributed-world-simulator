extends SceneTree

const Fabric = preload("res://scripts/research/fabric0/fabric0_adaptive_multievent_manifold_v1.gd")
const Experiments = preload("res://scripts/research/fabric0/fabric0_adaptive_multievent_manifold_experiments_v1.gd")

func close(a: float, b: float, tolerance: float = 1.0e-10) -> bool:
	return absf(a-b) <= tolerance

func max_event_error(run: Dictionary, references: Array) -> float:
	var events: Array = run["system"]["events"]
	var result := 0.0
	for i in range(references.size()):
		result = maxf(result, absf(float(events[i]["time"]) - float(references[i])))
	return result

func _init() -> void:
	var checks := 0

	# ---------------------------------------------------------------------
	# Adaptive constrained manifold integration + convergence under refinement.
	# ---------------------------------------------------------------------
	var references := [PI/16.0, 5.0*PI/16.0]
	var analytic := Fabric.analytic_zero_times(-0.3,1.2,4.0,1.2)
	assert(analytic.size() == 2); checks += 1
	assert(close(float(analytic[0]), float(references[0]), 1.0e-15)); checks += 1
	assert(close(float(analytic[1]), float(references[1]), 1.0e-15)); checks += 1

	var coarse := Experiments.run_tolerance(1.0e-5)
	var medium := Experiments.run_tolerance(1.0e-7)
	var fine := Experiments.run_tolerance(1.0e-9)
	var ultra := Experiments.run_tolerance(1.0e-11)
	for run in [coarse, medium, fine, ultra]:
		assert(run["system"]["events"].size() == 2); checks += 1
		assert(float(run["result"]["max_constraint_residual"]) <= 1.0e-12); checks += 1
		assert(String(run["result"]["state_hash"]).length() == 64); checks += 1

	var err_coarse := max_event_error(coarse,references)
	var err_medium := max_event_error(medium,references)
	var err_fine := max_event_error(fine,references)
	var err_ultra := max_event_error(ultra,references)
	assert(err_medium < err_coarse); checks += 1
	assert(err_fine < err_medium); checks += 1
	assert(err_ultra < err_fine); checks += 1
	assert(err_coarse < 2.0e-5); checks += 1
	assert(err_medium < 1.0e-6); checks += 1
	assert(err_fine < 2.0e-8); checks += 1
	assert(err_ultra < 5.0e-10); checks += 1
	assert(int(coarse["result"]["accepted_steps"]) < int(medium["result"]["accepted_steps"])); checks += 1
	assert(int(medium["result"]["accepted_steps"]) < int(fine["result"]["accepted_steps"])); checks += 1
	assert(int(fine["result"]["accepted_steps"]) < int(ultra["result"]["accepted_steps"])); checks += 1
	assert(absf(float(medium["result"]["energy_drift"])) < absf(float(coarse["result"]["energy_drift"]))); checks += 1
	assert(absf(float(fine["result"]["energy_drift"])) < absf(float(medium["result"]["energy_drift"]))); checks += 1
	assert(absf(float(ultra["result"]["energy_drift"])) < absf(float(fine["result"]["energy_drift"]))); checks += 1
	assert(absf(float(ultra["result"]["energy_drift"])) < 1.0e-9); checks += 1

	# Exact numerical references from the 1e-9 gate.
	assert(close(float(fine["system"]["events"][0]["time"]), 0.19634954475054, 2.0e-14)); checks += 1
	assert(close(float(fine["system"]["events"][1]["time"]), 0.98174771949769, 2.0e-14)); checks += 1
	assert(int(fine["result"]["accepted_steps"]) == 68); checks += 1
	assert(int(fine["result"]["rejected_steps"]) == 1); checks += 1
	assert(close(float(fine["result"]["energy_drift"]), -7.03302e-9, 5.0e-14)); checks += 1

	# ---------------------------------------------------------------------
	# Two physical event instants; each performs two same-time manifold topology
	# mutations and reaches a fixed point on the third event iteration.
	# ---------------------------------------------------------------------
	var fs: Dictionary = fine["system"]
	var event1: Dictionary = fs["events"][0]
	var event2: Dictionary = fs["events"][1]
	assert(int(event1["direction"]) == 1); checks += 1
	assert(int(event2["direction"]) == -1); checks += 1
	for event in [event1,event2]:
		assert(bool(event["fixed_point"])); checks += 1
		assert(int(event["iterations"]) == 3); checks += 1
		assert(int(event["topology_mutations"]) == 2); checks += 1
		assert(event["transitions"].size() == 2); checks += 1
		assert(int(event["bisection_iterations"]) >= 30); checks += 1

	assert(event1["transitions"][0]["old_ids"] == ["floor|vertex:BR","wall|vertex:BL"]); checks += 1
	assert(event1["transitions"][0]["new_ids"] == ["floor|edge:bottom","wall|edge:left"]); checks += 1
	assert(event1["transitions"][0]["appeared"] == ["floor|edge:bottom","wall|edge:left"]); checks += 1
	assert(event1["transitions"][0]["disappeared"] == ["floor|vertex:BR","wall|vertex:BL"]); checks += 1
	assert(event1["transitions"][1]["new_ids"] == ["floor|vertex:BL","wall|vertex:TL"]); checks += 1
	assert(event1["final_contact_ids"] == ["floor|vertex:BL","wall|vertex:TL"]); checks += 1
	assert(close(float(event1["final_warm_cache"]["floor|vertex:BL"]),2.0)); checks += 1
	assert(close(float(event1["final_warm_cache"]["wall|vertex:TL"]),3.0)); checks += 1

	assert(event2["transitions"][0]["old_ids"] == ["floor|vertex:BL","wall|vertex:TL"]); checks += 1
	assert(event2["transitions"][0]["new_ids"] == ["floor|edge:bottom","wall|edge:left"]); checks += 1
	assert(event2["transitions"][1]["new_ids"] == ["floor|vertex:BR","wall|vertex:BL"]); checks += 1
	assert(event2["final_contact_ids"] == ["floor|vertex:BR","wall|vertex:BL"]); checks += 1
	assert(close(float(event2["final_warm_cache"]["floor|vertex:BR"]),2.0)); checks += 1
	assert(close(float(event2["final_warm_cache"]["wall|vertex:BL"]),3.0)); checks += 1
	assert(Fabric.current_contacts(fs)[0]["id"] == "floor|vertex:BR"); checks += 1
	assert(Fabric.current_contacts(fs)[1]["id"] == "wall|vertex:BL"); checks += 1
	assert(close(float(fs["warm_cache"]["floor|vertex:BR"]),2.0)); checks += 1
	assert(close(float(fs["warm_cache"]["wall|vertex:BL"]),3.0)); checks += 1

	# Generic lineage remap handles explicit feature split and merge.
	var split := Fabric.synthetic_split_remap(4.0)
	assert(close(float(split["floor|vertex:BL"]),2.0)); checks += 1
	assert(close(float(split["floor|vertex:BR"]),2.0)); checks += 1
	var merge := Fabric.synthetic_merge_remap(2.0,3.0)
	assert(close(float(merge["floor|edge:bottom"]),5.0)); checks += 1

	# Algebraic center satisfies the two selected corner constraints at arbitrary
	# orientation on both sides of the degenerate event.
	var neg := Fabric.new_corner_system(-0.2,1.0,4.0,0.5,0.3)
	var pos := Fabric.new_corner_system(0.2,1.0,4.0,0.5,0.3)
	for test_system in [neg,pos]:
		var gaps := Fabric.contact_gaps(test_system,Fabric.current_contacts(test_system))
		for value in gaps.values():
			assert(absf(float(value)) <= 1.0e-14); checks += 1

	# Deterministic replay of the adaptive multi-event history.
	var replay := Experiments.run_tolerance(1.0e-9)
	assert(String(replay["result"]["state_hash"]) == String(fine["result"]["state_hash"])); checks += 1
	assert(JSON.stringify(replay["system"]["events"]) == JSON.stringify(fs["events"])); checks += 1

	# ---------------------------------------------------------------------
	# Real Thread-based parallel sparse island execution + pattern/preconditioner
	# cache. Thread spawn order is explicitly reversed on the second solve.
	# ---------------------------------------------------------------------
	var solver := Fabric.new()
	var cache := Fabric.new_pattern_cache()
	var tasks := Experiments.parallel_tasks(1.0)
	var cold := solver.solve_islands_parallel(tasks,cache,false)
	assert(bool(cold["ok"])); checks += 1
	assert(bool(cold["parallel"])); checks += 1
	assert(int(cold["threads_started"]) == 2); checks += 1
	assert(int(cold["cache_hits"]) == 0); checks += 1
	assert(int(cold["cache_misses"]) == 2); checks += 1
	assert(String(cold["hash"]) == "40635ad181b0273659ffd0dacae622b7b7249427d5073c2f9ffb5913f43f7fe0"); checks += 1
	assert(cold["results"][0]["id"] == "alpha"); checks += 1
	assert(cold["results"][1]["id"] == "beta"); checks += 1
	assert(int(cold["results"][0]["iterations"]) == 3); checks += 1
	assert(int(cold["results"][1]["iterations"]) == 3); checks += 1
	assert(close(float(cold["results"][0]["x"][0]),2.0/9.0,1.0e-14)); checks += 1
	assert(close(float(cold["results"][0]["x"][1]),1.0/9.0,1.0e-14)); checks += 1
	assert(close(float(cold["results"][0]["x"][2]),13.0/9.0,1.0e-14)); checks += 1

	var warm_reverse := solver.solve_islands_parallel(tasks,cache,true)
	assert(bool(warm_reverse["ok"])); checks += 1
	assert(int(warm_reverse["threads_started"]) == 2); checks += 1
	assert(int(warm_reverse["cache_hits"]) == 2); checks += 1
	assert(int(warm_reverse["cache_misses"]) == 0); checks += 1
	assert(String(warm_reverse["hash"]) == String(cold["hash"])); checks += 1
	assert(int(cache["entries"].size()) == 2); checks += 1
	assert(int(cache["hits"]) == 2); checks += 1
	assert(int(cache["misses"]) == 2); checks += 1

	# Same sparse pattern, changed coefficients: cached preconditioner is reused as
	# a numerical hint, while PCG still solves the new matrix to tolerance.
	var changed := solver.solve_islands_parallel(Experiments.parallel_tasks(1.1),cache,true)
	assert(bool(changed["ok"])); checks += 1
	assert(int(changed["cache_hits"]) == 2); checks += 1
	assert(int(changed["cache_misses"]) == 0); checks += 1
	assert(String(changed["hash"]) != String(cold["hash"])); checks += 1
	for result in changed["results"]:
		assert(float(result["residual"]) <= 1.0e-11); checks += 1
		assert(bool(result["cache_hit"])); checks += 1

	# A completely fresh cache with reverse spawning yields the exact cold hash.
	var reverse_fresh_cache := Fabric.new_pattern_cache()
	var reverse_fresh := solver.solve_islands_parallel(tasks,reverse_fresh_cache,true)
	assert(bool(reverse_fresh["ok"])); checks += 1
	assert(String(reverse_fresh["hash"]) == String(cold["hash"])); checks += 1

	# ---------------------------------------------------------------------
	# Sleep/wake is derived computational state: quiet history can sleep an island;
	# physical motion immediately wakes it. It is not part of system_hash().
	# ---------------------------------------------------------------------
	var sleep := Fabric.new_sleep_tracker()
	var q1 := Fabric.update_sleep_state(sleep,"island:A",0.0,0.0)
	var q2 := Fabric.update_sleep_state(sleep,"island:A",0.0,0.0)
	var q3 := Fabric.update_sleep_state(sleep,"island:A",0.0,0.0)
	assert(not bool(q1["sleeping"])); checks += 1
	assert(not bool(q2["sleeping"])); checks += 1
	assert(bool(q3["sleeping"])); checks += 1
	assert(bool(q3["slept"])); checks += 1
	var wake := Fabric.update_sleep_state(sleep,"island:A",1.0,0.0)
	assert(not bool(wake["sleeping"])); checks += 1
	assert(bool(wake["woke"])); checks += 1
	assert(int(wake["quiet_steps"]) == 0); checks += 1

	# Fail closed on invalid adaptive contract / invalid cache pattern.
	var bad := Fabric.new_corner_system()
	var bad_step := Fabric.advance_adaptive(bad,0.1,{"atol":0.0})
	assert(not bool(bad_step["ok"])); checks += 1
	assert(String(bad_step["code"]) == "BAD_ADAPTIVE_OPTIONS"); checks += 1
	var bad_cache := Fabric.new_pattern_cache()
	var bad_prep := Fabric.prepare_cached_preconditioner(bad_cache,"bad",[{0:0.0}])
	assert(not bool(bad_prep["ok"])); checks += 1
	assert(String(bad_prep["code"]) == "PATTERN_NONPOSITIVE_DIAGONAL"); checks += 1

	print("FABRIC0.12 Adaptive Multi-Event Manifold Acceptance: PASS (%d assertions) events=(%.12f,%.12f) errors=(%s,%s,%s,%s) steps=%d/%d energy=%s manifold_mutations=%d parallel_threads=%d cache=%d/%d hash=%s parallel_hash=%s" % [
		checks,
		float(fine["system"]["events"][0]["time"]),
		float(fine["system"]["events"][1]["time"]),
		str(err_coarse),str(err_medium),str(err_fine),str(err_ultra),
		int(fine["result"]["accepted_steps"]),int(fine["result"]["rejected_steps"]),
		str(float(fine["result"]["energy_drift"])),
		int(event1["topology_mutations"])+int(event2["topology_mutations"]),
		int(cold["threads_started"]),int(cache["hits"]),int(cache["misses"]),
		String(fine["result"]["state_hash"]),String(cold["hash"])
	])
	quit(0)
