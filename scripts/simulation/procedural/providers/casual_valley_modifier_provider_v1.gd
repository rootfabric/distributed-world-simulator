extends "res://scripts/simulation/procedural/providers/geo_provider.gd"

const GeoProviderBaseScript = preload("res://scripts/simulation/procedural/providers/geo_provider.gd")
const ProviderDescriptorScript = preload("res://scripts/simulation/procedural/contracts/geo_provider_descriptor.gd")
const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const MacroLayerScript = preload("res://scripts/simulation/procedural/providers/casual_macro_terrain_layer_provider_v1.gd")

const PROVIDER_ID: String = "geo-provider/casual-valley-modifier-v1"
const CONTRACT_VERSION: String = "1.0.0"
const GENERATOR_VERSION: String = "1.0.0"
const FIELD_SURFACE_HEIGHT_M: String = "geo/surface-height-m"
const MIN_POSITION_LENGTH_SQUARED: float = 0.000000000000000001

var _nominal_radius_m: float
var _half_width_m: float
var _depth_m: float
var _plane_normal: Vector3


func _init(
	nominal_radius_m: float = 6000000.0,
	half_width_m: float = 80000.0,
	depth_m: float = 350.0,
	plane_normal: Array = [0.35, 0.82, -0.45]
) -> void:
	_nominal_radius_m = nominal_radius_m
	_half_width_m = half_width_m
	_depth_m = depth_m
	_plane_normal = Vector3(float(plane_normal[0]), float(plane_normal[1]), float(plane_normal[2])).normalized() if plane_normal.size() == 3 else Vector3.UP


func get_descriptor() -> Dictionary:
	return ProviderDescriptorScript.create(
		PROVIDER_ID,
		CONTRACT_VERSION,
		GENERATOR_VERSION,
		[MacroLayerScript.FIELD_MACRO_SURFACE_HEIGHT_M],
		[FIELD_SURFACE_HEIGHT_M],
		true,
		{
			"nominal_radius_m": _nominal_radius_m,
			"half_width_m": _half_width_m,
			"depth_m": _depth_m,
			"plane_normal": [_plane_normal.x, _plane_normal.y, _plane_normal.z],
			"model": "great-circle-valley-v1",
		}
	)


func supports_query_kind(query_kind: String) -> bool:
	return query_kind == GeoProviderBaseScript.QUERY_SURFACE


func sample_surface(_context: Dictionary, query: Dictionary, input_fields: Dictionary) -> Dictionary:
	if not is_finite(_nominal_radius_m) or _nominal_radius_m <= 0.0 or not is_finite(_half_width_m) or _half_width_m <= 0.0 or not is_finite(_depth_m) or _depth_m < 0.0:
		return GeoProviderBaseScript.failure("INVALID_CASUAL_VALLEY_CONFIGURATION")
	var macro = input_fields.get(MacroLayerScript.FIELD_MACRO_SURFACE_HEIGHT_M)
	if typeof(macro) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(macro)):
		return GeoProviderBaseScript.failure("INVALID_MACRO_SURFACE_INPUT")
	var raw_position = query.get("body_fixed_position_m")
	if not GeoUtilsScript.is_vector3_array(raw_position):
		return GeoProviderBaseScript.failure("INVALID_CASUAL_VALLEY_POSITION")
	var position := Vector3(float(raw_position[0]), float(raw_position[1]), float(raw_position[2]))
	if position.length_squared() <= MIN_POSITION_LENGTH_SQUARED:
		return GeoProviderBaseScript.failure("ZERO_CASUAL_VALLEY_POSITION")
	var direction: Vector3 = position.normalized()
	var sine_distance: float = clampf(absf(direction.dot(_plane_normal)), 0.0, 1.0)
	var arc_distance_m: float = asin(sine_distance) * _nominal_radius_m
	var carve: float = 0.0
	if arc_distance_m < _half_width_m:
		var normalized: float = 1.0 - arc_distance_m / _half_width_m
		var smooth: float = normalized * normalized * (3.0 - 2.0 * normalized)
		carve = _depth_m * smooth
	return GeoProviderBaseScript.success({FIELD_SURFACE_HEIGHT_M: float(macro) - carve})
