extends SceneTree

const F=preload("res://scripts/research/fabric0/fabric0_multibody_convex_complementarity_graph_v1.gd")
const E=preload("res://scripts/research/fabric0/fabric0_multibody_convex_complementarity_graph_experiments_v1.gd")
const M=preload("res://scripts/research/fabric0/fabric0_multibody_convex_model_v1.gd")

func close(a:float,b:float,tol:float=1e-10)->bool:return absf(a-b)<=tol
func find_event(run:Dictionary,kind:String,id:String)->Dictionary:
	for e in run["world"]["events"]:
		if String(e["kind"])==kind and String(e.get("id",""))==id:return e
	return {}
func state_vec(run:Dictionary)->Array:
	var a:Array=[]
	for b in run["world"]["bodies"]:
		var q:Quaternion=b["q"]
		for x in [b["p"].x,b["p"].y,b["p"].z,q.x,q.y,q.z,q.w,b["v"].x,b["v"].y,b["v"].z,b["w"].x,b["w"].y,b["w"].z]:a.append(float(x))
	return a
func max_state_error(run:Dictionary,reference:Array)->float:
	var a:=state_vec(run);var m:=0.0
	for i in range(a.size()):m=maxf(m,absf(float(a[i])-float(reference[i])))
	return m
func block(solve:Dictionary,id:String)->Dictionary:return solve["blocks"][id]

func _init()->void:
	var checks:=0

	# --- Refinement over graph merge + complementarity split ---
	var reference=E.graph_run(0.0005,0.4);assert(bool(reference["result"]["ok"]));checks+=1
	var ref_state:=state_vec(reference);assert(ref_state.size()==52);checks+=1
	var ref_merge:=find_event(reference,"CONTACT_APPEAR","C|D");var ref_split:=find_event(reference,"CONTACT_DISAPPEAR","C|D")
	assert(not ref_merge.is_empty() and not ref_split.is_empty());checks+=1
	assert(close(float(ref_split["time"]),0.32,1e-13));checks+=1

	var coarse=E.graph_run(0.004,0.4);var medium=E.graph_run(0.002,0.4);var fine=E.graph_run(0.001,0.4)
	for run in [coarse,medium,fine]:
		assert(bool(run["result"]["ok"]));checks+=1
		assert(run["world"]["graph_events"].size()==2);checks+=1
		assert(String(run["world"]["graph_events"][0]["kind"])=="ISLAND_MERGE");checks+=1
		assert(String(run["world"]["graph_events"][1]["kind"])=="ISLAND_SPLIT");checks+=1
		assert(close(float(find_event(run,"CONTACT_DISAPPEAR","C|D")["time"]),0.32,1e-13));checks+=1

	var e_coarse:=absf(float(find_event(coarse,"CONTACT_APPEAR","C|D")["time"])-float(ref_merge["time"]))
	var e_medium:=absf(float(find_event(medium,"CONTACT_APPEAR","C|D")["time"])-float(ref_merge["time"]))
	var e_fine:=absf(float(find_event(fine,"CONTACT_APPEAR","C|D")["time"])-float(ref_merge["time"]))
	assert(e_medium<e_coarse);checks+=1;assert(e_fine<e_medium);checks+=1
	assert(e_coarse<1.7e-3);checks+=1;assert(e_medium<7.0e-4);checks+=1;assert(e_fine<2.3e-4);checks+=1
	var s_coarse:=max_state_error(coarse,ref_state);var s_medium:=max_state_error(medium,ref_state);var s_fine:=max_state_error(fine,ref_state)
	assert(s_medium<s_coarse);checks+=1;assert(s_fine<s_medium);checks+=1
	assert(s_coarse<4.3e-3);checks+=1;assert(s_medium<1.9e-3);checks+=1;assert(s_fine<7.5e-4);checks+=1
	var r_coarse:=float(coarse["result"]["energy_ledger_residual"]);var r_medium:=float(medium["result"]["energy_ledger_residual"]);var r_fine:=float(fine["result"]["energy_ledger_residual"])
	assert(r_medium<r_coarse);checks+=1;assert(r_fine<r_medium);checks+=1
	assert(r_coarse<0.19);checks+=1;assert(r_medium<0.094);checks+=1;assert(r_fine<0.048);checks+=1

	# --- Main accepted graph trajectory ---
	var w:Dictionary=fine["world"];var r:Dictionary=fine["result"]
	assert(close(float(r["time"]),0.4,1e-13));checks+=1
	assert(w["events"].size()==5);checks+=1
	var appear:=find_event(fine,"CONTACT_APPEAR","C|D");var disappear:=find_event(fine,"CONTACT_DISAPPEAR","C|D")
	assert(close(float(appear["time"]),0.18299031095859,2e-13));checks+=1
	assert(String(appear["mode"])=="stick");checks+=1
	assert(float(appear["normal_impulse"])>0.59);checks+=1
	assert(Vector2(appear["tangent_impulse"]).length()>0.039);checks+=1
	assert(close(float(disappear["time"]),0.32,1e-13));checks+=1
	assert(String(disappear["reason"])=="COMPLEMENTARITY_SEPARATION");checks+=1
	assert(w["graph_events"][0]["before"]==[["A","B","C"],["D"]]);checks+=1
	assert(w["graph_events"][0]["after"]==[["A","B","C","D"]]);checks+=1
	assert(w["graph_events"][1]["before"]==[["A","B","C","D"]]);checks+=1
	assert(w["graph_events"][1]["after"]==[["A","B","C"],["D"]]);checks+=1
	assert(String(w["events"][2]["kind"])=="SOURCE_CHANGE");checks+=1
	assert(close(float(w["events"][2]["time"]),0.32,1e-13));checks+=1
	assert(Vector3(w["events"][2]["new_force"])==Vector3(0,0,12));checks+=1
	assert(r["components"]==[["A","B","C"],["D"]]);checks+=1
	assert(w["contacts"].has("A|B") and w["contacts"].has("B|C") and w["contacts"].has("plane|A"));checks+=1
	assert(not w["contacts"].has("C|D"));checks+=1
	assert(float(r["max_penetration"])<5e-6);checks+=1
	assert(float(r["max_normal_violation"])<1.7e-4);checks+=1
	assert(float(r["max_cone_violation"])<1e-10);checks+=1
	assert(float(r["max_internal_linear_momentum_error"])<=1e-14);checks+=1
	assert(float(r["max_internal_angular_momentum_error"])<=1e-14);checks+=1
	assert(float(r["contact_dissipation"])>0.65);checks+=1
	assert(float(r["external_work"])>1.13);checks+=1
	assert(float(r["projection_distance"])<2e-5);checks+=1
	assert(close(float(r["projection_energy_delta"]),0.0,1e-12));checks+=1
	assert(String(r["state_hash"])=="68e18b6a9a16b574aaf0b6ca30b3cf5160ea9a69ba8919df11f1b04fda92d29c");checks+=1
	for b in w["bodies"]:
		assert(close(Quaternion(b["q"]).length(),1.0,1e-12));checks+=1
		assert(Vector3(b["w"]).length()>0.01);checks+=1

	# Dynamic mode evidence: graph contains both stick and slide transitions.
	var saw_slide:=false;var saw_stick_after_slide:=false;var saw_cd_stick:=false
	for ev in w["mode_events"]:
		if String(ev["new"])=="slide":saw_slide=true
		if String(ev["old"])=="slide" and String(ev["new"])=="stick":saw_stick_after_slide=true
		if String(ev["id"])=="C|D" and String(ev["new"])=="stick":saw_cd_stick=true
	assert(saw_slide);checks+=1;assert(saw_stick_after_slide);checks+=1;assert(saw_cd_stick);checks+=1

	# --- Simultaneous coupled normal complementarity chain ---
	var normal=E.normal_chain_probe();var ns:Dictionary=normal["solve"]
	assert(bool(ns["ok"]));checks+=1
	assert(normal["contacts"].size()==3);checks+=1
	assert(close(float(block(ns,"B|C")["pn"]),0.0367875,8e-6));checks+=1
	assert(close(float(block(ns,"A|B")["pn"]),0.08379375,8e-6));checks+=1
	assert(close(float(block(ns,"plane|A")["pn"]),0.12466875,8e-6));checks+=1
	assert(float(block(ns,"B|C")["pn"])>0 and float(block(ns,"A|B")["pn"])>0 and float(block(ns,"plane|A")["pn"])>0);checks+=1
	assert(float(ns["max_normal_violation"])<4e-6);checks+=1
	assert(float(ns["max_cone_violation"])==0.0);checks+=1

	# --- Coupled friction blocks: stick and slide in the same island ---
	var mixed=E.mixed_friction_probe();var ms:Dictionary=mixed["solve"]
	assert(bool(ms["ok"]));checks+=1
	assert(String(block(ms,"A|B")["mode"])=="stick");checks+=1
	assert(String(block(ms,"B|C")["mode"])=="slide");checks+=1
	assert(String(block(ms,"plane|A")["mode"])=="stick");checks+=1
	var bc:Dictionary=block(ms,"B|C");var cone_limit:=float(mixed["world"]["mu_pair"])*float(bc["pn"])
	assert(close(Vector2(bc["pt"]).length(),cone_limit,1e-12));checks+=1
	assert(Vector2(block(ms,"A|B")["pt"]).length()<float(mixed["world"]["mu_pair"])*float(block(ms,"A|B")["pn"]));checks+=1
	assert(float(ms["max_cone_violation"])<1e-12);checks+=1

	# --- PGS order robustness on the same coupled graph ---
	var order=E.coupled_order_probe()
	assert(float(order["max_v"])<2e-6);checks+=1
	assert(float(order["max_w"])<3e-7);checks+=1
	assert(String(block(order["forward"],"B|C")["mode"])==String(block(order["reverse"],"B|C")["mode"]));checks+=1

	# --- Actual Thread island/snapshot execution and canonical join order ---
	var physical_hash:=F.world_hash(w);var pf=F.parallel_island_audit(w,false);var pr=F.parallel_island_audit(w,true)
	assert(bool(pf["ok"]) and bool(pr["ok"]));checks+=1
	assert(int(pf["threads_started"])==2 and int(pr["threads_started"])==2);checks+=1
	assert(String(pf["hash"])=="49e8c7b2fa0e1177f0e19d36ee85c4e22239ad95556c2c0a7c909d24fb47b34b");checks+=1
	assert(String(pr["hash"])==String(pf["hash"]));checks+=1
	assert(pf["results"].size()==2);checks+=1
	assert(String(pf["results"][0]["id"])=="main" and String(pf["results"][1]["id"])=="side");checks+=1
	assert(F.world_hash(w)==physical_hash);checks+=1

	# --- Deterministic replay ---
	var replay=E.graph_run(0.001,0.4)
	assert(String(replay["result"]["state_hash"])==String(r["state_hash"]));checks+=1
	assert(JSON.stringify(replay["world"]["events"])==JSON.stringify(w["events"]));checks+=1
	assert(JSON.stringify(replay["world"]["graph_events"])==JSON.stringify(w["graph_events"]));checks+=1

	# --- Fail closed ---
	var bad=F.new_world();var badr=F.advance(bad,0.1,{"dt":0.0})
	assert(not bool(badr["ok"]) and String(badr["code"])=="BAD_STEP");checks+=1
	var bad2=F.new_world();var badr2=F.advance(bad2,0.0,{"dt":0.001})
	assert(not bool(badr2["ok"]) and String(badr2["code"])=="DURATION_NONPOSITIVE");checks+=1

	print("FABRIC0.15 Multibody Convex Complementarity Graph Acceptance: PASS (%d assertions) merge=%.12f split=%.12f refine=(%s,%s,%s) state_refine=(%s,%s,%s) energy=(%s,%s,%s) normal=(%.9f,%.9f,%.9f) order=(%s,%s) parallel=%s hash=%s" % [checks,float(appear["time"]),float(disappear["time"]),String.num_scientific(e_coarse),String.num_scientific(e_medium),String.num_scientific(e_fine),String.num_scientific(s_coarse),String.num_scientific(s_medium),String.num_scientific(s_fine),String.num_scientific(r_coarse),String.num_scientific(r_medium),String.num_scientific(r_fine),float(block(ns,"B|C")["pn"]),float(block(ns,"A|B")["pn"]),float(block(ns,"plane|A")["pn"]),String.num_scientific(float(order["max_v"])),String.num_scientific(float(order["max_w"])),String(pf["hash"]),String(r["state_hash"])])
	quit(0)
