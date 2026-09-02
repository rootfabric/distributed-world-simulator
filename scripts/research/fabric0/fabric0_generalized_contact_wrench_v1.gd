class_name Fabric0GeneralizedContactWrenchV1
extends RefCounted

const F = preload("res://scripts/research/fabric0/fabric0_general_convex_multipoint_mcp_v1.gd")

const EPS := 1.0e-12

static func solve_patch(
	bodies:Array,
	body_a_id:String,
	body_b_id:String,
	manifold:Dictionary,
	normal_impulse:float,
	options:Dictionary={}
) -> Dictionary:
	var valid:=_validate(bodies,body_a_id,body_b_id,manifold,normal_impulse,options)
	if not bool(valid.get("ok",false)):
		return valid
	var work:Array=[]
	for body_any in bodies:
		work.append(Dictionary(body_any).duplicate(true))
	work.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return String(a["id"])<String(b["id"]))
	var index:Dictionary={}
	for i in range(work.size()):index[String(work[i]["id"])]=i
	var a_id:=body_a_id
	var b_id:=body_b_id
	if a_id>b_id:
		var tmp:=a_id;a_id=b_id;b_id=tmp
	var ai:=int(index[a_id]);var bi:=int(index[b_id])
	var a:Dictionary=work[ai];var b:Dictionary=work[bi]
	var patch:=_patch_geometry(a,b,manifold)
	if not bool(patch.get("ok",false)):return patch
	var n:Vector3=patch["normal"]
	var t1:Vector3=patch["t1"]
	var t2:Vector3=patch["t2"]
	var radius:=float(patch["effective_radius"])
	var mu_t:=float(options.get("mu_tangent",0.5))
	var mu_r:=float(options.get("mu_rolling",0.02))
	var mu_s:=float(options.get("mu_torsion",0.02))
	var limits:=Vector3(mu_t*normal_impulse,mu_r*normal_impulse*radius,mu_s*normal_impulse*radius)
	var u0:=_generalized_velocity(work,ai,bi,patch)
	var k:=_effective_matrix(work,ai,bi,patch)
	var symmetry_error:=_symmetry_error(k)
	var solved:=_projected_maximum_dissipation(k,u0,limits,options)
	if not bool(solved.get("ok",false)):return solved
	var z:Array=solved["z"]
	var before_linear:=F.total_linear_momentum(work)
	var before_angular:=F.total_angular_momentum_origin(work)
	var before_energy:=F.total_kinetic_energy(work)
	_apply_generalized_impulse(work,ai,bi,patch,z)
	var u1:=_generalized_velocity(work,ai,bi,patch)
	var after_linear:=F.total_linear_momentum(work)
	var after_angular:=F.total_angular_momentum_origin(work)
	var after_energy:=F.total_kinetic_energy(work)
	var tangent:=t1*float(z[0])+t2*float(z[1])
	var rolling:=t1*float(z[2])+t2*float(z[3])
	var torsion:=n*float(z[4])
	var friction_moment:=rolling+torsion
	var full_force:=n*normal_impulse+tangent
	var predicted_delta:=_dot5(u0,z)+0.5*_quad5(k,z)
	var tangent_mag:=Vector2(float(z[0]),float(z[1])).length()
	var rolling_mag:=Vector2(float(z[2]),float(z[3])).length()
	var torsion_mag:=absf(float(z[4]))
	var modes:={
		"tangent":_disk_mode(tangent_mag,limits.x,"slide"),
		"rolling":_disk_mode(rolling_mag,limits.y,"roll"),
		"torsion":_disk_mode(torsion_mag,limits.z,"spin"),
	}
	var state:=_canonical_state(work)
	return {
		"ok":true,
		"kind":"GENERALIZED_CONTACT_WRENCH",
		"pair_id":a_id+"|"+b_id,
		"post_bodies":work,
		"patch":patch,
		"normal_impulse":normal_impulse,
		"limits":{"tangent":limits.x,"rolling":limits.y,"torsion":limits.z},
		"generalized_velocity_before":u0,
		"generalized_velocity_after":u1,
		"effective_matrix":k,
		"matrix_symmetry_error":symmetry_error,
		"generalized_impulse":z,
		"tangent_impulse":tangent,
		"rolling_moment_impulse":rolling,
		"torsional_moment_impulse":torsion,
		"friction_moment_impulse":friction_moment,
		"normal_support_resolved_externally":true,
		"applied_wrench_impulse":{"force":tangent,"moment":friction_moment},
		"admissible_resultant_wrench_impulse":{"force":full_force,"moment":friction_moment},
		"modes":modes,
		"iterations":int(solved["iterations"]),
		"projected_residual":float(solved["residual"]),
		"linear_momentum_error":(after_linear-before_linear).length(),
		"angular_momentum_error":(after_angular-before_angular).length(),
		"energy_before":before_energy,
		"energy_after":after_energy,
		"energy_delta":after_energy-before_energy,
		"predicted_energy_delta":predicted_delta,
		"energy_ledger_error":absf((after_energy-before_energy)-predicted_delta),
		"state":state,
		"signature":JSON.stringify({"pair":a_id+"|"+b_id,"normal_impulse":normal_impulse,"limits":limits,"z":z,"state":state},"",false),
	}

static func _validate(bodies:Array,a_id:String,b_id:String,manifold:Dictionary,normal_impulse:float,options:Dictionary)->Dictionary:
	if bodies.size()<2:return {"ok":false,"code":"TOO_FEW_BODIES"}
	if a_id.is_empty() or b_id.is_empty() or a_id==b_id:return {"ok":false,"code":"BAD_BODY_PAIR"}
	if normal_impulse<0.0:return {"ok":false,"code":"NEGATIVE_NORMAL_IMPULSE"}
	if not bool(manifold.get("ok",false)):return {"ok":false,"code":"BAD_MANIFOLD"}
	var points:Array=manifold.get("points",[])
	if points.size()<2:return {"ok":false,"code":"DEGENERATE_CONTACT_PATCH"}
	for key in ["mu_tangent","mu_rolling","mu_torsion"]:
		if float(options.get(key,0.0))<0.0:return {"ok":false,"code":"NEGATIVE_FRICTION_COEFFICIENT","key":key}
	if float(options.get("tolerance",1.0e-11))<=0.0:return {"ok":false,"code":"BAD_TOLERANCE"}
	if int(options.get("iterations",4096))<=0:return {"ok":false,"code":"BAD_ITERATION_BUDGET"}
	var ids:Dictionary={}
	for body_any in bodies:
		var id:=String(Dictionary(body_any).get("id",""))
		if id.is_empty():return {"ok":false,"code":"EMPTY_BODY_ID"}
		if ids.has(id):return {"ok":false,"code":"DUPLICATE_BODY_ID","body_id":id}
		ids[id]=true
	if not ids.has(a_id) or not ids.has(b_id):return {"ok":false,"code":"BODY_NOT_FOUND"}
	return {"ok":true}

static func _patch_geometry(a:Dictionary,b:Dictionary,manifold:Dictionary)->Dictionary:
	var n:=Vector3(manifold.get("normal",Vector3.ZERO))
	if n.length_squared()<=EPS:return {"ok":false,"code":"ZERO_PATCH_NORMAL"}
	n=n.normalized()
	if n.dot(Vector3(b["p"])-Vector3(a["p"]))<0.0:n=-n
	var basis:=F.Model.tangent_basis(n)
	var t1:Vector3=basis[0];var t2:Vector3=basis[1]
	var points:Array=manifold["points"]
	var center:=Vector3.ZERO
	for point_any in points:center+=Vector3(Dictionary(point_any)["point"])
	center/=float(points.size())
	var radius:=0.0
	for point_any in points:
		var delta:=Vector3(Dictionary(point_any)["point"])-center
		var planar:=delta-n*delta.dot(n)
		radius=maxf(radius,planar.length())
	if radius<=EPS:return {"ok":false,"code":"DEGENERATE_CONTACT_PATCH_RADIUS"}
	return {"ok":true,"normal":n,"t1":t1,"t2":t2,"center":center,"ra":center-Vector3(a["p"]),"rb":center-Vector3(b["p"]),"effective_radius":radius,"point_count":points.size()}

static func _generalized_velocity(bodies:Array,ai:int,bi:int,patch:Dictionary)->Array:
	var a:Dictionary=bodies[ai];var b:Dictionary=bodies[bi]
	var va:=F.Model.point_velocity(a,Vector3(patch["ra"]))
	var vb:=F.Model.point_velocity(b,Vector3(patch["rb"]))
	var relative:=vb-va
	var wr:=Vector3(b["w"])-Vector3(a["w"])
	var t1:Vector3=patch["t1"];var t2:Vector3=patch["t2"];var n:Vector3=patch["normal"]
	return [relative.dot(t1),relative.dot(t2),wr.dot(t1),wr.dot(t2),wr.dot(n)]

static func _effective_matrix(bodies:Array,ai:int,bi:int,patch:Dictionary)->Array:
	var base:=_generalized_velocity(bodies,ai,bi,patch)
	var matrix:Array=[]
	for _i in range(5):matrix.append([0.0,0.0,0.0,0.0,0.0])
	for j in range(5):
		var probe:=bodies.duplicate(true)
		var z:=[0.0,0.0,0.0,0.0,0.0];z[j]=1.0
		_apply_generalized_impulse(probe,ai,bi,patch,z)
		var out:=_generalized_velocity(probe,ai,bi,patch)
		for i in range(5):matrix[i][j]=float(out[i])-float(base[i])
	return matrix

static func _apply_generalized_impulse(bodies:Array,ai:int,bi:int,patch:Dictionary,z:Array)->void:
	var t1:Vector3=patch["t1"];var t2:Vector3=patch["t2"];var n:Vector3=patch["normal"]
	var tangent:=t1*float(z[0])+t2*float(z[1])
	if tangent.length_squared()>0.0:
		var contact={"a":ai,"b":bi,"ra":patch["ra"],"rb":patch["rb"]}
		F.Model.apply_impulse(bodies,contact,tangent)
	var moment:=t1*float(z[2])+t2*float(z[3])+n*float(z[4])
	if moment.length_squared()>0.0:
		var a:Dictionary=bodies[ai];var b:Dictionary=bodies[bi]
		a["w"]=Vector3(a["w"])-F.Model.inertia_inv_mul(a,moment)
		b["w"]=Vector3(b["w"])+F.Model.inertia_inv_mul(b,moment)

static func _projected_maximum_dissipation(k:Array,u:Array,limits:Vector3,options:Dictionary)->Dictionary:
	var tolerance:=float(options.get("tolerance",1.0e-11))
	var max_iterations:=int(options.get("iterations",4096))
	var lipschitz:=0.0
	for i in range(5):
		var row_sum:=0.0
		for j in range(5):row_sum+=absf(float(k[i][j]))
		lipschitz=maxf(lipschitz,row_sum)
	if lipschitz<=EPS:return {"ok":false,"code":"SINGULAR_GENERALIZED_EFFECTIVE_MATRIX"}
	var step:=float(options.get("step_scale",0.9))/lipschitz
	if step<=0.0:return {"ok":false,"code":"BAD_STEP_SCALE"}
	var z:=[0.0,0.0,0.0,0.0,0.0]
	var residual:=INF
	for iteration in range(max_iterations):
		var gradient:=_mat_vec5(k,z,u)
		var trial:Array=[]
		for i in range(5):trial.append(float(z[i])-step*float(gradient[i]))
		var projected:=_project(trial,limits)
		residual=0.0
		for i in range(5):residual=maxf(residual,absf(float(projected[i])-float(z[i])))
		z=projected
		if residual<=tolerance:
			return {"ok":true,"z":z,"iterations":iteration+1,"residual":residual,"step":step}
	return {"ok":false,"code":"GENERALIZED_WRENCH_DID_NOT_CONVERGE","iterations":max_iterations,"residual":residual}

static func _project(z:Array,limits:Vector3)->Array:
	var out:=z.duplicate()
	var tangent:=Vector2(float(out[0]),float(out[1]))
	if tangent.length()>limits.x and tangent.length()>EPS:
		tangent*=limits.x/tangent.length()
	out[0]=tangent.x;out[1]=tangent.y
	var rolling:=Vector2(float(out[2]),float(out[3]))
	if rolling.length()>limits.y and rolling.length()>EPS:
		rolling*=limits.y/rolling.length()
	out[2]=rolling.x;out[3]=rolling.y
	out[4]=clampf(float(out[4]),-limits.z,limits.z)
	return out

static func _disk_mode(value:float,limit:float,saturated_name:String)->String:
	if limit<=EPS:return "unconstrained"
	return saturated_name if value>=limit-1.0e-8*maxf(1.0,limit) else "stick"

static func _mat_vec5(k:Array,z:Array,u:Array)->Array:
	var out:Array=[]
	for i in range(5):
		var value:=float(u[i])
		for j in range(5):value+=float(k[i][j])*float(z[j])
		out.append(value)
	return out

static func _dot5(a:Array,b:Array)->float:
	var value:=0.0
	for i in range(5):value+=float(a[i])*float(b[i])
	return value

static func _quad5(k:Array,z:Array)->float:
	var kz:=_mat_vec5(k,z,[0.0,0.0,0.0,0.0,0.0])
	return _dot5(z,kz)

static func _symmetry_error(k:Array)->float:
	var maximum:=0.0
	for i in range(5):
		for j in range(5):maximum=maxf(maximum,absf(float(k[i][j])-float(k[j][i])))
	return maximum

static func _canonical_state(bodies:Array)->Array:
	var work:=bodies.duplicate(true)
	work.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return String(a["id"])<String(b["id"]))
	var out:Array=[]
	for body_any in work:
		var body:Dictionary=body_any;var v:Vector3=body["v"];var w:Vector3=body["w"]
		out.append([String(body["id"]),v.x,v.y,v.z,w.x,w.y,w.z])
	return out
