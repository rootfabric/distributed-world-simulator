extends SceneTree

const Compiler = preload("res://scripts/research/fabric_bake0/contact_wrench_bake_compiler_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/contact_wrench_bake_runtime_v1.gd")

const H64_A := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const H64_B := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
const H64_C := "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
const H64_D := "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
const EPS := 2.0e-10

func _init() -> void:
	var checks := 0
	var points := grid_points(21, 1.0, 0.75)
	assert(points.size() == 441); checks += 1
	var request := base_request(points)
	var compiled := Compiler.compile(request)
	assert(bool(compiled.get("ok", false))); checks += 1
	assert(String(compiled["status"]) == "BAKE_READY"); checks += 1
	var artifact: Dictionary = compiled["model"]
	assert(bool(Compiler.validate_model(artifact).get("ok", false))); checks += 1
	assert(String(artifact["kind"]) == Compiler.KIND); checks += 1
	assert(String(artifact["compiler_version"]) == Compiler.COMPILER_VERSION); checks += 1
	assert(String(artifact["fabric0_18_closure"]) == Compiler.FABRIC0_18_CLOSURE); checks += 1
	assert(String(artifact["fabric0_18_exact_physics"]) == Compiler.FABRIC0_18_EXACT_PHYSICS); checks += 1
	assert(String(artifact["bridge1_closure"]) == Compiler.BRIDGE1_CLOSURE); checks += 1
	assert(int(artifact["full_member_count"]) == 441); checks += 1
	assert(int(artifact["generator_count"]) == 4); checks += 1
	assert(float(artifact["reduction_ratio"]) > 110.0); checks += 1
	assert(bool(compiled["diagnostics"]["exact_support_function_preservation"])); checks += 1
	assert(not bool(artifact["internal_lambda_persisted"])); checks += 1
	assert(not bool(artifact["warm_start_persisted"])); checks += 1
	assert(not bool(artifact["contact_age_persisted"])); checks += 1
	assert(not bool(artifact["mode_history_persisted"])); checks += 1
	assert(String(artifact["reconstruction_policy"]) == "DISCARD_AND_REDERIVE_CONTACT_STATE"); checks += 1
	var artifact_text := JSON.stringify(artifact)
	assert(artifact_text.find("accepted_generalized_impulse") < 0); checks += 1
	assert(artifact_text.find("warm_start_proposal") < 0); checks += 1
	assert(not artifact.has("accepted_contact_age")); checks += 1
	assert(artifact_text.find("mode_transition_hypothesis") < 0); checks += 1

	# Caller/manifold ordering must not affect reduced identity.
	var reversed_points := points.duplicate(true)
	reversed_points.reverse()
	var reversed := Compiler.compile(base_request(reversed_points))
	assert(bool(reversed.get("ok", false))); checks += 1
	assert(String(reversed["model"]["model_hash"]) == String(artifact["model_hash"])); checks += 1
	assert(reversed["model"]["generators"] == artifact["generators"]); checks += 1

	# FULL manifold support function vs BAKED hull-generator support.
	var max_support_error := 0.0
	var max_projection_error := 0.0
	for direction in deterministic_directions():
		var full := full_support(request, direction)
		var baked := Runtime.support(artifact, direction)
		assert(bool(baked.get("ok", false))); checks += 1
		var error := absf(float(full["support"]) - float(baked["support"]))
		max_support_error = maxf(max_support_error, error)
		max_projection_error = maxf(max_projection_error, float(baked["projection_error"]))
		assert(error <= EPS * maxf(1.0, absf(float(full["support"])))); checks += 1
		assert(float(baked["projection_error"]) <= EPS * maxf(1.0, absf(float(baked["support"])))); checks += 1
		assert(bool(baked["noncanonical_witness"])); checks += 1

	# Boundary limits: support, friction, tipping, torsion are 6D wrench observables.
	var normal_cap := Runtime.support(artifact, [0.0, 0.0, 1.0, 0.0, 0.0, 0.0])
	assert(absf(float(normal_cap["support"]) - 12.0) < EPS); checks += 1
	var tangent_cap := Runtime.support(artifact, [1.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	assert(absf(float(tangent_cap["support"]) - 7.2) < EPS); checks += 1
	var tipping_x := Runtime.support(artifact, [0.0, 0.0, 0.0, 1.0, 0.0, 0.0])
	var tipping_y := Runtime.support(artifact, [0.0, 0.0, 0.0, 0.0, 1.0, 0.0])
	assert(float(tipping_x["support"]) > 8.9); checks += 1
	assert(float(tipping_y["support"]) > 11.9); checks += 1
	var torsion := Runtime.support(artifact, [0.0, 0.0, 0.0, 0.0, 0.0, 1.0])
	assert(float(torsion["support"]) > 8.0); checks += 1

	# Passive maximum-dissipation contact must never create positive boundary power.
	var max_contact_power := -INF
	for twist in [
		[1.0, 0.0, 0.0, 0.0, 0.0, 0.0],
		[0.0, -2.0, 0.0, 0.0, 0.0, 0.0],
		[0.2, -0.4, 0.0, 0.3, 0.0, 0.0],
		[0.1, 0.2, 0.0, 0.0, -0.5, 0.7],
		[0.8, -0.3, 0.0, 0.4, -0.2, 0.9],
	]:
		var dissipative := Runtime.maximum_dissipation_wrench(artifact, twist)
		assert(bool(dissipative.get("ok", false))); checks += 1
		max_contact_power = maxf(max_contact_power, float(dissipative["contact_power"]))
		assert(float(dissipative["contact_power"]) <= EPS); checks += 1
		assert(float(dissipative["dissipation"]) >= -EPS); checks += 1

	# Support-loss and over-capacity are explicit and distinct fail/transition surfaces.
	var live_guard := Runtime.normal_support_guard(artifact, 3.0)
	assert(bool(live_guard["persistent_contact_feasible"])); checks += 1
	assert(not bool(live_guard["separation_candidate"])); checks += 1
	assert(not bool(live_guard["capacity_exceeded"])); checks += 1
	var separation := Runtime.normal_support_guard(artifact, 0.0)
	assert(not bool(separation["persistent_contact_feasible"])); checks += 1
	assert(bool(separation["separation_candidate"])); checks += 1
	assert(String(separation["event_semantics"]) == "SUPPORT_TO_SEPARATION"); checks += 1
	var overload := Runtime.normal_support_guard(artifact, 12.5)
	assert(bool(overload["persistent_contact_feasible"])); checks += 1
	assert(bool(overload["capacity_exceeded"])); checks += 1
	assert(float(overload["capacity_margin"]) < 0.0); checks += 1

	# Tipping falsifier: unit normal support over x in [-1,1] cannot carry My demand > 1 without rolling reserve.
	var no_roll_request := base_request(points)
	no_roll_request["normal_support_limit"] = 1.0
	no_roll_request["mu_tangent"] = 0.0
	no_roll_request["mu_rolling"] = 0.0
	no_roll_request["mu_torsion"] = 0.0
	var no_roll := Compiler.compile(no_roll_request)
	assert(bool(no_roll.get("ok", false))); checks += 1
	var pure_my := Runtime.support(no_roll["model"], [0.0, 0.0, 0.0, 0.0, 1.0, 0.0])
	assert(absf(float(pure_my["support"]) - 1.0) < EPS); checks += 1
	assert(1.1 > float(pure_my["support"])); checks += 1
	var tipping_guard := Runtime.directional_wrench_guard(no_roll["model"], [0.0, 0.0, 0.0, 0.0, 1.0, 0.0], 0.9)
	assert(bool(tipping_guard.get("ok", false))); checks += 1
	assert(bool(tipping_guard["feasible"])); checks += 1
	assert(not bool(tipping_guard["refinement_required"])); checks += 1
	var tipping_exit := Runtime.directional_wrench_guard(no_roll["model"], [0.0, 0.0, 0.0, 0.0, 1.0, 0.0], 1.1)
	assert(bool(tipping_exit.get("ok", false))); checks += 1
	assert(not bool(tipping_exit["feasible"])); checks += 1
	assert(bool(tipping_exit["refinement_required"])); checks += 1
	assert(String(tipping_exit["event_semantics"]) == "WRENCH_CAPACITY_EXIT"); checks += 1

	# Fail closed: out-of-domain contact geometry or weak reduction is not silently approximated.
	var noncoplanar_points := points.duplicate(true)
	noncoplanar_points[220] = Dictionary(noncoplanar_points[220]).duplicate(true)
	noncoplanar_points[220]["position"] = Vector3(0.0, 0.0, 0.01)
	var noncoplanar := Compiler.compile(base_request(noncoplanar_points))
	assert(not bool(noncoplanar.get("ok", false))); checks += 1
	assert(String(noncoplanar.get("status", "")) == "NO_SAFE_BAKE"); checks += 1
	assert(String(noncoplanar.get("reason", "")) == "NON_COPLANAR_CONTACT_PATCH"); checks += 1
	var sparse_request := base_request([
		{"id": "p0", "position": Vector3(-1.0, -1.0, 0.0)},
		{"id": "p1", "position": Vector3(1.0, -1.0, 0.0)},
		{"id": "p2", "position": Vector3(1.0, 1.0, 0.0)},
		{"id": "p3", "position": Vector3(-1.0, 1.0, 0.0)},
	])
	var sparse := Compiler.compile(sparse_request)
	assert(not bool(sparse.get("ok", false))); checks += 1
	assert(String(sparse.get("reason", "")) == "INSUFFICIENT_CONTACT_REDUCTION"); checks += 1
	var bad_hash_request := base_request(points)
	bad_hash_request["physical_graph_hash"] = "bad"
	var bad_hash := Compiler.compile(bad_hash_request)
	assert(not bool(bad_hash.get("ok", false))); checks += 1
	assert(String(bad_hash.get("code", "")) == "B0_3_BAD_PROVENANCE_HASH"); checks += 1
	var bad_frame_request := base_request(points)
	bad_frame_request["t2"] = Vector3(0.0, -1.0, 0.0)
	var bad_frame := Compiler.compile(bad_frame_request)
	assert(not bool(bad_frame.get("ok", false))); checks += 1
	assert(String(bad_frame.get("code", "")) == "B0_3_LEFT_HANDED_CONTACT_FRAME"); checks += 1
	var leaked_state := artifact.duplicate(true)
	leaked_state["warm_start_persisted"] = true
	var leaked_check := Compiler.validate_model(leaked_state)
	assert(not bool(leaked_check.get("ok", false))); checks += 1
	assert(String(leaked_check.get("code", "")) == "B0_3_TRANSIENT_CONTACT_STATE_PERSISTED"); checks += 1
	var malformed_frame := artifact.duplicate(true)
	malformed_frame["normal"] = [0.0, 1.0]
	var malformed_check := Compiler.validate_model(malformed_frame)
	assert(not bool(malformed_check.get("ok", false))); checks += 1
	assert(String(malformed_check.get("code", "")) == "B0_3_BAD_MODEL_FRAME_VECTOR"); checks += 1
	var tampered := artifact.duplicate(true)
	tampered["normal_support_limit"] = 13.0
	var tampered_support := Runtime.support(tampered, [0.0, 0.0, 1.0, 0.0, 0.0, 0.0])
	assert(not bool(tampered_support.get("ok", false))); checks += 1
	assert(String(tampered_support.get("code", "")) == "B0_3_MODEL_HASH_MISMATCH"); checks += 1

	print("FABRIC-BAKE B0.3 Contact/Wrench Bake Acceptance: PASS (%d assertions) artifact=%s full=%d generators=%d ratio=%.3f max_support_error=%s max_projection_error=%s max_contact_power=%s" % [
		checks,
		String(artifact["model_hash"]),
		int(artifact["full_member_count"]),
		int(artifact["generator_count"]),
		float(artifact["reduction_ratio"]),
		String.num_scientific(max_support_error),
		String.num_scientific(max_projection_error),
		String.num_scientific(max_contact_power),
	])
	quit(0)

func base_request(points: Array) -> Dictionary:
	return {
		"model_id": "artifact/b0-3-contact-wrench",
		"patch_id": "contact-patch/b0-3-grid",
		"source_frontier_hash": H64_A,
		"physical_graph_hash": H64_B,
		"parent_artifact_checksum": H64_C,
		"authority_checksum": H64_D,
		"origin": Vector3.ZERO,
		"normal": Vector3(0.0, 0.0, 1.0),
		"t1": Vector3(1.0, 0.0, 0.0),
		"t2": Vector3(0.0, 1.0, 0.0),
		"points": points,
		"normal_support_limit": 12.0,
		"mu_tangent": 0.6,
		"mu_rolling": 0.08,
		"mu_torsion": 0.05,
		"effective_radius": 0.4,
		"minimum_reduction_ratio": 2.0,
	}

func grid_points(size: int, half_x: float, half_y: float) -> Array:
	var points: Array = []
	for iy in range(size):
		for ix in range(size):
			var x := lerpf(-half_x, half_x, float(ix) / float(size - 1))
			var y := lerpf(-half_y, half_y, float(iy) / float(size - 1))
			points.append({"id": "member/%03d/%03d" % [iy, ix], "position": Vector3(x, y, 0.0)})
	return points

func deterministic_directions() -> Array:
	var directions: Array = [
		[1.0,0.0,0.0,0.0,0.0,0.0], [-1.0,0.0,0.0,0.0,0.0,0.0],
		[0.0,1.0,0.0,0.0,0.0,0.0], [0.0,-1.0,0.0,0.0,0.0,0.0],
		[0.0,0.0,1.0,0.0,0.0,0.0], [0.0,0.0,-1.0,0.0,0.0,0.0],
		[0.0,0.0,0.0,1.0,0.0,0.0], [0.0,0.0,0.0,-1.0,0.0,0.0],
		[0.0,0.0,0.0,0.0,1.0,0.0], [0.0,0.0,0.0,0.0,-1.0,0.0],
		[0.0,0.0,0.0,0.0,0.0,1.0], [0.0,0.0,0.0,0.0,0.0,-1.0],
	]
	for i in range(1, 49):
		var a := float((i * 17) % 23 - 11) / 7.0
		var b := float((i * 29) % 31 - 15) / 9.0
		var c := float((i * 13) % 19 - 9) / 5.0
		var d := float((i * 7) % 17 - 8) / 6.0
		var e := float((i * 11) % 29 - 14) / 8.0
		var f := float((i * 5) % 13 - 6) / 4.0
		directions.append([a,b,c,d,e,f])
	return directions

func full_support(request: Dictionary, direction: Array) -> Dictionary:
	var qf := Vector3(float(direction[0]), float(direction[1]), float(direction[2]))
	var qm := Vector3(float(direction[3]), float(direction[4]), float(direction[5]))
	var origin: Vector3 = request["origin"]
	var n: Vector3 = request["normal"]
	var t1: Vector3 = request["t1"]
	var t2: Vector3 = request["t2"]
	var mu_t := float(request["mu_tangent"])
	var mu_r := float(request["mu_rolling"])
	var mu_tau := float(request["mu_torsion"])
	var reff := float(request["effective_radius"])
	var best_score := 0.0
	var best_id := ""
	for point_any in request["points"]:
		var point: Dictionary = point_any
		var r: Vector3 = Vector3(point["position"]) - origin
		var force_query := qf + qm.cross(r)
		var tangent_query := Vector2(force_query.dot(t1), force_query.dot(t2))
		var rolling_query := Vector2(qm.dot(t1), qm.dot(t2))
		var score := force_query.dot(n) + mu_t * tangent_query.length() + mu_r * reff * rolling_query.length() + mu_tau * reff * absf(qm.dot(n))
		if score > best_score + 1.0e-12 or (absf(score - best_score) <= 1.0e-12 and (best_id.is_empty() or String(point["id"]) < best_id)):
			best_score = score
			best_id = String(point["id"])
	return {"support": maxf(0.0, best_score) * float(request["normal_support_limit"]), "member_id": best_id}
