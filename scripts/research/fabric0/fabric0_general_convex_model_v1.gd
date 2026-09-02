class_name Fabric0GeneralConvexModelV1
extends RefCounted

const EPS := 1.0e-12

static func new_shape(id:String, vertices:Array, faces:Array)->Dictionary:
	assert(vertices.size() >= 4)
	var vv:Array = []
	for v in vertices:
		vv.append(Vector3(v))
	var ff:Array = []
	for face in faces:
		var ids:Array = []
		for i in face:
			ids.append(int(i))
		assert(ids.size() >= 3)
		ff.append(ids)
	return {"id":id, "vertices":vv, "faces":ff}

static func box_shape(id:String, half:Vector3)->Dictionary:
	assert(half.x > 0.0 and half.y > 0.0 and half.z > 0.0)
	var v := [
		Vector3(-half.x,-half.y,-half.z), Vector3( half.x,-half.y,-half.z),
		Vector3( half.x, half.y,-half.z), Vector3(-half.x, half.y,-half.z),
		Vector3(-half.x,-half.y, half.z), Vector3( half.x,-half.y, half.z),
		Vector3( half.x, half.y, half.z), Vector3(-half.x, half.y, half.z),
	]
	# Every face is CCW when viewed from outside.
	var f := [
		[0,3,2,1], # -Z
		[4,5,6,7], # +Z
		[0,1,5,4], # -Y
		[3,7,6,2], # +Y
		[0,4,7,3], # -X
		[1,2,6,5], # +X
	]
	return new_shape(id,v,f)

static func tetra_shape(id:String, scale:float=1.0)->Dictionary:
	assert(scale > 0.0)
	var v := [
		Vector3(1,1,1)*scale,
		Vector3(-1,-1,1)*scale,
		Vector3(-1,1,-1)*scale,
		Vector3(1,-1,-1)*scale,
	]
	var f := [[0,2,1],[0,1,3],[0,3,2],[1,2,3]]
	return new_shape(id,v,f)

static func new_body(id:String, shape:Dictionary, p:Vector3, q:Quaternion=Quaternion.IDENTITY, mass:float=1.0, inertia:Vector3=Vector3(0.2,0.25,0.3), v:Vector3=Vector3.ZERO, w:Vector3=Vector3.ZERO)->Dictionary:
	assert(mass > 0.0)
	assert(inertia.x > 0.0 and inertia.y > 0.0 and inertia.z > 0.0)
	return {
		"id":id, "shape":shape, "p":p, "q":q.normalized(), "v":v, "w":w,
		"mass":mass, "inv_mass":1.0/mass, "inertia":inertia,
	}

static func world_vertex(body:Dictionary, local:Vector3)->Vector3:
	return Vector3(body["p"]) + Quaternion(body["q"]) * local

static func local_vertex(body:Dictionary, world:Vector3)->Vector3:
	return Quaternion(body["q"]).inverse() * (world - Vector3(body["p"]))

static func support(body:Dictionary, direction:Vector3)->Dictionary:
	var d := direction
	if d.length_squared() <= EPS:
		d = Vector3.RIGHT
	var ld := Quaternion(body["q"]).inverse() * d
	var vertices:Array = body["shape"]["vertices"]
	var best_i := 0
	var best_dot := Vector3(vertices[0]).dot(ld)
	for i in range(1, vertices.size()):
		var score := Vector3(vertices[i]).dot(ld)
		if score > best_dot + EPS:
			best_dot = score
			best_i = i
	return {"index":best_i, "point":world_vertex(body,Vector3(vertices[best_i]))}

static func minkowski_support(a:Dictionary, b:Dictionary, direction:Vector3)->Dictionary:
	var sa := support(a,direction)
	var sb := support(b,-direction)
	return {
		"p":Vector3(sa["point"]) - Vector3(sb["point"]),
		"wa":Vector3(sa["point"]), "wb":Vector3(sb["point"]),
		"ia":int(sa["index"]), "ib":int(sb["index"]),
	}

static func face_vertices_world(body:Dictionary, face_index:int)->Array:
	var out:Array = []
	var face:Array = body["shape"]["faces"][face_index]
	for i in face:
		out.append(world_vertex(body,Vector3(body["shape"]["vertices"][int(i)])))
	return out

static func face_normal_world(body:Dictionary, face_index:int)->Vector3:
	var p := face_vertices_world(body,face_index)
	return (Vector3(p[1])-Vector3(p[0])).cross(Vector3(p[2])-Vector3(p[0])).normalized()

static func best_face(body:Dictionary, direction:Vector3)->Dictionary:
	var faces:Array = body["shape"]["faces"]
	var best := 0
	var best_dot := -INF
	for i in range(faces.size()):
		var n := face_normal_world(body,i)
		var d := n.dot(direction)
		if d > best_dot + EPS:
			best_dot = d
			best = i
	return {"index":best, "normal":face_normal_world(body,best), "vertices":face_vertices_world(body,best), "dot":best_dot}

static func aabb(body:Dictionary)->AABB:
	var vertices:Array = body["shape"]["vertices"]
	var p0 := world_vertex(body,Vector3(vertices[0]))
	var lo := p0
	var hi := p0
	for i in range(1,vertices.size()):
		var p := world_vertex(body,Vector3(vertices[i]))
		lo = Vector3(minf(lo.x,p.x),minf(lo.y,p.y),minf(lo.z,p.z))
		hi = Vector3(maxf(hi.x,p.x),maxf(hi.y,p.y),maxf(hi.z,p.z))
	return AABB(lo,hi-lo)

static func broadphase_pairs(bodies:Array)->Array:
	var entries:Array = []
	for i in range(bodies.size()):
		var box := aabb(bodies[i])
		entries.append({"i":i,"min_x":box.position.x,"max_x":box.end.x,"box":box,"id":String(bodies[i]["id"])})
	entries.sort_custom(func(x:Dictionary,y:Dictionary)->bool:
		if absf(float(x["min_x"])-float(y["min_x"])) > EPS:return float(x["min_x"]) < float(y["min_x"])
		return String(x["id"]) < String(y["id"])
	)
	var out:Array = []
	for a_idx in range(entries.size()):
		var ea:Dictionary = entries[a_idx]
		for b_idx in range(a_idx+1,entries.size()):
			var eb:Dictionary = entries[b_idx]
			if float(eb["min_x"]) > float(ea["max_x"]) + EPS:break
			var aa:AABB = ea["box"]
			var bb:AABB = eb["box"]
			if aa.end.y < bb.position.y or bb.end.y < aa.position.y:continue
			if aa.end.z < bb.position.z or bb.end.z < aa.position.z:continue
			var i := int(ea["i"])
			var j := int(eb["i"])
			if i > j:
				var temporary := i
				i = j
				j = temporary
			out.append([i,j])
	out.sort_custom(func(x:Array,y:Array)->bool:
		if int(x[0]) != int(y[0]):return int(x[0]) < int(y[0])
		return int(x[1]) < int(y[1])
	)
	return out


static func inertia_mul(body:Dictionary, omega_world:Vector3)->Vector3:
	var q:Quaternion = body["q"]
	var local := q.inverse() * omega_world
	var inertia:Vector3 = body["inertia"]
	return q * Vector3(local.x*inertia.x,local.y*inertia.y,local.z*inertia.z)

static func total_linear_momentum(bodies:Array)->Vector3:
	var momentum := Vector3.ZERO
	for body in bodies:
		momentum += float(body["mass"]) * Vector3(body["v"])
	return momentum

static func total_angular_momentum_origin(bodies:Array)->Vector3:
	var momentum := Vector3.ZERO
	for body in bodies:
		var linear := float(body["mass"]) * Vector3(body["v"])
		momentum += Vector3(body["p"]).cross(linear) + inertia_mul(body,Vector3(body["w"]))
	return momentum

static func total_kinetic_energy(bodies:Array)->float:
	var energy := 0.0
	for body in bodies:
		var linear := Vector3(body["v"])
		var angular := Vector3(body["w"])
		energy += 0.5 * float(body["mass"]) * linear.length_squared()
		energy += 0.5 * angular.dot(inertia_mul(body,angular))
	return energy

static func inertia_inv_mul(body:Dictionary, torque_world:Vector3)->Vector3:
	var q:Quaternion = body["q"]
	var local := q.inverse() * torque_world
	var i:Vector3 = body["inertia"]
	return q * Vector3(local.x/i.x,local.y/i.y,local.z/i.z)

static func point_velocity(body:Dictionary, r:Vector3)->Vector3:
	return Vector3(body["v"]) + Vector3(body["w"]).cross(r)

static func contact_velocity(bodies:Array, c:Dictionary)->Vector3:
	var b:Dictionary = bodies[int(c["b"])]
	var vb := point_velocity(b,Vector3(c["rb"]))
	if int(c["a"]) < 0:return vb
	var a:Dictionary = bodies[int(c["a"])]
	return vb - point_velocity(a,Vector3(c["ra"]))

static func apply_impulse(bodies:Array, c:Dictionary, impulse:Vector3)->void:
	var b:Dictionary = bodies[int(c["b"])]
	b["v"] = Vector3(b["v"]) + impulse*float(b["inv_mass"])
	b["w"] = Vector3(b["w"]) + inertia_inv_mul(b,Vector3(c["rb"]).cross(impulse))
	if int(c["a"]) >= 0:
		var a:Dictionary = bodies[int(c["a"])]
		a["v"] = Vector3(a["v"]) - impulse*float(a["inv_mass"])
		a["w"] = Vector3(a["w"]) - inertia_inv_mul(a,Vector3(c["ra"]).cross(impulse))

static func tangent_basis(n:Vector3)->Array:
	var ref := Vector3.UP
	if absf(n.dot(ref)) > 0.85:ref = Vector3.RIGHT
	var t1 := ref.cross(n).normalized()
	var t2 := n.cross(t1).normalized()
	return [t1,t2]

static func effective_scalar(bodies:Array,c:Dictionary,dir:Vector3)->float:
	var result := 0.0
	var b:Dictionary = bodies[int(c["b"])]
	result += float(b["inv_mass"])
	result += dir.dot(inertia_inv_mul(b,Vector3(c["rb"]).cross(dir)).cross(Vector3(c["rb"])))
	if int(c["a"]) >= 0:
		var a:Dictionary = bodies[int(c["a"])]
		result += float(a["inv_mass"])
		result += dir.dot(inertia_inv_mul(a,Vector3(c["ra"]).cross(dir)).cross(Vector3(c["ra"])))
	return result

static func effective_tangent2(bodies:Array,c:Dictionary,t1:Vector3,t2:Vector3)->Array:
	var k11 := effective_scalar(bodies,c,t1)
	var k22 := effective_scalar(bodies,c,t2)
	var k12 := 0.0
	var b:Dictionary = bodies[int(c["b"])]
	k12 += t1.dot(inertia_inv_mul(b,Vector3(c["rb"]).cross(t2)).cross(Vector3(c["rb"])))
	if int(c["a"]) >= 0:
		var a:Dictionary = bodies[int(c["a"])]
		k12 += t1.dot(inertia_inv_mul(a,Vector3(c["ra"]).cross(t2)).cross(Vector3(c["ra"])))
	return [[k11,k12],[k12,k22]]

static func solve2(k:Array,b:Vector2)->Vector2:
	var det := float(k[0][0])*float(k[1][1])-float(k[0][1])*float(k[1][0])
	if absf(det) <= EPS:return Vector2.ZERO
	return Vector2((b.x*float(k[1][1])-float(k[0][1])*b.y)/det,(float(k[0][0])*b.y-b.x*float(k[1][0]))/det)
