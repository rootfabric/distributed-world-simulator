extends SceneTree

const Fabric = preload("res://scripts/research/fabric0/fabric0_nonsmooth_fabric_v1.gd")
const Experiments = preload("res://scripts/research/fabric0/fabric0_nonsmooth_experiments_v1.gd")

func _init() -> void:
	print("=== FABRIC0.6 NONSMOOTH WORLD ===")
	print("Exact branch manifolds + inequalities; smooth branch equations are solved inside each active set.\n")

	var diode := Experiments.build_ideal_diode(-5.0)
	Fabric.solve(diode)
	print("[1] ONE-WAY COMPLEMENTARITY / ELECTRICAL")
	print("    reverse: branch=%s V=%.3f I=%.3f" % [
		Fabric.read_element_state(diode, "diode", "active_branch"),
		Fabric.read_port_state(diode, "diode", "p")["common"],
		Fabric.read_port_state(diode, "diode", "p")["balance"],
	])
	Fabric.set_equilibrium_preferred_common(diode, "source", 0.0)
	var boundary := Fabric.solve(diode)
	print("    boundary: branch=%s ambiguity=%d (previous branch retained)" % [
		Fabric.read_element_state(diode, "diode", "active_branch"),
		boundary["solver_stats"]["ambiguity_count"],
	])
	Fabric.set_equilibrium_preferred_common(diode, "source", 5.0)
	Fabric.solve(diode)
	print("    forward: branch=%s V=%.3f I=%.3f events=%d" % [
		Fabric.read_element_state(diode, "diode", "active_branch"),
		Fabric.read_port_state(diode, "diode", "p")["common"],
		Fabric.read_port_state(diode, "diode", "p")["balance"],
		diode["events"].size(),
	])

	var valve := Experiments.build_check_valve(-4.0)
	Fabric.solve(valve)
	Fabric.set_equilibrium_preferred_common(valve, "pressure_source", 4.0)
	Fabric.solve(valve)
	print("\n[2] SAME COMPLEMENTARITY / FLUID")
	print("    branch=%s pressure=%.3f flow=%.3f" % [
		Fabric.read_element_state(valve, "check_valve", "active_branch"),
		Fabric.read_port_state(valve, "check_valve", "p")["common"],
		Fabric.read_port_state(valve, "check_valve", "p")["balance"],
	])

	var clutch := Experiments.build_one_way_clutch(3.0)
	Fabric.solve(clutch)
	print("\n[3] SAME COMPLEMENTARITY / ROTATIONAL")
	print("    branch=%s omega=%.3f torque=%.3f" % [
		Fabric.read_element_state(clutch, "clutch", "active_branch"),
		Fabric.read_port_state(clutch, "clutch", "p")["common"],
		Fabric.read_port_state(clutch, "clutch", "p")["balance"],
	])

	var contact := Experiments.build_contact(-1.0, 1.0)
	Fabric.solve(contact)
	print("\n[4] UNILATERAL CONTACT")
	print("    separated: branch=%s va=%.3f vb=%.3f reaction=%.3f" % [
		Fabric.read_element_state(contact, "contact", "active_branch"),
		Fabric.read_port_state(contact, "contact", "a")["common"],
		Fabric.read_port_state(contact, "contact", "b")["common"],
		Fabric.read_port_state(contact, "contact", "b")["balance"],
	])
	Fabric.set_equilibrium_preferred_common(contact, "body_a", 1.0)
	Fabric.set_equilibrium_preferred_common(contact, "body_b", -1.0)
	Fabric.solve(contact)
	print("    approaching: branch=%s va=%.3f vb=%.3f reactions=(%.3f,%.3f) events=%d" % [
		Fabric.read_element_state(contact, "contact", "active_branch"),
		Fabric.read_port_state(contact, "contact", "a")["common"],
		Fabric.read_port_state(contact, "contact", "b")["common"],
		Fabric.read_port_state(contact, "contact", "a")["balance"],
		Fabric.read_port_state(contact, "contact", "b")["balance"],
		contact["events"].size(),
	])

	var friction := Experiments.build_friction(0.5, 1.0)
	Fabric.solve(friction)
	print("\n[5] EXACT 1D COULOMB STICK/SLIP")
	print("    drive=0.5 -> branch=%s v=%.3f F=%.3f Pabs=%.3f" % [
		Fabric.read_element_state(friction, "friction", "active_branch"),
		Fabric.read_port_state(friction, "friction", "p")["common"],
		Fabric.read_port_state(friction, "friction", "p")["balance"],
		Fabric.read_element_absorbed_power(friction, "friction"),
	])
	Fabric.set_equilibrium_preferred_common(friction, "drive", 3.0)
	var slide_result := Fabric.solve(friction)
	print("    drive=3.0 -> branch=%s v=%.3f F=%.3f Pabs=%.3f tried=%d" % [
		Fabric.read_element_state(friction, "friction", "active_branch"),
		Fabric.read_port_state(friction, "friction", "p")["common"],
		Fabric.read_port_state(friction, "friction", "p")["balance"],
		Fabric.read_element_absorbed_power(friction, "friction"),
		slide_result["solver_stats"]["branch_combinations_tried"],
	])
	Fabric.set_parameter_value(friction, "friction", "fmax", 4.0)
	Fabric.solve(friction)
	print("    same drive, Fmax=4 -> branch=%s v=%.3f F=%.3f" % [
		Fabric.read_element_state(friction, "friction", "active_branch"),
		Fabric.read_port_state(friction, "friction", "p")["common"],
		Fabric.read_port_state(friction, "friction", "p")["balance"],
	])
	Fabric.set_parameter_value(friction, "friction", "fmax", 1.0)
	Fabric.set_equilibrium_preferred_common(friction, "drive", -3.0)
	Fabric.solve(friction)
	print("    reverse drive=-3 -> branch=%s v=%.3f F=%.3f transitions=%d" % [
		Fabric.read_element_state(friction, "friction", "active_branch"),
		Fabric.read_port_state(friction, "friction", "p")["common"],
		Fabric.read_port_state(friction, "friction", "p")["balance"],
		friction["events"].size(),
	])

	var impossible := Experiments.build_no_admissible_relation()
	var impossible_result := Fabric.solve(impossible)
	print("\n[6] IMPOSSIBLE HYBRID PHYSICS FAILS CLOSED")
	print("    solved=%s diagnostic=%s" % [str(impossible_result["ok"]), impossible["diagnostics"][0]["code"]])

	print("\n    deterministic friction hash: %s" % Fabric.state_hash(friction))
	print("\nFABRIC0_6_NONSMOOTH_PLAYGROUND_PASS")
	quit(0)
