extends "res://scripts/simulation/procedural/providers/geo_provider.gd"

const GeoProviderBaseScript = preload("res://scripts/simulation/procedural/providers/geo_provider.gd")
const ProviderDescriptorScript = preload("res://scripts/simulation/procedural/contracts/geo_provider_descriptor.gd")
const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")

const PROVIDER_ID: String = "geo-provider/casual-macro-terrain-v1"
const CONTRACT_VERSION: String = "1.0.0"
const GENERATOR_VERSION: String = "1.0.0"
const FIELD_SURFACE_HEIGHT_M: String = "geo/surface-height-m"

const HASH_MODULUS: int = 2147483647
const MIN_POSITION_LENGTH_SQUARED: float = 0.000000000000000001
const MAX_OCTAVES: int = 8

var _seed: int
var _nominal_radius_m: float
var _amplitude_m: float
var _base_wavelength_m: float
var _octaves: int
var _persistence: float
var _base_height_m: float


func _init(
	seed: int = 2026080801,
	nominal_radius_m: float = 6000000.0,
	amplitude_m: float = 900.0,
	base_wavelength_m: float = 600000.0,
	octaves: int = 4,
	persistence: float = 0.5,
	base_height_m: float = 0.0
) -> void:
	_seed = seed
	_nominal_radius_m = nominal_radius_m
	_amplitude_m = amplitude_m
	_base_wavelength_m = base_wavelength_m
	_octaves = octaves
	_persistence = persistence
	_base_height_m = base_height_m


func get_descriptor() -> Dictionary:
	return ProviderDescriptorScript.create(
		PROVIDER_ID,
		CONTRACT_VERSION,
		GENERATOR_VERSION,
		[],
		[FIELD_SURFACE_HEIGHT_M],
		true,
		{
			"seed": _seed,
			"nominal_radius_m": _nominal_radius_m,
			"amplitude_m": _amplitude_m,
			"base_wavelength_m": _base_wavelength_m,
			"octaves": _octaves,
			"persistence": _persistence,
			"base_height_m": _base_height_m,
			"domain": "body-fixed-unit-direction-v1",
		}
	)


func supports_query_kind(query_kind: String) -> bool:
	return query_kind == GeoProviderBaseScript.QUERY_SURFACE


func sample_surface(_context: Dictionary, query: Dictionary, _input_fields: Dictionary) -> Dictionary:
	var config_error: String = _configuration_error()
	if not config_error.is_empty():
		return GeoProviderBaseScript.failure(config_error)
	var raw_position = query.get("body_fixed_position_m")
	if not GeoUtilsScript.is_vector3_array(raw_position):
		return GeoProviderBaseScript.failure("INVALID_MACRO_SURFACE_POSITION")
	var position := Vector3(float(raw_position[0]), float(raw_position[1]), float(raw_position[2]))
	if position.length_squared() <= MIN_POSITION_LENGTH_SQUARED:
		return GeoProviderBaseScript.failure("ZERO_MACRO_SURFACE_POSITION")
	var direction: Vector3 = position.normalized()
	var height_m: float = _base_height_m + _amplitude_m * _fractal_noise(direction)
	if not is_finite(height_m):
		return GeoProviderBaseScript.failure("NON_FINITE_MACRO_SURFACE_HEIGHT")
	return GeoProviderBaseScript.success({FIELD_SURFACE_HEIGHT_M: height_m})


func _configuration_error() -> String:
	if not GeoUtilsScript.is_json_integer(_seed):
		return "INVALID_MACRO_SURFACE_SEED"
	if not is_finite(_nominal_radius_m) or _nominal_radius_m <= 0.0:
		return "INVALID_MACRO_SURFACE_RADIUS"
	if not is_finite(_amplitude_m) or _amplitude_m < 0.0:
		return "INVALID_MACRO_SURFACE_AMPLITUDE"
	if not is_finite(_base_wavelength_m) or _base_wavelength_m <= 0.0:
		return "INVALID_MACRO_SURFACE_WAVELENGTH"
	if _octaves < 1 or _octaves > MAX_OCTAVES:
		return "INVALID_MACRO_SURFACE_OCTAVES"
	if not is_finite(_persistence) or _persistence <= 0.0 or _persistence > 1.0:
		return "INVALID_MACRO_SURFACE_PERSISTENCE"
	if not is_finite(_base_height_m):
		return "INVALID_MACRO_SURFACE_BASE_HEIGHT"
	return ""


func _fractal_noise(direction: Vector3) -> float:
	# Noise lives in body-fixed 3D direction space, never in cube-face UV or cell
	# coordinates. Therefore cube seams and LOD subdivision cannot alter the
	# canonical macro surface sample.
	var frequency: float = _nominal_radius_m / _base_wavelength_m
	var amplitude: float = 1.0
	var accumulated: float = 0.0
	var normalizer: float = 0.0
	for octave in range(_octaves):
		var octave_seed: int = _mix_seed(_seed, octave + 1)
		accumulated += _value_noise_3d(direction * frequency, octave_seed) * amplitude
		normalizer += amplitude
		frequency *= 2.0
		amplitude *= _persistence
	if normalizer <= 0.0:
		return 0.0
	return clampf(accumulated / normalizer, -1.0, 1.0)


func _value_noise_3d(point: Vector3, seed: int) -> float:
	var x0: int = int(floor(point.x))
	var y0: int = int(floor(point.y))
	var z0: int = int(floor(point.z))
	var tx: float = point.x - float(x0)
	var ty: float = point.y - float(y0)
	var tz: float = point.z - float(z0)
	var sx: float = _fade(tx)
	var sy: float = _fade(ty)
	var sz: float = _fade(tz)

	var c000: float = _lattice_value(x0, y0, z0, seed)
	var c100: float = _lattice_value(x0 + 1, y0, z0, seed)
	var c010: float = _lattice_value(x0, y0 + 1, z0, seed)
	var c110: float = _lattice_value(x0 + 1, y0 + 1, z0, seed)
	var c001: float = _lattice_value(x0, y0, z0 + 1, seed)
	var c101: float = _lattice_value(x0 + 1, y0, z0 + 1, seed)
	var c011: float = _lattice_value(x0, y0 + 1, z0 + 1, seed)
	var c111: float = _lattice_value(x0 + 1, y0 + 1, z0 + 1, seed)

	var x00: float = lerpf(c000, c100, sx)
	var x10: float = lerpf(c010, c110, sx)
	var x01: float = lerpf(c001, c101, sx)
	var x11: float = lerpf(c011, c111, sx)
	var y0v: float = lerpf(x00, x10, sy)
	var y1v: float = lerpf(x01, x11, sy)
	return lerpf(y0v, y1v, sz)


func _lattice_value(x: int, y: int, z: int, seed: int) -> float:
	var h: int = _positive_mod(seed, HASH_MODULUS)
	h = _mix_int(h, x, 73856093)
	h = _mix_int(h, y, 19349663)
	h = _mix_int(h, z, 83492791)
	h = _mix_int(h, x + y + z, 265443576)
	return (float(h) / float(HASH_MODULUS - 1)) * 2.0 - 1.0


func _mix_seed(seed: int, octave: int) -> int:
	return _mix_int(_positive_mod(seed, HASH_MODULUS), octave, 104729)


func _mix_int(state: int, coordinate: int, prime: int) -> int:
	var coordinate_term: int = _positive_mod(coordinate, HASH_MODULUS)
	var mixed: int = _positive_mod(state * 48271, HASH_MODULUS)
	mixed = _positive_mod(mixed + _positive_mod(coordinate_term * prime, HASH_MODULUS), HASH_MODULUS)
	mixed = _positive_mod(mixed * 69621 + 1, HASH_MODULUS)
	return mixed


func _positive_mod(value: int, modulus: int) -> int:
	var result: int = value % modulus
	return result + modulus if result < 0 else result


func _fade(value: float) -> float:
	# Quintic interpolation has zero first and second derivative at lattice
	# boundaries, giving visibly soft macro hills instead of blocky value noise.
	return value * value * value * (value * (value * 6.0 - 15.0) + 10.0)
