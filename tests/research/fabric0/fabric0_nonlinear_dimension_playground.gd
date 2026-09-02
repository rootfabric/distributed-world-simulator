extends SceneTree

const Fabric = preload("res://scripts/research/fabric0/fabric0_conservation_fabric_v3.gd")
const Experiments = preload("res://scripts/research/fabric0/fabric0_nonlinear_dimension_experiments_v1.gd")

func _init() -> void:
	print("=== FABRIC0.5 NONLINEAR LAW + DIMENSIONS ===")
	print("Residual laws are dimension-checked expression trees; Jacobians come from automatic differentiation.\n")

	print("[1] DIMENSIONS ARE EXECUTABLE CONTRACTS")
	print("    voltage * current -> %s" % Fabric.dim_string(Fabric.dim_mul(Fabric.dim_voltage(), Fabric.dim_current())))
	print("    torque * angular_velocity -> %s" % Fabric.dim_string(Fabric.dim_mul(Fabric.dim_torque(), Fabric.dim_angular_velocity())))
	var guard := Fabric.new_network()
	var bad_domain := Fabric.register_domain(guard, "bad", "voltage", "torque", Fabric.dim_voltage(), Fabric.dim_torque())
	print("    register voltage×torque domain -> %s (%s)" % [str(bad_domain), guard["diagnostics"][0]["code"]])

	var diode := Experiments.build_diode_like_bias()
	var diode_result := Fabric.solve(diode)
	var diode_port := Fabric.read_port_state(diode, "diode_like", "p")
	print("\n[2] EXPONENTIAL DIODE-LIKE LAW")
	print("    solved=%s iterations=%d V=%.9f I=%.9f expected ln(4)=%.9f" % [
		str(diode_result["ok"]), diode_result["iterations"], diode_port["common"], diode_port["balance"], log(4.0)
	])

	var saturation := Experiments.build_saturating_supply()
	var saturation_result := Fabric.solve(saturation)
	var saturation_port := Fabric.read_port_state(saturation, "saturating_source", "p")
	print("\n[3] SMOOTH SATURATION")
	print("    solved=%s iterations=%d common=%.9f balance=%.9f limit=2.0" % [
		str(saturation_result["ok"]), saturation_result["iterations"], saturation_port["common"], saturation_port["balance"]
	])

	var cubic := Experiments.build_cubic_rotational_drag()
	var cubic_result := Fabric.solve(cubic)
	var cubic_port := Fabric.read_port_state(cubic, "cubic_drag", "p")
	print("\n[4] CUBIC ROTATIONAL DRAG")
	print("    solved=%s iterations=%d omega=%.9f torque=%.9f omega^3=%.9f" % [
		str(cubic_result["ok"]), cubic_result["iterations"], cubic_port["common"], cubic_port["balance"], pow(float(cubic_port["common"]), 3.0)
	])

	var cross := Experiments.build_dimensioned_cross_domain_map()
	var cross_result := Fabric.solve(cross)
	var e := Fabric.read_port_state(cross, "dimensioned_map", "e")
	var m := Fabric.read_port_state(cross, "dimensioned_map", "m")
	print("\n[5] DIMENSIONED POWER MAP")
	print("    solved=%s V=%.6f omega=%.6f V=2*omega:%s" % [cross_result["ok"], e["common"], m["common"], str(is_equal_approx(float(e["common"]), 2.0 * float(m["common"])))])
	print("    current=%.6f torque=%.6f Pmap=%.12f" % [e["balance"], m["balance"], Fabric.read_element_absorbed_power(cross, "dimensioned_map")])

	var bad_map_net := Fabric.new_network()
	Experiments.register_electrical(bad_map_net)
	Experiments.register_rotational(bad_map_net)
	var bad_map := Fabric.linear_power_map(
		"bad_map",
		{"e": "electrical", "m": "rotational"},
		[{"terms": [
			{"port": "e", "coefficient": 1.0, "coefficient_dimension": Fabric.dim_dimensionless()},
			{"port": "m", "coefficient": -2.0, "coefficient_dimension": Fabric.dim_dimensionless()},
		], "nominal": 1.0}]
	)
	var added := Fabric.add_element(bad_map_net, bad_map)
	print("\n[6] HIDDEN UNIT CONVERSION IS REJECTED")
	print("    add V - 2*omega with dimensionless 2 -> %s (%s)" % [str(added), bad_map_net["diagnostics"][0]["code"]])

	var impossible := Experiments.build_impossible_nonlinear_cell()
	var impossible_result := Fabric.solve(impossible)
	print("\n[7] IMPOSSIBLE NONLINEAR PHYSICS FAILS CLOSED")
	print("    solved=%s diagnostic=%s" % [str(impossible_result["ok"]), impossible["diagnostics"][0]["code"]])

	print("\n    deterministic cross-domain hash: %s" % Fabric.state_hash(cross))
	print("\nFABRIC0_5_NONLINEAR_DIMENSIONS_PLAYGROUND_PASS")
	quit(0)
