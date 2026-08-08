extends "res://scripts/simulation/procedural/providers/geo_provider.gd"

const GeoProviderBaseScript = preload("res://scripts/simulation/procedural/providers/geo_provider.gd")
const ProviderDescriptorScript = preload("res://scripts/simulation/procedural/contracts/geo_provider_descriptor.gd")
const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const BaseSurfaceProviderScript = preload("res://scripts/simulation/procedural/providers/base_surface_provider_v1.gd")
const MacroLayerScript = preload("res://scripts/simulation/procedural/providers/casual_macro_terrain_layer_provider_v1.gd")

const PROVIDER_ID: String = "geo-provider/alternative-macro-terrain-v1"
const CONTRACT_VERSION: String = "1.0.0"
const GENERATOR_VERSION: String = "1.0.0"
const MIN_POSITION_LENGTH_SQUARED: float = 0.000000000000000001

var _seed: int
var _amplitude_m: float
var _frequency: float


func _init(seed: int = 2026080801, amplitude_m: float = 900.0, frequency: float = 7.0) -> void:
	_seed = seed
	_amplitude_m = amplitude_m
	_frequency = frequency


func get_descriptor() -> Dictionary:
	return ProviderDescriptorScript.create(
		PROVIDER_ID,
		CONTRACT_VERSION,
		GENERATOR_VERSION,
		[BaseSurfaceProviderScript.FIELD_BASE_SURFACE_HEIGHT_M],
		[MacroLayerScript.FIELD_MACRO_SURFACE_HEIGHT_M],
		true,
		{
			"seed": _seed,
			"amplitude_m": _amplitude_m,
			"frequency": _frequency,
			"domain": "body-fixed-unit-direction-v1",
			"algorithm": "analytic-harmonics-v1",
		}
	)


func supports_query_kind(query_kind: String) -> bool:
	return query_kind == GeoProviderBaseScript.QUERY_SURFACE


func sample_surface(_context: Dictionary, query: Dictionary, input_fields: Dictionary) -> Dictionary:
	if not GeoUtilsScript.is_json_integer(_seed):
		return GeoProviderBaseScript.failure("INVALID_ALTERNATIVE_MACRO_SEED")
	if not is_finite(_amplitude_m) or _amplitude_m < 0.0 or not is_finite(_frequency) or _frequency <= 0.0:
		return GeoProviderBaseScript.failure("INVALID_ALTERNATIVE_MACRO_CONFIGURATION")
	var base = input_fields.get(BaseSurfaceProviderScript.FIELD_BASE_SURFACE_HEIGHT_M)
	if typeof(base) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(base)):
		return GeoProviderBaseScript.failure("INVALID_BASE_SURFACE_INPUT")
	var raw_position = query.get("body_fixed_position_m")
	if not GeoUtilsScript.is_vector3_array(raw_position):
		return GeoProviderBaseScript.failure("INVALID_ALTERNATIVE_MACRO_POSITION")
	var position := Vector3(float(raw_position[0]), float(raw_position[1]), float(raw_position[2]))
	if position.length_squared() <= MIN_POSITION_LENGTH_SQUARED:
		return GeoProviderBaseScript.failure("ZERO_ALTERNATIVE_MACRO_POSITION")
	var d: Vector3 = position.normalized()
	var phase: float = float(_positive_mod(_seed, 1000003)) / 1000003.0 * TAU
	var harmonic_a: float = sin(d.x * _frequency + phase)
	var harmonic_b: float = cos(d.y * (_frequency * 0.73) - phase * 0.61)
	var harmonic_c: float = sin((d.z + d.x * 0.37) * (_frequency * 1.41) + phase * 1.17)
	var displacement: float = _amplitude_m * (harmonic_a * 0.50 + harmonic_b * 0.30 + harmonic_c * 0.20)
	return GeoProviderBaseScript.success({MacroLayerScript.FIELD_MACRO_SURFACE_HEIGHT_M: float(base) + displacement})


func _positive_mod(value: int, modulus: int) -> int:
	var result: int = value % modulus
	return result + modulus if result < 0 else result
