extends SceneTree

const Kernel = preload("res://scripts/research/fabric0/fabric0_kernel_v1.gd")
const Experiments = preload("res://scripts/research/fabric0/fabric0_experiments_v1.gd")

func _init() -> void:
	var checks := 0

	var invalid := Kernel.new_graph()
	assert(Kernel.add_element(invalid, Kernel.source("power", "power", 1.0))); checks += 1
	assert(Kernel.add_element(invalid, Kernel.sink("signal_sink", "signal"))); checks += 1
	assert(not Kernel.link(invalid, "bad_domain", "power", "out", "signal_sink", "in")); checks += 1

	var lamp := Experiments.build_switchable_lamp()
	Kernel.settle(lamp)
	assert(not bool(Kernel.read_state(lamp, "wall_switch", "closed"))); checks += 1
	assert(is_equal_approx(Kernel.read_input(lamp, "lamp"), 0.0)); checks += 1
	assert(is_equal_approx(Kernel.read_output(lamp, "lamp"), 0.0)); checks += 1
	assert(Kernel.set_switch_state(lamp, "wall_switch", true)); checks += 1
	Kernel.settle(lamp)
	assert(bool(Kernel.read_state(lamp, "wall_switch", "closed"))); checks += 1
	assert(is_equal_approx(Kernel.read_input(lamp, "lamp"), 12.0)); checks += 1
	assert(is_equal_approx(Kernel.read_output(lamp, "lamp"), 1.0)); checks += 1
	assert(not Kernel.set_switch_state(lamp, "battery", false)); checks += 1
	assert(Kernel.set_switch_state(lamp, "wall_switch", false)); checks += 1
	Kernel.settle(lamp)
	assert(is_equal_approx(Kernel.read_output(lamp, "lamp"), 0.0)); checks += 1

	var converter := Experiments.build_energy_converter()
	Kernel.settle(converter)
	assert(is_equal_approx(Kernel.read_input(converter, "shaft_load"), 72.0)); checks += 1
	assert(converter["elements"].size() == 4); checks += 1

	var breaker := Experiments.build_breakable_link(10.0, 5.0)
	Kernel.settle(breaker)
	assert(Kernel.connected_components(breaker).size() == 1); checks += 1
	assert(is_equal_approx(Kernel.read_input(breaker, "receiver"), 10.0)); checks += 1
	Kernel.step(breaker)
	assert(not Kernel.is_bond_active(breaker, "weak_bond")); checks += 1
	assert(Kernel.connected_components(breaker).size() == 2); checks += 1
	assert(is_equal_approx(Kernel.read_input(breaker, "receiver"), 0.0)); checks += 1
	assert(breaker["events"].size() == 1); checks += 1
	assert(String(breaker["events"][0]["type"]) == "bond_broken"); checks += 1

	var tank := Experiments.build_auto_fill_tank()
	var tank_history: Array[float] = []
	for _tick in range(8):
		Kernel.step(tank)
		tank_history.append(float(Kernel.read_state(tank, "store", "value")))
	assert(tank_history.size() == 8); checks += 1
	assert(is_equal_approx(tank_history[0], 2.0)); checks += 1
	assert(is_equal_approx(tank_history[1], 4.0)); checks += 1
	assert(is_equal_approx(tank_history[2], 6.0)); checks += 1
	assert(is_equal_approx(tank_history[3], 8.0)); checks += 1
	assert(is_equal_approx(tank_history[4], 8.0)); checks += 1
	assert(is_equal_approx(tank_history[7], 8.0)); checks += 1

	var heater := Experiments.build_regulated_heater()
	var heater_history: Array[float] = []
	for _tick in range(8):
		Kernel.step(heater)
		heater_history.append(float(Kernel.read_state(heater, "store", "value")))
	assert(is_equal_approx(heater_history[0], 19.0)); checks += 1
	assert(is_equal_approx(heater_history[1], 20.0)); checks += 1
	assert(is_equal_approx(heater_history[2], 21.0)); checks += 1
	assert(is_equal_approx(heater_history[3], 22.0)); checks += 1
	assert(is_equal_approx(heater_history[7], 22.0)); checks += 1
	assert(tank["elements"].size() == heater["elements"].size()); checks += 1

	var door := Experiments.build_proximity_door()
	Kernel.step(door)
	assert(is_equal_approx(float(Kernel.read_state(door, "position", "value")), 0.0)); checks += 1
	assert(Kernel.set_source_value(door, "proximity", 1.0)); checks += 1
	Kernel.step(door)
	Kernel.step(door)
	assert(is_equal_approx(float(Kernel.read_state(door, "position", "value")), 2.0)); checks += 1

	var rotation := Experiments.build_rotational_drive()
	Kernel.settle(rotation)
	assert(is_equal_approx(Kernel.read_input(rotation, "flywheel", "torque"), 4.0)); checks += 1
	Kernel.step(rotation)
	assert(is_equal_approx(float(Kernel.read_state(rotation, "flywheel", "speed")), 2.0)); checks += 1
	assert(is_equal_approx(Kernel.read_output(rotation, "load", "reaction_torque"), -2.0)); checks += 1
	assert(is_equal_approx(Kernel.read_input(rotation, "flywheel", "torque"), 2.0)); checks += 1
	assert(is_equal_approx(float(Kernel.read_state(rotation, "flywheel", "last_delta_energy")), 4.0)); checks += 1
	assert(is_equal_approx(float(Kernel.read_state(rotation, "flywheel", "last_work")), 4.0)); checks += 1
	Kernel.step(rotation)
	var second_delta_angle := float(Kernel.read_state(rotation, "flywheel", "last_delta_angle"))
	var second_delta_energy := float(Kernel.read_state(rotation, "flywheel", "last_delta_energy"))
	var drive_work := 4.0 * second_delta_angle
	var load_work := -2.0 * second_delta_angle
	assert(is_equal_approx(float(Kernel.read_state(rotation, "flywheel", "speed")), 3.0)); checks += 1
	assert(is_equal_approx(second_delta_angle, 2.5)); checks += 1
	assert(is_equal_approx(second_delta_energy, 5.0)); checks += 1
	assert(is_equal_approx(drive_work + load_work, second_delta_energy)); checks += 1
	for _tick in range(6):
		Kernel.step(rotation)
	assert(is_equal_approx(float(Kernel.read_state(rotation, "flywheel", "speed")), 3.984375)); checks += 1
	assert(is_equal_approx(Kernel.read_output(rotation, "load", "reaction_torque"), -3.984375)); checks += 1
	assert(Kernel.set_switch_state(rotation, "motor_switch", false)); checks += 1
	Kernel.step(rotation)
	assert(is_equal_approx(float(Kernel.read_state(rotation, "flywheel", "speed")), 1.9921875)); checks += 1
	assert(is_equal_approx(Kernel.read_output(rotation, "motor_switch"), 0.0)); checks += 1

	var replay_a := Experiments.build_auto_fill_tank()
	var replay_b := Experiments.build_auto_fill_tank()
	for _tick in range(8):
		Kernel.step(replay_a)
		Kernel.step(replay_b)
	assert(Kernel.state_hash(replay_a).length() == 64); checks += 1
	assert(Kernel.state_hash(replay_a) == Kernel.state_hash(replay_b)); checks += 1

	var rotation_replay_a := Experiments.build_rotational_drive()
	var rotation_replay_b := Experiments.build_rotational_drive()
	for _tick in range(8):
		Kernel.step(rotation_replay_a)
		Kernel.step(rotation_replay_b)
	assert(Kernel.state_hash(rotation_replay_a) == Kernel.state_hash(rotation_replay_b)); checks += 1

	var summary := Experiments.run_all()
	assert(is_equal_approx(float(summary["lamp_open_signal"]), 0.0)); checks += 1
	assert(is_equal_approx(float(summary["lamp_closed_power"]), 12.0)); checks += 1
	assert(is_equal_approx(float(summary["lamp_closed_signal"]), 1.0)); checks += 1
	assert(is_equal_approx(float(summary["converted_power"]), 72.0)); checks += 1
	assert(not bool(summary["breaker_active"])); checks += 1
	assert(int(summary["components_after"]) == 2); checks += 1
	assert(is_equal_approx(float(summary["tank_level"]), 8.0)); checks += 1
	assert(is_equal_approx(float(summary["heater_temperature"]), 22.0)); checks += 1
	assert(is_equal_approx(float(summary["door_closed"]), 0.0)); checks += 1
	assert(is_equal_approx(float(summary["door_opening"]), 2.0)); checks += 1
	assert(is_equal_approx(float(summary["rotation_loaded_speed"]), 3.984375)); checks += 1
	assert(is_equal_approx(float(summary["rotation_coast_speed"]), 1.9921875)); checks += 1
	assert(String(summary["tank_hash"]).length() == 64); checks += 1
	assert(String(summary["rotation_hash"]).length() == 64); checks += 1

	print("FABRIC0 Acceptance: PASS (%d assertions) lamp=%s power=%.1f tank=%.1f heater=%.1f door=%.1f omega=%.6f coast=%.6f hash=%s" % [
		checks,
		"ON" if is_equal_approx(float(summary["lamp_closed_signal"]), 1.0) else "OFF",
		float(summary["lamp_closed_power"]),
		float(summary["tank_level"]),
		float(summary["heater_temperature"]),
		float(summary["door_opening"]),
		float(summary["rotation_loaded_speed"]),
		float(summary["rotation_coast_speed"]),
		String(summary["rotation_hash"]),
	])
	quit(0)
