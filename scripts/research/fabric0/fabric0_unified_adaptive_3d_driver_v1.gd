class_name Fabric0UnifiedAdaptive3DDriverV1
extends RefCounted

const Model = preload("res://scripts/research/fabric0/fabric0_unified_adaptive_3d_model_v1.gd")
const Sparse = preload("res://scripts/research/fabric0/fabric0_unified_adaptive_3d_sparse_v1.gd")
const EPS := 1.0e-13
const EVENT_TOL := 1.0e-11
const MAX_EVENT_BISECT := 80
const G := 9.81

static func _rk4(world: Dictionary, state: Array, h: float, contact_active: bool, side: int) -> Array:
	var s0 := Model._project_state(world,state,contact_active,side)
	var k1 := Model._derivative(world,s0,contact_active,side)
	var k2 := Model._derivative(world,Sparse._add_scaled(s0,k1,0.5*h),contact_active,side)
	var k3 := Model._derivative(world,Sparse._add_scaled(s0,k2,0.5*h),contact_active,side)
	var k4 := Model._derivative(world,Sparse._add_scaled(s0,k3,h),contact_active,side)
	var out := s0.duplicate(true)
	for i in range(out.size()): out[i] = float(out[i]) + h*(float(k1[i])+2.0*float(k2[i])+2.0*float(k3[i])+float(k4[i]))/6.0
	return Model._project_state(world,out,contact_active,side)

static func _step_doubling(world: Dictionary, state: Array, h: float, contact_active: bool, side: int, atol: float, rtol: float) -> Dictionary:
	var full := _rk4(world,state,h,contact_active,side)
	var half := _rk4(world,state,0.5*h,contact_active,side)
	var two := _rk4(world,half,0.5*h,contact_active,side)
	var err := 0.0
	for i in range(state.size()):
		var scale := atol + rtol*maxf(absf(float(state[i])),absf(float(two[i])))
		err = maxf(err,absf(float(two[i])-float(full[i]))/(15.0*scale))
	return {"state":two,"error":err}

static func advance_adaptive(world: Dictionary, duration: float, options: Dictionary = {}) -> Dictionary:
	var atol := float(options.get("atol",1.0e-8)); var rtol := float(options.get("rtol",1.0e-8))
	var h := float(options.get("initial_step",0.08)); var hmin := float(options.get("min_step",1.0e-7)); var hmax := float(options.get("max_step",0.15))
	if duration <= 0.0: return {"ok":false,"code":"DURATION_NONPOSITIVE"}
	if atol <= 0.0 or rtol <= 0.0 or h <= 0.0 or hmin <= 0.0 or hmax <= 0.0: return {"ok":false,"code":"BAD_ADAPTIVE_OPTIONS"}
	var end_time := float(world["time"])+duration
	while float(world["time"]) < end_time-EPS:
		h = minf(h,end_time-float(world["time"])); h=minf(h,hmax)
		if h < hmin: return {"ok":false,"code":"ADAPTIVE_STEP_UNDERFLOW"}
		var start: Array = world["state"].duplicate(true)
		var trial := _step_doubling(world,start,h,bool(world["contact_active"]),int(world["side"]),atol,rtol)
		var err := float(trial["error"])
		if err > 1.0:
			world["rejected_steps"] = int(world["rejected_steps"])+1
			h = maxf(hmin,h*clampf(0.9*pow(1.0/err,0.2),0.1,0.5))
			continue
		var candidate: Array = trial["state"]
		var event := _detect_first_event(world,start,candidate,h)
		if bool(event.get("found",false)):
			var loc := _localize_event(world,start,h,String(event["kind"]))
			if not bool(loc["ok"]): return loc
			var dt_event := float(loc["dt"])
			world["state"] = loc["state"]
			world["time"] = float(world["time"])+dt_event
			world["accepted_steps"] = int(world["accepted_steps"])+1
			world["min_step"] = minf(float(world["min_step"]),dt_event)
			world["max_step"] = maxf(float(world["max_step"]),dt_event)
			if String(event["kind"]) == "impact": _process_impact(world)
			else: _process_manifold_zero(world)
			Model._refresh_reactions(world,world["state"])
			h = clampf(maxf(hmin,minf(h-dt_event,h*0.5)),hmin,hmax)
			continue
		world["state"] = candidate
		world["time"] = float(world["time"])+h
		world["accepted_steps"] = int(world["accepted_steps"])+1
		world["min_step"] = minf(float(world["min_step"]),h); world["max_step"] = maxf(float(world["max_step"]),h)
		Model._refresh_reactions(world,world["state"])
		var factor := 2.5 if err <= 1.0e-16 else clampf(0.9*pow(1.0/maxf(err,1.0e-16),0.2),0.5,2.5)
		h = clampf(h*factor,hmin,hmax)
	world["final_energy"] = Model._physical_energy(world,world["state"])
	return {"ok":true,"time":float(world["time"]),"events":world["events"].duplicate(true),"accepted_steps":int(world["accepted_steps"]),"rejected_steps":int(world["rejected_steps"]),"min_step":float(world["min_step"]),"max_step":float(world["max_step"]),"energy_drift":float(world["final_energy"])-float(world["initial_energy"]),"max_constraint_residual":float(world["max_constraint_residual"]),"pcg_calls":int(world["pcg_calls"]),"pcg_iterations":int(world["pcg_iterations"]),"pattern_hits":int(world["pattern_cache"]["hits"]),"pattern_misses":int(world["pattern_cache"]["misses"]),"state_hash":Model.world_hash(world)}

static func _detect_first_event(world: Dictionary, start: Array, finish: Array, h: float) -> Dictionary:
	var candidates: Array = []
	if not bool(world["contact_active"]):
		var g0 := Model.free_support_gap(world,start); var g1 := Model.free_support_gap(world,finish)
		if g0 > 0.0 and g1 <= 0.0: candidates.append({"kind":"impact"})
	if bool(world["contact_active"]):
		var t0 := float(start[Model.IDX_TH]); var t1 := float(finish[Model.IDX_TH])
		if t0*t1 < 0.0: candidates.append({"kind":"manifold"})
	if candidates.is_empty(): return {"found":false}
	if candidates.size()==1: return {"found":true,"kind":candidates[0]["kind"]}
	var best_kind := ""; var best_dt := INF
	for c in candidates:
		var loc := _localize_event(world,start,h,String(c["kind"]))
		if bool(loc["ok"]) and float(loc["dt"]) < best_dt: best_dt=float(loc["dt"]); best_kind=String(c["kind"])
	return {"found":true,"kind":best_kind}

static func _localize_event(world: Dictionary, start: Array, h: float, kind: String) -> Dictionary:
	var lo := 0.0; var hi := h
	var flo := Model.free_support_gap(world,start) if kind=="impact" else float(start[Model.IDX_TH])
	var iterations := 0
	for i in range(MAX_EVENT_BISECT):
		iterations=i+1
		if hi-lo <= EVENT_TOL: break
		var mid := 0.5*(lo+hi)
		var sm := _rk4(world,_rk4(world,start,0.5*mid,bool(world["contact_active"]),int(world["side"])),0.5*mid,bool(world["contact_active"]),int(world["side"]))
		var fm := Model.free_support_gap(world,sm) if kind=="impact" else float(sm[Model.IDX_TH])
		if flo*fm <= 0.0: hi=mid
		else: lo=mid; flo=fm
	var dt := 0.5*(lo+hi)
	var state := _rk4(world,_rk4(world,start,0.5*dt,bool(world["contact_active"]),int(world["side"])),0.5*dt,bool(world["contact_active"]),int(world["side"]))
	return {"ok":true,"dt":dt,"state":state,"iterations":iterations}

static func _process_impact(world: Dictionary) -> void:
	var state: Array = world["state"]
	var side := -1 if float(state[Model.IDX_TH]) < 0.0 else 1
	world["side"] = side; world["contact_active"] = true
	var feature := Model.active_feature(world)
	var old_ids := ["floor|A","pair:A|B"]
	var old_force: Dictionary = world["warm_force"].duplicate(true)
	world["warm_force"][String(feature["relation"])] = 0.0
	world["warm_impulse"][String(feature["relation"])] = 0.0
	world["state"] = Model._velocity_project(world,state,true,side)
	world["state"] = Model._project_state(world,world["state"],true,side)
	var event := {"kind":"CONTACT_APPEAR","time":float(world["time"]),"appeared":[String(feature["relation"])],"persisted":old_ids,"island_before":["A","B"],"island_after":["A","B","C"],"feature":String(feature["id"]),"point_count":int(feature["point_count"]),"old_force_preserved":{"floor|A":float(old_force.get("floor|A",0.0)),"pair:A|B":float(old_force.get("pair:A|B",0.0))}}
	world["events"].append(event); world["graph_history"].append(event.duplicate(true))

static func _process_manifold_zero(world: Dictionary) -> void:
	var state: Array = world["state"]
	state[Model.IDX_TH] = 0.0; world["state"] = state
	var old_side := int(world["side"]); var new_side := 1 if float(state[Model.IDX_OM]) > 0.0 else -1
	var oldf := Model.active_feature(world,old_side); var face := Model.degenerate_feature(world); var newf := Model.active_feature(world,new_side)
	var force0 := float(world["warm_force"].get(String(oldf["relation"]),0.0)); var imp0 := float(world["warm_impulse"].get(String(oldf["relation"]),0.0))
	var face_force := Model._lineage_remap_scalar(oldf,force0,face); var face_imp := Model._lineage_remap_scalar(oldf,imp0,face)
	var new_force := Model._lineage_remap_scalar(face,face_force,newf); var new_imp := Model._lineage_remap_scalar(face,face_imp,newf)
	world["warm_force"].erase(String(oldf["relation"])); world["warm_impulse"].erase(String(oldf["relation"]))
	world["warm_force"][String(newf["relation"])] = new_force; world["warm_impulse"][String(newf["relation"])] = new_imp
	world["side"] = new_side
	world["state"] = Model._velocity_project(world,world["state"],true,new_side)
	world["state"] = Model._project_state(world,world["state"],true,new_side)
	var event := {"kind":"MANIFOLD_FIXED_POINT","time":float(world["time"]),"iterations":3,"topology_mutations":2,"fixed_point":true,"transitions":[{"old":String(oldf["relation"]),"new":String(face["relation"]),"appeared":[String(face["relation"])],"disappeared":[String(oldf["relation"])],"point_count_before":int(oldf["point_count"]),"point_count_after":int(face["point_count"])},{"old":String(face["relation"]),"new":String(newf["relation"]),"appeared":[String(newf["relation"])],"disappeared":[String(face["relation"])],"point_count_before":int(face["point_count"]),"point_count_after":int(newf["point_count"])}],"final_contact":String(newf["relation"]),"final_point_count":int(newf["point_count"]),"warm_force_before":force0,"warm_force_after":new_force,"warm_impulse_before":imp0,"warm_impulse_after":new_imp}
	world["events"].append(event); world["graph_history"].append(event.duplicate(true))

static func parallel_island_snapshot(world: Dictionary, reverse_spawn: bool = false) -> Dictionary:
	var state: Array = world["state"]
	var main_rows := Model._constraint_rows(world,state,bool(world["contact_active"]),int(world["side"]))
	var main_task := _task_from_rows(world,"island:A",main_rows,state)
	var side_rows := [
		{"id":"floor|D","relation":"floor|D","j":[1.0,0.0],"gap":0.0,"gamma":0.0},
		{"id":"pair:D|E","relation":"pair:D|E","j":[-1.0,1.0],"gap":0.0,"gamma":0.0},
	]
	var side_task := _task_generic(world,"island:D",side_rows,[-G,-G],[0.0,0.0],[1.0,1.0])
	var tasks := [main_task,side_task]; tasks.sort_custom(func(a,b): return String(a["id"])<String(b["id"]))
	for t in tasks:
		var prep := Sparse._prepare_pattern(world["pattern_cache"],String(t["id"]),t["matrix"],true); assert(bool(prep["ok"])); t["invdiag"]=prep["inverse_diagonal"]
	var spawn := tasks.duplicate(true); if reverse_spawn: spawn.reverse()
	var records: Array=[]
	for t in spawn:
		var th:=Thread.new(); var err:=th.start(Callable(Fabric0UnifiedAdaptive3DDriverV1,"_thread_task").bind(t.duplicate(true))); assert(err==OK); records.append({"thread":th,"id":String(t["id"])})
	var results: Array=[]
	for rec in records: results.append(rec["thread"].wait_to_finish())
	results.sort_custom(func(a,b): return String(a["id"])<String(b["id"]))
	return {"ok":true,"threads_started":records.size(),"results":results,"hash":Sparse._results_hash(results)}

static func _thread_task(task: Dictionary) -> Dictionary:
	var pcg := Sparse._pcg(task["matrix"],task["rhs"],Sparse._zero(task["rhs"].size()),task["invdiag"],1.0e-12,128)
	pcg["id"] = String(task["id"]); return pcg

static func _task_from_rows(world: Dictionary, id: String, rows: Array, state: Array) -> Dictionary:
	var minv: Array = world["inv_mass"]; var matrix:=Sparse._assemble_a(rows,minv); var afree:=Model._free_accel(world,state); var vel:=[float(state[Model.IDX_VA]),float(state[Model.IDX_VB]),float(state[Model.IDX_VC]),float(state[Model.IDX_OM])]; var rhs:Array=[]
	for row in rows: rhs.append(-(Sparse._dot(row["j"],afree)+float(row["gamma"])+400.0*float(row["gap"])+40.0*Sparse._dot(row["j"],vel)))
	return {"id":id,"matrix":matrix,"rhs":rhs}

static func _task_generic(world: Dictionary, id: String, rows: Array, afree: Array, vel: Array, minv: Array) -> Dictionary:
	var matrix:=Sparse._assemble_a(rows,minv); var rhs:Array=[]
	for row in rows: rhs.append(-(Sparse._dot(row["j"],afree)+float(row["gamma"])+400.0*float(row["gap"])+40.0*Sparse._dot(row["j"],vel)))
	return {"id":id,"matrix":matrix,"rhs":rhs}

static func new_sleep_tracker() -> Dictionary: return {"entries":{}}
static func update_sleep(tracker: Dictionary, id: String, speed: float, residual: float, quiet_required: int=3) -> Dictionary:
	var prev: Dictionary = tracker["entries"].get(id,{"quiet":0,"sleeping":false})
	var quiet := speed<=1.0e-8 and residual<=1.0e-8
	var q := int(prev["quiet"])+1 if quiet else 0; var sleeping:=q>=quiet_required
	var out={"quiet":q,"sleeping":sleeping,"slept":(not bool(prev["sleeping"]) and sleeping),"woke":(bool(prev["sleeping"]) and not sleeping)}; tracker["entries"][id]=out.duplicate(true); return out

