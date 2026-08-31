class_name Fabric0GeneralConvexTrajectoryV1
extends RefCounted

const F = preload("res://scripts/research/fabric0/fabric0_general_convex_multipoint_mcp_v1.gd")
const Events = preload("res://scripts/research/fabric0/fabric0_general_convex_event_driver_v1.gd")
const Parallel = preload("res://scripts/research/fabric0/fabric0_general_convex_parallel_islands_v1.gd")
const Collision = preload("res://scripts/research/fabric0/fabric0_gjk_epa_v1.gd")

const SOURCE_TIME := 0.7
const FINAL_TIME := 1.0
const EVENT_HORIZON := 0.8
const SPLIT_HORIZON := 0.2

static func run(tolerance:float=1.0e-8, reverse_initial_spawn:bool=false, reverse_final_spawn:bool=false) -> Dictionary:
	if tolerance <= 0.0:
		return {"ok":false,"code":"BAD_TOLERANCE"}
	var world := _initial_world()
	var bodies:Array = world["bodies"]
	var manifolds:Dictionary = world["manifolds"]
	var contacts:Array = _contacts_from_manifolds(bodies, manifolds)
	var options := _solver_options()
	var events:Array = []
	var topology:Array = []
	var current_time := 0.0

	var initial_energy := F.total_kinetic_energy(bodies)
	var initial_linear := F.total_linear_momentum(bodies)
	var initial_angular := F.total_angular_momentum_origin(bodies)

	var initial_partition := Parallel.partition(bodies, contacts)
	if not bool(initial_partition.get("ok",false)):
		return initial_partition
	var initial_solve := Parallel.solve_same_world(bodies, contacts, 0.01, options, reverse_initial_spawn)
	if not bool(initial_solve.get("ok",false)):
		return {"ok":false,"code":"INITIAL_ISLAND_SOLVE_FAILED","detail":initial_solve}
	topology.append(_topology_snapshot("INITIAL", current_time, initial_partition, initial_solve))

	var appear := Events.transition_event(bodies[1], bodies[2], 0.0, EVENT_HORIZON, true, tolerance, 192)
	if not bool(appear.get("ok",false)):
		return {"ok":false,"code":"BRIDGE_APPEAR_LOCALIZATION_FAILED","detail":appear}
	var bridge_normal_result := _transition_normal(bodies[1], bodies[2], maxf(0.0, float(appear["time"])-float(appear["bracket_width"])))
	if not bool(bridge_normal_result.get("ok",false)):
		return bridge_normal_result
	var bridge_normal:Vector3=bridge_normal_result["normal"]
	var appear_sample := float(appear["time"]) + 0.5 * float(appear["bracket_width"])
	appear_sample = minf(appear_sample, EVENT_HORIZON)
	_advance_in_place(bodies, appear_sample)
	current_time += appear_sample
	var rebuilt := _rebuild_manifolds(bodies, manifolds, [[0,1],[2,3]])
	if not bool(rebuilt.get("ok",false)):
		return rebuilt
	manifolds = rebuilt["manifolds"]
	var bridge_materialized := _materialize_manifold(bodies[1], bodies[2], bridge_normal, {})
	if not bool(bridge_materialized.get("ok",false)):
		return {"ok":false,"code":"BRIDGE_MANIFOLD_FAILED","detail":bridge_materialized}
	var bridge_collision:Dictionary=bridge_materialized["collision"]
	var bridge_manifold:Dictionary=bridge_materialized["manifold"]
	manifolds["B|C"] = bridge_manifold
	contacts = _contacts_from_manifolds(bodies, manifolds)
	var merged_partition := Parallel.partition(bodies, contacts)
	if not bool(merged_partition.get("ok",false)):
		return merged_partition
	var merged_rows:=contacts.size()
	var pre_merge_energy := F.total_kinetic_energy(bodies)
	var merge_solve := Parallel.solve_same_world(bodies, contacts, 0.01, options, false)
	if not bool(merge_solve.get("ok",false)):
		return {"ok":false,"code":"MERGED_ISLAND_SOLVE_FAILED","detail":merge_solve}
	var post_merge_energy := F.total_kinetic_energy(bodies)
	var contact_dissipation := pre_merge_energy - post_merge_energy
	events.append({
		"kind":"CONTACT_APPEAR",
		"pair":"B|C",
		"boundary_time":float(appear["time"]),
		"realized_time":current_time,
		"bracket_width":float(appear["bracket_width"]),
		"manifold_points":bridge_manifold["points"].size(),
		"boundary_fallback":bool(bridge_materialized.get("boundary_fallback",false)),
		"feature_key":String(bridge_manifold["feature_key"]),
		"islands_before":initial_partition["islands"].size(),
		"islands_after":merged_partition["islands"].size(),
	})
	topology.append(_topology_snapshot("MERGED", current_time, merged_partition, merge_solve))

	if current_time >= SOURCE_TIME:
		return {"ok":false,"code":"SOURCE_TIME_REACHED_BEFORE_MERGE","time":current_time}
	_advance_in_place(bodies, SOURCE_TIME - current_time)
	current_time = SOURCE_TIME
	var source_rebuild := _rebuild_manifolds(bodies, manifolds, [[0,1],[1,2],[2,3]])
	if not bool(source_rebuild.get("ok",false)):
		return source_rebuild
	manifolds = source_rebuild["manifolds"]
	var bridge_lifetime_at_source:=0
	for bridge_point in manifolds["B|C"]["points"]:
		bridge_lifetime_at_source=maxi(bridge_lifetime_at_source,int(bridge_point["lifetime"]))
	var energy_before_source := F.total_kinetic_energy(bodies)
	_apply_symmetric_release(bodies)
	var energy_after_source := F.total_kinetic_energy(bodies)
	var source_work := energy_after_source - energy_before_source
	events.append({"kind":"SOURCE_RELEASE","time":current_time,"work":source_work,"bridge_lifetime":bridge_lifetime_at_source})

	var split_normal:Vector3=manifolds["B|C"]["normal"]
	var disappear := _localize_existing_manifold_separation(bodies[1], bodies[2], split_normal, SPLIT_HORIZON, tolerance, 192)
	if not bool(disappear.get("ok",false)):
		return {"ok":false,"code":"BRIDGE_DISAPPEAR_LOCALIZATION_FAILED","detail":disappear}
	var split_sample := float(disappear["time"]) + 0.5 * float(disappear["bracket_width"])
	split_sample = minf(split_sample, SPLIT_HORIZON)
	_advance_in_place(bodies, split_sample)
	current_time += split_sample
	var split_gap:=_support_gap(bodies[1],bodies[2],split_normal)
	if split_gap < -maxf(1.0e-12,tolerance*2.0):
		return {"ok":false,"code":"BRIDGE_SAMPLE_STILL_INTERSECTING","gap":split_gap,"time":current_time}
	manifolds.erase("B|C")
	var split_rebuild := _rebuild_manifolds(bodies, manifolds, [[0,1],[2,3]])
	if not bool(split_rebuild.get("ok",false)):
		return split_rebuild
	manifolds = split_rebuild["manifolds"]
	contacts = _contacts_from_manifolds(bodies, manifolds)
	var split_partition := Parallel.partition(bodies, contacts)
	if not bool(split_partition.get("ok",false)):
		return split_partition
	var split_rows:=contacts.size()
	var split_solve := Parallel.solve_same_world(bodies, contacts, 0.01, options, reverse_final_spawn)
	if not bool(split_solve.get("ok",false)):
		return {"ok":false,"code":"SPLIT_ISLAND_SOLVE_FAILED","detail":split_solve}
	events.append({
		"kind":"CONTACT_DISAPPEAR",
		"pair":"B|C",
		"boundary_time":SOURCE_TIME + float(disappear["time"]),
		"realized_time":current_time,
		"bracket_width":float(disappear["bracket_width"]),
		"islands_before":merged_partition["islands"].size(),
		"islands_after":split_partition["islands"].size(),
	})
	topology.append(_topology_snapshot("SPLIT", current_time, split_partition, split_solve))

	if current_time > FINAL_TIME:
		return {"ok":false,"code":"FINAL_TIME_OVERRUN","time":current_time}
	_advance_in_place(bodies, FINAL_TIME-current_time)
	current_time = FINAL_TIME

	var final_energy := F.total_kinetic_energy(bodies)
	var final_linear := F.total_linear_momentum(bodies)
	var final_angular := F.total_angular_momentum_origin(bodies)
	var energy_residual := final_energy - initial_energy - source_work + contact_dissipation
	var state := _state_vector(bodies)
	return {
		"ok":true,
		"time":current_time,
		"bodies":bodies,
		"events":events,
		"topology":topology,
		"manifolds":manifolds,
		"state":state,
		"signature":JSON.stringify({"events":events,"state":state},"",false),
		"initial_energy":initial_energy,
		"final_energy":final_energy,
		"source_work":source_work,
		"contact_dissipation":contact_dissipation,
		"energy_residual":energy_residual,
		"linear_momentum_error":(final_linear-initial_linear).length(),
		"angular_momentum_error":(final_angular-initial_angular).length(),
		"initial_threads":int(initial_solve["threads_started"]),
		"merged_threads":int(merge_solve["threads_started"]),
		"split_threads":int(split_solve["threads_started"]),
		"merged_rows":merged_rows,
		"split_rows":split_rows,
		"merged_complementarity":float(merge_solve["results"][0]["solve_metrics"]["comp"]),
		"merged_cone_violation":float(merge_solve["results"][0]["solve_metrics"]["cone"]),
		"bridge_lifetime_at_source":bridge_lifetime_at_source,
	}

static func _localize_existing_manifold_separation(a:Dictionary,b:Dictionary,normal:Vector3,horizon:float,tolerance:float,max_iterations:int) -> Dictionary:
	if horizon<=0.0:return {"ok":false,"code":"BAD_INTERVAL"}
	if tolerance<=0.0:return {"ok":false,"code":"BAD_TOLERANCE"}
	var g0:=_support_gap(a,b,normal)
	var g1:=_support_gap(Events.body_at(a,horizon),Events.body_at(b,horizon),normal)
	if g0>maxf(tolerance,1.0e-10):return {"ok":false,"code":"MANIFOLD_ALREADY_SEPARATED","gap0":g0}
	if g1<=0.0:return {"ok":false,"code":"NO_BRACKETED_SEPARATION","gap0":g0,"gap1":g1}
	var lo:=0.0
	var hi:=horizon
	var iterations:=0
	while hi-lo>tolerance and iterations<max_iterations:
		iterations+=1
		var mid:=0.5*(lo+hi)
		var gap:=_support_gap(Events.body_at(a,mid),Events.body_at(b,mid),normal)
		if gap<=0.0:lo=mid
		else:hi=mid
	if hi-lo>tolerance:return {"ok":false,"code":"SEPARATION_EVENT_DID_NOT_CONVERGE","iterations":iterations}
	return {
		"ok":true,"kind":"CONTACT_DISAPPEAR","time":0.5*(lo+hi),"bracket_width":hi-lo,
		"lo_gap":_support_gap(Events.body_at(a,lo),Events.body_at(b,lo),normal),
		"hi_gap":_support_gap(Events.body_at(a,hi),Events.body_at(b,hi),normal),
		"iterations":iterations,
	}

static func _transition_normal(a:Dictionary,b:Dictionary,time:float) -> Dictionary:
	var aa:=Events.body_at(a,time)
	var bb:=Events.body_at(b,time)
	var gjk:=Collision.intersect(aa,bb)
	var normal:=Vector3.ZERO
	if bool(gjk.get("ok",false)) and not bool(gjk.get("intersect",false)):
		normal=Vector3(gjk.get("separating_direction",Vector3.ZERO))
	if normal.length_squared()<=1.0e-18:
		normal=Vector3(bb["p"])-Vector3(aa["p"])
	if normal.length_squared()<=1.0e-18:
		return {"ok":false,"code":"BOUNDARY_NORMAL_UNAVAILABLE"}
	normal=normal.normalized()
	if normal.dot(Vector3(bb["p"])-Vector3(aa["p"]))<0.0:normal=-normal
	return {"ok":true,"normal":normal}

static func _materialize_manifold(a:Dictionary,b:Dictionary,normal_hint:Vector3,old_manifold:Dictionary) -> Dictionary:
	var collision:=F.collide(a,b)
	if bool(collision.get("ok",false)) and bool(collision.get("intersect",false)):
		var manifold:=F.build_manifold(a,b,collision,old_manifold)
		if bool(manifold.get("ok",false)):
			return {"ok":true,"collision":collision,"manifold":manifold,"boundary_fallback":false}
	var n:=normal_hint.normalized()
	if n.length_squared()<=1.0e-18:
		return {"ok":false,"code":"BOUNDARY_MANIFOLD_NORMAL_UNAVAILABLE","collision":collision}
	if n.dot(Vector3(b["p"])-Vector3(a["p"]))<0.0:n=-n
	var pa:Vector3=F.support(a,n)["point"]
	var pb:Vector3=F.support(b,-n)["point"]
	var gap:=(pb-pa).dot(n)
	if gap > 5.0e-6:
		return {"ok":false,"code":"BOUNDARY_MANIFOLD_GAP_TOO_LARGE","gap":gap,"collision":collision}
	var synthetic:Dictionary={
		"ok":true,"intersect":true,"normal":n,"depth":maxf(0.0,-gap),
		"point_a":pa,"point_b":pb,"gjk_iterations":int(collision.get("gjk_iterations",0)),"epa_iterations":0,
	}
	var manifold2:=F.build_manifold(a,b,synthetic,old_manifold)
	if not bool(manifold2.get("ok",false)):
		return {"ok":false,"code":"BOUNDARY_MANIFOLD_BUILD_FAILED","detail":manifold2,"gap":gap}
	return {"ok":true,"collision":synthetic,"manifold":manifold2,"boundary_fallback":true,"gap":gap}

static func _support_gap(a:Dictionary,b:Dictionary,n:Vector3) -> float:
	var normal:=n.normalized()
	if normal.dot(Vector3(b["p"])-Vector3(a["p"]))<0.0:normal=-normal
	var pa:Vector3=F.support(a,normal)["point"]
	var pb:Vector3=F.support(b,-normal)["point"]
	return (pb-pa).dot(normal)

static func _initial_world() -> Dictionary:
	var shape := F.box_shape("trajectory_box",Vector3(0.5,0.5,0.5))
	var bodies:Array = [
		F.new_body("A",shape,Vector3(-2.0,0,0),Quaternion.IDENTITY,1.0,Vector3(0.2,0.2,0.2),Vector3(1,0,0)),
		F.new_body("B",shape,Vector3(-1.01,0,0),Quaternion.IDENTITY,1.0,Vector3(0.2,0.2,0.2),Vector3(1,0,0)),
		F.new_body("C",shape,Vector3(1.01,0,0),Quaternion.IDENTITY,1.0,Vector3(0.2,0.2,0.2),Vector3(-1,0,0)),
		F.new_body("D",shape,Vector3(2.0,0,0),Quaternion.IDENTITY,1.0,Vector3(0.2,0.2,0.2),Vector3(-1,0,0)),
	]
	var manifolds:Dictionary = {}
	for pair in [[0,1],[2,3]]:
		var a:=int(pair[0]);var b:=int(pair[1])
		var collision:=F.collide(bodies[a],bodies[b])
		assert(bool(collision.get("ok",false)) and bool(collision.get("intersect",false)))
		var manifold:=F.build_manifold(bodies[a],bodies[b],collision)
		assert(bool(manifold.get("ok",false)))
		manifolds[_pair_key(bodies[a],bodies[b])] = manifold
	return {"bodies":bodies,"manifolds":manifolds}

static func _advance_in_place(bodies:Array,dt:float) -> void:
	if dt<=0.0:return
	for i in range(bodies.size()):
		bodies[i]=Events.body_at(bodies[i],dt)

static func _apply_symmetric_release(bodies:Array) -> void:
	bodies[0]["v"]=Vector3(-1,0,0)
	bodies[1]["v"]=Vector3(-1,0,0)
	bodies[2]["v"]=Vector3(1,0,0)
	bodies[3]["v"]=Vector3(1,0,0)
	for body in bodies:body["w"]=Vector3.ZERO

static func _rebuild_manifolds(bodies:Array,old:Dictionary,pairs:Array) -> Dictionary:
	var rebuilt:Dictionary={}
	for pair in pairs:
		var a:=int(pair[0]);var b:=int(pair[1])
		var key:=_pair_key(bodies[a],bodies[b])
		var old_manifold:Dictionary=old.get(key,{})
		var hint:=Vector3(old_manifold.get("normal",Vector3(bodies[b]["p"])-Vector3(bodies[a]["p"])))
		var materialized:=_materialize_manifold(bodies[a],bodies[b],hint,old_manifold)
		if not bool(materialized.get("ok",false)):
			return {"ok":false,"code":"PERSISTENT_MANIFOLD_REBUILD_FAILED","pair":key,"detail":materialized}
		rebuilt[key]=materialized["manifold"]
	return {"ok":true,"manifolds":rebuilt}

static func _contacts_from_manifolds(bodies:Array,manifolds:Dictionary) -> Array:
	var index_by_id:Dictionary={}
	for i in range(bodies.size()):index_by_id[String(bodies[i]["id"])]=i
	var contacts:Array=[]
	var keys:=manifolds.keys();keys.sort()
	for key_any in keys:
		var key:=String(key_any)
		var pair:=key.split("|")
		var a:=int(index_by_id[String(pair[0])])
		var b:=int(index_by_id[String(pair[1])])
		var manifold:Dictionary=manifolds[key]
		for point_any in manifold["points"]:
			var contact:Dictionary=point_any.duplicate(true)
			contact["a"]=a
			contact["b"]=b
			contact["mu"]=0.0
			contact["gap"]=0.0
			contacts.append(contact)
	return contacts

static func _solver_options() -> Dictionary:
	return {
		"beta":0.0,
		"normal_tolerance":1.0e-9,
		"normal_iterations":512,
		"tangent_iterations":0,
		"coupling_iterations":8,
		"coupling_tolerance":1.0e-10,
		"normal_regularization":1.0e-9,
		"max_threads":8,
	}

static func _topology_snapshot(label:String,time:float,partition:Dictionary,solve:Dictionary) -> Dictionary:
	var islands:Array=[]
	for island in partition["islands"]:islands.append(island["body_ids"].duplicate())
	return {"label":label,"time":time,"islands":islands,"threads":int(solve.get("threads_started",0))}

static func _state_vector(bodies:Array) -> Array:
	var out:Array=[]
	for body in bodies:
		var p:Vector3=body["p"];var q:Quaternion=body["q"];var v:Vector3=body["v"];var w:Vector3=body["w"]
		out.append([String(body["id"]),p.x,p.y,p.z,q.x,q.y,q.z,q.w,v.x,v.y,v.z,w.x,w.y,w.z])
	return out

static func state_error(a:Dictionary,b:Dictionary) -> float:
	var sa:Array=a["state"];var sb:Array=b["state"]
	if sa.size()!=sb.size():return INF
	var maximum:=0.0
	for i in range(sa.size()):
		if String(sa[i][0])!=String(sb[i][0]):return INF
		for j in range(1,sa[i].size()):maximum=maxf(maximum,absf(float(sa[i][j])-float(sb[i][j])))
	return maximum

static func event_time_error(a:Dictionary,b:Dictionary) -> float:
	if a["events"].size()!=b["events"].size():return INF
	var maximum:=0.0
	for i in range(a["events"].size()):
		var ea:Dictionary=a["events"][i];var eb:Dictionary=b["events"][i]
		if String(ea["kind"])!=String(eb["kind"]):return INF
		var ta:=float(ea.get("boundary_time",ea.get("time",0.0)))
		var tb:=float(eb.get("boundary_time",eb.get("time",0.0)))
		maximum=maxf(maximum,absf(ta-tb))
	return maximum

static func _pair_key(a:Dictionary,b:Dictionary) -> String:
	var x:=String(a["id"]);var y:=String(b["id"])
	return x+"|"+y if x<y else y+"|"+x
