extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_exact_boundary_reduction.v1"
const FIELDS: Array[String] = [
	"schema", "source_system_hash", "boundary_port_ids", "internal_variable_count",
	"full_equation_count", "reduced_equation_count", "schur_matrix", "reduced_rhs",
	"internal_rank", "reduced_rank", "pivot_relative_tolerance", "minimum_abs_pivot",
	"maximum_abs_pivot", "symmetry_error", "nullspace_residual", "passivity_certified",
	"reconstruction_recipe_hash", "runtime_full_work_units", "runtime_reduced_work_units",
	"runtime_work_ratio", "checksum",
]

static func create(
	source_system_hash: String, boundary_port_ids: Array, internal_variable_count: int,
	schur_matrix: Array, reduced_rhs: Array, internal_rank: int, reduced_rank: int,
	pivot_relative_tolerance: float, minimum_abs_pivot: float, maximum_abs_pivot: float,
	symmetry_error: float, nullspace_residual: float, passivity_certified: bool,
	reconstruction_recipe_hash: String, runtime_full_work_units: int,
	runtime_reduced_work_units: int
) -> Dictionary:
	var full_equation_count := boundary_port_ids.size() + internal_variable_count
	var reduced_equation_count := boundary_port_ids.size()
	var runtime_work_ratio := float(runtime_full_work_units) / float(runtime_reduced_work_units) if runtime_reduced_work_units > 0 else INF
	var value: Dictionary = {
		"schema": SCHEMA,
		"source_system_hash": source_system_hash,
		"boundary_port_ids": boundary_port_ids.duplicate(),
		"internal_variable_count": internal_variable_count,
		"full_equation_count": full_equation_count,
		"reduced_equation_count": reduced_equation_count,
		"schur_matrix": schur_matrix.duplicate(true),
		"reduced_rhs": reduced_rhs.duplicate(),
		"internal_rank": internal_rank,
		"reduced_rank": reduced_rank,
		"pivot_relative_tolerance": pivot_relative_tolerance,
		"minimum_abs_pivot": minimum_abs_pivot,
		"maximum_abs_pivot": maximum_abs_pivot,
		"symmetry_error": symmetry_error,
		"nullspace_residual": nullspace_residual,
		"passivity_certified": passivity_certified,
		"reconstruction_recipe_hash": reconstruction_recipe_hash,
		"runtime_full_work_units": runtime_full_work_units,
		"runtime_reduced_work_units": runtime_reduced_work_units,
		"runtime_work_ratio": runtime_work_ratio,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_EXACT_BOUNDARY_REDUCTION_SCHEMA")
	for field in ["source_system_hash", "reconstruction_recipe_hash"]:
		if not Utils.is_lower_hex_64(value.get(field)):
			return Utils.failure("INVALID_EXACT_BOUNDARY_REDUCTION_HASH", {"field": field})
	checked = Utils.validate_sorted_unique_strings(value.get("boundary_port_ids"), false)
	if not bool(checked.get("success", false)):
		return Utils.failure("INVALID_EXACT_BOUNDARY_REDUCTION_PORTS")
	var boundary_count: int = int(value["boundary_port_ids"].size())
	for port_id in value["boundary_port_ids"]:
		if not Utils.is_canonical_id(port_id, 2):
			return Utils.failure("INVALID_EXACT_BOUNDARY_REDUCTION_PORT")
	for field in ["internal_variable_count", "full_equation_count", "reduced_equation_count", "internal_rank", "reduced_rank", "runtime_full_work_units", "runtime_reduced_work_units"]:
		if not Utils.is_json_integer(value.get(field)) or int(value[field]) < 0:
			return Utils.failure("INVALID_EXACT_BOUNDARY_REDUCTION_INTEGER", {"field": field})
	if int(value["internal_variable_count"]) < 1:
		return Utils.failure("INVALID_EXACT_BOUNDARY_INTERNAL_COUNT")
	if int(value["full_equation_count"]) != boundary_count + int(value["internal_variable_count"]):
		return Utils.failure("EXACT_BOUNDARY_FULL_EQUATION_COUNT_MISMATCH")
	if int(value["reduced_equation_count"]) != boundary_count:
		return Utils.failure("EXACT_BOUNDARY_REDUCED_EQUATION_COUNT_MISMATCH")
	if int(value["internal_rank"]) > int(value["internal_variable_count"]) or int(value["reduced_rank"]) > boundary_count:
		return Utils.failure("INVALID_EXACT_BOUNDARY_RANK")
	if typeof(value.get("schur_matrix")) != TYPE_ARRAY or value["schur_matrix"].size() != boundary_count:
		return Utils.failure("INVALID_EXACT_BOUNDARY_SCHUR_MATRIX")
	for row in value["schur_matrix"]:
		if typeof(row) != TYPE_ARRAY or row.size() != boundary_count:
			return Utils.failure("INVALID_EXACT_BOUNDARY_SCHUR_MATRIX")
		for coefficient in row:
			if not Utils.is_finite_number(coefficient):
				return Utils.failure("INVALID_EXACT_BOUNDARY_SCHUR_COEFFICIENT")
	if typeof(value.get("reduced_rhs")) != TYPE_ARRAY or value["reduced_rhs"].size() != boundary_count:
		return Utils.failure("INVALID_EXACT_BOUNDARY_RHS")
	for coefficient in value["reduced_rhs"]:
		if not Utils.is_finite_number(coefficient):
			return Utils.failure("INVALID_EXACT_BOUNDARY_RHS")
	for field in ["pivot_relative_tolerance", "minimum_abs_pivot", "maximum_abs_pivot", "symmetry_error", "nullspace_residual", "runtime_work_ratio"]:
		if not Utils.is_non_negative_number(value.get(field)):
			return Utils.failure("INVALID_EXACT_BOUNDARY_REDUCTION_NUMBER", {"field": field})
	if float(value["pivot_relative_tolerance"]) <= 0.0 or float(value["minimum_abs_pivot"]) <= 0.0 or float(value["maximum_abs_pivot"]) < float(value["minimum_abs_pivot"]):
		return Utils.failure("INVALID_EXACT_BOUNDARY_PIVOT_EVIDENCE")
	if typeof(value.get("passivity_certified")) != TYPE_BOOL:
		return Utils.failure("INVALID_EXACT_BOUNDARY_PASSIVITY_FLAG")
	if int(value["runtime_full_work_units"]) <= 0 or int(value["runtime_reduced_work_units"]) <= 0 or float(value["runtime_work_ratio"]) <= 1.0:
		return Utils.failure("INSUFFICIENT_EXACT_BOUNDARY_WORK_REDUCTION")
	return Utils.validate_checksum(value)
