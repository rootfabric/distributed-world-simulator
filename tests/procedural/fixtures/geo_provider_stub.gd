extends "res://scripts/simulation/procedural/providers/geo_provider.gd"

const GeoProviderBaseScript = preload("res://scripts/simulation/procedural/providers/geo_provider.gd")

var _descriptor: Dictionary = {}
var _surface_values: Dictionary = {}
var _volume_values: Dictionary = {}
var _surface_supported: bool = true
var _volume_supported: bool = false


func _init(
	descriptor: Dictionary,
	surface_values: Dictionary = {},
	volume_values: Dictionary = {},
	surface_supported: bool = true,
	volume_supported: bool = false
) -> void:
	_descriptor = descriptor.duplicate(true)
	_surface_values = surface_values.duplicate(true)
	_volume_values = volume_values.duplicate(true)
	_surface_supported = surface_supported
	_volume_supported = volume_supported


func get_descriptor() -> Dictionary:
	return _descriptor.duplicate(true)


func supports_query_kind(query_kind: String) -> bool:
	if query_kind == GeoProviderBaseScript.QUERY_SURFACE:
		return _surface_supported
	if query_kind == GeoProviderBaseScript.QUERY_VOLUME:
		return _volume_supported
	return false


func sample_surface(_context: Dictionary, _query: Dictionary, _input_fields: Dictionary) -> Dictionary:
	if not _surface_supported:
		return GeoProviderBaseScript.failure("STUB_SURFACE_UNSUPPORTED")
	return GeoProviderBaseScript.success(_surface_values)


func sample_volume(_context: Dictionary, _query: Dictionary, _input_fields: Dictionary) -> Dictionary:
	if not _volume_supported:
		return GeoProviderBaseScript.failure("STUB_VOLUME_UNSUPPORTED")
	return GeoProviderBaseScript.success(_volume_values)
