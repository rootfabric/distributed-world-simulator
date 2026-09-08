extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const R2 = preload("res://scripts/research/fabric_bake0/fabric_physics_r2_compiler_v1.gd")
const A = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const D = preload("res://scripts/research/fabric0/fabric0_coupled_hybrid_dae_v1.gd")
const G = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_general_linear_v1.gd")
const P = D.Physical
const SCHEMA := "planet_simulator.fabric_composition_r3.v1"
const SOURCE_FIELDS: Array[String] = ["mechanical", "electrical", "mechanical_matter", "electrical_matter"]
const CONTROL_FIELDS: Array[String] = ["source_voltage_v", "external_force_n", "coupling_n_per_a", "guard_fraction"]
const MAX_ELEMENTS := 32
const MIN_CAPACITY_N := 1.0e-6

# This is an input grammar/compiler, not a new numerical solver or canonical owner.
static func compile(sources: Dictionary, authority: Dictionary) -> Dictionary:
	if not U.validate_exact_fields(sources, SOURCE_FIELDS).success: return U.failure("R3_SOURCE_FIELDS")
	for key in SOURCE_FIELDS:
		if not sources[key] is Dictionary: return U.failure("R3_SOURCE_TYPE")
	for key in ["mechanical", "electrical"]:
		if sources[key].get("parts") is Array and sources[key].parts.size() > MAX_ELEMENTS + 1: return U.failure("R3_TOPOLOGY_BUDGET")
		if sources[key].get("bonds") is Array and sources[key].bonds.size() > MAX_ELEMENTS: return U.failure("R3_TOPOLOGY_BUDGET")
	var mech := R2.compile_mechanical(sources.mechanical, sources.mechanical_matter)
	if not mech.success: return mech
	var elec := R2.compile_electrical(sources.electrical, sources.electrical_matter)
	if not elec.success: return elec
	if not A.validate_b0_safety(authority).success: return U.failure("R3_AUTHORITY_INVALID")
	var mutable: Array = []
	var readonly: Array = []
	for key in ["mechanical", "electrical"]:
		if not sources[key].build_state in ["OPERATIONAL", "DAMAGED"]: return U.failure("R3_SOURCE_NOT_EXECUTABLE")
		mutable.append(U.source_key("CONSTRUCTION", sources[key].construct_id))
		readonly.append(U.source_key("MATTER", sources[key + "_matter"].batch_id))
	mutable.sort()
	readonly.sort()
	if mutable[0] == mutable[1] or readonly[0] == readonly[1] or authority.mutable_source_ids != mutable or authority.readonly_source_ids != readonly: return U.failure("R3_AUTHORITY_SOURCE_COVERAGE")
	var controls = sources.mechanical.compiled_facets.get("composition_r3")
	if not controls is Dictionary: return U.failure("R3_CONTROLS_REQUIRED")
	var general_control_fields: Array[String] = CONTROL_FIELDS.duplicate()
	general_control_fields.append(G.COUPLER_FIELD)
	var legacy_controls: bool = U.validate_exact_fields(controls, CONTROL_FIELDS).success
	var generalized_controls: bool = U.validate_exact_fields(controls, general_control_fields).success
	if not legacy_controls and not generalized_controls: return U.failure("R3_CONTROLS_REQUIRED")
	for key in CONTROL_FIELDS:
		if not U.is_finite_number(controls[key]) or absf(float(controls[key])) > 1.0e6: return U.failure("R3_CONTROL_ENVELOPE", {"field": key})
	if generalized_controls and (typeof(controls[G.COUPLER_FIELD]) != TYPE_STRING or str(controls[G.COUPLER_FIELD]).is_empty()): return U.failure("R3_GENERAL_COUPLER_NODE_REQUIRED")
	if controls.coupling_n_per_a <= 0.0 or controls.guard_fraction <= 0.0 or controls.guard_fraction >= 1.0: return U.failure("R3_COUPLER_OR_GUARD_INVALID")
	var m: Dictionary = mech.details.model
	var e: Dictionary = elec.details.model
	if m.elements.size() > MAX_ELEMENTS or e.elements.size() > MAX_ELEMENTS: return U.failure("R3_TOPOLOGY_BUDGET")
	var boundary_facet = sources.electrical.compiled_facets.get(G.BOUNDARY_FACET)
	if boundary_facet is Dictionary and not boundary_facet.is_empty(): return G.compile_model(sources, m, e, controls, U.canonical_hash(sources), authority.checksum)
	if generalized_controls: return U.failure("R3_GENERAL_BOUNDARY_VOLTAGES_REQUIRED")
	var slider := {}
	var nodes := {}
	for node in m.nodes:
		if not U.is_positive_number(node.mass_kg): return U.failure("R3_MASS_INVALID")
		nodes[node.node_id] = node
		if not node.anchored:
			if not slider.is_empty(): return U.failure("R3_ONE_SLIDER_REQUIRED")
			slider = node
	if slider.is_empty(): return U.failure("R3_ONE_SLIDER_REQUIRED")
	var axis := Vector3.ZERO
	var stiffness := 0.0
	var damping := 0.0
	var covered := {slider.node_id: true}
	for element in m.elements:
		if element.node_a != slider.node_id and element.node_b != slider.node_id: return U.failure("R3_PARALLEL_SUPPORTS_REQUIRED")
		var anchor_id: String = element.node_b if element.node_a == slider.node_id else element.node_a
		var offset := _vector(slider.local_position_m) - _vector(nodes[anchor_id].local_position_m)
		var direction := offset.normalized()
		if axis == Vector3.ZERO: axis = direction
		if not nodes[anchor_id].anchored or direction.dot(axis) < 1.0 - 1.0e-10: return U.failure("R3_COLLINEAR_SAME_SIDE_ANCHORS_REQUIRED")
		covered[anchor_id] = true
		if "|" in element.element_id: return U.failure("R3_ELEMENT_ID_DELIMITER")
		if not U.is_positive_number(element.capacity_n) or element.capacity_n < MIN_CAPACITY_N: return U.failure("R3_CAPACITY_BELOW_EVENT_RESOLUTION")
		if element.active:
			stiffness += element.stiffness_n_per_m
			damping += element.damping_ns_per_m
	if covered.size() != nodes.size(): return U.failure("R3_HIDDEN_NODE_FORBIDDEN")
	var series := _series(e, sources.electrical)
	if not series.success: return series
	var resistance: float = series.details.resistance_ohm
	var mass: float = slider.mass_kg
	var rate := sqrt(stiffness / mass) + (damping + pow(float(controls.coupling_n_per_a), 2) / resistance) / mass
	if not is_finite(rate) or mass < 1.0e-6 or resistance < 1.0e-9: return U.failure("R3_NUMERIC_ENVELOPE")
	var max_step := minf(0.02, 0.1 / maxf(rate, 1.0))
	if max_step < 1.0e-7: return U.failure("R3_TIMESCALE_OUT_OF_SCOPE")
	var model := {"schema": SCHEMA, "mechanical_model": m, "electrical_model": e, "source_hash": U.canonical_hash(sources), "authority_hash": authority.checksum, "controls": controls.duplicate(true), "slider_id": slider.node_id, "axis": [axis.x, axis.y, axis.z], "mass_kg": mass, "stiffness_n_per_m": stiffness, "damping_ns_per_m": damping, "resistance_ohm": resistance, "load_id": series.details.load_id, "max_step_s": max_step, "bake_kind": "EXACT_ALGEBRAIC_ELIMINATION", "dynamic_state_reduction": false, "checksum": ""}
	model.checksum = U.compute_checksum(model)
	return U.success({"model": model})

static func _series(model: Dictionary, snapshot: Dictionary) -> Dictionary:
	var adjacency := {}
	for node in model.nodes: adjacency[node.node_id] = []
	var total := 0.0
	var load_id := ""
	var source_count := 0
	for i in range(model.elements.size()):
		var element: Dictionary = model.elements[i]
		if not element.active: return U.failure("R3_OPEN_CIRCUIT_OUT_OF_SCOPE")
		adjacency[element.node_a].append(element.node_b)
		adjacency[element.node_b].append(element.node_a)
		total += element.resistance_ohm
		var role: String = str(snapshot.bonds[i].metadata.get("composition_r3_role", ""))
		match role:
			"SOURCE_RESISTANCE": source_count += 1
			"LOAD_RESISTANCE":
				if not load_id.is_empty(): return U.failure("R3_ONE_LOAD_REQUIRED")
				load_id = element.element_id
			"WIRE_RESISTANCE": pass
			_: return U.failure("R3_ELECTRICAL_ROLE_REQUIRED")
	if source_count != 1 or load_id.is_empty(): return U.failure("R3_SOURCE_AND_LOAD_REQUIRED")
	var ends := 0
	for neighbors in adjacency.values():
		if neighbors.size() == 1: ends += 1
		elif neighbors.size() != 2: return U.failure("R3_SERIES_PATH_REQUIRED")
	var seen := {}
	var queue: Array = [adjacency.keys()[0]]
	while not queue.is_empty():
		var node: String = queue.pop_back()
		if seen.has(node): continue
		seen[node] = true
		for neighbor in adjacency[node]:
			if not seen.has(neighbor): queue.append(neighbor)
	if ends != 2 or seen.size() != adjacency.size() or not U.is_positive_number(total): return U.failure("R3_CONNECTED_SERIES_PATH_REQUIRED")
	return U.success({"resistance_ohm": total, "load_id": load_id})

static func system(model: Dictionary, fidelity: String, values: Dictionary = {}, time_s: float = 0.0, mode: String = "LIVE") -> Dictionary:
	if not U.validate_checksum(model).success or model.get("schema") != SCHEMA: return U.failure("R3_MODEL_CHECKSUM")
	if model.get("solver_kind") == G.SOLVER_KIND: return G.system(model, fidelity, values, time_s, mode)
	if not fidelity in ["FULL", "BAKE"] or not mode in ["LIVE", "REFINED", "WAIT_CANONICAL"]: return U.failure("R3_MODE_INVALID")
	var s := D.new_system()
	var controls: Dictionary = model.controls
	var parameters := {"m": [model.mass_kg, D.dim_mass()], "k": [model.stiffness_n_per_m, D.dim_div(D.dim_force(), D.dim_length())], "c": [model.damping_ns_per_m, D.dim_div(D.dim_force(), D.dim_velocity())], "r": [model.resistance_ohm, P.dim_div(P.dim_voltage(), P.dim_current())], "g": [controls.coupling_n_per_a, P.dim_div(P.dim_force(), P.dim_current())], "u": [controls.source_voltage_v, P.dim_voltage()], "f": [controls.external_force_n, D.dim_force()]}
	for name in parameters:
		if not D.add_parameter(s, name, parameters[name][0], parameters[name][1]): return U.failure("R3_DSL_PARAMETER")
	var dims := {"x": D.dim_length(), "v": D.dim_velocity(), "source_work": D.dim_energy(), "external_work": D.dim_energy(), "joule_heat": D.dim_energy(), "damper_heat": D.dim_energy()}
	for name in dims:
		var value = values.get(name, 0.0)
		if not U.is_finite_number(value): return U.failure("R3_STATE_INVALID")
		if not D.add_state(s, name, value, dims[name]): return U.failure("R3_DSL_STATE")
	var x := D.expr_state("x")
	var v := D.expr_state("v")
	var emf := D.expr_mul(D.expr_parameter("g"), v)
	var current := D.expr_div(D.expr_sub(D.expr_parameter("u"), emf), D.expr_parameter("r"))
	var rows: Array = []
	if fidelity == "FULL":
		D.add_algebraic(s, "i", 0.0, P.dim_current())
		current = D.expr_algebraic("i")
		rows.append(D.residual(D.expr_sub(D.expr_add(D.expr_mul(D.expr_parameter("r"), current), emf), D.expr_parameter("u")), 1.0))
	var spring := D.expr_mul(D.expr_parameter("k"), x)
	var damper := D.expr_mul(D.expr_parameter("c"), v)
	var motor := D.expr_mul(D.expr_parameter("g"), current)
	var force := D.expr_sub(D.expr_add(motor, D.expr_parameter("f")), D.expr_add(spring, damper))
	var flows := {"x": v, "v": D.expr_div(force, D.expr_parameter("m")), "source_work": D.expr_mul(D.expr_parameter("u"), current), "external_work": D.expr_mul(D.expr_parameter("f"), v), "joule_heat": D.expr_mul(D.expr_parameter("r"), D.expr_pow_int(current, 2)), "damper_heat": D.expr_mul(D.expr_parameter("c"), D.expr_pow_int(v, 2))}
	for live in ["LIVE", "REFINED"]:
		if not D.add_mode(s, live, flows, rows): return U.failure("R3_DSL_DIMENSIONS", {"diagnostics": s.diagnostics})
	if not D.add_mode(s, "WAIT_CANONICAL", {}, rows): return U.failure("R3_DSL_WAIT_MODE")
	for element in model.mechanical_model.elements:
		if not element.active: continue
		var effort := D.expr_add(D.expr_mul(D.expr_constant(element.stiffness_n_per_m, parameters.k[1]), x), D.expr_mul(D.expr_constant(element.damping_ns_per_m, parameters.c[1]), v))
		for sign_value in [-1.0, 1.0]:
			for kind in ["guard", "failure"]:
				var limit: float = element.capacity_n * (controls.guard_fraction if kind == "guard" else 1.0)
				var transition := {"id": "%s|%s|%s" % [kind, element.element_id, str(sign_value)], "from_modes": ["LIVE"] if kind == "guard" else ["LIVE", "REFINED"], "to_mode": "REFINED" if kind == "guard" else "WAIT_CANONICAL", "priority": 0, "guard": {"expr": D.expr_sub(D.expr_mul(D.expr_constant(sign_value), effort), D.expr_constant(limit, D.dim_force())), "nominal": limit, "direction": 1, "kind": "crossing"}}
				if not D.add_transition(s, transition): return U.failure("R3_DSL_GUARD")
				var condition: Dictionary = transition.duplicate(true)
				condition.id += "|initial"
				condition.guard.kind = "condition"
				if not D.add_transition(s, condition): return U.failure("R3_DSL_CONDITION")
	s.time = time_s
	if not D.set_initial_mode(s, mode) or not D.solve_algebraic(s).get("ok", false): return U.failure("R3_DAE_INITIAL_SOLVE")
	return U.success({"system": s})

static func _vector(position: Array) -> Vector3:
	return Vector3(float(position[0]), float(position[1]), float(position[2]))
