extends SceneTree

const Fabric = preload("res://scripts/research/fabric0/fabric0_coupled_hybrid_dae_v1.gd")
const Experiments = preload("res://scripts/research/fabric0/fabric0_coupled_hybrid_dae_experiments_v1.gd")

func _init() -> void:
	var s := Experiments.build_two_body_impact()
	Fabric.solve_algebraic(s)
	print("=== FABRIC0.8 COUPLED HYBRID DAE / EVENT ITERATION ===")
	print("Differential state and algebraic force are solved together at every RK stage; impact is a branch-based jump solve.\n")
	print("[1] PRE-IMPACT DAE")
	print("    x=(%.3f,%.3f) vn=(%.3f,%.3f) algebraic_force=(%.3f,%.3f) drive_link=%s" % [Fabric.read_state(s,"x_a"),Fabric.read_state(s,"x_b"),Fabric.read_state(s,"v_n_a"),Fabric.read_state(s,"v_n_b"),Fabric.read_algebraic(s,"f_a"),Fabric.read_algebraic(s,"f_b"),str(Experiments.bond_active(s,"drive_link"))])
	var result := Fabric.advance(s,1.0)
	var instant:Dictionary=s["events"][0]
	var impact:Dictionary=instant["transitions"][0]
	var broken:Dictionary=instant["transitions"][1]
	print("\n[2] LOCALIZED GEOMETRIC IMPACT")
	print("    event_time=%.12f gap_pre=%.12f branch=%s" % [instant["time"], impact["pre_states"]["x_b"]-impact["pre_states"]["x_a"], impact["jump_branch"]])
	print("    normal: pre_rel=%.6f post_rel=%.6f jn=%.6f" % [impact["pre_states"]["v_n_b"]-impact["pre_states"]["v_n_a"],impact["post_states"]["v_n_b"]-impact["post_states"]["v_n_a"],impact["jump_values"]["j_n"]])
	print("    tangent: pre_rel=%.6f post_rel=%.6f jt=%.6f mu*jn=%.6f" % [impact["pre_states"]["v_t_b"]-impact["pre_states"]["v_t_a"],impact["post_states"]["v_t_b"]-impact["post_states"]["v_t_a"],impact["jump_values"]["j_t"],0.3*impact["jump_values"]["j_n"]])
	print("\n[3] SAME-TIME EVENT ITERATION")
	print("    transitions=%d : %s -> %s" % [instant["transitions"].size(), impact["transition_id"], broken["transition_id"]])
	print("    algebraic f_a after impact-before-break=%.3f" % impact["post_algebraics"]["f_a"])
	print("    algebraic f_a after break/recompile=%.3f" % broken["post_algebraics"]["f_a"])
	print("    drive_link=%s topology_revision=%d mode=%s" % [str(Experiments.bond_active(s,"drive_link")),s["topology_revision"],Fabric.read_mode(s)])
	print("\n[4] REMAINING FLOW AFTER RECOMPILE")
	print("    final t=%.3f x=(%.6f,%.6f) vn=(%.6f,%.6f) gap=%.6f" % [s["time"],Fabric.read_state(s,"x_a"),Fabric.read_state(s,"x_b"),Fabric.read_state(s,"v_n_a"),Fabric.read_state(s,"v_n_b"),Fabric.read_state(s,"x_b")-Fabric.read_state(s,"x_a")])
	print("    algebraic_solve_calls=%d event_iterations=%d" % [result["solver_stats"]["algebraic_solves"],result["solver_stats"]["event_iterations"]])
	print("\n    deterministic state hash: %s" % Fabric.state_hash(s))
	print("\nFABRIC0_8_COUPLED_HYBRID_DAE_PLAYGROUND_PASS")
	quit(0)
