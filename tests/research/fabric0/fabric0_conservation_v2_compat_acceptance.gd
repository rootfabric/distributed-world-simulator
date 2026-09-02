extends SceneTree

const Fabric = preload("res://scripts/research/fabric0/fabric0_conservation_fabric_v2.gd")

func _init() -> void:
	var checks := 0

	var two := Fabric.new_network()
	assert(Fabric.register_domain(two, "electrical_like", "voltage", "current", "V", "A")); checks += 1
	assert(Fabric.add_element(two, Fabric.equilibrium_terminal("a", "electrical_like", 12.0, 2.0))); checks += 1
	assert(Fabric.add_element(two, Fabric.equilibrium_terminal("b", "electrical_like", 6.0, 1.0))); checks += 1
	assert(Fabric.add_element(two, Fabric.equilibrium_terminal("load", "electrical_like", 0.0, 3.0))); checks += 1
	assert(Fabric.link_ports(two, "ab", "a", "p", "b", "p")); checks += 1
	assert(Fabric.link_ports(two, "bl", "b", "p", "load", "p")); checks += 1
	assert(bool(Fabric.solve(two)["ok"])); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(two, "a", "p")["common"]), 5.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(two, "a", "p")["balance"]), 14.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(two, "b", "p")["balance"]), 1.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(two, "load", "p")["balance"]), -15.0)); checks += 1
	assert(Fabric.max_power_residual(two) <= 1.0e-9); checks += 1

	var ideal := Fabric.new_network()
	assert(Fabric.register_domain(ideal, "electrical_like", "voltage", "current", "V", "A")); checks += 1
	assert(Fabric.add_element(ideal, Fabric.ideal_common_constraint("ideal", "electrical_like", 10.0))); checks += 1
	assert(Fabric.add_element(ideal, Fabric.equilibrium_terminal("load_a", "electrical_like", 0.0, 2.0))); checks += 1
	assert(Fabric.add_element(ideal, Fabric.equilibrium_terminal("load_b", "electrical_like", 0.0, 1.0))); checks += 1
	assert(Fabric.link_ports(ideal, "ia", "ideal", "p", "load_a", "p")); checks += 1
	assert(Fabric.link_ports(ideal, "ab", "load_a", "p", "load_b", "p")); checks += 1
	assert(bool(Fabric.solve(ideal)["ok"])); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(ideal, "ideal", "p")["common"]), 10.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(ideal, "ideal", "p")["balance"]), 30.0)); checks += 1
	assert(Fabric.max_balance_residual(ideal) <= 1.0e-9); checks += 1

	var conflict := Fabric.new_network()
	assert(Fabric.register_domain(conflict, "x", "common", "balance")); checks += 1
	assert(Fabric.add_element(conflict, Fabric.ideal_common_constraint("x10", "x", 10.0))); checks += 1
	assert(Fabric.add_element(conflict, Fabric.ideal_common_constraint("x12", "x", 12.0))); checks += 1
	assert(Fabric.link_ports(conflict, "wire", "x10", "p", "x12", "p")); checks += 1
	assert(not bool(Fabric.solve(conflict)["ok"])); checks += 1
	assert(String(conflict["diagnostics"][0]["code"]) == "CONSTRAINT_CONFLICT"); checks += 1

	var floating := Fabric.new_network()
	assert(Fabric.register_domain(floating, "x", "common", "balance")); checks += 1
	assert(Fabric.add_element(floating, Fabric.linear_difference_coupler("link", "x", 1.0))); checks += 1
	assert(not bool(Fabric.solve(floating)["ok"])); checks += 1
	assert(String(floating["diagnostics"][0]["code"]) == "SINGULAR_FLOATING_ISLAND"); checks += 1

	var bridge := Fabric.new_network()
	assert(Fabric.register_domain(bridge, "x", "common", "balance")); checks += 1
	assert(Fabric.add_element(bridge, Fabric.equilibrium_terminal("source", "x", 12.0, 2.0))); checks += 1
	assert(Fabric.add_element(bridge, Fabric.linear_difference_coupler("link", "x", 1.0))); checks += 1
	assert(Fabric.add_element(bridge, Fabric.equilibrium_terminal("load", "x", 0.0, 1.0))); checks += 1
	assert(Fabric.link_ports(bridge, "sl", "source", "p", "link", "a")); checks += 1
	assert(Fabric.link_ports(bridge, "ll", "link", "b", "load", "p")); checks += 1
	assert(bool(Fabric.solve(bridge)["ok"])); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(bridge, "source", "p")["common"]), 9.6)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(bridge, "load", "p")["common"]), 4.8)); checks += 1
	assert(is_equal_approx(Fabric.read_element_absorbed_power(bridge, "link"), 23.04)); checks += 1

	var topology_hash := Fabric.state_hash(two)
	assert(Fabric.set_bond_active(two, "ab", false)); checks += 1
	var split := Fabric.solve(two)
	assert(bool(split["ok"])); checks += 1
	assert(int(split["cell_count"]) == 2); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(two, "a", "p")["common"]), 12.0)); checks += 1
	assert(Fabric.set_bond_active(two, "ab", true)); checks += 1
	assert(bool(Fabric.solve(two)["ok"])); checks += 1
	assert(Fabric.state_hash(two) == topology_hash); checks += 1

	print("FABRIC0.4 V2 Compatibility: PASS (%d assertions)" % checks)
	quit(0)
