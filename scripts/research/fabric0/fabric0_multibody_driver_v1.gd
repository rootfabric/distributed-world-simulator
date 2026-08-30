class_name Fabric0MultibodyDriverV1
extends RefCounted

const Model=preload("res://scripts/research/fabric0/fabric0_multibody_convex_model_v1.gd")
const Solver=preload("res://scripts/research/fabric0/fabric0_multibody_complementarity_v1.gd")
const EPS:=1.0e-12

static func initialize(world:Dictionary)->void:
	if not world["contacts"].is_empty():return
	var contacts:=Model.discover_contacts(world)
	var init:=Solver.solve(world,contacts,1.0/120.0,false)
	world["contacts"]=_contact_state(contacts,init["blocks"])
	world["initial_components"]=Model.dynamic_components(world,contacts)
	world["initial_energy"]=Model.total_energy(world);world["final_energy"]=world["initial_energy"]

static func advance(world:Dictionary,duration:float,options:Dictionary={})->Dictionary:
	if duration<=0.0:return {"ok":false,"code":"DURATION_NONPOSITIVE"}
	var dt:=float(options.get("dt",0.001));if dt<=0.0:return {"ok":false,"code":"BAD_STEP"}
	var end_time:=float(world["time"])+duration
	initialize(world)
	while float(world["time"])<end_time-EPS:
		var h:=minf(dt,end_time-float(world["time"]))
		if not bool(world.get("release_started",false)) and float(world["time"])<float(world["release_time"]) and float(world["time"])+h>float(world["release_time"]):
			h=float(world["release_time"])-float(world["time"])
		var step:=_step(world,h)
		if not bool(step["ok"]):return step
		if not bool(world.get("release_started",false)) and absf(float(world["time"])-float(world["release_time"]))<=1.0e-12:
			world["release_started"]=true
			world["events"].append({"kind":"SOURCE_CHANGE","time":float(world["time"]),"id":"drive:D","old_force":world["drive_force"],"new_force":world["release_force"]})
	world["final_energy"]=Model.total_energy(world)
	return {
		"ok":true,"time":float(world["time"]),"events":world["events"].duplicate(true),"graph_events":world["graph_events"].duplicate(true),"mode_events":world["mode_events"].duplicate(true),
		"contact_solves":int(world["contact_solves"]),"contact_iterations":int(world["contact_iterations"]),"max_normal_violation":float(world["max_normal_violation"]),"max_cone_violation":float(world["max_cone_violation"]),
		"min_normal_impulse":float(world["min_normal_impulse"]),"max_penetration":float(world["max_penetration"]),"max_internal_linear_momentum_error":float(world["max_internal_linear_momentum_error"]),"max_internal_angular_momentum_error":float(world["max_internal_angular_momentum_error"]),
		"contact_dissipation":float(world["contact_dissipation"]),"contact_gain":float(world["contact_gain"]),"external_work":float(world["external_work"]),"projection_energy_delta":float(world["projection_energy_delta"]),"projection_distance":float(world["projection_distance"]),"energy_delta":float(world["final_energy"])-float(world["initial_energy"]),"energy_ledger_residual":energy_ledger_residual(world),
		"state_hash":Model.graph_hash(world),"components":Model.dynamic_components(world,Model.discover_contacts(world)),
	}

static func energy_ledger_residual(world:Dictionary)->float:
	var contact_delta:=-float(world["contact_dissipation"])+float(world["contact_gain"])
	var edelta:=float(world["final_energy"])-float(world["initial_energy"])
	return absf(edelta-float(world["external_work"])-contact_delta-float(world["projection_energy_delta"]))

static func _step(world:Dictionary,h:float)->Dictionary:
	var t0:=float(world["time"]);var gaps0:=_all_gaps(world);var old_contacts:Dictionary=world["contacts"].duplicate(true);var old_components:=_components_from_state(world,old_contacts)
	_apply_external_velocity(world,h)
	var pre:=Model.discover_contacts(world);var solved_pre:=Solver.solve(world,pre,h,false);if not bool(solved_pre["ok"]):return solved_pre
	var forced_times:={}
	for c in pre:
		var id:=String(c["id"]);var block:Dictionary=solved_pre["blocks"][id]
		if old_contacts.has(id) and float(block["pn"])<=1.0e-10 and float(block["vn_after"])>1.0e-4:
			world["suppressed"][id]=true
			forced_times[id]=t0
	var source_force:=_source_force(world)
	var p_before_source:=Vector3(Model.body(world,"D")["p"])
	_integrate_configuration(world,h)
	var p_after_source:=Vector3(Model.body(world,"D")["p"]);world["external_work"]=float(world["external_work"])+source_force.dot(p_after_source-p_before_source)
	var gaps1:=_all_gaps(world)
	for id in world["suppressed"].keys():
		if float(gaps1.get(id,0.0))>float(world["release_slop"]):
			world["suppressed"].erase(id)
	var post:=Model.discover_contacts(world)
	if not _same_contact_ids(pre,post):
		_project_new_contacts(world,pre,post)
		post=Model.discover_contacts(world)
	var final_blocks:Dictionary=solved_pre["blocks"]
	if not _same_contact_ids(pre,post):
		var solved_post:=Solver.solve(world,post,h,false)
		if not bool(solved_post["ok"]):return solved_post
		final_blocks=solved_post["blocks"]
	_record_topology(world,old_contacts,post,final_blocks,old_components,gaps0,gaps1,t0,h,forced_times)
	_record_modes(world,old_contacts,post,final_blocks,t0+h)
	world["contacts"]=_contact_state(post,final_blocks)
	world["time"]=t0+h
	for c in post:world["max_penetration"]=maxf(float(world["max_penetration"]),maxf(0.0,-float(c["gap"])))
	return {"ok":true}

static func _project_new_contacts(world:Dictionary,pre:Array,post:Array)->void:
	var old_ids:={}
	for c in pre:old_ids[String(c["id"])]=true
	for c in post:
		var id:=String(c["id"])
		if old_ids.has(id) or float(c["gap"])>=0.0:continue
		var before:=Model.total_energy(world);var sep:=-float(c["gap"]);var n:Vector3=c["normal"]
		if int(c["a"])<0:
			var b:Dictionary=world["bodies"][int(c["b"])];b["p"]=Vector3(b["p"])+n*sep
		else:
			var a:Dictionary=world["bodies"][int(c["a"])];var b2:Dictionary=world["bodies"][int(c["b"])]
			var wa:=float(a["inv_mass"])/(float(a["inv_mass"])+float(b2["inv_mass"]));var wb:=1.0-wa
			a["p"]=Vector3(a["p"])-n*sep*wa;b2["p"]=Vector3(b2["p"])+n*sep*wb
		world["projection_distance"]=float(world["projection_distance"])+sep
		world["projection_energy_delta"]=float(world["projection_energy_delta"])+(Model.total_energy(world)-before)

static func _same_contact_ids(a:Array,b:Array)->bool:
	if a.size()!=b.size():return false
	for i in range(a.size()):
		if String(a[i]["id"])!=String(b[i]["id"]):return false
	return true

static func _apply_external_velocity(world:Dictionary,h:float)->void:
	for b in world["bodies"]:
		var force:=Vector3(world["gravity"])*float(b["mass"])
		if String(b["id"])=="D":force+=_source_force(world)
		b["v"]=Vector3(b["v"])+force*float(b["inv_mass"])*h
		var w:Vector3=b["w"];var iw:=Model.inertia_mul(b,w);var alpha:=Model.inertia_inv_mul(b,-w.cross(iw));b["w"]=w+alpha*h

static func _source_force(world:Dictionary)->Vector3:
	return Vector3(world["release_force"]) if bool(world.get("release_started",false)) else Vector3(world["drive_force"])

static func _integrate_configuration(world:Dictionary,h:float)->void:
	for b in world["bodies"]:
		b["p"]=Vector3(b["p"])+Vector3(b["v"])*h
		var w:Vector3=b["w"];var angle:=w.length()*h;var q:Quaternion=b["q"]
		if angle>EPS:q=(Quaternion(w.normalized(),angle)*q).normalized()
		else:q=q.normalized()
		b["q"]=q

static func _contact_state(contacts:Array,blocks:Dictionary)->Dictionary:
	var out:={}
	for c in contacts:
		var id:=String(c["id"]);var b:Dictionary=blocks.get(id,{"mode":"stick","pn":0.0,"pt":Vector2.ZERO})
		out[id]={"mode":String(b["mode"]),"pn":float(b["pn"]),"pt":b["pt"],"a":int(c["a"]),"b":int(c["b"]),"gap":float(c["gap"])}
	return out

static func _record_modes(world:Dictionary,old_contacts:Dictionary,contacts:Array,blocks:Dictionary,time:float)->void:
	for c in contacts:
		var id:=String(c["id"]);var mode:=String(blocks[id]["mode"]);var prev:=String(old_contacts[id]["mode"]) if old_contacts.has(id) else ""
		if prev!=mode:
			world["mode_events"].append({"kind":"MODE_CHANGE","time":time,"id":id,"old":prev,"new":mode})

static func _record_topology(world:Dictionary,old_contacts:Dictionary,contacts:Array,blocks:Dictionary,old_components:Array,gaps0:Dictionary,gaps1:Dictionary,t0:float,h:float,forced_times:Dictionary={})->void:
	var new_ids:={};for c in contacts:new_ids[String(c["id"])]=c
	var appeared:Array=[];var disappeared:Array=[]
	for id in new_ids.keys():
		if not old_contacts.has(id):appeared.append(String(id))
	for id in old_contacts.keys():
		if not new_ids.has(id):disappeared.append(String(id))
	appeared.sort();disappeared.sort()
	for id in appeared:
		var te:=_cross_time(float(gaps0.get(id,1.0)),float(gaps1.get(id,-1.0)),0.0,t0,h)
		var c:Dictionary=new_ids[id];var b:Dictionary=blocks[id]
		world["events"].append({"kind":"CONTACT_APPEAR","time":te,"id":id,"mode":String(b["mode"]),"normal_impulse":float(b["pn"]),"tangent_impulse":b["pt"],"gap":float(c["gap"])})
	for id in disappeared:
		var te:=float(forced_times[id]) if forced_times.has(id) else _cross_time(float(gaps0.get(id,0.0)),float(gaps1.get(id,float(world["release_slop"])*2.0)),float(world["release_slop"]),t0,h)
		world["events"].append({"kind":"CONTACT_DISAPPEAR","time":te,"id":id,"reason":"COMPLEMENTARITY_SEPARATION" if forced_times.has(id) else "GAP_SEPARATION"})
	var new_components:=Model.dynamic_components(world,contacts)
	if new_components.size()<old_components.size():
		var e={"kind":"ISLAND_MERGE","time":_first_contact_time(world,appeared,t0,h,gaps0,gaps1),"before":old_components,"after":new_components};world["events"].append(e);world["graph_events"].append(e)
	elif new_components.size()>old_components.size():
		var split_time:=_first_contact_time(world,disappeared,t0,h,gaps0,gaps1)
		for id in disappeared:
			if forced_times.has(id):split_time=minf(split_time,float(forced_times[id]))
		var e2={"kind":"ISLAND_SPLIT","time":split_time,"before":old_components,"after":new_components};world["events"].append(e2);world["graph_events"].append(e2)

static func _components_from_state(world:Dictionary,state:Dictionary)->Array:
	var contacts:Array=[]
	for id in state.keys():
		var s:Dictionary=state[id]
		if int(s["a"])>=0:contacts.append({"a":int(s["a"]),"b":int(s["b"])})
	return Model.dynamic_components(world,contacts)

static func _cross_time(g0:float,g1:float,threshold:float,t0:float,h:float)->float:
	var a:=g0-threshold;var b:=g1-threshold
	if absf(a-b)<=EPS:return t0+h
	return t0+h*clampf(a/(a-b),0.0,1.0)
static func _first_contact_time(world:Dictionary,ids:Array,t0:float,h:float,g0:Dictionary,g1:Dictionary)->float:
	if ids.is_empty():return t0+h
	var best:=t0+h
	for id in ids:
		var threshold:=0.0 if float(g1.get(id,0.0))<=float(world["release_slop"]) else float(world["release_slop"])
		best=minf(best,_cross_time(float(g0.get(id,0.0)),float(g1.get(id,0.0)),threshold,t0,h))
	return best

static func _all_gaps(world:Dictionary)->Dictionary:
	var out:={}
	for j in range(world["bodies"].size()):out["plane|"+String(world["bodies"][j]["id"])]=float(Model.contact_geometry(world,-1,j)["gap"])
	for i in range(world["bodies"].size()):
		for j in range(i+1,world["bodies"].size()):
			var id:=Model.pair_id(String(world["bodies"][i]["id"]),String(world["bodies"][j]["id"]));out[id]=float(Model.contact_geometry(world,i,j)["gap"])
	return out

static func parallel_island_audit(world:Dictionary,reverse_spawn:bool=false)->Dictionary:
	var main:=_snapshot_world(world,"main")
	var side:=Model.new_world();Model.body(side,"D")["p"]=Vector3(3.0,0.08,0.5);Model.body(side,"D")["v"]=Vector3.ZERO
	var side_task:=_snapshot_world(side,"side")
	var tasks:=[main,side_task];tasks.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return String(a["id"])<String(b["id"]))
	var spawn:=tasks.duplicate(true);if reverse_spawn:spawn.reverse()
	var threads:Array=[]
	for task in spawn:
		var th:=Thread.new();var err:=th.start(Callable(Fabric0MultibodyDriverV1,"_thread_solve").bind(task));assert(err==OK);threads.append(th)
	var results:Array=[];for th in threads:results.append(th.wait_to_finish());results.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return String(a["id"])<String(b["id"]))
	return {"ok":true,"threads_started":threads.size(),"results":results,"hash":Model.Sparse._sha(JSON.stringify(results,"",false))}

static func _snapshot_world(world:Dictionary,id:String)->Dictionary:
	var bodies:Array=[]
	for b in world["bodies"]:bodies.append(b.duplicate(true))
	return {"id":id,"bodies":bodies,"mu_plane":float(world["mu_plane"]),"mu_pair":float(world["mu_pair"]),"pair_restitution":0.0,"contact_slop":float(world["contact_slop"]),"release_slop":float(world["release_slop"]),"beta":float(world["beta"]),"solver_iterations":int(world["solver_iterations"]),"gravity":world["gravity"]}

static func _thread_solve(task:Dictionary)->Dictionary:
	var w={"bodies":task["bodies"],"contacts":{},"mu_plane":task["mu_plane"],"mu_pair":task["mu_pair"],"pair_restitution":task["pair_restitution"],"contact_slop":task["contact_slop"],"release_slop":task["release_slop"],"beta":task["beta"],"solver_iterations":task["solver_iterations"],"gravity":task["gravity"],"max_internal_linear_momentum_error":0.0,"max_internal_angular_momentum_error":0.0,"max_normal_violation":0.0,"max_cone_violation":0.0,"min_normal_impulse":INF,"contact_iterations":0,"contact_solves":0,"contact_dissipation":0.0,"contact_gain":0.0}
	for b in w["bodies"]:b["v"]=Vector3(b["v"])+Vector3(w["gravity"])*(1.0/240.0)
	var cs:=Model.discover_contacts(w);var s:=Solver.solve(w,cs,1.0/240.0,false);var blocks:Array=[]
	for c in cs:
		var idc:=String(c["id"]);blocks.append({"id":idc,"pn":float(s["blocks"][idc]["pn"]),"pt":s["blocks"][idc]["pt"],"mode":String(s["blocks"][idc]["mode"])})
	return {"id":String(task["id"]),"contacts":blocks,"components":Model.dynamic_components(w,cs)}
