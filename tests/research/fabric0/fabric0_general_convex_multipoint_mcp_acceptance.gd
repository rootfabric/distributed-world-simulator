extends SceneTree

const F = preload("res://scripts/research/fabric0/fabric0_general_convex_multipoint_mcp_v1.gd")
const E = preload("res://scripts/research/fabric0/fabric0_general_convex_multipoint_mcp_experiments_v1.gd")
const Model = preload("res://scripts/research/fabric0/fabric0_general_convex_model_v1.gd")
const Collision = preload("res://scripts/research/fabric0/fabric0_gjk_epa_v1.gd")

func close(a:float, b:float, tolerance:float=1.0e-10) -> bool:
	return absf(a-b) <= tolerance

func _init() -> void:
	var checks := 0

	# --- Generic support mapping over explicit convex vertex/face data. ---
	var box := F.box_shape("box",Vector3(0.5,0.75,1.0))
	var support_body := F.new_body("S",box,Vector3(2.0,-1.0,0.25))
	var support_x := F.support(support_body,Vector3.RIGHT)
	assert(close(Vector3(support_x["point"]).x,2.5)); checks += 1
	assert(int(support_x["index"]) == 1); checks += 1
	var support_z := F.support(support_body,Vector3.BACK)
	assert(close(Vector3(support_z["point"]).z,1.25)); checks += 1
	var tetra := F.tetra_shape("tetra",0.45)
	assert(tetra["vertices"].size() == 4 and tetra["faces"].size() == 4); checks += 1

	# --- Sweep-and-prune broadphase rejects distant convex bodies deterministically. ---
	var broadphase := E.broadphase_probe()
	assert(broadphase["pairs"] == [[0,1]]); checks += 1
	assert(F.broadphase_pairs(broadphase["bodies"]) == broadphase["pairs"]); checks += 1

	# --- Axis-aligned analytic GJK/EPA oracle. ---
	var unit_box := F.box_shape("unit_box",Vector3(0.5,0.5,0.5))
	var overlap_offsets := [
		Vector3(0.2,0.1,0.05),
		Vector3(0.8,0.1,0.1),
		Vector3(0.1,0.7,0.2),
		Vector3(0.1,0.2,0.6),
		Vector3(-0.65,0.15,-0.2),
	]
	for offset in overlap_offsets:
		var a := F.new_body("A",unit_box,Vector3.ZERO)
		var b := F.new_body("B",unit_box,offset)
		var penetration := F.collide(a,b)
		var expected := minf(1.0-absf(offset.x),minf(1.0-absf(offset.y),1.0-absf(offset.z)))
		assert(bool(penetration["ok"]) and bool(penetration["intersect"])); checks += 1
		assert(close(float(penetration["depth"]),expected,1.0e-10)); checks += 1
		assert(close(Vector3(penetration["normal"]).length(),1.0,1.0e-12)); checks += 1
		assert(int(penetration["gjk_iterations"]) <= 4); checks += 1
		assert(int(penetration["epa_iterations"]) <= 12); checks += 1

	for offset in [Vector3(1.01,0,0),Vector3(0,1.02,0),Vector3(0,0,-1.1),Vector3(2,2,2)]:
		var a := F.new_body("A",unit_box,Vector3.ZERO)
		var b := F.new_body("B",unit_box,offset)
		var separated := Collision.intersect(a,b)
		assert(bool(separated["ok"])); checks += 1
		assert(not bool(separated["intersect"])); checks += 1

	# --- A second convex family: tetrahedron against a rotated box. ---
	var rotated_box := F.new_body("A",unit_box,Vector3.ZERO,Quaternion(Vector3(1,1,0).normalized(),0.13))
	var tetra_hit := F.new_body("T",tetra,Vector3(0.25,0.1,0.05),Quaternion(Vector3.UP,0.27))
	var tetra_miss := F.new_body("T2",tetra,Vector3(1.6,0.0,0.0),Quaternion(Vector3.UP,0.27))
	var tetra_hit_result := F.collide(rotated_box,tetra_hit)
	var tetra_miss_result := F.collide(rotated_box,tetra_miss)
	assert(bool(tetra_hit_result["ok"]) and bool(tetra_hit_result["intersect"])); checks += 1
	assert(float(tetra_hit_result["depth"]) > 0.7); checks += 1
	assert(bool(tetra_miss_result["ok"]) and not bool(tetra_miss_result["intersect"])); checks += 1

	# --- EPA symmetry under pair reversal. ---
	var symmetry_a := F.new_body("A",unit_box,Vector3.ZERO,Quaternion(Vector3(1,2,3).normalized(),0.12))
	var symmetry_b := F.new_body("B",unit_box,Vector3(0.74,0.08,0.04),Quaternion(Vector3.UP,0.17))
	var ab := F.collide(symmetry_a,symmetry_b)
	var ba := F.collide(symmetry_b,symmetry_a)
	assert(close(float(ab["depth"]),float(ba["depth"]),1.0e-12)); checks += 1
	assert((Vector3(ab["normal"])+Vector3(ba["normal"])).length() < 1.0e-12); checks += 1
	assert((Vector3(ab["point_a"])-Vector3(ba["point_b"])).length() < 1.0e-12); checks += 1
	assert((Vector3(ab["point_b"])-Vector3(ba["point_a"])).length() < 1.0e-12); checks += 1

	# --- True clipped face manifold and persistent point identity. ---
	var pair := E.rotated_pair_probe()
	assert(bool(pair["collision"]["ok"]) and bool(pair["collision"]["intersect"])); checks += 1
	assert(close(float(pair["collision"]["depth"]),0.24741879096243,1.0e-12)); checks += 1
	assert(bool(pair["manifold"]["ok"])); checks += 1
	assert(pair["manifold"]["points"].size() == 4); checks += 1
	assert(String(pair["manifold"]["feature_key"]) == "A|B|ra:A:5|ib:B:4"); checks += 1
	var first_ids:Array = []
	for point in pair["manifold"]["points"]:
		first_ids.append(String(point["id"]))
		assert(int(point["lifetime"]) == 1); checks += 1
		assert(float(point["depth"]) >= 0.0); checks += 1
	var unique_first_ids:Dictionary = {}
	for id in first_ids:
		unique_first_ids[String(id)] = true
	assert(unique_first_ids.size() == 4); checks += 1

	var persistence := E.persistence_probe()
	assert(bool(persistence["next"]["ok"])); checks += 1
	assert(persistence["next"]["points"].size() == 4); checks += 1
	var next_ids:Array = []
	for point in persistence["next"]["points"]:
		next_ids.append(String(point["id"]))
		assert(int(point["lifetime"]) == 2); checks += 1
	assert(next_ids == first_ids); checks += 1

	# --- Eight-row graph-wide normal LCP over two four-point manifolds. ---
	var chain := E.graph_chain_probe(false,false)
	var chain_solve:Dictionary = chain["solve"]
	assert(bool(chain_solve["ok"])); checks += 1
	assert(chain["contacts"].size() == 8); checks += 1
	assert(chain["manifolds"][0]["points"].size() == 4 and chain["manifolds"][1]["points"].size() == 4); checks += 1
	assert(String(chain_solve["normal_solver"]) == "ACTIVE_SET_LCP"); checks += 1
	assert(chain_solve["canonical_ids"].size() == 8); checks += 1
	assert(absf(float(chain_solve["normal_matrix"][0][4])) > 1.0); checks += 1
	assert(float(chain_solve["normal_residual"]) <= 1.0e-12); checks += 1
	assert(float(chain_solve["max_complementarity_violation"]) < 1.0e-9); checks += 1
	assert(float(chain_solve["max_normal_velocity_violation"]) < 1.0e-9); checks += 1
	assert(float(chain_solve["max_cone_violation"]) == 0.0); checks += 1
	var ab_impulse := E.pair_normal_impulse(chain_solve,"A|B|")
	var bc_impulse := E.pair_normal_impulse(chain_solve,"B|C|")
	assert(close(ab_impulse,0.99999999975,1.0e-10)); checks += 1
	assert(close(bc_impulse,0.99999999975,1.0e-10)); checks += 1
	for body in chain["bodies"]:
		assert(absf(Vector3(body["v"]).z) < 5.0e-10); checks += 1
	assert(float(chain["linear_momentum_error"]) <= 1.0e-14); checks += 1
	assert(float(chain["angular_momentum_error"]) <= 1.0e-14); checks += 1
	assert(float(chain["kinetic_energy_delta"]) < -0.99); checks += 1

	# Canonical solve order removes caller contact ordering as a numerical input.
	var chain_reverse := E.graph_chain_probe(false,true)
	assert(bool(chain_reverse["solve"]["ok"])); checks += 1
	assert(String(chain_reverse["signature"]) == String(chain["signature"])); checks += 1

	# --- Strong sliding falsifier: coupled normal/friction fixed point. ---
	var sliding := E.graph_chain_probe(true,false)
	var sliding_solve:Dictionary = sliding["solve"]
	assert(bool(sliding_solve["ok"])); checks += 1
	assert(String(sliding_solve["friction_coupling"]) == "OUTER_FIXED_POINT"); checks += 1
	assert(int(sliding_solve["coupling_iterations"]) > 1); checks += 1
	assert(float(sliding_solve["max_complementarity_violation"]) < 1.0e-9); checks += 1
	assert(float(sliding_solve["max_normal_velocity_violation"]) < 1.0e-9); checks += 1
	assert(float(sliding_solve["max_cone_violation"]) <= 1.0e-12); checks += 1
	var slide_count := 0
	for id in sliding_solve["canonical_ids"]:
		var block:Dictionary = sliding_solve["blocks"][String(id)]
		if String(block["mode"]) == "slide":
			slide_count += 1
			var limit := 0.2 * float(block["pn"])
			assert(close(Vector2(block["pt"]).length(),limit,1.0e-10)); checks += 1
	assert(slide_count == 8); checks += 1
	assert(float(sliding["linear_momentum_error"]) <= 1.0e-14); checks += 1
	assert(float(sliding["angular_momentum_error"]) <= 1.0e-14); checks += 1
	assert(float(sliding["kinetic_energy_delta"]) < -3.0); checks += 1

	var sliding_replay := E.graph_chain_probe(true,false)
	var sliding_reverse := E.graph_chain_probe(true,true)
	assert(String(sliding_replay["signature"]) == String(sliding["signature"])); checks += 1
	assert(String(sliding_reverse["signature"]) == String(sliding["signature"])); checks += 1

	# --- Explicit fail-closed numerical boundaries. ---
	var bad_dt := F.solve_contacts([], [{"id":"bad"}], 0.0)
	assert(not bool(bad_dt["ok"]) and String(bad_dt["code"]) == "BAD_STEP"); checks += 1
	var bad_reg_bodies:Array = E.graph_chain_probe(false,false)["bodies"]
	var bad_reg := F.solve_contacts(bad_reg_bodies,chain["contacts"],0.01,{"normal_regularization":-1.0})
	assert(not bool(bad_reg["ok"]) and String(bad_reg["code"]) == "NEGATIVE_NORMAL_REGULARIZATION"); checks += 1
	var bad_budget_bodies:Array = E.graph_chain_probe(false,false)["bodies"]
	var bad_budget := F.solve_contacts(bad_budget_bodies,chain["contacts"],0.01,{"normal_iterations":0})
	assert(not bool(bad_budget["ok"]) and String(bad_budget["code"]) == "BAD_SOLVER_BUDGET"); checks += 1

	print("FABRIC0.16 General Convex Multipoint MCP S1 Acceptance: PASS (%d assertions) epa_depth=%.14f manifold=%d graph_rows=%d pair_impulses=(%.12f,%.12f) slide=%d coupling=%d comp=%s cone=%s linear=%s angular=%s" % [
		checks,
		float(pair["collision"]["depth"]),
		pair["manifold"]["points"].size(),
		chain["contacts"].size(),
		ab_impulse,
		bc_impulse,
		slide_count,
		int(sliding_solve["coupling_iterations"]),
		String.num_scientific(float(sliding_solve["max_complementarity_violation"])),
		String.num_scientific(float(sliding_solve["max_cone_violation"])),
		String.num_scientific(float(sliding["linear_momentum_error"])),
		String.num_scientific(float(sliding["angular_momentum_error"])),
	])
	quit(0)
