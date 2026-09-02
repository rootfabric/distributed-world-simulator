class_name Fabric0GeneralConvexParallelIslandsV1
extends RefCounted

const F = preload("res://scripts/research/fabric0/fabric0_general_convex_multipoint_mcp_v1.gd")

static func partition(bodies:Array,contacts:Array)->Dictionary:
	var validation:=_validate_world(bodies,contacts)
	if not bool(validation["ok"]):return validation
	var body_ids:Array=[]
	for body in bodies:body_ids.append(String(body["id"]))
	body_ids.sort()
	var parent:Dictionary={}
	for id in body_ids:parent[id]=id
	for contact in contacts:
		if int(contact["a"])<0:continue
		var a_id:=String(bodies[int(contact["a"])]["id"])
		var b_id:=String(bodies[int(contact["b"])]["id"])
		_union(parent,a_id,b_id)
	var groups:Dictionary={}
	for id in body_ids:
		var root:=_find(parent,id)
		if not groups.has(root):groups[root]=[]
		groups[root].append(id)
	var islands:Array=[]
	for ids_any in groups.values():
		var ids:Array=ids_any;ids.sort()
		var body_set:Dictionary={}
		for id in ids:body_set[id]=true
		var island_contacts:Array=[]
		for contact in contacts:
			var b_id:=String(bodies[int(contact["b"])]["id"])
			if not body_set.has(b_id):continue
			if int(contact["a"])>=0:
				var a_id:=String(bodies[int(contact["a"])]["id"])
				if not body_set.has(a_id):continue
			island_contacts.append(contact.duplicate(true))
		island_contacts.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return String(a["id"])<String(b["id"]))
		islands.append({"id":String(ids[0]),"body_ids":ids,"contacts":island_contacts})
	islands.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return String(a["id"])<String(b["id"]))
	return {"ok":true,"islands":islands}

static func solve_same_world(bodies:Array,contacts:Array,dt:float,options:Dictionary={},reverse_spawn:bool=false)->Dictionary:
	if dt<=0.0:return {"ok":false,"code":"BAD_STEP"}
	var partitioned:=partition(bodies,contacts)
	if not bool(partitioned["ok"]):return partitioned
	var islands:Array=partitioned["islands"]
	var max_threads:=int(options.get("max_threads",64))
	if max_threads<=0:return {"ok":false,"code":"BAD_THREAD_BUDGET"}
	if islands.size()>max_threads:return {"ok":false,"code":"ISLAND_THREAD_BUDGET_EXCEEDED","islands":islands.size(),"max_threads":max_threads}
	var tasks:Array=[]
	for island in islands:tasks.append(_make_task(bodies,island,dt,options))
	var spawn:=tasks.duplicate(true)
	if reverse_spawn:spawn.reverse()
	var threads:Array=[]
	for task in spawn:
		var thread:=Thread.new()
		var error:=thread.start(Callable(Fabric0GeneralConvexParallelIslandsV1,"_thread_solve").bind(task))
		if error!=OK:
			_join_threads(threads)
			return {"ok":false,"code":"THREAD_START_FAILED","error":error}
		threads.append(thread)
	var results:Array=[]
	for thread in threads:results.append(thread.wait_to_finish())
	results.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return String(a["id"])<String(b["id"]))
	for result in results:
		if not bool(result.get("ok",false)):return {"ok":false,"code":"ISLAND_SOLVE_FAILED","island":result}
	var index_by_id:Dictionary={}
	for i in range(bodies.size()):index_by_id[String(bodies[i]["id"])]=i
	for result in results:
		for state in result["body_states"]:
			var index:=int(index_by_id[String(state["id"])])
			bodies[index]["v"]=Vector3(state["v"])
			bodies[index]["w"]=Vector3(state["w"])
	return {
		"ok":true,
		"threads_started":threads.size(),
		"islands":islands,
		"results":results,
		"canonical_signature":_signature(results),
	}

static func _validate_world(bodies:Array,contacts:Array)->Dictionary:
	var ids:Dictionary={}
	for body in bodies:
		var id:=String(body.get("id",""))
		if id.is_empty():return {"ok":false,"code":"EMPTY_BODY_ID"}
		if ids.has(id):return {"ok":false,"code":"DUPLICATE_BODY_ID","id":id}
		ids[id]=true
	for contact in contacts:
		if not contact.has("id") or String(contact["id"]).is_empty():return {"ok":false,"code":"EMPTY_CONTACT_ID"}
		if not contact.has("a") or not contact.has("b"):return {"ok":false,"code":"CONTACT_BODY_INDEX_MISSING"}
		var a:=int(contact["a"])
		var b:=int(contact["b"])
		if b<0 or b>=bodies.size():return {"ok":false,"code":"CONTACT_BODY_INDEX_OUT_OF_RANGE","id":String(contact["id"])}
		if a>=bodies.size() or a< -1:return {"ok":false,"code":"CONTACT_BODY_INDEX_OUT_OF_RANGE","id":String(contact["id"])}
		if a==b:return {"ok":false,"code":"SELF_CONTACT","id":String(contact["id"])}
	return {"ok":true}

static func _join_threads(threads:Array)->void:
	for thread in threads:
		if thread.is_started():thread.wait_to_finish()

static func _make_task(bodies:Array,island:Dictionary,dt:float,options:Dictionary)->Dictionary:
	var global_index_by_id:Dictionary={}
	for i in range(bodies.size()):global_index_by_id[String(bodies[i]["id"])]=i
	var local_bodies:Array=[]
	var local_index_by_global:Dictionary={}
	for id in island["body_ids"]:
		var global_index:=int(global_index_by_id[String(id)])
		local_index_by_global[global_index]=local_bodies.size()
		local_bodies.append(bodies[global_index].duplicate(true))
	var local_contacts:Array=[]
	for contact_any in island["contacts"]:
		var contact:Dictionary=contact_any.duplicate(true)
		var global_b:=int(contact["b"])
		contact["b"]=int(local_index_by_global[global_b])
		if int(contact["a"])>=0:
			var global_a:=int(contact["a"])
			contact["a"]=int(local_index_by_global[global_a])
		local_contacts.append(contact)
	return {"id":String(island["id"]),"bodies":local_bodies,"contacts":local_contacts,"dt":dt,"options":options.duplicate(true)}

static func _thread_solve(task:Dictionary)->Dictionary:
	var bodies:Array=task["bodies"]
	var contacts:Array=task["contacts"]
	var solve:=F.solve_contacts(bodies,contacts,float(task["dt"]),task["options"])
	if not bool(solve.get("ok",false)):return {"id":String(task["id"]),"ok":false,"solve":solve}
	var states:Array=[]
	for body in bodies:states.append({"id":String(body["id"]),"v":Vector3(body["v"]),"w":Vector3(body["w"])})
	states.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return String(a["id"])<String(b["id"]))
	var blocks:Array=[]
	for id in solve.get("canonical_ids",[]):
		var block:Dictionary=solve["blocks"][String(id)]
		blocks.append({"id":String(id),"pn":float(block["pn"]),"pt":Vector2(block["pt"]),"mode":String(block["mode"])})
	return {"id":String(task["id"]),"ok":true,"body_states":states,"blocks":blocks,"solve_metrics":{"comp":float(solve.get("max_complementarity_violation",0.0)),"cone":float(solve.get("max_cone_violation",0.0))}}

static func _signature(results:Array)->String:
	var canonical:Array=[]
	for result in results:
		var states:Array=[]
		for state in result["body_states"]:
			var v:Vector3=state["v"];var w:Vector3=state["w"]
			states.append([String(state["id"]),v.x,v.y,v.z,w.x,w.y,w.z])
		var blocks:Array=[]
		for block in result["blocks"]:
			var pt:Vector2=block["pt"]
			blocks.append([String(block["id"]),float(block["pn"]),pt.x,pt.y,String(block["mode"])])
		canonical.append({"id":String(result["id"]),"states":states,"blocks":blocks})
	return JSON.stringify(canonical,"",false)

static func _find(parent:Dictionary,id:String)->String:
	var root:=id
	while String(parent[root])!=root:root=String(parent[root])
	return root

static func _union(parent:Dictionary,a:String,b:String)->void:
	var ra:=_find(parent,a);var rb:=_find(parent,b)
	if ra==rb:return
	if ra<rb:parent[rb]=ra
	else:parent[ra]=rb
