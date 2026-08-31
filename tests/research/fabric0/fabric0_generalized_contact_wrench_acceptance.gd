extends SceneTree

const F=preload("res://scripts/research/fabric0/fabric0_general_convex_multipoint_mcp_v1.gd")
const W=preload("res://scripts/research/fabric0/fabric0_generalized_contact_wrench_v1.gd")
const E=preload("res://scripts/research/fabric0/fabric0_generalized_contact_wrench_experiments_v1.gd")

func close(a:float,b:float,tolerance:float)->bool:
	return absf(a-b)<=tolerance

func vec5_max_abs(values:Array)->float:
	var maximum:=0.0
	for value in values:maximum=maxf(maximum,absf(float(value)))
	return maximum

func _init()->void:
	var checks:=0

	# High support budget: all five generalized friction velocities stick to zero.
	var stick:=E.stick_probe()
	assert(bool(stick["ok"]));checks+=1
	assert(String(stick["kind"])=="GENERALIZED_CONTACT_WRENCH");checks+=1
	assert(String(stick["pair_id"])=="A|B");checks+=1
	assert(int(stick["patch"]["point_count"])==4);checks+=1
	assert(close(float(stick["patch"]["effective_radius"]),sqrt(0.5),1.0e-12));checks+=1
	assert(String(stick["modes"]["tangent"])=="stick");checks+=1
	assert(String(stick["modes"]["rolling"])=="stick");checks+=1
	assert(String(stick["modes"]["torsion"])=="stick");checks+=1
	assert(vec5_max_abs(stick["generalized_velocity_after"])<7.0e-12);checks+=1
	assert(float(stick["matrix_symmetry_error"])<1.0e-14);checks+=1
	assert(float(stick["projected_residual"])<1.1e-12);checks+=1
	assert(float(stick["energy_delta"])<0.0);checks+=1
	assert(float(stick["energy_ledger_error"])<1.0e-14);checks+=1
	assert(float(stick["linear_momentum_error"])<1.0e-14);checks+=1
	assert(float(stick["angular_momentum_error"])<1.0e-14);checks+=1
	assert(bool(stick["normal_support_resolved_externally"]));checks+=1

	# Low support budget: tangent, rolling and torsion independently reach their admissible bounds.
	var saturated:=E.saturated_probe()
	assert(bool(saturated["ok"]));checks+=1
	assert(String(saturated["modes"]["tangent"])=="slide");checks+=1
	assert(String(saturated["modes"]["rolling"])=="roll");checks+=1
	assert(String(saturated["modes"]["torsion"])=="spin");checks+=1
	var z:Array=saturated["generalized_impulse"]
	var tangent_mag:=Vector2(float(z[0]),float(z[1])).length()
	var rolling_mag:=Vector2(float(z[2]),float(z[3])).length()
	var torsion_mag:=absf(float(z[4]))
	assert(close(tangent_mag,float(saturated["limits"]["tangent"]),1.0e-12));checks+=1
	assert(close(rolling_mag,float(saturated["limits"]["rolling"]),1.0e-12));checks+=1
	assert(close(torsion_mag,float(saturated["limits"]["torsion"]),1.0e-12));checks+=1
	assert(close(float(saturated["limits"]["tangent"]),0.5,1.0e-12));checks+=1
	assert(close(float(saturated["limits"]["rolling"]),0.11313708498985,1.0e-12));checks+=1
	assert(close(float(saturated["limits"]["torsion"]),0.07071067811865,1.0e-12));checks+=1
	assert(float(saturated["energy_delta"])<-3.3);checks+=1
	assert(close(float(saturated["energy_delta"]),float(saturated["predicted_energy_delta"]),1.0e-13));checks+=1
	assert(float(saturated["energy_ledger_error"])<1.0e-13);checks+=1
	assert(float(saturated["linear_momentum_error"])<1.0e-14);checks+=1
	assert(float(saturated["angular_momentum_error"])<1.0e-14);checks+=1
	assert(float(saturated["matrix_symmetry_error"])<1.0e-14);checks+=1
	assert(Vector3(saturated["applied_wrench_impulse"]["force"]).length()>0.49);checks+=1
	assert(Vector3(saturated["applied_wrench_impulse"]["moment"]).length()>0.13);checks+=1

	# Canonical pair/body identity: reversing caller order cannot change the physical result.
	var sat_reverse_bodies:=E.saturated_probe(true,false)
	var sat_reverse_pair:=E.saturated_probe(false,true)
	assert(bool(sat_reverse_bodies["ok"]) and bool(sat_reverse_pair["ok"]));checks+=1
	assert(String(sat_reverse_bodies["signature"])==String(saturated["signature"]));checks+=1
	assert(String(sat_reverse_pair["signature"])==String(saturated["signature"]));checks+=1
	assert(E.state_error(sat_reverse_bodies["state"],saturated["state"])==0.0);checks+=1
	assert(E.state_error(sat_reverse_pair["state"],saturated["state"])==0.0);checks+=1

	# Pure rotational resistance: no tangent force is required to carry rolling/torsional moment.
	var moment:=E.pure_moment_probe()
	assert(bool(moment["ok"]));checks+=1
	assert(String(moment["modes"]["tangent"])=="unconstrained");checks+=1
	assert(String(moment["modes"]["rolling"])=="roll");checks+=1
	assert(String(moment["modes"]["torsion"])=="spin");checks+=1
	assert(Vector3(moment["applied_wrench_impulse"]["force"]).length()==0.0);checks+=1
	assert(Vector3(moment["applied_wrench_impulse"]["moment"]).length()>0.2);checks+=1
	assert(float(moment["energy_delta"])<0.0);checks+=1
	assert(float(moment["linear_momentum_error"])==0.0);checks+=1
	assert(float(moment["angular_momentum_error"])<1.0e-14);checks+=1
	assert(float(moment["energy_ledger_error"])<1.0e-14);checks+=1

	# Pure point friction: rotational-moment channels can be disabled independently.
	var tangent:=E.pure_tangent_probe()
	assert(bool(tangent["ok"]));checks+=1
	assert(String(tangent["modes"]["tangent"])=="slide");checks+=1
	assert(String(tangent["modes"]["rolling"])=="unconstrained");checks+=1
	assert(String(tangent["modes"]["torsion"])=="unconstrained");checks+=1
	assert(Vector3(tangent["applied_wrench_impulse"]["force"]).length()>0.59);checks+=1
	assert(Vector3(tangent["applied_wrench_impulse"]["moment"]).length()==0.0);checks+=1
	assert(float(tangent["energy_delta"])<0.0);checks+=1
	assert(float(tangent["linear_momentum_error"])<1.0e-14);checks+=1
	assert(float(tangent["angular_momentum_error"])<1.0e-14);checks+=1

	# Zero normal support means zero admissible friction wrench and exact state preservation.
	var zero:=E.zero_budget_probe()
	assert(bool(zero["ok"]));checks+=1
	assert(Vector3(zero["applied_wrench_impulse"]["force"]).length()==0.0);checks+=1
	assert(Vector3(zero["applied_wrench_impulse"]["moment"]).length()==0.0);checks+=1
	assert(float(zero["energy_delta"])==0.0);checks+=1
	assert(float(zero["energy_ledger_error"])==0.0);checks+=1
	for value in zero["generalized_impulse"]:assert(float(value)==0.0);checks+=1

	# Fail-closed contract surface.
	var fixture:=E._fixture(Vector3.ZERO,Vector3.ZERO)
	var bodies:Array=fixture["bodies"]
	var manifold:Dictionary=fixture["manifold"]
	var negative_normal:=W.solve_patch(bodies,"A","B",manifold,-1.0)
	assert(not bool(negative_normal["ok"]) and String(negative_normal["code"])=="NEGATIVE_NORMAL_IMPULSE");checks+=1
	var negative_mu:=W.solve_patch(bodies,"A","B",manifold,1.0,{"mu_rolling":-0.1})
	assert(not bool(negative_mu["ok"]) and String(negative_mu["code"])=="NEGATIVE_FRICTION_COEFFICIENT");checks+=1
	var missing:=W.solve_patch(bodies,"A","Q",manifold,1.0)
	assert(not bool(missing["ok"]) and String(missing["code"])=="BODY_NOT_FOUND");checks+=1
	var same:=W.solve_patch(bodies,"A","A",manifold,1.0)
	assert(not bool(same["ok"]) and String(same["code"])=="BAD_BODY_PAIR");checks+=1
	var bad_manifold:=manifold.duplicate(true);bad_manifold["ok"]=false
	var bad_manifold_result:=W.solve_patch(bodies,"A","B",bad_manifold,1.0)
	assert(not bool(bad_manifold_result["ok"]) and String(bad_manifold_result["code"])=="BAD_MANIFOLD");checks+=1
	var degenerate:=manifold.duplicate(true);degenerate["points"]=[degenerate["points"][0]]
	var degenerate_result:=W.solve_patch(bodies,"A","B",degenerate,1.0)
	assert(not bool(degenerate_result["ok"]) and String(degenerate_result["code"])=="DEGENERATE_CONTACT_PATCH");checks+=1
	var bad_tolerance:=W.solve_patch(bodies,"A","B",manifold,1.0,{"tolerance":0.0})
	assert(not bool(bad_tolerance["ok"]) and String(bad_tolerance["code"])=="BAD_TOLERANCE");checks+=1
	var bad_iterations:=W.solve_patch(bodies,"A","B",manifold,1.0,{"iterations":0})
	assert(not bool(bad_iterations["ok"]) and String(bad_iterations["code"])=="BAD_ITERATION_BUDGET");checks+=1

	print("FABRIC0.17-C Generalized Contact Wrench Acceptance: PASS (%d assertions) radius=%.12f stick_res=%s limits=(%.12f,%.12f,%.12f) sat_energy=%.12f moment_energy=%.12f tangent_energy=%.12f ledger=%s" % [
		checks,float(stick["patch"]["effective_radius"]),String.num_scientific(float(stick["projected_residual"])),
		float(saturated["limits"]["tangent"]),float(saturated["limits"]["rolling"]),float(saturated["limits"]["torsion"]),
		float(saturated["energy_delta"]),float(moment["energy_delta"]),float(tangent["energy_delta"]),String.num_scientific(float(saturated["energy_ledger_error"]))
	])
	quit(0)
