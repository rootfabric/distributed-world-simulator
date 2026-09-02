extends SceneTree

const Fabric = preload("res://scripts/research/fabric0/fabric0_conservation_fabric_v2.gd")
const Experiments = preload("res://scripts/research/fabric0/fabric0_power_map_experiments_v1.gd")

func _init() -> void:
	print("=== FABRIC0.4 POWER MAP PLAYGROUND ===")
	print("A Power Map is a homogeneous constraint subspace. Constraint reactions route power but cannot create it.\n")

	var machine := Experiments.build_forward_machine()
	print("[1] MOTOR-LIKE MACHINE WITHOUT MOTOR CLASS")
	for tick in range(6):
		Fabric.step(machine, 1.0)
		var e := Fabric.read_port_state(machine, "transducer", "e")
		var m := Fabric.read_port_state(machine, "transducer", "m")
		print("    tick %d: V=%.6f I_map=%.6f omega=%.6f tau_map=%.6f E=%.6f Pmap=%.12f" % [
			tick + 1,
			e["common"], e["balance"], m["common"], m["balance"],
			float(Fabric.read_element_state(machine, "inertia", "energy")),
			Fabric.read_element_absorbed_power(machine, "transducer"),
		])

	print("\n[2] OPEN ELECTRICAL BOND -> BACK-EMF WITHOUT CURRENT")
	Fabric.set_bond_active(machine, "supply_link", false)
	Fabric.step(machine, 1.0)
	var open_e := Fabric.read_port_state(machine, "transducer", "e")
	var open_m := Fabric.read_port_state(machine, "transducer", "m")
	print("    V=%.6f I=%.6f omega=%.6f torque=%.6f" % [open_e["common"], open_e["balance"], open_m["common"], open_m["balance"]])

	var generator := Experiments.build_reverse_generator()
	Fabric.solve(generator)
	var ge := Fabric.read_port_state(generator, "transducer", "e")
	var gm := Fabric.read_port_state(generator, "transducer", "m")
	print("\n[3] SAME MAP, REVERSED ENERGY DIRECTION")
	print("    electrical: V=%.6f I=%.6f" % [ge["common"], ge["balance"]])
	print("    mechanical: omega=%.6f torque=%.6f" % [gm["common"], gm["balance"]])
	print("    map absorbed power=%.12f" % Fabric.read_element_absorbed_power(generator, "transducer"))

	var diff := Experiments.build_open_differential()
	Fabric.solve(diff)
	var left := Fabric.read_port_state(diff, "kinematic_map", "left")
	var right := Fabric.read_port_state(diff, "kinematic_map", "right")
	var carrier := Fabric.read_port_state(diff, "kinematic_map", "carrier")
	print("\n[4] THREE-PORT DIFFERENTIAL-LIKE MAP")
	print("    omega_left=%.6f omega_right=%.6f omega_carrier=%.6f" % [left["common"], right["common"], carrier["common"]])
	print("    relation left+right=2*carrier -> %s" % str(is_equal_approx(float(left["common"]) + float(right["common"]), 2.0 * float(carrier["common"]))))
	print("    reaction torques=(%.6f, %.6f, %.6f)" % [left["balance"], right["balance"], carrier["balance"]])
	print("    map absorbed power=%.12f" % Fabric.read_element_absorbed_power(diff, "kinematic_map"))

	print("\n    deterministic differential hash: %s" % Fabric.state_hash(diff))
	print("\nFABRIC0_4_POWER_MAP_PLAYGROUND_PASS")
	quit(0)
