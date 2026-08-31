class_name Fabric0GeneralizedContactWrenchGraphV1
extends RefCounted

const F=preload("res://scripts/research/fabric0/fabric0_general_convex_multipoint_mcp_v1.gd")
const Patch=preload("res://scripts/research/fabric0/fabric0_generalized_contact_wrench_v1.gd")

const EPS:=1.0e-12

static func solve_patches(bodies:Array,manifolds:Dictionary,normal_impulses:Dictionary,options:Dictionary={})->Dictionary:
	var valid:=_validate(bodies,manifolds,normal_impulses,options)
	if not bool(valid.get("ok",false)):return valid
	var work:Array=[]
	for body_any in bodies:work.append(Dictionary(body_any).duplicate(true))
	work.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return String(a["id"])<String(b["id"]))
	var index:Dictionary={}
	for i in range(work.size()):index[String(work[i]["id"])]=i
	var pair_ids:=manifolds.keys();pair_ids.sort()
	var patches:Array=[]
	var mu_t:=float(options.get("mu_tangent",0.1))
	var mu_r:=float(options.get("mu_rolling",0.02))
	var mu_s:=float(options.get("mu_torsion",0.02))
	for pair_any in pair_ids:
		var pair_id:=String(pair_any)
		var split:=pair_id.split("|")
		var ai:=int(index[String(split[0])]);var bi:=int(index[String(split[1])])
		var geometry:=Patch._patch_geometry(work[ai],work[bi],Dictionary(manifolds[pair_id]))
		if not bool(geometry.get("ok",false)):return {"ok":false,"code":"PATCH_GEOMETRY_FAILED","pair_id":pair_id,"detail":geometry}
		var pn:=float(normal_impulses[pair_id])
		var radius:=float(geometry["effective_radius"])
		patches.append({"pair_id":pair_id,"ai":ai,"bi":bi,"geometry":geometry,"normal_impulse":pn,"limits":Vector3(mu_t*pn,mu_r*pn*radius,mu_s*pn*radius)})
	var u0:=_all_velocity(work,patches)
	var k:=_effective_matrix(work,patches)
	var symmetry_error:=_symmetry_error(k)
	var cross_patch_coupling:=_max_cross_patch_coupling(k,patches.size())
	var solved:=_solve_projected(k,u0,patches,options)
	if not bool(solved.get("ok",false)):return solved
	var z:Array=solved["z"]
	var linear0:=F.total_linear_momentum(work)
	var angular0:=F.total_angular_momentum_origin(work)
	var energy0:=F.total_kinetic_energy(work)
	_apply_all(work,patches,z)
	var u1:=_all_velocity(work,patches)
	var linear1:=F.total_linear_momentum(work)
	var angular1:=F.total_angular_momentum_origin(work)
	var energy1:=F.total_kinetic_energy(work)
	var per_pair:Dictionary={}
	for p in range(patches.size()):
		var patch:Dictionary=patches[p]
		var base:=p*5
		var local:=[float(z[base]),float(z[base+1]),float(z[base+2]),float(z[base+3]),float(z[base+4])]
		var g:Dictionary=patch["geometry"]
		var t1:Vector3=g["t1"];var t2:Vector3=g["t2"];var n:Vector3=g["normal"]
		var force:=t1*float(local[0])+t2*float(local[1])
		var rolling:=t1*float(local[2])+t2*float(local[3])
		var torsion:=n*float(local[4])
		var limits:Vector3=patch["limits"]
		per_pair[String(patch["pair_id"])]= {
			"normal_impulse":float(patch["normal_impulse"]),
			"effective_radius":float(g["effective_radius"]),
			"limits":{"tangent":limits.x,"rolling":limits.y,"torsion":limits.z},
			"generalized_impulse":local,
			"force":force,
			"moment":rolling+torsion,
			"modes":{
				"tangent":_mode(Vector2(local[0],local[1]).length(),limits.x,"slide"),
				"rolling":_mode(Vector2(local[2],local[3]).length(),limits.y,"roll"),
				"torsion":_mode(absf(float(local[4])),limits.z,"spin"),
			},
		}
	var predicted:=_dot(u0,z)+0.5*_quad(k,z)
	var state:=_state(work)
	return {
		"ok":true,"kind":"GENERALIZED_CONTACT_WRENCH_GRAPH","post_bodies":work,"patches":patches,"per_pair":per_pair,
		"generalized_velocity_before":u0,"generalized_velocity_after":u1,"effective_matrix":k,"matrix_symmetry_error":symmetry_error,"max_cross_patch_coupling":cross_patch_coupling,
		"generalized_impulse":z,"iterations":int(solved["iterations"]),"projected_residual":float(solved["residual"]),
		"linear_momentum_error":(linear1-linear0).length(),"angular_momentum_error":(angular1-angular0).length(),
		"energy_before":energy0,"energy_after":energy1,"energy_delta":energy1-energy0,"predicted_energy_delta":predicted,
		"energy_ledger_error":absf((energy1-energy0)-predicted),"state":state,
		"signature":JSON.stringify({"pairs":pair_ids,"z":z,"state":state},"",false),
	}

static func _validate(bodies:Array,manifolds:Dictionary,normal_impulses:Dictionary,options:Dictionary)->Dictionary:
	if bodies.size()<2:return {"ok":false,"code":"TOO_FEW_BODIES"}
	if manifolds.is_empty():return {"ok":false,"code":"EMPTY_PATCH_GRAPH"}
	var ids:Dictionary={}
	for body_any in bodies:
		var id:=String(Dictionary(body_any).get("id",""))
		if id.is_empty():return {"ok":false,"code":"EMPTY_BODY_ID"}
		if ids.has(id):return {"ok":false,"code":"DUPLICATE_BODY_ID","body_id":id}
		ids[id]=true
	for pair_any in manifolds.keys():
		var pair_id:=String(pair_any);var split:=pair_id.split("|")
		if split.size()!=2 or not ids.has(String(split[0])) or not ids.has(String(split[1])):return {"ok":false,"code":"BAD_PATCH_PAIR","pair_id":pair_id}
		if not normal_impulses.has(pair_id):return {"ok":false,"code":"MISSING_NORMAL_IMPULSE","pair_id":pair_id}
		if float(normal_impulses[pair_id])<0.0:return {"ok":false,"code":"NEGATIVE_NORMAL_IMPULSE","pair_id":pair_id}
	for key in ["mu_tangent","mu_rolling","mu_torsion"]:
		if float(options.get(key,0.0))<0.0:return {"ok":false,"code":"NEGATIVE_FRICTION_COEFFICIENT","key":key}
	if float(options.get("tolerance",1.0e-11))<=0.0:return {"ok":false,"code":"BAD_TOLERANCE"}
	if int(options.get("iterations",12000))<=0:return {"ok":false,"code":"BAD_ITERATION_BUDGET"}
	return {"ok":true}

static func _all_velocity(bodies:Array,patches:Array)->Array:
	var out:Array=[]
	for patch_any in patches:
		var p:Dictionary=patch_any
		for value in Patch._generalized_velocity(bodies,int(p["ai"]),int(p["bi"]),Dictionary(p["geometry"])):out.append(float(value))
	return out

static func _effective_matrix(bodies:Array,patches:Array)->Array:
	var base:=_all_velocity(bodies,patches);var count:=base.size();var matrix:Array=[]
	for _i in range(count):
		var row:Array=[]
		for _j in range(count):row.append(0.0)
		matrix.append(row)
	for j in range(count):
		var probe:=bodies.duplicate(true);var z:Array=[]
		for _i in range(count):z.append(0.0)
		z[j]=1.0
		_apply_all(probe,patches,z)
		var v:=_all_velocity(probe,patches)
		for i in range(count):matrix[i][j]=float(v[i])-float(base[i])
	return matrix

static func _apply_all(bodies:Array,patches:Array,z:Array)->void:
	for p in range(patches.size()):
		var patch:Dictionary=patches[p];var base:=p*5
		Patch._apply_generalized_impulse(bodies,int(patch["ai"]),int(patch["bi"]),Dictionary(patch["geometry"]),[z[base],z[base+1],z[base+2],z[base+3],z[base+4]])

static func _solve_projected(k:Array,u:Array,patches:Array,options:Dictionary)->Dictionary:
	var tolerance:=float(options.get("tolerance",1.0e-11));var max_iterations:=int(options.get("iterations",12000));var count:=u.size()
	var lipschitz:=0.0
	for i in range(count):
		var sum:=0.0
		for j in range(count):sum+=absf(float(k[i][j]))
		lipschitz=maxf(lipschitz,sum)
	if lipschitz<=EPS:return {"ok":false,"code":"SINGULAR_WRENCH_GRAPH_MATRIX"}
	var step:=float(options.get("step_scale",0.9))/lipschitz
	if step<=0.0:return {"ok":false,"code":"BAD_STEP_SCALE"}
	var z:Array=[];for _i in range(count):z.append(0.0)
	var residual:=INF
	for iteration in range(max_iterations):
		var gradient:=_mat_vec(k,z,u);var trial:Array=[]
		for i in range(count):trial.append(float(z[i])-step*float(gradient[i]))
		var projected:=_project(trial,patches);residual=0.0
		for i in range(count):residual=maxf(residual,absf(float(projected[i])-float(z[i])))
		z=projected
		if residual<=tolerance:return {"ok":true,"z":z,"iterations":iteration+1,"residual":residual,"step":step}
	return {"ok":false,"code":"WRENCH_GRAPH_DID_NOT_CONVERGE","iterations":max_iterations,"residual":residual}

static func _project(z:Array,patches:Array)->Array:
	var out:=z.duplicate()
	for p in range(patches.size()):
		var limits:Vector3=patches[p]["limits"];var base:=p*5
		var tangent:=Vector2(float(out[base]),float(out[base+1]))
		if tangent.length()>limits.x and tangent.length()>EPS:tangent*=limits.x/tangent.length()
		out[base]=tangent.x;out[base+1]=tangent.y
		var rolling:=Vector2(float(out[base+2]),float(out[base+3]))
		if rolling.length()>limits.y and rolling.length()>EPS:rolling*=limits.y/rolling.length()
		out[base+2]=rolling.x;out[base+3]=rolling.y
		out[base+4]=clampf(float(out[base+4]),-limits.z,limits.z)
	return out

static func _mat_vec(k:Array,z:Array,u:Array)->Array:
	var out:Array=[]
	for i in range(u.size()):
		var value:=float(u[i]);for j in range(z.size()):value+=float(k[i][j])*float(z[j])
		out.append(value)
	return out

static func _dot(a:Array,b:Array)->float:
	var value:=0.0
	for i in range(a.size()):value+=float(a[i])*float(b[i])
	return value

static func _quad(k:Array,z:Array)->float:
	var zero:Array=[];for _i in range(z.size()):zero.append(0.0)
	return _dot(z,_mat_vec(k,z,zero))

static func _symmetry_error(k:Array)->float:
	var maximum:=0.0
	for i in range(k.size()):
		for j in range(k.size()):maximum=maxf(maximum,absf(float(k[i][j])-float(k[j][i])))
	return maximum

static func _mode(value:float,limit:float,saturated:String)->String:
	if limit<=EPS:return "unconstrained"
	return saturated if value>=limit-1.0e-8*maxf(1.0,limit) else "stick"

static func _max_cross_patch_coupling(k:Array,patch_count:int)->float:
	var maximum:=0.0
	for a in range(patch_count):
		for b in range(patch_count):
			if a==b:continue
			for i in range(5):
				for j in range(5):maximum=maxf(maximum,absf(float(k[a*5+i][b*5+j])))
	return maximum

static func _state(bodies:Array)->Array:
	var out:Array=[]
	for body_any in bodies:
		var b:Dictionary=body_any;var p:Vector3=b["p"];var q:Quaternion=b["q"];var v:Vector3=b["v"];var w:Vector3=b["w"]
		out.append([String(b["id"]),p.x,p.y,p.z,q.x,q.y,q.z,q.w,v.x,v.y,v.z,w.x,w.y,w.z])
	return out
