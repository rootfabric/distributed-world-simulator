extends SceneTree

const Fabric = preload("res://scripts/research/fabric0/fabric0_conservation_fabric_v3.gd")

func register_electrical(net: Dictionary) -> bool:
	return Fabric.register_domain(net, "electrical", "voltage", "current", Fabric.dim_voltage(), Fabric.dim_current(), "V", "A")

func register_rotational(net: Dictionary) -> bool:
	return Fabric.register_domain(net, "rotational", "angular_velocity", "torque", Fabric.dim_angular_velocity(), Fabric.dim_torque(), "rad/s", "N.m")

func dimensioned_map(element_id: String) -> Dictionary:
	return Fabric.linear_power_map(
		element_id,
		{"e": "electrical", "m": "rotational"},
		[{"terms": [
			{"port": "e", "coefficient": 1.0, "coefficient_dimension": Fabric.dim_dimensionless()},
			{"port": "m", "coefficient": -2.0, "coefficient_dimension": Fabric.dim_div(Fabric.dim_voltage(), Fabric.dim_angular_velocity())},
		], "nominal": 10.0}]
	)

func _init() -> void:
	var checks := 0

	# FABRIC0.3 static two-source cell.
	var two := Fabric.new_network()
	assert(register_electrical(two)); checks += 1
	assert(Fabric.add_element(two, Fabric.equilibrium_terminal("a", "electrical", 12.0, 2.0))); checks += 1
	assert(Fabric.add_element(two, Fabric.equilibrium_terminal("b", "electrical", 6.0, 1.0))); checks += 1
	assert(Fabric.add_element(two, Fabric.equilibrium_terminal("load", "electrical", 0.0, 3.0))); checks += 1
	assert(Fabric.link_ports(two, "ab", "a", "p", "b", "p")); checks += 1
	assert(Fabric.link_ports(two, "bl", "b", "p", "load", "p")); checks += 1
	var two_result := Fabric.solve(two)
	assert(bool(two_result["ok"])); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(two, "a", "p")["common"]), 5.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(two, "a", "p")["balance"]), 14.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(two, "b", "p")["balance"]), 1.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(two, "load", "p")["balance"]), -15.0)); checks += 1
	assert(Fabric.max_balance_residual(two) <= 1.0e-9); checks += 1
	assert(Fabric.max_power_residual(two) <= 1.0e-9); checks += 1

	# Topology split/rejoin remains equation recompilation.
	var two_hash := Fabric.state_hash(two)
	assert(Fabric.set_bond_active(two, "ab", false)); checks += 1
	var split := Fabric.solve(two)
	assert(bool(split["ok"])); checks += 1
	assert(int(split["cell_count"]) == 2); checks += 1
	assert(int(split["island_count"]) == 2); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(two, "a", "p")["common"]), 12.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(two, "b", "p")["common"]), 1.5)); checks += 1
	assert(Fabric.set_bond_active(two, "ab", true)); checks += 1
	assert(bool(Fabric.solve(two)["ok"])); checks += 1
	assert(Fabric.state_hash(two) == two_hash); checks += 1

	# Ideal reaction remains solved, not prescribed.
	var ideal := Fabric.new_network()
	assert(register_electrical(ideal)); checks += 1
	assert(Fabric.add_element(ideal, Fabric.ideal_common_constraint("ideal", "electrical", 10.0))); checks += 1
	assert(Fabric.add_element(ideal, Fabric.equilibrium_terminal("l1", "electrical", 0.0, 2.0))); checks += 1
	assert(Fabric.add_element(ideal, Fabric.equilibrium_terminal("l2", "electrical", 0.0, 1.0))); checks += 1
	assert(Fabric.link_ports(ideal, "i1", "ideal", "p", "l1", "p")); checks += 1
	assert(Fabric.link_ports(ideal, "12", "l1", "p", "l2", "p")); checks += 1
	assert(bool(Fabric.solve(ideal)["ok"])); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(ideal, "ideal", "p")["common"]), 10.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(ideal, "ideal", "p")["balance"]), 30.0)); checks += 1

	# Floating linear network still gets the stronger historical diagnostic.
	var floating := Fabric.new_network()
	assert(register_rotational(floating)); checks += 1
	assert(Fabric.add_element(floating, Fabric.linear_difference_coupler("link", "rotational", 1.0))); checks += 1
	var floating_result := Fabric.solve(floating)
	assert(not bool(floating_result["ok"])); checks += 1
	assert(String(floating["diagnostics"][0]["code"]) == "SINGULAR_FLOATING_ISLAND"); checks += 1

	# FABRIC0.4 mixed-domain dynamic machine still works under V3.
	var machine := Fabric.new_network()
	assert(register_electrical(machine)); checks += 1
	assert(register_rotational(machine)); checks += 1
	assert(Fabric.add_element(machine, Fabric.equilibrium_terminal("supply", "electrical", 12.0, 2.0))); checks += 1
	assert(Fabric.add_element(machine, dimensioned_map("map"))); checks += 1
	assert(Fabric.add_element(machine, Fabric.linear_storage_terminal("inertia", "rotational", 2.0, 0.0))); checks += 1
	assert(Fabric.add_element(machine, Fabric.equilibrium_terminal("drag", "rotational", 0.0, 0.5))); checks += 1
	assert(Fabric.link_ports(machine, "supply_map", "supply", "p", "map", "e")); checks += 1
	assert(Fabric.link_ports(machine, "map_inertia", "map", "m", "inertia", "p")); checks += 1
	assert(Fabric.link_ports(machine, "inertia_drag", "inertia", "p", "drag", "p")); checks += 1
	var first := Fabric.step(machine, 1.0)
	assert(bool(first["ok"])); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(machine, "map", "e")["common"]), 64.0 / 7.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(machine, "map", "m")["common"]), 32.0 / 7.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(machine, "map", "e")["balance"]), -40.0 / 7.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(machine, "map", "m")["balance"]), 80.0 / 7.0)); checks += 1
	assert(absf(Fabric.read_element_absorbed_power(machine, "map")) <= 1.0e-9); checks += 1
	assert(is_equal_approx(float(Fabric.read_element_state(machine, "inertia", "energy")), 1024.0 / 49.0)); checks += 1

	for _i in range(5):
		assert(bool(Fabric.step(machine, 1.0)["ok"])); checks += 1
	var before_open := float(Fabric.read_port_state(machine, "inertia", "p")["common"])
	assert(is_equal_approx(before_open, 161434400.0 / 28588707.0)); checks += 1
	assert(Fabric.set_bond_active(machine, "supply_map", false)); checks += 1
	assert(bool(Fabric.step(machine, 1.0)["ok"])); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(machine, "map", "m")["common"]), 0.8 * before_open)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(machine, "map", "e")["balance"]), 0.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(machine, "map", "m")["balance"]), 0.0)); checks += 1

	# V3 Power Map remains generic enough for a 3-port differential relation.
	var diff := Fabric.new_network()
	assert(register_rotational(diff)); checks += 1
	assert(Fabric.add_element(diff, Fabric.equilibrium_terminal("left_load", "rotational", 0.0, 1.0))); checks += 1
	assert(Fabric.add_element(diff, Fabric.equilibrium_terminal("right_load", "rotational", 0.0, 2.0))); checks += 1
	assert(Fabric.add_element(diff, Fabric.equilibrium_terminal("carrier_drive", "rotational", 6.0, 2.0))); checks += 1
	var diff_map := Fabric.linear_power_map(
		"diff_map",
		{"left": "rotational", "right": "rotational", "carrier": "rotational"},
		[{"terms": [
			{"port": "left", "coefficient": 1.0, "coefficient_dimension": Fabric.dim_dimensionless()},
			{"port": "right", "coefficient": 1.0, "coefficient_dimension": Fabric.dim_dimensionless()},
			{"port": "carrier", "coefficient": -2.0, "coefficient_dimension": Fabric.dim_dimensionless()},
		], "nominal": 1.0}]
	)
	assert(Fabric.add_element(diff, diff_map)); checks += 1
	assert(Fabric.link_ports(diff, "left", "left_load", "p", "diff_map", "left")); checks += 1
	assert(Fabric.link_ports(diff, "right", "right_load", "p", "diff_map", "right")); checks += 1
	assert(Fabric.link_ports(diff, "carrier", "carrier_drive", "p", "diff_map", "carrier")); checks += 1
	assert(bool(Fabric.solve(diff)["ok"])); checks += 1
	var left := Fabric.read_port_state(diff, "diff_map", "left")
	var right := Fabric.read_port_state(diff, "diff_map", "right")
	var carrier := Fabric.read_port_state(diff, "diff_map", "carrier")
	assert(is_equal_approx(float(left["common"]), 24.0 / 7.0)); checks += 1
	assert(is_equal_approx(float(right["common"]), 12.0 / 7.0)); checks += 1
	assert(is_equal_approx(float(carrier["common"]), 18.0 / 7.0)); checks += 1
	assert(is_equal_approx(float(left["balance"]), 24.0 / 7.0)); checks += 1
	assert(is_equal_approx(float(right["balance"]), 24.0 / 7.0)); checks += 1
	assert(is_equal_approx(float(carrier["balance"]), -48.0 / 7.0)); checks += 1
	assert(absf(Fabric.read_element_absorbed_power(diff, "diff_map")) <= 1.0e-9); checks += 1

	print("FABRIC0.5 V3 Compatibility: PASS (%d assertions)" % checks)
	quit(0)
