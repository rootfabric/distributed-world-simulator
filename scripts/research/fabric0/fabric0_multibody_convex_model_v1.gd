class_name Fabric0MultibodyConvexModelV1
extends RefCounted

const Rigid = preload("res://scripts/research/fabric0/fabric0_full6dof_contact_v1.gd")
const Sparse = preload("res://scripts/research/fabric0/fabric0_unified_adaptive_3d_sparse_v1.gd")
const Z := Vector3.BACK
const EPS := 1.0e-12

static func new_body(id:String,p:Vector3,v:Vector3,w:Vector3=Vector3.ZERO,mass:float=1.0,radius:float=0.5,inertia:Vector3=Vector3(0.11,0.13,0.17))->Dictionary:
	return {
		"id":id,"p":p,"q":Quaternion.IDENTITY,"v":v,"w":w,
		"mass":mass,"inv_mass":1.0/mass,"radius":radius,"inertia":inertia,
	}

static func new_world()->Dictionary:
	var bodies := [
		new_body("A",Vector3(0,0,0.5),Vector3.ZERO,Vector3(0.15,-0.08,0.04),1.0,0.5,Vector3(0.10,0.13,0.16)),
		new_body("B",Vector3(0,0,1.5),Vector3.ZERO,Vector3(-0.05,0.12,-0.07),1.15,0.5,Vector3(0.12,0.16,0.19)),
		new_body("C",Vector3(0,0,2.5),Vector3.ZERO,Vector3(0.09,0.03,0.11),0.9,0.5,Vector3(0.09,0.12,0.14)),
		new_body("D",Vector3(0.0,0.0,3.7),Vector3(0.3,-0.15,-0.2),Vector3(0.25,-0.18,0.9),0.3,0.5,Vector3(0.032,0.041,0.052)),
	]
	var world := {
		"time":0.0,"bodies":bodies,"gravity":Vector3(0,0,-9.81),
		"mu_plane":0.48,"mu_pair":0.34,"pair_restitution":0.0,
		"contact_slop":2.5e-4,"release_slop":1.5e-3,"beta":0.12,
		"solver_iterations":32,"release_time":0.32,"drive_force":Vector3.ZERO,"release_force":Vector3(0.0,0.0,12.0),
		"contacts":{},"suppressed":{},"events":[],"mode_events":[],"graph_events":[],
		"max_normal_violation":0.0,"max_cone_violation":0.0,"min_normal_impulse":INF,
		"max_internal_linear_momentum_error":0.0,"max_internal_angular_momentum_error":0.0,
		"contact_iterations":0,"contact_solves":0,"max_penetration":0.0,
		"contact_dissipation":0.0,"contact_gain":0.0,"external_work":0.0,"projection_energy_delta":0.0,"projection_distance":0.0,
		"initial_components":[],"initial_energy":0.0,"final_energy":0.0,
	}
	world["initial_energy"] = total_energy(world)
	world["final_energy"] = world["initial_energy"]
	return world

static func body_index(world:Dictionary,id:String)->int:
	for i in range(world["bodies"].size()):
		if String(world["bodies"][i]["id"])==id:return i
	return -1

static func body(world:Dictionary,id:String)->Dictionary:
	var i:=body_index(world,id);assert(i>=0);return world["bodies"][i]

static func inertia_mul(b:Dictionary,w:Vector3)->Vector3:
	return Rigid.inertia_mul(Quaternion(b["q"]),Vector3(b["inertia"]),w)
static func inertia_inv_mul(b:Dictionary,t:Vector3)->Vector3:
	return Rigid.inertia_inv_mul(Quaternion(b["q"]),Vector3(b["inertia"]),t)

static func kinetic_body(b:Dictionary)->float:
	var v:Vector3=b["v"];var w:Vector3=b["w"]
	return 0.5*float(b["mass"])*v.length_squared()+0.5*w.dot(inertia_mul(b,w))
static func total_kinetic(world:Dictionary)->float:
	var e:=0.0
	for b in world["bodies"]:e+=kinetic_body(b)
	return e
static func total_energy(world:Dictionary)->float:
	var e:=total_kinetic(world);var g:Vector3=world["gravity"]
	for b in world["bodies"]:e-=float(b["mass"])*g.dot(Vector3(b["p"]))
	return e
static func total_linear_momentum(world:Dictionary)->Vector3:
	var p:=Vector3.ZERO
	for b in world["bodies"]:p+=float(b["mass"])*Vector3(b["v"])
	return p
static func total_angular_momentum_origin(world:Dictionary)->Vector3:
	var l:=Vector3.ZERO
	for b in world["bodies"]:
		l+=Vector3(b["p"]).cross(float(b["mass"])*Vector3(b["v"]))+inertia_mul(b,Vector3(b["w"]))
	return l

static func pair_id(a:String,b:String)->String:
	return a+"|"+b if a<b else b+"|"+a

static func contact_geometry(world:Dictionary,a_idx:int,b_idx:int)->Dictionary:
	if a_idx<0:
		var b:Dictionary=world["bodies"][b_idx];var rb:=Vector3(0,0,-float(b["radius"]))
		return {"normal":Z,"gap":Vector3(b["p"]).z-float(b["radius"]),"ra":Vector3.ZERO,"rb":rb,"point":Vector3(b["p"])+rb}
	var a:Dictionary=world["bodies"][a_idx];var b:Dictionary=world["bodies"][b_idx]
	var d:=Vector3(b["p"])-Vector3(a["p"]);var dist:=d.length();var n:=Vector3.RIGHT if dist<=EPS else d/dist
	var pa:=Vector3(a["p"])+n*float(a["radius"]);var pb:=Vector3(b["p"])-n*float(b["radius"]);var cp:=0.5*(pa+pb)
	return {"normal":n,"gap":dist-float(a["radius"])-float(b["radius"]),"ra":cp-Vector3(a["p"]),"rb":cp-Vector3(b["p"]),"point":cp}

static func tangent_basis(n:Vector3)->Array:
	var ref:=Z
	if absf(n.dot(ref))>0.88:ref=Vector3.RIGHT
	var t1:=ref.cross(n).normalized();var t2:=n.cross(t1).normalized()
	return [t1,t2]

static func contact_velocity(world:Dictionary,c:Dictionary)->Vector3:
	var b:Dictionary=world["bodies"][int(c["b"])]
	var vb:=Vector3(b["v"])+Vector3(b["w"]).cross(Vector3(c["rb"]))
	if int(c["a"])<0:return vb
	var a:Dictionary=world["bodies"][int(c["a"])]
	var va:=Vector3(a["v"])+Vector3(a["w"]).cross(Vector3(c["ra"]))
	return vb-va

static func apply_impulse(world:Dictionary,c:Dictionary,j:Vector3)->void:
	var bi:=int(c["b"]);var b:Dictionary=world["bodies"][bi]
	b["v"]=Vector3(b["v"])+j*float(b["inv_mass"])
	b["w"]=Vector3(b["w"])+inertia_inv_mul(b,Vector3(c["rb"]).cross(j))
	if int(c["a"])>=0:
		var ai:=int(c["a"]);var a:Dictionary=world["bodies"][ai]
		a["v"]=Vector3(a["v"])-j*float(a["inv_mass"])
		a["w"]=Vector3(a["w"])-inertia_inv_mul(a,Vector3(c["ra"]).cross(j))

static func effective_scalar(world:Dictionary,c:Dictionary,dir:Vector3)->float:
	var result:=0.0
	var b:Dictionary=world["bodies"][int(c["b"])]
	result+=float(b["inv_mass"])
	result+=dir.dot(inertia_inv_mul(b,Vector3(c["rb"]).cross(dir)).cross(Vector3(c["rb"])))
	if int(c["a"])>=0:
		var a:Dictionary=world["bodies"][int(c["a"])]
		result+=float(a["inv_mass"])
		result+=dir.dot(inertia_inv_mul(a,Vector3(c["ra"]).cross(dir)).cross(Vector3(c["ra"])))
	return result

static func effective_tangent2(world:Dictionary,c:Dictionary,t1:Vector3,t2:Vector3)->Array:
	var k11:=effective_scalar(world,c,t1);var k22:=effective_scalar(world,c,t2)
	var cross12:=0.0
	var b:Dictionary=world["bodies"][int(c["b"])]
	cross12+=t1.dot(inertia_inv_mul(b,Vector3(c["rb"]).cross(t2)).cross(Vector3(c["rb"])))
	if int(c["a"])>=0:
		var a:Dictionary=world["bodies"][int(c["a"])]
		cross12+=t1.dot(inertia_inv_mul(a,Vector3(c["ra"]).cross(t2)).cross(Vector3(c["ra"])))
	return [[k11,cross12],[cross12,k22]]

static func solve2(k:Array,b:Vector2)->Vector2:
	var det:=float(k[0][0])*float(k[1][1])-float(k[0][1])*float(k[1][0])
	if absf(det)<=EPS:return Vector2.ZERO
	return Vector2((b.x*float(k[1][1])-float(k[0][1])*b.y)/det,(float(k[0][0])*b.y-b.x*float(k[1][0]))/det)

static func discover_contacts(world:Dictionary)->Array:
	var result:Array=[];var old:Dictionary=world["contacts"];var slop:=float(world["contact_slop"]);var release:=float(world["release_slop"])
	for j in range(world["bodies"].size()):
		var id:="plane|"+String(world["bodies"][j]["id"]);var g:=contact_geometry(world,-1,j);var keep:=old.has(id)
		if world.get("suppressed",{}).has(id):
			continue
		if float(g["gap"]) <= (release if keep else slop):
			var c={"id":id,"a":-1,"b":j,"mu":float(world["mu_plane"]),"restitution":0.0,"is_new":not keep}
			c.merge(g);result.append(c)
	for i in range(world["bodies"].size()):
		for j in range(i+1,world["bodies"].size()):
			var ida:=String(world["bodies"][i]["id"]);var idb:=String(world["bodies"][j]["id"]);var id:=pair_id(ida,idb);var g:=contact_geometry(world,i,j);var keep:=old.has(id)
			if world.get("suppressed",{}).has(id):
				continue
			if float(g["gap"]) <= (release if keep else slop):
				var c={"id":id,"a":i,"b":j,"mu":float(world["mu_pair"]),"restitution":float(world["pair_restitution"]),"is_new":not keep}
				c.merge(g);result.append(c)
	result.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return String(a["id"])<String(b["id"]))
	return result

static func dynamic_components(world:Dictionary,contacts:Array)->Array:
	var ids:Array=[];for b in world["bodies"]:ids.append(String(b["id"]));ids.sort()
	var parent:={};for id in ids:parent[id]=id
	for c in contacts:
		if int(c["a"])<0:continue
		var a:=String(world["bodies"][int(c["a"])]["id"]);var b:=String(world["bodies"][int(c["b"])]["id"])
		var ra:=_find(parent,a);var rb:=_find(parent,b)
		if ra!=rb:
			if ra<rb:parent[rb]=ra
			else:parent[ra]=rb
	var groups:={}
	for id in ids:
		var r:=_find(parent,id)
		if not groups.has(r):
			groups[r]=[]
		groups[r].append(id)
	var out:Array=[]
	for g in groups.values():
		g.sort()
		out.append(g)
	out.sort_custom(func(a:Array,b:Array)->bool:return String(a[0])<String(b[0]))
	return out
static func _find(parent:Dictionary,x:String)->String:
	var r:=x
	while String(parent[r])!=r:r=String(parent[r])
	return r

static func graph_hash(world:Dictionary)->String:
	var bs:Array=[]
	for b in world["bodies"]:
		var q:Quaternion=b["q"]
		bs.append({"id":String(b["id"]),"p":b["p"],"q":[q.x,q.y,q.z,q.w],"v":b["v"],"w":b["w"]})
	var cs:Array=[];for id in world["contacts"].keys():cs.append(String(id));cs.sort()
	var ev:Array=[]
	for e in world["events"]:ev.append({"kind":String(e["kind"]),"time":float(e["time"]),"id":String(e.get("id",""))})
	return Sparse._sha(JSON.stringify({"time":float(world["time"]),"bodies":bs,"contacts":cs,"events":ev},"",false))
