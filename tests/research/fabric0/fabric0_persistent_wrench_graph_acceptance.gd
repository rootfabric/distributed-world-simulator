extends SceneTree

const Graph=preload("res://scripts/research/fabric0/fabric0_persistent_wrench_graph_v1.gd")
const E=preload("res://scripts/research/fabric0/fabric0_persistent_wrench_graph_experiments_v1.gd")

func close(a:float,b:float,tolerance:float)->bool:
	return absf(a-b)<=tolerance

func strict_decreasing(values:Array)->bool:
	for i in range(1,values.size()):
		if not float(values[i])<float(values[i-1]):return false
	return true

func _init()->void:
	var checks:=0

	# Two-support plank: one graph redistributes normal support according to load location.
	var curve:=E.support_curve()
	assert(curve.size()==6);checks+=1
	for i in range(5):
		var x:=float(curve[i]["x"]);var r:Dictionary=curve[i]["result"]
		assert(bool(r["ok"]));checks+=1
		var l:=float(r["per_contact"]["L"]["normal_impulse"]);var rr:=float(r["per_contact"]["R"]["normal_impulse"])
		assert(close(l,0.5*(1.0-x),2.0e-11));checks+=1
		assert(close(rr,0.5*(1.0+x),2.0e-11));checks+=1
		assert(close(l+rr,1.0,2.0e-11));checks+=1
		assert(float(r["normal_complementarity_error"])<2.0e-12);checks+=1
		assert(float(r["matrix_symmetry_error"])<1.0e-14);checks+=1
		assert(float(r["max_cross_contact_coupling"])>0.39);checks+=1
		assert(float(r["energy_ledger_error"])<1.0e-14);checks+=1
		assert(float(r["kinetic_delta"])<=1.0e-15);checks+=1
		if x<1.0:
			assert(bool(r["per_contact"]["L"]["persistent_state"]["active"]));checks+=1
			assert(bool(r["per_contact"]["R"]["persistent_state"]["active"]));checks+=1
		else:
			assert(not bool(r["per_contact"]["L"]["persistent_state"]["active"]));checks+=1
			assert(r["per_contact"]["L"]["persistent_state"]["modes"]=={"tangent":"open","rolling":"open","torsion":"open"});checks+=1

	var balanced:Dictionary=curve[2]["result"] # x=0.5
	assert(close(float(balanced["reaction_force_impulse"].y),1.0,2.0e-11));checks+=1
	assert(close(float(balanced["reaction_moment_impulse"].z),0.5,2.0e-11));checks+=1

	# Outside the support span the weak contact opens instead of producing negative normal support.
	var loss:Dictionary=curve[5]["result"]
	assert(bool(loss["ok"]));checks+=1
	assert(float(loss["per_contact"]["L"]["normal_impulse"])==0.0);checks+=1
	assert(not bool(loss["per_contact"]["L"]["persistent_state"]["active"]));checks+=1
	assert(loss["per_contact"]["L"]["persistent_state"]["modes"]=={"tangent":"open","rolling":"open","torsion":"open"});checks+=1
	assert(bool(loss["per_contact"]["R"]["persistent_state"]["active"]));checks+=1
	assert(float(loss["min_open_normal_velocity"])>0.0124);checks+=1
	assert(float(loss["normal_complementarity_error"])<2.0e-12);checks+=1
	assert(float(loss["post_body"]["w"].z)<-0.0062);checks+=1
	assert(float(loss["energy_ledger_error"])<1.0e-14);checks+=1

	# Persistent history survives on the loaded support while the unloaded support emits separation state.
	var continuity:=E.support_loss_continuity_probe()
	assert(bool(continuity["ok"]));checks+=1
	assert(bool(continuity["left_before"]["active"]));checks+=1
	assert(not bool(continuity["left_after"]["active"]));checks+=1
	assert(continuity["left_after"]["mode_transition_hypothesis"]["contact"]=="SEPARATION_CANDIDATE");checks+=1
	assert(continuity["left_after"]["warm_start_proposal"]==[0.0,0.0,0.0,0.0,0.0]);checks+=1
	assert(bool(continuity["right_after"]["identity_continued"]));checks+=1
	assert(int(continuity["right_after"]["update_count"])==1);checks+=1
	assert(close(float(continuity["right_after"]["contact_age"]),0.01,1.0e-15));checks+=1
	assert(close(float(continuity["right_after"]["first_seen_time"]),0.01,1.0e-15));checks+=1

	# Shared-body corner graph supports mixed contact modes in one solve.
	var mixed:=E.corner_mixed_probe()
	assert(bool(mixed["ok"]));checks+=1
	assert(String(mixed["floor_modes"]["tangent"])=="slide");checks+=1
	assert(String(mixed["wall_modes"]["tangent"])=="stick");checks+=1
	var mr:Dictionary=mixed["result"]
	assert(bool(mr["per_contact"]["FLOOR"]["persistent_state"]["active"]));checks+=1
	assert(bool(mr["per_contact"]["WALL"]["persistent_state"]["active"]));checks+=1
	var floor_t:Vector2=mr["per_contact"]["FLOOR"]["tangent_impulse"]
	var wall_t:Vector2=mr["per_contact"]["WALL"]["tangent_impulse"]
	assert(close(floor_t.length(),float(mr["per_contact"]["FLOOR"]["limits"]["tangent"]),2.0e-11));checks+=1
	assert(wall_t.length()<float(mr["per_contact"]["WALL"]["limits"]["tangent"])-0.05);checks+=1
	assert(float(mr["max_cross_contact_coupling"])>=1.0);checks+=1
	assert(float(mr["normal_complementarity_error"])<6.0e-12);checks+=1
	assert(float(mr["energy_ledger_error"])<1.0e-14);checks+=1
	assert(float(mr["kinetic_delta"])<0.0);checks+=1
	var mixed_reverse:=E.corner(-0.2,-0.2,-0.8,0.0,true,0.04,1.2,-0.8,0.2)
	assert(bool(mixed_reverse["ok"]));checks+=1
	assert(String(mixed_reverse["signature"])==String(mr["signature"]));checks+=1

	# Generalized wrench graph can activate slide, roll and spin simultaneously.
	var all_modes:=E.plank(0.7,0.6,0.16,0.05)
	assert(bool(all_modes["ok"]));checks+=1
	for id in ["L","R"]:
		var modes:Dictionary=all_modes["per_contact"][id]["persistent_state"]["modes"]
		assert(String(modes["tangent"])=="slide");checks+=1
		assert(String(modes["rolling"])=="roll");checks+=1
		assert(String(modes["torsion"])=="spin");checks+=1
		assert(close(Vector2(all_modes["per_contact"][id]["tangent_impulse"]).length(),float(all_modes["per_contact"][id]["limits"]["tangent"]),2.0e-11));checks+=1
		assert(close(Vector2(all_modes["per_contact"][id]["rolling_impulse"]).length(),float(all_modes["per_contact"][id]["limits"]["rolling"]),2.0e-11));checks+=1
		assert(close(absf(float(all_modes["per_contact"][id]["torsion_impulse"])),float(all_modes["per_contact"][id]["limits"]["torsion"]),2.0e-11));checks+=1
	assert(float(all_modes["post_body"]["w"].x)>0.031);checks+=1
	assert(float(all_modes["post_body"]["w"].y)>0.001);checks+=1
	assert(float(all_modes["energy_ledger_error"])<1.0e-14);checks+=1
	assert(float(all_modes["normal_complementarity_error"])<2.0e-12);checks+=1

	# Unified graph is caller-order independent; sequential pair mutation is a strong falsifier.
	var order:=E.order_determinism_probe()
	assert(bool(order["ok"]));checks+=1
	assert(float(order["state_error"])==0.0);checks+=1
	assert(bool(order["signature_equal"]));checks+=1
	var sequential:=E.sequential_falsifier()
	assert(bool(sequential["ok"]));checks+=1
	assert(float(sequential["state_error"])>0.031);checks+=1
	assert(float(sequential["forward"]["w"].z)>0.024);checks+=1
	assert(float(sequential["reverse"]["w"].z)<-0.006);checks+=1

	# Solver tolerance refinement converges strictly to a tighter reference.
	var refinement:=E.tolerance_refinement_probe()
	assert(bool(refinement["ok"]));checks+=1
	assert(refinement["errors"].size()==4);checks+=1
	assert(strict_decreasing(refinement["errors"]));checks+=1
	assert(float(refinement["errors"][0])<9.0e-6);checks+=1
	assert(float(refinement["errors"][3])<9.0e-12);checks+=1
	for run_any in refinement["runs"]:
		var run:Dictionary=run_any
		assert(float(run["matrix_symmetry_error"])<1.0e-14);checks+=1
		assert(float(run["energy_ledger_error"])<1.0e-14);checks+=1

	# Physical no-creep: 10,000 repeated gravity-support solves, not bookkeeping-only updates.
	var steady:=E.steady_support_probe(10000)
	assert(bool(steady["ok"]));checks+=1
	assert(int(steady["steps"])==10000);checks+=1
	assert(close(float(steady["time"]),10.0,1.0e-15));checks+=1
	assert(float(steady["max_speed"])<2.0e-13);checks+=1
	assert(float(steady["max_angular_speed"])<1.0e-15);checks+=1
	assert(Vector3(steady["position"]).length()<2.0e-12);checks+=1
	assert(Vector3(steady["angle"]).length()<2.0e-12);checks+=1
	for id in ["L","R"]:
		var state:Dictionary=steady["states"][id]
		assert(bool(state["active"]));checks+=1
		assert(int(state["identity_epoch"])==0);checks+=1
		assert(int(state["update_count"])==9999);checks+=1
		assert(close(float(state["contact_age"]),9.999,1.0e-12));checks+=1
		assert(close(float(state["normal_support"]),0.5,2.0e-12));checks+=1
		assert(state["modes"]=={"tangent":"stick","rolling":"stick","torsion":"stick"});checks+=1

	# Fail-closed input boundary.
	var base_body={"id":"X","mass":1.0,"inertia":Vector3.ONE,"v":Vector3.ZERO,"w":Vector3.ZERO}
	var contacts:=E._contacts(0.0)
	var too_few:=Graph.solve(base_body,[contacts[0]])
	assert(not bool(too_few["ok"]) and too_few["code"]=="TOO_FEW_CONTACTS");checks+=1
	var bad_mass:=base_body.duplicate(true);bad_mass["mass"]=0.0
	var r_bad_mass:=Graph.solve(bad_mass,contacts)
	assert(not bool(r_bad_mass["ok"]) and r_bad_mass["code"]=="BAD_MASS");checks+=1
	var bad_inertia:=base_body.duplicate(true);bad_inertia["inertia"]=Vector3(1,0,1)
	var r_bad_inertia:=Graph.solve(bad_inertia,contacts)
	assert(not bool(r_bad_inertia["ok"]) and r_bad_inertia["code"]=="BAD_INERTIA");checks+=1
	var duplicate:=contacts.duplicate(true);duplicate[1]["contact_id"]="L"
	var r_duplicate:=Graph.solve(base_body,duplicate)
	assert(not bool(r_duplicate["ok"]) and r_duplicate["code"]=="DUPLICATE_CONTACT_ID");checks+=1
	var negative:=contacts.duplicate(true);negative[0]["mu_tangent"]=-0.1
	var r_negative:=Graph.solve(base_body,negative)
	assert(not bool(r_negative["ok"]) and r_negative["code"]=="NEGATIVE_WRENCH_COEFFICIENT");checks+=1
	var nonunit:=contacts.duplicate(true);nonunit[0]["normal"]=Vector3(0,2,0)
	var r_nonunit:=Graph.solve(base_body,nonunit)
	assert(not bool(r_nonunit["ok"]) and r_nonunit["code"]=="NONUNIT_CONTACT_FRAME");checks+=1
	var bad_tol:=Graph.solve(base_body,contacts,{}, {"tolerance":0.0})
	assert(not bool(bad_tol["ok"]) and bad_tol["code"]=="BAD_TOLERANCE");checks+=1
	var bad_budget:=Graph.solve(base_body,contacts,{}, {"iterations":0})
	assert(not bool(bad_budget["ok"]) and bad_budget["code"]=="BAD_ITERATION_BUDGET");checks+=1

	print("FABRIC0.18-C Multicontact Persistent Wrench Graph Acceptance: PASS (%d assertions) support=(%.12f,%.12f) loss_open=%.12f mixed=%s/%s sequential_delta=%.12f refine=%s steady_v=%s" % [
		checks,float(balanced["per_contact"]["L"]["normal_impulse"]),float(balanced["per_contact"]["R"]["normal_impulse"]),float(loss["min_open_normal_velocity"]),String(mixed["floor_modes"]["tangent"]),String(mixed["wall_modes"]["tangent"]),float(sequential["state_error"]),str(refinement["errors"]),String.num_scientific(float(steady["max_speed"]))
	])
	quit(0)
