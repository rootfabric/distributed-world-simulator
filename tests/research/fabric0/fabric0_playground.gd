extends SceneTree

const Kernel = preload("res://scripts/research/fabric0/fabric0_kernel_v1.gd")
const Experiments = preload("res://scripts/research/fabric0/fabric0_experiments_v1.gd")

func _init() -> void:
	print("=== FABRIC0 LOW-LEVEL PLAYGROUND ===")
	print("No Lamp, Motor, Fuse or Tank runtime classes exist here; only generic local laws and typed bonds.\n")

	var lamp := Experiments.build_switchable_lamp()
	Kernel.settle(lamp)
	print("[1] SWITCHABLE FUNCTION")
	print("    switch=0 -> indicator power = %.1f" % Kernel.read_input(lamp, "indicator"))
	Kernel.set_source_value(lamp, "switch", 1.0)
	Kernel.settle(lamp)
	print("    switch=1 -> indicator power = %.1f" % Kernel.read_input(lamp, "indicator"))

	var converter := Experiments.build_energy_converter()
	Kernel.settle(converter)
	print("\n[2] CROSS-DOMAIN COMPOSITION")
	print("    100 electric power -> converter(0.80) -> loss(0.90) -> %.1f rotational power" % Kernel.read_input(converter, "shaft_load"))

	var breaker := Experiments.build_breakable_link()
	Kernel.settle(breaker)
	print("\n[3] TOPOLOGY IS STATE")
	print("    before overload: components=%d receiver=%.1f" % [Kernel.connected_components(breaker).size(), Kernel.read_input(breaker, "receiver")])
	Kernel.step(breaker)
	print("    after overload:  components=%d receiver=%.1f bond_active=%s" % [Kernel.connected_components(breaker).size(), Kernel.read_input(breaker, "receiver"), str(Kernel.is_bond_active(breaker, "weak_bond"))])

	var tank := Experiments.build_auto_fill_tank()
	print("\n[4] CLOSED LOOP FROM THE SAME PRIMITIVES")
	for tick in range(8):
		Kernel.step(tank)
		print("    tick %d: level=%.1f valve_flow=%.1f control=%.0f" % [
			tick + 1,
			float(Kernel.read_state(tank, "tank", "value")),
			Kernel.read_output(tank, "valve"),
			Kernel.read_output(tank, "level_switch"),
		])
	print("\n    deterministic state hash: %s" % Kernel.state_hash(tank))
	print("\nFABRIC0_PLAYGROUND_PASS")
	quit(0)
