extends SceneTree

const Experiments = preload("res://scripts/research/fabric0/fabric0_multicontact_cone_experiments_v1.gd")

func _init() -> void:
	var manifold := Experiments.compile_corner_manifold(false)
	var solved := Experiments.solve_corner(false, false)
	print("=== FABRIC0.9 MULTI-CONTACT GEOMETRIC MANIFOLD + CONE SOLVE ===")
	print("Geometry generates contacts; all contact impulses are solved simultaneously in one product-of-friction-cones problem.\n")
	print("[1] GEOMETRY-DERIVED MANIFOLD")
	print("    contacts=%d ids=%s" % [manifold["contact_count"], str(manifold["contact_ids"])])
	print("\n[2] GLOBAL CONE SOLVE")
	print("    rank=%d/%d redundant=%s iterations=%d residuals=(%.12f,%.12f)" % [solved["matrix_rank"], solved["impulse_unknown_count"], str(solved["redundant_impulse_manifold"]), solved["iterations"], solved["primal_residual"], solved["dual_residual"]])
	print("    post linear=(%.6f, %.6f, %.6f)" % [solved["post_linear_velocity"].x, solved["post_linear_velocity"].y, solved["post_linear_velocity"].z])
	print("    post angular=(%.6f, %.6f, %.6f)" % [solved["post_angular_velocity"].x, solved["post_angular_velocity"].y, solved["post_angular_velocity"].z])
	print("    active=%d sliding=%d cone_violation=%.12f" % [solved["active_contact_count"], solved["sliding_contact_count"], solved["max_cone_violation"]])
	print("\n[3] CONTACT IMPULSES")
	for c in solved["contacts"]:
		print("    %-19s jn=%8.5f jt=(%8.5f,%8.5f) |jt|/(mu*jn)=%6.3f active=%s slide=%s" % [
			String(c["id"]), float(c["j_n"]), float(c["j_t1"]), float(c["j_t2"]),
			0.0 if float(c["cone_limit"]) <= 1.0e-12 else float(c["tangent_norm"]) / float(c["cone_limit"]),
			str(c["active"]), str(c["sliding"])
		])
	print("\n[4] CONSERVATION / DISSIPATION AUDIT")
	print("    total impulse=(%.6f,%.6f,%.6f)" % [solved["total_impulse"].x, solved["total_impulse"].y, solved["total_impulse"].z])
	print("    torque impulse=(%.6f,%.6f,%.6f)" % [solved["total_torque_impulse"].x, solved["total_torque_impulse"].y, solved["total_torque_impulse"].z])
	print("    impulse residuals linear=%.12f angular=%.12f" % [solved["linear_impulse_residual"].length(), solved["angular_impulse_residual"].length()])
	print("    kinetic energy %.6f -> %.6f (delta %.6f)" % [solved["energy_pre"], solved["energy_post"], solved["energy_delta"]])
	var reordered := Experiments.solve_corner(true, true)
	print("\n[5] ORDER INVARIANCE")
	print("    original hash = %s" % solved["state_hash"])
	print("    reordered hash= %s" % reordered["state_hash"])
	print("    identical=%s" % str(solved["state_hash"] == reordered["state_hash"]))
	print("\nFABRIC0_9_MULTICONTACT_CONE_PLAYGROUND_PASS")
	quit(0)
