extends SceneTree

const Conservation = preload("res://scripts/research/fabric0/fabric0_conservation_fabric_v1.gd")
const Experiments = preload("res://scripts/research/fabric0/fabric0_conservation_experiments_v1.gd")

func _init() -> void:
	print("=== FABRIC0.3 CONSERVATION CELL PLAYGROUND ===")
	print("Topology creates cells. Cells equalize one common quantity and force the paired balance quantity to sum to zero.\n")

	var net := Experiments.build_two_source_cell()
	var result := Conservation.solve(net)
	print("[1] TWO SOURCES + ONE LOAD / NO DEVICE ROLES")
	print("    solved=%s common=%.6f" % [str(result["ok"]), Conservation.read_port_state(net, "source_a", "p")["common"]])
	for id in ["source_a", "source_b", "load"]:
		var port := Conservation.read_port_state(net, id, "p")
		print("    %s balance=%.6f power_into_cell=%.6f" % [id, port["balance"], port["power_into_cell"]])
	print("    residual balance=%.12f power=%.12f" % [Conservation.max_balance_residual(net), Conservation.max_power_residual(net)])

	var topology := Experiments.build_two_source_cell()
	Conservation.solve(topology)
	var topology_hash := Conservation.state_hash(topology)
	Conservation.set_bond_active(topology, "wire_a_b", false)
	var split := Conservation.solve(topology)
	print("\n[2] TOPOLOGY COMPILES EQUATIONS")
	print("    bond OFF -> cells=%d islands=%d sourceA_common=%.6f sourceB_load_common=%.6f" % [
		split["cell_count"],
		split["island_count"],
		Conservation.read_port_state(topology, "source_a", "p")["common"],
		Conservation.read_port_state(topology, "source_b", "p")["common"],
	])
	Conservation.set_bond_active(topology, "wire_a_b", true)
	Conservation.solve(topology)
	print("    bond ON  -> cells=%d common=%.6f state_restored=%s" % [
		topology["cells"].size(),
		Conservation.read_port_state(topology, "source_a", "p")["common"],
		str(Conservation.state_hash(topology) == topology_hash),
	])

	var reversal := Experiments.build_role_reversal_cell()
	Conservation.solve(reversal)
	var weak := Conservation.read_port_state(reversal, "weak_source", "p")
	print("\n[3] ROLE REVERSAL EMERGES")
	print("    shared common=%.6f" % weak["common"])
	print("    weak source balance=%.6f -> it became a sink without changing class" % weak["balance"])
	print("    weak source absorbed_power=%.6f" % Conservation.read_element_absorbed_power(reversal, "weak_source"))

	var ideal := Experiments.build_ideal_source_cell()
	Conservation.solve(ideal)
	print("\n[4] IDEAL CONSTRAINT USES A LAGRANGE FLOW")
	print("    common=%.6f ideal balance=%.6f loadA=%.6f loadB=%.6f" % [
		Conservation.read_port_state(ideal, "ideal_source", "p")["common"],
		Conservation.read_port_state(ideal, "ideal_source", "p")["balance"],
		Conservation.read_port_state(ideal, "load_a", "p")["balance"],
		Conservation.read_port_state(ideal, "load_b", "p")["balance"],
	])

	var conflict := Experiments.build_conflicting_ideal_cell()
	var conflict_result := Conservation.solve(conflict)
	print("\n[5] IMPOSSIBLE PHYSICS FAILS CLOSED")
	print("    solved=%s diagnostic=%s" % [str(conflict_result["ok"]), conflict["diagnostics"][0]["code"]])

	var bridge := Experiments.build_two_cell_bridge()
	Conservation.solve(bridge)
	print("\n[6] TWO CELLS + DIFFERENCE COUPLER")
	print("    source cell common=%.6f" % Conservation.read_port_state(bridge, "source", "p")["common"])
	print("    load   cell common=%.6f" % Conservation.read_port_state(bridge, "load", "p")["common"])
	print("    coupler absorbed power=%.6f" % Conservation.read_element_absorbed_power(bridge, "link"))
	print("    residual balance=%.12f power=%.12f" % [Conservation.max_balance_residual(bridge), Conservation.max_power_residual(bridge)])

	var rotational := Experiments.build_rotational_conservation_cell()
	Conservation.solve(rotational)
	print("\n[7] SAME CELL SEMANTICS, DIFFERENT PHYSICS DOMAIN")
	print("    domain common=angular_velocity, balance=torque")
	print("    omega=%.6f drive_torque=%.6f drag_torque=%.6f" % [
		Conservation.read_port_state(rotational, "drive", "p")["common"],
		Conservation.read_port_state(rotational, "drive", "p")["balance"],
		Conservation.read_port_state(rotational, "drag", "p")["balance"],
	])

	print("\n    deterministic hash: %s" % Conservation.state_hash(rotational))
	print("\nFABRIC0_3_CONSERVATION_PLAYGROUND_PASS")
	quit(0)
