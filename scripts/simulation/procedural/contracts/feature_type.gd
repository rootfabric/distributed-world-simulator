extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")

const PREFIX: String = "feature-type/"

const VALLEY: String = "feature-type/valley"
const RIVER: String = "feature-type/river"
const CRATER: String = "feature-type/crater"
const FAULT: String = "feature-type/fault"
const CAVE_SYSTEM: String = "feature-type/cave-system"
const ORE_VEIN: String = "feature-type/ore-vein"
const FLOATING_ISLAND: String = "feature-type/floating-island"
const VOLCANIC_CONDUIT: String = "feature-type/volcanic-conduit"
const REEF: String = "feature-type/reef"
const STORM_CELL: String = "feature-type/storm-cell"
const ASTEROID_CLUSTER: String = "feature-type/asteroid-cluster"
const ARTIFICIAL_RUIN_ZONE: String = "feature-type/artificial-ruin-zone"


static func validate(value) -> Dictionary:
	if not GeoUtilsScript.is_canonical_id(value, 2):
		return GeoUtilsScript.failure("INVALID_FEATURE_TYPE")
	var text: String = String(value)
	if not text.begins_with(PREFIX) or text.length() <= PREFIX.length():
		return GeoUtilsScript.failure("INVALID_FEATURE_TYPE_NAMESPACE")
	return GeoUtilsScript.success()
