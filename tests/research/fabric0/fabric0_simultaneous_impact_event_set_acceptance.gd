extends SceneTree

const F=preload("res://scripts/research/fabric0/fabric0_general_convex_multipoint_mcp_v1.gd")
const EventSet=preload("res://scripts/research/fabric0/fabric0_simultaneous_impact_event_set_v1.gd")
const E=preload("res://scripts/research/fabric0/fabric0_simultaneous_impact_event_set_experiments_v1.gd")

func close(a:float,b:float,tolerance:float)->bool:
	return absf(a-b)<=tolerance

func _init()->void:
	var checks:=0

	var exact3:=E.exact_three_body_probe(1.0e-10)
	assert(bool(exact3["ok"]));checks+=1
	assert(String(exact3["kind"])=="SIMULTANEOUS_IMPACT_EVENT_SET");checks+=1
	assert(exact3["pair_ids"]==["C|L","C|R"]);checks+=1
	assert(int(exact3["member_count"])==2);checks+=1
	assert(int(exact3["deferred_count"])==0);checks+=1
	assert(bool(exact3["interval_overlap"]));checks+=1
	assert(String(exact3["classification"])=="INTERVAL_COINCIDENT");checks+=1
	assert(close(float(exact3["time"]),0.5,7.0e-11));checks+=1
	assert(String(exact3["signature"])=="SIMULTANEOUS_IMPACT_SET[C|L,C|R]");checks+=1
	for member in exact3["members"]:
		assert(float(member["approach_speed"])>1.9);checks+=1

	var coarse:=E.five_body_probe(1.0e-3)
	var medium:=E.five_body_probe(1.0e-5)
	var fine:=E.five_body_probe(1.0e-7)
	var finer:=E.five_body_probe(1.0e-9)
	var reference:=E.five_body_probe(1.0e-11)
	for run in [coarse,medium,fine,finer,reference]:
		assert(bool(run["ok"]));checks+=1
		assert(String(run["anchor_id"])=="C|L");checks+=1
		assert(int(run["localized_events"])==3);checks+=1
		assert(int(run["swept_candidates"])>=3);checks+=1
		assert(float(run["uncertainty_span"])>=0.0);checks+=1

	# At coarse temporal resolution the 0.5002 contact is intentionally unresolved.
	assert(coarse["pair_ids"]==["C|L","C|R","P|Q"]);checks+=1
	assert(int(coarse["member_count"])==3);checks+=1

	# Refinement separates the later physical event and stabilizes the true simultaneous set.
	for run in [medium,fine,finer,reference]:
		assert(run["pair_ids"]==["C|L","C|R"]);checks+=1
		assert(int(run["member_count"])==2);checks+=1
		assert(int(run["deferred_count"])==1);checks+=1
		assert(String(run["deferred_events"][0]["id"])=="P|Q");checks+=1
		assert(float(run["deferred_events"][0]["time"])>float(run["time"]));checks+=1

	var ref_time:=float(reference["time"])
	var time_errors:=[
		absf(float(medium["time"])-ref_time),
		absf(float(fine["time"])-ref_time),
		absf(float(finer["time"])-ref_time),
	]
	assert(float(time_errors[1])<float(time_errors[0]));checks+=1
	assert(float(time_errors[2])<float(time_errors[1]));checks+=1
	assert(close(ref_time,0.5,1.0e-11));checks+=1
	assert(close(float(reference["deferred_events"][0]["time"]),0.5002,1.0e-11));checks+=1

	var reverse:=E.five_body_probe(1.0e-9,true)
	assert(bool(reverse["ok"]));checks+=1
	assert(String(reverse["signature"])==String(finer["signature"]));checks+=1
	assert(reverse["pair_ids"]==finer["pair_ids"]);checks+=1
	assert(close(float(reverse["time"]),float(finer["time"]),1.0e-15));checks+=1
	assert(String(reverse["deferred_events"][0]["id"])==String(finer["deferred_events"][0]["id"]));checks+=1
	assert(close(float(reverse["deferred_events"][0]["time"]),float(finer["deferred_events"][0]["time"]),1.0e-15));checks+=1

	var quiet:=E.no_event_probe()
	assert(not bool(quiet["ok"]));checks+=1
	assert(String(quiet["code"])=="NO_IMPACT_EVENT");checks+=1

	var shape:=F.box_shape("bad_box",Vector3(0.5,0.5,0.5))
	var duplicate:Array=[F.new_body("X",shape,Vector3(-2,0,0)),F.new_body("X",shape,Vector3(2,0,0))]
	var duplicate_result:=EventSet.next_appearance_event_set(duplicate,0.0,0.6)
	assert(not bool(duplicate_result["ok"]) and String(duplicate_result["code"])=="DUPLICATE_BODY_ID");checks+=1
	var too_few:=EventSet.next_appearance_event_set([duplicate[0]],0.0,0.6)
	assert(not bool(too_few["ok"]) and String(too_few["code"])=="TOO_FEW_BODIES");checks+=1
	var bad_interval:=EventSet.next_appearance_event_set(duplicate,0.6,0.0)
	assert(not bool(bad_interval["ok"]) and String(bad_interval["code"])=="BAD_INTERVAL");checks+=1
	var bad_tolerance:=EventSet.next_appearance_event_set(duplicate,0.0,0.6,0.0)
	assert(not bool(bad_tolerance["ok"]) and String(bad_tolerance["code"])=="BAD_ROOT_TOLERANCE");checks+=1
	var bad_resolution:=EventSet.next_appearance_event_set(duplicate,0.0,0.6,1.0e-8,-1.0)
	assert(not bool(bad_resolution["ok"]) and String(bad_resolution["code"])=="BAD_SIMULTANEOUS_RESOLUTION");checks+=1
	var budget_world:=E._five_body_world()
	var bad_budget:=EventSet.next_appearance_event_set(budget_world,0.0,0.6,1.0e-8,1.0e-8,128,9)
	assert(not bool(bad_budget["ok"]) and String(bad_budget["code"])=="PAIR_BUDGET_EXCEEDED");checks+=1
	var bad_speed:=EventSet.next_appearance_event_set(budget_world,0.0,0.6,1.0e-8,1.0e-8,128,64,-1.0)
	assert(not bool(bad_speed["ok"]) and String(bad_speed["code"])=="BAD_APPROACH_SPEED_THRESHOLD");checks+=1

	print("FABRIC0.17-A Simultaneous Impact Event Set Acceptance: PASS (%d assertions) coarse=%s stable=%s event=%.12f deferred=%.12f refine=(%s,%s,%s)" % [
		checks,
		str(coarse["pair_ids"]),
		str(reference["pair_ids"]),
		ref_time,
		float(reference["deferred_events"][0]["time"]),
		String.num_scientific(float(time_errors[0])),
		String.num_scientific(float(time_errors[1])),
		String.num_scientific(float(time_errors[2]))
	])
	quit(0)
