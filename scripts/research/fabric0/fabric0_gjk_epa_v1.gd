class_name Fabric0GjkEpaV1
extends RefCounted

const Model = preload("res://scripts/research/fabric0/fabric0_general_convex_model_v1.gd")
const EPS := 1.0e-10
const EPA_TOL := 1.0e-8

static func intersect(a:Dictionary,b:Dictionary,max_iterations:int=48)->Dictionary:
	var direction := Vector3(b["p"]) - Vector3(a["p"])
	if direction.length_squared() <= EPS:direction = Vector3(1.0,0.37,-0.19)
	var simplex:Array = [Model.minkowski_support(a,b,direction)]
	direction = -Vector3(simplex[0]["p"])
	for iteration in range(max_iterations):
		if direction.length_squared() <= EPS:
			return {"ok":true,"intersect":true,"simplex":simplex,"iterations":iteration+1}
		var point := Model.minkowski_support(a,b,direction)
		if Vector3(point["p"]).dot(direction) < -EPS:
			return {"ok":true,"intersect":false,"simplex":simplex,"iterations":iteration+1,"separating_direction":direction}
		simplex.append(point)
		var update := _update_simplex(simplex)
		simplex = update["simplex"]
		if bool(update["contains"]):
			if simplex.size() < 4:
				var expanded := _expand_simplex(a,b,simplex)
				if not bool(expanded["ok"]):return expanded
				simplex = expanded["simplex"]
			return {"ok":true,"intersect":true,"simplex":simplex,"iterations":iteration+1}
		direction = Vector3(update["direction"])
	return {"ok":false,"code":"GJK_DID_NOT_CONVERGE","simplex":simplex}

static func penetration(a:Dictionary,b:Dictionary,max_gjk_iterations:int=48,max_epa_iterations:int=96)->Dictionary:
	var gjk := intersect(a,b,max_gjk_iterations)
	if not bool(gjk["ok"]):return gjk
	if not bool(gjk["intersect"]):return {"ok":true,"intersect":false,"gjk":gjk}
	var simplex:Array = gjk["simplex"]
	if simplex.size() < 4:
		var expanded := _expand_simplex(a,b,simplex)
		if not bool(expanded["ok"]):return expanded
		simplex = expanded["simplex"]
	var vertices:Array = simplex.duplicate(true)
	var faces:Array = []
	for tri in [[0,1,2],[0,3,1],[0,2,3],[1,3,2]]:
		var face := _make_face(vertices,int(tri[0]),int(tri[1]),int(tri[2]))
		if bool(face["ok"]):faces.append(face)
	if faces.size() < 4:return {"ok":false,"code":"EPA_DEGENERATE_INITIAL_POLYTOPE"}
	for iteration in range(max_epa_iterations):
		faces.sort_custom(func(x:Dictionary,y:Dictionary)->bool:
			if absf(float(x["distance"])-float(y["distance"])) > EPS:return float(x["distance"]) < float(y["distance"])
			return _face_key(x) < _face_key(y)
		)
		var closest:Dictionary = faces[0]
		var normal:Vector3 = closest["normal"]
		var support := Model.minkowski_support(a,b,normal)
		var support_distance := Vector3(support["p"]).dot(normal)
		if support_distance - float(closest["distance"]) <= EPA_TOL or _has_support(vertices,support):
			var witness := _face_witness(vertices,closest)
			return {
				"ok":true,"intersect":true,"normal":normal,"depth":float(closest["distance"]),
				"point_a":witness["point_a"],"point_b":witness["point_b"],
				"gjk_iterations":int(gjk["iterations"]),"epa_iterations":iteration+1,
				"simplex":simplex,
			}
		var new_index := vertices.size()
		vertices.append(support)
		var visible:Array = []
		for fi in range(faces.size()):
			var f:Dictionary = faces[fi]
			var va:Vector3 = vertices[int(f["a"])]["p"]
			if Vector3(f["normal"]).dot(Vector3(support["p"])-va) > EPA_TOL:
				visible.append(fi)
		if visible.is_empty():
			var witness2 := _face_witness(vertices,closest)
			return {"ok":true,"intersect":true,"normal":normal,"depth":float(closest["distance"]),"point_a":witness2["point_a"],"point_b":witness2["point_b"],"gjk_iterations":int(gjk["iterations"]),"epa_iterations":iteration+1,"simplex":simplex}
		var horizon:Array = []
		for fi in visible:
			var f2:Dictionary = faces[int(fi)]
			for edge in [[int(f2["a"]),int(f2["b"])],[int(f2["b"]),int(f2["c"])],[int(f2["c"]),int(f2["a"])]]:
				_add_horizon_edge(horizon,int(edge[0]),int(edge[1]))
		visible.sort()
		visible.reverse()
		for fi in visible:faces.remove_at(int(fi))
		for edge in horizon:
			var nf := _make_face(vertices,int(edge[0]),int(edge[1]),new_index)
			if bool(nf["ok"]):faces.append(nf)
		if faces.is_empty():return {"ok":false,"code":"EPA_EMPTY_POLYTOPE"}
	return {"ok":false,"code":"EPA_DID_NOT_CONVERGE"}

static func _update_simplex(simplex:Array)->Dictionary:
	match simplex.size():
		2:return _line(simplex)
		3:return _triangle(simplex)
		4:return _tetrahedron(simplex)
		_:
			return {"contains":false,"simplex":[simplex[-1]],"direction":-Vector3(simplex[-1]["p"])}

static func _line(s:Array)->Dictionary:
	var a = s[-1]
	var b = s[-2]
	var av:Vector3 = a["p"]
	var bv:Vector3 = b["p"]
	var ab := bv-av
	var ao := -av
	if ab.dot(ao) > EPS:
		var d := _triple_cross(ab,ao,ab)
		if d.length_squared() <= EPS:d = _orthogonal(ab)
		return {"contains":false,"simplex":[b,a],"direction":d}
	return {"contains":false,"simplex":[a],"direction":ao}

static func _triangle(s:Array)->Dictionary:
	var a = s[-1]
	var b = s[-2]
	var c = s[-3]
	var av:Vector3 = a["p"]
	var bv:Vector3 = b["p"]
	var cv:Vector3 = c["p"]
	var ab := bv-av
	var ac := cv-av
	var ao := -av
	var abc := ab.cross(ac)
	var ac_side := abc.cross(ac)
	if ac_side.dot(ao) > EPS:
		if ac.dot(ao) > EPS:
			var d1 := _triple_cross(ac,ao,ac)
			if d1.length_squared() <= EPS:d1 = _orthogonal(ac)
			return {"contains":false,"simplex":[c,a],"direction":d1}
		return _line([b,a])
	var ab_side := ab.cross(abc)
	if ab_side.dot(ao) > EPS:
		return _line([b,a])
	if abc.dot(ao) > EPS:
		return {"contains":false,"simplex":[c,b,a],"direction":abc}
	return {"contains":false,"simplex":[b,c,a],"direction":-abc}

static func _tetrahedron(s:Array)->Dictionary:
	var a = s[-1]
	var b = s[-2]
	var c = s[-3]
	var d = s[-4]
	var av:Vector3=a["p"]
	var ao := -av
	# Explicit faces through newest point A: ABC, ACD, ADB.
	var candidates := [[a,b,c,d],[a,c,d,b],[a,d,b,c]]
	for item in candidates:
		var pa:Vector3=item[0]["p"]
		var pb:Vector3=item[1]["p"]
		var pc:Vector3=item[2]["p"]
		var opposite:Vector3=item[3]["p"]
		var n := (pb-pa).cross(pc-pa)
		if n.dot(opposite-pa) > 0.0:n = -n
		if n.dot(ao) > EPS:
			return _triangle([item[2],item[1],item[0]])
	return {"contains":true,"simplex":[d,c,b,a],"direction":Vector3.ZERO}

static func _expand_simplex(a:Dictionary,b:Dictionary,simplex:Array)->Dictionary:
	var out:Array = simplex.duplicate(true)
	var directions := [Vector3.RIGHT,Vector3.UP,Vector3.BACK,Vector3(1,1,1).normalized(),Vector3(-1,1,0.3).normalized(),Vector3(0.2,-1,1).normalized()]
	for d in directions:
		if out.size() >= 4:break
		for sign in [1.0,-1.0]:
			var p := Model.minkowski_support(a,b,d*sign)
			if not _has_support(out,p):out.append(p)
			if out.size() >= 4:break
	if out.size() < 4:return {"ok":false,"code":"GJK_DEGENERATE_SIMPLEX"}
	# Pick a non-degenerate tetrahedron deterministically.
	for i in range(out.size()-3):
		for j in range(i+1,out.size()-2):
			for k in range(j+1,out.size()-1):
				for l in range(k+1,out.size()):
					var p0:Vector3=out[i]["p"]
					var p1:Vector3=out[j]["p"]
					var p2:Vector3=out[k]["p"]
					var p3:Vector3=out[l]["p"]
					var volume := absf((p1-p0).dot((p2-p0).cross(p3-p0)))
					if volume > 1.0e-9:return {"ok":true,"simplex":[out[i],out[j],out[k],out[l]]}
	return {"ok":false,"code":"GJK_DEGENERATE_TETRAHEDRON"}

static func _make_face(vertices:Array,a:int,b:int,c:int)->Dictionary:
	var pa:Vector3=vertices[a]["p"]
	var pb:Vector3=vertices[b]["p"]
	var pc:Vector3=vertices[c]["p"]
	var n := (pb-pa).cross(pc-pa)
	var length := n.length()
	if length <= EPS:return {"ok":false}
	n /= length
	var distance := n.dot(pa)
	if distance < 0.0:
		var temporary := b
		b = c
		c = temporary
		n = -n
		distance = -distance
	return {"ok":true,"a":a,"b":b,"c":c,"normal":n,"distance":distance}

static func _face_witness(vertices:Array,face:Dictionary)->Dictionary:
	var a:Dictionary=vertices[int(face["a"])]
	var b:Dictionary=vertices[int(face["b"])]
	var c:Dictionary=vertices[int(face["c"])]
	var p:Vector3 = Vector3(face["normal"])*float(face["distance"])
	var bary := _barycentric(p,Vector3(a["p"]),Vector3(b["p"]),Vector3(c["p"]))
	var wa := Vector3(a["wa"])*bary.x + Vector3(b["wa"])*bary.y + Vector3(c["wa"])*bary.z
	var wb := Vector3(a["wb"])*bary.x + Vector3(b["wb"])*bary.y + Vector3(c["wb"])*bary.z
	return {"point_a":wa,"point_b":wb,"bary":bary}

static func _barycentric(p:Vector3,a:Vector3,b:Vector3,c:Vector3)->Vector3:
	var v0:=b-a
	var v1:=c-a
	var v2:=p-a
	var d00:=v0.dot(v0)
	var d01:=v0.dot(v1)
	var d11:=v1.dot(v1)
	var d20:=v2.dot(v0)
	var d21:=v2.dot(v1)
	var den:=d00*d11-d01*d01
	if absf(den)<=EPS:return Vector3(1,0,0)
	var v:=(d11*d20-d01*d21)/den
	var w:=(d00*d21-d01*d20)/den
	var u:=1.0-v-w
	return Vector3(u,v,w)

static func _add_horizon_edge(edges:Array,a:int,b:int)->void:
	for i in range(edges.size()):
		if int(edges[i][0])==b and int(edges[i][1])==a:
			edges.remove_at(i)
			return
	edges.append([a,b])

static func _has_support(vertices:Array,p:Dictionary)->bool:
	for v in vertices:
		if (Vector3(v["p"])-Vector3(p["p"])).length_squared() <= 1.0e-18:return true
	return false

static func _triple_cross(a:Vector3,b:Vector3,c:Vector3)->Vector3:
	return a.cross(b).cross(c)

static func _orthogonal(v:Vector3)->Vector3:
	var ref := Vector3.RIGHT
	if absf(v.normalized().dot(ref)) > 0.9:ref = Vector3.UP
	return v.cross(ref).cross(v).normalized()

static func _face_key(face:Dictionary)->String:
	var ids := [int(face["a"]),int(face["b"]),int(face["c"])]
	ids.sort()
	return "%08d:%08d:%08d" % ids
