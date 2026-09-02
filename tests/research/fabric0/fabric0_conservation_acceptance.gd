extends SceneTree

const Conservation = preload("res://scripts/research/fabric0/fabric0_conservation_fabric_v1.gd")
const Experiments = preload("res://scripts/research/fabric0/fabric0_conservation_experiments_v1.gd")

func _init() -> void:
	var checks := 0

	var domain_guard := Conservation.new_network()
	assert(Conservation.register_domain(domain_guard, "electric", "voltage", "current", "V", "A")); checks += 1
	assert(Conservation.register_domain(domain_guard, "rotational", "angular_velocity", "torque", "rad/s", "N*m")); checks += 1
	assert(not Conservation.register_domain(domain_guard, "electric", "voltage", "current")); checks += 1
	assert(Conservation.add_element(domain_guard, Conservation.equilibrium_terminal("electric_port", "electric", 1.0, 1.0))); checks += 1
	assert(Conservation.add_element(domain_guard, Conservation.equilibrium_terminal("rot_port", "rotational", 1.0, 1.0))); checks += 1
	assert(not Conservation.link_ports(domain_guard, "bad_cross_domain", "electric_port", "p", "rot_port", "p")); checks += 1

	var two_source := Experiments.build_two_source_cell()
	var two_source_result := Conservation.solve(two_source)
	assert(bool(two_source_result["ok"])); checks += 1
	assert(int(two_source_result["cell_count"]) == 1); checks += 1
	assert(int(two_source_result["island_count"]) == 1); checks += 1
	var a := Conservation.read_port_state(two_source, "source_a", "p")
	var b := Conservation.read_port_state(two_source, "source_b", "p")
	var load := Conservation.read_port_state(two_source, "load", "p")
	assert(is_equal_approx(float(a["common"]), 5.0)); checks += 1
	assert(is_equal_approx(float(b["common"]), 5.0)); checks += 1
	assert(is_equal_approx(float(load["common"]), 5.0)); checks += 1
	assert(is_equal_approx(float(a["balance"]), 14.0)); checks += 1
	assert(is_equal_approx(float(b["balance"]), 1.0)); checks += 1
	assert(is_equal_approx(float(load["balance"]), -15.0)); checks += 1
	assert(is_equal_approx(float(a["balance"]) + float(b["balance"]) + float(load["balance"]), 0.0)); checks += 1
	assert(Conservation.max_balance_residual(two_source) <= 1.0e-9); checks += 1
	assert(Conservation.max_power_residual(two_source) <= 1.0e-9); checks += 1
	assert(is_equal_approx(float(a["power_into_cell"]), 70.0)); checks += 1
	assert(is_equal_approx(float(b["power_into_cell"]), 5.0)); checks += 1
	assert(is_equal_approx(float(load["power_into_cell"]), -75.0)); checks += 1
	assert(is_equal_approx(float(a["power_into_cell"]) + float(b["power_into_cell"]) + float(load["power_into_cell"]), 0.0)); checks += 1

	var topology := Experiments.build_two_source_cell()
	assert(bool(Conservation.solve(topology)["ok"])); checks += 1
	var topology_initial_hash := Conservation.state_hash(topology)
	assert(is_equal_approx(float(Conservation.read_port_state(topology, "source_a", "p")["common"]), 5.0)); checks += 1
	assert(Conservation.set_bond_active(topology, "wire_a_b", false)); checks += 1
	var split_result := Conservation.solve(topology)
	assert(bool(split_result["ok"])); checks += 1
	assert(int(split_result["cell_count"]) == 2); checks += 1
	assert(int(split_result["island_count"]) == 2); checks += 1
	assert(is_equal_approx(float(Conservation.read_port_state(topology, "source_a", "p")["common"]), 12.0)); checks += 1
	assert(is_equal_approx(float(Conservation.read_port_state(topology, "source_a", "p")["balance"]), 0.0)); checks += 1
	assert(is_equal_approx(float(Conservation.read_port_state(topology, "source_b", "p")["common"]), 1.5)); checks += 1
	assert(is_equal_approx(float(Conservation.read_port_state(topology, "load", "p")["common"]), 1.5)); checks += 1
	assert(Conservation.set_bond_active(topology, "wire_a_b", true)); checks += 1
	var rejoin_result := Conservation.solve(topology)
	assert(bool(rejoin_result["ok"])); checks += 1
	assert(int(rejoin_result["cell_count"]) == 1); checks += 1
	assert(is_equal_approx(float(Conservation.read_port_state(topology, "source_a", "p")["common"]), 5.0)); checks += 1
	assert(Conservation.state_hash(topology) == topology_initial_hash); checks += 1

	var reversal := Experiments.build_role_reversal_cell()
	var reversal_result := Conservation.solve(reversal)
	assert(bool(reversal_result["ok"])); checks += 1
	var strong := Conservation.read_port_state(reversal, "strong_source", "p")
	var weak := Conservation.read_port_state(reversal, "weak_source", "p")
	var reversal_load := Conservation.read_port_state(reversal, "load", "p")
	assert(is_equal_approx(float(strong["common"]), 8.0)); checks += 1
	assert(is_equal_approx(float(strong["balance"]), 12.0)); checks += 1
	assert(is_equal_approx(float(weak["balance"]), -4.0)); checks += 1
	assert(is_equal_approx(float(reversal_load["balance"]), -8.0)); checks += 1
	assert(float(weak["balance"]) < 0.0); checks += 1
	assert(is_equal_approx(Conservation.read_element_absorbed_power(reversal, "weak_source"), 32.0)); checks += 1
	assert(Conservation.max_power_residual(reversal) <= 1.0e-9); checks += 1

	var ideal := Experiments.build_ideal_source_cell()
	var ideal_result := Conservation.solve(ideal)
	assert(bool(ideal_result["ok"])); checks += 1
	var ideal_source := Conservation.read_port_state(ideal, "ideal_source", "p")
	var ideal_load_a := Conservation.read_port_state(ideal, "load_a", "p")
	var ideal_load_b := Conservation.read_port_state(ideal, "load_b", "p")
	assert(is_equal_approx(float(ideal_source["common"]), 10.0)); checks += 1
	assert(is_equal_approx(float(ideal_load_a["common"]), 10.0)); checks += 1
	assert(is_equal_approx(float(ideal_load_b["common"]), 10.0)); checks += 1
	assert(is_equal_approx(float(ideal_load_a["balance"]), -20.0)); checks += 1
	assert(is_equal_approx(float(ideal_load_b["balance"]), -10.0)); checks += 1
	assert(is_equal_approx(float(ideal_source["balance"]), 30.0)); checks += 1
	assert(Conservation.max_balance_residual(ideal) <= 1.0e-9); checks += 1
	assert(Conservation.max_power_residual(ideal) <= 1.0e-9); checks += 1

	var conflict := Experiments.build_conflicting_ideal_cell()
	var conflict_result := Conservation.solve(conflict)
	assert(not bool(conflict_result["ok"])); checks += 1
	assert(conflict["diagnostics"].size() == 1); checks += 1
	assert(String(conflict["diagnostics"][0]["code"]) == "CONSTRAINT_CONFLICT"); checks += 1
	assert(String(conflict["cells"][0]["status"]) == "CONSTRAINT_CONFLICT"); checks += 1

	var floating := Experiments.build_floating_pair()
	var floating_result := Conservation.solve(floating)
	assert(not bool(floating_result["ok"])); checks += 1
	assert(floating["diagnostics"].size() == 1); checks += 1
	assert(String(floating["diagnostics"][0]["code"]) == "SINGULAR_FLOATING_ISLAND"); checks += 1
	assert(floating["cells"].size() == 2); checks += 1

	var bridge := Experiments.build_two_cell_bridge()
	var bridge_result := Conservation.solve(bridge)
	assert(bool(bridge_result["ok"])); checks += 1
	assert(int(bridge_result["cell_count"]) == 2); checks += 1
	assert(int(bridge_result["island_count"]) == 1); checks += 1
	var bridge_source := Conservation.read_port_state(bridge, "source", "p")
	var bridge_a := Conservation.read_port_state(bridge, "link", "a")
	var bridge_b := Conservation.read_port_state(bridge, "link", "b")
	var bridge_load := Conservation.read_port_state(bridge, "load", "p")
	assert(is_equal_approx(float(bridge_source["common"]), 9.6)); checks += 1
	assert(is_equal_approx(float(bridge_a["common"]), 9.6)); checks += 1
	assert(is_equal_approx(float(bridge_b["common"]), 4.8)); checks += 1
	assert(is_equal_approx(float(bridge_load["common"]), 4.8)); checks += 1
	assert(is_equal_approx(float(bridge_source["balance"]), 4.8)); checks += 1
	assert(is_equal_approx(float(bridge_a["balance"]), -4.8)); checks += 1
	assert(is_equal_approx(float(bridge_b["balance"]), 4.8)); checks += 1
	assert(is_equal_approx(float(bridge_load["balance"]), -4.8)); checks += 1
	assert(is_equal_approx(Conservation.read_element_absorbed_power(bridge, "link"), 23.04)); checks += 1
	assert(Conservation.max_balance_residual(bridge) <= 1.0e-9); checks += 1
	assert(Conservation.max_power_residual(bridge) <= 1.0e-9); checks += 1

	var fixed := Experiments.build_fixed_balance_cell()
	var fixed_result := Conservation.solve(fixed)
	assert(bool(fixed_result["ok"])); checks += 1
	var flow_source := Conservation.read_port_state(fixed, "flow_source", "p")
	var fixed_load := Conservation.read_port_state(fixed, "load", "p")
	assert(is_equal_approx(float(flow_source["common"]), 1.5)); checks += 1
	assert(is_equal_approx(float(flow_source["balance"]), 3.0)); checks += 1
	assert(is_equal_approx(float(fixed_load["balance"]), -3.0)); checks += 1
	assert(Conservation.max_power_residual(fixed) <= 1.0e-9); checks += 1

	var rotational := Experiments.build_rotational_conservation_cell()
	var rotational_result := Conservation.solve(rotational)
	assert(bool(rotational_result["ok"])); checks += 1
	var drive := Conservation.read_port_state(rotational, "drive", "p")
	var drag := Conservation.read_port_state(rotational, "drag", "p")
	assert(is_equal_approx(float(drive["common"]), 20.0 / 3.0)); checks += 1
	assert(is_equal_approx(float(drag["common"]), 20.0 / 3.0)); checks += 1
	assert(is_equal_approx(float(drive["balance"]), 20.0 / 3.0)); checks += 1
	assert(is_equal_approx(float(drag["balance"]), -20.0 / 3.0)); checks += 1
	assert(Conservation.max_balance_residual(rotational) <= 1.0e-9); checks += 1
	assert(Conservation.max_power_residual(rotational) <= 1.0e-9); checks += 1

	var replay_a := Experiments.build_two_source_cell()
	var replay_b := Experiments.build_two_source_cell()
	assert(bool(Conservation.solve(replay_a)["ok"])); checks += 1
	assert(bool(Conservation.solve(replay_b)["ok"])); checks += 1
	assert(Conservation.state_hash(replay_a).length() == 64); checks += 1
	assert(Conservation.state_hash(replay_a) == Conservation.state_hash(replay_b)); checks += 1

	var bridge_replay_a := Experiments.build_two_cell_bridge()
	var bridge_replay_b := Experiments.build_two_cell_bridge()
	assert(bool(Conservation.solve(bridge_replay_a)["ok"])); checks += 1
	assert(bool(Conservation.solve(bridge_replay_b)["ok"])); checks += 1
	assert(Conservation.state_hash(bridge_replay_a) == Conservation.state_hash(bridge_replay_b)); checks += 1

	var summary := Experiments.run_all()
	assert(bool(summary["two_source_ok"])); checks += 1
	assert(is_equal_approx(float(summary["two_source_common"]), 5.0)); checks += 1
	assert(is_equal_approx(float(summary["two_source_a_balance"]), 14.0)); checks += 1
	assert(is_equal_approx(float(summary["two_source_b_balance"]), 1.0)); checks += 1
	assert(is_equal_approx(float(summary["two_source_load_balance"]), -15.0)); checks += 1
	assert(float(summary["two_source_power_residual"]) <= 1.0e-9); checks += 1
	assert(bool(summary["reversal_ok"])); checks += 1
	assert(is_equal_approx(float(summary["reversal_common"]), 8.0)); checks += 1
	assert(is_equal_approx(float(summary["reversal_weak_balance"]), -4.0)); checks += 1
	assert(is_equal_approx(float(summary["reversal_weak_absorbed_power"]), 32.0)); checks += 1
	assert(bool(summary["ideal_ok"])); checks += 1
	assert(is_equal_approx(float(summary["ideal_common"]), 10.0)); checks += 1
	assert(is_equal_approx(float(summary["ideal_balance"]), 30.0)); checks += 1
	assert(bool(summary["bridge_ok"])); checks += 1
	assert(is_equal_approx(float(summary["bridge_source_common"]), 9.6)); checks += 1
	assert(is_equal_approx(float(summary["bridge_load_common"]), 4.8)); checks += 1
	assert(is_equal_approx(float(summary["bridge_absorbed_power"]), 23.04)); checks += 1
	assert(bool(summary["fixed_ok"])); checks += 1
	assert(is_equal_approx(float(summary["fixed_common"]), 1.5)); checks += 1
	assert(bool(summary["rotational_ok"])); checks += 1
	assert(is_equal_approx(float(summary["rotational_common"]), 20.0 / 3.0)); checks += 1
	assert(is_equal_approx(float(summary["rotational_drive_balance"]), 20.0 / 3.0)); checks += 1
	assert(is_equal_approx(float(summary["rotational_drag_balance"]), -20.0 / 3.0)); checks += 1
	assert(String(summary["rotational_hash"]).length() == 64); checks += 1

	print("FABRIC0.3 Conservation Acceptance: PASS (%d assertions) junction=%.6f role_reversal=%.6f bridge=(%.6f->%.6f) rotational=%.6f hash=%s" % [
		checks,
		float(summary["two_source_common"]),
		float(summary["reversal_common"]),
		float(summary["bridge_source_common"]),
		float(summary["bridge_load_common"]),
		float(summary["rotational_common"]),
		String(summary["rotational_hash"]),
	])
	quit(0)
