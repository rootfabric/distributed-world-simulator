class_name Fabric0GeneralConvexEventDriverV1
extends RefCounted

const F = preload("res://scripts/research/fabric0/fabric0_general_convex_multipoint_mcp_v1.gd")
const EPS := 1.0e-12

static func body_at(body:Dictionary,time:float)->Dictionary:
	var out:Dictionary=body.duplicate(true)
	out["p"]=Vector3(body["p"])+Vector3(body.get("v",Vector3.ZERO))*time
	var w:Vector3=body.get("w",Vector3.ZERO)
	var q:Quaternion=body.get("q",Quaternion.IDENTITY)
	var angle:=w.length()*time
	if angle>EPS:
		q=(Quaternion(w.normalized(),angle)*q).normalized()
	else:
		q=q.normalized()
	out["q"]=q
	return out

static func swept_aabb(body:Dictionary,t0:float,t1:float)->AABB:
	var radius:=_bounding_radius(body)
	var p0:=Vector3(body["p"])+Vector3(body.get("v",Vector3.ZERO))*t0
	var p1:=Vector3(body["p"])+Vector3(body.get("v",Vector3.ZERO))*t1
	var lo:=Vector3(minf(p0.x,p1.x),minf(p0.y,p1.y),minf(p0.z,p1.z))-Vector3.ONE*radius
	var hi:=Vector3(maxf(p0.x,p1.x),maxf(p0.y,p1.y),maxf(p0.z,p1.z))+Vector3.ONE*radius
	return AABB(lo,hi-lo)

static func swept_candidate(a:Dictionary,b:Dictionary,t0:float,t1:float)->bool:
	if t1<t0:return false
	var aa:=swept_aabb(a,t0,t1)
	var bb:=swept_aabb(b,t0,t1)
	return not (
		aa.end.x<bb.position.x or bb.end.x<aa.position.x or
		aa.end.y<bb.position.y or bb.end.y<aa.position.y or
		aa.end.z<bb.position.z or bb.end.z<aa.position.z
	)

static func _bounding_radius(body:Dictionary)->float:
	var radius:=0.0
	for vertex in body["shape"]["vertices"]:
		radius=maxf(radius,Vector3(vertex).length())
	return radius

static func collision_at(a:Dictionary,b:Dictionary,time:float)->Dictionary:
	return F.collide(body_at(a,time),body_at(b,time))

static func localize_contact_transition(a:Dictionary,b:Dictionary,t0:float,t1:float,target_intersecting:bool,tolerance:float=1.0e-9,max_iterations:int=96)->Dictionary:
	if t1<=t0:return {"ok":false,"code":"BAD_INTERVAL"}
	if tolerance<=0.0:return {"ok":false,"code":"BAD_TOLERANCE"}
	if max_iterations<=0:return {"ok":false,"code":"BAD_ITERATION_BUDGET"}
	var p0:=_contact_measure_at(a,b,t0,Vector3.ZERO)
	if not bool(p0.get("ok",false)):return p0
	var p1:=_contact_measure_at(a,b,t1,Vector3(p0.get("normal",Vector3.ZERO)))
	if not bool(p1.get("ok",false)):return p1
	var s0:=float(p0["measure"])<=0.0
	var s1:=float(p1["measure"])<=0.0
	if s0==s1:return {"ok":false,"code":"NO_BRACKETED_TRANSITION","state0":s0,"state1":s1,"measure0":p0["measure"],"measure1":p1["measure"]}
	if s1!=target_intersecting:return {"ok":false,"code":"WRONG_TARGET_STATE"}
	var lo:=t0
	var hi:=t1
	var lo_probe:Dictionary=p0
	var hi_probe:Dictionary=p1
	var iterations:=0
	var boundary_fallbacks:=int(p0.get("boundary_fallback",false))+int(p1.get("boundary_fallback",false))
	while hi-lo>tolerance and iterations<max_iterations:
		iterations+=1
		var mid:=0.5*(lo+hi)
		var hint:=_blend_normal(Vector3(lo_probe["normal"]),Vector3(hi_probe["normal"]))
		var probe:=_contact_measure_at(a,b,mid,hint)
		if not bool(probe.get("ok",false)):return probe
		if bool(probe.get("boundary_fallback",false)):boundary_fallbacks+=1
		var state:=float(probe["measure"])<=0.0
		if state==s0:
			lo=mid
			lo_probe=probe
		else:
			hi=mid
			hi_probe=probe
	if hi-lo>tolerance:return {"ok":false,"code":"CONTACT_EVENT_DID_NOT_CONVERGE","iterations":iterations}
	var event_time:=0.5*(lo+hi)
	var inside_time:=0.5*(event_time+t1)
	var inside_collision:=collision_at(a,b,inside_time)
	if not bool(inside_collision.get("ok",false)):
		return _collision_failure("COLLISION_AT_INSIDE_SAMPLE_FAILED",inside_collision)
	if bool(inside_collision.get("intersect",false))!=target_intersecting:
		return {"ok":false,"code":"INSIDE_SAMPLE_WRONG_STATE"}
	return {
		"ok":true,
		"time":event_time,
		"inside_time":inside_time,
		"iterations":iterations,
		"bracket_width":hi-lo,
		"before_state":s0,
		"after_state":s1,
		"target_intersecting":target_intersecting,
		"boundary_fallbacks":boundary_fallbacks,
		"lo_measure":float(lo_probe["measure"]),
		"hi_measure":float(hi_probe["measure"]),
		"inside_collision":inside_collision,
	}

static func _contact_measure_at(a:Dictionary,b:Dictionary,time:float,normal_hint:Vector3)->Dictionary:
	var aa:=body_at(a,time)
	var bb:=body_at(b,time)
	var collision:=F.collide(aa,bb)
	if bool(collision.get("ok",false)):
		if bool(collision.get("intersect",false)):
			var n:=_orient_normal(Vector3(collision["normal"]),aa,bb)
			return {"ok":true,"measure":-float(collision["depth"]),"normal":n,"collision":collision,"boundary_fallback":false}
		var gjk:Dictionary=collision.get("gjk",{})
		var separating:=Vector3(gjk.get("separating_direction",normal_hint))
		if separating.length_squared()<=EPS:
			separating=normal_hint
		if separating.length_squared()<=EPS:
			return {"ok":false,"code":"NO_SEPARATING_NORMAL"}
		var sn:=_orient_normal(separating.normalized(),aa,bb)
		var gap:=_support_gap(aa,bb,sn)
		if gap < -1.0e-9:return {"ok":false,"code":"SEPARATING_DIRECTION_GAP_INCONSISTENT","gap":gap,"collision":collision}
		return {"ok":true,"measure":gap,"normal":sn,"collision":collision,"boundary_fallback":false}
	var code:=String(collision.get("code",""))
	if not _is_zero_measure_boundary_code(code):
		return _collision_failure("COLLISION_MEASURE_FAILED",collision)
	if normal_hint.length_squared()<=EPS:
		return {"ok":false,"code":"BOUNDARY_WITHOUT_NORMAL_HINT","collision":collision}
	var n2:=_orient_normal(normal_hint.normalized(),aa,bb)
	return {"ok":true,"measure":_support_gap(aa,bb,n2),"normal":n2,"collision":collision,"boundary_fallback":true,"boundary_code":code}

static func _support_gap(a:Dictionary,b:Dictionary,n:Vector3)->float:
	var pa:Vector3=F.support(a,n)["point"]
	var pb:Vector3=F.support(b,-n)["point"]
	return (pb-pa).dot(n)

static func _orient_normal(n:Vector3,a:Dictionary,b:Dictionary)->Vector3:
	var out:=n.normalized()
	if out.dot(Vector3(b["p"])-Vector3(a["p"]))<0.0:out=-out
	return out

static func _blend_normal(a:Vector3,b:Vector3)->Vector3:
	if a.length_squared()<=EPS:return b.normalized()
	if b.length_squared()<=EPS:return a.normalized()
	var bb:=b
	if a.dot(bb)<0.0:bb=-bb
	var sum:=a+bb
	return a.normalized() if sum.length_squared()<=EPS else sum.normalized()

static func _is_zero_measure_boundary_code(code:String)->bool:
	return code in [
		"GJK_DEGENERATE_SIMPLEX",
		"GJK_DEGENERATE_TETRAHEDRON",
		"EPA_DEGENERATE_INITIAL_POLYTOPE",
	]

static func transition_event(a:Dictionary,b:Dictionary,t0:float,t1:float,target_intersecting:bool,tolerance:float=1.0e-9,max_iterations:int=96)->Dictionary:
	var localized:=localize_contact_transition(a,b,t0,t1,target_intersecting,tolerance,max_iterations)
	if not bool(localized.get("ok",false)):return localized
	return {
		"ok":true,
		"kind":"CONTACT_APPEAR" if target_intersecting else "CONTACT_DISAPPEAR",
		"id":_pair_id(a,b),
		"time":float(localized["time"]),
		"inside_time":float(localized["inside_time"]),
		"iterations":int(localized["iterations"]),
		"bracket_width":float(localized["bracket_width"]),
		"boundary_fallbacks":int(localized.get("boundary_fallbacks",0)),
		"lo_measure":float(localized.get("lo_measure",0.0)),
		"hi_measure":float(localized.get("hi_measure",0.0)),
	}

static func build_persistent_manifold_at(a:Dictionary,b:Dictionary,time:float,old_manifold:Dictionary={})->Dictionary:
	var aa:=body_at(a,time)
	var bb:=body_at(b,time)
	var collision:=F.collide(aa,bb)
	if not bool(collision.get("ok",false)):return _collision_failure("MANIFOLD_COLLISION_FAILED",collision)
	if not bool(collision.get("intersect",false)):return {"ok":false,"code":"NO_CONTACT_AT_TIME","time":time}
	var manifold:=F.build_manifold(aa,bb,collision,old_manifold)
	if not bool(manifold.get("ok",false)):return manifold
	return {"ok":true,"time":time,"collision":collision,"manifold":manifold}

static func localize_mode_transition(bodies0:Array,bodies1:Array,contacts:Array,dt:float,t0:float,t1:float,contact_id:String,target_mode:String,options:Dictionary={},tolerance:float=1.0e-9,max_iterations:int=96)->Dictionary:
	if bodies0.size()!=bodies1.size():return {"ok":false,"code":"BODY_COUNT_MISMATCH"}
	if t1<=t0:return {"ok":false,"code":"BAD_INTERVAL"}
	if dt<=0.0:return {"ok":false,"code":"BAD_STEP"}
	if tolerance<=0.0:return {"ok":false,"code":"BAD_TOLERANCE"}
	if max_iterations<=0:return {"ok":false,"code":"BAD_ITERATION_BUDGET"}
	if target_mode not in ["stick","slide"]:return {"ok":false,"code":"BAD_TARGET_MODE"}
	var s0:=_solve_mode_at(bodies0,bodies1,contacts,dt,0.0,contact_id,options)
	if not bool(s0.get("ok",false)):return s0
	var s1:=_solve_mode_at(bodies0,bodies1,contacts,dt,1.0,contact_id,options)
	if not bool(s1.get("ok",false)):return s1
	var mode0:=String(s0["mode"])
	var mode1:=String(s1["mode"])
	if mode0==mode1:return {"ok":false,"code":"NO_MODE_TRANSITION","mode0":mode0,"mode1":mode1}
	if mode1!=target_mode:return {"ok":false,"code":"WRONG_TARGET_MODE","mode1":mode1}
	var lo:=0.0
	var hi:=1.0
	var iterations:=0
	while (hi-lo)*(t1-t0)>tolerance and iterations<max_iterations:
		iterations+=1
		var mid:=0.5*(lo+hi)
		var sm:=_solve_mode_at(bodies0,bodies1,contacts,dt,mid,contact_id,options)
		if not bool(sm.get("ok",false)):return sm
		if String(sm["mode"])==mode0:lo=mid
		else:hi=mid
	if (hi-lo)*(t1-t0)>tolerance:return {"ok":false,"code":"MODE_EVENT_DID_NOT_CONVERGE","iterations":iterations}
	var alpha:=0.5*(lo+hi)
	var final_state:=_solve_mode_at(bodies0,bodies1,contacts,dt,hi,contact_id,options)
	if not bool(final_state.get("ok",false)):return final_state
	return {
		"ok":true,
		"kind":"MODE_CHANGE",
		"id":contact_id,
		"old":mode0,
		"new":target_mode,
		"time":t0+(t1-t0)*alpha,
		"iterations":iterations,
		"bracket_width":(hi-lo)*(t1-t0),
		"target_block":final_state.get("block",{}),
	}

static func _solve_mode_at(bodies0:Array,bodies1:Array,contacts:Array,dt:float,alpha:float,contact_id:String,options:Dictionary)->Dictionary:
	var bodies:Array=[]
	for i in range(bodies0.size()):
		var a:Dictionary=bodies0[i]
		var b:Dictionary=bodies1[i]
		if String(a.get("id",""))!=String(b.get("id","")):return {"ok":false,"code":"BODY_ID_MISMATCH"}
		var out:Dictionary=a.duplicate(true)
		out["v"]=Vector3(a.get("v",Vector3.ZERO)).lerp(Vector3(b.get("v",Vector3.ZERO)),alpha)
		out["w"]=Vector3(a.get("w",Vector3.ZERO)).lerp(Vector3(b.get("w",Vector3.ZERO)),alpha)
		bodies.append(out)
	var local_contacts:=contacts.duplicate(true)
	var solved:=F.solve_contacts(bodies,local_contacts,dt,options)
	if not bool(solved.get("ok",false)):return {"ok":false,"code":"MODE_SOLVE_FAILED","solve":solved}
	if not solved["blocks"].has(contact_id):return {"ok":false,"code":"CONTACT_ID_NOT_SOLVED","id":contact_id}
	var block:Dictionary=solved["blocks"][contact_id]
	return {"ok":true,"mode":String(block["mode"]),"block":block,"solve":solved}

static func _pair_id(a:Dictionary,b:Dictionary)->String:
	var x:=String(a["id"]);var y:=String(b["id"])
	return x+"|"+y if x<y else y+"|"+x

static func _collision_failure(code:String,collision:Dictionary)->Dictionary:
	return {"ok":false,"code":code,"collision":collision}
