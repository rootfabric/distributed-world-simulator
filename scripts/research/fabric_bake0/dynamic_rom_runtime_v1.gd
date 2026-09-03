extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Dense = preload("res://scripts/research/fabric_bake0/dense_linear_algebra_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/dynamic_rom_descriptor_v1.gd")
const RomState = preload("res://scripts/research/fabric_bake0/dynamic_rom_state_v1.gd")

const RUNTIME_VERSION := "FABRIC-BAKE/B0.4-B/VALIDATION-RUNTIME-R1"

static func initial_state(descriptor: Dictionary) -> Dictionary:
	var checked := Descriptor.validate(descriptor)
	if not bool(checked.get("success", false)):
		return _failure(String(checked.get("error_code", "B0_4_B_INVALID_ROM_DESCRIPTOR")))
	var values: Array = []
	values.resize(int(descriptor["reduced_state_count"]))
	values.fill(0.0)
	var state := RomState.create(
		String(descriptor["descriptor_hash"]),
		String(descriptor["reduced_state_schema_hash"]),
		0.0,
		0,
		values
	)
	if state.is_empty():
		return _failure("B0_4_B_ROM_INITIAL_STATE_CREATE_FAILED")
	return {
		"success": true,
		"state": state,
		"stored_energy": 0.0,
	}

static func step(
	descriptor: Dictionary,
	state: Dictionary,
	port_flows: Dictionary,
	delta_s: float
) -> Dictionary:
	var prepared := prepare_step(descriptor, delta_s)
	if not bool(prepared.get("success", false)):
		return prepared
	var checked := _validate_state(descriptor, state)
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_port_flows(descriptor, port_flows)
	if not bool(checked.get("success", false)):
		return checked
	return _step_prepared(descriptor, state, port_flows, delta_s, prepared)

static func prepare_step(descriptor: Dictionary, delta_s: float) -> Dictionary:
	var checked := Descriptor.validate(descriptor)
	if not bool(checked.get("success", false)):
		return _failure(String(checked.get("error_code", "B0_4_B_INVALID_ROM_DESCRIPTOR")))
	if not Utils.is_positive_number(delta_s):
		return _failure("B0_4_B_INVALID_ROM_STEP")
	var operator := _matrix_add(
		descriptor["reduced_dissipation_matrix"],
		_matrix_scale(descriptor["reduced_mass_matrix"], 1.0 / delta_s)
	)
	var factor := Dense.factor_square(operator, 1.0e-13)
	if not bool(factor.get("success", false)):
		return _failure("B0_4_B_ROM_STEP_OPERATOR_SINGULAR")
	return {
		"success": true,
		"delta_s": delta_s,
		"descriptor_hash": String(descriptor["descriptor_hash"]),
		"factor": factor,
		"operator_hash": Utils.canonical_hash(operator),
	}

static func step_prepared(
	descriptor: Dictionary,
	state: Dictionary,
	port_flows: Dictionary,
	delta_s: float,
	prepared: Dictionary
) -> Dictionary:
	if String(prepared.get("descriptor_hash", "")) != String(descriptor.get("descriptor_hash", "")):
		return _failure("B0_4_B_ROM_PREPARED_DESCRIPTOR_MISMATCH")
	var checked := _validate_state(descriptor, state)
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_port_flows(descriptor, port_flows)
	if not bool(checked.get("success", false)):
		return checked
	return _step_prepared(descriptor, state, port_flows, delta_s, prepared)

static func advance_sequence(
	descriptor: Dictionary,
	state: Dictionary,
	flow_sequence: Array,
	delta_s: float
) -> Dictionary:
	var prepared := prepare_step(descriptor, delta_s)
	if not bool(prepared.get("success", false)):
		return prepared
	var checked := _validate_state(descriptor, state)
	if not bool(checked.get("success", false)):
		return checked
	if flow_sequence.is_empty():
		return _failure("B0_4_B_EMPTY_ROM_FLOW_SEQUENCE")
	var current: Dictionary = state.duplicate(true)
	var max_balance_residual := 0.0
	var max_unaccounted_creation := 0.0
	var boundary_energy_in := 0.0
	var dissipated_energy := 0.0
	var numerical_dissipation_energy := 0.0
	var boundary: Array = []
	for raw in flow_sequence:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("B0_4_B_INVALID_ROM_FLOW_SAMPLE")
		checked = _validate_port_flows(descriptor, raw)
		if not bool(checked.get("success", false)):
			return checked
		var advanced := _step_prepared(descriptor, current, raw, delta_s, prepared)
		if not bool(advanced.get("success", false)):
			return advanced
		current = advanced["state"]
		boundary = advanced["boundary"]
		max_balance_residual = maxf(max_balance_residual, absf(float(advanced["energy"]["balance_residual"])))
		max_unaccounted_creation = maxf(max_unaccounted_creation, float(advanced["energy"]["unaccounted_energy_creation"]))
		boundary_energy_in += float(advanced["energy"]["boundary_energy_in"])
		dissipated_energy += float(advanced["energy"]["dissipated_energy"])
		numerical_dissipation_energy += float(advanced["energy"]["numerical_dissipation_energy"])
	return {
		"success": true,
		"state": current,
		"boundary": boundary,
		"summary": {
			"steps": flow_sequence.size(),
			"delta_s": delta_s,
			"max_balance_residual": max_balance_residual,
			"max_unaccounted_energy_creation": max_unaccounted_creation,
			"boundary_energy_in": boundary_energy_in,
			"dissipated_energy": dissipated_energy,
			"numerical_dissipation_energy": numerical_dissipation_energy,
			"final_stored_energy": _quadratic_energy(
				descriptor["reduced_mass_matrix"],
				current["values"]
			),
		},
	}

static func _step_prepared(
	descriptor: Dictionary,
	state: Dictionary,
	port_flows: Dictionary,
	delta_s: float,
	prepared: Dictionary
) -> Dictionary:
	if absf(float(prepared.get("delta_s", -1.0)) - delta_s) > 1.0e-15:
		return _failure("B0_4_B_ROM_PREPARED_STEP_MISMATCH")
	var old_values: Array = state["values"]
	var flow_vector: Array = []
	for port_id in descriptor["port_ids"]:
		flow_vector.append(float(port_flows[String(port_id)]))
	var mass_old := Dense.matvec(descriptor["reduced_mass_matrix"], old_values)
	var input := Dense.matvec(descriptor["reduced_input_matrix"], flow_vector)
	var rhs: Array = []
	for index in range(old_values.size()):
		rhs.append(float(mass_old[index]) / delta_s + float(input[index]))
	var solved := Dense.solve_factored(prepared["factor"], rhs)
	if not bool(solved.get("success", false)):
		return _failure("B0_4_B_ROM_STEP_SOLVE_FAILED")
	var new_values: Array = solved["details"]["solution"]
	var new_state := RomState.create(
		String(descriptor["descriptor_hash"]),
		String(descriptor["reduced_state_schema_hash"]),
		float(state["time_s"]) + delta_s,
		int(state["step_index"]) + 1,
		new_values
	)
	if new_state.is_empty():
		return _failure("B0_4_B_ROM_STATE_CREATE_FAILED")

	var efforts := Dense.matvec(descriptor["reduced_output_matrix"], new_values)
	var boundary: Array = []
	var boundary_power_in := 0.0
	for port_index in range(descriptor["port_ids"].size()):
		var effort := float(efforts[port_index])
		var flow := float(flow_vector[port_index])
		var sign := float(descriptor["port_orientation_signs"][port_index])
		var power_into := sign * effort * flow
		boundary_power_in += power_into
		boundary.append({
			"port_id": String(descriptor["port_ids"][port_index]),
			"effort": effort,
			"flow": flow,
			"power_into": power_into,
		})

	var stored_before := _quadratic_energy(descriptor["reduced_mass_matrix"], old_values)
	var stored_after := _quadratic_energy(descriptor["reduced_mass_matrix"], new_values)
	var dissipated_power := _quadratic_form(descriptor["reduced_dissipation_matrix"], new_values)
	var delta_values: Array = []
	for index in range(old_values.size()):
		delta_values.append(float(new_values[index]) - float(old_values[index]))
	var numerical_dissipation := _quadratic_energy(descriptor["reduced_mass_matrix"], delta_values)
	var boundary_energy_in := boundary_power_in * delta_s
	var dissipated_energy := dissipated_power * delta_s
	var stored_delta := stored_after - stored_before
	var balance_residual := stored_delta + dissipated_energy + numerical_dissipation - boundary_energy_in
	var scale := maxf(
		1.0,
		maxf(
			absf(stored_before),
			maxf(absf(stored_after), maxf(absf(boundary_energy_in), absf(dissipated_energy)))
		)
	)
	var tolerance := 5.0e-12 * scale
	var unaccounted_creation := maxf(0.0, balance_residual - tolerance)

	return {
		"success": true,
		"state": new_state,
		"boundary": boundary,
		"energy": {
			"stored_before": stored_before,
			"stored_after": stored_after,
			"stored_delta": stored_delta,
			"boundary_power_in": boundary_power_in,
			"boundary_energy_in": boundary_energy_in,
			"dissipated_power": dissipated_power,
			"dissipated_energy": dissipated_energy,
			"numerical_dissipation_energy": numerical_dissipation,
			"balance_residual": balance_residual,
			"unaccounted_energy_creation": unaccounted_creation,
			"scale_aware_creation_tolerance": tolerance,
		},
		"runtime": {
			"version": RUNTIME_VERSION,
			"operator_hash": String(prepared["operator_hash"]),
			"execution_scope": "VALIDATION_ONLY_B0_4_B",
		},
	}

static func _validate_state(descriptor: Dictionary, state: Dictionary) -> Dictionary:
	var checked := RomState.validate(state)
	if not bool(checked.get("success", false)):
		return _failure(String(checked.get("error_code", "B0_4_B_INVALID_ROM_STATE")))
	if String(state["rom_descriptor_hash"]) != String(descriptor["descriptor_hash"]):
		return _failure("B0_4_B_ROM_STATE_DESCRIPTOR_MISMATCH")
	if String(state["reduced_state_schema_hash"]) != String(descriptor["reduced_state_schema_hash"]):
		return _failure("B0_4_B_ROM_STATE_SCHEMA_MISMATCH")
	if state["values"].size() != int(descriptor["reduced_state_count"]):
		return _failure("B0_4_B_ROM_STATE_LENGTH_MISMATCH")
	return Utils.success()

static func _validate_port_flows(descriptor: Dictionary, port_flows: Dictionary) -> Dictionary:
	var expected: Array = descriptor["port_ids"].duplicate()
	var actual: Array = []
	for key in port_flows.keys():
		actual.append(String(key))
	actual.sort()
	if actual != expected:
		return _failure("B0_4_B_ROM_PORT_FLOW_COVERAGE_MISMATCH", {
			"expected": expected,
			"actual": actual,
		})
	for port_id in expected:
		if not Utils.is_finite_number(port_flows[String(port_id)]):
			return _failure("B0_4_B_ROM_NONFINITE_PORT_FLOW", {"port_id": port_id})
	return Utils.success()

static func _quadratic_energy(matrix: Array, values: Array) -> float:
	return 0.5 * _quadratic_form(matrix, values)

static func _quadratic_form(matrix: Array, values: Array) -> float:
	var product := Dense.matvec(matrix, values)
	return Dense.dot(values, product)

static func _matrix_scale(matrix: Array, scale: float) -> Array:
	var output: Array = []
	for row in matrix:
		var new_row: Array = []
		for value in row:
			new_row.append(float(value) * scale)
		output.append(new_row)
	return output

static func _matrix_add(a: Array, b: Array) -> Array:
	var output: Array = []
	for row_index in range(a.size()):
		var row: Array = []
		for column_index in range(a[row_index].size()):
			row.append(float(a[row_index][column_index]) + float(b[row_index][column_index]))
		output.append(row)
	return output

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": code,
		"details": details.duplicate(true),
	}
