extends "res://scripts/simulation/procedural/providers/geo_provider.gd"

const GeoProviderBaseScript = preload("res://scripts/simulation/procedural/providers/geo_provider.gd")

var _descriptor: Dictionary
var _outputs: Dictionary


func _init(descriptor: Dictionary, outputs: Dictionary = {}) -> void:
	_descriptor = descriptor.duplicate(true)
	_outputs = outputs.duplicate(true)


func get_descriptor() -> Dictionary:
	return _descriptor.duplicate(true)


func supports_query_kind(query_kind: String) -> bool:
	return query_kind == GeoProviderBaseScript.QUERY_SURFACE


func sample_surface(_context: Dictionary, _query: Dictionary, _input_fields: Dictionary) -> Dictionary:
	return GeoProviderBaseScript.success(_outputs)
