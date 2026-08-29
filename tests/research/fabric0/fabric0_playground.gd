extends SceneTree

const Kernel = preload("res://scripts/research/fabric0/fabric0_kernel_v1.gd")
const Experiments = preload("res://scripts/research/fabric0/fabric0_experiments_v1.gd")

func _init() -> void:
	print("=== FABRIC0 LOW-LEVEL PLAYGROUND ===")
	print("Device names live in experiments; the kernel still only knows generic local laws, typed ports, state and bonds.\n")

	var lamp := Experiments.build_switchable_lamp()
	Kernel.settle(lamp)
	print("[1] INLINE SWITCH -> LAMP")
	print("    switch OPEN   -> lamp power=%.1f lit=%s" % [Kernel.read_input(lamp, "lamp"), str(Kernel.read_output(lamp, "lamp") > 0.5)])
	Kernel.set_switch_state(lamp, "wall_switch", true)
	Kernel.settle(lamp)
	print("    switch CLOSED -> lamp power=%.1f lit=%s" % [Kernel.read_input(lamp, "lamp"), str(Kernel.read_output(lamp, "lamp") > 0.5)])
	Kernel.set_switch_state(lamp, "wall_switch", false)
	Kernel.settle(lamp)
	print("    switch OPEN   -> lamp power=%.1f lit=%s" % [Kernel.read_input(lamp, "lamp"), str(Kernel.read_output(lamp, "lamp") > 0.5)])

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
	print("\n[4] SAME FEEDBACK PATTERN: TANK")
	for tick in range(6):
		Kernel.step(tank)
		print("    tick %d: level=%.1f flow=%.1f control=%.0f" % [
			tick + 1,
			float(Kernel.read_state(tank, "store", "value")),
			Kernel.read_output(tank, "gate"),
			Kernel.read_output(tank, "controller"),
		])

	var heater := Experiments.build_regulated_heater()
	print("\n[5] SAME FEEDBACK PATTERN: HEATER")
	for tick in range(6):
		Kernel.step(heater)
		print("    tick %d: temperature=%.1f rate=%.1f control=%.0f" % [
			tick + 1,
			float(Kernel.read_state(heater, "store", "value")),
			Kernel.read_output(heater, "gate"),
			Kernel.read_output(heater, "controller"),
		])

	var door := Experiments.build_proximity_door()
	Kernel.step(door)
	print("\n[6] CONTROL + STATE: PROXIMITY DOOR")
	print("    no proximity -> position=%.1f" % float(Kernel.read_state(door, "position", "value")))
	Kernel.set_source_value(door, "proximity", 1.0)
	Kernel.step(door)
	Kernel.step(door)
	print("    proximity=1 -> position=%.1f" % float(Kernel.read_state(door, "position", "value")))

	var rotation := Experiments.build_rotational_drive()
	print("\n[7] TWO-WAY ROTATIONAL WALL: TORQUE <-> SPEED")
	print("    motor torque passes through the same generic Switch used by the lamp")
	for tick in range(8):
		Kernel.step(rotation)
		print("    tick %d: omega=%.6f drive=%.6f reaction=%.6f net=%.6f energy=%.6f" % [
			tick + 1,
			float(Kernel.read_state(rotation, "flywheel", "speed")),
			Kernel.read_output(rotation, "motor_switch"),
			Kernel.read_output(rotation, "load", "reaction_torque"),
			Kernel.read_input(rotation, "flywheel", "torque"),
			float(Kernel.read_state(rotation, "flywheel", "energy")),
		])
	print("    opening motor switch...")
	Kernel.set_switch_state(rotation, "motor_switch", false)
	Kernel.step(rotation)
	print("    coast: omega=%.6f drive=%.1f reaction=%.6f" % [
		float(Kernel.read_state(rotation, "flywheel", "speed")),
		Kernel.read_output(rotation, "motor_switch"),
		Kernel.read_output(rotation, "load", "reaction_torque"),
	])
	print("    local discrete work == kinetic-energy delta: %s" % str(is_equal_approx(
		float(Kernel.read_state(rotation, "flywheel", "last_work")),
		float(Kernel.read_state(rotation, "flywheel", "last_delta_energy"))
	)))

	print("\n    deterministic rotational hash: %s" % Kernel.state_hash(rotation))
	print("\nFABRIC0_PLAYGROUND_PASS")
	quit(0)
