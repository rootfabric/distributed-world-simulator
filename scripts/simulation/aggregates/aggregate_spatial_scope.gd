extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SpatialRefScript = preload("res://scripts/simulation/spatial/spatial_ref.gd")

const SCHEMA: String = "planet_simulator.aggregate_spatial_scope.v1"
const KIND_NONE: String = "NONE"
const KIND_POINT: String = "POINT"
const KIND_BOUNDS: String = "BOUNDS"
const KIND_CELL: String = "CELL"
const KIND_REGION: String = "REGION"
const KIND_CELL_SET: String = "CELL_SET"
const KINDS: Array[String] = [KIND_NONE, KIND_POINT, KIND_BOUNDS, KIND_CELL, KIND_REGION, KIND_CELL_SET]
const FIELDS: Array[String] = ["schema", "scope_kind", "scope_data"]


static func create(scope_kind: String, scope_data: Dictionary = {}) -> Dictionary:
	return {
		"schema": SCHEMA,
		"scope_kind": scope_kind,
		"scope_data": scope_data.duplicate(true),
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return _failure("UNSUPPORTED_SPATIAL_SCOPE_SCHEMA")
	if typeof(value.get("scope_kind")) != TYPE_STRING or not KINDS.has(String(value["scope_kind"])):
		return _failure("INVALID_SPATIAL_SCOPE_KIND")
	if typeof(value.get("scope_data")) != TYPE_DICTIONARY:
		return _failure("INVALID_SPATIAL_SCOPE_DATA")
	var data: Dictionary = value["scope_data"]
	var safe: Dictionary = UtilsScript.canonicalize(data, "$.scope_data")
	if not bool(safe.get("success", false)):
		return _failure("NON_CANONICAL_SPATIAL_SCOPE")
	match String(value["scope_kind"]):
		KIND_NONE:
			if not data.is_empty():
				return _failure("NONE_SCOPE_MUST_BE_EMPTY")
		KIND_POINT:
			if data.size() != 1 or typeof(data.get("spatial_ref")) != TYPE_DICTIONARY or not SpatialRefScript.is_valid(data["spatial_ref"]):
				return _failure("INVALID_POINT_SCOPE")
		KIND_CELL:
			if data.size() != 1 or not _valid_id(data.get("cell_id")):
				return _failure("INVALID_CELL_SCOPE")
		KIND_REGION:
			if data.size() != 1 or not _valid_id(data.get("region_id")):
				return _failure("INVALID_REGION_SCOPE")
		KIND_CELL_SET:
			if data.size() != 1 or typeof(data.get("cell_ids")) != TYPE_ARRAY:
				return _failure("INVALID_CELL_SET_SCOPE")
			var seen: Dictionary = {}
			for raw_id in data["cell_ids"]:
				if not _valid_id(raw_id) or seen.has(raw_id):
					return _failure("INVALID_CELL_SET_SCOPE")
				seen[raw_id] = true
			if seen.is_empty():
				return _failure("INVALID_CELL_SET_SCOPE")
		KIND_BOUNDS:
			var required: Array[String] = ["frame_id", "minimum_m", "maximum_m"]
			var bounds_exact: Dictionary = UtilsScript.validate_exact_fields(data, required)
			if not bool(bounds_exact.get("success", false)):
				return _failure("INVALID_BOUNDS_SCOPE")
			if not _valid_id(data.get("frame_id")) or not _vector3(data.get("minimum_m")) or not _vector3(data.get("maximum_m")):
				return _failure("INVALID_BOUNDS_SCOPE")
			for index in range(3):
				if float(data["minimum_m"][index]) > float(data["maximum_m"][index]):
					return _failure("INVALID_BOUNDS_SCOPE")
	return UtilsScript.validation_success()


static func _valid_id(value) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text: String = String(value)
	if text.is_empty() or text != text.strip_edges().to_lower() or text.begins_with("/") or text.ends_with("/"):
		return false
	for part in text.split("/", true):
		if part.is_empty():
			return false
		for character in part:
			if not String(character) in ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "-", "_", ".", ":"]:
				return false
	return true


static func _vector3(value) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return false
	for component in value:
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(component)):
			return false
	return true


static func _failure(code: String) -> Dictionary:
	return UtilsScript.validation_failure(code, code)
