class_name Fabric0PersistentWrenchGraphV1
extends RefCounted

const State = preload("res://scripts/research/fabric0/fabric0_persistent_wrench_contact_state_v1.gd")
const EPS := 1.0e-12

static func solve(body:Dictionary,contacts:Array,previous_states:Dictionary={},options:Dictionary={})->Dictionary:
	var checked:=_validate(body,contacts,options)
	if not bool(checked.get("ok",false)):return checked
	var work:=body.duplicate(true)
	var ordered:Array=[]
	for c_any in contacts:ordered.append(Dictionary(c_any).duplicate(true))
	ordered.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return String(a["contact_id"])<String(b["contact_id"]))
	var nvars:=ordered.size()*6
	var u:=_generalized_velocity(work,ordered)
	var k:=_effective_matrix(work,ordered,u)
	var symmetry_error:=_symmetry_error(k)
	var cross_contact_coupling:=_cross_contact_coupling(k,ordered.size())
	var z:=_initial_guess(ordered,previous_states)
	var solved:=_projected_solve(k,u,z,ordered,options)
	if not bool(solved.get("ok",false)):return solved
	z=Array(solved["z"])
	_apply_all(work,ordered,z)
	var u_after:=_generalized_velocity(work,ordered)
	var per_contact:Dictionary={}
	var total_force:=Vector3.ZERO
	var total_moment:=Vector3.ZERO
	var time:=float(options.get("time",0.0))
	var state_options:Dictionary=options.get("state_options",{})
	for ci in range(ordered.size()):
		var c:Dictionary=ordered[ci]
		var base:=ci*6
		var pn:=float(z[base])
		var tang:=Vector2(float(z[base+1]),float(z[base+2]))
		var roll:=Vector2(float(z[base+3]),float(z[base+4]))
		var tors:=float(z[base+5])
		var n:Vector3=c["normal"];var t1:Vector3=c["t1"];var t2:Vector3=c["t2"];var r:Vector3=c["r"]
		var force:=n*pn+t1*tang.x+t2*tang.y
		var explicit_moment:=t1*roll.x+t2*roll.y+n*tors
		total_force+=force
		total_moment+=r.cross(force)+explicit_moment
		var reff:=float(c["effective_radius"])
		var limits:={"tangent":float(c["mu_tangent"])*pn,"rolling":float(c["mu_rolling"])*pn*reff,"torsion":float(c["mu_torsion"])*pn*reff}
		var obs:={"body_a":String(c.get("anchor_id","WORLD")),"body_b":String(body["id"]),"members":Array(c["member_ids"]).duplicate()}
		var solved_state:={"normal_support":pn,"generalized_impulse":[tang.x,tang.y,roll.x,roll.y,tors],"generalized_velocity_after":[u_after[base+1],u_after[base+2],u_after[base+3],u_after[base+4],u_after[base+5]],"limits":limits}
		var previous=previous_states.get(String(c["contact_id"]),{})
		var persistent:Dictionary
		var support_tolerance:=float(state_options.get("normal_support_tolerance",EPS))
		if pn<=support_tolerance:
			var seed:Dictionary
			if previous is Dictionary and bool(Dictionary(previous).get("ok",false)):
				seed=Dictionary(previous)
			else:
				seed=State.begin(obs,{"normal_support":0.0,"generalized_impulse":[0.0,0.0,0.0,0.0,0.0],"generalized_velocity_after":[0.0,0.0,0.0,0.0,0.0],"limits":{"tangent":0.0,"rolling":0.0,"torsion":0.0}},time,state_options)
			persistent=State.separate(seed,time)
			persistent["limits"]=limits.duplicate(true)
		elif previous is Dictionary and bool(Dictionary(previous).get("ok",false)):
			persistent=State.advance(Dictionary(previous),obs,solved_state,time,state_options)
		else:
			persistent=State.begin(obs,solved_state,time,state_options)
		if not bool(persistent.get("ok",false)):
			return {"ok":false,"code":"PERSISTENT_STATE_REJECTED","contact_id":c["contact_id"],"detail":persistent}
		per_contact[String(c["contact_id"])]= {
			"normal_impulse":pn,"tangent_impulse":tang,"rolling_impulse":roll,"torsion_impulse":tors,
			"force_impulse":force,"explicit_moment_impulse":explicit_moment,"limits":limits,
			"generalized_velocity_after":[u_after[base],u_after[base+1],u_after[base+2],u_after[base+3],u_after[base+4],u_after[base+5]],
			"persistent_state":persistent,
		}
	var normal_audit:=_normal_complementarity(z,u_after,ordered.size())
	var kinetic_before:=_kinetic(body)
	var kinetic_after:=_kinetic(work)
	var predicted:=_dot(u,z)+0.5*_quad(k,z)
	return {
		"ok":true,"kind":"MULTICONTACT_PERSISTENT_WRENCH_GRAPH","post_body":work,"contacts":ordered,"per_contact":per_contact,
		"generalized_velocity_before":u,"generalized_velocity_after":u_after,"effective_matrix":k,"generalized_impulse":z,
		"matrix_symmetry_error":symmetry_error,"max_cross_contact_coupling":cross_contact_coupling,
		"projected_residual":float(solved["residual"]),"iterations":int(solved["iterations"]),"step":float(solved["step"]),
		"normal_complementarity_error":normal_audit["error"],"max_active_normal_velocity":normal_audit["max_active_normal_velocity"],"min_open_normal_velocity":normal_audit["min_open_normal_velocity"],
		"reaction_force_impulse":total_force,"reaction_moment_impulse":total_moment,
		"kinetic_before":kinetic_before,"kinetic_after":kinetic_after,"kinetic_delta":kinetic_after-kinetic_before,
		"predicted_kinetic_delta":predicted,"energy_ledger_error":absf((kinetic_after-kinetic_before)-predicted),
		"signature":_signature(work,ordered,z,per_contact),
	}

static func _validate(body:Dictionary,contacts:Array,options:Dictionary)->Dictionary:
	if String(body.get("id","")).is_empty():return {"ok":false,"code":"EMPTY_BODY_ID"}
	if float(body.get("mass",0.0))<=0.0:return {"ok":false,"code":"BAD_MASS"}
	if not body.has("v") or not body.has("w") or not body.has("inertia"):return {"ok":false,"code":"INCOMPLETE_BODY"}
	var inertia:Vector3=body["inertia"]
	if inertia.x<=0.0 or inertia.y<=0.0 or inertia.z<=0.0:return {"ok":false,"code":"BAD_INERTIA"}
	if contacts.size()<2:return {"ok":false,"code":"TOO_FEW_CONTACTS"}
	var ids:Dictionary={}
	for c_any in contacts:
		if not (c_any is Dictionary):return {"ok":false,"code":"BAD_CONTACT"}
		var c:Dictionary=c_any;var id:=String(c.get("contact_id",""))
		if id.is_empty():return {"ok":false,"code":"EMPTY_CONTACT_ID"}
		if ids.has(id):return {"ok":false,"code":"DUPLICATE_CONTACT_ID","contact_id":id}
		ids[id]=true
		for key in ["r","normal","t1","t2","effective_radius","mu_tangent","mu_rolling","mu_torsion","member_ids"]:
			if not c.has(key):return {"ok":false,"code":"INCOMPLETE_CONTACT","contact_id":id,"missing":key}
		if float(c["effective_radius"])<0.0:return {"ok":false,"code":"BAD_EFFECTIVE_RADIUS","contact_id":id}
		for key in ["mu_tangent","mu_rolling","mu_torsion"]:
			if float(c[key])<0.0:return {"ok":false,"code":"NEGATIVE_WRENCH_COEFFICIENT","contact_id":id,"key":key}
		var n:Vector3=c["normal"];var t1:Vector3=c["t1"];var t2:Vector3=c["t2"]
		if absf(n.length()-1.0)>1.0e-9 or absf(t1.length()-1.0)>1.0e-9 or absf(t2.length()-1.0)>1.0e-9:return {"ok":false,"code":"NONUNIT_CONTACT_FRAME","contact_id":id}
		if absf(n.dot(t1))>1.0e-9 or absf(n.dot(t2))>1.0e-9 or absf(t1.dot(t2))>1.0e-9:return {"ok":false,"code":"NONORTHOGONAL_CONTACT_FRAME","contact_id":id}
	if float(options.get("tolerance",1.0e-11))<=0.0:return {"ok":false,"code":"BAD_TOLERANCE"}
	if int(options.get("iterations",30000))<=0:return {"ok":false,"code":"BAD_ITERATION_BUDGET"}
	return {"ok":true}

static func _generalized_velocity(body:Dictionary,contacts:Array)->Array:
	var out:Array=[];var v:Vector3=body["v"];var w:Vector3=body["w"]
	for c_any in contacts:
		var c:Dictionary=c_any;var r:Vector3=c["r"];var vc:=v+w.cross(r)
		var n:Vector3=c["normal"];var t1:Vector3=c["t1"];var t2:Vector3=c["t2"]
		out.append(vc.dot(n));out.append(vc.dot(t1));out.append(vc.dot(t2));out.append(w.dot(t1));out.append(w.dot(t2));out.append(w.dot(n))
	return out

static func _effective_matrix(body:Dictionary,contacts:Array,base:Array)->Array:
	var count:=contacts.size()*6;var matrix:Array=[]
	for _i in range(count):
		var row:Array=[];for _j in range(count):row.append(0.0)
		matrix.append(row)
	for j in range(count):
		var probe:=body.duplicate(true)
		var z:Array=[]
		for _i in range(count):
			z.append(0.0)
		z[j]=1.0
		_apply_all(probe,contacts,z)
		var after:=_generalized_velocity(probe,contacts)
		for i in range(count):matrix[i][j]=float(after[i])-float(base[i])
	return matrix

static func _apply_all(body:Dictionary,contacts:Array,z:Array)->void:
	for ci in range(contacts.size()):
		var c:Dictionary=contacts[ci];var b:=ci*6
		var force:=Vector3(c["normal"])*float(z[b])+Vector3(c["t1"])*float(z[b+1])+Vector3(c["t2"])*float(z[b+2])
		var moment:=Vector3(c["r"]).cross(force)+Vector3(c["t1"])*float(z[b+3])+Vector3(c["t2"])*float(z[b+4])+Vector3(c["normal"])*float(z[b+5])
		body["v"]=Vector3(body["v"])+force/float(body["mass"])
		var inertia:Vector3=body["inertia"]
		body["w"]=Vector3(body["w"])+Vector3(moment.x/inertia.x,moment.y/inertia.y,moment.z/inertia.z)

static func _initial_guess(contacts:Array,previous_states:Dictionary)->Array:
	var z:Array=[]
	for c_any in contacts:
		var c:Dictionary=c_any;var previous=previous_states.get(String(c["contact_id"]),{})
		if previous is Dictionary and bool(Dictionary(previous).get("ok",false)):
			var p:Dictionary=previous;z.append(maxf(0.0,float(p.get("normal_support",0.0))))
			var warm:Array=p.get("warm_start_proposal",[0.0,0.0,0.0,0.0,0.0])
			for i in range(5):z.append(float(warm[i]) if i<warm.size() else 0.0)
		else:
			for _i in range(6):z.append(0.0)
	return _project(z,contacts)

static func _projected_solve(k:Array,u:Array,initial:Array,contacts:Array,options:Dictionary)->Dictionary:
	var tolerance:=float(options.get("tolerance",1.0e-11));var max_iterations:=int(options.get("iterations",30000))
	var lipschitz:=0.0
	for i in range(k.size()):
		var sum:=0.0;for j in range(k.size()):sum+=absf(float(k[i][j]))
		lipschitz=maxf(lipschitz,sum)
	if lipschitz<=EPS:return {"ok":false,"code":"SINGULAR_GRAPH_MATRIX"}
	var step:=float(options.get("step_scale",0.9))/lipschitz
	if step<=0.0:return {"ok":false,"code":"BAD_STEP_SCALE"}
	var z:=initial.duplicate();var residual:=INF
	for iteration in range(max_iterations):
		var g:=_mat_vec(k,z,u);var trial:Array=[]
		for i in range(z.size()):trial.append(float(z[i])-step*float(g[i]))
		var projected:=_project(trial,contacts);residual=0.0
		for i in range(z.size()):residual=maxf(residual,absf(float(projected[i])-float(z[i])))
		z=projected
		if residual<=tolerance:return {"ok":true,"z":z,"iterations":iteration+1,"residual":residual,"step":step}
	return {"ok":false,"code":"PERSISTENT_WRENCH_GRAPH_DID_NOT_CONVERGE","iterations":max_iterations,"residual":residual}

static func _project(z:Array,contacts:Array)->Array:
	var out:=z.duplicate()
	for ci in range(contacts.size()):
		var c:Dictionary=contacts[ci];var b:=ci*6
		var pn:=maxf(0.0,float(out[b]));out[b]=pn
		var tang:=Vector2(float(out[b+1]),float(out[b+2]));var tl:=float(c["mu_tangent"])*pn
		if tang.length()>tl and tang.length()>EPS:tang*=tl/tang.length()
		out[b+1]=tang.x;out[b+2]=tang.y
		var roll:=Vector2(float(out[b+3]),float(out[b+4]));var rl:=float(c["mu_rolling"])*pn*float(c["effective_radius"])
		if roll.length()>rl and roll.length()>EPS:roll*=rl/roll.length()
		out[b+3]=roll.x;out[b+4]=roll.y
		var sl:=float(c["mu_torsion"])*pn*float(c["effective_radius"]);out[b+5]=clampf(float(out[b+5]),-sl,sl)
	return out

static func _mat_vec(k:Array,z:Array,u:Array)->Array:
	var out:Array=[]
	for i in range(u.size()):
		var value:=float(u[i]);for j in range(z.size()):value+=float(k[i][j])*float(z[j])
		out.append(value)
	return out

static func _dot(a:Array,b:Array)->float:
	var out:=0.0
	for i in range(a.size()):
		out+=float(a[i])*float(b[i])
	return out

static func _quad(k:Array,z:Array)->float:
	var zero:Array=[];for _i in range(z.size()):zero.append(0.0)
	return _dot(z,_mat_vec(k,z,zero))

static func _kinetic(body:Dictionary)->float:
	var v:Vector3=body["v"];var w:Vector3=body["w"];var i:Vector3=body["inertia"]
	return 0.5*float(body["mass"])*v.length_squared()+0.5*(i.x*w.x*w.x+i.y*w.y*w.y+i.z*w.z*w.z)

static func _symmetry_error(k:Array)->float:
	var maximum:=0.0
	for i in range(k.size()):
		for j in range(k.size()):maximum=maxf(maximum,absf(float(k[i][j])-float(k[j][i])))
	return maximum

static func _cross_contact_coupling(k:Array,count:int)->float:
	var maximum:=0.0
	for a in range(count):
		for b in range(count):
			if a==b:continue
			for i in range(6):
				for j in range(6):maximum=maxf(maximum,absf(float(k[a*6+i][b*6+j])))
	return maximum


static func _normal_complementarity(z:Array,u_after:Array,count:int)->Dictionary:
	var error:=0.0
	var max_active:=0.0
	var min_open:=INF
	for ci in range(count):
		var pn:=float(z[ci*6]);var vn:=float(u_after[ci*6])
		error=maxf(error,maxf(0.0,-pn))
		error=maxf(error,maxf(0.0,-vn))
		error=maxf(error,absf(pn*vn))
		if pn>1.0e-10:max_active=maxf(max_active,absf(vn))
		else:min_open=minf(min_open,vn)
	if not is_finite(min_open):min_open=0.0
	return {"error":error,"max_active_normal_velocity":max_active,"min_open_normal_velocity":min_open}

static func _max_abs(values:Array)->float:
	var maximum:=0.0
	for value_any in values:
		maximum=maxf(maximum,absf(float(value_any)))
	return maximum

static func _signature(body:Dictionary,contacts:Array,z:Array,per_contact:Dictionary)->String:
	var ids:Array=[];for c_any in contacts:ids.append(String(Dictionary(c_any)["contact_id"]))
	var modes:Dictionary={};for id in ids:modes[id]=Dictionary(Dictionary(per_contact[id])["persistent_state"])["modes"]
	var v:Vector3=body["v"];var w:Vector3=body["w"]
	return JSON.stringify({"ids":ids,"z":z,"v":[v.x,v.y,v.z],"w":[w.x,w.y,w.z],"modes":modes},"",false)
