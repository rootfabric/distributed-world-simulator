class_name Fabric0PersistentWrenchGraphExperimentsV1
extends RefCounted

const Graph=preload("res://scripts/research/fabric0/fabric0_persistent_wrench_graph_v1.gd")

static func plank(load_x:float=0.0,tangent_impulse:float=0.0,roll_impulse:float=0.0,torsion_impulse:float=0.0,reverse_contacts:bool=false,rolling_mu:float=0.08)->Dictionary:
	var mass:=10.0;var inertia:=Vector3(4.0,2.5,6.0);var normal_impulse:=1.0
	var body={"id":"PLANK","mass":mass,"inertia":inertia,"v":Vector3(tangent_impulse/mass,-normal_impulse/mass,0),"w":Vector3(roll_impulse/inertia.x,torsion_impulse/inertia.y,-load_x*normal_impulse/inertia.z)}
	var contacts:=_contacts(rolling_mu)
	if reverse_contacts:contacts.reverse()
	return Graph.solve(body,contacts,{}, {"time":0.01,"tolerance":1.0e-12,"iterations":60000,"step_scale":0.8})

static func support_curve()->Array:
	var out:Array=[]
	for x in [0.0,0.25,0.5,0.75,1.0,1.1]:
		var r:=plank(float(x),0.0,0.0,0.0,false,0.0);out.append({"x":x,"result":r})
	return out

static func mixed_mode_probe()->Dictionary:
	# Offset loading weakens the left support; combined tangent/rolling drive should saturate the weak patch first.
	var best:Dictionary={}
	for tang in [0.15,0.2,0.25,0.3,0.35,0.4,0.45,0.5,0.6]:
		for roll in [0.0,0.02,0.04,0.06,0.08,0.1,0.12,0.16]:
			var r:=plank(0.7,float(tang),float(roll),0.0)
			if not bool(r.get("ok",false)):continue
			var lm=Dictionary(Dictionary(r["per_contact"])["L"])["persistent_state"]["modes"]
			var rm=Dictionary(Dictionary(r["per_contact"])["R"])["persistent_state"]["modes"]
			if lm!=rm:
				return {"ok":true,"tangent":tang,"roll":roll,"result":r,"left_modes":lm,"right_modes":rm}
			best={"ok":false,"tangent":tang,"roll":roll,"result":r,"left_modes":lm,"right_modes":rm}
	return best

static func support_loss_continuity_probe()->Dictionary:
	var first:=_plank_with_previous(0.9,{},0.01,0.0)
	if not bool(first.get("ok",false)):return {"ok":false,"code":"FIRST_SUPPORT_SOLVE_FAILED","detail":first}
	var states:Dictionary={}
	for id in ["L","R"]:states[id]=Dictionary(Dictionary(first["per_contact"])[id])["persistent_state"]
	var second:=_plank_with_previous(1.1,states,0.02,0.0)
	if not bool(second.get("ok",false)):return {"ok":false,"code":"SECOND_SUPPORT_SOLVE_FAILED","detail":second}
	return {"ok":true,"first":first,"second":second,"left_before":states["L"],"right_before":states["R"],"left_after":Dictionary(Dictionary(second["per_contact"])["L"])["persistent_state"],"right_after":Dictionary(Dictionary(second["per_contact"])["R"])["persistent_state"]}

static func _plank_with_previous(load_x:float,previous_states:Dictionary,time:float,rolling_mu:float)->Dictionary:
	var mass:=10.0;var inertia:=Vector3(4.0,2.5,6.0);var normal_impulse:=1.0
	var body={"id":"PLANK","mass":mass,"inertia":inertia,"v":Vector3(0,-normal_impulse/mass,0),"w":Vector3(0,0,-load_x*normal_impulse/inertia.z)}
	return Graph.solve(body,_contacts(rolling_mu),previous_states,{"time":time,"tolerance":1.0e-12,"iterations":80000,"step_scale":0.8})

static func order_determinism_probe()->Dictionary:
	var forward:=plank(0.6,0.25,0.05,0.02,false)
	var reverse:=plank(0.6,0.25,0.05,0.02,true)
	if not bool(forward.get("ok",false)) or not bool(reverse.get("ok",false)):
		return {"ok":false,"code":"GRAPH_ORDER_RUN_FAILED","forward":forward,"reverse":reverse}
	return {"ok":true,"forward":forward,"reverse":reverse,"state_error":_body_error(forward["post_body"],reverse["post_body"]),"signature_equal":String(forward["signature"])==String(reverse["signature"])}

static func sequential_falsifier()->Dictionary:
	var mass:=10.0;var inertia:=Vector3(4.0,2.5,6.0);var x:=0.6;var normal_impulse:=1.0
	var initial={"id":"PLANK","mass":mass,"inertia":inertia,"v":Vector3(0,-normal_impulse/mass,0),"w":Vector3(0,0,-x*normal_impulse/inertia.z)}
	var contacts:=_contacts(0.0)
	var forward:=_sequential(initial,contacts)
	contacts.reverse()
	var reverse:=_sequential(initial,contacts)
	return {"ok":true,"forward":forward,"reverse":reverse,"state_error":_body_error(forward,reverse)}

static func tolerance_refinement_probe()->Dictionary:
	var tolerances:=[1.0e-6,1.0e-8,1.0e-10,1.0e-12]
	var reference:=_plank_tolerance(0.6,1.0e-14)
	if not bool(reference.get("ok",false)):return {"ok":false,"code":"REFERENCE_FAILED","detail":reference}
	var errors:Array=[];var runs:Array=[]
	for tolerance_any in tolerances:
		var r:=_plank_tolerance(0.6,float(tolerance_any))
		if not bool(r.get("ok",false)):return {"ok":false,"code":"REFINEMENT_RUN_FAILED","tolerance":tolerance_any,"detail":r}
		runs.append(r)
		var e:=maxf(absf(float(r["per_contact"]["L"]["normal_impulse"])-float(reference["per_contact"]["L"]["normal_impulse"])),absf(float(r["per_contact"]["R"]["normal_impulse"])-float(reference["per_contact"]["R"]["normal_impulse"])))
		errors.append(e)
	return {"ok":true,"tolerances":tolerances,"runs":runs,"reference":reference,"errors":errors}

static func _plank_tolerance(load_x:float,tolerance:float)->Dictionary:
	var mass:=10.0;var inertia:=Vector3(4.0,2.5,6.0);var normal_impulse:=1.0
	var body={"id":"PLANK","mass":mass,"inertia":inertia,"v":Vector3(0,-normal_impulse/mass,0),"w":Vector3(0,0,-load_x*normal_impulse/inertia.z)}
	return Graph.solve(body,_contacts(0.0),{}, {"time":0.01,"tolerance":tolerance,"iterations":120000,"step_scale":0.8})

static func _sequential(initial:Dictionary,contacts:Array)->Dictionary:
	var body:=initial.duplicate(true)
	for contact_any in contacts:
		var one:Array=[Dictionary(contact_any)]
		var u:=Graph._generalized_velocity(body,one)
		var k:=Graph._effective_matrix(body,one,u)
		var initial_z:=[0.0,0.0,0.0,0.0,0.0,0.0]
		var solved:=Graph._projected_solve(k,u,initial_z,one,{"tolerance":1.0e-12,"iterations":60000,"step_scale":0.8})
		if bool(solved.get("ok",false)):Graph._apply_all(body,one,solved["z"])
	return body

static func _body_error(a:Dictionary,b:Dictionary)->float:
	return maxf((Vector3(a["v"])-Vector3(b["v"])).length(),(Vector3(a["w"])-Vector3(b["w"])).length())

static func corner(vx:float=-0.1,vy:float=-0.1,vz:float=0.0,wz:float=-0.1,reverse_contacts:bool=false,floor_mu:float=0.18,wall_mu:float=0.9,wx:float=0.0,wy:float=0.0)->Dictionary:
	var body={"id":"BLOCK","mass":2.0,"inertia":Vector3(1.0,1.0,1.2),"v":Vector3(vx,vy,vz),"w":Vector3(wx,wy,wz)}
	var floor={"contact_id":"FLOOR","anchor_id":"FLOOR_ANCHOR","r":Vector3(0,-1,0),"normal":Vector3(0,1,0),"t1":Vector3(1,0,0),"t2":Vector3(0,0,1),"effective_radius":0.3,"mu_tangent":floor_mu,"mu_rolling":0.0,"mu_torsion":0.0,"member_ids":["F|p0","F|p1","F|p2","F|p3"]}
	var wall={"contact_id":"WALL","anchor_id":"WALL_ANCHOR","r":Vector3(-1,0,0),"normal":Vector3(1,0,0),"t1":Vector3(0,1,0),"t2":Vector3(0,0,1),"effective_radius":0.3,"mu_tangent":wall_mu,"mu_rolling":0.0,"mu_torsion":0.0,"member_ids":["W|p0","W|p1","W|p2","W|p3"]}
	var contacts:Array=[floor,wall]
	if reverse_contacts:contacts.reverse()
	return Graph.solve(body,contacts,{}, {"time":0.01,"tolerance":1.0e-12,"iterations":80000,"step_scale":0.7})

static func corner_mixed_probe()->Dictionary:
	for vz in [-0.8,-0.4,-0.2,-0.1,0.1,0.2,0.4,0.8]:
		for wx in [-0.8,-0.4,-0.2,0.0,0.2,0.4,0.8]:
			for wy in [-0.8,-0.4,-0.2,0.0,0.2,0.4,0.8]:
				var r:=corner(-0.2,-0.2,float(vz),0.0,false,0.04,1.2,float(wx),float(wy))
				if not bool(r.get("ok",false)):continue
				var fm=Dictionary(Dictionary(r["per_contact"])["FLOOR"])["persistent_state"]["modes"]
				var wm=Dictionary(Dictionary(r["per_contact"])["WALL"])["persistent_state"]["modes"]
				if String(fm["tangent"])=="slide" and String(wm["tangent"])=="stick":
					return {"ok":true,"vz":vz,"wx":wx,"wy":wy,"result":r,"floor_modes":fm,"wall_modes":wm}
				if String(wm["tangent"])=="slide" and String(fm["tangent"])=="stick":
					return {"ok":true,"vz":vz,"wx":wx,"wy":wy,"result":r,"floor_modes":fm,"wall_modes":wm}
	return {"ok":false}

static func steady_support_probe(steps:int=10000,dt:float=0.001)->Dictionary:
	var body={"id":"PLANK","mass":10.0,"inertia":Vector3(4.0,2.5,6.0),"v":Vector3.ZERO,"w":Vector3.ZERO}
	var contacts:=_contacts(0.0)
	var states:Dictionary={}
	var position:=Vector3.ZERO
	var angle:=Vector3.ZERO
	var max_speed:=0.0
	var max_angular:=0.0
	for step in range(1,steps+1):
		body["v"]=Vector3(body["v"])+Vector3(0,-1.0/10.0,0)
		var r:=Graph.solve(body,contacts,states,{"time":float(step)*dt,"tolerance":1.0e-13,"iterations":80000,"step_scale":0.8})
		if not bool(r.get("ok",false)):return {"ok":false,"code":"STEADY_SOLVE_FAILED","step":step,"detail":r}
		body=Dictionary(r["post_body"]).duplicate(true)
		states={}
		for id in ["L","R"]:states[id]=Dictionary(Dictionary(r["per_contact"])[id])["persistent_state"]
		position+=Vector3(body["v"])*dt
		angle+=Vector3(body["w"])*dt
		max_speed=maxf(max_speed,Vector3(body["v"]).length())
		max_angular=maxf(max_angular,Vector3(body["w"]).length())
	return {"ok":true,"steps":steps,"time":float(steps)*dt,"body":body,"position":position,"angle":angle,"max_speed":max_speed,"max_angular_speed":max_angular,"states":states}

static func _contacts(rolling_mu:float=0.08)->Array:
	var common={"normal":Vector3(0,1,0),"t1":Vector3(1,0,0),"t2":Vector3(0,0,1),"effective_radius":0.4,"mu_tangent":0.45,"mu_rolling":rolling_mu,"mu_torsion":0.05,"anchor_id":"FLOOR"}
	var l:=common.duplicate(true);l["contact_id"]="L";l["r"]=Vector3(-1,0,0);l["member_ids"]=["L|p0","L|p1","L|p2","L|p3"]
	var r:=common.duplicate(true);r["contact_id"]="R";r["r"]=Vector3(1,0,0);r["member_ids"]=["R|p0","R|p1","R|p2","R|p3"]
	return [l,r]
