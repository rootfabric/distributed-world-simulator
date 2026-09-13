extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const D = preload("res://scripts/research/fabric0/fabric0_coupled_hybrid_dae_v1.gd")
const P = D.Physical
const Graph = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_general_graph_v1.gd")
const SOLVER_KIND := "GENERAL_LINEAR_GRAPH_V1"

static func system(model: Dictionary, fidelity: String, values: Dictionary = {}, time_s: float = 0.0, mode: String = "LIVE") -> Dictionary:
	if not U.validate_checksum(model).success or model.get("solver_kind") != SOLVER_KIND: return U.failure("R3_GENERAL_MODEL_CHECKSUM")
	if not fidelity in ["FULL", "BAKE"] or not mode in ["LIVE", "REFINED", "WAIT_CANONICAL"]: return U.failure("R3_MODE_INVALID")
	var s := D.new_system()
	var g: float = float(model.controls.coupling_n_per_a)
	var f_external: float = float(model.controls.external_force_n)
	var current_dim := P.dim_current()
	var current_per_velocity := D.dim_div(current_dim, D.dim_velocity())
	var power_dim := D.dim_div(D.dim_energy(), D.dim_time())
	var power_per_velocity := D.dim_div(power_dim, D.dim_velocity())
	var power_per_velocity2 := D.dim_div(power_per_velocity, D.dim_velocity())
	var parameters := {
		"g": [g, P.dim_div(P.dim_force(), P.dim_current())], "f": [f_external, D.dim_force()],
		"i0": [model.source_current_offset_a, current_dim], "iv": [model.source_current_velocity_gain, current_per_velocity],
		"p0": [model.external_power_offset_w, power_dim], "pv": [model.external_power_velocity_gain, power_per_velocity],
		"h0": [model.joule_power_offset_w, power_dim], "hv": [model.joule_power_velocity_gain, power_per_velocity],
		"hvv": [model.joule_power_velocity2_gain, power_per_velocity2],
	}
	for i in range(model.mobile_nodes.size()): parameters["m_%d" % i] = [model.mobile_masses_kg[i], D.dim_mass()]
	for i in range(model.mechanical_model.elements.size()):
		var element: Dictionary = model.mechanical_model.elements[i]
		parameters["k_%d" % i] = [element.stiffness_n_per_m, D.dim_div(D.dim_force(), D.dim_length())]
		parameters["c_%d" % i] = [element.damping_ns_per_m, D.dim_div(D.dim_force(), D.dim_velocity())]
	for name in parameters:
		if not D.add_parameter(s, name, parameters[name][0], parameters[name][1]): return U.failure("R3_DSL_PARAMETER")
	for i in range(model.mobile_nodes.size()):
		for prefix in ["x", "v"]:
			var state_name := "%s_%d" % [prefix, i]
			var dimension := D.dim_length() if prefix == "x" else D.dim_velocity()
			var value = values.get(state_name, 0.0)
			if not U.is_finite_number(value) or not D.add_state(s, state_name, float(value), dimension): return U.failure("R3_STATE_INVALID")
	for name in ["source_work", "external_work", "joule_heat", "damper_heat"]:
		var value = values.get(name, 0.0)
		if not U.is_finite_number(value) or not D.add_state(s, name, float(value), D.dim_energy()): return U.failure("R3_STATE_INVALID")
	var coupler_index: int = int(model.mobile_index[model.coupler_node_id])
	var coupler_v := D.expr_state("v_%d" % coupler_index)
	var current := D.expr_add(D.expr_parameter("i0"), D.expr_mul(D.expr_parameter("iv"), coupler_v))
	var rows: Array = []
	if fidelity == "FULL":
		if not D.add_algebraic(s, "i", float(model.source_current_offset_a), current_dim): return U.failure("R3_DSL_ALGEBRAIC")
		var algebraic := D.expr_algebraic("i")
		rows.append(D.residual(D.expr_sub(algebraic, current), maxf(1.0e-9, absf(float(model.source_current_offset_a)))))
		current = algebraic
	var forces: Array = []
	for _i in range(model.mobile_nodes.size()): forces.append(D.expr_constant(0.0, D.dim_force()))
	var damper_power := D.expr_constant(0.0, power_dim)
	var effort_expressions := {}
	for edge_index in range(model.mechanical_model.elements.size()):
		var element: Dictionary = model.mechanical_model.elements[edge_index]
		if not element.active: continue
		var a_index := int(model.mobile_index.get(str(element.node_a), -1))
		var b_index := int(model.mobile_index.get(str(element.node_b), -1))
		var xa := D.expr_state("x_%d" % a_index) if a_index >= 0 else D.expr_constant(0.0, D.dim_length())
		var xb := D.expr_state("x_%d" % b_index) if b_index >= 0 else D.expr_constant(0.0, D.dim_length())
		var va := D.expr_state("v_%d" % a_index) if a_index >= 0 else D.expr_constant(0.0, D.dim_velocity())
		var vb := D.expr_state("v_%d" % b_index) if b_index >= 0 else D.expr_constant(0.0, D.dim_velocity())
		# G2-B signed effort convention is node_a -> node_b:
		# effort = k*(q_a-q_b) + c*(v_a-v_b). Keep the physical internal
		# force identical by applying -effort to a and +effort to b.
		var dq := D.expr_sub(xa, xb)
		var dv := D.expr_sub(va, vb)
		var effort := D.expr_add(D.expr_mul(D.expr_parameter("k_%d" % edge_index), dq), D.expr_mul(D.expr_parameter("c_%d" % edge_index), dv))
		effort_expressions[str(element.element_id)] = effort
		if a_index >= 0: forces[a_index] = D.expr_sub(forces[a_index], effort)
		if b_index >= 0: forces[b_index] = D.expr_add(forces[b_index], effort)
		damper_power = D.expr_add(damper_power, D.expr_mul(D.expr_parameter("c_%d" % edge_index), D.expr_pow_int(dv, 2)))
	forces[coupler_index] = D.expr_add(forces[coupler_index], D.expr_add(D.expr_mul(D.expr_parameter("g"), current), D.expr_parameter("f")))
	var flows := {}
	for i in range(model.mobile_nodes.size()):
		flows["x_%d" % i] = D.expr_state("v_%d" % i)
		flows["v_%d" % i] = D.expr_div(forces[i], D.expr_parameter("m_%d" % i))
	flows.source_work = D.expr_add(D.expr_parameter("p0"), D.expr_mul(D.expr_parameter("pv"), coupler_v))
	flows.external_work = D.expr_mul(D.expr_parameter("f"), coupler_v)
	flows.joule_heat = D.expr_add(D.expr_add(D.expr_parameter("h0"), D.expr_mul(D.expr_parameter("hv"), coupler_v)), D.expr_mul(D.expr_parameter("hvv"), D.expr_pow_int(coupler_v, 2)))
	flows.damper_heat = damper_power
	for live in ["LIVE", "REFINED"]:
		if not D.add_mode(s, live, flows, rows): return U.failure("R3_DSL_DIMENSIONS", {"diagnostics": s.diagnostics})
	if not D.add_mode(s, "WAIT_CANONICAL", {}, rows): return U.failure("R3_DSL_WAIT_MODE")
	for element in model.mechanical_model.elements:
		if not element.active: continue
		var effort: Dictionary = effort_expressions[str(element.element_id)]
		for sign_value in [-1.0, 1.0]:
			for kind in ["guard", "failure"]:
				var limit: float = float(element.capacity_n) * (float(model.controls.guard_fraction) if kind == "guard" else 1.0)
				var transition := {"id": "%s|%s|%s" % [kind, element.element_id, str(sign_value)], "from_modes": ["LIVE"] if kind == "guard" else ["LIVE", "REFINED"], "to_mode": "REFINED" if kind == "guard" else "WAIT_CANONICAL", "priority": 0, "guard": {"expr": D.expr_sub(D.expr_mul(D.expr_constant(sign_value), effort), D.expr_constant(limit, D.dim_force())), "nominal": limit, "direction": 1, "kind": "crossing"}}
				if not D.add_transition(s, transition): return U.failure("R3_DSL_GUARD")
				var condition: Dictionary = transition.duplicate(true)
				condition.id += "|initial"
				condition.guard.kind = "condition"
				if not D.add_transition(s, condition): return U.failure("R3_DSL_CONDITION")
	s.time = time_s
	if not D.set_initial_mode(s, mode) or not D.solve_algebraic(s).get("ok", false): return U.failure("R3_DAE_INITIAL_SOLVE")
	return U.success({"system": s})

static func observe(model: Dictionary, system_value: Dictionary, fidelity: String, fracture_j: float = 0.0) -> Dictionary:
	var coupler_index: int = int(model.mobile_index[model.coupler_node_id])
	var x := float(system_value.states["x_%d" % coupler_index].value)
	var v := float(system_value.states["v_%d" % coupler_index].value)
	var boundaries := Graph.boundary_for_velocity(model.boundary_voltages_v, model.source_port_id, float(model.controls.coupling_n_per_a), v)
	var graph := Graph.solve_resistive(model.electrical_model, boundaries)
	if not graph.success: return {"error_code": graph.error_code}
	var current := float(graph.details.port_currents_a[model.source_port_id])
	var kinetic := 0.0
	var displacements := {}
	var velocities := {}
	for i in range(model.mobile_nodes.size()):
		var node_id: String = str(model.mobile_nodes[i])
		var xi := float(system_value.states["x_%d" % i].value)
		var vi := float(system_value.states["v_%d" % i].value)
		displacements[node_id] = xi
		velocities[node_id] = vi
		kinetic += 0.5 * float(model.mobile_masses_kg[i]) * vi * vi
	var elastic := 0.0
	var supports: Array = []
	var efforts := {}
	var utilization := 0.0
	for element in model.mechanical_model.elements:
		var a_index := int(model.mobile_index.get(str(element.node_a), -1))
		var b_index := int(model.mobile_index.get(str(element.node_b), -1))
		var xa := float(system_value.states["x_%d" % a_index].value) if a_index >= 0 else 0.0
		var xb := float(system_value.states["x_%d" % b_index].value) if b_index >= 0 else 0.0
		var va := float(system_value.states["v_%d" % a_index].value) if a_index >= 0 else 0.0
		var vb := float(system_value.states["v_%d" % b_index].value) if b_index >= 0 else 0.0
		var dq := xa - xb
		var dv := va - vb
		var effort := (float(element.stiffness_n_per_m) * dq + float(element.damping_ns_per_m) * dv) if element.active else 0.0
		var bond_id := str(element.element_id)
		efforts[bond_id] = effort
		if element.active:
			elastic += 0.5 * float(element.stiffness_n_per_m) * dq * dq
			utilization = maxf(utilization, absf(effort) / float(element.capacity_n))
		supports.append({"bond_id": bond_id, "active": element.active, "effort_n": effort, "capacity_n": element.capacity_n})
	var source_work := float(system_value.states.source_work.value)
	var external_work := float(system_value.states.external_work.value)
	var joule_heat := float(system_value.states.joule_heat.value)
	var damper_heat := float(system_value.states.damper_heat.value)
	var source_power := Graph.external_power(model.boundary_voltages_v, graph.details.port_currents_a)
	var g: float = float(model.controls.coupling_n_per_a)
	var energy_residual := kinetic + elastic + fracture_j + joule_heat + damper_heat - source_work - external_work
	return {"time_s": system_value.time, "displacement_m": x, "velocity_m_per_s": v, "current_a": current, "back_emf_v": g * v, "actuator_force_n": g * current, "constraint_residual_v": 0.0, "source_power_w": source_power, "coupler_electrical_power_w": g * v * current, "coupler_mechanical_power_w": g * current * v, "kinetic_j": kinetic, "elastic_j": elastic, "fracture_heat_j": fracture_j, "source_work_j": source_work, "external_work_j": external_work, "joule_heat_j": joule_heat, "damper_heat_j": damper_heat, "energy_residual_j": energy_residual, "coupler_power_residual_w": 0.0, "supports": supports, "fidelity": fidelity, "mode": system_value.mode, "max_step_s": model.max_step_s, "guard_fraction": model.controls.guard_fraction, "utilization": utilization, "axis": model.axis.duplicate(), "electrical_observables": {"potentials_v": graph.details.potentials_v, "edge_currents_a": graph.details.edge_currents_a, "port_currents_a": graph.details.port_currents_a, "kcl_residual_a": graph.details.kcl_residual_a, "power_residual_w": graph.details.power_residual_w, "condition_estimate": graph.details.pivot_condition_estimate}, "mechanical_observables": {"displacements_m": displacements, "velocities_m_per_s": velocities, "efforts_n": efforts}}

static func element_elastic_energy(model: Dictionary, system_value: Dictionary, element_id: String) -> float:
	for element in model.mechanical_model.elements:
		if str(element.element_id) != element_id: continue
		var a_index := int(model.mobile_index.get(str(element.node_a), -1))
		var b_index := int(model.mobile_index.get(str(element.node_b), -1))
		var xa := float(system_value.states["x_%d" % a_index].value) if a_index >= 0 else 0.0
		var xb := float(system_value.states["x_%d" % b_index].value) if b_index >= 0 else 0.0
		var dx := xb - xa
		return 0.5 * float(element.stiffness_n_per_m) * dx * dx
	return 0.0
