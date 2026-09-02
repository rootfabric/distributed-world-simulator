extends SceneTree

const F = preload("res://scripts/research/fabric0/fabric0_full6dof_frictional_manifold_v1.gd")
const E = preload("res://scripts/research/fabric0/fabric0_full6dof_frictional_manifold_experiments_v1.gd")
const M = preload("res://scripts/research/fabric0/fabric0_full6dof_model_v1.gd")

func close(a: float, b: float, tol: float = 1.0e-10) -> bool:
	return absf(a - b) <= tol

func vec3_close(a: Vector3, b: Vector3, tol: float = 1.0e-10) -> bool:
	return (a - b).length() <= tol

func max_event_error(run: Dictionary, reference: Array) -> float:
	var result := 0.0
	for i in range(reference.size()):
		result = maxf(result, absf(float(run["world"]["events"][i]["time"]) - float(reference[i])))
	return result

func max_state_error(run: Dictionary, reference: Array) -> float:
	var result := 0.0
	for i in range(reference.size()):
		result = maxf(result, absf(float(run["world"]["state"][i]) - float(reference[i])))
	return result

func event_losses(world: Dictionary) -> float:
	var result := 0.0
	for event in world["events"]:
		if String(event["kind"]) == "IMPACT":
			result += maxf(0.0, -float(event["kinetic_delta"]))
		else:
			result += maxf(0.0, -float(event["transition_kinetic_delta"]))
	return result

func energy_closure(run: Dictionary) -> float:
	return absf(-float(run["result"]["energy_delta"]) - float(run["result"]["friction_dissipation"]) - event_losses(run["world"]))

func _init() -> void:
	var checks := 0

	# --- Unified sliding + feature-manifold convergence gate ---
	var reference := E.sliding_run(1.0e-12, 0.315)
	assert(bool(reference["result"]["ok"])); checks += 1
	assert(reference["world"]["events"].size() == 2); checks += 1
	var ref_times: Array = []
	for event in reference["world"]["events"]:
		ref_times.append(float(event["time"]))
	var ref_state: Array = reference["world"]["state"].duplicate(true)

	var coarse := E.sliding_run(1.0e-7, 0.315)
	var fine := E.sliding_run(1.0e-9, 0.315)
	var finer := E.sliding_run(1.0e-11, 0.315)
	for run in [coarse, fine, finer]:
		assert(bool(run["result"]["ok"])); checks += 1
		assert(run["world"]["events"].size() == 2); checks += 1

	var event_error_coarse := max_event_error(coarse, ref_times)
	var event_error_fine := max_event_error(fine, ref_times)
	var event_error_finer := max_event_error(finer, ref_times)
	assert(event_error_fine < event_error_coarse); checks += 1
	assert(event_error_finer < event_error_fine); checks += 1
	assert(event_error_coarse < 7.0e-8); checks += 1
	assert(event_error_fine < 2.0e-9); checks += 1
	assert(event_error_finer < 4.0e-11); checks += 1

	var state_error_coarse := max_state_error(coarse, ref_state)
	var state_error_fine := max_state_error(fine, ref_state)
	var state_error_finer := max_state_error(finer, ref_state)
	assert(state_error_fine < state_error_coarse); checks += 1
	assert(state_error_finer < state_error_fine); checks += 1
	assert(state_error_coarse < 6.0e-7); checks += 1
	assert(state_error_fine < 1.4e-8); checks += 1
	assert(state_error_finer < 3.0e-10); checks += 1

	var closure_coarse := energy_closure(coarse)
	var closure_fine := energy_closure(fine)
	var closure_finer := energy_closure(finer)
	assert(closure_fine < closure_coarse); checks += 1
	assert(closure_finer < closure_fine); checks += 1
	assert(closure_coarse < 4.0e-7); checks += 1
	assert(closure_fine < 1.6e-8); checks += 1
	assert(closure_finer < 4.0e-10); checks += 1

	var w: Dictionary = fine["world"]
	var r: Dictionary = fine["result"]
	assert(close(float(w["time"]), 0.315, 1.0e-13)); checks += 1
	assert(close(float(w["events"][0]["time"]), 0.25850330043665, 2.0e-13)); checks += 1
	assert(close(float(w["events"][1]["time"]), 0.31322331523056, 2.0e-13)); checks += 1
	assert(int(r["accepted_steps"]) == 24); checks += 1
	assert(int(r["rejected_steps"]) == 1); checks += 1
	assert(float(r["min_normal_force"]) > 5.0); checks += 1
	assert(close(float(r["max_cone_ratio"]), 1.0, 1.0e-12)); checks += 1
	assert(int(r["contact_force_calls"]) == 22); checks += 1
	assert(int(r["slide_force_calls"]) == 22); checks += 1
	assert(int(r["stick_force_calls"]) == 0); checks += 1
	assert(float(r["max_gap"]) <= 1.0e-13); checks += 1
	assert(float(r["max_quat_error"]) <= 1.0e-14); checks += 1
	assert(float(r["friction_dissipation"]) > 1.2); checks += 1
	assert(event_losses(w) > 4.0); checks += 1
	assert(float(r["energy_delta"]) < -5.2); checks += 1
	assert(energy_closure(fine) < 1.6e-8); checks += 1
	assert(String(r["state_hash"]) == "2b52dc944cdc4a48152265db3e456c629bfb5f66969850563e39ec188147efe7"); checks += 1

	var expected_paths := [
		["plane|C|v:---", "plane|C|edge:0:v:+--:v:---", "plane|C|v:+--"],
		["plane|C|v:+--", "plane|C|edge:1:v:++-:v:+--", "plane|C|v:++-"],
	]
	for i in range(2):
		var event: Dictionary = w["events"][i]
		assert(String(event["kind"]) == "FEATURE_FIXED_POINT"); checks += 1
		assert(bool(event["fixed_point"])); checks += 1
		assert(int(event["iterations"]) == 3); checks += 1
		assert(int(event["topology_mutations"]) == 2); checks += 1
		assert(event["point_counts"] == [1,2,1]); checks += 1
		assert(event["path"] == expected_paths[i]); checks += 1
		assert(bool(event["transition_active"])); checks += 1
		assert(String(event["transition_mode"]) == "slide"); checks += 1
		assert(close(float(event["transition_cone_ratio"]), 1.0, 1.0e-12)); checks += 1
		assert(float(event["transition_linear_momentum_error"]) <= 1.0e-12); checks += 1
		assert(float(event["transition_angular_momentum_error"]) <= 1.0e-12); checks += 1
		assert(float(event["transition_kinetic_delta"]) < 0.0); checks += 1
		assert(vec3_close(Vector3(event["warm_force_before"]), Vector3(event["warm_force_remapped"]), 1.0e-12)); checks += 1
		var expected_warm := Vector3(event["warm_impulse_remapped"]) + Vector3(event["transition_impulse"])
		assert(vec3_close(expected_warm, Vector3(event["warm_impulse_after"]), 1.0e-12)); checks += 1

	# Full 6DOF is exercised: all translation, quaternion and angular components are live.
	var base := E.sliding_world()
	var final_state: Array = w["state"]
	assert(absf(float(final_state[0]) - float(base["state"][0])) > 0.1); checks += 1
	assert(absf(float(final_state[1]) - float(base["state"][1])) > 0.1); checks += 1
	assert(absf(float(final_state[2]) - float(base["state"][2])) > 0.01); checks += 1
	for qi in range(3,7):
		assert(absf(float(final_state[qi])) > 1.0e-4); checks += 1
	for vi in range(7,10):
		assert(absf(float(final_state[vi])) > 1.0e-2); checks += 1
	for wi in range(10,13):
		assert(absf(float(final_state[wi])) > 1.0e-2); checks += 1
	var q_final := M.quat(final_state)
	assert(close(q_final.length(), 1.0, 1.0e-14)); checks += 1
	var inertia: Vector3 = w["inertia_body"]
	assert(not close(inertia.x, inertia.y)); checks += 1
	assert(not close(inertia.y, inertia.z)); checks += 1
	assert(not close(inertia.x, inertia.z)); checks += 1

	# Active unilateral + Coulomb cone state.
	var slide_probe := F.force_probe(w, w["state"], "slide")
	assert(bool(slide_probe["ok"]) and bool(slide_probe["active"])); checks += 1
	assert(String(slide_probe["mode"]) == "slide"); checks += 1
	assert(float(slide_probe["normal"]) > 0.0); checks += 1
	assert(close(float(slide_probe["cone_ratio"]), 1.0, 1.0e-12)); checks += 1
	var final_feature := M.current_feature(w)
	var final_geom := M.contact_geometry(w, w["state"], final_feature)
	assert(absf(float(final_geom["gap"])) <= 1.0e-13); checks += 1
	assert(absf(float(final_geom["gap"]) * float(slide_probe["normal"])) <= 1.0e-13); checks += 1

	# --- Oblique free-flight impact + feature-transition impulse ---
	var impact := E.impact_run(1.0e-6, 0.305)
	assert(bool(impact["result"]["ok"])); checks += 1
	assert(impact["world"]["events"].size() == 2); checks += 1
	var impact_event: Dictionary = impact["world"]["events"][0]
	var feature_event: Dictionary = impact["world"]["events"][1]
	assert(String(impact_event["kind"]) == "IMPACT"); checks += 1
	assert(close(float(impact_event["time"]), 0.16920086866594, 2.0e-12)); checks += 1
	assert(String(impact_event["feature"]) == "plane|C|v:---"); checks += 1
	assert(String(impact_event["mode"]) == "stick"); checks += 1
	assert(float(impact_event["cone_ratio"]) < 0.84); checks += 1
	assert(float(impact_event["cone_ratio"]) > 0.82); checks += 1
	assert(float(impact_event["linear_momentum_error"]) <= 1.0e-12); checks += 1
	assert(float(impact_event["angular_momentum_error"]) <= 1.0e-12); checks += 1
	assert(float(impact_event["kinetic_delta"]) < -25.0); checks += 1
	assert(String(feature_event["kind"]) == "FEATURE_FIXED_POINT"); checks += 1
	assert(close(float(feature_event["time"]), 0.29569829052867, 2.0e-12)); checks += 1
	assert(String(feature_event["transition_mode"]) == "slide"); checks += 1
	assert(close(float(feature_event["transition_cone_ratio"]), 1.0, 1.0e-12)); checks += 1
	assert(float(feature_event["transition_linear_momentum_error"]) <= 1.0e-12); checks += 1
	assert(float(feature_event["transition_angular_momentum_error"]) <= 1.0e-12); checks += 1
	assert(float(feature_event["transition_kinetic_delta"]) < -4.0); checks += 1
	assert(energy_closure(impact) < 2.0e-7); checks += 1
	assert(String(impact["result"]["state_hash"]) == "de5584cb0f2da6b788e8873eac1ff99e2a8bedd1f71c56727fe809eaae29efe9"); checks += 1

	# --- Torque-free full 3-axis rigid-body invariant audit ---
	var free_rotation := E.free_rotation_run(1.0e-10, 0.6)
	assert(bool(free_rotation["result"]["ok"])); checks += 1
	assert(free_rotation["world"]["events"].is_empty()); checks += 1
	assert((Vector3(free_rotation["p1"]) - Vector3(free_rotation["p0"])).length() <= 1.0e-13); checks += 1
	assert((Vector3(free_rotation["l1"]) - Vector3(free_rotation["l0"])).length() < 1.0e-9); checks += 1
	assert(absf(float(free_rotation["e1"]) - float(free_rotation["e0"])) < 2.0e-10); checks += 1
	var free_q := M.quat(free_rotation["world"]["state"])
	assert(close(free_q.length(), 1.0, 1.0e-14)); checks += 1
	var free_w := M.omega(free_rotation["world"]["state"])
	assert(absf(free_w.x) > 0.1 and absf(free_w.y) > 0.1 and absf(free_w.z) > 0.1); checks += 1
	assert(String(free_rotation["result"]["state_hash"]) == "e57d66d29b7de53757f5b4ba2d0d2a26f3c2a342086a63aebc93726b40666a99"); checks += 1

	# --- Feature hierarchy and lineage: vertex -> edge -> face ---
	var chain := E.feature_chain_probe()
	assert(String(chain["vertex"]["type"]) == "vertex" and int(chain["vertex"]["point_count"]) == 1); checks += 1
	assert(String(chain["edge"]["type"]) == "edge" and int(chain["edge"]["point_count"]) == 2); checks += 1
	assert(String(chain["face"]["type"]) == "face" and int(chain["face"]["point_count"]) == 4); checks += 1
	assert(chain["face"]["zero_axes"] == [0,1]); checks += 1
	assert(vec3_close(Vector3(chain["edge_value"]), Vector3(chain["value"]), 1.0e-15)); checks += 1
	assert(vec3_close(Vector3(chain["face_value"]), Vector3(chain["value"]), 1.0e-15)); checks += 1
	assert(vec3_close(Vector3(chain["face"]["local_point"]), Vector3(0,0,-0.25), 1.0e-15)); checks += 1

	# --- Static friction and unilateral separation probes ---
	var stick := E.stick_probe()
	assert(bool(stick["ok"]) and bool(stick["active"])); checks += 1
	assert(String(stick["mode"]) == "stick"); checks += 1
	assert(float(stick["normal"]) > 12.0); checks += 1
	assert(float(stick["cone_ratio"]) < 0.47); checks += 1
	assert(Vector2(Vector3(stick["vc"]).x, Vector3(stick["vc"]).y).length() <= 1.0e-12); checks += 1
	var separated := E.separation_probe()
	assert(bool(separated["ok"]) and not bool(separated["active"])); checks += 1
	assert(String(separated["mode"]) == "separated"); checks += 1
	assert(close(float(separated["normal"]), 0.0, 1.0e-15)); checks += 1
	assert(float(separated["signed_normal"]) < -4.0); checks += 1
	assert(Vector3(separated["free_accel"]).z > 5.0); checks += 1
	var free_world := F.new_world()
	assert(M.free_gap(free_world, free_world["state"]) > 0.5); checks += 1
	assert(not bool(free_world["contact_active"])); checks += 1

	# --- Actual Thread parallel contact-island audit ---
	var physical_hash_before := F.world_hash(w)
	var parallel_forward := F.parallel_contact_audit(w, false)
	var parallel_reverse := F.parallel_contact_audit(w, true)
	assert(bool(parallel_forward["ok"]) and bool(parallel_reverse["ok"])); checks += 1
	assert(int(parallel_forward["threads_started"]) == 2 and int(parallel_reverse["threads_started"]) == 2); checks += 1
	assert(String(parallel_forward["hash"]) == "526844a8ca0629969477f2942853b3e7b9617b391e39fc54147d30d38852773c"); checks += 1
	assert(String(parallel_reverse["hash"]) == String(parallel_forward["hash"])); checks += 1
	assert(parallel_forward["results"].size() == 2); checks += 1
	for result in parallel_forward["results"]:
		assert(bool(result["active"])); checks += 1
		assert(String(result["mode"]) == "slide"); checks += 1
		assert(close(float(result["cone_ratio"]), 1.0, 1.0e-12)); checks += 1
	assert(F.world_hash(w) == physical_hash_before); checks += 1

	# --- Deterministic replay ---
	var replay := E.sliding_run(1.0e-9, 0.315)
	assert(String(replay["result"]["state_hash"]) == String(r["state_hash"])); checks += 1
	assert(JSON.stringify(replay["world"]["events"]) == JSON.stringify(w["events"])); checks += 1

	# --- Fail closed ---
	var bad_time_world := F.new_world()
	var bad_time := F.advance(bad_time_world, 0.1, {"atol":0.0})
	assert(not bool(bad_time["ok"]) and String(bad_time["code"]) == "BAD_ADAPTIVE_OPTIONS"); checks += 1
	var api = F.ContactAPI()
	var bad_mu: Dictionary = api.validate_contract(Vector3(1,1,1), 1.0, -0.1)
	var bad_mass: Dictionary = api.validate_contract(Vector3(1,1,1), 0.0, 0.2)
	var bad_inertia: Dictionary = api.validate_contract(Vector3(1,-1,1), 1.0, 0.2)
	assert(not bool(bad_mu["ok"]) and String(bad_mu["code"]) == "BAD_FRICTION_COEFFICIENT"); checks += 1
	assert(not bool(bad_mass["ok"]) and String(bad_mass["code"]) == "BAD_MASS"); checks += 1
	assert(not bool(bad_inertia["ok"]) and String(bad_inertia["code"]) == "BAD_INERTIA"); checks += 1

	print("FABRIC0.14 Full 6DOF Frictional Feature Manifold Acceptance: PASS (%d assertions) slide_events=(%.12f,%.12f) refine=(%s,%s,%s) state_refine=(%s,%s,%s) closure=(%s,%s,%s) impact=(%.12f,%.12f) free_dL=%s parallel=%s hash=%s" % [
		checks,
		float(w["events"][0]["time"]), float(w["events"][1]["time"]),
		String.num_scientific(event_error_coarse), String.num_scientific(event_error_fine), String.num_scientific(event_error_finer),
		String.num_scientific(state_error_coarse), String.num_scientific(state_error_fine), String.num_scientific(state_error_finer),
		String.num_scientific(closure_coarse), String.num_scientific(closure_fine), String.num_scientific(closure_finer),
		float(impact_event["time"]), float(feature_event["time"]),
		String.num_scientific((Vector3(free_rotation["l1"]) - Vector3(free_rotation["l0"])).length()),
		String(parallel_forward["hash"]), String(r["state_hash"])
	])
	quit(0)
