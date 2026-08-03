extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")

const SCHEMA: String = "planet_simulator.matter_spatial_grid_profile.v1"
const DEFAULT_UNIVERSE_ID: String = "planet-simulator"
const DEFAULT_INSTANCE_ID: String = "matter-lab"
const DEFAULT_SPACE_ID: String = "asteroid-mw0"
const DEFAULT_GRID_ID: String = "matter-grid-mw2"
const DEFAULT_ROOT_ID: String = "asteroid-mw0-root"
const DEFAULT_GRID_REVISION: int = 1
const DEFAULT_MAX_LEVEL: int = 5
const DEFAULT_BRICK_INTERIOR_RESOLUTION: int = 8
const DEFAULT_GHOST_BORDER_SAMPLES: int = 1
const MIN_BRICK_INTERIOR_RESOLUTION: int = 2
const MAX_BRICK_INTERIOR_RESOLUTION: int = 64
const MAX_GHOST_BORDER_SAMPLES: int = 4
const FIELDS: Array[String] = [
	"schema",
	"universe_id",
	"instance_id",
	"space_id",
	"grid_id",
	"grid_revision",
	"root_id",
	"body_id",
	"body_frame_id",
	"root_center_m",
	"root_half_extent_m",
	"max_level",
	"brick_interior_resolution",
	"ghost_border_samples",
	"checksum",
]


static func create(data: Dictionary = {}) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"universe_id": String(data.get("universe_id", DEFAULT_UNIVERSE_ID)).strip_edges().to_lower(),
		"instance_id": String(data.get("instance_id", DEFAULT_INSTANCE_ID)).strip_edges().to_lower(),
		"space_id": String(data.get("space_id", DEFAULT_SPACE_ID)).strip_edges().to_lower(),
		"grid_id": String(data.get("grid_id", DEFAULT_GRID_ID)).strip_edges().to_lower(),
		"grid_revision": int(data.get("grid_revision", DEFAULT_GRID_REVISION)),
		"root_id": String(data.get("root_id", DEFAULT_ROOT_ID)).strip_edges().to_lower(),
		"body_id": String(data.get("body_id", "")).strip_edges().to_lower(),
		"body_frame_id": String(data.get("body_frame_id", "")).strip_edges().to_lower(),
		"root_center_m": _float_array(data.get("root_center_m", [0.0, 0.0, 0.0])),
		"root_half_extent_m": float(data.get("root_half_extent_m", 0.0)),
		"max_level": int(data.get("max_level", DEFAULT_MAX_LEVEL)),
		"brick_interior_resolution": int(data.get(
			"brick_interior_resolution", DEFAULT_BRICK_INTERIOR_RESOLUTION
		)),
		"ghost_border_samples": int(data.get(
			"ghost_border_samples", DEFAULT_GHOST_BORDER_SAMPLES
		)),
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_GRID_PROFILE_SCHEMA")
	for field in ["universe_id", "instance_id", "space_id", "grid_id", "root_id"]:
		if not _is_lower_segment(value.get(field)):
			return MatterUtilsScript.failure("INVALID_MATTER_GRID_IDENTIFIER", {"field": field})
	for field in ["body_id", "body_frame_id"]:
		if not MatterUtilsScript.is_canonical_id(value.get(field), 2):
			return MatterUtilsScript.failure("INVALID_MATTER_GRID_BODY_ID", {"field": field})
	if not MatterUtilsScript.is_vector3_array(value.get("root_center_m")):
		return MatterUtilsScript.failure("INVALID_MATTER_GRID_ROOT_CENTER")
	if not MatterUtilsScript.is_positive_number(value.get("root_half_extent_m")):
		return MatterUtilsScript.failure("INVALID_MATTER_GRID_ROOT_EXTENT")
	for field in [
		"grid_revision", "max_level", "brick_interior_resolution", "ghost_border_samples"
	]:
		if not MatterUtilsScript.is_json_integer(value.get(field)):
			return MatterUtilsScript.failure("INVALID_MATTER_GRID_INTEGER", {"field": field})
	if int(value["grid_revision"]) < 1:
		return MatterUtilsScript.failure("INVALID_MATTER_GRID_REVISION")
	if int(value["max_level"]) < 1 or int(value["max_level"]) > MatterUtilsScript.MAX_STORAGE_LEVEL:
		return MatterUtilsScript.failure("INVALID_MATTER_GRID_MAX_LEVEL")
	var resolution: int = int(value["brick_interior_resolution"])
	if resolution < MIN_BRICK_INTERIOR_RESOLUTION or resolution > MAX_BRICK_INTERIOR_RESOLUTION:
		return MatterUtilsScript.failure("INVALID_MATTER_BRICK_RESOLUTION")
	var ghost: int = int(value["ghost_border_samples"])
	if ghost < 1 or ghost > MAX_GHOST_BORDER_SAMPLES:
		return MatterUtilsScript.failure("INVALID_MATTER_GHOST_BORDER")
	var axis_count: int = sample_axis_count(value)
	var total_count: int = axis_count * axis_count * axis_count
	if total_count < 1 or total_count > MatterUtilsScript.MAX_SAMPLE_COUNT:
		return MatterUtilsScript.failure("MATTER_BRICK_SAMPLE_COUNT_OUT_OF_RANGE")
	var safe: Dictionary = MatterUtilsScript.validate_json_safe(value, "$.matter_spatial_grid_profile")
	if not bool(safe.get("success", false)):
		return safe
	return MatterUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return MatterUtilsScript.normalize(value, validate)


static func sample_axis_count(value: Dictionary) -> int:
	if not MatterUtilsScript.is_json_integer(value.get("brick_interior_resolution")) \
		or not MatterUtilsScript.is_json_integer(value.get("ghost_border_samples")):
		return 0
	return int(value["brick_interior_resolution"]) + 1 + 2 * int(value["ghost_border_samples"])


static func sample_count(value: Dictionary) -> int:
	var axis_count: int = sample_axis_count(value)
	return axis_count * axis_count * axis_count


static func content_hash(value: Dictionary) -> String:
	return MatterUtilsScript.payload_hash(value) if bool(validate(value).get("success", false)) else ""


static func _float_array(raw) -> Array:
	var result: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return result
	for component in raw:
		result.append(float(component))
	return result


static func _is_lower_segment(value) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text: String = String(value)
	if text.is_empty() or text != text.strip_edges() or text != text.to_lower():
		return false
	for character in text:
		var token: String = String(character)
		if not token in [
			"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
			"n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
			"0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "-", "_",
		]:
			return false
	return true
