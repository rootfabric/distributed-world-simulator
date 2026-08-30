extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")

const SCHEMA: String = "planet_simulator.moon_surface_feature_catalog.v1"
const CATALOG_ID: String = "matter-feature-catalog/moon-p7-bubble"
const CATALOG_VERSION: String = "1.0.0"
const FIELDS: Array[String] = [
	"schema",
	"catalog_id",
	"catalog_version",
	"generator_seed",
	"features",
	"feature_hash",
	"checksum",
]


static func create(generator_seed: int, features: Array = []) -> Dictionary:
	var normalized: Array = []
	for feature in features:
		if typeof(feature) != TYPE_DICTIONARY:
			continue
		var value: Dictionary = Dictionary(feature).duplicate(true)
		normalized.append(value)
	normalized.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("feature_id", "")) < String(b.get("feature_id", ""))
	)
	var value: Dictionary = {
		"schema": SCHEMA,
		"catalog_id": CATALOG_ID,
		"catalog_version": CATALOG_VERSION,
		"generator_seed": generator_seed,
		"features": normalized,
		"feature_hash": MatterUtilsScript.payload_hash(normalized),
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func default_catalog(generator_seed: int) -> Dictionary:
	return create(generator_seed, [])


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if String(value.get("schema", "")) != SCHEMA 		or String(value.get("catalog_id", "")) != CATALOG_ID 		or String(value.get("catalog_version", "")) != CATALOG_VERSION:
		return MatterUtilsScript.failure("INVALID_MOON_FEATURE_CATALOG_IDENTITY")
	if not MatterUtilsScript.is_json_integer(value.get("generator_seed")):
		return MatterUtilsScript.failure("INVALID_MOON_FEATURE_CATALOG_SEED")
	if typeof(value.get("features")) != TYPE_ARRAY:
		return MatterUtilsScript.failure("INVALID_MOON_FEATURE_CATALOG_FEATURES")
	var previous_id := ""
	for index in range(value["features"].size()):
		var entry = value["features"][index]
		if typeof(entry) != TYPE_DICTIONARY:
			return MatterUtilsScript.failure("INVALID_MOON_FEATURE", {"index": index})
		var feature_id := String(entry.get("feature_id", ""))
		if not MatterUtilsScript.is_canonical_id(feature_id, 2):
			return MatterUtilsScript.failure("INVALID_MOON_FEATURE_ID", {"index": index})
		if index > 0 and feature_id <= previous_id:
			return MatterUtilsScript.failure("MOON_FEATURE_CATALOG_NOT_SORTED_UNIQUE", {"index": index})
		previous_id = feature_id
	if not MatterUtilsScript.is_lower_hex_64(value.get("feature_hash")) 		or String(value["feature_hash"]) != MatterUtilsScript.payload_hash(value["features"]):
		return MatterUtilsScript.failure("MOON_FEATURE_CATALOG_HASH_MISMATCH")
	var safe := MatterUtilsScript.validate_json_safe(value, "$.moon_surface_feature_catalog")
	if not bool(safe.get("success", false)):
		return safe
	return MatterUtilsScript.validate_checksum(value)
