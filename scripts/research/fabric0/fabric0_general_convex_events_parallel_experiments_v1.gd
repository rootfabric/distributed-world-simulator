class_name Fabric0GeneralConvexEventsParallelExperimentsV1
extends RefCounted

const F=preload("res://scripts/research/fabric0/fabric0_general_convex_multipoint_mcp_v1.gd")
const Events=preload("res://scripts/research/fabric0/fabric0_general_convex_event_driver_v1.gd")
const Parallel=preload("res://scripts/research/fabric0/fabric0_general_convex_parallel_islands_v1.gd")

static func contact_event_probe(tolerance:float=1.0e-9)->Dictionary:
	var shape:=F.box_shape("box",Vector3(0.5,0.5,0.5))
	var a:=F.new_body("A",shape,Vector3.ZERO)
	var incoming:=F.new_body("B",shape,Vector3(2,0,0),Quaternion.IDENTITY,1.0,Vector3(0.2,0.2,0.2),Vector3(-2,0,0))
	var support:=F.new_body("S",shape,Vector3.ZERO)
	var outgoing:=F.new_body("T",shape,Vector3(0.8,0,0),Quaternion.IDENTITY,1.0,Vector3(0.2,0.2,0.2),Vector3(2,0,0))
	return {
		"a":a,"incoming":incoming,"support":support,"outgoing":outgoing,
		"appear_candidate":Events.swept_candidate(a,incoming,0.0,0.75),
		"appear":Events.transition_event(a,incoming,0.0,0.75,true,tolerance,128),
		"disappear":Events.transition_event(support,outgoing,0.0,0.4,false,tolerance,128),
	}

static func persistent_event_manifold_probe()->Dictionary:
	var event:=contact_event_probe(1.0e-10)
	var first:=Events.build_persistent_manifold_at(event["a"],event["incoming"],0.51)
	var second:=Events.build_persistent_manifold_at(event["a"],event["incoming"],0.515,first.get("manifold",{}))
	return {"event":event,"first":first,"second":second}

static func mode_transition_probe(tolerance:float=1.0e-8)->Dictionary:
	var shape:=F.box_shape("box",Vector3(0.5,0.5,0.5))
	var low:Array=[
		F.new_body("L",shape,Vector3.ZERO,Quaternion.IDENTITY,1.0,Vector3(0.2,0.2,0.2),Vector3(0,0,1)),
		F.new_body("U",shape,Vector3(0,0,0.95),Quaternion.IDENTITY,1.0,Vector3(0.2,0.2,0.2),Vector3(0.01,0,-1)),
	]
	var contacts:=_pair_contacts(low,0,1,0.2)
	var high:=low.duplicate(true)
	high[1]["v"]=Vector3(5,0,-1)
	var options:=_friction_options()
	var low_solve:=F.solve_contacts(low.duplicate(true),contacts.duplicate(true),0.01,options)
	var high_solve:=F.solve_contacts(high.duplicate(true),contacts.duplicate(true),0.01,options)
	var id:=String(low_solve["canonical_ids"][0])
	var event:=Events.localize_mode_transition(low,high,contacts,0.01,0.0,1.0,id,"slide",options,tolerance,160)
	return {"low":low,"high":high,"contacts":contacts,"low_solve":low_solve,"high_solve":high_solve,"id":id,"event":event}

static func parallel_same_world_probe(reverse_spawn:bool=false)->Dictionary:
	var shape:=F.box_shape("box",Vector3(0.5,0.5,0.5))
	var bodies:Array=[
		F.new_body("A",shape,Vector3(0,0,0),Quaternion.IDENTITY,1.0,Vector3(0.2,0.2,0.2),Vector3(0,0,1)),
		F.new_body("B",shape,Vector3(0,0,0.95),Quaternion.IDENTITY,1.0,Vector3(0.2,0.2,0.2),Vector3(0,0,-1)),
		F.new_body("D",shape,Vector3(5,0,0),Quaternion.IDENTITY,1.0,Vector3(0.2,0.2,0.2),Vector3(0,0,2)),
		F.new_body("E",shape,Vector3(5,0,0.95),Quaternion.IDENTITY,1.0,Vector3(0.2,0.2,0.2),Vector3(0,0,-2)),
	]
	var contacts:Array=[]
	contacts.append_array(_pair_contacts(bodies,0,1,0.0))
	contacts.append_array(_pair_contacts(bodies,2,3,0.0))
	var options:={"beta":0.0,"tangent_iterations":0,"normal_iterations":256,"coupling_iterations":8,"normal_regularization":1.0e-9,"normal_tolerance":1.0e-9}
	var sequential_bodies:=bodies.duplicate(true)
	var sequential:=F.solve_contacts(sequential_bodies,contacts.duplicate(true),0.01,options)
	var parallel_bodies:=bodies.duplicate(true)
	var parallel:=Parallel.solve_same_world(parallel_bodies,contacts.duplicate(true),0.01,options,reverse_spawn)
	return {
		"initial_bodies":bodies,"contacts":contacts,"options":options,
		"sequential_bodies":sequential_bodies,"sequential":sequential,
		"parallel_bodies":parallel_bodies,"parallel":parallel,
		"max_state_error":_max_velocity_error(sequential_bodies,parallel_bodies),
	}

static func parallel_failure_atomicity_probe()->Dictionary:
	var probe:=parallel_same_world_probe(false)
	var bodies:Array=probe["initial_bodies"].duplicate(true)
	var before:=_velocity_signature(bodies)
	var bad_options:Dictionary=probe["options"].duplicate(true)
	bad_options["normal_iterations"]=0
	var result:=Parallel.solve_same_world(bodies,probe["contacts"].duplicate(true),0.01,bad_options,false)
	return {"result":result,"before":before,"after":_velocity_signature(bodies)}

static func _pair_contacts(bodies:Array,a_idx:int,b_idx:int,mu:float)->Array:
	var collision:=F.collide(bodies[a_idx],bodies[b_idx])
	assert(bool(collision.get("ok",false)) and bool(collision.get("intersect",false)))
	var manifold:=F.build_manifold(bodies[a_idx],bodies[b_idx],collision)
	assert(bool(manifold.get("ok",false)))
	var contacts:Array=[]
	for point_any in manifold["points"]:
		var contact:Dictionary=point_any.duplicate(true)
		contact["a"]=a_idx
		contact["b"]=b_idx
		contact["mu"]=mu
		contact["gap"]=0.0
		contacts.append(contact)
	return contacts

static func _friction_options()->Dictionary:
	return {"beta":0.0,"normal_tolerance":1.0e-9,"normal_iterations":256,"tangent_iterations":64,"coupling_iterations":256,"coupling_tolerance":1.0e-9,"normal_regularization":1.0e-9}

static func _max_velocity_error(a:Array,b:Array)->float:
	var maximum:=0.0
	for i in range(a.size()):
		maximum=maxf(maximum,(Vector3(a[i]["v"])-Vector3(b[i]["v"])).length())
		maximum=maxf(maximum,(Vector3(a[i]["w"])-Vector3(b[i]["w"])).length())
	return maximum

static func _velocity_signature(bodies:Array)->String:
	var out:Array=[]
	for body in bodies:
		var v:Vector3=body["v"]
		var w:Vector3=body["w"]
		out.append([String(body["id"]),v.x,v.y,v.z,w.x,w.y,w.z])
	return JSON.stringify(out,"",false)
