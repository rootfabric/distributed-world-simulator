extends SceneTree

const F=preload("res://scripts/research/fabric0/fabric0_general_convex_multipoint_mcp_v1.gd")
const Events=preload("res://scripts/research/fabric0/fabric0_general_convex_event_driver_v1.gd")
const Parallel=preload("res://scripts/research/fabric0/fabric0_general_convex_parallel_islands_v1.gd")
const E=preload("res://scripts/research/fabric0/fabric0_general_convex_events_parallel_experiments_v1.gd")

func close(a:float,b:float,tolerance:float=1.0e-10)->bool:
	return absf(a-b)<=tolerance

func _init()->void:
	var checks:=0

	# --- Conservative motion candidate envelope. ---
	var shape:=F.box_shape("candidate_box",Vector3(0.5,0.5,0.5))
	var candidate_a:=F.new_body("A",shape,Vector3.ZERO)
	var candidate_b:=F.new_body("B",shape,Vector3(2,0,0),Quaternion.IDENTITY,1.0,Vector3(0.2,0.2,0.2),Vector3(-2,0,0),Vector3(0.3,0.1,0.2))
	var far:=F.new_body("F",shape,Vector3(10,10,0))
	assert(Events.swept_candidate(candidate_a,candidate_b,0.0,0.75));checks+=1
	assert(not Events.swept_candidate(candidate_a,far,0.0,0.75));checks+=1
	var swept:=Events.swept_aabb(candidate_b,0.0,0.75)
	assert(swept.size.x>2.0 and swept.size.y>1.0 and swept.size.z>1.0);checks+=1

	# --- GJK/EPA-normal-guided contact transition localization + refinement. ---
	var c4:=E.contact_event_probe(1.0e-4)
	var c6:=E.contact_event_probe(1.0e-6)
	var c8:=E.contact_event_probe(1.0e-8)
	var cref:=E.contact_event_probe(1.0e-10)
	for run in [c4,c6,c8,cref]:
		assert(bool(run["appear"]["ok"]));checks+=1
		assert(bool(run["disappear"]["ok"]));checks+=1
		assert(String(run["appear"]["kind"])=="CONTACT_APPEAR");checks+=1
		assert(String(run["disappear"]["kind"])=="CONTACT_DISAPPEAR");checks+=1
		assert(float(run["appear"]["bracket_width"])>0.0);checks+=1
		assert(float(run["disappear"]["bracket_width"])>0.0);checks+=1
	assert(close(float(cref["appear"]["time"]),0.5,5.0e-11));checks+=1
	assert(close(float(cref["disappear"]["time"]),0.1,6.0e-11));checks+=1
	assert(int(cref["appear"]["boundary_fallbacks"])>0);checks+=1
	assert(int(cref["disappear"]["boundary_fallbacks"])>0);checks+=1
	assert(float(cref["appear"]["lo_measure"])>0.0 and float(cref["appear"]["hi_measure"])<=0.0);checks+=1
	assert(float(cref["disappear"]["lo_measure"])<=0.0 and float(cref["disappear"]["hi_measure"])>0.0);checks+=1
	var appear_ref:=float(cref["appear"]["time"])
	var disappear_ref:=float(cref["disappear"]["time"])
	var appear_errors:=[absf(float(c4["appear"]["time"])-appear_ref),absf(float(c6["appear"]["time"])-appear_ref),absf(float(c8["appear"]["time"])-appear_ref)]
	var disappear_errors:=[absf(float(c4["disappear"]["time"])-disappear_ref),absf(float(c6["disappear"]["time"])-disappear_ref),absf(float(c8["disappear"]["time"])-disappear_ref)]
	assert(float(appear_errors[1])<float(appear_errors[0]) and float(appear_errors[2])<float(appear_errors[1]));checks+=1
	assert(float(disappear_errors[1])<float(disappear_errors[0]) and float(disappear_errors[2])<float(disappear_errors[1]));checks+=1
	assert(float(c8["appear"]["bracket_width"])<1.0e-8);checks+=1
	assert(float(c8["disappear"]["bracket_width"])<1.0e-8);checks+=1

	# --- Persistent four-point manifold survives after localized appearance. ---
	var persistence:=E.persistent_event_manifold_probe()
	assert(bool(persistence["first"]["ok"]) and bool(persistence["second"]["ok"]));checks+=1
	var first_points:Array=persistence["first"]["manifold"]["points"]
	var second_points:Array=persistence["second"]["manifold"]["points"]
	assert(first_points.size()==4 and second_points.size()==4);checks+=1
	var first_ids:Array=[]
	var second_ids:Array=[]
	for point in first_points:
		first_ids.append(String(point["id"]));assert(int(point["lifetime"])==1);checks+=1
	for point in second_points:
		second_ids.append(String(point["id"]));assert(int(point["lifetime"])==2);checks+=1
	assert(first_ids==second_ids);checks+=1
	assert(String(persistence["first"]["manifold"]["feature_key"])==String(persistence["second"]["manifold"]["feature_key"]));checks+=1
	assert(float(persistence["second"]["collision"]["depth"])>float(persistence["first"]["collision"]["depth"]));checks+=1

	# --- Root localization of the S1 solved stick -> slide mode surface. ---
	var m4:=E.mode_transition_probe(1.0e-4)
	var m6:=E.mode_transition_probe(1.0e-6)
	var m8:=E.mode_transition_probe(1.0e-8)
	var mref:=E.mode_transition_probe(1.0e-10)
	for run in [m4,m6,m8,mref]:
		assert(bool(run["event"]["ok"]));checks+=1
		assert(String(run["low_solve"]["blocks"][run["id"]]["mode"])=="stick");checks+=1
		assert(String(run["high_solve"]["blocks"][run["id"]]["mode"])=="slide");checks+=1
		assert(String(run["event"]["old"])=="stick" and String(run["event"]["new"])=="slide");checks+=1
	var mode_ref:=float(mref["event"]["time"])
	var mode_errors:=[absf(float(m4["event"]["time"])-mode_ref),absf(float(m6["event"]["time"])-mode_ref),absf(float(m8["event"]["time"])-mode_ref)]
	assert(float(mode_errors[1])<float(mode_errors[0]) and float(mode_errors[2])<float(mode_errors[1]));checks+=1
	assert(close(mode_ref,0.15798543221899,6.0e-11));checks+=1
	assert(float(mref["event"]["bracket_width"])<1.0e-10);checks+=1
	var target_block:Dictionary=mref["event"]["target_block"]
	assert(String(target_block["mode"])=="slide");checks+=1
	assert(Vector2(target_block["pt"]).length()>0.049);checks+=1

	# --- Same-world actual Thread islands equal one sequential block-diagonal solve. ---
	var forward:=E.parallel_same_world_probe(false)
	var reverse:=E.parallel_same_world_probe(true)
	assert(bool(forward["sequential"]["ok"]) and bool(forward["parallel"]["ok"]));checks+=1
	assert(bool(reverse["sequential"]["ok"]) and bool(reverse["parallel"]["ok"]));checks+=1
	assert(int(forward["parallel"]["threads_started"])==2 and int(reverse["parallel"]["threads_started"])==2);checks+=1
	assert(forward["parallel"]["islands"].size()==2);checks+=1
	assert(forward["parallel"]["islands"][0]["body_ids"]==["A","B"]);checks+=1
	assert(forward["parallel"]["islands"][1]["body_ids"]==["D","E"]);checks+=1
	assert(forward["contacts"].size()==8);checks+=1
	assert(float(forward["max_state_error"])==0.0);checks+=1
	assert(float(reverse["max_state_error"])==0.0);checks+=1
	assert(String(forward["parallel"]["canonical_signature"])==String(reverse["parallel"]["canonical_signature"]));checks+=1
	for result in forward["parallel"]["results"]:
		assert(bool(result["ok"]));checks+=1
		assert(float(result["solve_metrics"]["comp"])<=1.0e-12);checks+=1
		assert(float(result["solve_metrics"]["cone"])<=1.0e-12);checks+=1
	assert(F.total_linear_momentum(forward["parallel_bodies"]).distance_to(F.total_linear_momentum(forward["initial_bodies"]))<=1.0e-14);checks+=1
	assert(F.total_angular_momentum_origin(forward["parallel_bodies"]).distance_to(F.total_angular_momentum_origin(forward["initial_bodies"]))<=1.0e-14);checks+=1

	# --- Parallel island failure is transactional: original world receives no partial join. ---
	var failure:=E.parallel_failure_atomicity_probe()
	assert(not bool(failure["result"]["ok"]));checks+=1
	assert(String(failure["result"]["code"])=="ISLAND_SOLVE_FAILED");checks+=1
	assert(String(failure["result"]["island"]["solve"]["code"])=="BAD_SOLVER_BUDGET");checks+=1
	assert(String(failure["before"])==String(failure["after"]));checks+=1

	# --- Explicit fail-closed event boundaries. ---
	var bad_interval:=Events.transition_event(candidate_a,candidate_b,1.0,0.0,true)
	assert(not bool(bad_interval["ok"]) and String(bad_interval["code"])=="BAD_INTERVAL");checks+=1
	var no_transition:=Events.transition_event(candidate_a,far,0.0,0.5,true)
	assert(not bool(no_transition["ok"]) and String(no_transition["code"])=="NO_BRACKETED_TRANSITION");checks+=1
	var bad_mode:=Events.localize_mode_transition(mref["low"],mref["high"],mref["contacts"],0.0,0.0,1.0,String(mref["id"]),"slide")
	assert(not bool(bad_mode["ok"]) and String(bad_mode["code"])=="BAD_STEP");checks+=1
	var bad_parallel:=Parallel.solve_same_world([],[],0.0)
	assert(not bool(bad_parallel["ok"]) and String(bad_parallel["code"])=="BAD_STEP");checks+=1
	var duplicate_bodies:Array=forward["initial_bodies"].duplicate(true)
	duplicate_bodies[1]["id"]="A"
	var duplicate_result:=Parallel.solve_same_world(duplicate_bodies,forward["contacts"].duplicate(true),0.01,forward["options"])
	assert(not bool(duplicate_result["ok"]) and String(duplicate_result["code"])=="DUPLICATE_BODY_ID");checks+=1
	var malformed_contacts:Array=forward["contacts"].duplicate(true)
	malformed_contacts[0]["b"]=999
	var malformed_result:=Parallel.solve_same_world(forward["initial_bodies"].duplicate(true),malformed_contacts,0.01,forward["options"])
	assert(not bool(malformed_result["ok"]) and String(malformed_result["code"])=="CONTACT_BODY_INDEX_OUT_OF_RANGE");checks+=1
	var budget_options:Dictionary=forward["options"].duplicate(true)
	budget_options["max_threads"]=1
	var budget_bodies:Array=forward["initial_bodies"].duplicate(true)
	var budget_before:=JSON.stringify(budget_bodies)
	var budget_result:=Parallel.solve_same_world(budget_bodies,forward["contacts"].duplicate(true),0.01,budget_options)
	assert(not bool(budget_result["ok"]) and String(budget_result["code"])=="ISLAND_THREAD_BUDGET_EXCEEDED");checks+=1
	assert(JSON.stringify(budget_bodies)==budget_before);checks+=1
	var bad_target:=Events.localize_mode_transition(mref["low"],mref["high"],mref["contacts"],0.01,0.0,1.0,String(mref["id"]),"rolling")
	assert(not bool(bad_target["ok"]) and String(bad_target["code"])=="BAD_TARGET_MODE");checks+=1

	print("FABRIC0.16 S2 Adaptive Convex Events + Same-World Parallel Islands Acceptance: PASS (%d assertions) appear=%.12f disappear=%.12f mode=%.12f event_refine=(%s,%s,%s) mode_refine=(%s,%s,%s) manifold=%d threads=%d parallel_error=%s" % [
		checks,appear_ref,disappear_ref,mode_ref,
		String.num_scientific(float(appear_errors[0])),String.num_scientific(float(appear_errors[1])),String.num_scientific(float(appear_errors[2])),
		String.num_scientific(float(mode_errors[0])),String.num_scientific(float(mode_errors[1])),String.num_scientific(float(mode_errors[2])),
		second_points.size(),int(forward["parallel"]["threads_started"]),String.num_scientific(float(forward["max_state_error"]))
	])
	quit(0)
