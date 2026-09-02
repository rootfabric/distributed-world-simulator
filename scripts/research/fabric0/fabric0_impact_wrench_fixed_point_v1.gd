class_name Fabric0ImpactWrenchFixedPointV1
extends RefCounted

const F=preload("res://scripts/research/fabric0/fabric0_general_convex_multipoint_mcp_v1.gd")
const Graph=preload("res://scripts/research/fabric0/fabric0_graph_mcp_v1.gd")
const Impact=preload("res://scripts/research/fabric0/fabric0_simultaneous_impact_solver_v1.gd")
const WrenchGraph=preload("res://scripts/research/fabric0/fabric0_generalized_contact_wrench_graph_v1.gd")

const EPS:=1.0e-12

static func solve_event_set(bodies:Array,event_set:Dictionary,restitution:float,wrench_options:Dictionary={},options:Dictionary={})->Dictionary:
	var outer_tolerance:=float(options.get("outer_tolerance",5.0e-10))
	var outer_iterations:=int(options.get("outer_iterations",256))
	var outer_relaxation:=float(options.get("outer_relaxation",1.0))
	if outer_tolerance<=0.0:return {"ok":false,"code":"BAD_OUTER_TOLERANCE"}
	if outer_iterations<=0:return {"ok":false,"code":"BAD_OUTER_ITERATION_BUDGET"}
	if outer_relaxation<=0.0 or outer_relaxation>1.0:return {"ok":false,"code":"BAD_OUTER_RELAXATION"}
	var impact_options:Dictionary=options.get("impact_options",{})
	var seed:=Impact.solve_event_set(bodies,event_set,restitution,impact_options)
	if not bool(seed.get("ok",false)):return {"ok":false,"code":"NORMAL_SEED_FAILED","detail":seed}
	var pre:Array=seed["pre_bodies"].duplicate(true)
	var contacts:Array=seed["contacts"]
	var manifolds:Dictionary=seed["manifolds"]
	var wmat:Array=seed["normal_matrix"]
	var regularization:=float(seed["normal_regularization"])
	var normal_tolerance:=float(impact_options.get("impact_tolerance",1.0e-10))
	var normal_iterations:=int(impact_options.get("impact_iterations",256))
	var q_base:Array=[]
	for contact_any in contacts:
		var contact:Dictionary=contact_any
		var vn:=F.Model.contact_velocity(pre,contact).dot(Vector3(contact["normal"]))
		q_base.append((1.0+restitution)*vn)
	var lambda:Array=[]
	for contact_any in contacts:
		lambda.append(float(seed["blocks"][String(Dictionary(contact_any)["id"])]["lambda"]))
	var completed:=0
	var last_delta:=INF
	var last_residual:=INF
	var initial_reopened_residual:=INF
	var last_wrench:Dictionary={}
	var previous_z:Array=[]
	var converged:=false
	for iteration in range(outer_iterations):
		completed=iteration+1
		var normal_state:=pre.duplicate(true)
		_apply_normal(normal_state,contacts,lambda)
		var pair_impulses:=_pair_impulses(contacts,lambda)
		var wrench:=WrenchGraph.solve_patches(normal_state,manifolds,pair_impulses,wrench_options)
		if not bool(wrench.get("ok",false)):return {"ok":false,"code":"WRENCH_FIXED_POINT_STAGE_FAILED","iteration":completed,"detail":wrench}
		last_wrench=wrench
		last_residual=_normal_residual(pre,wrench["post_bodies"],contacts,lambda,restitution,regularization)
		if iteration==0:initial_reopened_residual=last_residual
		if last_residual<=outer_tolerance:
			converged=true
			break
		var cross:Array=[]
		for contact_any in contacts:
			var contact:Dictionary=contact_any
			var before:=F.Model.contact_velocity(normal_state,contact).dot(Vector3(contact["normal"]))
			var after:=F.Model.contact_velocity(wrench["post_bodies"],contact).dot(Vector3(contact["normal"]))
			cross.append(after-before)
		var q_eff:Array=[]
		for i in range(q_base.size()):q_eff.append(float(q_base[i])+float(cross[i]))
		var normal:=Graph._solve_lcp_active_set(wmat,q_eff,normal_tolerance,normal_iterations)
		if not bool(normal.get("ok",false)):return {"ok":false,"code":"NORMAL_FIXED_POINT_STAGE_FAILED","iteration":completed,"detail":normal}
		var solved_lambda:Array=normal["lambda"].duplicate()
		var lambda_new:Array=[]
		for i in range(lambda.size()):lambda_new.append(float(lambda[i])+outer_relaxation*(float(solved_lambda[i])-float(lambda[i])))
		var z:Array=wrench["generalized_impulse"].duplicate()
		last_delta=_max_delta(lambda,lambda_new,previous_z,z)
		lambda=lambda_new
		previous_z=z
	if not converged:
		return {"ok":false,"code":"IMPACT_WRENCH_FIXED_POINT_DID_NOT_CONVERGE","iterations":completed,"delta":last_delta,"normal_residual":last_residual,"limit":outer_tolerance}

	# Rebuild transactionally from the immutable pre-impact state at the accepted lambda.
	var normal_state:=pre.duplicate(true)
	_apply_normal(normal_state,contacts,lambda)
	var pair_impulses:=_pair_impulses(contacts,lambda)
	var wrench:=WrenchGraph.solve_patches(normal_state,manifolds,pair_impulses,wrench_options)
	if not bool(wrench.get("ok",false)):return {"ok":false,"code":"FINAL_WRENCH_SOLVE_FAILED","detail":wrench}
	var post:Array=wrench["post_bodies"]
	var max_normal_residual:=_normal_residual(pre,post,contacts,lambda,restitution,regularization)
	if max_normal_residual>outer_tolerance:
		return {"ok":false,"code":"FINAL_NORMAL_RESIDUAL_REOPENED","residual":max_normal_residual,"limit":outer_tolerance}
	var max_physical_violation:=0.0
	for i in range(contacts.size()):
		var contact:Dictionary=contacts[i]
		var before:=F.Model.contact_velocity(pre,contact).dot(Vector3(contact["normal"]))
		var after:=F.Model.contact_velocity(post,contact).dot(Vector3(contact["normal"]))
		max_physical_violation=maxf(max_physical_violation,maxf(0.0,-(after+restitution*before)))
	var energy0:=F.total_kinetic_energy(pre)
	var normal_energy:=F.total_kinetic_energy(normal_state)-energy0
	var wrench_energy:=F.total_kinetic_energy(post)-F.total_kinetic_energy(normal_state)
	var energy1:=F.total_kinetic_energy(post)
	var linear0:=F.total_linear_momentum(pre);var linear1:=F.total_linear_momentum(post)
	var angular0:=F.total_angular_momentum_origin(pre);var angular1:=F.total_angular_momentum_origin(post)
	var state:=_state(post)
	return {
		"ok":true,"kind":"COUPLED_IMPACT_WRENCH_FIXED_POINT","event_time":float(event_set["time"]),"restitution":restitution,
		"pre_bodies":pre,"post_bodies":post,"contacts":contacts,"manifolds":manifolds,"contact_rows":contacts.size(),
		"normal_impulses":lambda,"pair_impulses":pair_impulses,"wrench":wrench,
		"outer_iterations":completed,"outer_delta":last_delta,"outer_relaxation":outer_relaxation,"outer_residual_tolerance":outer_tolerance,
		"initial_reopened_normal_residual":initial_reopened_residual,"max_normal_complementarity_violation":max_normal_residual,"max_physical_normal_violation":max_physical_violation,
		"normal_energy_delta":normal_energy,"wrench_energy_delta":wrench_energy,
		"energy_before":energy0,"energy_after":energy1,"energy_delta":energy1-energy0,
		"energy_ledger_error":absf((energy1-energy0)-(normal_energy+wrench_energy)),
		"linear_momentum_error":(linear1-linear0).length(),"angular_momentum_error":(angular1-angular0).length(),
		"state":state,"signature":JSON.stringify({"event_time":event_set["time"],"pair_impulses":pair_impulses,"wrench":wrench["generalized_impulse"],"state":state},"",false),
	}

static func _normal_residual(pre:Array,post:Array,contacts:Array,lambda:Array,restitution:float,regularization:float)->float:
	var maximum:=0.0
	for i in range(contacts.size()):
		var contact:Dictionary=contacts[i]
		var before:=F.Model.contact_velocity(pre,contact).dot(Vector3(contact["normal"]))
		var after:=F.Model.contact_velocity(post,contact).dot(Vector3(contact["normal"]))
		var physical:=after+restitution*before
		var reg:=physical+regularization*float(lambda[i])
		maximum=maxf(maximum,maxf(0.0,-float(lambda[i])))
		maximum=maxf(maximum,maxf(0.0,-reg))
		maximum=maxf(maximum,absf(float(lambda[i])*reg))
	return maximum

static func _apply_normal(bodies:Array,contacts:Array,lambda:Array)->void:
	for i in range(contacts.size()):
		var value:=float(lambda[i])
		if value>EPS:F.Model.apply_impulse(bodies,Dictionary(contacts[i]),Vector3(Dictionary(contacts[i])["normal"])*value)

static func _pair_impulses(contacts:Array,lambda:Array)->Dictionary:
	var out:Dictionary={}
	for i in range(contacts.size()):
		var pair:=String(Dictionary(contacts[i])["pair_id"])
		out[pair]=float(out.get(pair,0.0))+float(lambda[i])
	return out

static func _max_delta(old_lambda:Array,new_lambda:Array,old_z:Array,new_z:Array)->float:
	var maximum:=0.0
	for i in range(new_lambda.size()):maximum=maxf(maximum,absf(float(new_lambda[i])-float(old_lambda[i])))
	if not old_z.is_empty() and old_z.size()==new_z.size():
		for i in range(new_z.size()):maximum=maxf(maximum,absf(float(new_z[i])-float(old_z[i])))
	return maximum

static func _state(bodies:Array)->Array:
	var out:Array=[]
	for body_any in bodies:
		var b:Dictionary=body_any;var p:Vector3=b["p"];var q:Quaternion=b["q"];var v:Vector3=b["v"];var w:Vector3=b["w"]
		out.append([String(b["id"]),p.x,p.y,p.z,q.x,q.y,q.z,q.w,v.x,v.y,v.z,w.x,w.y,w.z])
	return out
