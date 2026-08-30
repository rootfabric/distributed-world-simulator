extends SceneTree

const Fabric = preload("res://scripts/research/fabric0/fabric0_coupled_hybrid_dae_v1.gd")
const Experiments = preload("res://scripts/research/fabric0/fabric0_coupled_hybrid_dae_experiments_v1.gd")

func close(a: float, b: float, tol: float = 1.0e-8) -> bool:
	return absf(a-b) <= tol

func _init() -> void:
	var checks := 0

	# DAE dimensions fail closed.
	var bad := Fabric.new_system()
	assert(Fabric.add_state(bad, "x", 0.0, Fabric.dim_length())); checks += 1
	assert(Fabric.add_algebraic(bad, "f", 0.0, Fabric.dim_force())); checks += 1
	assert(not Fabric.add_mode(bad, "bad", {"x":Fabric.expr_algebraic("f")}, [Fabric.residual(Fabric.expr_algebraic("f"),1.0)])); checks += 1
	assert(String(bad["diagnostics"][0]["code"]) == "DAE_FLOW_DIMENSION_MISMATCH"); checks += 1

	var system := Experiments.build_two_body_impact()
	assert(Experiments.bond_active(system, "drive_link")); checks += 1
	var algebraic0 := Fabric.solve_algebraic(system)
	assert(bool(algebraic0["ok"])); checks += 1
	assert(close(Fabric.read_algebraic(system,"f_a"),2.0)); checks += 1
	assert(close(Fabric.read_algebraic(system,"f_b"),0.0)); checks += 1

	# One macrostep crosses geometry, solves impulse/friction, runs same-time event iteration,
	# recompiles the DAE after topology break, then completes the remaining flow.
	var result := Fabric.advance(system, 1.0)
	assert(bool(result["ok"])); checks += 1
	assert(int(result["events"]) == 1); checks += 1
	assert(system["events"].size() == 1); checks += 1
	assert(int(result["solver_stats"]["algebraic_solves"]) > 20); checks += 1
	assert(int(result["solver_stats"]["event_iterations"]) >= 3); checks += 1
	assert(int(result["solver_stats"]["localized_events"]) == 1); checks += 1

	var instant: Dictionary = system["events"][0]
	assert(String(instant["event_id"]) == "fabric0/instant/000001"); checks += 1
	assert(close(float(instant["time"]), -4.0 + sqrt(20.0), 2.0e-9)); checks += 1
	assert(instant["transitions"].size() == 2); checks += 1
	assert(String(instant["transitions"][0]["transition_id"]) == "impact"); checks += 1
	assert(String(instant["transitions"][1]["transition_id"]) == "break_on_impulse"); checks += 1

	var impact: Dictionary = instant["transitions"][0]
	assert(String(impact["jump_branch"]) == "slide_neg"); checks += 1
	var pre: Dictionary = impact["pre_states"]
	var post: Dictionary = impact["post_states"]
	var jump: Dictionary = impact["jump_values"]
	var t_hit := -4.0 + sqrt(20.0)
	var expected_x := 3.0*t_hit + 0.5*t_hit*t_hit
	var expected_pre_va := 3.0 + t_hit
	var expected_vrel := -1.0 - expected_pre_va
	var expected_jn := -(1.0+0.5)*expected_vrel/(1.0/2.0+1.0)
	var expected_jt := 0.3*expected_jn
	assert(close(float(pre["x_a"]), expected_x, 2.0e-8)); checks += 1
	assert(close(float(pre["x_b"]), expected_x, 2.0e-8)); checks += 1
	assert(close(float(pre["v_n_a"]), expected_pre_va, 2.0e-8)); checks += 1
	assert(close(float(pre["v_n_b"]), -1.0)); checks += 1
	assert(close(float(jump["j_n"]), expected_jn, 2.0e-8)); checks += 1
	assert(close(float(jump["j_t"]), expected_jt, 2.0e-8)); checks += 1
	assert(float(jump["j_n"]) > 4.0); checks += 1

	# Jump conserves total linear momentum while enforcing restitution in normal direction.
	var p_n_pre := 2.0*float(pre["v_n_a"]) + float(pre["v_n_b"])
	var p_n_post := 2.0*float(post["v_n_a"]) + float(post["v_n_b"])
	assert(close(p_n_pre,p_n_post,2.0e-8)); checks += 1
	var rel_pre := float(pre["v_n_b"])-float(pre["v_n_a"])
	var rel_post := float(post["v_n_b"])-float(post["v_n_a"])
	assert(close(rel_post,-0.5*rel_pre,2.0e-8)); checks += 1
	assert(rel_pre < 0.0 and rel_post > 0.0); checks += 1

	# Tangential impulse lies exactly on the Coulomb cone and conserves tangential momentum.
	var p_t_pre := 2.0*float(pre["v_t_a"]) + float(pre["v_t_b"])
	var p_t_post := 2.0*float(post["v_t_a"]) + float(post["v_t_b"])
	assert(close(p_t_pre,p_t_post,2.0e-8)); checks += 1
	assert(close(float(jump["j_t"]),0.3*float(jump["j_n"]),2.0e-8)); checks += 1
	assert(float(post["v_t_b"])-float(post["v_t_a"]) < 0.0); checks += 1
	assert(close(float(post["last_j_n"]),float(jump["j_n"]),2.0e-8)); checks += 1
	assert(close(float(post["last_j_t"]),float(jump["j_t"]),2.0e-8)); checks += 1

	# Impact dissipates kinetic energy for e<1 and sliding friction; it must not create energy.
	var ke_pre := 0.5*2.0*(pow(float(pre["v_n_a"]),2.0)+pow(float(pre["v_t_a"]),2.0)) + 0.5*(pow(float(pre["v_n_b"]),2.0)+pow(float(pre["v_t_b"]),2.0))
	var ke_post := 0.5*2.0*(pow(float(post["v_n_a"]),2.0)+pow(float(post["v_t_a"]),2.0)) + 0.5*(pow(float(post["v_n_b"]),2.0)+pow(float(post["v_t_b"]),2.0))
	assert(ke_post < ke_pre); checks += 1
	assert(ke_pre-ke_post > 1.0); checks += 1

	# Same-time iteration: first jump still sees the live drive; the second transition breaks it,
	# and the algebraic force is re-solved to zero at the exact same physical time.
	assert(close(float(impact["post_algebraics"]["f_a"]),2.0)); checks += 1
	var broken: Dictionary = instant["transitions"][1]
	assert(close(float(broken["post_algebraics"]["f_a"]),0.0)); checks += 1
	assert(int(broken["topology_revision_before"]) == 0); checks += 1
	assert(int(broken["topology_revision_after"]) == 1); checks += 1
	assert(not Experiments.bond_active(system,"drive_link")); checks += 1
	assert(Fabric.read_mode(system) == "broken"); checks += 1
	assert(close(Fabric.read_algebraic(system,"f_a"),0.0)); checks += 1
	assert(close(Fabric.read_algebraic(system,"f_b"),0.0)); checks += 1

	# Remaining flow uses the recompiled broken topology, so post-impact normal velocities stay constant.
	var remain := 1.0-t_hit
	var expected_va_post := expected_pre_va-expected_jn/2.0
	var expected_vb_post := -1.0+expected_jn
	var expected_xa_final := expected_x+expected_va_post*remain
	var expected_xb_final := expected_x+expected_vb_post*remain
	assert(close(Fabric.read_state(system,"v_n_a"),expected_va_post,2.0e-8)); checks += 1
	assert(close(Fabric.read_state(system,"v_n_b"),expected_vb_post,2.0e-8)); checks += 1
	assert(close(Fabric.read_state(system,"x_a"),expected_xa_final,3.0e-8)); checks += 1
	assert(close(Fabric.read_state(system,"x_b"),expected_xb_final,3.0e-8)); checks += 1
	assert(Fabric.read_state(system,"x_b")-Fabric.read_state(system,"x_a") > 1.0); checks += 1
	assert(close(float(system["time"]),1.0,1.0e-12)); checks += 1
	assert(int(system["topology_revision"]) == 1); checks += 1

	# Event surfaces can depend directly on a solved algebraic reaction, not only differential state.
	var reaction_guard := Experiments.build_algebraic_guard()
	var rg := Fabric.advance(reaction_guard,1.5)
	assert(bool(rg["ok"])); checks += 1
	assert(int(rg["events"]) == 1); checks += 1
	assert(Fabric.read_mode(reaction_guard) == "high"); checks += 1
	assert(close(float(reaction_guard["events"][0]["time"]),1.0,2.0e-9)); checks += 1
	assert(String(reaction_guard["events"][0]["transitions"][0]["transition_id"]) == "reaction_threshold"); checks += 1
	assert(close(float(reaction_guard["events"][0]["transitions"][0]["pre_algebraics"]["reaction"]),2.0,2.0e-8)); checks += 1
	assert(close(Fabric.read_state(reaction_guard,"x"),1.5,2.0e-8)); checks += 1
	assert(close(Fabric.read_algebraic(reaction_guard,"reaction"),3.0,2.0e-8)); checks += 1
	assert(int(rg["solver_stats"]["algebraic_solves"]) > 10); checks += 1

	# Zero residual is not enough: a rank-deficient algebraic manifold is rejected.
	var singular := Fabric.new_system()
	assert(Fabric.add_algebraic(singular,"y",0.0,Fabric.dim_force(),1.0)); checks += 1
	var zero_force := Fabric.expr_mul(Fabric.expr_algebraic("y"),Fabric.expr_constant(0.0,Fabric.dim_dimensionless()))
	assert(Fabric.add_mode(singular,"floating",{},[Fabric.residual(zero_force,1.0)])); checks += 1
	assert(Fabric.set_initial_mode(singular,"floating")); checks += 1
	var singular_result := Fabric.solve_algebraic(singular)
	assert(not bool(singular_result["ok"])); checks += 1
	assert(String(singular_result["code"]) == "DAE_SINGULAR_ALGEBRAIC_MANIFOLD"); checks += 1

	# Deterministic coupled replay includes same event instant, branch, impulse and topology history.
	var replay_a := Experiments.build_two_body_impact()
	var replay_b := Experiments.build_two_body_impact()
	assert(bool(Fabric.advance(replay_a,1.0)["ok"])); checks += 1
	assert(bool(Fabric.advance(replay_b,1.0)["ok"])); checks += 1
	assert(Fabric.state_hash(replay_a).length() == 64); checks += 1
	assert(Fabric.state_hash(replay_a) == Fabric.state_hash(replay_b)); checks += 1
	assert(JSON.stringify(replay_a["events"]) == JSON.stringify(replay_b["events"])); checks += 1

	print("FABRIC0.8 Coupled Hybrid DAE Acceptance: PASS (%d assertions) t_hit=%.12f jn=%.9f jt=%.9f branch=%s same_time=%d fa_after=%.3f gap_final=%.9f hash=%s" % [
		checks,
		float(instant["time"]),
		float(jump["j_n"]),
		float(jump["j_t"]),
		String(impact["jump_branch"]),
		instant["transitions"].size(),
		Fabric.read_algebraic(system,"f_a"),
		Fabric.read_state(system,"x_b")-Fabric.read_state(system,"x_a"),
		Fabric.state_hash(replay_a),
	])
	quit(0)
