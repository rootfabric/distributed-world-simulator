extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_linear_boundary_system.v1"
const FIELDS: Array[String] = [
	"schema", "system_id", "boundary_port_ids", "internal_variable_ids",
	"coefficient_matrix", "rhs", "system_hash", "checksum",
]

static func create(
	system_id: String, boundary_port_ids: Array, internal_variable_ids: Array,
	coefficient_matrix: Array, rhs: Array
) -> Dictionary:
	var boundary_count: int = boundary_port_ids.size()
	var internal_count: int = internal_variable_ids.size()
	var total: int = boundary_count + internal_count
	if coefficient_matrix.size() != total or rhs.size() != total:
		return {}

	var boundary_entries: Array = []
	for index in range(boundary_count):
		boundary_entries.append({"id": boundary_port_ids[index], "index": index})
	boundary_entries.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))

	var internal_entries: Array = []
	for index in range(internal_count):
		internal_entries.append({"id": internal_variable_ids[index], "index": boundary_count + index})
	internal_entries.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))

	var permutation: Array = []
	var ordered_boundary_ids: Array = []
	var ordered_internal_ids: Array = []
	for entry in boundary_entries:
		ordered_boundary_ids.append(entry["id"])
		permutation.append(entry["index"])
	for entry in internal_entries:
		ordered_internal_ids.append(entry["id"])
		permutation.append(entry["index"])

	var ordered_matrix: Array = []
	for row_index in permutation:
		if typeof(coefficient_matrix[row_index]) != TYPE_ARRAY or coefficient_matrix[row_index].size() != total:
			return {}
		var row: Array = []
		for column_index in permutation:
			row.append(coefficient_matrix[row_index][column_index])
		ordered_matrix.append(row)
	var ordered_rhs: Array = []
	for index in permutation:
		ordered_rhs.append(rhs[index])

	var identity_payload := {
		"system_id": system_id,
		"boundary_port_ids": ordered_boundary_ids,
		"internal_variable_ids": ordered_internal_ids,
		"coefficient_matrix": ordered_matrix,
		"rhs": ordered_rhs,
	}
	var value: Dictionary = {
		"schema": SCHEMA,
		"system_id": system_id,
		"boundary_port_ids": ordered_boundary_ids,
		"internal_variable_ids": ordered_internal_ids,
		"coefficient_matrix": ordered_matrix,
		"rhs": ordered_rhs,
		"system_hash": Utils.canonical_hash(identity_payload),
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_LINEAR_BOUNDARY_SYSTEM_SCHEMA")
	if not Utils.is_canonical_id(value.get("system_id"), 2):
		return Utils.failure("INVALID_LINEAR_BOUNDARY_SYSTEM_ID")
	checked = Utils.validate_sorted_unique_strings(value.get("boundary_port_ids"), false)
	if not bool(checked.get("success", false)):
		return Utils.failure("INVALID_LINEAR_BOUNDARY_PORT_IDS")
	checked = Utils.validate_sorted_unique_strings(value.get("internal_variable_ids"), false)
	if not bool(checked.get("success", false)):
		return Utils.failure("INVALID_LINEAR_INTERNAL_VARIABLE_IDS")
	for port_id in value["boundary_port_ids"]:
		if not Utils.is_canonical_id(port_id, 2):
			return Utils.failure("INVALID_LINEAR_BOUNDARY_PORT_ID")
	for variable_id in value["internal_variable_ids"]:
		if not Utils.is_canonical_id(variable_id, 2):
			return Utils.failure("INVALID_LINEAR_INTERNAL_VARIABLE_ID")
		if value["boundary_port_ids"].has(variable_id):
			return Utils.failure("LINEAR_BOUNDARY_INTERNAL_ID_OVERLAP")
	var total: int = int(value["boundary_port_ids"].size()) + int(value["internal_variable_ids"].size())
	if typeof(value.get("coefficient_matrix")) != TYPE_ARRAY or value["coefficient_matrix"].size() != total:
		return Utils.failure("INVALID_LINEAR_COEFFICIENT_MATRIX_SIZE")
	for row_index in range(total):
		var row = value["coefficient_matrix"][row_index]
		if typeof(row) != TYPE_ARRAY or row.size() != total:
			return Utils.failure("INVALID_LINEAR_COEFFICIENT_MATRIX_ROW", {"row": row_index})
		for column_index in range(total):
			if not Utils.is_finite_number(row[column_index]):
				return Utils.failure("INVALID_LINEAR_COEFFICIENT", {"row": row_index, "column": column_index})
	if typeof(value.get("rhs")) != TYPE_ARRAY or value["rhs"].size() != total:
		return Utils.failure("INVALID_LINEAR_RHS_SIZE")
	for index in range(total):
		if not Utils.is_finite_number(value["rhs"][index]):
			return Utils.failure("INVALID_LINEAR_RHS", {"index": index})
	if not Utils.is_lower_hex_64(value.get("system_hash")):
		return Utils.failure("INVALID_LINEAR_BOUNDARY_SYSTEM_HASH")
	var identity_payload := {
		"system_id": value["system_id"],
		"boundary_port_ids": value["boundary_port_ids"],
		"internal_variable_ids": value["internal_variable_ids"],
		"coefficient_matrix": value["coefficient_matrix"],
		"rhs": value["rhs"],
	}
	if String(value["system_hash"]) != Utils.canonical_hash(identity_payload):
		return Utils.failure("LINEAR_BOUNDARY_SYSTEM_HASH_MISMATCH")
	return Utils.validate_checksum(value)
