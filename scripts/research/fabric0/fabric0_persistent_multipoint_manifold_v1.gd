class_name Fabric0PersistentMultipointManifoldV1
extends RefCounted

const Model = preload("res://scripts/research/fabric0/fabric0_general_convex_model_v1.gd")
const EPS := 1.0e-9

static func build(a:Dictionary,b:Dictionary,epa:Dictionary,old_manifold:Dictionary={},max_points:int=4)->Dictionary:
	if not bool(epa.get("ok",false)) or not bool(epa.get("intersect",false)):
		return {"ok":false,"code":"NO_PENETRATION_FOR_MANIFOLD"}
	var n := Vector3(epa["normal"]).normalized()
	var center_delta := Vector3(b["p"])-Vector3(a["p"])
	if n.dot(center_delta) < 0.0:n = -n
	var fa := Model.best_face(a,n)
	var fb := Model.best_face(b,-n)
	var align_a := float(fa["dot"])
	var align_b := float(fb["dot"])
	var reference_is_a := align_a >= align_b - 1.0e-12
	var ref_body:Dictionary = a if reference_is_a else b
	var inc_body:Dictionary = b if reference_is_a else a
	var ref := fa if reference_is_a else fb
	var inc := fb if reference_is_a else fa
	var ref_normal := n if reference_is_a else -n
	var ref_vertices:Array = ref["vertices"]
	var polygon:Array = inc["vertices"].duplicate()
	for i in range(ref_vertices.size()):
		var p0:Vector3 = ref_vertices[i]
		var p1:Vector3 = ref_vertices[(i+1)%ref_vertices.size()]
		var edge := p1-p0
		var side_normal := edge.cross(ref_normal).normalized()
		polygon = _clip_polygon(polygon,p0,side_normal)
		if polygon.is_empty():break
	var feature_key := "%s|ra:%s:%d|ib:%s:%d" % [pair_id(a,b),String(ref_body["id"]),int(ref["index"]),String(inc_body["id"]),int(inc["index"])]
	var candidates:Array = []
	if not polygon.is_empty():
		var plane_point:Vector3 = ref_vertices[0]
		for p_any in polygon:
			var p:Vector3 = p_any
			var separation := ref_normal.dot(p-plane_point)
			if separation > 5.0e-6:continue
			var on_ref := p-ref_normal*separation
			var pa:Vector3
			var pb:Vector3
			if reference_is_a:
				pa=on_ref
				pb=p
			else:
				pa=p
				pb=on_ref
			var cp := 0.5*(pa+pb)
			candidates.append({
				"point":cp,"point_a":pa,"point_b":pb,"depth":maxf(0.0,-separation),
				"normal":n,"feature_key":feature_key,
				"local_a":Model.local_vertex(a,pa),"local_b":Model.local_vertex(b,pb),
			})
	# Degenerate vertex/edge contact fallback keeps EPA witness observable.
	if candidates.is_empty():
		var wa:Vector3 = epa["point_a"]
		var wb:Vector3 = epa["point_b"]
		var cp2:=0.5*(wa+wb)
		candidates.append({"point":cp2,"point_a":wa,"point_b":wb,"depth":float(epa["depth"]),"normal":n,"feature_key":feature_key,"local_a":Model.local_vertex(a,wa),"local_b":Model.local_vertex(b,wb)})
	_deduplicate(candidates)
	_reduce(candidates,n,max_points)
	_assign_persistent_ids(candidates,old_manifold,feature_key)
	for c in candidates:
		c["ra"] = Vector3(c["point"])-Vector3(a["p"])
		c["rb"] = Vector3(c["point"])-Vector3(b["p"])
		c["gap"] = -float(c["depth"])
	return {"ok":true,"pair_id":pair_id(a,b),"normal":n,"reference_is_a":reference_is_a,"reference_face":int(ref["index"]),"incident_face":int(inc["index"]),"feature_key":feature_key,"points":candidates}

static func pair_id(a:Dictionary,b:Dictionary)->String:
	var x:=String(a["id"])
	var y:=String(b["id"])
	return x+"|"+y if x<y else y+"|"+x

static func _clip_polygon(poly:Array,plane_point:Vector3,outward:Vector3)->Array:
	var out:Array=[]
	if poly.is_empty():return out
	for i in range(poly.size()):
		var current:Vector3=poly[i]
		var previous:Vector3=poly[(i+poly.size()-1)%poly.size()]
		var dc:=outward.dot(current-plane_point)
		var dp:=outward.dot(previous-plane_point)
		var current_inside:=dc<=EPS
		var previous_inside:=dp<=EPS
		if current_inside != previous_inside:
			var denom:=dp-dc
			if absf(denom)>1.0e-15:
				var t:=dp/denom
				out.append(previous+(current-previous)*clampf(t,0.0,1.0))
		if current_inside:out.append(current)
	return out

static func _deduplicate(points:Array)->void:
	var i:=0
	while i<points.size():
		var j:=i+1
		while j<points.size():
			if (Vector3(points[i]["point"])-Vector3(points[j]["point"])).length_squared()<1.0e-14:
				if float(points[j]["depth"])>float(points[i]["depth"]):points[i]=points[j]
				points.remove_at(j)
			else:j+=1
		i+=1

static func _reduce(points:Array,n:Vector3,max_points:int)->void:
	if points.size()<=max_points:
		_sort_points(points,n)
		return
	var basis:=Model.tangent_basis(n)
	var t1:Vector3=basis[0]
	var t2:Vector3=basis[1]
	var selected:Array=[]
	var extrema := [
		_find_extreme(points,t1,true),_find_extreme(points,t1,false),
		_find_extreme(points,t2,true),_find_extreme(points,t2,false),
	]
	for idx in extrema:
		if not selected.has(int(idx)):selected.append(int(idx))
	while selected.size()<max_points:
		var best:=-1
		var best_score:=-INF
		for i in range(points.size()):
			if selected.has(i):continue
			var score:=0.0
			for s in selected:score+=Vector3(points[i]["point"]).distance_squared_to(Vector3(points[int(s)]["point"]))
			if score>best_score:
				best_score=score
				best=i
		if best<0:break
		selected.append(best)
	var kept:Array=[]
	for idx in selected.slice(0,max_points):kept.append(points[int(idx)])
	points.clear()
	points.append_array(kept)
	_sort_points(points,n)

static func _find_extreme(points:Array,dir:Vector3,maximum:bool)->int:
	var best:=0
	var score:=Vector3(points[0]["point"]).dot(dir)
	for i in range(1,points.size()):
		var s:=Vector3(points[i]["point"]).dot(dir)
		if (maximum and s>score) or ((not maximum) and s<score):
			score=s
			best=i
	return best

static func _sort_points(points:Array,n:Vector3)->void:
	var basis:=Model.tangent_basis(n)
	var t1:Vector3=basis[0]
	var t2:Vector3=basis[1]
	points.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
		var ax:=Vector3(a["point"]).dot(t1)
		var bx:=Vector3(b["point"]).dot(t1)
		if absf(ax-bx)>1.0e-10:return ax<bx
		var ay:=Vector3(a["point"]).dot(t2)
		var by:=Vector3(b["point"]).dot(t2)
		return ay<by
	)

static func _assign_persistent_ids(points:Array,old_manifold:Dictionary,feature_key:String)->void:
	var old_points:Array = old_manifold.get("points",[])
	var used:Dictionary={}
	var next_slot:=0
	for op in old_points:
		var id:=String(op.get("id",""))
		if id.begins_with(feature_key+"|p"):
			var suffix:=id.get_slice("|p",1)
			if suffix.is_valid_int():next_slot=maxi(next_slot,int(suffix)+1)
	for p in points:
		var best:=-1
		var best_d:=0.0025 # 5 cm squared threshold
		for i in range(old_points.size()):
			if used.has(i):continue
			var op:Dictionary=old_points[i]
			if String(op.get("feature_key",""))!=feature_key:continue
			var d:=(Vector3(op["local_a"])-Vector3(p["local_a"])).length_squared()+(Vector3(op["local_b"])-Vector3(p["local_b"])).length_squared()
			if d<best_d:
				best_d=d
				best=i
		if best>=0:
			var old:Dictionary=old_points[best]
			used[best]=true
			p["id"]=String(old["id"])
			p["lifetime"]=int(old.get("lifetime",1))+1
		else:
			p["id"]="%s|p%d" % [feature_key,next_slot]
			next_slot+=1
			p["lifetime"]=1
