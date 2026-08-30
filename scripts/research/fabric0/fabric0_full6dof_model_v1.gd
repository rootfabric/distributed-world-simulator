class_name Fabric0Full6DOFModelV1
extends RefCounted

const Contact = preload("res://scripts/research/fabric0/fabric0_full6dof_contact_v1.gd")
const Sparse = preload("res://scripts/research/fabric0/fabric0_unified_adaptive_3d_sparse_v1.gd")
const UP := Vector3.BACK
const IDX_P:=0
const IDX_Q:=3
const IDX_V:=7
const IDX_W:=10

static func new_world() -> Dictionary:
	var q := (Quaternion(Vector3.RIGHT,0.31)*Quaternion(Vector3.UP,-0.23)*Quaternion(Vector3.BACK,0.19)).normalized()
	var s:=pack(Vector3(0.0,0.0,1.25),q,Vector3(1.8,-0.9,-3.4),Vector3(1.35,-1.1,1.8))
	var world:={
		"time":0.0,"state":s,"mass":2.0,"inertia_body":Vector3(0.19,0.31,0.43),"half":Vector3(0.45,0.32,0.25),
		"gravity":Vector3(0,0,-9.81),"external_force":Vector3.ZERO,"external_torque":Vector3.ZERO,
		"mu":0.42,"restitution":0.0,"contact_active":false,"contact_mode":"slide","support_signs":Vector3.ZERO,
		"events":[],"warm_force":{},"warm_impulse":{},"max_gap":0.0,"max_quat_error":0.0,"min_normal_force":INF,"max_cone_ratio":0.0,
		"accepted_steps":0,"rejected_steps":0,"min_step":INF,"max_step":0.0,"contact_force_calls":0,"slide_force_calls":0,"stick_force_calls":0,"friction_dissipation":0.0,"feature_guard":[false,false,false],
	}
	world["initial_energy"]=_energy(world,s);world["final_energy"]=world["initial_energy"]
	return world

static func pack(p:Vector3,q:Quaternion,v:Vector3,w:Vector3)->Array:
	q=q.normalized();return [p.x,p.y,p.z,q.x,q.y,q.z,q.w,v.x,v.y,v.z,w.x,w.y,w.z]
static func pos(s:Array)->Vector3:return Vector3(float(s[0]),float(s[1]),float(s[2]))
static func quat(s:Array)->Quaternion:return Quaternion(float(s[3]),float(s[4]),float(s[5]),float(s[6])).normalized()
static func vel(s:Array)->Vector3:return Vector3(float(s[7]),float(s[8]),float(s[9]))
static func omega(s:Array)->Vector3:return Vector3(float(s[10]),float(s[11]),float(s[12]))
static func with_parts(s:Array,p:Vector3,q:Quaternion,v:Vector3,w:Vector3)->Array:return pack(p,q,v,w)

static func _sgn(v:float)->float:return -1.0 if v<0.0 else 1.0
static func support_signs_from_q(q:Quaternion)->Vector3:
	var nb:=q.inverse()*UP
	return Vector3(-_sgn(nb.x),-_sgn(nb.y),-_sgn(nb.z))

static func _vertex_id(signs:Vector3)->String:
	return "v:%s%s%s" % ["+" if signs.x>0 else "-","+" if signs.y>0 else "-","+" if signs.z>0 else "-"]
static func local_vertex(world:Dictionary,signs:Vector3)->Vector3:
	var h:Vector3=world["half"];return Vector3(signs.x*h.x,signs.y*h.y,signs.z*h.z)

static func feature_from_signs(world:Dictionary, signs:Vector3)->Dictionary:
	var id:=_vertex_id(signs)
	return {"type":"vertex","id":id,"relation":"plane|C|"+id,"lineage":[id],"point_count":1,"local_point":local_vertex(world,signs)}

static func degenerate_feature(world:Dictionary, old_signs:Vector3, axis:int)->Dictionary:
	var a:=old_signs;var b:=old_signs
	if axis==0:b.x=-b.x
	elif axis==1:b.y=-b.y
	else:b.z=-b.z
	var ids:=[_vertex_id(a),_vertex_id(b)];ids.sort()
	var lp:=(local_vertex(world,a)+local_vertex(world,b))*0.5
	return {"type":"edge","id":"edge:"+String.num_int64(axis)+":"+ids[0]+":"+ids[1],"relation":"plane|C|edge:"+String.num_int64(axis)+":"+ids[0]+":"+ids[1],"lineage":ids,"point_count":2,"local_point":lp}

static func support_feature_from_orientation(world:Dictionary,q:Quaternion,tol:float=1e-10)->Dictionary:
	var nb:=q.inverse()*UP
	var comps:=[nb.x,nb.y,nb.z];var choices:Array=[];var zero_axes:Array=[]
	for i in range(3):
		if absf(float(comps[i]))<=tol:
			choices.append([-1.0,1.0]);zero_axes.append(i)
		else:choices.append([-_sgn(float(comps[i]))])
	var ids:Array=[];var sum:=Vector3.ZERO;var count:=0
	for x in choices[0]:
		for y in choices[1]:
			for z in choices[2]:
				var sg:=Vector3(float(x),float(y),float(z));ids.append(_vertex_id(sg));sum+=local_vertex(world,sg);count+=1
	ids.sort();var typ:String="vertex"
	if zero_axes.size()==1:typ="edge"
	elif zero_axes.size()==2:typ="face"
	return {"type":typ,"id":typ+":"+":".join(ids),"relation":"plane|C|"+typ+":"+":".join(ids),"lineage":ids,"point_count":count,"local_point":sum/float(count),"zero_axes":zero_axes,"n_body":nb}

static func current_feature(world:Dictionary)->Dictionary:
	return feature_from_signs(world,world["support_signs"])
static func contact_geometry(world:Dictionary,s:Array,feature:Dictionary)->Dictionary:
	var q:=quat(s);var r:=q*Vector3(feature["local_point"]);var p:=pos(s);var vc:=vel(s)+omega(s).cross(r)
	return {"r":r,"world_point":p+r,"gap":p.z+r.z,"vc":vc}
static func free_gap(world:Dictionary,s:Array)->float:
	var f:=support_feature_from_orientation(world,quat(s),0.0);return float(contact_geometry(world,s,f)["gap"])

static func project_contact(world:Dictionary,s:Array)->Array:
	if not bool(world["contact_active"]):return normalize_state(s)
	var f:=current_feature(world);var q:=quat(s);var p:=pos(s);var v:=vel(s);var w:=omega(s);var r:=q*Vector3(f["local_point"])
	p.z=-r.z
	var vc:=v+w.cross(r)
	v.z-=vc.z
	return pack(p,q,v,w)
static func normalize_state(s:Array)->Array:return pack(pos(s),quat(s),vel(s),omega(s))

static func force_probe(world:Dictionary,s:Array,preferred_mode:String="slide")->Dictionary:
	var ss:=project_contact(world,s);var f:=current_feature(world);var g:=contact_geometry(world,ss,f);var q:=quat(ss);var v:=vel(ss);var w:=omega(ss)
	var ext:Vector3=world["gravity"]*float(world["mass"])+Vector3(world["external_force"])
	return Contact.friction_force(q,world["inertia_body"],float(world["mass"]),g["r"],v,w,ext,world["external_torque"],float(world["mu"]),preferred_mode)

static func friction_power(world:Dictionary,raw:Array)->float:
	if not bool(world["contact_active"]):return 0.0
	var s:=project_contact(world,raw)
	var probe:=force_probe(world,s,String(world["contact_mode"]))
	if not bool(probe["ok"]) or not bool(probe["active"]) or String(probe["mode"])!="slide":return 0.0
	var vc:Vector3=probe["vc"];var f:Vector3=probe["force"]
	return maxf(0.0,-(f.x*vc.x+f.y*vc.y))

static func derivative(world:Dictionary,raw:Array)->Array:
	var s:=project_contact(world,raw) if bool(world["contact_active"]) else normalize_state(raw)
	var p:=pos(s);var q:=quat(s);var v:=vel(s);var w:=omega(s)
	var force:Vector3=world["gravity"]*float(world["mass"])+Vector3(world["external_force"]);var torque:Vector3=world["external_torque"]
	if bool(world["contact_active"]):
		var probe:=force_probe(world,s,String(world["contact_mode"]));assert(bool(probe["ok"]))
		if bool(probe["active"]):
			var f:Vector3=probe["force"];var geom:=contact_geometry(world,s,current_feature(world));force+=f;torque+=Vector3(geom["r"]).cross(f)
	var a:=force/float(world["mass"])
	var iw:=Contact.inertia_mul(q,world["inertia_body"],w)
	var alpha:=Contact.inertia_inv_mul(q,world["inertia_body"],torque-w.cross(iw))
	var oq:=Quaternion(w.x,w.y,w.z,0.0);var qd:=oq*q;qd=Quaternion(qd.x*0.5,qd.y*0.5,qd.z*0.5,qd.w*0.5)
	return [v.x,v.y,v.z,qd.x,qd.y,qd.z,qd.w,a.x,a.y,a.z,alpha.x,alpha.y,alpha.z]

static func apply_impact(world:Dictionary,s:Array)->Dictionary:
	var q:=quat(s);var signs:=support_signs_from_q(q);world["support_signs"]=signs
	var f:=feature_from_signs(world,signs);var g:=contact_geometry(world,s,f);var v:=vel(s);var w:=omega(s)
	var before_energy:=_kinetic(world,s);var before_p:=v*float(world["mass"]);var before_l:=Contact.inertia_mul(q,world["inertia_body"],w)
	var imp:=Contact.impact_impulse(q,world["inertia_body"],float(world["mass"]),g["r"],v,w,float(world["mu"]),float(world["restitution"]));if not bool(imp["ok"]):return imp
	if not bool(imp["active"]):return {"ok":false,"code":"IMPACT_NOT_ACTIVE"}
	var p:Vector3=imp["impulse"];var applied:=Contact.apply_impulse(q,world["inertia_body"],float(world["mass"]),g["r"],v,w,p)
	world["contact_active"]=true;world["contact_mode"]=String(imp["mode"]);world["warm_impulse"][String(f["relation"])]=p
	var out:=project_contact(world,pack(pos(s),q,applied["v"],applied["w"]));var after_p:=vel(out)*float(world["mass"]);var after_l:=Contact.inertia_mul(q,world["inertia_body"],omega(out));var after_energy:=_kinetic(world,out)
	return {"ok":true,"state":out,"feature":f,"impulse":p,"mode":String(imp["mode"]),"cone_ratio":float(imp["cone_ratio"]),"linear_momentum_error":(after_p-before_p-p).length(),"angular_momentum_error":(after_l-before_l-Vector3(g["r"]).cross(p)).length(),"kinetic_delta":after_energy-before_energy,"vc_before":imp["vc_before"]}

static func apply_feature_impulse(world:Dictionary,s:Array,feature:Dictionary)->Dictionary:
	var q:=quat(s);var g:=contact_geometry(world,s,feature);var v:=vel(s);var w:=omega(s)
	var before_energy:=_kinetic(world,s);var before_p:=linear_momentum(world,s);var before_l:=angular_momentum(world,s)
	var imp:=Contact.impact_impulse(q,world["inertia_body"],float(world["mass"]),g["r"],v,w,float(world["mu"]),float(world["restitution"]))
	if not bool(imp["ok"]):return imp
	if not bool(imp["active"]):
		return {"ok":true,"active":false,"state":s,"impulse":Vector3.ZERO,"mode":"separated","cone_ratio":0.0,"linear_momentum_error":0.0,"angular_momentum_error":0.0,"kinetic_delta":0.0,"vc_before":imp["vc_before"]}
	var p:Vector3=imp["impulse"];var applied:=Contact.apply_impulse(q,world["inertia_body"],float(world["mass"]),g["r"],v,w,p)
	var out:=pack(pos(s),q,applied["v"],applied["w"]);var after_p:=linear_momentum(world,out);var after_l:=angular_momentum(world,out);var after_energy:=_kinetic(world,out)
	return {"ok":true,"active":true,"state":out,"impulse":p,"mode":String(imp["mode"]),"cone_ratio":float(imp["cone_ratio"]),"linear_momentum_error":(after_p-before_p-p).length(),"angular_momentum_error":(after_l-before_l-Vector3(g["r"]).cross(p)).length(),"kinetic_delta":after_energy-before_energy,"vc_before":imp["vc_before"]}

static func feature_component(s:Array,axis:int)->float:
	var nb:=quat(s).inverse()*UP
	return nb.x if axis==0 else (nb.y if axis==1 else nb.z)
static func next_signs(signs:Vector3,axis:int)->Vector3:
	var n:=signs
	if axis==0:n.x=-n.x
	elif axis==1:n.y=-n.y
	else:n.z=-n.z
	return n
static func lineage_remap(oldf:Dictionary,value,newf:Dictionary):
	var setn:={};for x in newf["lineage"]:setn[String(x)]=true
	for x in oldf["lineage"]:
		if setn.has(String(x)):return value
	return Vector3.ZERO if value is Vector3 else 0.0

static func _kinetic(world:Dictionary,s:Array)->float:
	var v:=vel(s);var w:=omega(s);var q:=quat(s);return 0.5*float(world["mass"])*v.length_squared()+0.5*w.dot(Contact.inertia_mul(q,world["inertia_body"],w))
static func _energy(world:Dictionary,s:Array)->float:return _kinetic(world,s)-float(world["mass"])*Vector3(world["gravity"]).dot(pos(s))
static func linear_momentum(world:Dictionary,s:Array)->Vector3:
	return vel(s)*float(world["mass"])
static func angular_momentum(world:Dictionary,s:Array)->Vector3:
	return Contact.inertia_mul(quat(s),world["inertia_body"],omega(s))
static func rotational_energy(world:Dictionary,s:Array)->float:
	var w:=omega(s);return 0.5*w.dot(Contact.inertia_mul(quat(s),world["inertia_body"],w))

static func world_hash(world:Dictionary)->String:
	var events:Array=[];for e in world["events"]:events.append({"kind":String(e["kind"]),"time":float(e["time"]),"feature":String(e.get("feature",e.get("final_feature","")))})
	var payload={"time":float(world["time"]),"state":world["state"],"contact":bool(world["contact_active"]),"mode":String(world["contact_mode"]),"signs":world["support_signs"],"events":events}
	return Sparse._sha(JSON.stringify(payload,"",false))
