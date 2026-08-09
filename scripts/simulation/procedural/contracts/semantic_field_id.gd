extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")

const PREFIX: String = "geo/"


static func validate(value) -> Dictionary:
	if not GeoUtilsScript.is_canonical_id(value, 2):
		return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_ID")
	var text: String = String(value)
	if not text.begins_with(PREFIX) or text.length() <= PREFIX.length():
		return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_ID_NAMESPACE")
	return GeoUtilsScript.success()


static func normalize_many(values: Array) -> Dictionary:
	var normalized: Array = []
	var seen: Dictionary = {}
	for raw in values:
		var validation: Dictionary = validate(raw)
		if not bool(validation.get("success", false)):
			return validation
		seen[String(raw)] = true
	normalized = seen.keys()
	normalized.sort()
	if normalized.is_empty():
		return GeoUtilsScript.failure("EMPTY_SEMANTIC_FIELD_ID_SET")
	return GeoUtilsScript.success({"field_ids": normalized})
