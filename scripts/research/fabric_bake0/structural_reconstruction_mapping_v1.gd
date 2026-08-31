extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_structural_reconstruction_mapping.v1"
const FIELDS: Array[String] = [
	"schema", "mapping_id", "source_frontier_hash", "construct_id", "reference_part_id",
	"full_state_schema_hash", "reduced_state_schema_hash", "part_mappings", "region_mappings",
	"reconstruction_version", "checksum",
]
const PART_FIELDS: Array[String] = [
	"part_id", "region_id", "position_from_com", "orientation_from_aggregate",
]
const REGION_FIELDS: Array[String] = ["region_id", "part_ids"]
const STATE_FIELDS: Array[String] = ["position", "orientation", "linear_velocity", "angular_velocity"]
const UNIT_TOLERANCE := 1.0e-9

static func create(
	mapping_id: String, source_frontier_hash: String, construct_id: String,
	reference_part_id: String, full_state_schema_hash: String, reduced_state_schema_hash: String,
	part_mappings: Array, region_mappings: Array, reconstruction_version: String
) -> Dictionary:
	var parts := Utils.sorted_dicts(part_mappings, "part_id")
	var regions := Utils.sorted_dicts(region_mappings, "region_id")
	for index in range(regions.size()):
		if typeof(regions[index]) == TYPE_DICTIONARY:
			var region: Dictionary = regions[index]
			if typeof(region.get("part_ids")) == TYPE_ARRAY:
				region["part_ids"] = Utils.sorted_strings(region["part_ids"])
	var value: Dictionary = {
		"schema": SCHEMA,
		"mapping_id": mapping_id,
		"source_frontier_hash": source_frontier_hash,
		"construct_id": construct_id,
		"reference_part_id": reference_part_id,
		"full_state_schema_hash": full_state_schema_hash,
		"reduced_state_schema_hash": reduced_state_schema_hash,
		"part_mappings": parts,
		"region_mappings": regions,
		"reconstruction_version": reconstruction_version,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_STRUCTURAL_RECONSTRUCTION_MAPPING_SCHEMA")
	for field in ["mapping_id", "construct_id", "reference_part_id"]:
		if not Utils.is_canonical_id(value.get(field), 2):
			return Utils.failure("INVALID_STRUCTURAL_RECONSTRUCTION_ID", {"field": field})
	for field in ["source_frontier_hash", "full_state_schema_hash", "reduced_state_schema_hash"]:
		if not Utils.is_lower_hex_64(value.get(field)):
			return Utils.failure("INVALID_STRUCTURAL_RECONSTRUCTION_HASH", {"field": field})
	if typeof(value.get("reconstruction_version")) != TYPE_STRING or String(value["reconstruction_version"]).strip_edges().is_empty():
		return Utils.failure("INVALID_STRUCTURAL_RECONSTRUCTION_VERSION")
	if typeof(value.get("part_mappings")) != TYPE_ARRAY or value["part_mappings"].is_empty():
		return Utils.failure("INVALID_STRUCTURAL_PART_MAPPINGS")
	if typeof(value.get("region_mappings")) != TYPE_ARRAY or value["region_mappings"].is_empty():
		return Utils.failure("INVALID_STRUCTURAL_REGION_MAPPINGS")
	var part_ids: Array = []
	var previous_part := ""
	for index in range(value["part_mappings"].size()):
		var raw = value["part_mappings"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_STRUCTURAL_PART_MAPPING", {"index": index})
		var part: Dictionary = raw
		checked = Utils.validate_exact_fields(part, PART_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		if not Utils.is_canonical_id(part.get("part_id"), 2):
			return Utils.failure("INVALID_STRUCTURAL_PART_ID", {"index": index})
		if not Utils.is_canonical_id(part.get("region_id"), 2):
			return Utils.failure("INVALID_STRUCTURAL_REGION_ID", {"index": index})
		checked = _validate_vec3(part.get("position_from_com"))
		if not bool(checked.get("success", false)):
			return checked
		checked = _validate_quat(part.get("orientation_from_aggregate"))
		if not bool(checked.get("success", false)):
			return checked
		var current := String(part["part_id"])
		if index > 0 and current <= previous_part:
			return Utils.failure("STRUCTURAL_PART_MAPPINGS_NOT_SORTED_UNIQUE", {"index": index})
		previous_part = current
		part_ids.append(current)
	if not part_ids.has(String(value["reference_part_id"])):
		return Utils.failure("STRUCTURAL_REFERENCE_PART_NOT_MAPPED")
	var covered: Dictionary = {}
	var previous_region := ""
	for index in range(value["region_mappings"].size()):
		var raw = value["region_mappings"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_STRUCTURAL_REGION_MAPPING", {"index": index})
		var region: Dictionary = raw
		checked = Utils.validate_exact_fields(region, REGION_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		if not Utils.is_canonical_id(region.get("region_id"), 2):
			return Utils.failure("INVALID_STRUCTURAL_REGION_ID", {"index": index})
		checked = Utils.validate_sorted_unique_strings(region.get("part_ids"), false)
		if not bool(checked.get("success", false)):
			return checked
		var current := String(region["region_id"])
		if index > 0 and current <= previous_region:
			return Utils.failure("STRUCTURAL_REGIONS_NOT_SORTED_UNIQUE", {"index": index})
		previous_region = current
		for part_id in region["part_ids"]:
			if not part_ids.has(part_id):
				return Utils.failure("STRUCTURAL_REGION_PART_NOT_MAPPED", {"part_id": part_id})
			if covered.has(String(part_id)):
				return Utils.failure("STRUCTURAL_PART_MAPPED_TO_MULTIPLE_REGIONS", {"part_id": part_id})
			covered[String(part_id)] = current
	for part in value["part_mappings"]:
		var part_id := String(part["part_id"])
		if not covered.has(part_id):
			return Utils.failure("STRUCTURAL_PART_NOT_REGION_MAPPED", {"part_id": part_id})
		if String(covered[part_id]) != String(part["region_id"]):
			return Utils.failure("STRUCTURAL_PART_REGION_MISMATCH", {"part_id": part_id})
	return Utils.validate_checksum(value)

static func reconstruct(mapping: Dictionary, reduced_state: Dictionary) -> Dictionary:
	var checked := validate(mapping)
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_state(reduced_state)
	if not bool(checked.get("success", false)):
		return checked
	var com := _vec3(reduced_state["position"])
	var aggregate_q := _quat(reduced_state["orientation"])
	var linear_velocity := _vec3(reduced_state["linear_velocity"])
	var angular_velocity := _vec3(reduced_state["angular_velocity"])
	var states: Dictionary = {}
	for part in mapping["part_mappings"]:
		var local_r := _vec3(part["position_from_com"])
		var world_r := aggregate_q * local_r
		var part_q := _canonical_quat(aggregate_q * _quat(part["orientation_from_aggregate"]))
		states[String(part["part_id"])] = {
			"position": _arr3(com + world_r),
			"orientation": _arr4(part_q),
			"linear_velocity": _arr3(linear_velocity + angular_velocity.cross(world_r)),
			"angular_velocity": _arr3(angular_velocity),
		}
	return Utils.success({"full_states": states})

static func project(mapping: Dictionary, full_states: Dictionary, tolerance: float = 1.0e-9) -> Dictionary:
	var checked := validate(mapping)
	if not bool(checked.get("success", false)):
		return checked
	if tolerance <= 0.0 or not is_finite(tolerance):
		return Utils.failure("INVALID_STRUCTURAL_MAPPING_TOLERANCE")
	var by_id: Dictionary = {}
	for part in mapping["part_mappings"]:
		by_id[String(part["part_id"])] = part
	if full_states.size() != by_id.size():
		return Utils.failure("STRUCTURAL_FULL_STATE_PART_COUNT_MISMATCH")
	for part_id in by_id.keys():
		if not full_states.has(part_id) or typeof(full_states[part_id]) != TYPE_DICTIONARY:
			return Utils.failure("STRUCTURAL_FULL_STATE_PART_MISSING", {"part_id": part_id})
		checked = _validate_state(full_states[part_id])
		if not bool(checked.get("success", false)):
			return checked
	var reference_id := String(mapping["reference_part_id"])
	var reference_mapping: Dictionary = by_id[reference_id]
	var reference_state: Dictionary = full_states[reference_id]
	var local_q := _quat(reference_mapping["orientation_from_aggregate"])
	var aggregate_q := _canonical_quat(_quat(reference_state["orientation"]) * local_q.inverse())
	var world_r := aggregate_q * _vec3(reference_mapping["position_from_com"])
	var omega := _vec3(reference_state["angular_velocity"])
	var com := _vec3(reference_state["position"]) - world_r
	var linear_velocity := _vec3(reference_state["linear_velocity"]) - omega.cross(world_r)
	var reduced_state := {
		"position": _arr3(com),
		"orientation": _arr4(aggregate_q),
		"linear_velocity": _arr3(linear_velocity),
		"angular_velocity": _arr3(omega),
	}
	var rebuilt := reconstruct(mapping, reduced_state)
	if not bool(rebuilt.get("success", false)):
		return rebuilt
	var expected: Dictionary = rebuilt["details"]["full_states"]
	for part_id in by_id.keys():
		var actual: Dictionary = full_states[part_id]
		var predicted: Dictionary = expected[part_id]
		if _vec3(actual["position"]).distance_to(_vec3(predicted["position"])) > tolerance:
			return Utils.failure("NON_RIGID_FULL_STATE", {"part_id": part_id, "field": "position"})
		if _vec3(actual["linear_velocity"]).distance_to(_vec3(predicted["linear_velocity"])) > tolerance:
			return Utils.failure("NON_RIGID_FULL_STATE", {"part_id": part_id, "field": "linear_velocity"})
		if _vec3(actual["angular_velocity"]).distance_to(_vec3(predicted["angular_velocity"])) > tolerance:
			return Utils.failure("NON_RIGID_FULL_STATE", {"part_id": part_id, "field": "angular_velocity"})
		if _quat_distance(_quat(actual["orientation"]), _quat(predicted["orientation"])) > tolerance:
			return Utils.failure("NON_RIGID_FULL_STATE", {"part_id": part_id, "field": "orientation"})
	return Utils.success({"reduced_state": reduced_state})

static func maximum_roundtrip_error(mapping: Dictionary, reduced_state: Dictionary) -> Dictionary:
	var full := reconstruct(mapping, reduced_state)
	if not bool(full.get("success", false)):
		return full
	var projected := project(mapping, full["details"]["full_states"])
	if not bool(projected.get("success", false)):
		return projected
	var result: Dictionary = projected["details"]["reduced_state"]
	var maximum := 0.0
	maximum = maxf(maximum, _vec3(result["position"]).distance_to(_vec3(reduced_state["position"])))
	maximum = maxf(maximum, _vec3(result["linear_velocity"]).distance_to(_vec3(reduced_state["linear_velocity"])))
	maximum = maxf(maximum, _vec3(result["angular_velocity"]).distance_to(_vec3(reduced_state["angular_velocity"])))
	maximum = maxf(maximum, _quat_distance(_quat(result["orientation"]), _quat(reduced_state["orientation"])))
	return Utils.success({"maximum_error": maximum})

static func _validate_state(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, STATE_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	for field in ["position", "linear_velocity", "angular_velocity"]:
		checked = _validate_vec3(value.get(field))
		if not bool(checked.get("success", false)):
			return checked
	return _validate_quat(value.get("orientation"))

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
	if absf(norm_sq - 1.0) > UNIT_TOLERANCE:
		return Utils.failure("NON_UNIT_STRUCTURAL_QUATERNION", {"norm_squared": norm_sq})
	return Utils.success()

static func _vec3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func _quat(value: Array) -> Quaternion:
	return Quaternion(float(value[0]), float(value[1]), float(value[2]), float(value[3])).normalized()

static func _arr3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

static func _arr4(value: Quaternion) -> Array:
	var q := _canonical_quat(value)
	return [q.x, q.y, q.z, q.w]

static func _canonical_quat(value: Quaternion) -> Quaternion:
	var q := value.normalized()
	if q.w < 0.0 or (is_zero_approx(q.w) and (q.z < 0.0 or (is_zero_approx(q.z) and (q.y < 0.0 or (is_zero_approx(q.y) and q.x < 0.0))))):
		return Quaternion(-q.x, -q.y, -q.z, -q.w)
	return q

static func _quat_distance(a: Quaternion, b: Quaternion) -> float:
	var qa := a.normalized()
	var qb := b.normalized()
	return 1.0 - absf(qa.dot(qb))
