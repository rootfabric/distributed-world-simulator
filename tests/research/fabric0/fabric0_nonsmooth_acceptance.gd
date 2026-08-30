extends SceneTree

const Fabric = preload("res://scripts/research/fabric0/fabric0_nonsmooth_fabric_v1.gd")
const Experiments = preload("res://scripts/research/fabric0/fabric0_nonsmooth_experiments_v1.gd")

func _init() -> void:
	var checks := 0

	# Dimension/power conjugacy survives into nonsmooth successor.
	assert(Fabric.dim_equal(Fabric.dim_mul(Fabric.dim_voltage(), Fabric.dim_current()), Fabric.dim_power())); checks += 1
	assert(Fabric.dim_equal(Fabric.dim_mul(Fabric.dim_force(), Fabric.dim_velocity()), Fabric.dim_power())); checks += 1
	assert(Fabric.dim_equal(Fabric.dim_mul(Fabric.dim_pressure(), Fabric.dim_volume_flow()), Fabric.dim_power())); checks += 1
	assert(Fabric.dim_equal(Fabric.dim_mul(Fabric.dim_torque(), Fabric.dim_angular_velocity()), Fabric.dim_power())); checks += 1

	var bad_domain := Fabric.new_network()
	assert(not Fabric.register_domain(bad_domain, "bad", "voltage", "torque", Fabric.dim_voltage(), Fabric.dim_torque())); checks += 1
	assert(String(bad_domain["diagnostics"][0]["code"]) == "DOMAIN_NOT_POWER_CONJUGATE"); checks += 1

	# Exact complementarity compiler creates two smooth manifolds.
	var comp := Fabric.complementarity_branches(
		"pair", [],
		Fabric.expr_common("p"), 1.0,
		Fabric.expr_balance("p"), 1.0
	)
	assert(comp.size() == 2); checks += 1
	assert(String(comp[0]["id"]) == "pair:a_zero"); checks += 1
	assert(String(comp[1]["id"]) == "pair:b_zero"); checks += 1

	# Ideal hard diode: reverse is blocked.
	var diode := Experiments.build_ideal_diode(-5.0)
	var result := Fabric.solve(diode)
	assert(bool(result["ok"])); checks += 1
	assert(String(Fabric.read_element_state(diode, "diode", "active_branch")) == "oneway:b_zero"); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(diode, "diode", "p")["common"]), -5.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(diode, "diode", "p")["balance"]), 0.0)); checks += 1
	assert(Fabric.max_balance_residual(diode) <= 1.0e-9); checks += 1
	assert(Fabric.max_power_residual(diode) <= 1.0e-9); checks += 1

	# At exact switching surface both branches are valid; previous state wins.
	assert(Fabric.set_equilibrium_preferred_common(diode, "source", 0.0)); checks += 1
	result = Fabric.solve(diode)
	assert(bool(result["ok"])); checks += 1
	assert(String(Fabric.read_element_state(diode, "diode", "active_branch")) == "oneway:b_zero"); checks += 1
	assert(int(result["solver_stats"]["ambiguity_count"]) >= 1); checks += 1
	assert(diode["events"].is_empty()); checks += 1

	# Forward drive closes complementarity on common=0 and creates reaction flow.
	assert(Fabric.set_equilibrium_preferred_common(diode, "source", 5.0)); checks += 1
	result = Fabric.solve(diode)
	assert(bool(result["ok"])); checks += 1
	assert(String(Fabric.read_element_state(diode, "diode", "active_branch")) == "oneway:a_zero"); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(diode, "diode", "p")["common"]), 0.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(diode, "diode", "p")["balance"]), -5.0)); checks += 1
	assert(diode["events"].size() == 1); checks += 1
	assert(String(diode["events"][0]["type"]) == "nonsmooth_transition"); checks += 1
	assert(String(diode["events"][0]["from"]) == "oneway:b_zero"); checks += 1
	assert(String(diode["events"][0]["to"]) == "oneway:a_zero"); checks += 1

	# Reverse again: state returns to blocked and records another discrete event.
	assert(Fabric.set_equilibrium_preferred_common(diode, "source", -2.0)); checks += 1
	assert(bool(Fabric.solve(diode)["ok"])); checks += 1
	assert(String(Fabric.read_element_state(diode, "diode", "active_branch")) == "oneway:b_zero"); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(diode, "diode", "p")["common"]), -2.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(diode, "diode", "p")["balance"]), 0.0)); checks += 1
	assert(diode["events"].size() == 2); checks += 1

	# Same exact complementarity grammar works in pressure/flow domain.
	var valve := Experiments.build_check_valve(-4.0)
	assert(bool(Fabric.solve(valve)["ok"])); checks += 1
	assert(String(Fabric.read_element_state(valve, "check_valve", "active_branch")) == "oneway:b_zero"); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(valve, "check_valve", "p")["common"]), -4.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(valve, "check_valve", "p")["balance"]), 0.0)); checks += 1
	assert(Fabric.set_equilibrium_preferred_common(valve, "pressure_source", 4.0)); checks += 1
	assert(bool(Fabric.solve(valve)["ok"])); checks += 1
	assert(String(Fabric.read_element_state(valve, "check_valve", "active_branch")) == "oneway:a_zero"); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(valve, "check_valve", "p")["common"]), 0.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(valve, "check_valve", "p")["balance"]), -4.0)); checks += 1

	# Same one-way complementarity also works as a rotational stop/clutch relation.
	var clutch := Experiments.build_one_way_clutch(-3.0)
	assert(bool(Fabric.solve(clutch)["ok"])); checks += 1
	assert(String(Fabric.read_element_state(clutch, "clutch", "active_branch")) == "clutch:b_zero"); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(clutch, "clutch", "p")["common"]), -3.0)); checks += 1
	assert(Fabric.set_equilibrium_preferred_common(clutch, "shaft", 3.0)); checks += 1
	assert(bool(Fabric.solve(clutch)["ok"])); checks += 1
	assert(String(Fabric.read_element_state(clutch, "clutch", "active_branch")) == "clutch:a_zero"); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(clutch, "clutch", "p")["common"]), 0.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(clutch, "clutch", "p")["balance"]), -3.0)); checks += 1

	# Two-port unilateral contact: separated bodies carry zero reaction.
	var contact := Experiments.build_contact(-1.0, 1.0)
	assert(bool(Fabric.solve(contact)["ok"])); checks += 1
	assert(String(Fabric.read_element_state(contact, "contact", "active_branch")) == "contact:b_zero"); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(contact, "contact", "a")["common"]), -1.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(contact, "contact", "b")["common"]), 1.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(contact, "contact", "a")["balance"]), 0.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(contact, "contact", "b")["balance"]), 0.0)); checks += 1

	# Approaching bodies activate contact: equal normal velocity + equal/opposite reaction.
	assert(Fabric.set_equilibrium_preferred_common(contact, "body_a", 1.0)); checks += 1
	assert(Fabric.set_equilibrium_preferred_common(contact, "body_b", -1.0)); checks += 1
	assert(bool(Fabric.solve(contact)["ok"])); checks += 1
	assert(String(Fabric.read_element_state(contact, "contact", "active_branch")) == "contact:a_zero"); checks += 1
	var ca := Fabric.read_port_state(contact, "contact", "a")
	var cb := Fabric.read_port_state(contact, "contact", "b")
	assert(is_equal_approx(float(ca["common"]), 0.0)); checks += 1
	assert(is_equal_approx(float(cb["common"]), 0.0)); checks += 1
	assert(is_equal_approx(float(ca["balance"]), -1.0)); checks += 1
	assert(is_equal_approx(float(cb["balance"]), 1.0)); checks += 1
	assert(is_equal_approx(float(ca["balance"]) + float(cb["balance"]), 0.0)); checks += 1
	assert(contact["events"].size() == 1); checks += 1
	assert(absf(Fabric.read_element_absorbed_power(contact, "contact")) <= 1.0e-9); checks += 1

	# At zero load both open/closed are admissible, but previous closed state remains selected.
	assert(Fabric.set_equilibrium_preferred_common(contact, "body_a", 0.0)); checks += 1
	assert(Fabric.set_equilibrium_preferred_common(contact, "body_b", 0.0)); checks += 1
	var boundary_contact := Fabric.solve(contact)
	assert(bool(boundary_contact["ok"])); checks += 1
	assert(String(Fabric.read_element_state(contact, "contact", "active_branch")) == "contact:a_zero"); checks += 1
	assert(int(boundary_contact["solver_stats"]["ambiguity_count"]) >= 1); checks += 1
	assert(contact["events"].size() == 1); checks += 1

	# Exact 1D Coulomb set-valued friction: below limit -> stick.
	var friction := Experiments.build_friction(0.5, 1.0)
	assert(bool(Fabric.solve(friction)["ok"])); checks += 1
	assert(String(Fabric.read_element_state(friction, "friction", "active_branch")) == "stick"); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(friction, "friction", "p")["common"]), 0.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(friction, "friction", "p")["balance"]), -0.5)); checks += 1
	assert(absf(Fabric.read_element_absorbed_power(friction, "friction")) <= 1.0e-9); checks += 1

	# Above limit -> positive sliding with force on exact Coulomb boundary.
	assert(Fabric.set_equilibrium_preferred_common(friction, "drive", 3.0)); checks += 1
	assert(bool(Fabric.solve(friction)["ok"])); checks += 1
	assert(String(Fabric.read_element_state(friction, "friction", "active_branch")) == "slide_pos"); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(friction, "friction", "p")["common"]), 2.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(friction, "friction", "p")["balance"]), -1.0)); checks += 1
	assert(is_equal_approx(Fabric.read_element_absorbed_power(friction, "friction"), 2.0)); checks += 1
	assert(friction["events"].size() == 1); checks += 1

	# Larger friction bound returns the same physical element to stick.
	assert(Fabric.set_parameter_value(friction, "friction", "fmax", 4.0)); checks += 1
	assert(bool(Fabric.solve(friction)["ok"])); checks += 1
	assert(String(Fabric.read_element_state(friction, "friction", "active_branch")) == "stick"); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(friction, "friction", "p")["common"]), 0.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(friction, "friction", "p")["balance"]), -3.0)); checks += 1
	assert(friction["events"].size() == 2); checks += 1

	# Restore bound and reverse hard enough -> negative sliding branch.
	assert(Fabric.set_parameter_value(friction, "friction", "fmax", 1.0)); checks += 1
	assert(Fabric.set_equilibrium_preferred_common(friction, "drive", -3.0)); checks += 1
	assert(bool(Fabric.solve(friction)["ok"])); checks += 1
	assert(String(Fabric.read_element_state(friction, "friction", "active_branch")) == "slide_neg"); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(friction, "friction", "p")["common"]), -2.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_port_state(friction, "friction", "p")["balance"]), 1.0)); checks += 1
	assert(is_equal_approx(Fabric.read_element_absorbed_power(friction, "friction"), 2.0)); checks += 1
	assert(friction["events"].size() == 3); checks += 1

	# No branch satisfying both equations and inequalities is an explicit failure.
	var impossible := Experiments.build_no_admissible_relation()
	var impossible_result := Fabric.solve(impossible)
	assert(not bool(impossible_result["ok"])); checks += 1
	assert(impossible["diagnostics"].size() == 1); checks += 1
	assert(String(impossible["diagnostics"][0]["code"]) == "NO_ADMISSIBLE_NONSMOOTH_BRANCH"); checks += 1

	# Deterministic event + branch replay.
	var replay_a := Experiments.build_friction(0.5, 1.0)
	var replay_b := Experiments.build_friction(0.5, 1.0)
	for net in [replay_a, replay_b]:
		assert(bool(Fabric.solve(net)["ok"])); checks += 1
		Fabric.set_equilibrium_preferred_common(net, "drive", 3.0)
		assert(bool(Fabric.solve(net)["ok"])); checks += 1
		Fabric.set_parameter_value(net, "friction", "fmax", 4.0)
		assert(bool(Fabric.solve(net)["ok"])); checks += 1
	assert(Fabric.state_hash(replay_a).length() == 64); checks += 1
	assert(Fabric.state_hash(replay_a) == Fabric.state_hash(replay_b)); checks += 1

	var summary := Experiments.run_all()
	assert(bool(summary["diode_forward_ok"])); checks += 1
	assert(String(summary["diode_branch"]) == "oneway:a_zero"); checks += 1
	assert(bool(summary["valve_forward_ok"])); checks += 1
	assert(String(summary["valve_branch"]) == "oneway:a_zero"); checks += 1
	assert(bool(summary["contact_closed_ok"])); checks += 1
	assert(String(summary["contact_branch"]) == "contact:a_zero"); checks += 1
	assert(bool(summary["friction_slide_ok"])); checks += 1
	assert(String(summary["friction_branch"]) == "slide_pos"); checks += 1
	assert(String(summary["friction_hash"]).length() == 64); checks += 1

	print("FABRIC0.6 Nonsmooth Acceptance: PASS (%d assertions) diode=(V=%.3f,I=%.3f) contact_reaction=%.3f friction=(v=%.3f,F=%.3f,P=%.3f) hash=%s" % [
		checks,
		float(summary["diode_voltage"]),
		float(summary["diode_current"]),
		float(summary["contact_reaction"]),
		float(summary["friction_velocity"]),
		float(summary["friction_force"]),
		float(summary["friction_power"]),
		String(summary["friction_hash"]),
	])
	quit(0)
