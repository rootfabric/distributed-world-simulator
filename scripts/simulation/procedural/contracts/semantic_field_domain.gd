extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")

const BODY_SURFACE_POINT: String = "semantic-field-domain/body-surface-point"
const BODY_VOLUME_POINT: String = "semantic-field-domain/body-volume-point"
const SUPPORTED: Array[String] = [BODY_SURFACE_POINT, BODY_VOLUME_POINT]


static func validate(value) -> Dictionary:
	if typeof(value) != TYPE_STRING or String(value) not in SUPPORTED:
		return GeoUtilsScript.failure("UNSUPPORTED_SEMANTIC_FIELD_DOMAIN")
	return GeoUtilsScript.success()
