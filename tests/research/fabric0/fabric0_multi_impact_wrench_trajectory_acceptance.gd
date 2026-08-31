extends SceneTree

const T=preload("res://scripts/research/fabric0/fabric0_multi_impact_wrench_trajectory_v1.gd")
const E=preload("res://scripts/research/fabric0/fabric0_multi_impact_wrench_trajectory_experiments_v1.gd")

func close(a:float,b:float,tolerance:float)->bool:
	return absf(a-b)<=tolerance

func _init()->void:
	var checks:=0
	var refinement:=E.refinement_probe()
	assert(bool(refinement["ok"]));checks+=1
	var coarse:Dictionary=refinement["coarse"]
	var medium:Dictionary=refinement["medium"]
	var fine:Dictionary=refinement["fine"]
	var reference:Dictionary=refinement["reference"]

	# The integrated world has two causally ordered simultaneous event sets.
	for run in [coarse,medium,fine,reference]:
		assert(int(run["events"].size())==2);checks+=1
		assert(run["events"][0]["pair_ids"]==["C|L","C|R"]);checks+=1
		assert(run["events"][1]["pair_ids"]==["P|Q","Q|S"]);checks+=1
		assert(int(run["events"][0]["normal_rows"])==8);checks+=1
		assert(int(run["events"][1]["normal_rows"])==8);checks+=1
		assert(float(run["events"][0]["time"])<float(run["events"][1]["time"]));checks+=1
		assert(float(run["events"][0]["normal_wrench_cross_drift"])<5.0e-10);checks+=1
		assert(float(run["events"][1]["normal_wrench_cross_drift"])<5.0e-10);checks+=1
		assert(float(run["events"][0]["initial_reopened_normal_residual"])>0.3);checks+=1
		assert(float(run["events"][1]["initial_reopened_normal_residual"])>0.3);checks+=1
		assert(float(run["events"][0]["wrench_energy_delta"])<-0.6);checks+=1
		assert(float(run["events"][1]["wrench_energy_delta"])<-0.6);checks+=1
		assert(float(run["events"][0]["max_tangent_impulse"])>0.3);checks+=1
		assert(float(run["events"][1]["max_tangent_impulse"])>0.3);checks+=1
		assert(float(run["events"][0]["max_moment_impulse"])>0.004);checks+=1
		assert(float(run["events"][1]["max_moment_impulse"])>0.003);checks+=1
		assert(float(run["events"][0]["max_cross_patch_coupling"])>3.0);checks+=1
		assert(float(run["events"][1]["max_cross_patch_coupling"])>3.0);checks+=1
		assert(float(run["events"][0]["wrench_symmetry_error"])<1.0e-14);checks+=1
		assert(float(run["events"][1]["wrench_symmetry_error"])<1.0e-14);checks+=1
		assert(float(run["events"][0]["wrench_ledger_error"])<1.0e-13);checks+=1
		assert(float(run["events"][1]["wrench_ledger_error"])<1.0e-13);checks+=1
		assert(float(run["events"][0]["event_energy_ledger_error"])<1.0e-13);checks+=1
		assert(float(run["events"][1]["event_energy_ledger_error"])<1.0e-13);checks+=1
		assert(String(run["events"][0]["wrench_modes"]["C|L"]["tangent"])=="slide");checks+=1
		assert(String(run["events"][1]["wrench_modes"]["P|Q"]["tangent"])=="slide");checks+=1
		assert(float(run["linear_momentum_error"])<1.0e-13);checks+=1
		assert(float(run["angular_momentum_error"])<1.0e-13);checks+=1
		assert(float(run["energy_ledger_error"])<1.0e-13);checks+=1
		assert(close(float(run["time"]),0.55,1.0e-15));checks+=1

	# Reference event identity is the intended two-level temporal structure.
	assert(close(float(reference["events"][0]["time"]),0.5,1.0e-11));checks+=1
	assert(close(float(reference["events"][1]["time"]),0.5002,1.0e-11));checks+=1
	assert(close(float(reference["initial_energy"]),9.66625,1.0e-12));checks+=1
	assert(close(float(reference["final_energy"]),2.07687223207214,2.0e-11));checks+=1
	assert(float(reference["events"][0]["outer_iterations"])<=16);checks+=1
	assert(float(reference["events"][1]["outer_iterations"])<=16);checks+=1
	assert(not bool(reference["events"][0]["persistent_after"]));checks+=1
	assert(not bool(reference["events"][1]["persistent_after"]));checks+=1

	# Whole-state and event-time refinement converge strictly to the 1e-11 reference.
	var state_errors:Array=refinement["state_errors"]
	var event_errors:Array=refinement["event_errors"]
	assert(float(state_errors[1])<float(state_errors[0]));checks+=1
	assert(float(state_errors[2])<float(state_errors[1]));checks+=1
	assert(float(event_errors[1])<float(event_errors[0]));checks+=1
	assert(float(event_errors[2])<float(event_errors[1]));checks+=1
	assert(float(state_errors[0])<8.0e-6);checks+=1
	assert(float(state_errors[2])<7.0e-10);checks+=1
	assert(float(event_errors[0])<3.0e-6);checks+=1
	assert(float(event_errors[2])<3.0e-10);checks+=1

	# Exact replay and caller/member reversal do not alter event identity or final state.
	var determinism:=E.determinism_probe(1.0e-9)
	assert(bool(determinism["ok"]));checks+=1
	for key in ["replay_state_error","reverse_body_state_error","reverse_member_state_error","replay_event_error","reverse_body_event_error","reverse_member_event_error"]:
		assert(float(determinism[key])==0.0);checks+=1
	assert(String(determinism["replay"]["signature"])==String(determinism["forward"]["signature"]));checks+=1
	assert(String(determinism["reverse_bodies"]["signature"])==String(determinism["forward"]["signature"]));checks+=1
	assert(String(determinism["reverse_members"]["signature"])==String(determinism["forward"]["signature"]));checks+=1

	# A coarse temporal grouping that aliases the two physical event sets is rejected before any jump.
	var under:=E.under_refined_probe()
	assert(not bool(under["ok"]));checks+=1
	assert(String(under["code"])=="EVENT_SET_NOT_REFINED_ENOUGH_FOR_TRAJECTORY");checks+=1
	assert(under["pair_ids"]==["C|L","C|R","P|Q","Q|S"]);checks+=1

	# Fail-closed fixed-point controls.
	for code in ["BAD_OUTER_TOLERANCE","BAD_OUTER_ITERATION_BUDGET","BAD_OUTER_RELAXATION"]:
		var bad:=E.fixed_point_bad_option_probe(code)
		assert(not bool(bad["ok"]));checks+=1
		assert(String(bad["code"])==code);checks+=1
	var bad_tolerance:=T.run(0.0)
	assert(not bool(bad_tolerance["ok"]) and String(bad_tolerance["code"])=="BAD_TOLERANCE");checks+=1

	print("FABRIC0.17-D Unified Multi-Impact Wrench Trajectory Acceptance: PASS (%d assertions) events=(%.12f,%.12f) state_refine=(%s,%s,%s) event_refine=(%s,%s,%s) reopen=(%s,%s)->res=(%s,%s) energy=%.12f->%.12f ledger=%s" % [
		checks,float(reference["events"][0]["time"]),float(reference["events"][1]["time"]),
		String.num_scientific(float(state_errors[0])),String.num_scientific(float(state_errors[1])),String.num_scientific(float(state_errors[2])),
		String.num_scientific(float(event_errors[0])),String.num_scientific(float(event_errors[1])),String.num_scientific(float(event_errors[2])),
		String.num_scientific(float(reference["events"][0]["initial_reopened_normal_residual"])),String.num_scientific(float(reference["events"][1]["initial_reopened_normal_residual"])),
		String.num_scientific(float(reference["events"][0]["normal_wrench_cross_drift"])),String.num_scientific(float(reference["events"][1]["normal_wrench_cross_drift"])),
		float(reference["initial_energy"]),float(reference["final_energy"]),String.num_scientific(float(reference["energy_ledger_error"]))
	])
	quit(0)
