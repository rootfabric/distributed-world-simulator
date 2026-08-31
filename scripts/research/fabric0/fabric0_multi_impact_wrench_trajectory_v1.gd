class_name Fabric0MultiImpactWrenchTrajectoryV1
extends RefCounted

const F=preload("res://scripts/research/fabric0/fabric0_general_convex_multipoint_mcp_v1.gd")
const Events=preload("res://scripts/research/fabric0/fabric0_general_convex_event_driver_v1.gd")
const EventSet=preload("res://scripts/research/fabric0/fabric0_simultaneous_impact_event_set_v1.gd")
const Impact=preload("res://scripts/research/fabric0/fabric0_simultaneous_impact_solver_v1.gd")
const FixedPoint=preload("res://scripts/research/fabric0/fabric0_impact_wrench_fixed_point_v1.gd")

const FIRST_HORIZON:=0.55
const SECOND_HORIZON:=0.01
const FINAL_TIME:=0.55

static func run(tolerance:float=1.0e-9,reverse_bodies:bool=false,reverse_members:bool=false)->Dictionary:
	if tolerance<=0.0:return {"ok":false,"code":"BAD_TOLERANCE"}
	var bodies:=_world()
	if reverse_bodies:bodies.reverse()
	var initial_linear:=F.total_linear_momentum(bodies)
	var initial_angular:=F.total_angular_momentum_origin(bodies)
	var initial_energy:=F.total_kinetic_energy(bodies)
	var events:Array=[]
	var energy_terms:Array=[]
	var current_time:=0.0

	var first_set:=EventSet.next_appearance_event_set(bodies,0.0,FIRST_HORIZON,tolerance,tolerance,256,64)
	if not bool(first_set.get("ok",false)):return {"ok":false,"code":"FIRST_EVENT_SET_FAILED","detail":first_set}
	if first_set["pair_ids"]!=["C|L","C|R"]:
		return {"ok":false,"code":"EVENT_SET_NOT_REFINED_ENOUGH_FOR_TRAJECTORY","stage":"FIRST","pair_ids":first_set["pair_ids"]}
	if reverse_members:first_set=_reverse_event_set(first_set)
	var first:=_solve_event(bodies,first_set,0.3,tolerance)
	if not bool(first.get("ok",false)):return {"ok":false,"code":"FIRST_EVENT_SOLVE_FAILED","detail":first}
	bodies=first["post_bodies"]
	current_time=float(first["relative_time"])
	energy_terms.append(float(first["normal_energy_delta"]));energy_terms.append(float(first["wrench_energy_delta"]))
	events.append(_event_record("FIRST",current_time,first))

	var deferred_subset:=_deferred_body_subset(bodies,first_set)
	if not bool(deferred_subset.get("ok",false)):
		return {"ok":false,"code":"DEFERRED_EVENT_ISLAND_FAILED","detail":deferred_subset}
	var second_set:=EventSet.next_appearance_event_set(deferred_subset["bodies"],0.0,SECOND_HORIZON,tolerance,tolerance,256,64)
	if not bool(second_set.get("ok",false)):return {"ok":false,"code":"SECOND_EVENT_SET_FAILED","detail":second_set}
	if second_set["pair_ids"]!=deferred_subset["pair_ids"]:
		return {"ok":false,"code":"UNEXPECTED_SECOND_EVENT_SET","pair_ids":second_set["pair_ids"],"expected":deferred_subset["pair_ids"]}
	if reverse_members:second_set=_reverse_event_set(second_set)
	var second:=_solve_event(bodies,second_set,0.2,tolerance)
	if not bool(second.get("ok",false)):return {"ok":false,"code":"SECOND_EVENT_SOLVE_FAILED","detail":second}
	bodies=second["post_bodies"]
	var second_absolute:=current_time+float(second["relative_time"])
	current_time=second_absolute
	energy_terms.append(float(second["normal_energy_delta"]));energy_terms.append(float(second["wrench_energy_delta"]))
	events.append(_event_record("SECOND",current_time,second))

	if current_time>FINAL_TIME:return {"ok":false,"code":"FINAL_TIME_OVERRUN","time":current_time}
	var flow_energy_before:=F.total_kinetic_energy(bodies)
	_advance_in_place(bodies,FINAL_TIME-current_time)
	current_time=FINAL_TIME
	var flow_energy_after:=F.total_kinetic_energy(bodies)
	var flow_energy_delta:=flow_energy_after-flow_energy_before
	energy_terms.append(flow_energy_delta)

	var final_linear:=F.total_linear_momentum(bodies)
	var final_angular:=F.total_angular_momentum_origin(bodies)
	var final_energy:=F.total_kinetic_energy(bodies)
	var expected_delta:=0.0
	for value in energy_terms:expected_delta+=float(value)
	var state:=_state(bodies)
	return {
		"ok":true,"time":current_time,"events":events,"state":state,"bodies":bodies,
		"initial_energy":initial_energy,"final_energy":final_energy,"energy_terms":energy_terms,"flow_energy_delta":flow_energy_delta,
		"energy_ledger_error":absf((final_energy-initial_energy)-expected_delta),
		"linear_momentum_error":(final_linear-initial_linear).length(),"angular_momentum_error":(final_angular-initial_angular).length(),
		"signature":JSON.stringify({"events":events,"state":state},"",false),
	}

static func _solve_event(bodies:Array,event_set:Dictionary,restitution:float,tolerance:float=1.0e-9)->Dictionary:
	var fixed:=FixedPoint.solve_event_set(
		bodies,event_set,restitution,
		{"mu_tangent":0.15,"mu_rolling":0.04,"mu_torsion":0.03,"tolerance":1.0e-12,"iterations":30000},
		{"outer_tolerance":5.0e-10,"outer_iterations":256,"outer_relaxation":1.0,"impact_options":{"max_event_uncertainty":maxf(1.0e-6,4.0*tolerance),"max_boundary_gap":maxf(5.0e-6,2.0*tolerance),"impact_tolerance":1.0e-11,"impact_iterations":1024,"normal_regularization":1.0e-9}}
	)
	if not bool(fixed.get("ok",false)):
		return {"ok":false,"code":"IMPACT_WRENCH_FIXED_POINT_FAILED","detail":fixed}
	var persistent:=false
	for contact_any in fixed["contacts"]:
		var contact:Dictionary=contact_any
		var vn:=F.Model.contact_velocity(fixed["post_bodies"],contact).dot(Vector3(contact["normal"]))
		if vn<=1.0e-10:persistent=true
	var canonical_pair_ids:Array=event_set["pair_ids"].duplicate();canonical_pair_ids.sort()
	return {
		"ok":true,"relative_time":float(event_set["time"]),"pair_ids":canonical_pair_ids,
		"fixed":fixed,"post_bodies":fixed["post_bodies"],
		"normal_energy_delta":float(fixed["normal_energy_delta"]),"wrench_energy_delta":float(fixed["wrench_energy_delta"]),
		"normal_wrench_cross_drift":float(fixed["max_normal_complementarity_violation"]),"persistent_after":persistent,
	}

static func _event_record(label:String,time:float,solved:Dictionary)->Dictionary:
	var fixed:Dictionary=solved["fixed"]
	var modes:Dictionary={}
	var wrench_impulses:Dictionary={}
	var max_tangent:=0.0
	var max_moment:=0.0
	for pair_any in fixed["wrench"]["per_pair"].keys():
		var pair:=String(pair_any)
		var per:Dictionary=fixed["wrench"]["per_pair"][pair]
		modes[pair]=per["modes"]
		wrench_impulses[pair]=per["generalized_impulse"]
		max_tangent=maxf(max_tangent,Vector3(per["force"]).length())
		max_moment=maxf(max_moment,Vector3(per["moment"]).length())
	return {
		"label":label,"time":time,"pair_ids":solved["pair_ids"],"normal_rows":int(fixed["contact_rows"]),
		"normal_pair_impulses":fixed["pair_impulses"],"wrench_modes":modes,"wrench_generalized_impulses":wrench_impulses,
		"max_tangent_impulse":max_tangent,"max_moment_impulse":max_moment,
		"normal_energy_delta":float(solved["normal_energy_delta"]),"wrench_energy_delta":float(solved["wrench_energy_delta"]),
		"normal_wrench_cross_drift":float(solved["normal_wrench_cross_drift"]),"persistent_after":bool(solved["persistent_after"]),
		"outer_iterations":int(fixed["outer_iterations"]),"outer_delta":float(fixed["outer_delta"]),
		"initial_reopened_normal_residual":float(fixed["initial_reopened_normal_residual"]),
		"wrench_symmetry_error":float(fixed["wrench"]["matrix_symmetry_error"]),"max_cross_patch_coupling":float(fixed["wrench"]["max_cross_patch_coupling"]),"wrench_ledger_error":float(fixed["wrench"]["energy_ledger_error"]),
		"event_energy_ledger_error":float(fixed["energy_ledger_error"]),
	}

static func _deferred_body_subset(bodies:Array,first_set:Dictionary)->Dictionary:
	var deferred:Array=first_set.get("deferred_events",[])
	if deferred.size()<2:
		return {"ok":false,"code":"TOO_FEW_DEFERRED_EVENTS","count":deferred.size()}
	var earliest:=float(Dictionary(deferred[0])["time"])
	var resolution:=maxf(float(first_set.get("simultaneous_resolution",0.0)),float(first_set.get("root_tolerance",0.0)))
	var pair_ids:Array=[]
	var body_ids:Dictionary={}
	for event_any in deferred:
		var event:Dictionary=event_any
		if absf(float(event["time"])-earliest)>maxf(4.0*resolution,1.0e-8):
			continue
		var id:=String(event["id"])
		pair_ids.append(id)
		var split:=id.split("|")
		if split.size()!=2:return {"ok":false,"code":"BAD_DEFERRED_PAIR_ID","id":id}
		body_ids[String(split[0])]=true;body_ids[String(split[1])]=true
	if pair_ids.size()<2:return {"ok":false,"code":"NO_DEFERRED_SIMULTANEOUS_GROUP","pairs":pair_ids}
	pair_ids.sort()
	var subset:Array=[]
	for body_any in bodies:
		var body:Dictionary=body_any
		if body_ids.has(String(body["id"])):subset.append(body)
	if subset.size()<3:return {"ok":false,"code":"DEFERRED_ISLAND_TOO_SMALL","body_count":subset.size()}
	return {"ok":true,"bodies":subset,"pair_ids":pair_ids,"body_ids":body_ids.keys()}

static func _world()->Array:
	var center_shape:=F.box_shape("trajectory_017d_center",Vector3(0.5,0.7,0.5))
	var incoming_shape:=F.box_shape("trajectory_017d_incoming",Vector3(0.5,0.5,0.5))
	return [
		# FIRST group: both x-face roots are exactly t=0.5; y offsets create angular impulse without pre-impact rotation.
		F.new_body("L",incoming_shape,Vector3(-2,0.3,0),Quaternion.IDENTITY,1.0,Vector3(0.2,0.2,0.2),Vector3(2,0.35,0)),
		F.new_body("C",center_shape,Vector3.ZERO,Quaternion.IDENTITY,1.5,Vector3(0.3,0.35,0.4)),
		F.new_body("R",incoming_shape,Vector3(2.25,-0.2,0),Quaternion.IDENTITY,0.8,Vector3(0.18,0.22,0.2),Vector3(-2.5,-0.25,0)),
		# SECOND group: independent simultaneous pair set at t=0.5002 in absolute world time.
		F.new_body("P",incoming_shape,Vector3(-2.0004,4.3,0),Quaternion.IDENTITY,1.1,Vector3(0.21,0.23,0.2),Vector3(2,0.30,0)),
		F.new_body("Q",center_shape,Vector3(0,4,0),Quaternion.IDENTITY,1.4,Vector3(0.29,0.34,0.39)),
		F.new_body("S",incoming_shape,Vector3(2.2505,3.8,0),Quaternion.IDENTITY,0.9,Vector3(0.19,0.21,0.2),Vector3(-2.5,-0.20,0)),
	]

static func _advance_in_place(bodies:Array,dt:float)->void:
	if dt<=0.0:return
	for i in range(bodies.size()):bodies[i]=Events.body_at(bodies[i],dt)

static func _reverse_event_set(source:Dictionary)->Dictionary:
	var out:=source.duplicate(true);out["members"].reverse();out["pair_ids"].reverse();return out

static func _state(bodies:Array)->Array:
	var work:=bodies.duplicate(true);work.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return String(a["id"])<String(b["id"]))
	var out:Array=[]
	for body_any in work:
		var b:Dictionary=body_any;var p:Vector3=b["p"];var q:Quaternion=b["q"];var v:Vector3=b["v"];var w:Vector3=b["w"]
		out.append([String(b["id"]),p.x,p.y,p.z,q.x,q.y,q.z,q.w,v.x,v.y,v.z,w.x,w.y,w.z])
	return out

static func state_error(a:Dictionary,b:Dictionary)->float:
	var sa:Array=a["state"];var sb:Array=b["state"]
	if sa.size()!=sb.size():return INF
	var maximum:=0.0
	for i in range(sa.size()):
		if String(sa[i][0])!=String(sb[i][0]):return INF
		for j in range(1,sa[i].size()):maximum=maxf(maximum,absf(float(sa[i][j])-float(sb[i][j])))
	return maximum

static func event_time_error(a:Dictionary,b:Dictionary)->float:
	if a["events"].size()!=b["events"].size():return INF
	var maximum:=0.0
	for i in range(a["events"].size()):maximum=maxf(maximum,absf(float(a["events"][i]["time"])-float(b["events"][i]["time"])))
	return maximum
