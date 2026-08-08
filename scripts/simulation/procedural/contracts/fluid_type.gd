extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")

const PREFIX: String = "fluid-type/"

const WATER: String = "fluid-type/water"
const LAVA: String = "fluid-type/lava"
const METHANE: String = "fluid-type/methane"
const AMMONIA: String = "fluid-type/ammonia"


static func validate(value) -> Dictionary:
	if not GeoUtilsScript.is_canonical_id(value, 2):
		return GeoUtilsScript.failure("INVALID_FLUID_TYPE")
	var text: String = String(value)
	if not text.begins_with(PREFIX) or text.length() <= PREFIX.length():
		return GeoUtilsScript.failure("INVALID_FLUID_TYPE_NAMESPACE")
	return GeoUtilsScript.success()
