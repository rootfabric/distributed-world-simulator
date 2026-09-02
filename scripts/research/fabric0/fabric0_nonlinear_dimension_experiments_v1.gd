class_name Fabric0NonlinearDimensionExperimentsV1
extends RefCounted

const Fabric = preload("res://scripts/research/fabric0/fabric0_conservation_fabric_v3.gd")

static func register_electrical(net: Dictionary) -> bool:
	return Fabric.register_domain(
		net,
		"electrical",
		"voltage",
		"current",
		Fabric.dim_voltage(),
		Fabric.dim_current(),
		"V",
		"A",
		1.0,
		1.0
	)

static func register_rotational(net: Dictionary) -> bool:
	return Fabric.register_domain(
		net,
		"rotational",
		"angular_velocity",
		"torque",
		Fabric.dim_angular_velocity(),
		Fabric.dim_torque(),
		"rad/s",
		"N.m",
		1.0,
		1.0
	)

static func build_diode_like_bias() -> Dictionary:
	var net := Fabric.new_network()
	assert(register_electrical(net))
	assert(Fabric.add_element(net, Fabric.fixed_balance_terminal("bias", "electrical", 3.0)))
	var diode_residual := Fabric.expr_add(
		Fabric.expr_balance("p"),
		Fabric.expr_mul(
			Fabric.expr_parameter("isat"),
			Fabric.expr_sub(
				Fabric.expr_exp(
					Fabric.expr_div(Fabric.expr_common("p"), Fabric.expr_parameter("vscale"))
				),
				Fabric.expr_constant(1.0, Fabric.dim_dimensionless())
			)
		)
	)
	assert(Fabric.add_element(net, Fabric.nonlinear_constitutive(
		"diode_like",
		{"p": "electrical"},
		{
			"isat": {"value": 1.0, "dimension": Fabric.dim_current()},
			"vscale": {"value": 1.0, "dimension": Fabric.dim_voltage()},
		},
		[{
			"expr": diode_residual,
			"nominal": 1.0,
		}]
	)))
	assert(Fabric.link_ports(net, "bias_diode", "bias", "p", "diode_like", "p"))
	return net

static func build_saturating_supply() -> Dictionary:
	var net := Fabric.new_network()
	assert(register_electrical(net))
	assert(Fabric.add_element(net, Fabric.equilibrium_terminal("load", "electrical", 0.0, 1.0)))
	var saturation_argument := Fabric.expr_div(
		Fabric.expr_sub(Fabric.expr_parameter("preferred"), Fabric.expr_common("p")),
		Fabric.expr_parameter("width")
	)
	var saturation_current := Fabric.expr_mul(
		Fabric.expr_parameter("imax"),
		Fabric.expr_tanh(saturation_argument)
	)
	var residual := Fabric.expr_sub(Fabric.expr_balance("p"), saturation_current)
	assert(Fabric.add_element(net, Fabric.nonlinear_constitutive(
		"saturating_source",
		{"p": "electrical"},
		{
			"imax": {"value": 2.0, "dimension": Fabric.dim_current()},
			"preferred": {"value": 5.0, "dimension": Fabric.dim_voltage()},
			"width": {"value": 1.0, "dimension": Fabric.dim_voltage()},
		},
		[{
			"expr": residual,
			"nominal": 1.0,
		}]
	)))
	assert(Fabric.link_ports(net, "supply_load", "saturating_source", "p", "load", "p"))
	return net

static func build_cubic_rotational_drag() -> Dictionary:
	var net := Fabric.new_network()
	assert(register_rotational(net))
	assert(Fabric.add_element(net, Fabric.fixed_balance_terminal("drive", "rotational", 3.0)))
	var omega_cubed := Fabric.expr_pow_int(Fabric.expr_common("p"), 3)
	var drag_torque := Fabric.expr_mul(Fabric.expr_parameter("k"), omega_cubed)
	var residual := Fabric.expr_add(Fabric.expr_balance("p"), drag_torque)
	assert(Fabric.add_element(net, Fabric.nonlinear_constitutive(
		"cubic_drag",
		{"p": "rotational"},
		{
			"k": {
				"value": 1.0,
				"dimension": Fabric.dim_div(Fabric.dim_torque(), Fabric.dim_pow(Fabric.dim_angular_velocity(), 3)),
			},
		},
		[{
			"expr": residual,
			"nominal": 1.0,
		}]
	)))
	assert(Fabric.link_ports(net, "drive_drag", "drive", "p", "cubic_drag", "p"))
	return net

static func build_dimensioned_cross_domain_map() -> Dictionary:
	var net := Fabric.new_network()
	assert(register_electrical(net))
	assert(register_rotational(net))
	assert(Fabric.add_element(net, Fabric.equilibrium_terminal("electrical_source", "electrical", 12.0, 2.0)))
	assert(Fabric.add_element(net, Fabric.equilibrium_terminal("rotational_load", "rotational", 0.0, 1.0)))
	var map := Fabric.linear_power_map(
		"dimensioned_map",
		{"e": "electrical", "m": "rotational"},
		[{
			"terms": [
				{
					"port": "e",
					"coefficient": 1.0,
					"coefficient_dimension": Fabric.dim_dimensionless(),
				},
				{
					"port": "m",
					"coefficient": -2.0,
					"coefficient_dimension": Fabric.dim_div(Fabric.dim_voltage(), Fabric.dim_angular_velocity()),
				},
			],
			"nominal": 10.0,
		}]
	)
	assert(Fabric.add_element(net, map))
	assert(Fabric.link_ports(net, "source_map", "electrical_source", "p", "dimensioned_map", "e"))
	assert(Fabric.link_ports(net, "map_load", "dimensioned_map", "m", "rotational_load", "p"))
	return net

static func build_impossible_nonlinear_cell() -> Dictionary:
	var net := Fabric.new_network()
	assert(register_electrical(net))
	var residual := Fabric.expr_add(
		Fabric.expr_pow_int(Fabric.expr_balance("p"), 2),
		Fabric.expr_parameter("floor")
	)
	assert(Fabric.add_element(net, Fabric.nonlinear_constitutive(
		"impossible",
		{"p": "electrical"},
		{
			"floor": {"value": 1.0, "dimension": Fabric.dim_pow(Fabric.dim_current(), 2)},
		},
		[{
			"expr": residual,
			"nominal": 1.0,
		}]
	)))
	return net

static func run_all() -> Dictionary:
	var diode := build_diode_like_bias()
	var diode_result := Fabric.solve(diode)

	var saturation := build_saturating_supply()
	var saturation_result := Fabric.solve(saturation)

	var cubic := build_cubic_rotational_drag()
	var cubic_result := Fabric.solve(cubic)

	var cross := build_dimensioned_cross_domain_map()
	var cross_result := Fabric.solve(cross)

	return {
		"diode_ok": bool(diode_result["ok"]),
		"diode_voltage": float(Fabric.read_port_state(diode, "diode_like", "p")["common"]),
		"diode_current": float(Fabric.read_port_state(diode, "diode_like", "p")["balance"]),
		"diode_iterations": int(diode_result.get("iterations", 0)),
		"diode_residual": float(diode_result.get("normalized_residual", 0.0)),
		"saturation_ok": bool(saturation_result["ok"]),
		"saturation_voltage": float(Fabric.read_port_state(saturation, "saturating_source", "p")["common"]),
		"saturation_current": float(Fabric.read_port_state(saturation, "saturating_source", "p")["balance"]),
		"saturation_iterations": int(saturation_result.get("iterations", 0)),
		"cubic_ok": bool(cubic_result["ok"]),
		"cubic_omega": float(Fabric.read_port_state(cubic, "cubic_drag", "p")["common"]),
		"cubic_torque": float(Fabric.read_port_state(cubic, "cubic_drag", "p")["balance"]),
		"cubic_iterations": int(cubic_result.get("iterations", 0)),
		"cross_ok": bool(cross_result["ok"]),
		"cross_voltage": float(Fabric.read_port_state(cross, "dimensioned_map", "e")["common"]),
		"cross_omega": float(Fabric.read_port_state(cross, "dimensioned_map", "m")["common"]),
		"cross_current": float(Fabric.read_port_state(cross, "dimensioned_map", "e")["balance"]),
		"cross_torque": float(Fabric.read_port_state(cross, "dimensioned_map", "m")["balance"]),
		"cross_map_power": Fabric.read_element_absorbed_power(cross, "dimensioned_map"),
		"cross_hash": Fabric.state_hash(cross),
	}
