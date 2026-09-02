class_name Fabric0NonsmoothExperimentsV1
extends RefCounted

const Fabric = preload("res://scripts/research/fabric0/fabric0_nonsmooth_fabric_v1.gd")

static func register_electrical(net: Dictionary) -> bool:
	return Fabric.register_domain(net, "electrical", "voltage", "current", Fabric.dim_voltage(), Fabric.dim_current(), "V", "A", 1.0, 1.0)

static func register_translational(net: Dictionary) -> bool:
	return Fabric.register_domain(net, "translational", "velocity", "force", Fabric.dim_velocity(), Fabric.dim_force(), "m/s", "N", 1.0, 1.0)

static func register_rotational(net: Dictionary) -> bool:
	return Fabric.register_domain(net, "rotational", "angular_velocity", "torque", Fabric.dim_angular_velocity(), Fabric.dim_torque(), "rad/s", "N.m", 1.0, 1.0)

static func register_fluid(net: Dictionary) -> bool:
	return Fabric.register_domain(net, "fluid", "pressure", "volume_flow", Fabric.dim_pressure(), Fabric.dim_volume_flow(), "Pa", "m3/s", 1.0, 1.0)

static func one_way_relation(element_id: String, domain: String) -> Dictionary:
	# -common >= 0 ⟂ -balance >= 0.
	# blocked: balance=0, common<=0
	# conducting: common=0, balance<=0
	var branches := Fabric.complementarity_branches(
		"oneway",
		[],
		Fabric.expr_neg(Fabric.expr_common("p")),
		1.0,
		Fabric.expr_neg(Fabric.expr_balance("p")),
		1.0,
		1,
		0
	)
	return Fabric.hybrid_relation(element_id, {"p": domain}, {}, branches, "oneway:b_zero")

static func build_ideal_diode(preferred_voltage: float) -> Dictionary:
	var net := Fabric.new_network()
	assert(register_electrical(net))
	assert(Fabric.add_element(net, Fabric.equilibrium_terminal("source", "electrical", preferred_voltage, 1.0)))
	assert(Fabric.add_element(net, one_way_relation("diode", "electrical")))
	assert(Fabric.link_ports(net, "wire", "source", "p", "diode", "p"))
	return net

static func build_check_valve(preferred_pressure: float) -> Dictionary:
	var net := Fabric.new_network()
	assert(register_fluid(net))
	assert(Fabric.add_element(net, Fabric.equilibrium_terminal("pressure_source", "fluid", preferred_pressure, 1.0)))
	assert(Fabric.add_element(net, one_way_relation("check_valve", "fluid")))
	assert(Fabric.link_ports(net, "pipe", "pressure_source", "p", "check_valve", "p"))
	return net

static func contact_relation() -> Dictionary:
	var shared: Array = [Fabric.residual(
		Fabric.expr_add(Fabric.expr_balance("a"), Fabric.expr_balance("b")),
		1.0
	)]
	var separation_speed := Fabric.expr_sub(Fabric.expr_common("b"), Fabric.expr_common("a"))
	var normal_reaction := Fabric.expr_balance("b")
	var branches := Fabric.complementarity_branches(
		"contact",
		shared,
		separation_speed,
		1.0,
		normal_reaction,
		1.0,
		1,
		0
	)
	return Fabric.hybrid_relation(
		"contact",
		{"a": "translational", "b": "translational"},
		{},
		branches,
		"contact:b_zero"
	)

static func build_contact(preferred_a: float, preferred_b: float) -> Dictionary:
	var net := Fabric.new_network()
	assert(register_translational(net))
	assert(Fabric.add_element(net, Fabric.equilibrium_terminal("body_a", "translational", preferred_a, 1.0)))
	assert(Fabric.add_element(net, Fabric.equilibrium_terminal("body_b", "translational", preferred_b, 1.0)))
	assert(Fabric.add_element(net, contact_relation()))
	assert(Fabric.link_ports(net, "contact_a", "body_a", "p", "contact", "a"))
	assert(Fabric.link_ports(net, "contact_b", "body_b", "p", "contact", "b"))
	return net

static func friction_relation(fmax: float) -> Dictionary:
	var fmax_expr := Fabric.expr_parameter("fmax")
	var balance := Fabric.expr_balance("p")
	var common := Fabric.expr_common("p")
	var branches: Array = [
		Fabric.branch(
			"stick",
			[Fabric.residual(common, 1.0)],
			[
				Fabric.inequality(Fabric.expr_add(fmax_expr, balance), 1.0, "lower_cone_slack"),
				Fabric.inequality(Fabric.expr_sub(fmax_expr, balance), 1.0, "upper_cone_slack"),
			],
			0
		),
		Fabric.branch(
			"slide_pos",
			[Fabric.residual(Fabric.expr_add(balance, fmax_expr), 1.0)],
			[Fabric.inequality(common, 1.0, "positive_slip")],
			1
		),
		Fabric.branch(
			"slide_neg",
			[Fabric.residual(Fabric.expr_sub(balance, fmax_expr), 1.0)],
			[Fabric.inequality(Fabric.expr_neg(common), 1.0, "negative_slip")],
			1
		),
	]
	return Fabric.hybrid_relation(
		"friction",
		{"p": "translational"},
		{"fmax": {"value": fmax, "dimension": Fabric.dim_force()}},
		branches,
		"stick"
	)

static func build_friction(preferred_velocity: float, fmax: float = 1.0) -> Dictionary:
	var net := Fabric.new_network()
	assert(register_translational(net))
	assert(Fabric.add_element(net, Fabric.equilibrium_terminal("drive", "translational", preferred_velocity, 1.0)))
	assert(Fabric.add_element(net, friction_relation(fmax)))
	assert(Fabric.link_ports(net, "friction_contact", "drive", "p", "friction", "p"))
	return net

static func one_way_clutch_relation() -> Dictionary:
	var branches := Fabric.complementarity_branches(
		"clutch",
		[],
		Fabric.expr_neg(Fabric.expr_common("p")),
		1.0,
		Fabric.expr_neg(Fabric.expr_balance("p")),
		1.0,
		1,
		0
	)
	return Fabric.hybrid_relation("clutch", {"p": "rotational"}, {}, branches, "clutch:b_zero")

static func build_one_way_clutch(preferred_omega: float) -> Dictionary:
	var net := Fabric.new_network()
	assert(register_rotational(net))
	assert(Fabric.add_element(net, Fabric.equilibrium_terminal("shaft", "rotational", preferred_omega, 1.0)))
	assert(Fabric.add_element(net, one_way_clutch_relation()))
	assert(Fabric.link_ports(net, "clutch_shaft", "shaft", "p", "clutch", "p"))
	return net

static func build_no_admissible_relation() -> Dictionary:
	var net := Fabric.new_network()
	assert(register_electrical(net))
	assert(Fabric.add_element(net, Fabric.equilibrium_terminal("source", "electrical", 0.0, 1.0)))
	var impossible_branch := Fabric.branch(
		"impossible",
		[Fabric.residual(Fabric.expr_common("p"), 1.0)],
		[Fabric.inequality(Fabric.expr_sub(Fabric.expr_common("p"), Fabric.expr_constant(1.0, Fabric.dim_voltage())), 1.0, "must_be_at_least_one_volt")]
	)
	assert(Fabric.add_element(net, Fabric.hybrid_relation("impossible", {"p": "electrical"}, {}, [impossible_branch], "impossible")))
	assert(Fabric.link_ports(net, "wire", "source", "p", "impossible", "p"))
	return net

static func run_all() -> Dictionary:
	var diode := build_ideal_diode(-5.0)
	var diode_reverse := Fabric.solve(diode)
	Fabric.set_equilibrium_preferred_common(diode, "source", 5.0)
	var diode_forward := Fabric.solve(diode)

	var valve := build_check_valve(-4.0)
	var valve_reverse := Fabric.solve(valve)
	Fabric.set_equilibrium_preferred_common(valve, "pressure_source", 4.0)
	var valve_forward := Fabric.solve(valve)

	var contact := build_contact(-1.0, 1.0)
	var contact_open := Fabric.solve(contact)
	Fabric.set_equilibrium_preferred_common(contact, "body_a", 1.0)
	Fabric.set_equilibrium_preferred_common(contact, "body_b", -1.0)
	var contact_closed := Fabric.solve(contact)

	var friction := build_friction(0.5, 1.0)
	var friction_stick := Fabric.solve(friction)
	Fabric.set_equilibrium_preferred_common(friction, "drive", 3.0)
	var friction_slide := Fabric.solve(friction)

	return {
		"diode_reverse_ok": bool(diode_reverse["ok"]),
		"diode_forward_ok": bool(diode_forward["ok"]),
		"diode_branch": String(Fabric.read_element_state(diode, "diode", "active_branch")),
		"diode_voltage": float(Fabric.read_port_state(diode, "diode", "p")["common"]),
		"diode_current": float(Fabric.read_port_state(diode, "diode", "p")["balance"]),
		"valve_reverse_ok": bool(valve_reverse["ok"]),
		"valve_forward_ok": bool(valve_forward["ok"]),
		"valve_branch": String(Fabric.read_element_state(valve, "check_valve", "active_branch")),
		"valve_pressure": float(Fabric.read_port_state(valve, "check_valve", "p")["common"]),
		"valve_flow": float(Fabric.read_port_state(valve, "check_valve", "p")["balance"]),
		"contact_open_ok": bool(contact_open["ok"]),
		"contact_closed_ok": bool(contact_closed["ok"]),
		"contact_branch": String(Fabric.read_element_state(contact, "contact", "active_branch")),
		"contact_reaction": float(Fabric.read_port_state(contact, "contact", "b")["balance"]),
		"friction_stick_ok": bool(friction_stick["ok"]),
		"friction_slide_ok": bool(friction_slide["ok"]),
		"friction_branch": String(Fabric.read_element_state(friction, "friction", "active_branch")),
		"friction_velocity": float(Fabric.read_port_state(friction, "friction", "p")["common"]),
		"friction_force": float(Fabric.read_port_state(friction, "friction", "p")["balance"]),
		"friction_power": Fabric.read_element_absorbed_power(friction, "friction"),
		"friction_hash": Fabric.state_hash(friction),
	}
