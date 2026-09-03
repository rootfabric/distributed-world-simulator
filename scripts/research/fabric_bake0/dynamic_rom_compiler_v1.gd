extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Dense = preload("res://scripts/research/fabric_bake0/dense_linear_algebra_v1.gd")
const FullModel = preload("res://scripts/research/fabric_bake0/dynamic_full_model_descriptor_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/dynamic_rom_descriptor_v1.gd")
const ArtifactBinding = preload("res://scripts/research/fabric_bake0/dynamic_rom_artifact_binding_v1.gd")
const ReducedStateSchema = preload("res://scripts/research/fabric_bake0/dynamic_rom_state_schema_v1.gd")

const COMPILER_VERSION := "FABRIC-BAKE/B0.4-B/R1"
const STATUS_READY := "ROM_REDUCTION_READY_NOT_RUNTIME_CERTIFIED"
const STATUS_NO_SAFE_BAKE := "NO_SAFE_BAKE"
const TARGET_REDUCED_STATES := 24
const INTERPOLATION_TOLERANCE := 1.0e-8
const ORTHONORMALITY_TOLERANCE := 1.0e-9
const LAPLACE_SHIFTS: Array = [0.0, 0.2, 1.0, 5.0, 20.0, 100.0]

static func compile(
	full_model: Dictionary,
	target_reduced_states: int = TARGET_REDUCED_STATES,
	laplace_shifts: Array = LAPLACE_SHIFTS
) -> Dictionary:
	var checked := FullModel.validate(full_model)
	if not bool(checked.get("success", false)):
		return _no_safe(String(checked.get("error_code", "B0_4_B_INVALID_FULL_MODEL")))
	var n := int(full_model["full_state_schema"]["state_count"])
	var port_count: int = int(full_model["boundary_contract"]["ports"].size())
	if n < 512:
		return _no_safe("B0_4_B_FULL_STATE_REFERENCE_BELOW_512")
	if target_reduced_states != TARGET_REDUCED_STATES:
		return _no_safe("B0_4_B_R1_REQUIRES_24_REDUCED_STATES")
	if target_reduced_states > 24 or float(n) / float(target_reduced_states) < 20.0:
		return _no_safe("B0_4_B_REDUCTION_TARGET_TOO_WEAK")
	if laplace_shifts != LAPLACE_SHIFTS:
		return _no_safe("B0_4_B_R1_SHIFT_SET_MISMATCH")
	if laplace_shifts.size() * port_count != target_reduced_states:
		return _no_safe("B0_4_B_SHIFT_PORT_BASIS_SIZE_MISMATCH")

	var operators := _full_operators(full_model)
	if not bool(operators.get("success", false)):
		return operators

	var basis_result := _build_basis(full_model, operators, laplace_shifts)
	if not bool(basis_result.get("success", false)):
		return basis_result
	var basis_columns: Array = basis_result["basis_columns"]
	if basis_columns.size() != target_reduced_states:
		return _no_safe("B0_4_B_BASIS_RANK_DEFICIENT", {"rank": basis_columns.size()})
	var basis_matrix := _columns_to_rows(basis_columns, n)

	var reduced_mass := _reduced_mass(operators["storage"], basis_columns)
	var reduced_dissipation := _reduced_dissipation(
		operators["shunts"], operators["edges"], basis_columns
	)
	var port_data := _port_data(full_model)
	if not bool(port_data.get("success", false)):
		return port_data
	var reduced_input := _reduced_input(basis_columns, port_data["indices"], port_data["signs"])
	var reduced_output := _reduced_output(basis_columns, port_data["indices"])

	var passivity := _passivity_certificate(reduced_mass, reduced_dissipation)
	if not bool(passivity.get("certified", false)):
		return _no_safe("B0_4_B_PASSIVITY_CERTIFICATE_FAILED", passivity)

	var interpolation := _interpolation_certificate(
		operators,
		reduced_mass,
		reduced_dissipation,
		reduced_input,
		reduced_output,
		port_data["indices"],
		laplace_shifts
	)
	if not bool(interpolation.get("certified", false)):
		return _no_safe("B0_4_B_INTERPOLATION_CERTIFICATE_FAILED", interpolation)

	var basis_hash := Utils.canonical_hash(basis_matrix)
	var reduced_state_schema := ReducedStateSchema.create(target_reduced_states)
	if reduced_state_schema.is_empty():
		return _no_safe("B0_4_B_REDUCED_STATE_SCHEMA_CREATE_FAILED")
	var reduced_state_schema_hash := String(reduced_state_schema["schema_hash"])
	var descriptor := Descriptor.create(
		"dynamic-rom/b0-4-r1",
		COMPILER_VERSION,
		String(full_model["model_hash"]),
		String(full_model["source_binding"]["checksum"]),
		String(full_model["boundary_contract"]["contract_hash"]),
		String(full_model["full_state_schema"]["schema_hash"]),
		reduced_state_schema_hash,
		laplace_shifts,
		basis_matrix,
		reduced_mass,
		reduced_dissipation,
		reduced_input,
		reduced_output,
		port_data["port_ids"],
		port_data["signs"],
		n,
		passivity,
		interpolation
	)
	if descriptor.is_empty():
		return _no_safe("B0_4_B_DESCRIPTOR_CREATE_FAILED")
	checked = Descriptor.validate(descriptor)
	if not bool(checked.get("success", false)):
		return _no_safe(String(checked.get("error_code", "B0_4_B_DESCRIPTOR_INVALID")))
	var binding := ArtifactBinding.create(descriptor)
	if binding.is_empty():
		return _no_safe("B0_4_B_ARTIFACT_BINDING_CREATE_FAILED")

	return {
		"success": true,
		"status": STATUS_READY,
		"reason": "",
		"descriptor": descriptor,
		"reduced_state_schema": reduced_state_schema,
		"artifact_binding": binding,
		"diagnostics": {
			"full_state_count": n,
			"reduced_state_count": target_reduced_states,
			"reduction_ratio": float(n) / float(target_reduced_states),
			"basis_rank": basis_columns.size(),
			"basis_hash": String(descriptor["basis_hash"]),
			"descriptor_hash": String(descriptor["descriptor_hash"]),
			"artifact_binding_hash": String(binding["binding_hash"]),
			"c_orthonormality_error": float(passivity["c_orthonormality_error"]),
			"mass_min_cholesky_pivot": float(passivity["mass_min_cholesky_pivot"]),
			"dissipation_min_cholesky_pivot": float(passivity["dissipation_min_cholesky_pivot"]),
			"interpolation_max_abs_error": float(interpolation["max_abs_boundary_error"]),
			"interpolation_max_relative_error": float(interpolation["max_relative_boundary_error"]),
			"interpolation_probe_count": int(interpolation["probe_count"]),
			"runtime_certified": false,
		},
	}

static func _full_operators(model: Dictionary) -> Dictionary:
	var n := int(model["full_state_schema"]["state_count"])
	var storage: Array = []
	storage.resize(n)
	var shunts: Array = []
	shunts.resize(n)
	shunts.fill(0.0)
	for index in range(n):
		storage[index] = float(model["storage_nodes"][index]["storage_coefficient"])
	var state_index: Dictionary = FullModel.state_index(model)
	for shunt in model["shunts"]:
		var index := int(state_index[String(shunt["state_id"])])
		shunts[index] = float(shunt["conductance"])
	var edges: Array = []
	for edge in model["edges"]:
		var a := int(state_index[String(edge["state_a_id"])])
		var b := int(state_index[String(edge["state_b_id"])])
		if b != a + 1:
			return _no_safe("B0_4_B_R1_REQUIRES_CANONICAL_PATH")
		edges.append({
			"a": a,
			"b": b,
			"g": float(edge["conductance"]),
		})
	if edges.size() != n - 1:
		return _no_safe("B0_4_B_R1_PATH_EDGE_COUNT_MISMATCH")
	return {
		"success": true,
		"storage": storage,
		"shunts": shunts,
		"edges": edges,
	}

static func _port_data(model: Dictionary) -> Dictionary:
	var state_index: Dictionary = FullModel.state_index(model)
	var indices: Array = []
	var signs: Array = []
	var port_ids: Array = []
	if model["port_bindings"].size() != model["boundary_contract"]["ports"].size():
		return _no_safe("B0_4_B_PORT_BINDING_COVERAGE_MISMATCH")
	for index in range(model["port_bindings"].size()):
		var binding: Dictionary = model["port_bindings"][index]
		var port: Dictionary = model["boundary_contract"]["ports"][index]
		if String(binding["port_id"]) != String(port["port_id"]):
			return _no_safe("B0_4_B_PORT_ORDER_MISMATCH")
		var state_id := String(binding["state_id"])
		if not state_index.has(state_id):
			return _no_safe("B0_4_B_PORT_STATE_MISSING")
		indices.append(int(state_index[state_id]))
		signs.append(1.0 if String(port["orientation"]) == "INTO_SUBSYSTEM" else -1.0)
		port_ids.append(String(port["port_id"]))
	return {
		"success": true,
		"indices": indices,
		"signs": signs,
		"port_ids": port_ids,
	}

static func _build_basis(
	model: Dictionary,
	operators: Dictionary,
	laplace_shifts: Array
) -> Dictionary:
	var port_data := _port_data(model)
	if not bool(port_data.get("success", false)):
		return port_data
	var n := int(model["full_state_schema"]["state_count"])
	var basis: Array = []
	for shift_raw in laplace_shifts:
		var shift := float(shift_raw)
		for port_index in range(port_data["indices"].size()):
			var rhs: Array = []
			rhs.resize(n)
			rhs.fill(0.0)
			rhs[int(port_data["indices"][port_index])] = float(port_data["signs"][port_index])
			var solved := _solve_shifted_full(operators, shift, rhs)
			if not bool(solved.get("success", false)):
				return solved
			var vector: Array = solved["values"]
			for _pass in range(2):
				for existing in basis:
					var coefficient := _c_inner(existing, vector, operators["storage"])
					for index in range(n):
						vector[index] = float(vector[index]) - coefficient * float(existing[index])
			var norm_squared := _c_inner(vector, vector, operators["storage"])
			if norm_squared <= 1.0e-24:
				return _no_safe("B0_4_B_BASIS_RANK_DEFICIENT", {
					"shift": shift,
					"port_index": port_index,
					"rank": basis.size(),
				})
			var inverse_norm := 1.0 / sqrt(norm_squared)
			for index in range(n):
				vector[index] = float(vector[index]) * inverse_norm
			basis.append(vector)
	return {"success": true, "basis_columns": basis}

static func _solve_shifted_full(
	operators: Dictionary,
	shift: float,
	rhs: Array
) -> Dictionary:
	var storage: Array = operators["storage"]
	var shunts: Array = operators["shunts"]
	var edges: Array = operators["edges"]
	var n := storage.size()
	if rhs.size() != n:
		return _no_safe("B0_4_B_SHIFTED_FULL_RHS_MISMATCH")
	var lower: Array = []
	var diag: Array = []
	var upper: Array = []
	lower.resize(n)
	diag.resize(n)
	upper.resize(n)
	lower.fill(0.0)
	diag.fill(0.0)
	upper.fill(0.0)
	for index in range(n):
		diag[index] = float(shunts[index]) + shift * float(storage[index])
	for edge in edges:
		var a := int(edge["a"])
		var b := int(edge["b"])
		var g := float(edge["g"])
		diag[a] = float(diag[a]) + g
		diag[b] = float(diag[b]) + g
		upper[a] = -g
		lower[b] = -g
	return _solve_tridiagonal(lower, diag, upper, rhs)

static func _solve_tridiagonal(
	lower: Array,
	diag: Array,
	upper: Array,
	rhs: Array
) -> Dictionary:
	var n := diag.size()
	if n < 1 or lower.size() != n or upper.size() != n or rhs.size() != n:
		return _no_safe("B0_4_B_INVALID_TRIDIAGONAL_SYSTEM")
	var c_prime: Array = []
	var d_prime: Array = []
	c_prime.resize(n)
	d_prime.resize(n)
	var pivot := float(diag[0])
	if absf(pivot) <= 1.0e-15:
		return _no_safe("B0_4_B_SINGULAR_FULL_SHIFT_SYSTEM", {"index": 0})
	c_prime[0] = float(upper[0]) / pivot
	d_prime[0] = float(rhs[0]) / pivot
	for index in range(1, n):
		pivot = float(diag[index]) - float(lower[index]) * float(c_prime[index - 1])
		if absf(pivot) <= 1.0e-15:
			return _no_safe("B0_4_B_SINGULAR_FULL_SHIFT_SYSTEM", {"index": index})
		c_prime[index] = float(upper[index]) / pivot if index + 1 < n else 0.0
		d_prime[index] = (
			float(rhs[index]) - float(lower[index]) * float(d_prime[index - 1])
		) / pivot
	var values: Array = []
	values.resize(n)
	values[n - 1] = float(d_prime[n - 1])
	for index in range(n - 2, -1, -1):
		values[index] = float(d_prime[index]) - float(c_prime[index]) * float(values[index + 1])
	return {"success": true, "values": values}

static func _reduced_mass(storage: Array, basis: Array) -> Array:
	var r := basis.size()
	var matrix := _zero_matrix(r, r)
	for a in range(r):
		for b in range(a, r):
			var value := _c_inner(basis[a], basis[b], storage)
			matrix[a][b] = value
			matrix[b][a] = value
	return matrix

static func _reduced_dissipation(shunts: Array, edges: Array, basis: Array) -> Array:
	var r := basis.size()
	var matrix := _zero_matrix(r, r)
	for a in range(r):
		for b in range(a, r):
			var value := 0.0
			for index in range(shunts.size()):
				value += float(shunts[index]) * float(basis[a][index]) * float(basis[b][index])
			for edge in edges:
				var i := int(edge["a"])
				var j := int(edge["b"])
				var da := float(basis[a][i]) - float(basis[a][j])
				var db := float(basis[b][i]) - float(basis[b][j])
				value += float(edge["g"]) * da * db
			matrix[a][b] = value
			matrix[b][a] = value
	return matrix

static func _reduced_input(basis: Array, port_indices: Array, port_signs: Array) -> Array:
	var matrix := _zero_matrix(basis.size(), port_indices.size())
	for reduced_index in range(basis.size()):
		for port_index in range(port_indices.size()):
			matrix[reduced_index][port_index] = (
				float(port_signs[port_index])
				* float(basis[reduced_index][int(port_indices[port_index])])
			)
	return matrix

static func _reduced_output(basis: Array, port_indices: Array) -> Array:
	var matrix := _zero_matrix(port_indices.size(), basis.size())
	for port_index in range(port_indices.size()):
		for reduced_index in range(basis.size()):
			matrix[port_index][reduced_index] = float(basis[reduced_index][int(port_indices[port_index])])
	return matrix

static func _passivity_certificate(mass: Array, dissipation: Array) -> Dictionary:
	var mass_symmetry := Dense.symmetry_error(mass)
	var dissipation_symmetry := Dense.symmetry_error(dissipation)
	var orthonormality := 0.0
	for row in range(mass.size()):
		for column in range(mass.size()):
			var expected := 1.0 if row == column else 0.0
			orthonormality = maxf(orthonormality, absf(float(mass[row][column]) - expected))
	var mass_cholesky := _cholesky_min_pivot(mass)
	var dissipation_cholesky := _cholesky_min_pivot(dissipation)
	var certified := (
		orthonormality <= ORTHONORMALITY_TOLERANCE
		and mass_symmetry <= 1.0e-12
		and dissipation_symmetry <= 1.0e-12
		and bool(mass_cholesky.get("success", false))
		and bool(dissipation_cholesky.get("success", false))
		and float(mass_cholesky.get("min_pivot", 0.0)) > 1.0e-10
		and float(dissipation_cholesky.get("min_pivot", 0.0)) > 1.0e-10
	)
	var certificate := {
		"certificate_kind": "CONGRUENCE_PASSIVITY_SPD_R1",
		"c_orthonormality_error": orthonormality,
		"mass_symmetry_error": mass_symmetry,
		"dissipation_symmetry_error": dissipation_symmetry,
		"mass_min_cholesky_pivot": float(mass_cholesky.get("min_pivot", 0.0)),
		"dissipation_min_cholesky_pivot": float(dissipation_cholesky.get("min_pivot", 0.0)),
		"certified": certified,
	}
	certificate["certificate_hash"] = Utils.canonical_hash(certificate)
	return certificate

static func _interpolation_certificate(
	operators: Dictionary,
	reduced_mass: Array,
	reduced_dissipation: Array,
	reduced_input: Array,
	reduced_output: Array,
	port_indices: Array,
	laplace_shifts: Array
) -> Dictionary:
	var max_abs_error := 0.0
	var max_relative_error := 0.0
	var probe_count := 0
	for shift_raw in laplace_shifts:
		var shift := float(shift_raw)
		var reduced_operator := _matrix_add(
			reduced_dissipation,
			_matrix_scale(reduced_mass, shift)
		)
		var factor := Dense.factor_square(reduced_operator, 1.0e-13)
		if not bool(factor.get("success", false)):
			return {
				"certificate_kind": "RATIONAL_INTERPOLATION_R1",
				"laplace_shifts": laplace_shifts.duplicate(),
				"probe_count": probe_count,
				"max_abs_boundary_error": INF,
				"max_relative_boundary_error": INF,
				"certified_tolerance": INTERPOLATION_TOLERANCE,
				"certified": false,
				"certificate_hash": Utils.canonical_hash({"failed": "REDUCED_SHIFT_SINGULAR"}),
			}
		for input_port in range(port_indices.size()):
			var rhs_full: Array = []
			rhs_full.resize(operators["storage"].size())
			rhs_full.fill(0.0)
			var sign := 1.0
			# Br already contains the exact orientation sign. Recover it from the
			# first non-zero relation between Br and the basis/output rows.
			for reduced_index in range(reduced_input.size()):
				var output_value := float(reduced_output[input_port][reduced_index])
				if absf(output_value) > 1.0e-14:
					sign = signf(float(reduced_input[reduced_index][input_port]) / output_value)
					break
			rhs_full[int(port_indices[input_port])] = sign
			var full_solve := _solve_shifted_full(operators, shift, rhs_full)
			if not bool(full_solve.get("success", false)):
				return _failed_interpolation(laplace_shifts, probe_count, "FULL_SHIFT_SOLVE")
			var rhs_reduced: Array = []
			for row in range(reduced_input.size()):
				rhs_reduced.append(float(reduced_input[row][input_port]))
			var reduced_solve := Dense.solve_factored(factor, rhs_reduced)
			if not bool(reduced_solve.get("success", false)):
				return _failed_interpolation(laplace_shifts, probe_count, "REDUCED_SHIFT_SOLVE")
			var reduced_state: Array = reduced_solve["details"]["solution"]
			var full_output: Array = []
			var reduced_output_values: Array = []
			for output_port in range(port_indices.size()):
				full_output.append(float(full_solve["values"][int(port_indices[output_port])]))
				var value := 0.0
				for reduced_index in range(reduced_state.size()):
					value += float(reduced_output[output_port][reduced_index]) * float(reduced_state[reduced_index])
				reduced_output_values.append(value)
			var abs_error := Dense.max_abs_delta(full_output, reduced_output_values)
			var full_norm := sqrt(maxf(0.0, Dense.dot(full_output, full_output)))
			var error_vector: Array = []
			for index in range(full_output.size()):
				error_vector.append(float(full_output[index]) - float(reduced_output_values[index]))
			var error_norm := sqrt(maxf(0.0, Dense.dot(error_vector, error_vector)))
			var relative := error_norm / maxf(full_norm, 1.0e-15)
			max_abs_error = maxf(max_abs_error, abs_error)
			max_relative_error = maxf(max_relative_error, relative)
			probe_count += 1
	var certified := max_abs_error <= INTERPOLATION_TOLERANCE and max_relative_error <= INTERPOLATION_TOLERANCE
	var certificate := {
		"certificate_kind": "RATIONAL_INTERPOLATION_R1",
		"laplace_shifts": laplace_shifts.duplicate(),
		"probe_count": probe_count,
		"max_abs_boundary_error": max_abs_error,
		"max_relative_boundary_error": max_relative_error,
		"certified_tolerance": INTERPOLATION_TOLERANCE,
		"certified": certified,
	}
	certificate["certificate_hash"] = Utils.canonical_hash(certificate)
	return certificate

static func _failed_interpolation(shifts: Array, probe_count: int, reason: String) -> Dictionary:
	var certificate := {
		"certificate_kind": "RATIONAL_INTERPOLATION_R1",
		"laplace_shifts": shifts.duplicate(),
		"probe_count": probe_count,
		"max_abs_boundary_error": 1.0e30,
		"max_relative_boundary_error": 1.0e30,
		"certified_tolerance": INTERPOLATION_TOLERANCE,
		"certified": false,
	}
	certificate["certificate_hash"] = Utils.canonical_hash({
		"certificate": certificate,
		"reason": reason,
	})
	return certificate

static func _cholesky_min_pivot(matrix: Array) -> Dictionary:
	var n := matrix.size()
	if n < 1:
		return {"success": false, "min_pivot": 0.0}
	var lower := _zero_matrix(n, n)
	var min_pivot := INF
	for row in range(n):
		for column in range(row + 1):
			var value := float(matrix[row][column])
			for k in range(column):
				value -= float(lower[row][k]) * float(lower[column][k])
			if row == column:
				if value <= 1.0e-15:
					return {"success": false, "min_pivot": maxf(0.0, value)}
				var pivot := sqrt(value)
				lower[row][column] = pivot
				min_pivot = minf(min_pivot, pivot)
			else:
				lower[row][column] = value / float(lower[column][column])
	return {"success": true, "min_pivot": min_pivot}

static func _c_inner(a: Array, b: Array, storage: Array) -> float:
	var value := 0.0
	for index in range(storage.size()):
		value += float(storage[index]) * float(a[index]) * float(b[index])
	return value

static func _columns_to_rows(columns: Array, row_count: int) -> Array:
	var rows := _zero_matrix(row_count, columns.size())
	for column in range(columns.size()):
		for row in range(row_count):
			rows[row][column] = float(columns[column][row])
	return rows

static func _reduced_state_ids(count: int) -> Array:
	var output: Array = []
	for index in range(count):
		output.append("rom-state/%03d" % index)
	return output

static func _zero_matrix(rows: int, columns: int) -> Array:
	var matrix: Array = []
	for _row in range(rows):
		var row: Array = []
		row.resize(columns)
		row.fill(0.0)
		matrix.append(row)
	return matrix

static func _matrix_scale(matrix: Array, scale: float) -> Array:
	var output := _zero_matrix(matrix.size(), matrix[0].size())
	for row in range(matrix.size()):
		for column in range(matrix[row].size()):
			output[row][column] = float(matrix[row][column]) * scale
	return output

static func _matrix_add(a: Array, b: Array) -> Array:
	var output := _zero_matrix(a.size(), a[0].size())
	for row in range(a.size()):
		for column in range(a[row].size()):
			output[row][column] = float(a[row][column]) + float(b[row][column])
	return output

static func _no_safe(reason: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"status": STATUS_NO_SAFE_BAKE,
		"error_code": reason,
		"reason": reason,
		"details": details.duplicate(true),
	}
