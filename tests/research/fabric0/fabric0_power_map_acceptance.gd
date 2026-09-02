extends SceneTree

const Fabric = preload("res://scripts/research/fabric0/fabric0_conservation_fabric_v2.gd")
const Experiments = preload("res://scripts/research/fabric0/fabric0_power_map_experiments_v1.gd")

func _init() -> void:
	var checks := 0

	var forward := Experiments.build_forward_machine()
	var static_result := Fabric.solve(forward)
	assert(not bool(static_result["ok"])); checks += 1
	assert(forward["diagnostics"].size() == 1); checks += 1
	assert(String(forward["diagnostics"][0]["code"]) == "DYNAMIC_ELEMENT_REQUIRES_STEP"); checks += 1

	var first := Fabric.step(forward, 1.0)
	assert(bool(first["ok"])); checks += 1
	var v1 := Fabric.read_port_state(forward, "transducer", "e")
	var w1 := Fabric.read_port_state(forward, "transducer", "m")
	var supply1 := Fabric.read_port_state(forward, "supply", "p")
	var inertia1 := Fabric.read_port_state(forward, "inertia", "p")
	var drag1 := Fabric.read_port_state(forward, "drag", "p")
	assert(is_equal_approx(float(v1["common"]), 64.0 / 7.0)); checks += 1
	assert(is_equal_approx(float(w1["common"]), 32.0 / 7.0)); checks += 1
	assert(is_equal_approx(float(v1["common"]), 2.0 * float(w1["common"]))); checks += 1
	assert(is_equal_approx(float(v1["balance"]), -40.0 / 7.0)); checks += 1
	assert(is_equal_approx(float(w1["balance"]), 80.0 / 7.0)); checks += 1
	assert(absf(Fabric.read_element_absorbed_power(forward, "transducer")) <= 1.0e-9); checks += 1
	assert(Fabric.max_balance_residual(forward) <= 1.0e-9); checks += 1
	assert(Fabric.max_power_residual(forward) <= 1.0e-9); checks += 1
	assert(absf(Fabric.total_absorbed_power(forward)) <= 1.0e-9); checks += 1
	assert(is_equal_approx(float(supply1["balance"]), 40.0 / 7.0)); checks += 1
	assert(is_equal_approx(float(drag1["balance"]), -16.0 / 7.0)); checks += 1
	assert(is_equal_approx(float(inertia1["balance"]), -64.0 / 7.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_element_state(forward, "inertia", "energy")), 1024.0 / 49.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_element_state(forward, "inertia", "last_delta_energy")), 1024.0 / 49.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_element_state(forward, "inertia", "last_absorbed_work")), 2048.0 / 49.0)); checks += 1
	assert(is_equal_approx(float(Fabric.read_element_state(forward, "inertia", "last_numerical_dissipation")), 1024.0 / 49.0)); checks += 1

	var expected := [
		32.0 / 7.0,
		800.0 / 147.0,
		17312.0 / 3087.0,
		365600.0 / 64827.0,
		7685792.0 / 1361367.0,
		161434400.0 / 28588707.0,
	]
	var history: Array = [float(w1["common"])]
	for _i in range(5):
		var result := Fabric.step(forward, 1.0)
		assert(bool(result["ok"])); checks += 1
		history.append(float(Fabric.read_port_state(forward, "inertia", "p")["common"]))
	for i in range(expected.size()):
		assert(is_equal_approx(float(history[i]), float(expected[i]))); checks += 1
	assert(history[5] > history[4]); checks += 1
	assert(history[5] < 5.65); checks += 1
	assert(absf(Fabric.read_element_absorbed_power(forward, "transducer")) <= 1.0e-9); checks += 1

	var speed_before_open := float(Fabric.read_port_state(forward, "inertia", "p")["common"])
	assert(Fabric.set_bond_active(forward, "supply_link", false)); checks += 1
	var open_result := Fabric.step(forward, 1.0)
	assert(bool(open_result["ok"])); checks += 1
	var open_e := Fabric.read_port_state(forward, "transducer", "e")
	var open_m := Fabric.read_port_state(forward, "transducer", "m")
	assert(is_equal_approx(float(open_m["common"]), 0.8 * speed_before_open)); checks += 1
	assert(is_equal_approx(float(open_e["common"]), 2.0 * float(open_m["common"]))); checks += 1
	assert(is_equal_approx(float(open_e["balance"]), 0.0)); checks += 1
	assert(is_equal_approx(float(open_m["balance"]), 0.0)); checks += 1
	assert(absf(Fabric.read_element_absorbed_power(forward, "transducer")) <= 1.0e-9); checks += 1
	assert(Fabric.max_power_residual(forward) <= 1.0e-9); checks += 1

	var reverse := Experiments.build_reverse_generator()
	var reverse_result := Fabric.solve(reverse)
	assert(bool(reverse_result["ok"])); checks += 1
	var re := Fabric.read_port_state(reverse, "transducer", "e")
	var rm := Fabric.read_port_state(reverse, "transducer", "m")
	var load := Fabric.read_port_state(reverse, "electrical_load", "p")
	var drive := Fabric.read_port_state(reverse, "shaft_drive", "p")
	assert(is_equal_approx(float(re["common"]), 20.0 / 3.0)); checks += 1
	assert(is_equal_approx(float(rm["common"]), 10.0 / 3.0)); checks += 1
	assert(is_equal_approx(float(re["balance"]), 20.0 / 3.0)); checks += 1
	assert(is_equal_approx(float(rm["balance"]), -40.0 / 3.0)); checks += 1
	assert(is_equal_approx(float(load["balance"]), -20.0 / 3.0)); checks += 1
	assert(is_equal_approx(float(drive["balance"]), 40.0 / 3.0)); checks += 1
	assert(absf(Fabric.read_element_absorbed_power(reverse, "transducer")) <= 1.0e-9); checks += 1
	assert(is_equal_approx(Fabric.read_element_absorbed_power(reverse, "electrical_load"), 400.0 / 9.0)); checks += 1
	assert(is_equal_approx(Fabric.read_element_absorbed_power(reverse, "shaft_drive"), -400.0 / 9.0)); checks += 1
	assert(absf(Fabric.total_absorbed_power(reverse)) <= 1.0e-9); checks += 1

	var diff := Experiments.build_open_differential()
	var diff_result := Fabric.solve(diff)
	assert(bool(diff_result["ok"])); checks += 1
	var left := Fabric.read_port_state(diff, "kinematic_map", "left")
	var right := Fabric.read_port_state(diff, "kinematic_map", "right")
	var carrier := Fabric.read_port_state(diff, "kinematic_map", "carrier")
	assert(is_equal_approx(float(left["common"]), 24.0 / 7.0)); checks += 1
	assert(is_equal_approx(float(right["common"]), 12.0 / 7.0)); checks += 1
	assert(is_equal_approx(float(carrier["common"]), 18.0 / 7.0)); checks += 1
	assert(is_equal_approx(float(left["common"]) + float(right["common"]), 2.0 * float(carrier["common"]))); checks += 1
	assert(is_equal_approx(float(left["balance"]), 24.0 / 7.0)); checks += 1
	assert(is_equal_approx(float(right["balance"]), 24.0 / 7.0)); checks += 1
	assert(is_equal_approx(float(carrier["balance"]), -48.0 / 7.0)); checks += 1
	assert(absf(Fabric.read_element_absorbed_power(diff, "kinematic_map")) <= 1.0e-9); checks += 1
	assert(absf(Fabric.total_absorbed_power(diff)) <= 1.0e-9); checks += 1

	var replay_a := Experiments.build_forward_machine()
	var replay_b := Experiments.build_forward_machine()
	for _i in range(6):
		assert(bool(Fabric.step(replay_a, 1.0)["ok"])); checks += 1
		assert(bool(Fabric.step(replay_b, 1.0)["ok"])); checks += 1
	assert(Fabric.state_hash(replay_a).length() == 64); checks += 1
	assert(Fabric.state_hash(replay_a) == Fabric.state_hash(replay_b)); checks += 1

	var diff_a := Experiments.build_open_differential()
	var diff_b := Experiments.build_open_differential()
	assert(bool(Fabric.solve(diff_a)["ok"])); checks += 1
	assert(bool(Fabric.solve(diff_b)["ok"])); checks += 1
	assert(Fabric.state_hash(diff_a) == Fabric.state_hash(diff_b)); checks += 1

	var summary := Experiments.run_all()
	assert(bool(summary["open_result_ok"])); checks += 1
	assert(float(summary["open_after"]) < float(summary["open_before"])); checks += 1
	assert(is_equal_approx(float(summary["open_current"]), 0.0)); checks += 1
	assert(bool(summary["reverse_ok"])); checks += 1
	assert(is_equal_approx(float(summary["reverse_voltage"]), 20.0 / 3.0)); checks += 1
	assert(is_equal_approx(float(summary["reverse_omega"]), 10.0 / 3.0)); checks += 1
	assert(bool(summary["diff_ok"])); checks += 1
	assert(is_equal_approx(float(summary["diff_left"]) + float(summary["diff_right"]), 2.0 * float(summary["diff_carrier"]))); checks += 1
	assert(String(summary["diff_hash"]).length() == 64); checks += 1

	print("FABRIC0.4 Power Map Acceptance: PASS (%d assertions) forward_omega=%.9f open_omega=%.9f reverse=(V=%.3f,w=%.3f) diff=(%.6f,%.6f,%.6f) hash=%s" % [
		checks,
		float(summary["open_before"]),
		float(summary["open_after"]),
		float(summary["reverse_voltage"]),
		float(summary["reverse_omega"]),
		float(summary["diff_left"]),
		float(summary["diff_right"]),
		float(summary["diff_carrier"]),
		String(summary["diff_hash"]),
	])
	quit(0)
