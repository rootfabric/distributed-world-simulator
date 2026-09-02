extends SceneTree

const T=preload("res://scripts/research/fabric0/fabric0_general_convex_trajectory_v1.gd")

func close(a:float,b:float,tolerance:float=1.0e-10)->bool:
	return absf(a-b)<=tolerance

func _init()->void:
	var checks:=0
	var r3:=T.run(1.0e-3)
	var r5:=T.run(1.0e-5)
	var r7:=T.run(1.0e-7)
	var r9:=T.run(1.0e-9)
	var ref:=T.run(1.0e-11)
	for run in [r3,r5,r7,r9,ref]:
		assert(bool(run.get("ok",false)));checks+=1
		assert(close(float(run["time"]),1.0,1.0e-15));checks+=1
		assert(run["events"].size()==3);checks+=1
		assert(run["topology"].size()==3);checks+=1
		assert(int(run["initial_threads"])==2 and int(run["merged_threads"])==1 and int(run["split_threads"])==2);checks+=1
		assert(int(run["merged_rows"])==12 and int(run["split_rows"])==8);checks+=1
		assert(float(run["merged_complementarity"])<1.0e-9);checks+=1
		assert(float(run["merged_cone_violation"])<=1.0e-12);checks+=1
		assert(close(float(run["energy_residual"]),0.0,1.0e-14));checks+=1
		assert(float(run["linear_momentum_error"])<=1.0e-14);checks+=1
		assert(float(run["angular_momentum_error"])<=1.0e-14);checks+=1

	assert(String(ref["events"][0]["kind"])=="CONTACT_APPEAR");checks+=1
	assert(String(ref["events"][1]["kind"])=="SOURCE_RELEASE");checks+=1
	assert(String(ref["events"][2]["kind"])=="CONTACT_DISAPPEAR");checks+=1
	assert(close(float(ref["events"][0]["boundary_time"]),0.51,1.0e-11));checks+=1
	assert(close(float(ref["events"][2]["boundary_time"]),0.7,6.0e-11));checks+=1
	assert(int(ref["events"][0]["manifold_points"])==4);checks+=1
	assert(bool(ref["events"][0]["boundary_fallback"]));checks+=1
	assert(String(ref["events"][0]["feature_key"])=="B|C|ra:B:5|ib:C:4");checks+=1
	assert(int(ref["bridge_lifetime_at_source"])==2);checks+=1
	assert(int(ref["events"][1]["bridge_lifetime"])==2);checks+=1

	assert(ref["topology"][0]["islands"]==[["A","B"],["C","D"]]);checks+=1
	assert(ref["topology"][1]["islands"]==[["A","B","C","D"]]);checks+=1
	assert(ref["topology"][2]["islands"]==[["A","B"],["C","D"]]);checks+=1
	assert(int(ref["topology"][0]["threads"])==2);checks+=1
	assert(int(ref["topology"][1]["threads"])==1);checks+=1
	assert(int(ref["topology"][2]["threads"])==2);checks+=1

	assert(close(float(ref["initial_energy"]),2.0,1.0e-14));checks+=1
	assert(close(float(ref["contact_dissipation"]),2.0,1.0e-12));checks+=1
	assert(close(float(ref["source_work"]),2.0,1.0e-14));checks+=1
	assert(close(float(ref["final_energy"]),2.0,1.0e-14));checks+=1
	assert(close(float(ref["energy_residual"]),0.0,1.0e-14));checks+=1

	var final_manifolds:Dictionary=ref["manifolds"]
	assert(final_manifolds.keys().size()==2);checks+=1
	assert(final_manifolds.has("A|B") and final_manifolds.has("C|D"));checks+=1
	for key in ["A|B","C|D"]:
		var points:Array=final_manifolds[key]["points"]
		assert(points.size()==4);checks+=1
		for point in points:
			assert(int(point["lifetime"])==4);checks+=1

	var state_errors:=[T.state_error(r3,ref),T.state_error(r5,ref),T.state_error(r7,ref),T.state_error(r9,ref)]
	var event_errors:=[T.event_time_error(r3,ref),T.event_time_error(r5,ref),T.event_time_error(r7,ref),T.event_time_error(r9,ref)]
	for i in range(1,state_errors.size()):
		assert(float(state_errors[i])<float(state_errors[i-1]));checks+=1
		assert(float(event_errors[i])<float(event_errors[i-1]));checks+=1
	assert(float(state_errors[3])<2.0e-10);checks+=1
	assert(float(event_errors[3])<4.0e-10);checks+=1

	var replay:=T.run(1.0e-9)
	var replay2:=T.run(1.0e-9)
	var reverse:=T.run(1.0e-9,true,true)
	assert(String(replay["signature"])==String(replay2["signature"]));checks+=1
	assert(String(replay["signature"])==String(reverse["signature"]));checks+=1
	assert(T.state_error(replay,reverse)==0.0);checks+=1
	assert(T.event_time_error(replay,reverse)==0.0);checks+=1

	var bad:=T.run(0.0)
	assert(not bool(bad["ok"]) and String(bad["code"])=="BAD_TOLERANCE");checks+=1

	print("FABRIC0.16 S3 Unified Event-Driven Convex Trajectory Acceptance: PASS (%d assertions) merge=%.12f split=%.12f rows=%d->%d threads=%d->%d->%d state_refine=(%s,%s,%s,%s) event_refine=(%s,%s,%s,%s) energy_res=%s" % [
		checks,float(ref["events"][0]["boundary_time"]),float(ref["events"][2]["boundary_time"]),int(ref["merged_rows"]),int(ref["split_rows"]),
		int(ref["initial_threads"]),int(ref["merged_threads"]),int(ref["split_threads"]),
		String.num_scientific(float(state_errors[0])),String.num_scientific(float(state_errors[1])),String.num_scientific(float(state_errors[2])),String.num_scientific(float(state_errors[3])),
		String.num_scientific(float(event_errors[0])),String.num_scientific(float(event_errors[1])),String.num_scientific(float(event_errors[2])),String.num_scientific(float(event_errors[3])),
		String.num_scientific(float(ref["energy_residual"]))
	])
	quit(0)
