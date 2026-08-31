extends SceneTree

const F=preload("res://scripts/research/fabric0/fabric0_general_convex_multipoint_mcp_v1.gd")
const EventSet=preload("res://scripts/research/fabric0/fabric0_simultaneous_impact_event_set_v1.gd")
const Impact=preload("res://scripts/research/fabric0/fabric0_simultaneous_impact_solver_v1.gd")
const E=preload("res://scripts/research/fabric0/fabric0_simultaneous_impact_solver_experiments_v1.gd")

func close(a:float,b:float,tolerance:float)->bool:
	return absf(a-b)<=tolerance

func _init()->void:
	var checks:=0

	var elastic:=E.coupled_three_body_probe(1.0,1.0e-9)
	assert(bool(elastic["ok"]));checks+=1
	assert(String(elastic["kind"])=="COUPLED_SIMULTANEOUS_IMPACT_SOLVE");checks+=1
	assert(int(elastic["pair_count"])==2);checks+=1
	assert(int(elastic["contact_rows"])==8);checks+=1
	assert(elastic["pair_impulses"].keys().size()==2);checks+=1
	assert(elastic["pair_impulses"].has("C|L") and elastic["pair_impulses"].has("C|R"));checks+=1
	assert(close(float(elastic["pair_impulses"]["C|L"]),4.0,2.0e-8));checks+=1
	assert(close(float(elastic["pair_impulses"]["C|R"]),4.0,2.0e-8));checks+=1
	assert(int(elastic["manifolds"]["C|L"]["points"].size())==4);checks+=1
	assert(int(elastic["manifolds"]["C|R"]["points"].size())==4);checks+=1
	assert(int(elastic["boundary_fallbacks"])>=1);checks+=1
	assert(float(elastic["max_complementarity_violation"])<1.0e-8);checks+=1
	assert(float(elastic["max_physical_w_violation"])<1.0e-8);checks+=1
	assert(float(elastic["max_restitution_error"])<2.0e-8);checks+=1
	assert(float(elastic["linear_momentum_error"])<1.0e-13);checks+=1
	assert(float(elastic["angular_momentum_error"])<1.0e-13);checks+=1
	assert(close(float(elastic["energy_before"]),4.0,1.0e-12));checks+=1
	assert(close(float(elastic["energy_after"]),4.0,5.0e-8));checks+=1
	assert(absf(float(elastic["energy_delta"]))<5.0e-8);checks+=1
	assert(elastic["input_before"]==elastic["input_after"]);checks+=1

	var state:Array=elastic["state"]
	assert(String(state[0][0])=="C" and close(float(state[0][1]),0.0,2.0e-8));checks+=1
	assert(String(state[1][0])=="L" and close(float(state[1][1]),-2.0,2.0e-8));checks+=1
	assert(String(state[2][0])=="R" and close(float(state[2][1]),2.0,2.0e-8));checks+=1
	for row in state:
		assert(absf(float(row[4]))<1.0e-12 and absf(float(row[5]))<1.0e-12 and absf(float(row[6]))<1.0e-12);checks+=1

	# The coupled solve canonicalizes both body and event-member order.
	var reverse_bodies:=E.coupled_three_body_probe(1.0,1.0e-9,true,false)
	var reverse_members:=E.coupled_three_body_probe(1.0,1.0e-9,false,true)
	assert(bool(reverse_bodies["ok"]) and bool(reverse_members["ok"]));checks+=1
	assert(String(reverse_bodies["signature"])==String(elastic["signature"]));checks+=1
	assert(String(reverse_members["signature"])==String(elastic["signature"]));checks+=1
	assert(E.state_error(reverse_bodies["state"],elastic["state"])==0.0);checks+=1
	assert(E.state_error(reverse_members["state"],elastic["state"])==0.0);checks+=1

	# Sequential pair impacts are intentionally not accepted semantics: order changes the result.
	var sequential_forward:=E.sequential_reference(false,1.0)
	var sequential_reverse:=E.sequential_reference(true,1.0)
	assert(E.state_error(sequential_forward["state"],sequential_reverse["state"])>1.9);checks+=1
	assert(E.state_error(sequential_forward["state"],elastic["state"])>1.9);checks+=1
	assert(E.state_error(sequential_reverse["state"],elastic["state"])>1.9);checks+=1
	assert(Vector3(sequential_forward["linear"]).length()<1.0e-13);checks+=1
	assert(Vector3(sequential_reverse["linear"]).length()<1.0e-13);checks+=1

	# Restitution is solved on the same coupled graph, not post-processed pair-by-pair.
	var inelastic:=E.restitution_probe(0.0)
	var half:=E.restitution_probe(0.5)
	assert(bool(inelastic["ok"]) and bool(half["ok"]));checks+=1
	assert(close(float(inelastic["energy_after"]),0.0,5.0e-8));checks+=1
	assert(close(float(half["energy_after"]),1.0,5.0e-8));checks+=1
	assert(close(float(half["energy_after"])/float(half["energy_before"]),0.25,2.0e-8));checks+=1
	assert(float(inelastic["energy_after"])<=float(half["energy_after"]));checks+=1
	assert(float(half["energy_after"])<=float(elastic["energy_after"])+1.0e-8);checks+=1
	assert(float(inelastic["max_complementarity_violation"])<1.0e-8);checks+=1
	assert(float(half["max_complementarity_violation"])<1.0e-8);checks+=1


	# Off-center simultaneous impacts exercise full 6DOF coupling and angular momentum.
	var offset:=E.offset_three_body_probe(0.35,1.0e-9)
	var offset_reverse_bodies:=E.offset_three_body_probe(0.35,1.0e-9,true,false)
	var offset_reverse_members:=E.offset_three_body_probe(0.35,1.0e-9,false,true)
	assert(bool(offset["ok"]) and bool(offset_reverse_bodies["ok"]) and bool(offset_reverse_members["ok"]));checks+=1
	assert(int(offset["contact_rows"])==8);checks+=1
	assert(String(offset["signature"])==String(offset_reverse_bodies["signature"]));checks+=1
	assert(String(offset["signature"])==String(offset_reverse_members["signature"]));checks+=1
	assert(float(offset["linear_momentum_error"])<1.0e-13);checks+=1
	assert(float(offset["angular_momentum_error"])<1.0e-13);checks+=1
	assert(float(offset["energy_after"])<float(offset["energy_before"]));checks+=1
	assert(float(offset["max_complementarity_violation"])<1.0e-8);checks+=1
	assert(float(offset["max_restitution_error"])<2.0e-8);checks+=1
	var offset_state:Array=offset["state"]
	assert(absf(float(offset_state[0][6]))>1.4);checks+=1
	assert(absf(float(offset_state[1][6]))>1.4);checks+=1
	assert(absf(float(offset_state[2][6]))>1.4);checks+=1

	# Under-resolved near-coincident roots are rejected before a physical jump is solved.
	var under_refined:=E.under_refined_probe()
	assert(not bool(under_refined["ok"]));checks+=1
	assert(String(under_refined["code"])=="EVENT_SET_NOT_REFINED_ENOUGH");checks+=1

	# Explicit fail-closed contract checks.
	var bodies:=E.three_body_world()
	var event_set:=EventSet.next_appearance_event_set(bodies,0.0,0.6,1.0e-9,1.0e-9,192,16)
	var bad_restitution:=Impact.solve_event_set(bodies,event_set,1.1)
	assert(not bool(bad_restitution["ok"]) and String(bad_restitution["code"])=="BAD_RESTITUTION");checks+=1
	var bad_kind:=event_set.duplicate(true);bad_kind["kind"]="CONTACT_APPEAR"
	var bad_kind_result:=Impact.solve_event_set(bodies,bad_kind,0.0)
	assert(not bool(bad_kind_result["ok"]) and String(bad_kind_result["code"])=="BAD_EVENT_SET_KIND");checks+=1
	var one_member:=event_set.duplicate(true);one_member["members"]=[one_member["members"][0]];one_member["pair_ids"]=[one_member["pair_ids"][0]]
	var one_member_result:=Impact.solve_event_set(bodies,one_member,0.0)
	assert(not bool(one_member_result["ok"]) and String(one_member_result["code"])=="EVENT_SET_NOT_MULTIPLE");checks+=1
	var bad_iterations:=Impact.solve_event_set(bodies,event_set,0.0,{"impact_iterations":0})
	assert(not bool(bad_iterations["ok"]) and String(bad_iterations["code"])=="BAD_IMPACT_ITERATION_BUDGET");checks+=1
	var bad_uncertainty:=Impact.solve_event_set(bodies,event_set,0.0,{"max_event_uncertainty":0.0})
	assert(not bool(bad_uncertainty["ok"]) and String(bad_uncertainty["code"])=="BAD_EVENT_UNCERTAINTY_LIMIT");checks+=1

	print("FABRIC0.17-B Coupled Simultaneous Impact Solve Acceptance: PASS (%d assertions) rows=%d impulses=(%.12f,%.12f) energy=(%.12f->%.12f) comp=%s restitution=%s sequential_order_delta=%s" % [
		checks,int(elastic["contact_rows"]),float(elastic["pair_impulses"]["C|L"]),float(elastic["pair_impulses"]["C|R"]),
		float(elastic["energy_before"]),float(elastic["energy_after"]),String.num_scientific(float(elastic["max_complementarity_violation"])),
		String.num_scientific(float(elastic["max_restitution_error"])),String.num_scientific(E.state_error(sequential_forward["state"],sequential_reverse["state"]))
	])
	quit(0)
