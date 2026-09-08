extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_general_graph_v1.gd")
const Mechanics = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_general_mechanics_v1.gd")
const System = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_general_system_v1.gd")
const SOLVER_KIND := "GENERAL_LINEAR_GRAPH_V1"
const BOUNDARY_FACET := "composition_r3_boundary_voltages_v"
const COUPLER_FIELD := "coupler_node_id"
const RESIDUAL_REL_TOL := 2.0e-10
const MAX_NODES := Graph.MAX_NODES

static func compile_model(
		sources: Dictionary,
		mechanical_model: Dictionary,
		electrical_model: Dictionary,
		controls: Dictionary,
		source_hash: String,
		authority_hash: String
) -> Dictionary:
	var facets = sources.electrical.compiled_facets.get(BOUNDARY_FACET)
	if not facets is Dictionary or facets.is_empty():
		return U.failure("R3_GENERAL_BOUNDARY_VOLTAGES_REQUIRED")
	var boundaries: Dictionary = facets.duplicate(true)
	if boundaries.size() < 2 or boundaries.size() > MAX_NODES:
		return U.failure("R3_GENERAL_BOUNDARY_COUNT")
	var electrical_ids := {}
	for node in electrical_model.nodes:
		electrical_ids[str(node.node_id)] = true
	for raw_id in boundaries:
		if typeof(raw_id) != TYPE_STRING or not electrical_ids.has(str(raw_id)) or not U.is_finite_number(boundaries[raw_id]):
			return U.failure("R3_GENERAL_BOUNDARY_INVALID")
		boundaries[raw_id] = float(boundaries[raw_id])

	var mechanical := Mechanics.compile_mechanics(mechanical_model, controls)
	if not mechanical.success:
		return mechanical
	var roles := _electrical_roles(sources.electrical)
	if not roles.success:
		return roles
	var source_edge_id: String = roles.details.source_edge_id
	var source_edge := _element_by_id(electrical_model.elements, source_edge_id)
	if source_edge.is_empty():
		return U.failure("R3_GENERAL_SOURCE_EDGE_MISSING")
	var source_candidates: Array[String] = []
	for endpoint in [str(source_edge.node_a), str(source_edge.node_b)]:
		if boundaries.has(endpoint):
			source_candidates.append(endpoint)
	if source_candidates.size() != 1:
		return U.failure("R3_GENERAL_SOURCE_BOUNDARY_REQUIRED")
	var source_port_id: String = source_candidates[0]
	var source_voltage: float = float(controls.source_voltage_v)
	var minimum_boundary := INF
	for raw_value in boundaries.values():
		minimum_boundary = minf(minimum_boundary, float(raw_value))
	if not is_finite(minimum_boundary):
		return U.failure("R3_GENERAL_BOUNDARY_INVALID")
	# R3 source_voltage_v remains the mutable source amplitude. The boundary facet
	# supplies all other independent Dirichlet potentials and the source terminal ID.
	boundaries[source_port_id] = minimum_boundary + source_voltage

	var nominal := Graph.solve_resistive(electrical_model, boundaries)
	if not nominal.success:
		return nominal
	var coupling: float = float(controls.coupling_n_per_a)
	var plus_boundaries := Graph.boundary_for_velocity(boundaries, source_port_id, coupling, 1.0)
	var minus_boundaries := Graph.boundary_for_velocity(boundaries, source_port_id, coupling, -1.0)
	var plus := Graph.solve_resistive(electrical_model, plus_boundaries)
	var minus := Graph.solve_resistive(electrical_model, minus_boundaries)
	if not plus.success: return plus
	if not minus.success: return minus
	var i0: float = float(nominal.details.port_currents_a[source_port_id])
	var i_plus: float = float(plus.details.port_currents_a[source_port_id])
	var i_minus: float = float(minus.details.port_currents_a[source_port_id])
	var di_dv := 0.5 * (i_plus - i_minus)
	if not is_finite(di_dv) or di_dv > RESIDUAL_REL_TOL * (1.0 + absf(i0)):
		return U.failure("R3_GENERAL_NONPASSIVE_SOURCE_RESPONSE")

	var p0 := Graph.external_power(boundaries, nominal.details.port_currents_a)
	var p_plus := Graph.external_power(boundaries, plus.details.port_currents_a)
	var p_minus := Graph.external_power(boundaries, minus.details.port_currents_a)
	var power_linear := 0.5 * (p_plus - p_minus)
	var power_curvature := 0.5 * (p_plus + p_minus) - p0
	if absf(power_curvature) > RESIDUAL_REL_TOL * (1.0 + absf(p0) + absf(p_plus) + absf(p_minus)):
		return U.failure("R3_GENERAL_EXTERNAL_POWER_NONLINEAR")

	var h0: float = float(nominal.details.joule_power_w)
	var h_plus: float = float(plus.details.joule_power_w)
	var h_minus: float = float(minus.details.joule_power_w)
	var heat_linear := 0.5 * (h_plus - h_minus)
	var heat_quadratic := 0.5 * (h_plus + h_minus) - h0
	for velocity in [-1.0, 0.0, 1.0]:
		var graph: Dictionary = minus if velocity < 0.0 else (plus if velocity > 0.0 else nominal)
		var external: float = p0 + power_linear * velocity
		var heat: float = h0 + heat_linear * velocity + heat_quadratic * velocity * velocity
		var current: float = i0 + di_dv * velocity
		var residual: float = external - heat - coupling * current * velocity
		var scale := 1.0 + absf(external) + absf(heat) + absf(coupling * current * velocity)
		if absf(residual) > 2.0e-9 * scale:
			return U.failure("R3_GENERAL_COUPLER_POWER_IDENTITY")
		if float(graph.details.power_residual_w) > 2.0e-9 * (1.0 + absf(heat)):
			return U.failure("R3_GENERAL_GRAPH_POWER_RESIDUAL")

	var mechanics: Dictionary = mechanical.details
	var rate: float = float(mechanics.rate_bound)
	var coupler_index: int = int(mechanics.mobile_index[mechanics.coupler_node_id])
	var coupler_mass: float = float(mechanics.mobile_masses_kg[coupler_index])
	rate += maxf(0.0, -coupling * di_dv / coupler_mass)
	var max_step := minf(0.02, 0.08 / maxf(rate, 1.0))
	if max_step < 1.0e-7:
		return U.failure("R3_TIMESCALE_OUT_OF_SCOPE")

	var model := {
		"schema": "planet_simulator.fabric_composition_r3.v1",
		"solver_kind": SOLVER_KIND,
		"mechanical_model": mechanical_model.duplicate(true),
		"electrical_model": electrical_model.duplicate(true),
		"source_hash": source_hash,
		"authority_hash": authority_hash,
		"controls": controls.duplicate(true),
		"axis": mechanics.axis.duplicate(),
		"mobile_nodes": mechanics.mobile_nodes.duplicate(),
		"mobile_masses_kg": mechanics.mobile_masses_kg.duplicate(),
		"mobile_index": mechanics.mobile_index.duplicate(true),
		"coupler_node_id": mechanics.coupler_node_id,
		"boundary_voltages_v": boundaries.duplicate(true),
		"source_port_id": source_port_id,
		"source_edge_id": source_edge_id,
		"load_id": roles.details.load_id,
		"source_current_offset_a": i0,
		"source_current_velocity_gain": di_dv,
		"external_power_offset_w": p0,
		"external_power_velocity_gain": power_linear,
		"joule_power_offset_w": h0,
		"joule_power_velocity_gain": heat_linear,
		"joule_power_velocity2_gain": heat_quadratic,
		"max_step_s": max_step,
		"bake_kind": "EXACT_ALGEBRAIC_ELIMINATION",
		"dynamic_state_reduction": false,
		"checksum": "",
	}
	model.checksum = U.compute_checksum(model)
	return U.success({"model": model})

static func _electrical_roles(snapshot: Dictionary) -> Dictionary:
	var source := ""
	var load_ids: Array[String] = []
	for bond in snapshot.bonds:
		var role := str(bond.metadata.get("composition_r3_role", ""))
		match role:
			"SOURCE_RESISTANCE":
				if not source.is_empty(): return U.failure("R3_SOURCE_AND_LOAD_REQUIRED")
				source = str(bond.bond_id)
			"LOAD_RESISTANCE": load_ids.append(str(bond.bond_id))
			"WIRE_RESISTANCE": pass
			_: return U.failure("R3_ELECTRICAL_ROLE_REQUIRED")
	if source.is_empty() or load_ids.is_empty(): return U.failure("R3_SOURCE_AND_LOAD_REQUIRED")
	load_ids.sort()
	return U.success({"source_edge_id": source, "load_id": load_ids[0] if load_ids.size() == 1 else ""})

static func _element_by_id(elements: Array, element_id: String) -> Dictionary:
	for element in elements:
		if str(element.element_id) == element_id: return element
	return {}

static func _compile_mechanics(model: Dictionary, controls: Dictionary) -> Dictionary:
	return Mechanics.compile_mechanics(model, controls)

static func solve_resistive(model: Dictionary, boundary_voltages_v: Dictionary) -> Dictionary:
	return Graph.solve_resistive(model, boundary_voltages_v)

static func solve_mechanical_static(model: Dictionary, coupler_node_id: String) -> Dictionary:
	return Mechanics.solve_mechanical_static(model, coupler_node_id)

static func system(model: Dictionary, fidelity: String, values: Dictionary = {}, time_s: float = 0.0, mode: String = "LIVE") -> Dictionary:
	return System.system(model, fidelity, values, time_s, mode)

static func observe(model: Dictionary, system_value: Dictionary, fidelity: String, fracture_j: float = 0.0) -> Dictionary:
	return System.observe(model, system_value, fidelity, fracture_j)

static func element_elastic_energy(model: Dictionary, system_value: Dictionary, element_id: String) -> float:
	return System.element_elastic_energy(model, system_value, element_id)
