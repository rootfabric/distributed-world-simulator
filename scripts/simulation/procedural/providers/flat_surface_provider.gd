extends "res://scripts/simulation/procedural/providers/geo_provider.gd"

const GeoProviderBaseScript = preload("res://scripts/simulation/procedural/providers/geo_provider.gd")
const ProviderDescriptorScript = preload("res://scripts/simulation/procedural/contracts/geo_provider_descriptor.gd")

const PROVIDER_ID: String = "geo-provider/flat-surface"
const CONTRACT_VERSION: String = "1.0.0"
const GENERATOR_VERSION: String = "1.0.0"
const FIELD_SURFACE_HEIGHT_M: String = "geo/surface-height-m"

var _height_m: float = 0.0


func _init(height_m: float = 0.0) -> void:
	_height_m = height_m


func get_descriptor() -> Dictionary:
	return ProviderDescriptorScript.create(
		PROVIDER_ID,
		CONTRACT_VERSION,
		GENERATOR_VERSION,
		[],
		[FIELD_SURFACE_HEIGHT_M],
		true,
		{"height_m": _height_m}
	)


func supports_query_kind(query_kind: String) -> bool:
	return query_kind == GeoProviderBaseScript.QUERY_SURFACE


func sample_surface(_context: Dictionary, _query: Dictionary, _input_fields: Dictionary) -> Dictionary:
	return GeoProviderBaseScript.success({FIELD_SURFACE_HEIGHT_M: _height_m})
