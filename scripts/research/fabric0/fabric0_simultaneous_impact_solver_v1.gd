class_name Fabric0SimultaneousImpactSolverV1
extends RefCounted

const F = preload("res://scripts/research/fabric0/fabric0_general_convex_multipoint_mcp_v1.gd")
const Events = preload("res://scripts/research/fabric0/fabric0_general_convex_event_driver_v1.gd")
const Graph = preload("res://scripts/research/fabric0/fabric0_graph_mcp_v1.gd")

const EPS := 1.0e-12

static func solve_event_set(
	bodies:Array,
	event_set:Dictionary,
	restitution:float=0.0,
	options:Dictionary={}
) -> Dictionary:
	var valid:=_validate(bodies,event_set,restitution,options)
	if not bool(valid.get("ok",false)):
		return valid

	var canonical_bodies:Array=[]
	for body_any in bodies:
		canonical_bodies.append(Dictionary(body_any).duplicate(true))
	canonical_bodies.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
		return String(a["id"])<String(b["id"])
	)
	var event_time:=float(event_set["time"])
	var pre_bodies:Array=[]
	for body_any in canonical_bodies:
		pre_bodies.append(Events.body_at(Dictionary(body_any),event_time))
	var post_bodies:Array=pre_bodies.duplicate(true)
	var index_by_id:Dictionary={}
	for i in range(pre_bodies.size()):
		index_by_id[String(pre_bodies[i]["id"])]=i

	var materialized:=_materialize_event_contacts(pre_bodies,index_by_id,event_set,options)
	if not bool(materialized.get("ok",false)):
		return materialized
	var contacts:Array=materialized["contacts"]
	if contacts.is_empty():
		return {"ok":false,"code":"EMPTY_IMPACT_CONTACT_GRAPH"}
	contacts.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
		return String(a["id"])<String(b["id"])
	)

	var regularization:=float(options.get("normal_regularization",1.0e-9))
	var tolerance:=float(options.get("impact_tolerance",1.0e-10))
	var max_iterations:=int(options.get("impact_iterations",256))
	var wmat:=Graph._normal_matrix(pre_bodies,contacts,regularization)
	var q:Array=[]
	var vn_before:Array=[]
	for contact_any in contacts:
		var contact:Dictionary=contact_any
		var vn:=F.Model.contact_velocity(pre_bodies,contact).dot(Vector3(contact["normal"]))
		vn_before.append(vn)
		q.append((1.0+restitution)*vn)
	var normal:=Graph._solve_lcp_active_set(wmat,q,tolerance,max_iterations)
	if not bool(normal.get("ok",false)):
		return {"ok":false,"code":"SIMULTANEOUS_IMPACT_LCP_FAILED","detail":normal}
	var impulses:Array=normal["lambda"].duplicate()
	for i in range(contacts.size()):
		var impulse:=float(impulses[i])
		if impulse>EPS:
			F.Model.apply_impulse(post_bodies,contacts[i],Vector3(contacts[i]["normal"])*impulse)

	var blocks:Dictionary={}
	var pair_impulses:Dictionary={}
	var max_complementarity:=0.0
	var max_restitution_error:=0.0
	var max_physical_w_violation:=0.0
	for i in range(contacts.size()):
		var contact:Dictionary=contacts[i]
		var lambda:=float(impulses[i])
		var before:=float(vn_before[i])
		var after:=F.Model.contact_velocity(post_bodies,contact).dot(Vector3(contact["normal"]))
		var physical_w:=after+restitution*before
		var regularized_w:=physical_w+regularization*lambda
		max_complementarity=maxf(max_complementarity,maxf(0.0,-lambda))
		max_complementarity=maxf(max_complementarity,maxf(0.0,-regularized_w))
		max_complementarity=maxf(max_complementarity,absf(lambda*regularized_w))
		max_physical_w_violation=maxf(max_physical_w_violation,maxf(0.0,-physical_w))
		if lambda>tolerance:
			max_restitution_error=maxf(max_restitution_error,absf(physical_w))
		var pair_id:=String(contact["pair_id"])
		pair_impulses[pair_id]=float(pair_impulses.get(pair_id,0.0))+lambda
		blocks[String(contact["id"])]= {
			"pair_id":pair_id,
			"lambda":lambda,
			"vn_before":before,
			"vn_after":after,
			"physical_w":physical_w,
			"regularized_w":regularized_w,
		}

	var linear_before:=F.total_linear_momentum(pre_bodies)
	var linear_after:=F.total_linear_momentum(post_bodies)
	var angular_before:=F.total_angular_momentum_origin(pre_bodies)
	var angular_after:=F.total_angular_momentum_origin(post_bodies)
	var energy_before:=F.total_kinetic_energy(pre_bodies)
	var energy_after:=F.total_kinetic_energy(post_bodies)
	var state:=_canonical_state(post_bodies)
	return {
		"ok":true,
		"kind":"COUPLED_SIMULTANEOUS_IMPACT_SOLVE",
		"event_time":event_time,
		"restitution":restitution,
		"pre_bodies":pre_bodies,
		"post_bodies":post_bodies,
		"contacts":contacts,
		"contact_rows":contacts.size(),
		"pair_count":event_set["pair_ids"].size(),
		"manifolds":materialized["manifolds"],
		"boundary_fallbacks":int(materialized["boundary_fallbacks"]),
		"normal_matrix":wmat,
		"normal_regularization":regularization,
		"normal_iterations":int(normal["iterations"]),
		"normal_residual":float(normal["residual"]),
		"pair_impulses":pair_impulses,
		"blocks":blocks,
		"max_complementarity_violation":max_complementarity,
		"max_physical_w_violation":max_physical_w_violation,
		"max_restitution_error":max_restitution_error,
		"linear_momentum_error":(linear_after-linear_before).length(),
		"angular_momentum_error":(angular_after-angular_before).length(),
		"energy_before":energy_before,
		"energy_after":energy_after,
		"energy_delta":energy_after-energy_before,
		"state":state,
		"signature":JSON.stringify({"event_time":event_time,"restitution":restitution,"pair_impulses":pair_impulses,"state":state},"",false),
	}

static func _validate(bodies:Array,event_set:Dictionary,restitution:float,options:Dictionary)->Dictionary:
	if bodies.size()<3:
		return {"ok":false,"code":"TOO_FEW_BODIES"}
	if String(event_set.get("kind",""))!="SIMULTANEOUS_IMPACT_EVENT_SET":
		return {"ok":false,"code":"BAD_EVENT_SET_KIND"}
	var pair_ids:Array=event_set.get("pair_ids",[])
	var members:Array=event_set.get("members",[])
	if pair_ids.size()<2 or members.size()<2:
		return {"ok":false,"code":"EVENT_SET_NOT_MULTIPLE"}
	if pair_ids.size()!=members.size():
		return {"ok":false,"code":"EVENT_SET_MEMBER_COUNT_MISMATCH"}
	if restitution<0.0 or restitution>1.0:
		return {"ok":false,"code":"BAD_RESTITUTION"}
	var max_uncertainty:=float(options.get("max_event_uncertainty",1.0e-6))
	if max_uncertainty<=0.0:
		return {"ok":false,"code":"BAD_EVENT_UNCERTAINTY_LIMIT"}
	if float(event_set.get("uncertainty_span",INF))>max_uncertainty:
		return {"ok":false,"code":"EVENT_SET_NOT_REFINED_ENOUGH","uncertainty_span":event_set.get("uncertainty_span",INF),"limit":max_uncertainty}
	var regularization:=float(options.get("normal_regularization",1.0e-9))
	if regularization<0.0:
		return {"ok":false,"code":"NEGATIVE_NORMAL_REGULARIZATION"}
	if float(options.get("impact_tolerance",1.0e-10))<=0.0:
		return {"ok":false,"code":"BAD_IMPACT_TOLERANCE"}
	if int(options.get("impact_iterations",256))<=0:
		return {"ok":false,"code":"BAD_IMPACT_ITERATION_BUDGET"}
	if float(options.get("max_boundary_gap",5.0e-6))<=0.0:
		return {"ok":false,"code":"BAD_BOUNDARY_GAP_LIMIT"}
	var ids:Dictionary={}
	for body_any in bodies:
		var body:Dictionary=body_any
		var id:=String(body.get("id",""))
		if id.is_empty():
			return {"ok":false,"code":"EMPTY_BODY_ID"}
		if ids.has(id):
			return {"ok":false,"code":"DUPLICATE_BODY_ID","body_id":id}
		ids[id]=true
	var expected_ids:Array=[]
	for member_any in members:
		var member:Dictionary=member_any
		var id:=String(member.get("id",""))
		if id.is_empty() or expected_ids.has(id):
			return {"ok":false,"code":"BAD_EVENT_MEMBER_ID","id":id}
		expected_ids.append(id)
		var split:=id.split("|")
		if split.size()!=2 or not ids.has(String(split[0])) or not ids.has(String(split[1])):
			return {"ok":false,"code":"EVENT_MEMBER_BODY_NOT_FOUND","id":id}
	expected_ids.sort()
	var canonical_pair_ids:=pair_ids.duplicate()
	canonical_pair_ids.sort()
	if expected_ids!=canonical_pair_ids:
		return {"ok":false,"code":"EVENT_SET_PAIR_ID_MISMATCH"}
	return {"ok":true}

static func _materialize_event_contacts(pre_bodies:Array,index_by_id:Dictionary,event_set:Dictionary,options:Dictionary)->Dictionary:
	var contacts:Array=[]
	var manifolds:Dictionary={}
	var fallbacks:=0
	var max_boundary_gap:=float(options.get("max_boundary_gap",5.0e-6))
	var members:Array=event_set["members"].duplicate(true)
	members.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
		return String(a["id"])<String(b["id"])
	)
	for member_any in members:
		var member:Dictionary=member_any
		var pair:=String(member["id"]).split("|")
		var a_id:=String(pair[0])
		var b_id:=String(pair[1])
		var a_index:=int(index_by_id[a_id])
		var b_index:=int(index_by_id[b_id])
		var a:Dictionary=pre_bodies[a_index]
		var b:Dictionary=pre_bodies[b_index]
		var normal:=Vector3(member["normal"]).normalized()
		if normal.length_squared()<=EPS:
			return {"ok":false,"code":"EVENT_MEMBER_ZERO_NORMAL","id":member["id"]}
		if normal.dot(Vector3(b["p"])-Vector3(a["p"]))<0.0:
			normal=-normal
		var pa:Vector3=F.support(a,normal)["point"]
		var pb:Vector3=F.support(b,-normal)["point"]
		var gap:=(pb-pa).dot(normal)
		if absf(gap)>max_boundary_gap:
			return {"ok":false,"code":"EVENT_BOUNDARY_GAP_TOO_LARGE","id":member["id"],"gap":gap,"limit":max_boundary_gap}
		var collision:=F.collide(a,b)
		var boundary_fallback:=not (bool(collision.get("ok",false)) and bool(collision.get("intersect",false)))
		if boundary_fallback:
			collision={
				"ok":true,"intersect":true,"normal":normal,"depth":maxf(0.0,-gap),
				"point_a":pa,"point_b":pb,"gjk_iterations":int(collision.get("gjk_iterations",0)),"epa_iterations":0,
			}
			fallbacks+=1
		var manifold:=F.build_manifold(a,b,collision,{},4)
		if not bool(manifold.get("ok",false)):
			return {"ok":false,"code":"IMPACT_MANIFOLD_BUILD_FAILED","id":member["id"],"detail":manifold}
		manifolds[String(member["id"])]=manifold
		for point_any in manifold["points"]:
			var contact:Dictionary=Dictionary(point_any).duplicate(true)
			contact["a"]=a_index
			contact["b"]=b_index
			contact["pair_id"]=String(member["id"])
			contact["normal"]=normal
			contact["gap"]=0.0
			contact["mu"]=0.0
			contacts.append(contact)
	return {"ok":true,"contacts":contacts,"manifolds":manifolds,"boundary_fallbacks":fallbacks}

static func _canonical_state(bodies:Array)->Array:
	var work:=bodies.duplicate(true)
	work.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
		return String(a["id"])<String(b["id"])
	)
	var state:Array=[]
	for body_any in work:
		var body:Dictionary=body_any
		var v:Vector3=body["v"]
		var w:Vector3=body["w"]
		state.append([String(body["id"]),v.x,v.y,v.z,w.x,w.y,w.z])
	return state
