extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Model = preload("res://scripts/research/fabric_bake0/dynamic_full_model_descriptor_v1.gd")
const FullState = preload("res://scripts/research/fabric_bake0/dynamic_full_state_v1.gd")

const SOLVER_VERSION := "FABRIC-BAKE/B0.4-A/FULL-REFERENCE-R1"
const PIVOT_EPS := 1.0e-15

static func initial_state(model: Dictionary) -> Dictionary:
	var checked := Model.validate(model)
	if not bool(checked.get("success", false)):
		return _failure(String(checked.get("error_code", "B0_4_A_INVALID_MODEL")))
	var values: Array = []
	for node in model["storage_nodes"]:
		values.append(float(node["initial_value"]))
	var state := FullState.create(
		String(model["model_hash"]),
		String(model["full_state_schema"]["schema_hash"]),
		0.0,
		0,
		values
	)
	if state.is_empty():
		return _failure("B0_4_A_INITIAL_STATE_CREATE_FAILED")
	return {
		"success": true,
		"state": state,
		"stored_energy": _stored_energy(model, values),
	}

static func step(
	model: Dictionary,
	state: Dictionary,
	port_flows: Dictionary,
	delta_s: float
) -> Dictionary:
	var checked := Model.validate(model)
	if not bool(checked.get("success", false)):
		return _failure(String(checked.get("error_code", "B0_4_A_INVALID_MODEL")))
	checked = _validate_state(model, state)
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_port_flows(model, port_flows)
	if not bool(checked.get("success", false)):
		return checked
	if not Utils.is_positive_number(delta_s):
		return _failure("B0_4_A_INVALID_REFERENCE_STEP")
	if delta_s > float(model["reference_solver"]["max_step_s"]) + 1.0e-15:
		return _failure("B0_4_A_REFERENCE_STEP_EXCEEDS_CERTIFIED_MAX", {
			"delta_s": delta_s,
			"max_step_s": float(model["reference_solver"]["max_step_s"]),
		})
	return _step_validated(model, state, port_flows, delta_s)

static func advance_constant(
	model: Dictionary,
	state: Dictionary,
	port_flows: Dictionary,
	delta_s: float,
	steps: int
) -> Dictionary:
	var checked := Model.validate(model)
	if not bool(checked.get("success", false)):
		return _failure(String(checked.get("error_code", "B0_4_A_INVALID_MODEL")))
	checked = _validate_state(model, state)
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_port_flows(model, port_flows)
	if not bool(checked.get("success", false)):
		return checked
	if not Utils.is_positive_number(delta_s):
		return _failure("B0_4_A_INVALID_REFERENCE_STEP")
	if delta_s > float(model["reference_solver"]["max_step_s"]) + 1.0e-15:
		return _failure("B0_4_A_REFERENCE_STEP_EXCEEDS_CERTIFIED_MAX")
	if not Utils.is_json_integer(steps) or steps < 1:
		return _failure("B0_4_A_INVALID_REFERENCE_STEP_COUNT")

	var current: Dictionary = state.duplicate(true)
	var max_balance_residual := 0.0
	var max_unaccounted_creation := 0.0
	var boundary_energy_in := 0.0
	var dissipated_energy := 0.0
	var numerical_dissipation_energy := 0.0
	var last_boundary: Array = []
	for _index in range(steps):
		var advanced := _step_validated(model, current, port_flows, delta_s)
		if not bool(advanced.get("success", false)):
			return advanced
		current = advanced["state"]
		max_balance_residual = maxf(max_balance_residual, absf(float(advanced["energy"]["balance_residual"])))
		max_unaccounted_creation = maxf(max_unaccounted_creation, float(advanced["energy"]["unaccounted_energy_creation"]))
		boundary_energy_in += float(advanced["energy"]["boundary_energy_in"])
		dissipated_energy += float(advanced["energy"]["dissipated_energy"])
		numerical_dissipation_energy += float(advanced["energy"]["numerical_dissipation_energy"])
		last_boundary = advanced["boundary"]
	return {
		"success": true,
		"state": current,
		"boundary": last_boundary,
		"summary": {
			"steps": steps,
			"delta_s": delta_s,
			"max_balance_residual": max_balance_residual,
			"max_unaccounted_energy_creation": max_unaccounted_creation,
			"boundary_energy_in": boundary_energy_in,
			"dissipated_energy": dissipated_energy,
			"numerical_dissipation_energy": numerical_dissipation_energy,
			"final_stored_energy": _stored_energy(model, current["values"]),
		},
	}

static func _step_validated(
	model: Dictionary,
	state: Dictionary,
	port_flows: Dictionary,
	delta_s: float
) -> Dictionary:
	var count := int(model["full_state_schema"]["state_count"])
	var old_values: Array = state["values"]
	var state_index: Dictionary = Model.state_index(model)
	var injections: Array = []
	injections.resize(count)
	injections.fill(0.0)

	var boundary_port_by_id := {}
	for port in model["boundary_contract"]["ports"]:
		boundary_port_by_id[String(port["port_id"])] = port
	for binding in model["port_bindings"]:
		var port_id := String(binding["port_id"])
		var state_id := String(binding["state_id"])
		var index := int(state_index[state_id])
		var port: Dictionary = boundary_port_by_id[port_id]
		var orientation_sign := _orientation_sign(String(port["orientation"]))
		injections[index] = float(injections[index]) + orientation_sign * float(port_flows[port_id])

	var lower: Array = []
	var diag: Array = []
	var upper: Array = []
	var rhs: Array = []
	lower.resize(count)
	diag.resize(count)
	upper.resize(count)
	rhs.resize(count)
	lower.fill(0.0)
	diag.fill(0.0)
	upper.fill(0.0)
	rhs.fill(0.0)

	var edge_g: Array = []
	edge_g.resize(maxi(0, count - 1))
	for index in range(model["edges"].size()):
		edge_g[index] = float(model["edges"][index]["conductance"])
	var shunt_by_state := {}
	for shunt in model["shunts"]:
		shunt_by_state[String(shunt["state_id"])] = float(shunt["conductance"])

	for index in range(count):
		var state_id := String(model["full_state_schema"]["states"][index]["state_id"])
		var storage := float(model["storage_nodes"][index]["storage_coefficient"])
		var left_g := float(edge_g[index - 1]) if index > 0 else 0.0
		var right_g := float(edge_g[index]) if index + 1 < count else 0.0
		var shunt_g := float(shunt_by_state[state_id])
		lower[index] = -left_g
		upper[index] = -right_g
		diag[index] = storage / delta_s + shunt_g + left_g + right_g
		rhs[index] = storage / delta_s * float(old_values[index]) + float(injections[index])

	var solved := _solve_tridiagonal(lower, diag, upper, rhs)
	if not bool(solved.get("success", false)):
		return solved
	var new_values: Array = solved["values"]
	var new_state := FullState.create(
		String(model["model_hash"]),
		String(model["full_state_schema"]["schema_hash"]),
		float(state["time_s"]) + delta_s,
		int(state["step_index"]) + 1,
		new_values
	)
	if new_state.is_empty():
		return _failure("B0_4_A_REFERENCE_STATE_CREATE_FAILED")

	var boundary: Array = []
	var boundary_power_in := 0.0
	for binding in model["port_bindings"]:
		var port_id := String(binding["port_id"])
		var state_id := String(binding["state_id"])
		var index := int(state_index[state_id])
		var port: Dictionary = boundary_port_by_id[port_id]
		var effort := float(new_values[index])
		var flow := float(port_flows[port_id])
		var power_into := float(_orientation_sign(String(port["orientation"]))) * effort * flow
		boundary_power_in += power_into
		boundary.append({
			"port_id": port_id,
			"effort": effort,
			"flow": flow,
			"power_into": power_into,
			"effort_dimension": port["effort_dimension"].duplicate(true),
			"flow_dimension": port["flow_dimension"].duplicate(true),
			"frame": String(port["frame"]),
			"orientation": String(port["orientation"]),
		})

	var stored_before := _stored_energy(model, old_values)
	var stored_after := _stored_energy(model, new_values)
	var dissipated_power := _dissipated_power(model, new_values)
	var numerical_dissipation := _numerical_dissipation_energy(model, old_values, new_values)
	var boundary_energy_in := boundary_power_in * delta_s
	var dissipated_energy := dissipated_power * delta_s
	var delta_stored := stored_after - stored_before
	var balance_residual := delta_stored + dissipated_energy + numerical_dissipation - boundary_energy_in
	var scale := maxf(
		1.0,
		maxf(
			absf(stored_before),
			maxf(absf(stored_after), maxf(absf(boundary_energy_in), absf(dissipated_energy)))
		)
	)
	var creation_tolerance := 2.0e-12 * scale
	var unaccounted_creation := maxf(0.0, balance_residual - creation_tolerance)

	return {
		"success": true,
		"state": new_state,
		"boundary": boundary,
		"energy": {
			"stored_before": stored_before,
			"stored_after": stored_after,
			"stored_delta": delta_stored,
			"boundary_power_in": boundary_power_in,
			"boundary_energy_in": boundary_energy_in,
			"dissipated_power": dissipated_power,
			"dissipated_energy": dissipated_energy,
			"numerical_dissipation_energy": numerical_dissipation,
			"balance_residual": balance_residual,
			"unaccounted_energy_creation": unaccounted_creation,
			"scale_aware_creation_tolerance": creation_tolerance,
		},
		"solver": {
			"version": SOLVER_VERSION,
			"method": Model.SOLVER_METHOD,
			"pivot_min_abs": float(solved["pivot_min_abs"]),
		},
	}

static func _solve_tridiagonal(
	lower: Array,
	diag: Array,
	upper: Array,
	rhs: Array
) -> Dictionary:
	var count := diag.size()
	if count < 1 or lower.size() != count or upper.size() != count or rhs.size() != count:
		return _failure("B0_4_A_INVALID_TRIDIAGONAL_SYSTEM")
	var c_prime: Array = []
	var d_prime: Array = []
	c_prime.resize(count)
	d_prime.resize(count)
	var pivot := float(diag[0])
	var pivot_min_abs := absf(pivot)
	if absf(pivot) <= PIVOT_EPS:
		return _failure("B0_4_A_TRIDIAGONAL_SINGULAR_PIVOT", {"index": 0})
	c_prime[0] = float(upper[0]) / pivot
	d_prime[0] = float(rhs[0]) / pivot
	for index in range(1, count):
		pivot = float(diag[index]) - float(lower[index]) * float(c_prime[index - 1])
		pivot_min_abs = minf(pivot_min_abs, absf(pivot))
		if absf(pivot) <= PIVOT_EPS:
			return _failure("B0_4_A_TRIDIAGONAL_SINGULAR_PIVOT", {"index": index})
		c_prime[index] = float(upper[index]) / pivot if index + 1 < count else 0.0
		d_prime[index] = (
			float(rhs[index]) - float(lower[index]) * float(d_prime[index - 1])
		) / pivot
	var values: Array = []
	values.resize(count)
	values[count - 1] = float(d_prime[count - 1])
	for reverse_index in range(count - 2, -1, -1):
		values[reverse_index] = float(d_prime[reverse_index]) - float(c_prime[reverse_index]) * float(values[reverse_index + 1])
	return {
		"success": true,
		"values": values,
		"pivot_min_abs": pivot_min_abs,
	}

static func _validate_state(model: Dictionary, state: Dictionary) -> Dictionary:
	var checked := FullState.validate(state)
	if not bool(checked.get("success", false)):
		return _failure(String(checked.get("error_code", "B0_4_A_INVALID_FULL_STATE")))
	if String(state["model_hash"]) != String(model["model_hash"]):
		return _failure("B0_4_A_FULL_STATE_MODEL_MISMATCH")
	if String(state["state_schema_hash"]) != String(model["full_state_schema"]["schema_hash"]):
		return _failure("B0_4_A_FULL_STATE_SCHEMA_MISMATCH")
	if state["values"].size() != int(model["full_state_schema"]["state_count"]):
		return _failure("B0_4_A_FULL_STATE_LENGTH_MISMATCH")
	return Utils.success()

static func _validate_port_flows(model: Dictionary, port_flows: Dictionary) -> Dictionary:
	var expected: Array = []
	for port in model["boundary_contract"]["ports"]:
		expected.append(String(port["port_id"]))
	expected.sort()
	var actual: Array = []
	for key in port_flows.keys():
		actual.append(String(key))
	actual.sort()
	if actual != expected:
		return _failure("B0_4_A_REFERENCE_PORT_FLOW_COVERAGE_MISMATCH", {
			"expected": expected,
			"actual": actual,
		})
	for port_id in expected:
		if not Utils.is_finite_number(port_flows[port_id]):
			return _failure("B0_4_A_NONFINITE_REFERENCE_PORT_FLOW", {"port_id": port_id})
	return Utils.success()

static func _stored_energy(model: Dictionary, values: Array) -> float:
	var energy := 0.0
	for index in range(values.size()):
		var storage := float(model["storage_nodes"][index]["storage_coefficient"])
		var effort := float(values[index])
		energy += 0.5 * storage * effort * effort
	return energy

static func _dissipated_power(model: Dictionary, values: Array) -> float:
	var index_by_state: Dictionary = Model.state_index(model)
	var power := 0.0
	for edge in model["edges"]:
		var a := int(index_by_state[String(edge["state_a_id"])])
		var b := int(index_by_state[String(edge["state_b_id"])])
		var delta := float(values[a]) - float(values[b])
		power += float(edge["conductance"]) * delta * delta
	for shunt in model["shunts"]:
		var index := int(index_by_state[String(shunt["state_id"])])
		var effort := float(values[index])
		power += float(shunt["conductance"]) * effort * effort
	return power

static func _numerical_dissipation_energy(
	model: Dictionary,
	old_values: Array,
	new_values: Array
) -> float:
	var energy := 0.0
	for index in range(old_values.size()):
		var delta := float(new_values[index]) - float(old_values[index])
		energy += 0.5 * float(model["storage_nodes"][index]["storage_coefficient"]) * delta * delta
	return energy

static func _orientation_sign(orientation: String) -> int:
	return 1 if orientation == "INTO_SUBSYSTEM" else -1

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": code,
		"details": details.duplicate(true),
	}
