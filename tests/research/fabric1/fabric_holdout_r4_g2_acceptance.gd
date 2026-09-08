extends SceneTree

const B = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_canonical_bridge_v1.gd")
const C = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_compiler_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_general_graph_v1.gd")
const Mechanics = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_general_mechanics_v1.gd")
const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const Bond = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const Composition = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const Batch = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")
const U = C.U
const E := {"material/rubber": 1.0e6, "material/steel": 2.0e11, "material/aluminum": 6.9e10, "material/copper": 1.1e11}
const RHO := {"material/rubber": 1.0e13, "material/steel": 1.43e-7, "material/aluminum": 2.82e-8, "material/copper": 1.68e-8}
const UNITS := {"m": 1.0, "cm": 0.01, "mm": 0.001}

var failures: Array[String] = []
var assertions := 0

func _initialize() -> void:
	_transport_stability()
	_general_graph()
	_general_mechanics()
	_revealed_g1_open_regression()
	print("G2_ASSERTIONS=", assertions, " FAILURES=", failures.size())
	if failures.is_empty():
		print("FABRIC-HOLDOUT-R4-G2: PASS")
		quit(0)
	else:
		print("G2_FAILURES=", JSON.stringify(failures))
		print("FABRIC-HOLDOUT-R4-G2: FAIL")
		quit(1)

func _check(ok: bool, label: String, detail = null) -> void:
	assertions += 1
	if not ok:
		failures.append(label)
		print("FAIL ", label, " ", detail)

func _transport_stability() -> void:
	var payload := {"matter": [0.1, 0.3333333333333333, 0.0000001, 1.2345678901234567, 17.000000000000004], "nested": {"temperature_k": 293.15, "mass_fraction": 0.37, "bulk_volume_m3": 0.000000000123456789}}
	var normalized_a := NetworkUtils.canonicalize(payload)
	var wire := NetworkUtils.canonical_json(payload)
	var decoded = JSON.parse_string(wire)
	var normalized_b := NetworkUtils.canonicalize(decoded)
	_check(normalized_a.success and normalized_b.success, "G2-C finite payload normalizes")
	_check(normalized_a.get("value") == normalized_b.get("value"), "G2-C normalize encode/decode idempotent", [normalized_a, normalized_b, wire])
	_check(NetworkUtils.payload_hash(payload) == NetworkUtils.payload_hash(decoded), "G2-C payload hash transport stable")
	var document := {"schema": "fabric.g2.transport.v1", "payload": payload, "checksum": ""}
	document.checksum = U.compute_checksum(document)
	var transported = JSON.parse_string(JSON.stringify(document, "", true, true))
	_check(transported is Dictionary and U.validate_checksum(transported).success, "G2-C checksum survives raw Godot JSON transport", transported)
	if transported is Dictionary:
		var tampered: Dictionary = transported.duplicate(true)
		tampered.payload.nested.mass_fraction = float(tampered.payload.nested.mass_fraction) + 0.01
		_check(not U.validate_checksum(tampered).success, "G2-C tamper remains rejected")
	_check(NetworkUtils.canonical_json(NAN).is_empty() and NetworkUtils.canonical_json(INF).is_empty(), "G2-C nonfinite remains forbidden")
	_check(NetworkUtils.canonical_json(Vector3.ONE).is_empty(), "G2-C Godot Variant remains forbidden")

func _general_graph() -> void:
	var model := {"nodes": [{"node_id": "n_a"}, {"node_id": "n_b"}, {"node_id": "n_c"}, {"node_id": "n_d"}, {"node_id": "n_e"}], "elements": [
		{"element_id": "e_ab", "node_a": "n_a", "node_b": "n_b", "resistance_ohm": 2.0, "active": true},
		{"element_id": "e_bc", "node_a": "n_b", "node_b": "n_c", "resistance_ohm": 5.0, "active": true},
		{"element_id": "e_cd", "node_a": "n_c", "node_b": "n_d", "resistance_ohm": 7.0, "active": true},
		{"element_id": "e_bd", "node_a": "n_b", "node_b": "n_d", "resistance_ohm": 11.0, "active": true},
		{"element_id": "e_be", "node_a": "n_b", "node_b": "n_e", "resistance_ohm": 13.0, "active": true},
		{"element_id": "e_ec", "node_a": "n_e", "node_b": "n_c", "resistance_ohm": 17.0, "active": true},
	]}
	var boundaries := {"n_a": 12.0, "n_c": 3.25, "n_d": -1.5}
	var solved := Graph.solve_resistive(model, boundaries)
	_check(solved.success, "G2-A branch loop three-port solves", solved)
	if solved.success:
		_check(solved.details.potentials_v.size() == 5 and solved.details.edge_currents_a.size() == 6 and solved.details.port_currents_a.size() == 3, "G2-A complete graph readback")
		_check(float(solved.details.kcl_residual_a) < 1.0e-10, "G2-A KCL residual", solved.details.kcl_residual_a)
		_check(float(solved.details.power_residual_w) < 1.0e-10, "G2-A power residual", solved.details.power_residual_w)
		for element in model.elements:
			var expected := (float(solved.details.potentials_v[element.node_a]) - float(solved.details.potentials_v[element.node_b])) / float(element.resistance_ohm)
			_check(absf(float(solved.details.edge_currents_a[element.element_id]) - expected) < 1.0e-12, "G2-A Ohm readback " + str(element.element_id))
		var permuted := model.duplicate(true)
		permuted.nodes.reverse()
		permuted.elements.reverse()
		var replay := Graph.solve_resistive(permuted, {"n_d": -1.5, "n_a": 12.0, "n_c": 3.25})
		_check(replay.success and U.canonical_hash(replay.details) == U.canonical_hash(solved.details), "G2-A insertion permutation deterministic", [solved, replay])
	var floating := model.duplicate(true)
	floating.nodes.append({"node_id": "n_f"})
	floating.nodes.append({"node_id": "n_g"})
	floating.elements.append({"element_id": "e_fg", "node_a": "n_f", "node_b": "n_g", "resistance_ohm": 4.0, "active": true})
	var rejected := Graph.solve_resistive(floating, boundaries)
	_check(not rejected.success and rejected.error_code == "R3_GENERAL_FLOATING_COMPONENT", "G2-A floating component fail-closed", rejected)

func _general_mechanics() -> void:
	var model := {"nodes": [
		{"node_id": "m_left", "local_position_m": [0.0, 0.0, 0.0], "mass_kg": 1.0, "anchored": true},
		{"node_id": "m_1", "local_position_m": [1.0, 0.0, 0.0], "mass_kg": 1.25, "anchored": false},
		{"node_id": "m_2", "local_position_m": [2.0, 0.0, 0.0], "mass_kg": 2.5, "anchored": false},
		{"node_id": "m_3", "local_position_m": [3.0, 0.0, 0.0], "mass_kg": 1.75, "anchored": false},
		{"node_id": "m_right", "local_position_m": [4.0, 0.0, 0.0], "mass_kg": 1.0, "anchored": true},
	], "elements": [
		{"element_id": "s_1", "node_a": "m_left", "node_b": "m_1", "stiffness_n_per_m": 70.0, "damping_ns_per_m": 0.4, "capacity_n": 200.0, "active": true},
		{"element_id": "s_2", "node_a": "m_1", "node_b": "m_2", "stiffness_n_per_m": 110.0, "damping_ns_per_m": 0.7, "capacity_n": 200.0, "active": true},
		{"element_id": "s_3", "node_a": "m_2", "node_b": "m_3", "stiffness_n_per_m": 90.0, "damping_ns_per_m": 0.5, "capacity_n": 200.0, "active": true},
		{"element_id": "s_4", "node_a": "m_3", "node_b": "m_right", "stiffness_n_per_m": 130.0, "damping_ns_per_m": 0.8, "capacity_n": 200.0, "active": true},
	]}
	var compiled := Mechanics.compile_mechanics(model, {"coupler_node_id": "m_2"})
	_check(compiled.success, "G2-B 3-mobile mechanics compiles", compiled)
	if compiled.success:
		_check(compiled.details.mobile_nodes == ["m_1", "m_2", "m_3"], "G2-B deterministic coordinate ordering", compiled.details.mobile_nodes)
		_check(is_finite(float(compiled.details.rate_bound)) and float(compiled.details.rate_bound) > 0.0, "G2-B finite rate bound")
	var static_response := Mechanics.solve_mechanical_static(model, "m_2")
	_check(static_response.success and absf(float(static_response.details.displacement_per_newton.m_2)) > 0.0, "G2-B static coupled response", static_response)
	var permuted := model.duplicate(true)
	permuted.nodes.reverse()
	permuted.elements.reverse()
	var permuted_static := Mechanics.solve_mechanical_static(permuted, "m_2")
	_check(permuted_static.success and U.canonical_hash(permuted_static.details.displacement_per_newton) == U.canonical_hash(static_response.details.displacement_per_newton), "G2-B insertion permutation invariant", permuted_static)
	var weak := model.duplicate(true)
	weak.elements[1].stiffness_n_per_m = 0.000001
	weak.elements[1].damping_ns_per_m = 0.0000001
	var weak_result := Mechanics.solve_mechanical_static(weak, "m_2")
	_check(weak_result.success and is_finite(float(weak_result.details.pivot_condition_estimate)), "G2-B weak but well-posed mode accepted", weak_result)
	var tiny_mass := model.duplicate(true)
	tiny_mass.nodes[2].mass_kg = 1.0e-15
	var tiny_result := Mechanics.compile_mechanics(tiny_mass, {"coupler_node_id": "m_2"})
	_check(not tiny_result.success and tiny_result.error_code == "R3_MASS_INVALID", "G2-B DAE divisor floor fails closed", tiny_result)
	var renamed_orientation := model.duplicate(true)
	for i in range(renamed_orientation.elements.size()):
		var edge: Dictionary = renamed_orientation.elements[i]
		edge.element_id = "renamed_%02d" % (renamed_orientation.elements.size() - i)
		if i % 2 == 0:
			var endpoint = edge.node_a
			edge.node_a = edge.node_b
			edge.node_b = endpoint
	var renamed_compiled := Mechanics.compile_mechanics(renamed_orientation, {"coupler_node_id": "m_2"})
	_check(renamed_compiled.success and U.canonical_hash(renamed_compiled.details.axis) == U.canonical_hash(compiled.details.axis), "G2-B axial basis independent of element IDs/orientation", renamed_compiled)

func _revealed_g1_open_regression() -> void:
	var corpus = JSON.parse_string(FileAccess.get_file_as_string("res://config/research/fabric-holdout-r4-cases.json"))
	_check(corpus is Dictionary and corpus.get("cases") is Array and corpus.cases.size() == 8, "G2 open regression frozen G1 corpus readable")
	if not corpus is Dictionary or not corpus.get("cases") is Array: return
	var replay_checked := false
	for raw_case in corpus.cases:
		var input: Dictionary = raw_case
		var sources := _sources_from_case(input)
		var authority := _authority(sources)
		var compiled := C.compile(sources, authority)
		if input.expectation == "REJECT_INVALID":
			_check(not compiled.success and compiled.error_code == "R3_GENERAL_FLOATING_COMPONENT", "G2 open regression invalid rejection " + str(input.id), compiled)
			continue
		_check(compiled.success, "G2 open regression capability " + str(input.id), compiled)
		if not compiled.success: continue
		var expected_ports := _ports(input)
		_check(U.canonical_hash(compiled.details.model.boundary_voltages_v) == U.canonical_hash(expected_ports), "G2 canonical ports preserved " + str(input.id), [compiled.details.model.boundary_voltages_v, expected_ports])
		var mobile_count := 0
		for node in input.mechanical_nodes:
			if not bool(node[3]): mobile_count += 1
		_check(compiled.details.model.mobile_nodes.size() == mobile_count, "G2 mobile coordinate count " + str(input.id), compiled.details.model.mobile_nodes)
		var bridge = B.new()
		var initialized: Dictionary = bridge.initialize(sources, authority)
		_check(initialized.success, "G2 runtime initialize " + str(input.id), initialized)
		if not initialized.success: continue
		var source_hash := U.canonical_hash(sources)
		for step_index in range(int(input.steps)):
			if not bridge.inspect().pending_proposal.is_empty(): break
			var result := bridge.execute(bridge.make_command("advance", {"dt_s": float(input.dt_s)}, authority), authority)
			if not result.success:
				_check(false, "G2 runtime advance %s/%d" % [str(input.id), step_index], result)
				break
		var observed: Dictionary = bridge.inspect()
		_check(not observed.is_empty() and U.canonical_hash(sources) == source_hash, "G2 source unchanged " + str(input.id))
		if not observed.is_empty():
			_check(absf(float(observed.electrical_observables.kcl_residual_a)) < 1.0e-8, "G2 runtime KCL " + str(input.id), observed.electrical_observables)
			_check(absf(float(observed.electrical_observables.power_residual_w)) < 1.0e-7, "G2 runtime power " + str(input.id), observed.electrical_observables)
			_check(is_finite(float(observed.energy_residual_j)), "G2 runtime finite energy residual " + str(input.id), observed.energy_residual_j)
		if not replay_checked:
			replay_checked = true
			var document: Dictionary = bridge.export_replay()
			var transported = JSON.parse_string(JSON.stringify(document, "", true, true))
			_check(transported is Dictionary and U.validate_checksum(transported).success, "G2 cold journal transport checksum", transported)
			if transported is Dictionary:
				var fresh = B.new()
				var matter := {"mechanical_matter": bridge.sources().mechanical_matter, "electrical_matter": bridge.sources().electrical_matter}
				var replay := fresh.replay(transported, bridge.canonical_state(), matter, authority, document.checksum)
				_check(replay.success, "G2 cold replay after raw JSON transport", replay)
				if replay.success: _check(U.canonical_hash(fresh.inspect()) == U.canonical_hash(bridge.inspect()), "G2 cold replay snapshot exact")

func _sources_from_case(input: Dictionary) -> Dictionary:
	var scale: float = float(UNITS[input.length_unit])
	var mechanical_parts: Array = []
	var mechanical_bonds: Array = []
	var mechanical_mass := 0.0
	var mechanical_positions := {}
	for row in input.mechanical_nodes:
		var position := float(row[1]) * scale
		var mass := float(row[2])
		mechanical_positions[str(row[0])] = position
		mechanical_parts.append(Part.create("part/" + str(row[0]), "item/" + str(row[0]), "BEAM", "mechanical", mass, [position, 0.0, 0.0], {"physics_r2_anchor": bool(row[3])}))
		mechanical_mass += mass
	for row in input.springs:
		var length := absf(float(mechanical_positions[str(row[1])]) - float(mechanical_positions[str(row[2])]))
		var area := float(row[3]) * length / float(E[input.material_mechanical])
		mechanical_bonds.append(Bond.create("bond/" + str(row[0]), "part/" + str(row[1]), "part/" + str(row[2]), "AXIAL_SPRING", float(row[5]), "INTACT", {"area_m2": area, "damping_ns_per_m": float(row[4])}))
	var port_values := _ports(input)
	var maximum_port := -INF
	var minimum_port := INF
	for voltage in port_values.values():
		maximum_port = maxf(maximum_port, float(voltage))
		minimum_port = minf(minimum_port, float(voltage))
	var controls := {"source_voltage_v": maximum_port - minimum_port, "external_force_n": float(input.external_force_n), "coupling_n_per_a": float(input.coupling), "guard_fraction": float(input.guard_fraction), "coupler_node_id": "part/" + str(input.coupler_node)}
	var mechanical := Snapshot.create("construct/g2-%s-mechanical" % str(input.id), "item/g2-%s-mechanical" % str(input.id), 1, "OPERATIONAL", mechanical_parts, mechanical_bonds, {"composition_r3": controls})
	var electrical_parts: Array = []
	var electrical_bonds: Array = []
	var electrical_positions := {}
	for row in input.electrical_nodes:
		var position := float(row[1]) * scale
		electrical_positions[str(row[0])] = position
		electrical_parts.append(Part.create("part/" + str(row[0]), "item/" + str(row[0]), "BEAM", "electrical", 1.0, [position, 0.0, 0.0], {}))
	for row in input.resistors:
		var length := absf(float(electrical_positions[str(row[1])]) - float(electrical_positions[str(row[2])]))
		var area := float(RHO[input.material_electrical]) * length / float(row[3])
		var role := "WIRE_RESISTANCE" if str(row[4]) == "WIRE" else str(row[4])
		electrical_bonds.append(Bond.create("bond/" + str(row[0]), "part/" + str(row[1]), "part/" + str(row[2]), "ELECTRICAL_RESISTOR", 100.0, "INTACT", {"area_m2": area, "composition_r3_role": role}))
	var electrical := Snapshot.create("construct/g2-%s-electrical" % str(input.id), "item/g2-%s-electrical" % str(input.id), 1, "OPERATIONAL", electrical_parts, electrical_bonds, {"composition_r3_boundary_voltages_v": port_values})
	return {"mechanical": mechanical, "electrical": electrical, "mechanical_matter": _matter("g2-%s-mechanical" % str(input.id), mechanical_mass, str(input.material_mechanical)), "electrical_matter": _matter("g2-%s-electrical" % str(input.id), float(electrical_parts.size()), str(input.material_electrical))}

func _ports(input: Dictionary) -> Dictionary:
	var result := {}
	for key in input.ports: result["part/" + str(key)] = float(input.ports[key])
	return result

func _matter(label: String, mass: float, material: String) -> Dictionary:
	return Batch.create({"batch_id": "batch/" + label, "container_id": "container/" + label, "source_body_id": "body/" + label, "source_operation_id": "operation/" + label, "total_mass_kg": mass, "bulk_volume_m3": mass * 0.001, "composition": Composition.create([{"material_id": material, "mass_fraction": 1.0}]), "temperature_k": 293.15})

func _authority(sources: Dictionary, owner: String = "server/g2") -> Dictionary:
	var records: Array = []
	var mutable: Array = []
	var readonly: Array = []
	for domain in ["mechanical", "electrical"]:
		var source_id: String = sources[domain].construct_id
		records.append({"source_domain": "CONSTRUCTION", "source_id": source_id, "authority_epoch": 19, "owner_id": owner})
		mutable.append(U.source_key("CONSTRUCTION", source_id))
		source_id = sources[domain + "_matter"].batch_id
		records.append({"source_domain": "MATTER", "source_id": source_id, "authority_epoch": 19, "owner_id": owner})
		readonly.append(U.source_key("MATTER", source_id))
	return C.A.create(owner, records, mutable, readonly)
