class_name Fabric0ConservationExperimentsV1
extends RefCounted

const Conservation = preload("res://scripts/research/fabric0/fabric0_conservation_fabric_v1.gd")

static func build_two_source_cell() -> Dictionary:
	var net := Conservation.new_network()
	assert(Conservation.register_domain(net, "electrical_like", "voltage", "current", "V", "A"))
	assert(Conservation.add_element(net, Conservation.equilibrium_terminal("source_a", "electrical_like", 12.0, 2.0)))
	assert(Conservation.add_element(net, Conservation.equilibrium_terminal("source_b", "electrical_like", 6.0, 1.0)))
	assert(Conservation.add_element(net, Conservation.equilibrium_terminal("load", "electrical_like", 0.0, 3.0)))
	assert(Conservation.link_ports(net, "wire_a_b", "source_a", "p", "source_b", "p"))
	assert(Conservation.link_ports(net, "wire_b_load", "source_b", "p", "load", "p"))
	return net

static func build_role_reversal_cell() -> Dictionary:
	var net := Conservation.new_network()
	assert(Conservation.register_domain(net, "electrical_like", "voltage", "current", "V", "A"))
	assert(Conservation.add_element(net, Conservation.equilibrium_terminal("strong_source", "electrical_like", 12.0, 3.0)))
	assert(Conservation.add_element(net, Conservation.equilibrium_terminal("weak_source", "electrical_like", 4.0, 1.0)))
	assert(Conservation.add_element(net, Conservation.equilibrium_terminal("load", "electrical_like", 0.0, 1.0)))
	assert(Conservation.link_ports(net, "wire_sources", "strong_source", "p", "weak_source", "p"))
	assert(Conservation.link_ports(net, "wire_load", "weak_source", "p", "load", "p"))
	return net

static func build_ideal_source_cell() -> Dictionary:
	var net := Conservation.new_network()
	assert(Conservation.register_domain(net, "electrical_like", "voltage", "current", "V", "A"))
	assert(Conservation.add_element(net, Conservation.ideal_common_constraint("ideal_source", "electrical_like", 10.0)))
	assert(Conservation.add_element(net, Conservation.equilibrium_terminal("load_a", "electrical_like", 0.0, 2.0)))
	assert(Conservation.add_element(net, Conservation.equilibrium_terminal("load_b", "electrical_like", 0.0, 1.0)))
	assert(Conservation.link_ports(net, "wire_source_a", "ideal_source", "p", "load_a", "p"))
	assert(Conservation.link_ports(net, "wire_a_b", "load_a", "p", "load_b", "p"))
	return net

static func build_conflicting_ideal_cell() -> Dictionary:
	var net := Conservation.new_network()
	assert(Conservation.register_domain(net, "electrical_like", "voltage", "current", "V", "A"))
	assert(Conservation.add_element(net, Conservation.ideal_common_constraint("ideal_a", "electrical_like", 10.0)))
	assert(Conservation.add_element(net, Conservation.ideal_common_constraint("ideal_b", "electrical_like", 12.0)))
	assert(Conservation.link_ports(net, "wire_conflict", "ideal_a", "p", "ideal_b", "p"))
	return net

static func build_floating_pair() -> Dictionary:
	var net := Conservation.new_network()
	assert(Conservation.register_domain(net, "electrical_like", "voltage", "current", "V", "A"))
	assert(Conservation.add_element(net, Conservation.linear_difference_coupler("coupler", "electrical_like", 1.0)))
	return net

static func build_two_cell_bridge() -> Dictionary:
	var net := Conservation.new_network()
	assert(Conservation.register_domain(net, "electrical_like", "voltage", "current", "V", "A"))
	assert(Conservation.add_element(net, Conservation.equilibrium_terminal("source", "electrical_like", 12.0, 2.0)))
	assert(Conservation.add_element(net, Conservation.linear_difference_coupler("link", "electrical_like", 1.0)))
	assert(Conservation.add_element(net, Conservation.equilibrium_terminal("load", "electrical_like", 0.0, 1.0)))
	assert(Conservation.link_ports(net, "wire_source_link", "source", "p", "link", "a"))
	assert(Conservation.link_ports(net, "wire_link_load", "link", "b", "load", "p"))
	return net

static func build_fixed_balance_cell() -> Dictionary:
	var net := Conservation.new_network()
	assert(Conservation.register_domain(net, "electrical_like", "voltage", "current", "V", "A"))
	assert(Conservation.add_element(net, Conservation.fixed_balance_terminal("flow_source", "electrical_like", 3.0)))
	assert(Conservation.add_element(net, Conservation.equilibrium_terminal("load", "electrical_like", 0.0, 2.0)))
	assert(Conservation.link_ports(net, "wire_source_load", "flow_source", "p", "load", "p"))
	return net

static func build_rotational_conservation_cell() -> Dictionary:
	var net := Conservation.new_network()
	assert(Conservation.register_domain(net, "rotational_shaft", "angular_velocity", "torque", "rad/s", "N*m"))
	assert(Conservation.add_element(net, Conservation.equilibrium_terminal("drive", "rotational_shaft", 10.0, 2.0)))
	assert(Conservation.add_element(net, Conservation.equilibrium_terminal("drag", "rotational_shaft", 0.0, 1.0)))
	assert(Conservation.link_ports(net, "shaft", "drive", "p", "drag", "p"))
	return net

static func run_all() -> Dictionary:
	var two_source := build_two_source_cell()
	var two_source_result := Conservation.solve(two_source)

	var reversal := build_role_reversal_cell()
	var reversal_result := Conservation.solve(reversal)

	var ideal := build_ideal_source_cell()
	var ideal_result := Conservation.solve(ideal)

	var bridge := build_two_cell_bridge()
	var bridge_result := Conservation.solve(bridge)

	var fixed := build_fixed_balance_cell()
	var fixed_result := Conservation.solve(fixed)

	var rotational := build_rotational_conservation_cell()
	var rotational_result := Conservation.solve(rotational)

	return {
		"two_source_ok": bool(two_source_result["ok"]),
		"two_source_common": float(Conservation.read_port_state(two_source, "source_a", "p")["common"]),
		"two_source_a_balance": float(Conservation.read_port_state(two_source, "source_a", "p")["balance"]),
		"two_source_b_balance": float(Conservation.read_port_state(two_source, "source_b", "p")["balance"]),
		"two_source_load_balance": float(Conservation.read_port_state(two_source, "load", "p")["balance"]),
		"two_source_power_residual": Conservation.max_power_residual(two_source),
		"reversal_ok": bool(reversal_result["ok"]),
		"reversal_common": float(Conservation.read_port_state(reversal, "weak_source", "p")["common"]),
		"reversal_weak_balance": float(Conservation.read_port_state(reversal, "weak_source", "p")["balance"]),
		"reversal_weak_absorbed_power": Conservation.read_element_absorbed_power(reversal, "weak_source"),
		"ideal_ok": bool(ideal_result["ok"]),
		"ideal_common": float(Conservation.read_port_state(ideal, "ideal_source", "p")["common"]),
		"ideal_balance": float(Conservation.read_port_state(ideal, "ideal_source", "p")["balance"]),
		"bridge_ok": bool(bridge_result["ok"]),
		"bridge_source_common": float(Conservation.read_port_state(bridge, "source", "p")["common"]),
		"bridge_load_common": float(Conservation.read_port_state(bridge, "load", "p")["common"]),
		"bridge_absorbed_power": Conservation.read_element_absorbed_power(bridge, "link"),
		"fixed_ok": bool(fixed_result["ok"]),
		"fixed_common": float(Conservation.read_port_state(fixed, "load", "p")["common"]),
		"rotational_ok": bool(rotational_result["ok"]),
		"rotational_common": float(Conservation.read_port_state(rotational, "drive", "p")["common"]),
		"rotational_drive_balance": float(Conservation.read_port_state(rotational, "drive", "p")["balance"]),
		"rotational_drag_balance": float(Conservation.read_port_state(rotational, "drag", "p")["balance"]),
		"rotational_hash": Conservation.state_hash(rotational),
	}
