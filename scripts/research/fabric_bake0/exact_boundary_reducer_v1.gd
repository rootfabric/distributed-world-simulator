extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const LinearSystem = preload("res://scripts/research/fabric_bake0/linear_boundary_system_v1.gd")
const LinearAlgebra = preload("res://scripts/research/fabric_bake0/dense_linear_algebra_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/exact_boundary_reduction_descriptor_v1.gd")

const REDUCED := "REDUCED"
const NO_SAFE_BAKE := "NO_SAFE_BAKE"
const POLICY_FIELDS: Array[String] = [
	"pivot_relative_tolerance", "symmetry_tolerance", "passivity_tolerance",
	"require_symmetric", "require_passive_laplacian",
]

static func reduce(system: Dictionary, policy: Dictionary) -> Dictionary:
	var checked := LinearSystem.validate(system)
	if not bool(checked.get("success", false)):
		return checked
	checked = Utils.validate_exact_fields(policy, POLICY_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	for field in ["pivot_relative_tolerance", "symmetry_tolerance", "passivity_tolerance"]:
		if not Utils.is_positive_number(policy.get(field)):
			return Utils.failure("INVALID_EXACT_BOUNDARY_POLICY_NUMBER", {"field": field})
	for field in ["require_symmetric", "require_passive_laplacian"]:
		if typeof(policy.get(field)) != TYPE_BOOL:
			return Utils.failure("INVALID_EXACT_BOUNDARY_POLICY_FLAG", {"field": field})

	var boundary_count: int = int(system["boundary_port_ids"].size())
	var internal_count: int = int(system["internal_variable_ids"].size())
	var matrix: Array = system["coefficient_matrix"]
	var rhs: Array = system["rhs"]
	var a_bb := _slice_matrix(matrix, 0, boundary_count, 0, boundary_count)
	var a_bi := _slice_matrix(matrix, 0, boundary_count, boundary_count, boundary_count + internal_count)
	var a_ib := _slice_matrix(matrix, boundary_count, boundary_count + internal_count, 0, boundary_count)
	var a_ii := _slice_matrix(matrix, boundary_count, boundary_count + internal_count, boundary_count, boundary_count + internal_count)
	var r_b := rhs.slice(0, boundary_count)
	var r_i := rhs.slice(boundary_count, boundary_count + internal_count)

	var factor := LinearAlgebra.factor_square(a_ii, float(policy["pivot_relative_tolerance"]))
	if not bool(factor.get("success", false)):
		if String(factor.get("error_code", "")) == "RANK_DEFICIENCY":
			return _no_safe("RANK_DEFICIENCY", factor.get("details", {}))
		return factor
	var factor_details: Dictionary = factor["details"]

	var solved_columns: Array = []
	for column in range(boundary_count):
		var column_rhs: Array = []
		for row in range(internal_count):
			column_rhs.append(float(a_ib[row][column]))
		var solved := LinearAlgebra.solve_factored(factor, column_rhs)
		if not bool(solved.get("success", false)):
			return _no_safe("UNSAFE_ELIMINATION", {"phase": "AII_INV_AIB", "column": column})
		solved_columns.append(solved["details"]["solution"])
	var solved_rhs := LinearAlgebra.solve_factored(factor, r_i)
	if not bool(solved_rhs.get("success", false)):
		return _no_safe("UNSAFE_ELIMINATION", {"phase": "AII_INV_RI"})
	var aii_inv_ri: Array = solved_rhs["details"]["solution"]

	var schur: Array = []
	for row in range(boundary_count):
		var reduced_row: Array = []
		for column in range(boundary_count):
			var correction := 0.0
			for internal_index in range(internal_count):
				correction += float(a_bi[row][internal_index]) * float(solved_columns[column][internal_index])
			reduced_row.append(float(a_bb[row][column]) - correction)
		schur.append(reduced_row)
	var reduced_rhs: Array = []
	for row in range(boundary_count):
		var correction := 0.0
		for internal_index in range(internal_count):
			correction += float(a_bi[row][internal_index]) * float(aii_inv_ri[internal_index])
		reduced_rhs.append(float(r_b[row]) - correction)

	var matrix_scale := maxf(1.0, LinearAlgebra.max_abs_matrix(matrix))
	var symmetry_error := LinearAlgebra.symmetry_error(schur)
	if bool(policy["require_symmetric"]):
		var source_symmetry_error := LinearAlgebra.symmetry_error(matrix)
		if source_symmetry_error > float(policy["symmetry_tolerance"]) * matrix_scale:
			return _no_safe("UNSAFE_ELIMINATION", {"phase": "SOURCE_RECIPROCITY", "symmetry_error": source_symmetry_error})
		if symmetry_error > float(policy["symmetry_tolerance"]) * maxf(1.0, LinearAlgebra.max_abs_matrix(schur)):
			return _no_safe("UNSAFE_ELIMINATION", {"phase": "REDUCED_RECIPROCITY", "symmetry_error": symmetry_error})

	var passivity_certified := false
	if bool(policy["require_passive_laplacian"]):
		if LinearAlgebra.max_abs_vector(rhs) > float(policy["passivity_tolerance"]) * matrix_scale:
			return _no_safe("UNSAFE_ELIMINATION", {"phase": "PASSIVITY_NONZERO_SOURCE"})
		var source_laplacian := LinearAlgebra.laplacian_certificate(matrix, float(policy["passivity_tolerance"]))
		var reduced_laplacian := LinearAlgebra.laplacian_certificate(schur, float(policy["passivity_tolerance"]))
		if not bool(source_laplacian.get("success", false)) or not bool(reduced_laplacian.get("success", false)):
			return _no_safe("UNSAFE_ELIMINATION", {"phase": "PASSIVITY_CERTIFICATE_ERROR"})
		if not bool(source_laplacian["details"]["certified"]) or not bool(reduced_laplacian["details"]["certified"]):
			return _no_safe("UNSAFE_ELIMINATION", {
				"phase": "PASSIVITY_CERTIFICATE_FAILED",
				"source": source_laplacian["details"],
				"reduced": reduced_laplacian["details"],
			})
		passivity_certified = true

	var reduced_rank := LinearAlgebra.matrix_rank(schur, float(policy["pivot_relative_tolerance"]))
	var nullspace_residual := LinearAlgebra.row_sum_residual(schur)
	var reconstruction_recipe_hash := Utils.canonical_hash({
		"algorithm": "DETERMINISTIC_PARTIAL_PIVOT_LU_V1",
		"source_system_hash": system["system_hash"],
		"boundary_port_ids": system["boundary_port_ids"],
		"pivot_relative_tolerance": policy["pivot_relative_tolerance"],
	})
	var full_work_units: int = 2 * internal_count * internal_count + 4 * internal_count * boundary_count + 2 * boundary_count * boundary_count
	var reduced_work_units: int = 2 * boundary_count * boundary_count
	var descriptor := Descriptor.create(
		String(system["system_hash"]), system["boundary_port_ids"], internal_count,
		schur, reduced_rhs, int(factor_details["rank"]), reduced_rank,
		float(policy["pivot_relative_tolerance"]), float(factor_details["minimum_abs_pivot"]),
		float(factor_details["maximum_abs_pivot"]), symmetry_error, nullspace_residual,
		passivity_certified, reconstruction_recipe_hash, full_work_units, reduced_work_units
	)
	if descriptor.is_empty():
		return Utils.failure("INVALID_EXACT_BOUNDARY_REDUCTION_ASSEMBLY")
	return {
		"success": true,
		"error_code": "",
		"status": REDUCED,
		"reason": "",
		"descriptor": descriptor,
		"diagnostics": {
			"boundary_count": boundary_count,
			"internal_count": internal_count,
			"factor_work_units": int(factor_details["factor_work_units"]),
		},
	}

static func evaluate_full(system: Dictionary, boundary_effort: Array, pivot_relative_tolerance: float) -> Dictionary:
	var checked := LinearSystem.validate(system)
	if not bool(checked.get("success", false)):
		return checked
	var boundary_count: int = int(system["boundary_port_ids"].size())
	var internal_count: int = int(system["internal_variable_ids"].size())
	if boundary_effort.size() != boundary_count:
		return Utils.failure("INVALID_BOUNDARY_EFFORT_SIZE")
	var matrix: Array = system["coefficient_matrix"]
	var rhs: Array = system["rhs"]
	var a_bb := _slice_matrix(matrix, 0, boundary_count, 0, boundary_count)
	var a_bi := _slice_matrix(matrix, 0, boundary_count, boundary_count, boundary_count + internal_count)
	var a_ib := _slice_matrix(matrix, boundary_count, boundary_count + internal_count, 0, boundary_count)
	var a_ii := _slice_matrix(matrix, boundary_count, boundary_count + internal_count, boundary_count, boundary_count + internal_count)
	var internal_rhs: Array = []
	for row in range(internal_count):
		var value := float(rhs[boundary_count + row])
		for column in range(boundary_count):
			value -= float(a_ib[row][column]) * float(boundary_effort[column])
		internal_rhs.append(value)
	var factor := LinearAlgebra.factor_square(a_ii, pivot_relative_tolerance)
	if not bool(factor.get("success", false)):
		return factor
	var solved := LinearAlgebra.solve_factored(factor, internal_rhs)
	if not bool(solved.get("success", false)):
		return solved
	var internal_state: Array = solved["details"]["solution"]
	var boundary_flow: Array = []
	for row in range(boundary_count):
		var value := -float(rhs[row])
		for column in range(boundary_count):
			value += float(a_bb[row][column]) * float(boundary_effort[column])
		for internal_index in range(internal_count):
			value += float(a_bi[row][internal_index]) * float(internal_state[internal_index])
		boundary_flow.append(value)
	return Utils.success({
		"boundary_effort": boundary_effort.duplicate(),
		"boundary_flow": boundary_flow,
		"boundary_power": LinearAlgebra.dot(boundary_effort, boundary_flow),
		"internal_state": internal_state,
	})

static func evaluate_reduced(descriptor: Dictionary, boundary_effort: Array) -> Dictionary:
	var checked := Descriptor.validate(descriptor)
	if not bool(checked.get("success", false)):
		return checked
	if boundary_effort.size() != descriptor["boundary_port_ids"].size():
		return Utils.failure("INVALID_BOUNDARY_EFFORT_SIZE")
	var boundary_flow := LinearAlgebra.matvec(descriptor["schur_matrix"], boundary_effort)
	for index in range(boundary_flow.size()):
		boundary_flow[index] = float(boundary_flow[index]) - float(descriptor["reduced_rhs"][index])
	return Utils.success({
		"boundary_effort": boundary_effort.duplicate(),
		"boundary_flow": boundary_flow,
		"boundary_power": LinearAlgebra.dot(boundary_effort, boundary_flow),
	})

static func _slice_matrix(matrix: Array, row_begin: int, row_end: int, column_begin: int, column_end: int) -> Array:
	var output: Array = []
	for row in range(row_begin, row_end):
		var output_row: Array = []
		for column in range(column_begin, column_end):
			output_row.append(float(matrix[row][column]))
		output.append(output_row)
	return output

static func _no_safe(reason: String, diagnostics: Dictionary = {}) -> Dictionary:
	return {
		"success": true,
		"error_code": "",
		"status": NO_SAFE_BAKE,
		"reason": reason,
		"descriptor": {},
		"diagnostics": diagnostics.duplicate(true),
	}
