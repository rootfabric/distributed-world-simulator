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
	assert(is_equal_approx(Kernel.read_input(lamp, "indicator"), 0.0)); checks += 1
	assert(Kernel.set_source_value(lamp, "switch", 1.0)); checks += 1
	Kernel.settle(lamp)
	assert(is_equal_approx(Kernel.read_input(lamp, "indicator"), 12.0)); checks += 1
	assert(Kernel.set_source_value(lamp, "switch", 0.0)); checks += 1
	Kernel.settle(lamp)
	assert(is_equal_approx(Kernel.read_input(lamp, "indicator"), 0.0)); checks += 1

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
	var history: Array[float] = []
	for _tick in range(8):
		Kernel.step(tank)
		history.append(float(Kernel.read_state(tank, "tank", "value")))
	assert(history.size() == 8); checks += 1
	assert(is_equal_approx(history[0], 2.0)); checks += 1
	assert(is_equal_approx(history[1], 4.0)); checks += 1
	assert(is_equal_approx(history[2], 6.0)); checks += 1
	assert(is_equal_approx(history[3], 8.0)); checks += 1
	assert(is_equal_approx(history[4], 8.0)); checks += 1
	assert(is_equal_approx(history[5], 8.0)); checks += 1
	assert(is_equal_approx(history[7], 8.0)); checks += 1

	var replay_a := Experiments.build_auto_fill_tank()
	var replay_b := Experiments.build_auto_fill_tank()
	for _tick in range(8):
		Kernel.step(replay_a)
		Kernel.step(replay_b)
	assert(Kernel.state_hash(replay_a).length() == 64); checks += 1
	assert(Kernel.state_hash(replay_a) == Kernel.state_hash(replay_b)); checks += 1

	var summary := Experiments.run_all()
	assert(is_equal_approx(float(summary["lamp_on"]), 12.0)); checks += 1
	assert(is_equal_approx(float(summary["converted_power"]), 72.0)); checks += 1
	assert(not bool(summary["breaker_active"])); checks += 1
	assert(int(summary["components_after"]) == 2); checks += 1
	assert(String(summary["tank_hash"]).length() == 64); checks += 1

	print("FABRIC0 Acceptance: PASS (%d assertions) lamp=%.1f converted=%.1f tank=%.1f hash=%s" % [
		checks,
		float(summary["lamp_on"]),
		float(summary["converted_power"]),
		float(summary["tank_level"]),
		String(summary["tank_hash"]),
	])
	quit(0)
