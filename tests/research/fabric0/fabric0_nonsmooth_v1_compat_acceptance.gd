extends SceneTree

const Fabric = preload("res://scripts/research/fabric0/fabric0_nonsmooth_fabric_v1.gd")
const Experiments = preload("res://scripts/research/fabric0/fabric0_nonsmooth_experiments_v1.gd")

func _init() -> void:
	var checks := 0

	# FABRIC0.5 smooth nonlinear law is a one-branch hybrid relation.
	var smooth := Fabric.new_network()
	assert(Experiments.register_electrical(smooth)); checks += 1
	assert(Fabric.add_element(smooth, Fabric.fixed_balance_terminal("bias", "electrical", 3.0))); checks += 1
	var diode_residual := Fabric.expr_add(
		Fabric.expr_balance("p"),
		Fabric.expr_mul(
			Fabric.expr_parameter("isat"),
			Fabric.expr_sub(
				Fabric.expr_exp(Fabric.expr_div(Fabric.expr_common("p"), Fabric.expr_parameter("vscale"))),
				Fabric.expr_constant(1.0, Fabric.dim_dimensionless())
			)
		)
	)
	var smooth_branch := Fabric.branch("smooth", [Fabric.residual(diode_residual, 1.0)], [], 0)
	assert(Fabric.add_element(smooth, Fabric.hybrid_relation(
		"smooth_diode_like",
		{"p": "electrical"},
		{
			"isat": {"value": 1.0, "dimension": Fabric.dim_current()},
			"vscale": {"value": 1.0, "dimension": Fabric.dim_voltage()},
		},
		[smooth_branch],
		"smooth"
	))); checks += 1
	assert(Fabric.link_ports(smooth, "wire", "bias", "p", "smooth_diode_like", "p")); checks += 1
	var smooth_result := Fabric.solve(smooth)
	assert(bool(smooth_result["ok"])); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(smooth, "smooth_diode_like", "p")["common"]), log(4.0))); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(smooth, "smooth_diode_like", "p")["balance"]), -3.0)); checks += 1
	assert(String(Fabric.read_element_state(smooth, "smooth_diode_like", "active_branch")) == "smooth"); checks += 1
	assert(Fabric.max_balance_residual(smooth) <= 1.0e-9); checks += 1

	# Dimension checker still rejects transcendental functions of dimensioned values.
	var invalid := Fabric.new_network()
	assert(Experiments.register_electrical(invalid)); checks += 1
	var bad_branch := Fabric.branch(
		"bad",
		[Fabric.residual(Fabric.expr_add(Fabric.expr_balance("p"), Fabric.expr_exp(Fabric.expr_common("p"))), 1.0)],
		[]
	)
	assert(not Fabric.add_element(invalid, Fabric.hybrid_relation("bad", {"p": "electrical"}, {}, [bad_branch], "bad"))); checks += 1
	assert(String(invalid["diagnostics"][0]["code"]) == "HYBRID_DIMENSION_ERROR"); checks += 1

	# FABRIC0.4 dimensioned mixed-domain Power Map survives in the nonsmooth successor.
	var cross := Fabric.new_network()
	assert(Experiments.register_electrical(cross)); checks += 1
	assert(Experiments.register_rotational(cross)); checks += 1
	assert(Fabric.add_element(cross, Fabric.equilibrium_terminal("source", "electrical", 12.0, 2.0))); checks += 1
	assert(Fabric.add_element(cross, Fabric.equilibrium_terminal("load", "rotational", 0.0, 1.0))); checks += 1
	var map := Fabric.linear_power_map(
		"map",
		{"e": "electrical", "m": "rotational"},
		[{
			"terms": [
				{"port": "e", "coefficient": 1.0, "coefficient_dimension": Fabric.dim_dimensionless()},
				{"port": "m", "coefficient": -2.0, "coefficient_dimension": Fabric.dim_div(Fabric.dim_voltage(), Fabric.dim_angular_velocity())},
			],
			"nominal": 10.0,
		}]
	)
	assert(Fabric.add_element(cross, map)); checks += 1
	assert(Fabric.link_ports(cross, "source_map", "source", "p", "map", "e")); checks += 1
	assert(Fabric.link_ports(cross, "map_load", "map", "m", "load", "p")); checks += 1
	var cross_result := Fabric.solve(cross)
	assert(bool(cross_result["ok"])); checks += 1
	var e := Fabric.read_port_state(cross, "map", "e")
	var m := Fabric.read_port_state(cross, "map", "m")
	assert(is_equal_approx(float(e["common"]), 32.0 / 3.0)); checks += 1
	assert(is_equal_approx(float(m["common"]), 16.0 / 3.0)); checks += 1
	assert(is_equal_approx(float(e["common"]), 2.0 * float(m["common"]))); checks += 1
	assert(is_equal_approx(float(e["balance"]), -8.0 / 3.0)); checks += 1
	assert(is_equal_approx(float(m["balance"]), 16.0 / 3.0)); checks += 1
	assert(absf(Fabric.read_element_absorbed_power(cross, "map")) <= 1.0e-9); checks += 1
	assert(Fabric.max_power_residual(cross) <= 1.0e-9); checks += 1

	# Historical Conservation Cell behavior is still the zero-hybrid case.
	var two := Fabric.new_network()
	assert(Experiments.register_electrical(two)); checks += 1
	assert(Fabric.add_element(two, Fabric.equilibrium_terminal("a", "electrical", 12.0, 2.0))); checks += 1
	assert(Fabric.add_element(two, Fabric.equilibrium_terminal("b", "electrical", 6.0, 1.0))); checks += 1
	assert(Fabric.add_element(two, Fabric.equilibrium_terminal("load", "electrical", 0.0, 3.0))); checks += 1
	assert(Fabric.link_ports(two, "ab", "a", "p", "b", "p")); checks += 1
	assert(Fabric.link_ports(two, "bl", "b", "p", "load", "p")); checks += 1
	assert(bool(Fabric.solve(two)["ok"])); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(two, "a", "p")["common"]), 5.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(two, "a", "p")["balance"]), 14.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(two, "b", "p")["balance"]), 1.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(two, "load", "p")["balance"]), -15.0)); checks += 1
	assert(Fabric.max_balance_residual(two) <= 1.0e-9); checks += 1

	# Deterministic smooth replay on fresh graphs.
	var fresh_a := Fabric.new_network()
	var fresh_b := Fabric.new_network()
	for net in [fresh_a, fresh_b]:
		Experiments.register_electrical(net)
		Fabric.add_element(net, Fabric.fixed_balance_terminal("bias", "electrical", 3.0))
		Fabric.add_element(net, Fabric.hybrid_relation(
			"smooth_diode_like", {"p": "electrical"},
			{"isat": {"value": 1.0, "dimension": Fabric.dim_current()}, "vscale": {"value": 1.0, "dimension": Fabric.dim_voltage()}},
			[Fabric.branch("smooth", [Fabric.residual(diode_residual, 1.0)], [])], "smooth"
		))
		Fabric.link_ports(net, "wire", "bias", "p", "smooth_diode_like", "p")
		assert(bool(Fabric.solve(net)["ok"])); checks += 1
	assert(Fabric.state_hash(fresh_a) == Fabric.state_hash(fresh_b)); checks += 1

	print("FABRIC0.6 Predecessor Compatibility: PASS (%d assertions) smooth=%.9f cross=(%.6f,%.6f)" % [
		checks,
		float(Fabric.read_port_state(smooth, "smooth_diode_like", "p")["common"]),
		float(e["common"]),
		float(m["common"]),
	])
	quit(0)
