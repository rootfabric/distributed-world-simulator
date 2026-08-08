extends "res://scripts/simulation/procedural/providers/geo_provider.gd"

const GeoProviderBaseScript = preload("res://scripts/simulation/procedural/providers/geo_provider.gd")
const ProviderDescriptorScript = preload("res://scripts/simulation/procedural/contracts/geo_provider_descriptor.gd")
const G3MacroProviderScript = preload("res://scripts/simulation/procedural/providers/casual_macro_terrain_provider_v1.gd")
const BaseSurfaceProviderScript = preload("res://scripts/simulation/procedural/providers/base_surface_provider_v1.gd")

const PROVIDER_ID: String = "geo-provider/casual-macro-terrain-layer-v1"
const CONTRACT_VERSION: String = "1.0.0"
const GENERATOR_VERSION: String = "1.0.0"
const FIELD_MACRO_SURFACE_HEIGHT_M: String = "geo/macro-surface-height-m"

var _seed: int
var _nominal_radius_m: float
var _amplitude_m: float
var _base_wavelength_m: float
var _octaves: int
var _persistence: float
var _g3_provider


func _init(
	seed: int = 2026080801,
	nominal_radius_m: float = 6000000.0,
	amplitude_m: float = 900.0,
	base_wavelength_m: float = 600000.0,
	octaves: int = 4,
	persistence: float = 0.5
) -> void:
	_seed = seed
	_nominal_radius_m = nominal_radius_m
	_amplitude_m = amplitude_m
	_base_wavelength_m = base_wavelength_m
	_octaves = octaves
	_persistence = persistence
	_g3_provider = G3MacroProviderScript.new(seed, nominal_radius_m, amplitude_m, base_wavelength_m, octaves, persistence, 0.0)


func get_descriptor() -> Dictionary:
	return ProviderDescriptorScript.create(
		PROVIDER_ID,
		CONTRACT_VERSION,
		GENERATOR_VERSION,
		[BaseSurfaceProviderScript.FIELD_BASE_SURFACE_HEIGHT_M],
		[FIELD_MACRO_SURFACE_HEIGHT_M],
		true,
		{
			"seed": _seed,
			"nominal_radius_m": _nominal_radius_m,
			"amplitude_m": _amplitude_m,
			"base_wavelength_m": _base_wavelength_m,
			"octaves": _octaves,
			"persistence": _persistence,
			"source_provider_id": G3MacroProviderScript.PROVIDER_ID,
			"source_generator_version": G3MacroProviderScript.GENERATOR_VERSION,
			"domain": "body-fixed-unit-direction-v1",
		}
	)


func supports_query_kind(query_kind: String) -> bool:
	return query_kind == GeoProviderBaseScript.QUERY_SURFACE


func sample_surface(context: Dictionary, query: Dictionary, input_fields: Dictionary) -> Dictionary:
	if not input_fields.has(BaseSurfaceProviderScript.FIELD_BASE_SURFACE_HEIGHT_M):
		return GeoProviderBaseScript.failure("MISSING_BASE_SURFACE_INPUT")
	var base_height = input_fields[BaseSurfaceProviderScript.FIELD_BASE_SURFACE_HEIGHT_M]
	if typeof(base_height) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(base_height)):
		return GeoProviderBaseScript.failure("INVALID_BASE_SURFACE_INPUT")
	var response: Dictionary = _g3_provider.sample_surface(context, query, {})
	if not bool(response.get("success", false)):
		return GeoProviderBaseScript.failure("G3_MACRO_LAYER_SAMPLE_FAILED", {"cause": response.get("error_code", "")})
	var displacement = response["details"]["values"].get(G3MacroProviderScript.FIELD_SURFACE_HEIGHT_M)
	if typeof(displacement) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(displacement)):
		return GeoProviderBaseScript.failure("INVALID_G3_MACRO_LAYER_OUTPUT")
	return GeoProviderBaseScript.success({FIELD_MACRO_SURFACE_HEIGHT_M: float(base_height) + float(displacement)})
