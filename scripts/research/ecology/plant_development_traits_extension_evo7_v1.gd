extends RefCounted

## ECO.EVO7 FFF1 - additive heritable development trait extension (versioned successor data).
## Adds the five functional axes proven as semantic gaps by FFF0
## (docs/plans/ECO_EVO7_FFF0_CONTRACT_MAPPING_RU.md section 9).
## This contract NEVER replaces PlantDevelopmentTraits v1 (PH0): it rides alongside it.
## Research-only derived data: presentation-neutral, side-effect-free, no writes.

const SCHEMA := "distributed_world_simulator.ecology.plant_development_traits_extension_evo7.v1"
const VERSION := "1.0.0"
const DEFAULT_EXTENSION_ID := "plant-development-extension/evo7-baseline"

## Axis semantics (frozen for R1, see FFF1 checkpoint design brief):
##   foliage_density       - crown density potential [0.05..1]
##   leaf_economics_proxy  - fast-slow leaf economics [0=conservative .. 1=acquisitive/fast]
##   structural_investment - wood density proxy [0..1]
##   root_spread_m         - lateral root extent, meters [0.05..30] (mirrors PH0 crown_spread bounds)
##   root_shoot_ratio      - heritable biomass allocation target [0.15..0.85]
const TRAIT_NAMES: Array[String] = [
	"foliage_density",
	"leaf_economics_proxy",
	"structural_investment",
	"root_spread_m",
	"root_shoot_ratio",
]
const FIELD_NAMES: Array[String] = [
	"schema", "version", "extension_id",
	"foliage_density", "leaf_economics_proxy", "structural_investment",
	"root_spread_m", "root_shoot_ratio",
	"checksum",
]
const BOUNDS := {
	"foliage_density": [0.05, 1.0],
	"leaf_economics_proxy": [0.0, 1.0],
	"structural_investment": [0.0, 1.0],
	"root_spread_m": [0.05, 30.0],
	"root_shoot_ratio": [0.15, 0.85],
}

static func create_default() -> Dictionary:
	return create(DEFAULT_EXTENSION_ID, 0.45, 0.50, 0.40, 1.60, 0.50)

static func create(
	extension_id: String,
	foliage_density: float,
	leaf_economics_proxy: float,
	structural_investment: float,
	root_spread_m: float,
	root_shoot_ratio: float
) -> Dictionary:
	var traits := {
		"schema": SCHEMA,
		"version": VERSION,
		"extension_id": extension_id,
		"foliage_density": foliage_density,
		"leaf_economics_proxy": leaf_economics_proxy,
		"structural_investment": structural_investment,
		"root_spread_m": root_spread_m,
		"root_shoot_ratio": root_shoot_ratio,
	}
	traits["checksum"] = compute_checksum(traits)
	return traits

static func with_trait(source: Dictionary, trait_name: String, value: float, suffix: String = "") -> Dictionary:
	if not TRAIT_NAMES.has(trait_name):
		return {}
	if not bool(validate(source).get("success", false)):
		return {}
	var copy := source.duplicate(true)
	copy[trait_name] = value
	copy["extension_id"] = String(source["extension_id"]) + suffix
	copy["checksum"] = compute_checksum(copy)
	return copy

static func validate(traits: Dictionary) -> Dictionary:
	if traits.keys().size() != FIELD_NAMES.size():
		return _failure("ECO_PLANT_DEV_TRAITS_EXT_FIELD_COUNT_MISMATCH")
	for field_name in FIELD_NAMES:
		if not traits.has(field_name):
			return _failure("ECO_PLANT_DEV_TRAITS_EXT_MISSING_FIELD", {"field": field_name})
	for field_name in traits.keys():
		if not String(field_name) in FIELD_NAMES:
			return _failure("ECO_PLANT_DEV_TRAITS_EXT_UNEXPECTED_FIELD", {"field": String(field_name)})
	if String(traits.get("schema", "")) != SCHEMA or String(traits.get("version", "")) != VERSION:
		return _failure("ECO_PLANT_DEV_TRAITS_EXT_SCHEMA_VERSION_MISMATCH")
	var extension_id := String(traits.get("extension_id", ""))
	if extension_id.is_empty() or extension_id != extension_id.strip_edges():
		return _failure("ECO_PLANT_DEV_TRAITS_EXT_INVALID_ID")
	for name in TRAIT_NAMES:
		var value = traits.get(name)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			return _failure("ECO_PLANT_DEV_TRAITS_EXT_NON_FINITE", {"field": name})
		var bounds: Array = BOUNDS[name]
		if float(value) < float(bounds[0]) or float(value) > float(bounds[1]):
			return _failure("ECO_PLANT_DEV_TRAITS_EXT_OUT_OF_RANGE", {"field": name})
	if String(traits.get("checksum", "")) != compute_checksum(traits):
		return _failure("ECO_PLANT_DEV_TRAITS_EXT_CHECKSUM_MISMATCH")
	return _success()

static func compute_checksum(traits: Dictionary) -> String:
	var tokens := PackedStringArray([SCHEMA, VERSION, String(traits.get("extension_id", ""))])
	for name in TRAIT_NAMES:
		tokens.append("%.9f" % float(traits.get(name, 0.0)))
	return "|".join(tokens).sha256_text()

static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
