class_name Fabric0SimultaneousImpactSolverExperimentsV1
extends RefCounted

const F = preload("res://scripts/research/fabric0/fabric0_general_convex_multipoint_mcp_v1.gd")
const EventSet = preload("res://scripts/research/fabric0/fabric0_simultaneous_impact_event_set_v1.gd")
const Impact = preload("res://scripts/research/fabric0/fabric0_simultaneous_impact_solver_v1.gd")

static func coupled_three_body_probe(restitution:float=1.0,tolerance:float=1.0e-9,reverse_bodies:bool=false,reverse_members:bool=false)->Dictionary:
	var bodies:=three_body_world()
	if reverse_bodies:
		bodies.reverse()
	var event_set:=EventSet.next_appearance_event_set(bodies,0.0,0.6,tolerance,tolerance,192,16)
	if not bool(event_set.get("ok",false)):
		return event_set
	if reverse_members:
		event_set=event_set.duplicate(true)
		event_set["members"].reverse()
		event_set["pair_ids"].reverse()
	var input_signature:=velocity_signature(bodies)
	var solved:=Impact.solve_event_set(bodies,event_set,restitution,{"max_event_uncertainty":1.0e-6,"impact_tolerance":1.0e-11,"impact_iterations":512,"normal_regularization":1.0e-9})
	solved["input_before"]=input_signature
	solved["input_after"]=velocity_signature(bodies)
	return solved


static func offset_three_body_probe(restitution:float=0.35,tolerance:float=1.0e-9,reverse_bodies:bool=false,reverse_members:bool=false)->Dictionary:
	var bodies:=offset_three_body_world()
	if reverse_bodies:
		bodies.reverse()
	var event_set:=EventSet.next_appearance_event_set(bodies,0.0,0.6,tolerance,tolerance,192,16)
	if not bool(event_set.get("ok",false)):
		return event_set
	if reverse_members:
		event_set=event_set.duplicate(true)
		event_set["members"].reverse()
		event_set["pair_ids"].reverse()
	return Impact.solve_event_set(bodies,event_set,restitution,{"max_event_uncertainty":1.0e-6,"impact_tolerance":1.0e-11,"impact_iterations":512,"normal_regularization":1.0e-9})

static func offset_three_body_world()->Array:
	var center_shape:=F.box_shape("offset_center_box",Vector3(0.5,0.7,0.5))
	var incoming_shape:=F.box_shape("offset_incoming_box",Vector3(0.5,0.5,0.5))
	return [
		F.new_body("L",incoming_shape,Vector3(-2,0.3,0),Quaternion.IDENTITY,1.0,Vector3(0.2,0.2,0.2),Vector3(2,0,0)),
		F.new_body("C",center_shape,Vector3.ZERO,Quaternion.IDENTITY,1.5,Vector3(0.3,0.35,0.4)),
		F.new_body("R",incoming_shape,Vector3(2.25,-0.2,0),Quaternion.IDENTITY,0.8,Vector3(0.18,0.22,0.2),Vector3(-2.5,0,0)),
	]

static func under_refined_probe()->Dictionary:
	var bodies:=five_body_world()
	var event_set:=EventSet.next_appearance_event_set(bodies,0.0,0.6,1.0e-3,1.0e-3,192,64)
	if not bool(event_set.get("ok",false)):
		return event_set
	return Impact.solve_event_set(bodies,event_set,1.0,{"max_event_uncertainty":1.0e-6})

static func restitution_probe(restitution:float)->Dictionary:
	return coupled_three_body_probe(restitution,1.0e-10)

static func sequential_reference(reverse:bool=false,restitution:float=1.0)->Dictionary:
	var bodies:=three_body_world()
	var pairs:Array=[["L","C"],["C","R"]]
	if reverse:
		pairs.reverse()
	for pair_any in pairs:
		var pair:Array=pair_any
		_apply_pair_impact(bodies,String(pair[0]),String(pair[1]),restitution)
	return {"state":velocity_signature(bodies),"energy":F.total_kinetic_energy(bodies),"linear":F.total_linear_momentum(bodies)}

static func three_body_world()->Array:
	var shape:=F.box_shape("impact_solve_box",Vector3(0.5,0.5,0.5))
	return [
		F.new_body("L",shape,Vector3(-2,0,0),Quaternion.IDENTITY,1.0,Vector3(0.2,0.2,0.2),Vector3(2,0,0)),
		F.new_body("C",shape,Vector3.ZERO),
		F.new_body("R",shape,Vector3(2,0,0),Quaternion.IDENTITY,1.0,Vector3(0.2,0.2,0.2),Vector3(-2,0,0)),
	]

static func five_body_world()->Array:
	var shape:=F.box_shape("impact_solve_five_box",Vector3(0.5,0.5,0.5))
	return [
		F.new_body("L",shape,Vector3(-2,0,0),Quaternion.IDENTITY,1.0,Vector3(0.2,0.2,0.2),Vector3(2,0,0)),
		F.new_body("C",shape,Vector3.ZERO),
		F.new_body("R",shape,Vector3(2,0,0),Quaternion.IDENTITY,1.0,Vector3(0.2,0.2,0.2),Vector3(-2,0,0)),
		F.new_body("P",shape,Vector3(-2.0004,4,0),Quaternion.IDENTITY,1.0,Vector3(0.2,0.2,0.2),Vector3(2,0,0)),
		F.new_body("Q",shape,Vector3(0,4,0)),
	]

static func velocity_signature(bodies:Array)->Array:
	var work:=bodies.duplicate(true)
	work.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return String(a["id"])<String(b["id"]))
	var out:Array=[]
	for body_any in work:
		var body:Dictionary=body_any
		var v:Vector3=body["v"]
		var w:Vector3=body["w"]
		out.append([String(body["id"]),v.x,v.y,v.z,w.x,w.y,w.z])
	return out

static func state_error(a:Array,b:Array)->float:
	if a.size()!=b.size():return INF
	var maximum:=0.0
	for i in range(a.size()):
		if String(a[i][0])!=String(b[i][0]):return INF
		for j in range(1,a[i].size()):
			maximum=maxf(maximum,absf(float(a[i][j])-float(b[i][j])))
	return maximum

static func _apply_pair_impact(bodies:Array,a_id:String,b_id:String,restitution:float)->void:
	var index:Dictionary={}
	for i in range(bodies.size()):index[String(bodies[i]["id"])]=i
	var ai:=int(index[a_id])
	var bi:=int(index[b_id])
	var a:Dictionary=bodies[ai]
	var b:Dictionary=bodies[bi]
	var normal:=(Vector3(b["p"])-Vector3(a["p"])).normalized()
	var relative:=Vector3(b["v"])-Vector3(a["v"])
	var vn:=relative.dot(normal)
	if vn>=0.0:return
	var effective:=float(a["inv_mass"])+float(b["inv_mass"])
	var impulse:=-(1.0+restitution)*vn/effective
	a["v"]=Vector3(a["v"])-normal*impulse*float(a["inv_mass"])
	b["v"]=Vector3(b["v"])+normal*impulse*float(b["inv_mass"])
