class_name Fabric0MultibodyConvexComplementarityGraphExperimentsV1
extends RefCounted
const F=preload("res://scripts/research/fabric0/fabric0_multibody_convex_complementarity_graph_v1.gd")
const M=preload("res://scripts/research/fabric0/fabric0_multibody_convex_model_v1.gd")

static func graph_run(dt:float=0.001,duration:float=0.45)->Dictionary:
	var w:=F.new_world();var r:=F.advance(w,duration,{"dt":dt});return {"world":w,"result":r}

static func coupled_order_probe()->Dictionary:
	var a:=F.new_world();var b:=F.new_world()
	# Same external velocity kick before the graph solve.
	for world in [a,b]:
		for body in world["bodies"]:body["v"]=Vector3(body["v"])+Vector3(world["gravity"])*(1.0/240.0)
	var ca:=F.discover_contacts(a);var cb:=F.discover_contacts(b)
	var sa:=F.solve_contacts(a,ca,1.0/240.0,false);var sb:=F.solve_contacts(b,cb,1.0/240.0,true)
	var max_v:=0.0;var max_w:=0.0
	for i in range(a["bodies"].size()):
		max_v=maxf(max_v,(Vector3(a["bodies"][i]["v"])-Vector3(b["bodies"][i]["v"])).length())
		max_w=maxf(max_w,(Vector3(a["bodies"][i]["w"])-Vector3(b["bodies"][i]["w"])).length())
	return {"forward":sa,"reverse":sb,"max_v":max_v,"max_w":max_w}

static func normal_chain_probe(dt:float=1.0/240.0)->Dictionary:
	var w:=F.new_world()
	for b in w["bodies"]:
		b["w"]=Vector3.ZERO
		b["v"]=Vector3(b["v"]) if String(b["id"])=="D" else Vector3.ZERO
	for b in w["bodies"]:b["v"]=Vector3(b["v"])+Vector3(w["gravity"])*dt
	var contacts:=F.discover_contacts(w);var s:=F.solve_contacts(w,contacts,dt,false)
	return {"world":w,"contacts":contacts,"solve":s}

static func mixed_friction_probe(dt:float=1.0/240.0)->Dictionary:
	var w:=F.new_world()
	for b in w["bodies"]:
		b["w"]=Vector3.ZERO
		if String(b["id"])!="D":b["v"]=Vector3.ZERO
	M.body(w,"C")["v"]=Vector3(0.7,0.0,0.0)
	M.body(w,"B")["v"]=Vector3(0.08,0.0,0.0)
	for b in w["bodies"]:b["v"]=Vector3(b["v"])+Vector3(w["gravity"])*dt
	var contacts:=F.discover_contacts(w);var s:=F.solve_contacts(w,contacts,dt,false)
	return {"world":w,"contacts":contacts,"solve":s}
