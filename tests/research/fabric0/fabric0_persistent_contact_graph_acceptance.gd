extends SceneTree

const Fabric = preload("res://scripts/research/fabric0/fabric0_persistent_contact_graph_v1.gd")
const Experiments = preload("res://scripts/research/fabric0/fabric0_persistent_contact_graph_experiments_v1.gd")

func close(a: float, b: float, tolerance: float = 1.0e-8) -> bool:
	return absf(a - b) <= tolerance

func close_vec(a: Vector3, b: Vector3, tolerance: float = 1.0e-8) -> bool:
	return (a - b).length() <= tolerance

func island_by_id(result: Dictionary, id: String) -> Dictionary:
	for island in result["islands"]:
		if String(island["island_id"]) == id:
			return island
	return {}

func _init() -> void:
	var checks := 0

	# -------------------------------------------------------------------------
	# Persistent stack + independent islands + warm start.
	# -------------------------------------------------------------------------
	var run := Experiments.run_sequence(false, false)
	var world: Dictionary = run["world"]
	var results: Array = run["results"]
	assert(results.size() == 5); checks += 1

	var r0: Dictionary = results[0]
	assert(r0["lifecycle"]["appeared"] == ["pair:A|B", "plane:floor|body:A", "plane:floor|body:D", "plane:floor|body:E"]); checks += 1
	assert(r0["lifecycle"]["persisted"].is_empty()); checks += 1
	assert(r0["lifecycle"]["disappeared"].is_empty()); checks += 1
	assert(int(r0["solver_stats"]["island_count"]) == 3); checks += 1
	assert(int(r0["solver_stats"]["warm_start_contacts"]) == 0); checks += 1
	assert(int(r0["solver_stats"]["iterations"]) == 39); checks += 1
	assert(island_by_id(r0, "island:A")["body_ids"] == ["A", "B"]); checks += 1
	assert(island_by_id(r0, "island:D")["body_ids"] == ["D"]); checks += 1
	assert(island_by_id(r0, "island:E")["body_ids"] == ["E"]); checks += 1
	assert(island_by_id(r0, "island:A")["contact_ids"] == ["pair:A|B", "plane:floor|body:A"]); checks += 1

	var r1: Dictionary = results[1]
	assert(r1["lifecycle"]["appeared"].is_empty()); checks += 1
	assert(r1["lifecycle"]["persisted"] == ["pair:A|B", "plane:floor|body:A", "plane:floor|body:D", "plane:floor|body:E"]); checks += 1
	assert(r1["lifecycle"]["disappeared"].is_empty()); checks += 1
	assert(int(r1["solver_stats"]["island_count"]) == 3); checks += 1
	assert(int(r1["solver_stats"]["warm_start_contacts"]) == 4); checks += 1
	assert(int(r1["solver_stats"]["iterations"]) == 3); checks += 1
	assert(int(r1["solver_stats"]["iterations"]) < int(r0["solver_stats"]["iterations"])); checks += 1
	assert(int(island_by_id(r1, "island:A")["iterations"]) == 1); checks += 1
	assert(int(island_by_id(r1, "island:A")["warm_start_contacts"]) == 2); checks += 1

	# -------------------------------------------------------------------------
	# Island merge: a new dynamic D-E edge appears while old floor contacts keep
	# their cached impulses, proving warm-start identity is graph-independent.
	# -------------------------------------------------------------------------
	var r2: Dictionary = results[2]
	assert(r2["lifecycle"]["appeared"] == ["pair:D|E"]); checks += 1
	assert(r2["lifecycle"]["persisted"] == ["pair:A|B", "plane:floor|body:A", "plane:floor|body:D", "plane:floor|body:E"]); checks += 1
	assert(r2["lifecycle"]["disappeared"].is_empty()); checks += 1
	assert(int(r2["solver_stats"]["island_count"]) == 2); checks += 1
	var de2 := island_by_id(r2, "island:D")
	assert(de2["body_ids"] == ["D", "E"]); checks += 1
	assert(de2["contact_ids"] == ["pair:D|E", "plane:floor|body:D", "plane:floor|body:E"]); checks += 1
	assert(int(de2["warm_start_contacts"]) == 2); checks += 1
	assert(int(de2["iterations"]) == 1); checks += 1
	assert(int(de2["sparse_effective_mass_entries"]) == 29); checks += 1
	assert(int(de2["dense_effective_mass_capacity"]) == 81); checks += 1
	assert(int(de2["sparse_effective_mass_entries"]) < int(de2["dense_effective_mass_capacity"])); checks += 1
	assert(int(r2["solver_stats"]["sparse_effective_mass_entries"]) == 41); checks += 1

	# Persistent pair becomes warm-startable on the following step.
	var r3: Dictionary = results[3]
	assert(r3["lifecycle"]["appeared"].is_empty()); checks += 1
	assert("pair:D|E" in r3["lifecycle"]["persisted"]); checks += 1
	assert(int(r3["solver_stats"]["island_count"]) == 2); checks += 1
	var de3 := island_by_id(r3, "island:D")
	assert(int(de3["warm_start_contacts"]) == 3); checks += 1
	assert(int(world["contact_history"][3]["step"]) == 3); checks += 1

	# -------------------------------------------------------------------------
	# Island split: pair disappears, static floor does not glue D and E together.
	# -------------------------------------------------------------------------
	var r4: Dictionary = results[4]
	assert(r4["lifecycle"]["appeared"].is_empty()); checks += 1
	assert(r4["lifecycle"]["disappeared"] == ["pair:D|E"]); checks += 1
	assert(int(r4["solver_stats"]["island_count"]) == 3); checks += 1
	assert(island_by_id(r4, "island:D")["body_ids"] == ["D"]); checks += 1
	assert(island_by_id(r4, "island:E")["body_ids"] == ["E"]); checks += 1
	assert(not world["contact_cache"].has("pair:D|E")); checks += 1
	assert(int(world["contact_cache"]["pair:A|B"]["age_steps"]) == 5); checks += 1
	assert(int(world["contact_cache"]["plane:floor|body:D"]["age_steps"]) == 5); checks += 1
	assert(int(world["contact_cache"]["plane:floor|body:E"]["age_steps"]) == 5); checks += 1

	# Resting stack survives five gravity steps instead of slowly sinking.
	assert(close_vec(world["bodies"]["A"]["position"], Vector3(0.0, 0.5, 0.0), 2.0e-8)); checks += 1
	assert(close_vec(world["bodies"]["B"]["position"], Vector3(0.0, 1.5, 0.0), 2.0e-8)); checks += 1
	assert(world["bodies"]["A"]["linear_velocity"].length() <= 2.0e-8); checks += 1
	assert(world["bodies"]["B"]["linear_velocity"].length() <= 2.0e-8); checks += 1
	assert(world["bodies"]["D"]["linear_velocity"].length() <= 2.0e-8); checks += 1
	assert(world["bodies"]["E"]["linear_velocity"].length() <= 2.0e-8); checks += 1

	# Dynamic body-body contact carries load: its cached normal impulse is ~mg*dt.
	var ab_warm: Vector3 = world["contact_cache"]["pair:A|B"]["warm_impulse"]
	var a_floor_warm: Vector3 = world["contact_cache"]["plane:floor|body:A"]["warm_impulse"]
	assert(close(ab_warm.x, 0.0981, 2.0e-8)); checks += 1
	assert(close(a_floor_warm.x, 0.1962, 2.0e-8)); checks += 1

	# -------------------------------------------------------------------------
	# Independent island equivalence: unrelated D/E graph mutations cannot alter
	# the A/B island's physical trajectory.
	# -------------------------------------------------------------------------
	var stack := Fabric.new_world(Vector3(0.0, -9.81, 0.0))
	assert(Fabric.add_body(stack, Fabric.new_sphere_body("A",1.0,0.5,Vector3(0,0.5,0),Vector3.ZERO,Vector3.ZERO,0.6,0.0))); checks += 1
	assert(Fabric.add_body(stack, Fabric.new_sphere_body("B",1.0,0.5,Vector3(0,1.5,0),Vector3.ZERO,Vector3.ZERO,0.6,0.0))); checks += 1
	for _i in range(5):
		var stack_contacts := Fabric.compile_sphere_contacts(stack, Experiments.floor_planes(), 1.0e-6)
		assert(bool(stack_contacts["ok"])); checks += 1
		var stack_step := Fabric.step(stack, stack_contacts["contacts"], 0.01, {"rho":0.2,"tolerance":1.0e-9,"max_iterations":10000})
		assert(bool(stack_step["ok"])); checks += 1
	assert(close_vec(stack["bodies"]["A"]["position"], world["bodies"]["A"]["position"], 1.0e-12)); checks += 1
	assert(close_vec(stack["bodies"]["B"]["position"], world["bodies"]["B"]["position"], 1.0e-12)); checks += 1
	assert(close_vec(stack["bodies"]["A"]["linear_velocity"], world["bodies"]["A"]["linear_velocity"], 1.0e-12)); checks += 1
	assert(close_vec(stack["bodies"]["B"]["linear_velocity"], world["bodies"]["B"]["linear_velocity"], 1.0e-12)); checks += 1

	# -------------------------------------------------------------------------
	# Enumeration order is not physical truth across lifecycle + island changes.
	# -------------------------------------------------------------------------
	var reversed := Experiments.run_sequence(true, true)
	assert(String(reversed["hash"]) == String(run["hash"])); checks += 1
	assert(JSON.stringify(reversed["world"]["contact_history"]) == JSON.stringify(world["contact_history"])); checks += 1
	for id in ["A","B","D","E"]:
		assert(close_vec(reversed["world"]["bodies"][id]["position"], world["bodies"][id]["position"], 1.0e-12)); checks += 1
		assert(close_vec(reversed["world"]["bodies"][id]["linear_velocity"], world["bodies"][id]["linear_velocity"], 1.0e-12)); checks += 1

	# -------------------------------------------------------------------------
	# Event-aware bridge: a previously contact-free falling body crosses the
	# plane inside a large dt. Contact graph appears at localized physical time,
	# then remaining dt is solved as a persistent contact island.
	# -------------------------------------------------------------------------
	var falling := Fabric.new_world(Vector3(0.0,-9.81,0.0))
	assert(Fabric.add_body(falling, Fabric.new_sphere_body("fall",1.0,0.5,Vector3(0,2,0),Vector3(0,-1,0),Vector3.ZERO,0.5,0.0))); checks += 1
	var event_result := Fabric.advance_contact_free_to_first_plane_event(falling, Experiments.floor_planes(), 1.0, {"rho":0.2,"tolerance":1.0e-9,"max_iterations":10000})
	assert(bool(event_result["ok"])); checks += 1
	var reference_event := (-1.0 + sqrt(30.43)) / 9.81
	assert(close(float(event_result["event_time"]), reference_event, 2.0e-11)); checks += 1
	assert(String(event_result["event_body"]) == "fall"); checks += 1
	assert(String(event_result["event_plane"]) == "floor"); checks += 1
	assert(event_result["event_contact_ids"] == ["plane:floor|body:fall"]); checks += 1
	assert(close(float(event_result["contact_step"]["lifecycle"]["time"]), reference_event, 2.0e-11)); checks += 1
	assert(event_result["contact_step"]["lifecycle"]["appeared"] == ["plane:floor|body:fall"]); checks += 1
	assert(close(float(falling["time"]), 1.0, 1.0e-12)); checks += 1
	assert(close_vec(falling["bodies"]["fall"]["position"], Vector3(0,0.5,0), 2.0e-8)); checks += 1
	assert(falling["bodies"]["fall"]["linear_velocity"].length() <= 2.0e-8); checks += 1
	assert(int(event_result["contact_step"]["solver_stats"]["island_count"]) == 1); checks += 1
	assert(int(event_result["contact_step"]["islands"][0]["active_contacts"]) == 1); checks += 1

	# Fail closed on invalid provider identity/body reference.
	var invalid_world := Experiments.build_world()
	var bad_contact := {"id":"bad","body_a":"missing","body_b":"@static/floor","normal":Vector3.UP,"tangent_1":Vector3.RIGHT,"tangent_2":Vector3.BACK,"r_a":Vector3.ZERO,"r_b":Vector3.ZERO,"gap":0.0,"friction":0.5,"restitution":0.0}
	var bad_graph := Fabric.update_contact_graph(invalid_world, [bad_contact])
	assert(not bool(bad_graph["ok"])); checks += 1
	assert(String(bad_graph["code"]) == "CONTACT_BODY_A_UNKNOWN"); checks += 1

	assert(String(run["hash"]).length() == 64); checks += 1
	assert(String(event_result["state_hash"]).length() == 64); checks += 1

	print("FABRIC0.10 Persistent Contact Graph Acceptance: PASS (%d assertions) cold=%d warm=%d warm_hits=%d islands=%d->%d->%d lifecycle=%s/%s/%s event_t=%.12f sparse=%d/%d hash=%s event_hash=%s" % [
		checks,
		int(r0["solver_stats"]["iterations"]),
		int(r1["solver_stats"]["iterations"]),
		int(r1["solver_stats"]["warm_start_contacts"]),
		int(r1["solver_stats"]["island_count"]),
		int(r2["solver_stats"]["island_count"]),
		int(r4["solver_stats"]["island_count"]),
		String(r2["lifecycle"]["appeared"][0]),
		String(r3["lifecycle"]["persisted"][1]),
		String(r4["lifecycle"]["disappeared"][0]),
		float(event_result["event_time"]),
		int(de2["sparse_effective_mass_entries"]),
		int(de2["dense_effective_mass_capacity"]),
		String(run["hash"]),
		String(event_result["state_hash"]),
	])
	quit(0)
