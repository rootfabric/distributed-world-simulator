extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_dynamic_rom_descriptor.v1"
const BASIS_METHOD := "PASSIVE_RATIONAL_BLOCK_KRYLOV_R1"
const PASSIVITY_FIELDS: Array[String] = [
	"certificate_kind", "c_orthonormality_error",
	"mass_symmetry_error", "dissipation_symmetry_error",
	"mass_min_cholesky_pivot", "dissipation_min_cholesky_pivot",
	"certified", "certificate_hash",
]
const INTERPOLATION_FIELDS: Array[String] = [
	"certificate_kind", "laplace_shifts", "probe_count",
	"max_abs_boundary_error", "max_relative_boundary_error",
	"certified_tolerance", "certified", "certificate_hash",
]
const FIELDS: Array[String] = [
	"schema", "rom_id", "compiler_version",
	"full_model_hash", "source_binding_checksum", "boundary_contract_hash",
	"full_state_schema_hash", "reduced_state_schema_hash",
	"basis_method", "laplace_shifts", "basis_matrix", "basis_hash",
	"reduced_mass_matrix", "reduced_dissipation_matrix",
	"reduced_input_matrix", "reduced_output_matrix", "port_ids", "port_orientation_signs",
	"full_state_count", "reduced_state_count", "reduction_ratio",
	"passivity_certificate", "interpolation_certificate",
	"descriptor_hash", "checksum",
]

static func create(
	rom_id: String,
	compiler_version: String,
	full_model_hash: String,
	source_binding_checksum: String,
	boundary_contract_hash: String,
	full_state_schema_hash: String,
	reduced_state_schema_hash: String,
	laplace_shifts: Array,
	basis_matrix: Array,
	reduced_mass_matrix: Array,
	reduced_dissipation_matrix: Array,
	reduced_input_matrix: Array,
	reduced_output_matrix: Array,
	port_ids: Array,
	port_orientation_signs: Array,
	full_state_count: int,
	passivity_certificate: Dictionary,
	interpolation_certificate: Dictionary
) -> Dictionary:
	var reduced_state_count := reduced_mass_matrix.size()
	var value: Dictionary = {
		"schema": SCHEMA,
		"rom_id": rom_id,
		"compiler_version": compiler_version,
		"full_model_hash": full_model_hash,
		"source_binding_checksum": source_binding_checksum,
		"boundary_contract_hash": boundary_contract_hash,
		"full_state_schema_hash": full_state_schema_hash,
		"reduced_state_schema_hash": reduced_state_schema_hash,
		"basis_method": BASIS_METHOD,
		"laplace_shifts": _float_array(laplace_shifts),
		"basis_matrix": _float_matrix(basis_matrix),
		"basis_hash": Utils.canonical_hash(basis_matrix),
		"reduced_mass_matrix": _float_matrix(reduced_mass_matrix),
		"reduced_dissipation_matrix": _float_matrix(reduced_dissipation_matrix),
		"reduced_input_matrix": _float_matrix(reduced_input_matrix),
		"reduced_output_matrix": _float_matrix(reduced_output_matrix),
		"port_ids": Utils.sorted_strings(port_ids),
		"port_orientation_signs": _float_array(port_orientation_signs),
		"full_state_count": full_state_count,
		"reduced_state_count": reduced_state_count,
		"reduction_ratio": float(full_state_count) / float(reduced_state_count),
		"passivity_certificate": passivity_certificate.duplicate(true),
		"interpolation_certificate": interpolation_certificate.duplicate(true),
		"descriptor_hash": "",
		"checksum": "",
	}
	value["descriptor_hash"] = Utils.canonical_hash(_descriptor_payload(value))
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_DYNAMIC_ROM_DESCRIPTOR_SCHEMA")
	if not Utils.is_canonical_id(value.get("rom_id"), 2):
		return Utils.failure("INVALID_DYNAMIC_ROM_ID")
	if typeof(value.get("compiler_version")) != TYPE_STRING or String(value["compiler_version"]).strip_edges().is_empty():
		return Utils.failure("INVALID_DYNAMIC_ROM_COMPILER_VERSION")
	for field in [
		"full_model_hash", "source_binding_checksum", "boundary_contract_hash",
		"full_state_schema_hash", "reduced_state_schema_hash", "basis_hash",
	]:
		if not Utils.is_lower_hex_64(value.get(field)):
			return Utils.failure("INVALID_DYNAMIC_ROM_HASH", {"field": field})
	if value.get("basis_method") != BASIS_METHOD:
		return Utils.failure("UNSUPPORTED_DYNAMIC_ROM_BASIS_METHOD")
	checked = _validate_shifts(value.get("laplace_shifts"))
	if not bool(checked.get("success", false)):
		return checked
	if not Utils.is_json_integer(value.get("full_state_count")) or int(value["full_state_count"]) < 2:
		return Utils.failure("INVALID_DYNAMIC_ROM_FULL_STATE_COUNT")
	if not Utils.is_json_integer(value.get("reduced_state_count")) or int(value["reduced_state_count"]) < 1:
		return Utils.failure("INVALID_DYNAMIC_ROM_REDUCED_STATE_COUNT")
	var n := int(value["full_state_count"])
	var r := int(value["reduced_state_count"])
	if r > 24:
		return Utils.failure("DYNAMIC_ROM_REDUCED_STATE_LIMIT_EXCEEDED")
	if n < 512:
		return Utils.failure("DYNAMIC_ROM_FULL_STATE_REFERENCE_TOO_SMALL")
	if not Utils.is_finite_number(value.get("reduction_ratio")):
		return Utils.failure("INVALID_DYNAMIC_ROM_REDUCTION_RATIO")
	if absf(float(value["reduction_ratio"]) - float(n) / float(r)) > 1.0e-12:
		return Utils.failure("DYNAMIC_ROM_REDUCTION_RATIO_MISMATCH")
	if float(value["reduction_ratio"]) < 20.0:
		return Utils.failure("DYNAMIC_ROM_REDUCTION_BELOW_20X")
	checked = _validate_matrix(value.get("basis_matrix"), n, r, "BASIS")
	if not bool(checked.get("success", false)):
		return checked
	if String(value["basis_hash"]) != Utils.canonical_hash(value["basis_matrix"]):
		return Utils.failure("DYNAMIC_ROM_BASIS_HASH_MISMATCH")
	checked = _validate_matrix(value.get("reduced_mass_matrix"), r, r, "MASS")
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_matrix(value.get("reduced_dissipation_matrix"), r, r, "DISSIPATION")
	if not bool(checked.get("success", false)):
		return checked
	if typeof(value.get("port_ids")) != TYPE_ARRAY:
		return Utils.failure("INVALID_DYNAMIC_ROM_PORT_IDS")
	checked = Utils.validate_sorted_unique_strings(value["port_ids"], false)
	if not bool(checked.get("success", false)):
		return checked
	var p: int = int(value["port_ids"].size())
	if typeof(value.get("port_orientation_signs")) != TYPE_ARRAY or value["port_orientation_signs"].size() != p:
		return Utils.failure("INVALID_DYNAMIC_ROM_PORT_ORIENTATION_SIGNS")
	for index in range(p):
		if not Utils.is_finite_number(value["port_orientation_signs"][index]) or absf(absf(float(value["port_orientation_signs"][index])) - 1.0) > 1.0e-12:
			return Utils.failure("INVALID_DYNAMIC_ROM_PORT_ORIENTATION_SIGN", {"index": index})
	checked = _validate_matrix(value.get("reduced_input_matrix"), r, p, "INPUT")
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_matrix(value.get("reduced_output_matrix"), p, r, "OUTPUT")
	if not bool(checked.get("success", false)):
		return checked
	if typeof(value.get("passivity_certificate")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_DYNAMIC_ROM_PASSIVITY_CERTIFICATE")
	checked = Utils.validate_exact_fields(value["passivity_certificate"], PASSIVITY_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if not bool(value["passivity_certificate"].get("certified", false)):
		return Utils.failure("DYNAMIC_ROM_PASSIVITY_NOT_CERTIFIED")
	if String(value["passivity_certificate"].get("certificate_hash", "")) != Utils.canonical_hash(_without_hash(value["passivity_certificate"])):
		return Utils.failure("DYNAMIC_ROM_PASSIVITY_CERTIFICATE_HASH_MISMATCH")
	if typeof(value.get("interpolation_certificate")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_DYNAMIC_ROM_INTERPOLATION_CERTIFICATE")
	checked = Utils.validate_exact_fields(value["interpolation_certificate"], INTERPOLATION_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if not bool(value["interpolation_certificate"].get("certified", false)):
		return Utils.failure("DYNAMIC_ROM_INTERPOLATION_NOT_CERTIFIED")
	if value["interpolation_certificate"].get("laplace_shifts") != value["laplace_shifts"]:
		return Utils.failure("DYNAMIC_ROM_INTERPOLATION_SHIFT_MISMATCH")
	if String(value["interpolation_certificate"].get("certificate_hash", "")) != Utils.canonical_hash(_without_hash(value["interpolation_certificate"])):
		return Utils.failure("DYNAMIC_ROM_INTERPOLATION_CERTIFICATE_HASH_MISMATCH")
	if not Utils.is_lower_hex_64(value.get("descriptor_hash")):
		return Utils.failure("INVALID_DYNAMIC_ROM_DESCRIPTOR_HASH")
	if String(value["descriptor_hash"]) != Utils.canonical_hash(_descriptor_payload(value)):
		return Utils.failure("DYNAMIC_ROM_DESCRIPTOR_HASH_MISMATCH")
	return Utils.validate_checksum(value)

static func _validate_shifts(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.is_empty():
		return Utils.failure("INVALID_DYNAMIC_ROM_LAPLACE_SHIFTS")
	var previous := -INF
	for index in range(value.size()):
		if not Utils.is_non_negative_number(value[index]):
			return Utils.failure("INVALID_DYNAMIC_ROM_LAPLACE_SHIFT", {"index": index})
		var current := float(value[index])
		if index > 0 and current <= previous:
			return Utils.failure("DYNAMIC_ROM_LAPLACE_SHIFTS_NOT_SORTED_UNIQUE")
		previous = current
	return Utils.success()

static func _validate_matrix(value, rows: int, columns: int, kind: String) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.size() != rows:
		return Utils.failure("INVALID_DYNAMIC_ROM_%s_MATRIX" % kind)
	for row_index in range(rows):
		if typeof(value[row_index]) != TYPE_ARRAY or value[row_index].size() != columns:
			return Utils.failure("INVALID_DYNAMIC_ROM_%s_MATRIX" % kind, {"row": row_index})
		for column_index in range(columns):
			if not Utils.is_finite_number(value[row_index][column_index]):
				return Utils.failure("NONFINITE_DYNAMIC_ROM_%s_MATRIX" % kind, {"row": row_index, "column": column_index})
	return Utils.success()

static func _descriptor_payload(value: Dictionary) -> Dictionary:
	var payload := value.duplicate(true)
	payload.erase("descriptor_hash")
	payload.erase("checksum")
	return payload

static func _without_hash(value: Dictionary) -> Dictionary:
	var payload := value.duplicate(true)
	payload.erase("certificate_hash")
	return payload

static func _float_array(value: Array) -> Array:
	var output: Array = []
	for raw in value:
		output.append(float(raw))
	return output

static func _float_matrix(value: Array) -> Array:
	var output: Array = []
	for raw_row in value:
		var row: Array = []
		for raw in raw_row:
			row.append(float(raw))
		output.append(row)
	return output
