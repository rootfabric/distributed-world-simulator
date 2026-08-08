extends "res://scripts/simulation/procedural/providers/geo_provider.gd"

const GeoProviderBaseScript = preload("res://scripts/simulation/procedural/providers/geo_provider.gd")
const ProviderDescriptorScript = preload("res://scripts/simulation/procedural/contracts/geo_provider_descriptor.gd")

const PROVIDER_ID: String = "geo-provider/base-surface-v1"
const CONTRACT_VERSION: String = "1.0.0"
const GENERATOR_VERSION: String = "1.0.0"
const FIELD_BASE_SURFACE_HEIGHT_M: String = "geo/base-surface-height-m"

var _base_height_m: float = 0.0


func _init(base_height_m: float = 0.0) -> void:
	_base_height_m = base_height_m


func get_descriptor() -> Dictionary:
	return ProviderDescriptorScript.create(
		PROVIDER_ID,
		CONTRACT_VERSION,
		GENERATOR_VERSION,
		[],
		[FIELD_BASE_SURFACE_HEIGHT_M],
		true,
		{"base_height_m": _base_height_m}
	)


func supports_query_kind(query_kind: String) -> bool:
	return query_kind == GeoProviderBaseScript.QUERY_SURFACE


func sample_surface(_context: Dictionary, _query: Dictionary, _input_fields: Dictionary) -> Dictionary:
	if not is_finite(_base_height_m):
		return GeoProviderBaseScript.failure("INVALID_BASE_SURFACE_HEIGHT")
	return GeoProviderBaseScript.success({FIELD_BASE_SURFACE_HEIGHT_M: _base_height_m})
