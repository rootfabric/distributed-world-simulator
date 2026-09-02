class_name Fabric0PowerMapExperimentsV1
extends RefCounted

const Fabric = preload("res://scripts/research/fabric0/fabric0_conservation_fabric_v2.gd")

static func build_forward_machine() -> Dictionary:
	var net := Fabric.new_network()
	assert(Fabric.register_domain(net, "electrical_like", "voltage", "current", "V", "A"))
	assert(Fabric.register_domain(net, "rotational", "angular_velocity", "torque", "rad/s", "N*m"))
	assert(Fabric.add_element(net, Fabric.equilibrium_terminal("supply", "electrical_like", 12.0, 2.0)))
	assert(Fabric.add_element(net, Fabric.linear_power_map(
		"transducer",
		{"e": "electrical_like", "m": "rotational"},
		[{"e": 1.0, "m": -2.0}]
	)))
	assert(Fabric.add_element(net, Fabric.linear_storage_terminal("inertia", "rotational", 2.0, 0.0)))
	assert(Fabric.add_element(net, Fabric.equilibrium_terminal("drag", "rotational", 0.0, 0.5)))
	assert(Fabric.link_ports(net, "supply_link", "supply", "p", "transducer", "e"))
	assert(Fabric.link_ports(net, "shaft_storage", "transducer", "m", "inertia", "p"))
	assert(Fabric.link_ports(net, "shaft_drag", "inertia", "p", "drag", "p"))
	return net

static func build_reverse_generator() -> Dictionary:
	var net := Fabric.new_network()
	assert(Fabric.register_domain(net, "electrical_like", "voltage", "current", "V", "A"))
	assert(Fabric.register_domain(net, "rotational", "angular_velocity", "torque", "rad/s", "N*m"))
	assert(Fabric.add_element(net, Fabric.equilibrium_terminal("electrical_load", "electrical_like", 0.0, 1.0)))
	assert(Fabric.add_element(net, Fabric.linear_power_map(
		"transducer",
		{"e": "electrical_like", "m": "rotational"},
		[{"e": 1.0, "m": -2.0}]
	)))
	assert(Fabric.add_element(net, Fabric.equilibrium_terminal("shaft_drive", "rotational", 10.0, 2.0)))
	assert(Fabric.link_ports(net, "load_link", "electrical_load", "p", "transducer", "e"))
	assert(Fabric.link_ports(net, "shaft_link", "transducer", "m", "shaft_drive", "p"))
	return net

static func build_open_differential() -> Dictionary:
	var net := Fabric.new_network()
	assert(Fabric.register_domain(net, "rotational", "angular_velocity", "torque", "rad/s", "N*m"))
	assert(Fabric.add_element(net, Fabric.equilibrium_terminal("left_load", "rotational", 0.0, 1.0)))
	assert(Fabric.add_element(net, Fabric.equilibrium_terminal("right_load", "rotational", 0.0, 2.0)))
	assert(Fabric.add_element(net, Fabric.equilibrium_terminal("carrier_drive", "rotational", 6.0, 2.0)))
	assert(Fabric.add_element(net, Fabric.linear_power_map(
		"kinematic_map",
		{"left": "rotational", "right": "rotational", "carrier": "rotational"},
		[{"left": 1.0, "right": 1.0, "carrier": -2.0}]
	)))
	assert(Fabric.link_ports(net, "left_shaft", "left_load", "p", "kinematic_map", "left"))
	assert(Fabric.link_ports(net, "right_shaft", "right_load", "p", "kinematic_map", "right"))
	assert(Fabric.link_ports(net, "carrier_shaft", "carrier_drive", "p", "kinematic_map", "carrier"))
	return net

static func run_forward_steps(step_count: int = 6) -> Dictionary:
	var net := build_forward_machine()
	var speed_history: Array = []
	var voltage_history: Array = []
	for _i in range(step_count):
		var result := Fabric.step(net, 1.0)
		assert(bool(result["ok"]))
		speed_history.append(float(Fabric.read_port_state(net, "inertia", "p")["common"]))
		voltage_history.append(float(Fabric.read_port_state(net, "transducer", "e")["common"]))
	return {
		"network": net,
		"speed_history": speed_history,
		"voltage_history": voltage_history,
	}

static func run_all() -> Dictionary:
	var forward_bundle := run_forward_steps(6)
	var forward: Dictionary = forward_bundle["network"]
	var open_before := float(Fabric.read_port_state(forward, "inertia", "p")["common"])
	Fabric.set_bond_active(forward, "supply_link", false)
	var open_result := Fabric.step(forward, 1.0)
	var open_after := float(Fabric.read_port_state(forward, "inertia", "p")["common"])

	var reverse := build_reverse_generator()
	var reverse_result := Fabric.solve(reverse)

	var diff := build_open_differential()
	var diff_result := Fabric.solve(diff)

	return {
		"forward_speed_history": forward_bundle["speed_history"],
		"forward_voltage_history": forward_bundle["voltage_history"],
		"forward_map_absorbed_power": Fabric.read_element_absorbed_power(forward, "transducer"),
		"open_result_ok": bool(open_result["ok"]),
		"open_before": open_before,
		"open_after": open_after,
		"open_voltage": float(Fabric.read_port_state(forward, "transducer", "e")["common"]),
		"open_current": float(Fabric.read_port_state(forward, "transducer", "e")["balance"]),
		"reverse_ok": bool(reverse_result["ok"]),
		"reverse_voltage": float(Fabric.read_port_state(reverse, "transducer", "e")["common"]),
		"reverse_omega": float(Fabric.read_port_state(reverse, "transducer", "m")["common"]),
		"reverse_map_e_balance": float(Fabric.read_port_state(reverse, "transducer", "e")["balance"]),
		"reverse_map_m_balance": float(Fabric.read_port_state(reverse, "transducer", "m")["balance"]),
		"reverse_map_power": Fabric.read_element_absorbed_power(reverse, "transducer"),
		"diff_ok": bool(diff_result["ok"]),
		"diff_left": float(Fabric.read_port_state(diff, "kinematic_map", "left")["common"]),
		"diff_right": float(Fabric.read_port_state(diff, "kinematic_map", "right")["common"]),
		"diff_carrier": float(Fabric.read_port_state(diff, "kinematic_map", "carrier")["common"]),
		"diff_left_torque": float(Fabric.read_port_state(diff, "kinematic_map", "left")["balance"]),
		"diff_right_torque": float(Fabric.read_port_state(diff, "kinematic_map", "right")["balance"]),
		"diff_carrier_torque": float(Fabric.read_port_state(diff, "kinematic_map", "carrier")["balance"]),
		"diff_map_power": Fabric.read_element_absorbed_power(diff, "kinematic_map"),
		"diff_hash": Fabric.state_hash(diff),
	}
