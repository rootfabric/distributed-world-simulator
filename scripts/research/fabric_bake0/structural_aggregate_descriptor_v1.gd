extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_structural_aggregate_descriptor.v1"
const FIELDS: Array[String] = [
	"schema", "descriptor_id", "source_frontier_hash", "construct_id", "part_count", "bond_count",
	"region_count", "aggregate_frame", "total_mass", "center_of_mass", "inertia_tensor_body",
	"boundary_anchors", "support_envelope", "full_state_schema_hash", "reduced_state_schema_hash",
	"reconstruction_mapping_hash", "full_state_dof", "reduced_state_dof", "state_reduction_ratio", "checksum",
]
const FRAME_FIELDS: Array[String] = ["origin_policy", "orientation_policy"]
const ANCHOR_FIELDS: Array[String] = [
	"anchor_id", "part_id", "position_from_com", "orientation_from_aggregate", "linear_velocity_jacobian_body",
]
const SUPPORT_FIELDS: Array[String] = ["kind", "points"]
const SUPPORT_POINT_FIELDS: Array[String] = ["point_id", "part_id", "point_from_com"]
const SYMMETRY_TOLERANCE := 1.0e-10

static func create(
	descriptor_id: String, source_frontier_hash: String, construct_id: String,
	part_count: int, bond_count: int, region_count: int, total_mass: float,
	center_of_mass: Array, inertia_tensor_body: Array, boundary_anchors: Array,
	support_envelope: Dictionary, full_state_schema_hash: String, reduced_state_schema_hash: String,
	reconstruction_mapping_hash: String
) -> Dictionary:
	var anchors := Utils.sorted_dicts(boundary_anchors, "anchor_id")
	var support := support_envelope.duplicate(true)
	if typeof(support.get("points")) == TYPE_ARRAY:
		support["points"] = Utils.sorted_dicts(support["points"], "point_id")
	var value: Dictionary = {
		"schema": SCHEMA,
		"descriptor_id": descriptor_id,
		"source_frontier_hash": source_frontier_hash,
		"construct_id": construct_id,
		"part_count": part_count,
		"bond_count": bond_count,
		"region_count": region_count,
		"aggregate_frame": {"origin_policy": "CENTER_OF_MASS", "orientation_policy": "CONSTRUCTION_FRAME"},
		"total_mass": total_mass,
		"center_of_mass": center_of_mass.duplicate(),
		"inertia_tensor_body": inertia_tensor_body.duplicate(true),
		"boundary_anchors": anchors,
		"support_envelope": support,
		"full_state_schema_hash": full_state_schema_hash,
		"reduced_state_schema_hash": reduced_state_schema_hash,
		"reconstruction_mapping_hash": reconstruction_mapping_hash,
		"full_state_dof": part_count * 13,
		"reduced_state_dof": 13,
		"state_reduction_ratio": float(part_count),
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_STRUCTURAL_AGGREGATE_DESCRIPTOR_SCHEMA")
	for field in ["descriptor_id", "construct_id"]:
		if not Utils.is_canonical_id(value.get(field), 2):
			return Utils.failure("INVALID_STRUCTURAL_AGGREGATE_ID", {"field": field})
	for field in ["source_frontier_hash", "full_state_schema_hash", "reduced_state_schema_hash", "reconstruction_mapping_hash"]:
		if not Utils.is_lower_hex_64(value.get(field)):
			return Utils.failure("INVALID_STRUCTURAL_AGGREGATE_HASH", {"field": field})
	for field in ["part_count", "bond_count", "region_count", "full_state_dof", "reduced_state_dof"]:
		if not Utils.is_json_integer(value.get(field)) or int(value[field]) < 1:
			return Utils.failure("INVALID_STRUCTURAL_AGGREGATE_COUNT", {"field": field})
	if int(value["full_state_dof"]) != int(value["part_count"]) * 13 or int(value["reduced_state_dof"]) != 13:
		return Utils.failure("INVALID_STRUCTURAL_STATE_DOF")
	if not Utils.is_positive_number(value.get("state_reduction_ratio")) or absf(float(value["state_reduction_ratio"]) - float(value["part_count"])) > 1.0e-12:
		return Utils.failure("INVALID_STRUCTURAL_STATE_REDUCTION_RATIO")
	if not Utils.is_positive_number(value.get("total_mass")):
		return Utils.failure("INVALID_STRUCTURAL_TOTAL_MASS")
	checked = _validate_vec3(value.get("center_of_mass"))
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_spd_matrix3(value.get("inertia_tensor_body"))
	if not bool(checked.get("success", false)):
		return checked
	if typeof(value.get("aggregate_frame")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_STRUCTURAL_AGGREGATE_FRAME")
	checked = Utils.validate_exact_fields(value["aggregate_frame"], FRAME_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if String(value["aggregate_frame"]["origin_policy"]) != "CENTER_OF_MASS" or String(value["aggregate_frame"]["orientation_policy"]) != "CONSTRUCTION_FRAME":
		return Utils.failure("UNSUPPORTED_STRUCTURAL_AGGREGATE_FRAME")
	if typeof(value.get("boundary_anchors")) != TYPE_ARRAY or value["boundary_anchors"].is_empty():
		return Utils.failure("INVALID_STRUCTURAL_BOUNDARY_ANCHORS")
	var previous_anchor := ""
	for index in range(value["boundary_anchors"].size()):
		var raw = value["boundary_anchors"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_STRUCTURAL_BOUNDARY_ANCHOR", {"index": index})
		var anchor: Dictionary = raw
		checked = Utils.validate_exact_fields(anchor, ANCHOR_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		if not Utils.is_canonical_id(anchor.get("anchor_id"), 2) or not Utils.is_canonical_id(anchor.get("part_id"), 2):
			return Utils.failure("INVALID_STRUCTURAL_BOUNDARY_ANCHOR_ID", {"index": index})
		checked = _validate_vec3(anchor.get("position_from_com"))
		if not bool(checked.get("success", false)):
			return checked
		checked = _validate_quat(anchor.get("orientation_from_aggregate"))
		if not bool(checked.get("success", false)):
			return checked
		checked = _validate_matrix(anchor.get("linear_velocity_jacobian_body"), 3, 6)
		if not bool(checked.get("success", false)):
			return checked
		var current := String(anchor["anchor_id"])
		if index > 0 and current <= previous_anchor:
			return Utils.failure("STRUCTURAL_BOUNDARY_ANCHORS_NOT_SORTED_UNIQUE", {"index": index})
		previous_anchor = current
	if typeof(value.get("support_envelope")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_STRUCTURAL_SUPPORT_ENVELOPE")
	checked = Utils.validate_exact_fields(value["support_envelope"], SUPPORT_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if String(value["support_envelope"]["kind"]) != "FINITE_SUPPORT_SET":
		return Utils.failure("UNSUPPORTED_STRUCTURAL_SUPPORT_ENVELOPE")
	if typeof(value["support_envelope"].get("points")) != TYPE_ARRAY or value["support_envelope"]["points"].is_empty():
		return Utils.failure("EMPTY_STRUCTURAL_SUPPORT_ENVELOPE")
	var previous_point := ""
	for index in range(value["support_envelope"]["points"].size()):
		var raw = value["support_envelope"]["points"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_STRUCTURAL_SUPPORT_POINT", {"index": index})
		var point: Dictionary = raw
		checked = Utils.validate_exact_fields(point, SUPPORT_POINT_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		if typeof(point.get("point_id")) != TYPE_STRING or String(point["point_id"]).is_empty() or not Utils.is_canonical_id(point.get("part_id"), 2):
			return Utils.failure("INVALID_STRUCTURAL_SUPPORT_POINT_ID", {"index": index})
		checked = _validate_vec3(point.get("point_from_com"))
		if not bool(checked.get("success", false)):
			return checked
		var current := String(point["point_id"])
		if index > 0 and current <= previous_point:
			return Utils.failure("STRUCTURAL_SUPPORT_POINTS_NOT_SORTED_UNIQUE", {"index": index})
		previous_point = current
	return Utils.validate_checksum(value)

static func _validate_vec3(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return Utils.failure("INVALID_STRUCTURAL_VECTOR3")
	for component in value:
		if not Utils.is_finite_number(component):
			return Utils.failure("INVALID_STRUCTURAL_VECTOR3")
	return Utils.success()

static func _validate_quat(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.size() != 4:
		return Utils.failure("INVALID_STRUCTURAL_QUATERNION")
	var norm_sq := 0.0
	for component in value:
		if not Utils.is_finite_number(component):
			return Utils.failure("INVALID_STRUCTURAL_QUATERNION")
		norm_sq += float(component) * float(component)
	if absf(norm_sq - 1.0) > 1.0e-9:
		return Utils.failure("NON_UNIT_STRUCTURAL_QUATERNION")
	return Utils.success()

static func _validate_matrix(value, rows: int, columns: int) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.size() != rows:
		return Utils.failure("INVALID_STRUCTURAL_MATRIX")
	for row in value:
		if typeof(row) != TYPE_ARRAY or row.size() != columns:
			return Utils.failure("INVALID_STRUCTURAL_MATRIX")
		for component in row:
			if not Utils.is_finite_number(component):
				return Utils.failure("INVALID_STRUCTURAL_MATRIX")
	return Utils.success()

static func _validate_spd_matrix3(value) -> Dictionary:
	var checked := _validate_matrix(value, 3, 3)
	if not bool(checked.get("success", false)):
		return checked
	for row in range(3):
		for column in range(3):
			if absf(float(value[row][column]) - float(value[column][row])) > SYMMETRY_TOLERANCE:
				return Utils.failure("NONSYMMETRIC_STRUCTURAL_INERTIA")
	var a := float(value[0][0])
	var det2 := a * float(value[1][1]) - float(value[0][1]) * float(value[1][0])
	var det3 := (
		float(value[0][0]) * (float(value[1][1]) * float(value[2][2]) - float(value[1][2]) * float(value[2][1]))
		- float(value[0][1]) * (float(value[1][0]) * float(value[2][2]) - float(value[1][2]) * float(value[2][0]))
		+ float(value[0][2]) * (float(value[1][0]) * float(value[2][1]) - float(value[1][1]) * float(value[2][0]))
	)
	if a <= 0.0 or det2 <= 0.0 or det3 <= 0.0:
		return Utils.failure("NONPOSITIVE_STRUCTURAL_INERTIA")
	return Utils.success()
