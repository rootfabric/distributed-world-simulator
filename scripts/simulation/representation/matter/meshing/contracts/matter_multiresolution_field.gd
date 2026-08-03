extends RefCounted

const RepresentationUtils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const GridProfile = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const CellGrid = preload("res://scripts/simulation/matter/spatial/matter_cell_grid.gd")
const SourceSet = preload("res://scripts/simulation/representation/matter/meshing/contracts/matter_meshing_source_set.gd")
const RepresentationKey = preload("res://scripts/simulation/representation/contracts/representation_key.gd")

const SCHEMA := "planet_simulator.matter_multiresolution_field.v1"
const COLOR_COMPONENT_COUNT: int = 4
const FIELDS: Array[String] = [
	"schema",
	"source_set",
	"representation_key",
	"cell_address",
	"bounds_m",
	"lod_level",
	"resolution",
	"sample_spacing_m",
	"iso_level_m",
	"signed_distance_m",
	"colors_rgba",
	"minimum_signed_distance_m",
	"maximum_signed_distance_m",
	"field_hash",
	"checksum",
]


static func create(
	source_set: Dictionary,
	representation_key: Dictionary,
	cell_address: Dictionary,
	bounds_m: Array,
	resolution: int,
	sample_spacing_m: float,
	iso_level_m: float,
	signed_distance_m: Array,
	colors_rgba: Array,
	grid_profile: Dictionary
) -> Dictionary:
	var minimum_distance: float = INF
	var maximum_distance: float = -INF
	for raw_distance in signed_distance_m:
		var distance_m: float = float(raw_distance)
		minimum_distance = minf(minimum_distance, distance_m)
		maximum_distance = maxf(maximum_distance, distance_m)
	var field_payload: Dictionary = {
		"signed_distance_m": signed_distance_m,
		"colors_rgba": colors_rgba,
	}
	var value: Dictionary = {
		"schema": SCHEMA,
		"source_set": source_set.duplicate(true),
		"representation_key": representation_key.duplicate(true),
		"cell_address": cell_address.duplicate(true),
		"bounds_m": bounds_m.duplicate(true),
		"lod_level": int(source_set.get("lod_level", -1)),
		"resolution": resolution,
		"sample_spacing_m": sample_spacing_m,
		"iso_level_m": iso_level_m,
		"signed_distance_m": signed_distance_m.duplicate(true),
		"colors_rgba": colors_rgba.duplicate(true),
		"minimum_signed_distance_m": minimum_distance,
		"maximum_signed_distance_m": maximum_distance,
		"field_hash": RepresentationUtils.payload_hash(field_payload),
		"checksum": "",
	}
	value["checksum"] = RepresentationUtils.compute_checksum(value)
	return value if bool(validate(value, grid_profile).get("success", false)) else {}


static func validate(value: Dictionary, grid_profile: Dictionary) -> Dictionary:
	var checked: Dictionary = RepresentationUtils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return RepresentationUtils.failure("UNSUPPORTED_MATTER_MULTIRESOLUTION_FIELD_SCHEMA")
	if typeof(value.get("source_set")) != TYPE_DICTIONARY:
		return RepresentationUtils.failure("INVALID_MATTER_FIELD_SOURCE_SET")
	checked = SourceSet.validate(value["source_set"], grid_profile)
	if not bool(checked.get("success", false)):
		return checked
	if typeof(value.get("representation_key")) != TYPE_DICTIONARY:
		return RepresentationUtils.failure("INVALID_MATTER_FIELD_REPRESENTATION_KEY")
	checked = RepresentationKey.validate(value["representation_key"])
	if not bool(checked.get("success", false)):
		return checked
	var source_set: Dictionary = value["source_set"]
	var key: Dictionary = value["representation_key"]
	if key["source_revision"] != source_set["source_revision"] \
		or String(key["scope_id"]) != String(source_set["target_scope_id"]) \
		or int(key["lod_level"]) != int(source_set["lod_level"]):
		return RepresentationUtils.failure("MATTER_FIELD_REPRESENTATION_KEY_MISMATCH")
	if String(key["artifact_kind"]) != _artifact_kind(int(source_set["lod_level"])):
		return RepresentationUtils.failure("MATTER_FIELD_ARTIFACT_KIND_MISMATCH")
	if typeof(value.get("cell_address")) != TYPE_DICTIONARY \
		or value["cell_address"] != source_set["target_cell_address"] \
		or not bool(CellGrid.validate_address(grid_profile, value["cell_address"]).get("success", false)):
		return RepresentationUtils.failure("MATTER_FIELD_CELL_MISMATCH")
	checked = RepresentationUtils.validate_bounds_m(value.get("bounds_m"))
	if not bool(checked.get("success", false)):
		return checked
	var expected_bounds: Dictionary = CellGrid.bounds(grid_profile, value["cell_address"])
	var expected_bounds_array: Array = [
		float(expected_bounds["minimum_m"][0]),
		float(expected_bounds["minimum_m"][1]),
		float(expected_bounds["minimum_m"][2]),
		float(expected_bounds["maximum_m"][0]),
		float(expected_bounds["maximum_m"][1]),
		float(expected_bounds["maximum_m"][2]),
	]
	if value["bounds_m"] != expected_bounds_array:
		return RepresentationUtils.failure("MATTER_FIELD_BOUNDS_MISMATCH")
	for field in ["lod_level", "resolution"]:
		if not RepresentationUtils.is_json_integer(value.get(field)):
			return RepresentationUtils.failure("INVALID_MATTER_FIELD_INTEGER", {"field": field})
	if int(value["lod_level"]) != int(source_set["lod_level"]):
		return RepresentationUtils.failure("MATTER_FIELD_LOD_MISMATCH")
	var resolution: int = int(value["resolution"])
	if resolution != int(grid_profile["brick_interior_resolution"]):
		return RepresentationUtils.failure("MATTER_FIELD_RESOLUTION_MISMATCH")
	if not RepresentationUtils.is_positive_number(value.get("sample_spacing_m")) \
		or not RepresentationUtils.is_finite_number(value.get("iso_level_m")):
		return RepresentationUtils.failure("INVALID_MATTER_FIELD_SPACING")
	var expected_spacing: float = float(expected_bounds["edge_length_m"]) / float(resolution)
	if not is_equal_approx(float(value["sample_spacing_m"]), expected_spacing):
		return RepresentationUtils.failure("MATTER_FIELD_SPACING_MISMATCH")
	var axis_count: int = resolution + 1
	var sample_count: int = axis_count * axis_count * axis_count
	if typeof(value.get("signed_distance_m")) != TYPE_ARRAY \
		or value["signed_distance_m"].size() != sample_count:
		return RepresentationUtils.failure("MATTER_FIELD_DISTANCE_COUNT_MISMATCH")
	if typeof(value.get("colors_rgba")) != TYPE_ARRAY \
		or value["colors_rgba"].size() != sample_count:
		return RepresentationUtils.failure("MATTER_FIELD_COLOR_COUNT_MISMATCH")
	var minimum_distance: float = INF
	var maximum_distance: float = -INF
	for index in range(sample_count):
		var distance_value = value["signed_distance_m"][index]
		if not RepresentationUtils.is_finite_number(distance_value):
			return RepresentationUtils.failure("INVALID_MATTER_FIELD_DISTANCE", {"index": index})
		var distance_m: float = float(distance_value)
		minimum_distance = minf(minimum_distance, distance_m)
		maximum_distance = maxf(maximum_distance, distance_m)
		var color_value = value["colors_rgba"][index]
		if typeof(color_value) != TYPE_ARRAY or color_value.size() != COLOR_COMPONENT_COUNT:
			return RepresentationUtils.failure("INVALID_MATTER_FIELD_COLOR", {"index": index})
		for component in color_value:
			if not RepresentationUtils.is_finite_number(component) \
				or float(component) < 0.0 or float(component) > 1.0:
				return RepresentationUtils.failure("INVALID_MATTER_FIELD_COLOR", {"index": index})
	for field in ["minimum_signed_distance_m", "maximum_signed_distance_m"]:
		if not RepresentationUtils.is_finite_number(value.get(field)):
			return RepresentationUtils.failure("INVALID_MATTER_FIELD_RANGE")
	if float(value["minimum_signed_distance_m"]) != minimum_distance \
		or float(value["maximum_signed_distance_m"]) != maximum_distance:
		return RepresentationUtils.failure("MATTER_FIELD_RANGE_MISMATCH")
	var field_payload: Dictionary = {
		"signed_distance_m": value["signed_distance_m"],
		"colors_rgba": value["colors_rgba"],
	}
	if not RepresentationUtils.is_lower_hex_64(value.get("field_hash")) \
		or String(value["field_hash"]) != RepresentationUtils.payload_hash(field_payload):
		return RepresentationUtils.failure("MATTER_FIELD_HASH_MISMATCH")
	return RepresentationUtils.validate_checksum(value)


static func flat_index(resolution: int, x: int, y: int, z: int) -> int:
	var axis_count: int = resolution + 1
	if x < 0 or y < 0 or z < 0 or x >= axis_count or y >= axis_count or z >= axis_count:
		return -1
	return x + axis_count * (y + axis_count * z)


static func _artifact_kind(lod_level: int) -> String:
	match lod_level:
		0:
			return "DETAIL"
		1:
			return "SIMPLIFIED_MESH"
		2:
			return "MACRO_PROXY"
		_:
			return ""
