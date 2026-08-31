class_name Fabric0GeneralConvexMultipointMcpExperimentsV1
extends RefCounted

const F = preload("res://scripts/research/fabric0/fabric0_general_convex_multipoint_mcp_v1.gd")
const Model = preload("res://scripts/research/fabric0/fabric0_general_convex_model_v1.gd")

static func rotated_pair_probe() -> Dictionary:
	var shape := F.box_shape("box", Vector3(0.5,0.5,0.5))
	var a := F.new_body("A", shape, Vector3.ZERO)
	var b := F.new_body("B", shape, Vector3(0.8,0.05,0.0), Quaternion(Vector3.UP,0.1), 1.2, Vector3(0.2,0.23,0.27))
	var collision := F.collide(a,b)
	var manifold := F.build_manifold(a,b,collision)
	return {"a":a, "b":b, "collision":collision, "manifold":manifold}

static func persistence_probe() -> Dictionary:
	var first := rotated_pair_probe()
	var a:Dictionary = first["a"]
	var b:Dictionary = first["b"]
	var old_manifold:Dictionary = first["manifold"]
	b["p"] = Vector3(0.79,0.052,0.0)
	var collision := F.collide(a,b)
	var next_manifold := F.build_manifold(a,b,collision,old_manifold)
	return {"first":old_manifold, "next":next_manifold, "collision":collision}

static func broadphase_probe() -> Dictionary:
	var shape := F.box_shape("box", Vector3(0.5,0.5,0.5))
	var bodies := [
		F.new_body("A",shape,Vector3(0.0,0.0,0.0)),
		F.new_body("B",shape,Vector3(0.9,0.0,0.0)),
		F.new_body("C",shape,Vector3(4.0,0.0,0.0)),
		F.new_body("D",shape,Vector3(0.0,4.0,0.0)),
	]
	return {"bodies":bodies, "pairs":F.broadphase_pairs(bodies)}

static func graph_chain_probe(sliding:bool=false, reverse_contacts:bool=false) -> Dictionary:
	var shape := F.box_shape("box", Vector3(0.5,0.5,0.5))
	var a_velocity := Vector3(8.0,0.1,1.0) if sliding else Vector3(0.0,0.0,1.0)
	var c_velocity := Vector3(-6.0,-0.2,-1.0) if sliding else Vector3(0.0,0.0,-1.0)
	var bodies := [
		F.new_body("A",shape,Vector3(0.0,0.0,0.0),Quaternion.IDENTITY,1.0,Vector3(0.2,0.2,0.2),a_velocity),
		F.new_body("B",shape,Vector3(0.0,0.0,0.95),Quaternion.IDENTITY,1.0,Vector3(0.2,0.2,0.2),Vector3.ZERO),
		F.new_body("C",shape,Vector3(0.0,0.0,1.9),Quaternion.IDENTITY,1.0,Vector3(0.2,0.2,0.2),c_velocity),
	]
	var contacts:Array = []
	var manifolds:Array = []
	for pair in [[0,1],[1,2]]:
		var ai := int(pair[0])
		var bi := int(pair[1])
		var collision := F.collide(bodies[ai],bodies[bi])
		var manifold := F.build_manifold(bodies[ai],bodies[bi],collision)
		manifolds.append(manifold)
		for point in manifold["points"]:
			var contact:Dictionary = point.duplicate(true)
			contact["a"] = ai
			contact["b"] = bi
			contact["mu"] = 0.2 if sliding else 0.0
			# The collision stage proves geometry/depth. This impulse probe starts at the localized contact surface.
			contact["gap"] = 0.0
			contacts.append(contact)
	if reverse_contacts:
		contacts.reverse()

	var linear_before := F.total_linear_momentum(bodies)
	var angular_before := F.total_angular_momentum_origin(bodies)
	var energy_before := F.total_kinetic_energy(bodies)
	var options := {
		"beta":0.0,
		"normal_tolerance":1.0e-9,
		"normal_iterations":256,
		"tangent_iterations":64 if sliding else 0,
		"coupling_iterations":256 if sliding else 8,
		"coupling_tolerance":1.0e-9,
		"normal_regularization":1.0e-9,
	}
	var solve := F.solve_contacts(bodies,contacts,0.01,options)
	var linear_error := (F.total_linear_momentum(bodies)-linear_before).length()
	var angular_error := (F.total_angular_momentum_origin(bodies)-angular_before).length()
	var energy_delta := F.total_kinetic_energy(bodies)-energy_before
	return {
		"bodies":bodies,
		"contacts":contacts,
		"manifolds":manifolds,
		"solve":solve,
		"linear_momentum_error":linear_error,
		"angular_momentum_error":angular_error,
		"kinetic_energy_delta":energy_delta,
		"signature":solution_signature(bodies,solve),
	}

static func pair_normal_impulse(solve:Dictionary, pair_prefix:String) -> float:
	var total := 0.0
	for id in solve["blocks"].keys():
		if String(id).begins_with(pair_prefix):
			total += float(solve["blocks"][id]["pn"])
	return total

static func solution_signature(bodies:Array, solve:Dictionary) -> String:
	if not bool(solve.get("ok",false)):
		return JSON.stringify(solve)
	var block_data:Array = []
	for id in solve["canonical_ids"]:
		var block:Dictionary = solve["blocks"][String(id)]
		var tangent:Vector2 = block["pt"]
		block_data.append([
			String(id),
			float(block["pn"]),
			tangent.x,
			tangent.y,
			String(block["mode"]),
		])
	var body_data:Array = []
	for body in bodies:
		var v:Vector3 = body["v"]
		var w:Vector3 = body["w"]
		body_data.append([String(body["id"]),v.x,v.y,v.z,w.x,w.y,w.z])
	return JSON.stringify({"blocks":block_data,"bodies":body_data},"",false)
