extends SceneTree

const Fabric = preload("res://scripts/research/fabric0/fabric0_conservation_fabric_v3.gd")
const Experiments = preload("res://scripts/research/fabric0/fabric0_nonlinear_dimension_experiments_v1.gd")

func _init() -> void:
	var checks := 0

	assert(Fabric.dim_equal(Fabric.dim_mul(Fabric.dim_voltage(), Fabric.dim_current()), Fabric.dim_power())); checks += 1
	assert(Fabric.dim_equal(Fabric.dim_mul(Fabric.dim_torque(), Fabric.dim_angular_velocity()), Fabric.dim_power())); checks += 1
	assert(Fabric.dim_equal(Fabric.dim_mul(Fabric.dim_force(), Fabric.dim_velocity()), Fabric.dim_power())); checks += 1
	assert(Fabric.dim_equal(Fabric.dim_mul(Fabric.dim_pressure(), Fabric.dim_volume_flow()), Fabric.dim_power())); checks += 1
	assert(Fabric.dim_equal(Fabric.dim_div(Fabric.dim_energy(), Fabric.dim_time()), Fabric.dim_power())); checks += 1
	assert(not Fabric.dim_equal(Fabric.dim_voltage(), Fabric.dim_torque())); checks += 1
	assert(Fabric.dim_string(Fabric.dim_dimensionless()) == "1"); checks += 1

	var domain_guard := Fabric.new_network()
	assert(Fabric.register_domain(domain_guard, "electric", "voltage", "current", Fabric.dim_voltage(), Fabric.dim_current(), "V", "A")); checks += 1
	assert(Fabric.register_domain(domain_guard, "rot", "angular_velocity", "torque", Fabric.dim_angular_velocity(), Fabric.dim_torque(), "rad/s", "N.m")); checks += 1
	assert(Fabric.register_domain(domain_guard, "fluid", "pressure", "volume_flow", Fabric.dim_pressure(), Fabric.dim_volume_flow(), "Pa", "m3/s")); checks += 1
	assert(not Fabric.register_domain(domain_guard, "nonsense", "voltage", "torque", Fabric.dim_voltage(), Fabric.dim_torque())); checks += 1
	assert(domain_guard["diagnostics"].size() == 1); checks += 1
	assert(String(domain_guard["diagnostics"][0]["code"]) == "DOMAIN_NOT_POWER_CONJUGATE"); checks += 1

	assert(Fabric.add_element(domain_guard, Fabric.equilibrium_terminal("e", "electric", 0.0, 1.0))); checks += 1
	assert(Fabric.add_element(domain_guard, Fabric.equilibrium_terminal("r", "rot", 0.0, 1.0))); checks += 1
	assert(not Fabric.link_ports(domain_guard, "illegal_wire", "e", "p", "r", "p")); checks += 1

	var bad_map_net := Fabric.new_network()
	assert(Experiments.register_electrical(bad_map_net)); checks += 1
	assert(Experiments.register_rotational(bad_map_net)); checks += 1
	var bad_map := Fabric.linear_power_map(
		"bad_map",
		{"e": "electrical", "m": "rotational"},
		[{
			"terms": [
				{"port": "e", "coefficient": 1.0, "coefficient_dimension": Fabric.dim_dimensionless()},
				{"port": "m", "coefficient": -2.0, "coefficient_dimension": Fabric.dim_dimensionless()},
			],
			"nominal": 1.0,
		}]
	)
	assert(not Fabric.add_element(bad_map_net, bad_map)); checks += 1
	assert(bad_map_net["diagnostics"].size() == 1); checks += 1
	assert(String(bad_map_net["diagnostics"][0]["code"]) == "POWER_MAP_ROW_DIMENSION_MISMATCH"); checks += 1

	var missing_dim_net := Fabric.new_network()
	assert(Experiments.register_electrical(missing_dim_net)); checks += 1
	assert(Experiments.register_rotational(missing_dim_net)); checks += 1
	var missing_dim_map := Fabric.linear_power_map(
		"missing_dim",
		{"e": "electrical", "m": "rotational"},
		[{
			"terms": [
				{"port": "e", "coefficient": 1.0, "coefficient_dimension": Fabric.dim_dimensionless()},
				{"port": "m", "coefficient": -2.0},
			],
			"nominal": 1.0,
		}]
	)
	assert(not Fabric.add_element(missing_dim_net, missing_dim_map)); checks += 1
	assert(String(missing_dim_net["diagnostics"][0]["code"]) == "POWER_MAP_MISSING_COEFFICIENT_DIMENSION"); checks += 1

	var bad_expr_net := Fabric.new_network()
	assert(Experiments.register_electrical(bad_expr_net)); checks += 1
	var bad_exp := Fabric.nonlinear_constitutive(
		"bad_exp",
		{"p": "electrical"},
		{},
		[{
			"expr": Fabric.expr_add(Fabric.expr_balance("p"), Fabric.expr_exp(Fabric.expr_common("p"))),
			"nominal": 1.0,
		}]
	)
	assert(not Fabric.add_element(bad_expr_net, bad_exp)); checks += 1
	assert(String(bad_expr_net["diagnostics"][0]["code"]) == "NONLINEAR_DIMENSION_ERROR"); checks += 1
	assert(String(bad_expr_net["diagnostics"][0]["reason"]) == "TRANSCENDENTAL_REQUIRES_DIMENSIONLESS"); checks += 1

	var bad_add_net := Fabric.new_network()
	assert(Experiments.register_electrical(bad_add_net)); checks += 1
	var bad_add := Fabric.nonlinear_constitutive(
		"bad_add",
		{"p": "electrical"},
		{},
		[{
			"expr": Fabric.expr_add(Fabric.expr_balance("p"), Fabric.expr_common("p")),
			"nominal": 1.0,
		}]
	)
	assert(not Fabric.add_element(bad_add_net, bad_add)); checks += 1
	assert(String(bad_add_net["diagnostics"][0]["reason"]) == "ADD_SUB_DIMENSION_MISMATCH"); checks += 1

	var diode := Experiments.build_diode_like_bias()
	var diode_result := Fabric.solve(diode)
	assert(bool(diode_result["ok"])); checks += 1
	assert(int(diode_result["iterations"]) >= 2); checks += 1
	assert(int(diode_result["iterations"]) < 20); checks += 1
	assert(float(diode_result["normalized_residual"]) <= 1.0e-10); checks += 1
	var diode_port := Fabric.read_port_state(diode, "diode_like", "p")
	assert(is_equal_approx(float(diode_port["common"]), log(4.0))); checks += 1
	assert(is_equal_approx(float(diode_port["balance"]), -3.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(diode, "bias", "p")["balance"]), 3.0)); checks += 1
	assert(Fabric.max_balance_residual(diode) <= 1.0e-9); checks += 1
	assert(Fabric.max_power_residual(diode) <= 1.0e-9); checks += 1
	assert(is_equal_approx(Fabric.read_element_absorbed_power(diode, "diode_like"), 3.0 * log(4.0))); checks += 1

	var saturation := Experiments.build_saturating_supply()
	var saturation_result := Fabric.solve(saturation)
	assert(bool(saturation_result["ok"])); checks += 1
	assert(int(saturation_result["iterations"]) >= 2); checks += 1
	assert(int(saturation_result["iterations"]) < 20); checks += 1
	var saturation_port := Fabric.read_port_state(saturation, "saturating_source", "p")
	assert(is_equal_approx(float(saturation_port["common"]), 1.9902990904610843)); checks += 1
	assert(is_equal_approx(float(saturation_port["balance"]), 1.9902990904610843)); checks += 1
	assert(float(saturation_port["balance"]) < 2.0); checks += 1
	assert(float(saturation_port["balance"]) > 1.9); checks += 1
	assert(Fabric.max_balance_residual(saturation) <= 1.0e-9); checks += 1

	var cubic := Experiments.build_cubic_rotational_drag()
	var cubic_result := Fabric.solve(cubic)
	assert(bool(cubic_result["ok"])); checks += 1
	assert(int(cubic_result["iterations"]) >= 2); checks += 1
	assert(int(cubic_result["iterations"]) < 20); checks += 1
	var cubic_port := Fabric.read_port_state(cubic, "cubic_drag", "p")
	assert(is_equal_approx(float(cubic_port["common"]), pow(3.0, 1.0 / 3.0))); checks += 1
	assert(is_equal_approx(float(cubic_port["balance"]), -3.0)); checks += 1
	assert(is_equal_approx(pow(float(cubic_port["common"]), 3.0), 3.0)); checks += 1
	assert(Fabric.max_balance_residual(cubic) <= 1.0e-9); checks += 1

	var cross := Experiments.build_dimensioned_cross_domain_map()
	var cross_result := Fabric.solve(cross)
	assert(bool(cross_result["ok"])); checks += 1
	var e := Fabric.read_port_state(cross, "dimensioned_map", "e")
	var m := Fabric.read_port_state(cross, "dimensioned_map", "m")
	assert(is_equal_approx(float(e["common"]), 32.0 / 3.0)); checks += 1
	assert(is_equal_approx(float(m["common"]), 16.0 / 3.0)); checks += 1
	assert(is_equal_approx(float(e["common"]), 2.0 * float(m["common"]))); checks += 1
	assert(is_equal_approx(float(e["balance"]), -8.0 / 3.0)); checks += 1
	assert(is_equal_approx(float(m["balance"]), 16.0 / 3.0)); checks += 1
	assert(absf(Fabric.read_element_absorbed_power(cross, "dimensioned_map")) <= 1.0e-9); checks += 1
	assert(absf(Fabric.total_absorbed_power(cross)) <= 1.0e-9); checks += 1
	assert(Fabric.max_power_residual(cross) <= 1.0e-9); checks += 1

	var impossible := Experiments.build_impossible_nonlinear_cell()
	var impossible_result := Fabric.solve(impossible)
	assert(not bool(impossible_result["ok"])); checks += 1
	assert(impossible["diagnostics"].size() == 1); checks += 1
	assert(String(impossible["diagnostics"][0]["code"]) == "NEWTON_SINGULAR_JACOBIAN"); checks += 1

	var replay_a := Experiments.build_diode_like_bias()
	var replay_b := Experiments.build_diode_like_bias()
	assert(bool(Fabric.solve(replay_a)["ok"])); checks += 1
	assert(bool(Fabric.solve(replay_b)["ok"])); checks += 1
	assert(Fabric.state_hash(replay_a).length() == 64); checks += 1
	assert(Fabric.state_hash(replay_a) == Fabric.state_hash(replay_b)); checks += 1

	var cubic_a := Experiments.build_cubic_rotational_drag()
	var cubic_b := Experiments.build_cubic_rotational_drag()
	assert(bool(Fabric.solve(cubic_a)["ok"])); checks += 1
	assert(bool(Fabric.solve(cubic_b)["ok"])); checks += 1
	assert(Fabric.state_hash(cubic_a) == Fabric.state_hash(cubic_b)); checks += 1

	var summary := Experiments.run_all()
	assert(bool(summary["diode_ok"])); checks += 1
	assert(is_equal_approx(float(summary["diode_voltage"]), log(4.0))); checks += 1
	assert(bool(summary["saturation_ok"])); checks += 1
	assert(is_equal_approx(float(summary["saturation_voltage"]), 1.9902990904610843)); checks += 1
	assert(bool(summary["cubic_ok"])); checks += 1
	assert(is_equal_approx(float(summary["cubic_omega"]), pow(3.0, 1.0 / 3.0))); checks += 1
	assert(bool(summary["cross_ok"])); checks += 1
	assert(is_equal_approx(float(summary["cross_voltage"]), 32.0 / 3.0)); checks += 1
	assert(is_equal_approx(float(summary["cross_omega"]), 16.0 / 3.0)); checks += 1
	assert(String(summary["cross_hash"]).length() == 64); checks += 1

	print("FABRIC0.5 Nonlinear+Dimensions Acceptance: PASS (%d assertions) diode=%.9f saturation=%.9f cubic=%.9f cross=(V=%.6f,w=%.6f) hash=%s" % [
		checks,
		float(summary["diode_voltage"]),
		float(summary["saturation_voltage"]),
		float(summary["cubic_omega"]),
		float(summary["cross_voltage"]),
		float(summary["cross_omega"]),
		String(summary["cross_hash"]),
	])
	quit(0)
