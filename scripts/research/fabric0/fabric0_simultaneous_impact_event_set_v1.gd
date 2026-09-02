class_name Fabric0SimultaneousImpactEventSetV1
extends RefCounted

const Events = preload("res://scripts/research/fabric0/fabric0_general_convex_event_driver_v1.gd")
const F = preload("res://scripts/research/fabric0/fabric0_general_convex_multipoint_mcp_v1.gd")

const DEFAULT_MAX_PAIRS := 4096

static func next_appearance_event_set(
	bodies:Array,
	t0:float,
	t1:float,
	root_tolerance:float=1.0e-9,
	simultaneous_resolution:float=1.0e-9,
	max_iterations:int=128,
	max_pairs:int=DEFAULT_MAX_PAIRS,
	min_approach_speed:float=1.0e-10
) -> Dictionary:
	var valid := _validate_input(bodies,t0,t1,root_tolerance,simultaneous_resolution,max_iterations,max_pairs,min_approach_speed)
	if not bool(valid.get("ok",false)):
		return valid
	var collected := _collect_appearance_events(bodies,t0,t1,root_tolerance,max_iterations,max_pairs,min_approach_speed)
	if not bool(collected.get("ok",false)):
		return collected
	var events:Array=collected["events"]
	if events.is_empty():
		return {
			"ok":false,
			"code":"NO_IMPACT_EVENT",
			"pair_count":int(collected["pair_count"]),
			"swept_candidates":int(collected["swept_candidates"]),
			"non_impact_appearances":int(collected["non_impact_appearances"]),
		}
	var anchor:Dictionary=events[0]
	var members:Array=[]
	var deferred:Array=[]
	for event_any in events:
		var event:Dictionary=event_any
		if _interval_distance(anchor,event) <= simultaneous_resolution:
			members.append(event)
		else:
			deferred.append(event)
	var pair_ids:Array=[]
	var common_lo:float=-INF
	var common_hi:float=INF
	var union_lo:float=INF
	var union_hi:float=-INF
	var min_time:float=INF
	var max_time:float=-INF
	var total_fallbacks:=0
	for member_any in members:
		var member:Dictionary=member_any
		pair_ids.append(String(member["id"]))
		common_lo=maxf(common_lo,float(member["lo_time"]))
		common_hi=minf(common_hi,float(member["hi_time"]))
		union_lo=minf(union_lo,float(member["lo_time"]))
		union_hi=maxf(union_hi,float(member["hi_time"]))
		min_time=minf(min_time,float(member["time"]))
		max_time=maxf(max_time,float(member["time"]))
		total_fallbacks+=int(member.get("boundary_fallbacks",0))
	pair_ids.sort()
	var interval_overlap:=common_lo<=common_hi
	return {
		"ok":true,
		"kind":"SIMULTANEOUS_IMPACT_EVENT_SET",
		"time":float(anchor["time"]),
		"anchor_id":String(anchor["id"]),
		"pair_ids":pair_ids,
		"members":members,
		"deferred_events":deferred,
		"member_count":members.size(),
		"deferred_count":deferred.size(),
		"pair_count":int(collected["pair_count"]),
		"swept_candidates":int(collected["swept_candidates"]),
		"localized_events":events.size(),
		"non_impact_appearances":int(collected["non_impact_appearances"]),
		"root_tolerance":root_tolerance,
		"simultaneous_resolution":simultaneous_resolution,
		"interval_overlap":interval_overlap,
		"classification":"INTERVAL_COINCIDENT" if interval_overlap else "RESOLUTION_EQUIVALENT",
		"common_lo":common_lo,
		"common_hi":common_hi,
		"union_lo":union_lo,
		"union_hi":union_hi,
		"temporal_spread":max_time-min_time,
		"uncertainty_span":union_hi-union_lo,
		"boundary_fallbacks":total_fallbacks,
		"signature":_signature(pair_ids),
	}

static func _validate_input(
	bodies:Array,
	t0:float,
	t1:float,
	root_tolerance:float,
	simultaneous_resolution:float,
	max_iterations:int,
	max_pairs:int,
	min_approach_speed:float
) -> Dictionary:
	if bodies.size()<2:
		return {"ok":false,"code":"TOO_FEW_BODIES"}
	if t1<=t0:
		return {"ok":false,"code":"BAD_INTERVAL"}
	if root_tolerance<=0.0:
		return {"ok":false,"code":"BAD_ROOT_TOLERANCE"}
	if simultaneous_resolution<0.0:
		return {"ok":false,"code":"BAD_SIMULTANEOUS_RESOLUTION"}
	if max_iterations<=0:
		return {"ok":false,"code":"BAD_ITERATION_BUDGET"}
	if max_pairs<=0:
		return {"ok":false,"code":"BAD_PAIR_BUDGET"}
	if min_approach_speed<0.0:
		return {"ok":false,"code":"BAD_APPROACH_SPEED_THRESHOLD"}
	var expected_pairs:=bodies.size()*(bodies.size()-1)/2
	if expected_pairs>max_pairs:
		return {"ok":false,"code":"PAIR_BUDGET_EXCEEDED","pair_count":expected_pairs,"max_pairs":max_pairs}
	var ids:Dictionary={}
	for i in range(bodies.size()):
		var body:Dictionary=bodies[i]
		var id:=String(body.get("id",""))
		if id.is_empty():
			return {"ok":false,"code":"EMPTY_BODY_ID","body_index":i}
		if ids.has(id):
			return {"ok":false,"code":"DUPLICATE_BODY_ID","body_id":id}
		ids[id]=true
	return {"ok":true,"pair_count":expected_pairs}

static func _collect_appearance_events(
	bodies:Array,
	t0:float,
	t1:float,
	root_tolerance:float,
	max_iterations:int,
	max_pairs:int,
	min_approach_speed:float
) -> Dictionary:
	var events:Array=[]
	var swept_candidates:=0
	var non_impact_appearances:=0
	var pair_count:=0
	for i in range(bodies.size()):
		for j in range(i+1,bodies.size()):
			pair_count+=1
			if pair_count>max_pairs:
				return {"ok":false,"code":"PAIR_BUDGET_EXCEEDED","pair_count":pair_count,"max_pairs":max_pairs}
			var a:Dictionary=bodies[i]
			var b:Dictionary=bodies[j]
			if not Events.swept_candidate(a,b,t0,t1):
				continue
			swept_candidates+=1
			var localized:=Events.transition_event(a,b,t0,t1,true,root_tolerance,max_iterations)
			if not bool(localized.get("ok",false)):
				var code:=String(localized.get("code",""))
				if code=="NO_BRACKETED_TRANSITION":
					continue
				return {
					"ok":false,
					"code":"PAIR_EVENT_LOCALIZATION_FAILED",
					"pair_id":_pair_id(a,b),
					"detail":localized,
				}
			var impact:=_impact_kinematics(a,b,localized)
			if not bool(impact.get("ok",false)):
				return {"ok":false,"code":"IMPACT_KINEMATICS_FAILED","pair_id":_pair_id(a,b),"detail":impact}
			if float(impact["approach_speed"])<=min_approach_speed:
				non_impact_appearances+=1
				continue
			var width:=float(localized["bracket_width"])
			var time:=float(localized["time"])
			events.append({
				"id":String(localized["id"]),
				"a_id":String(a["id"]),
				"b_id":String(b["id"]),
				"time":time,
				"bracket_width":width,
				"lo_time":time-0.5*width,
				"hi_time":time+0.5*width,
				"iterations":int(localized["iterations"]),
				"boundary_fallbacks":int(localized.get("boundary_fallbacks",0)),
				"lo_measure":float(localized.get("lo_measure",0.0)),
				"hi_measure":float(localized.get("hi_measure",0.0)),
				"normal":impact["normal"],
				"approach_speed":float(impact["approach_speed"]),
			})
	events.sort_custom(func(x:Dictionary,y:Dictionary)->bool:
		if absf(float(x["time"])-float(y["time"]))>1.0e-15:
			return float(x["time"])<float(y["time"])
		return String(x["id"])<String(y["id"])
	)
	return {"ok":true,"events":events,"pair_count":pair_count,"swept_candidates":swept_candidates,"non_impact_appearances":non_impact_appearances}

static func _impact_kinematics(a:Dictionary,b:Dictionary,localized:Dictionary)->Dictionary:
	var inside_time:=float(localized.get("inside_time",localized["time"]))
	var inside_collision:=Events.collision_at(a,b,inside_time)
	if not bool(inside_collision.get("ok",false)) or not bool(inside_collision.get("intersect",false)):
		return {"ok":false,"code":"NO_INSIDE_COLLISION","collision":inside_collision}
	var aa:=Events.body_at(a,float(localized["time"]))
	var bb:=Events.body_at(b,float(localized["time"]))
	var normal:=Vector3(inside_collision["normal"]).normalized()
	if normal.dot(Vector3(bb["p"])-Vector3(aa["p"]))<0.0:
		normal=-normal
	var pa:Vector3=F.support(aa,normal)["point"]
	var pb:Vector3=F.support(bb,-normal)["point"]
	var point:=0.5*(pa+pb)
	var ra:=point-Vector3(aa["p"])
	var rb:=point-Vector3(bb["p"])
	var va:=Vector3(aa.get("v",Vector3.ZERO))+Vector3(aa.get("w",Vector3.ZERO)).cross(ra)
	var vb:=Vector3(bb.get("v",Vector3.ZERO))+Vector3(bb.get("w",Vector3.ZERO)).cross(rb)
	var relative:=vb-va
	return {"ok":true,"normal":normal,"approach_speed":-relative.dot(normal),"point":point}

static func _interval_distance(a:Dictionary,b:Dictionary)->float:
	var alo:=float(a["lo_time"])
	var ahi:=float(a["hi_time"])
	var blo:=float(b["lo_time"])
	var bhi:=float(b["hi_time"])
	if ahi<blo:
		return blo-ahi
	if bhi<alo:
		return alo-bhi
	return 0.0

static func _pair_id(a:Dictionary,b:Dictionary)->String:
	var x:=String(a["id"])
	var y:=String(b["id"])
	return x+"|"+y if x<y else y+"|"+x

static func _signature(pair_ids:Array)->String:
	var parts:=PackedStringArray()
	for id_any in pair_ids:
		parts.append(String(id_any))
	return "SIMULTANEOUS_IMPACT_SET["+",".join(parts)+"]"
