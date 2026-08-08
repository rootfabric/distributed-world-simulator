extends RefCounted

const QUERY_SURFACE: String = "SURFACE"
const QUERY_VOLUME: String = "VOLUME"


func get_descriptor() -> Dictionary:
	return {}


func supports_query_kind(_query_kind: String) -> bool:
	return false


func sample_surface(_context: Dictionary, _query: Dictionary, _input_fields: Dictionary) -> Dictionary:
	return failure("GEO_PROVIDER_SURFACE_UNSUPPORTED")


func sample_volume(_context: Dictionary, _query: Dictionary, _input_fields: Dictionary) -> Dictionary:
	return failure("GEO_PROVIDER_VOLUME_UNSUPPORTED")


static func success(values: Dictionary) -> Dictionary:
	return {
		"success": true,
		"error_code": "",
		"details": {"values": values.duplicate(true)},
	}


static func failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": code,
		"details": details.duplicate(true),
	}
