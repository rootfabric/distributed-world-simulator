extends SceneTree

const Fabric = preload("res://scripts/research/fabric0/fabric0_multicontact_cone_v1.gd")
const Experiments = preload("res://scripts/research/fabric0/fabric0_multicontact_cone_experiments_v1.gd")

func close(a: float, b: float, tolerance: float = 1.0e-7) -> bool:
	return absf(a - b) <= tolerance

func close_vec(a: Vector3, b: Vector3, tolerance: float = 1.0e-7) -> bool:
	return (a - b).length() <= tolerance

func _init() -> void:
	var checks := 0

	# Geometry compiler: two static planes touching one oriented box generate
	# one global, canonically identified 8-contact manifold.
	var manifold := Experiments.compile_corner_manifold(false)
	assert(bool(manifold["ok"])); checks += 1
	assert(int(manifold["contact_count"]) == 8); checks += 1
	assert(manifold["diagnostics"].is_empty()); checks += 1
	var expected_ids := [
		"floor::mx_my_mz", "floor::mx_my_pz", "floor::px_my_mz", "floor::px_my_pz",
		"wall::mx_my_mz", "wall::mx_my_pz", "wall::mx_py_mz", "wall::mx_py_pz",
	]
	assert(manifold["contact_ids"] == expected_ids); checks += 1

	# Plane enumeration order must not change manifold identity/order.
	var reversed_planes := Experiments.compile_corner_manifold(true)
	assert(bool(reversed_planes["ok"])); checks += 1
	assert(reversed_planes["contact_ids"] == expected_ids); checks += 1

	# Every generated contact basis is orthonormal and right-handed enough for
	# stable Jacobian assembly.
	for contact in manifold["contacts"]:
		var n: Vector3 = contact["normal"]
		var t1: Vector3 = contact["tangent_1"]
		var t2: Vector3 = contact["tangent_2"]
		assert(close(n.length(), 1.0, 1.0e-12)); checks += 1
		assert(close(t1.length(), 1.0, 1.0e-12)); checks += 1
		assert(close(t2.length(), 1.0, 1.0e-12)); checks += 1
		assert(absf(n.dot(t1)) <= 1.0e-12); checks += 1
		assert(absf(n.dot(t2)) <= 1.0e-12); checks += 1
		assert(absf(t1.dot(t2)) <= 1.0e-12); checks += 1

	var solved := Experiments.solve_corner(false, false)
	assert(bool(solved["ok"])); checks += 1
	assert(int(solved["contact_count"]) == 8); checks += 1
	assert(int(solved["active_contact_count"]) == 5); checks += 1
	assert(int(solved["sliding_contact_count"]) == 5); checks += 1
	assert(int(solved["matrix_rank"]) == 6); checks += 1
	assert(int(solved["impulse_unknown_count"]) == 24); checks += 1
	assert(bool(solved["redundant_impulse_manifold"])); checks += 1
	assert(int(solved["iterations"]) > 10 and int(solved["iterations"]) < 12000); checks += 1
	assert(float(solved["primal_residual"]) <= 1.0e-9); checks += 1
	assert(float(solved["dual_residual"]) <= 1.0e-9); checks += 1
	assert(float(solved["max_cone_violation"]) <= 2.0e-9); checks += 1

	# Exact-double numerical reference for this 8-contact floor+wall solve.
	assert(close_vec(solved["post_linear_velocity"], Vector3(0.58972105, 0.77679777, 0.23871175), 2.0e-7)); checks += 1
	assert(close_vec(solved["post_angular_velocity"], Vector3(-0.07479735, -0.02246894, 0.12224265), 2.0e-7)); checks += 1
	assert(close_vec(solved["total_impulse"], Vector3(5.17944211, 7.55359555, -1.52257649), 3.0e-7)); checks += 1
	assert(close_vec(solved["total_torque_impulse"], Vector3(-0.23739868, -0.26696273, 0.57779412), 3.0e-7)); checks += 1

	# Impulse-momentum audit including angular momentum through the world-space
	# diagonal inertia used by this research checkpoint.
	assert(solved["linear_impulse_residual"].length() <= 1.0e-9); checks += 1
	assert(solved["angular_impulse_residual"].length() <= 1.0e-9); checks += 1
	assert(close(float(solved["energy_pre"]), 14.208, 1.0e-9)); checks += 1
	assert(close(float(solved["energy_post"]), 1.01584788, 3.0e-7)); checks += 1
	assert(float(solved["energy_delta"]) < -13.0); checks += 1

	# All contacts are separating/non-penetrating after the simultaneous solve.
	for contact_result in solved["contacts"]:
		var post_v: Vector3 = contact_result["post_contact_velocity"]
		assert(post_v.x >= -2.0e-8); checks += 1
		var jn := float(contact_result["j_n"])
		var jt := float(contact_result["tangent_norm"])
		var limit := float(contact_result["cone_limit"])
		assert(jn >= -2.0e-9); checks += 1
		assert(jt <= limit + 2.0e-9); checks += 1

	# At least one contact on each independent surface participates, proving this
	# is a coupled multi-surface solve rather than four copies of one plane.
	var floor_active := 0
	var wall_active := 0
	for contact_result in solved["contacts"]:
		if bool(contact_result["active"]):
			if String(contact_result["plane_id"]) == "floor": floor_active += 1
			if String(contact_result["plane_id"]) == "wall": wall_active += 1
	assert(floor_active >= 2); checks += 1
	assert(wall_active >= 2); checks += 1

	# Critical FABRIC0.9 criterion: input enumeration order is not physical truth.
	# Reverse contacts, reverse planes, and demand the same canonical result.
	var reverse_contacts := Experiments.solve_corner(true, false)
	var reverse_everything := Experiments.solve_corner(true, true)
	assert(bool(reverse_contacts["ok"])); checks += 1
	assert(bool(reverse_everything["ok"])); checks += 1
	assert(close_vec(reverse_contacts["post_linear_velocity"], solved["post_linear_velocity"], 1.0e-12)); checks += 1
	assert(close_vec(reverse_contacts["post_angular_velocity"], solved["post_angular_velocity"], 1.0e-12)); checks += 1
	assert(close_vec(reverse_everything["post_linear_velocity"], solved["post_linear_velocity"], 1.0e-12)); checks += 1
	assert(close_vec(reverse_everything["post_angular_velocity"], solved["post_angular_velocity"], 1.0e-12)); checks += 1
	assert(String(reverse_contacts["state_hash"]) == String(solved["state_hash"])); checks += 1
	assert(String(reverse_everything["state_hash"]) == String(solved["state_hash"])); checks += 1

	# Contact impulse map is canonical by stable geometry identity as well.
	for contact_id in expected_ids:
		var a: Dictionary = solved["impulse_by_id"][contact_id]
		var b: Dictionary = reverse_everything["impulse_by_id"][contact_id]
		assert(close(float(a["j_n"]), float(b["j_n"]), 1.0e-12)); checks += 1
		assert(close(float(a["j_t1"]), float(b["j_t1"]), 1.0e-12)); checks += 1
		assert(close(float(a["j_t2"]), float(b["j_t2"]), 1.0e-12)); checks += 1

	# Fail closed on invalid geometry/physics metadata.
	var bad_body := Experiments.build_corner_body()
	bad_body["mass"] = 0.0
	var bad_manifold := Fabric.compile_box_plane_manifold(bad_body, Experiments.build_corner_planes())
	assert(not bool(bad_manifold["ok"])); checks += 1
	assert(String(bad_manifold["code"]) == "BODY_MASS_NONPOSITIVE"); checks += 1
	var bad_plane := Fabric.new_plane("bad", Vector3.ZERO, 0.0, 0.2, 0.0)
	var bad_plane_result := Fabric.compile_box_plane_manifold(Experiments.build_corner_body(), [bad_plane])
	assert(not bool(bad_plane_result["ok"])); checks += 1
	assert(String(bad_plane_result["code"]) == "PLANE_NORMAL_ZERO"); checks += 1

	print("FABRIC0.9 Multi-Contact Cone Acceptance: PASS (%d assertions) contacts=%d active=%d sliding=%d rank=%d/%d iters=%d post_v=(%.9f,%.9f,%.9f) post_w=(%.9f,%.9f,%.9f) E=%.9f->%.9f hash=%s" % [
		checks,
		int(solved["contact_count"]),
		int(solved["active_contact_count"]),
		int(solved["sliding_contact_count"]),
		int(solved["matrix_rank"]),
		int(solved["impulse_unknown_count"]),
		int(solved["iterations"]),
		solved["post_linear_velocity"].x,
		solved["post_linear_velocity"].y,
		solved["post_linear_velocity"].z,
		solved["post_angular_velocity"].x,
		solved["post_angular_velocity"].y,
		solved["post_angular_velocity"].z,
		float(solved["energy_pre"]),
		float(solved["energy_post"]),
		String(solved["state_hash"]),
	])
	quit(0)
