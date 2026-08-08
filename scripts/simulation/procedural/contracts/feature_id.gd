extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const FeatureTypeScript = preload("res://scripts/simulation/procedural/contracts/feature_type.gd")

const PREFIX: String = "world-feature/"
const STABLE_KEY_PREFIX: String = "feature-key/"


static func derive(
	body_id: String,
	feature_type: String,
	seed: int,
	generator_version: String,
	stable_key: String
) -> Dictionary:
	if not GeoUtilsScript.is_canonical_id(body_id, 2):
		return GeoUtilsScript.failure("INVALID_FEATURE_BODY_ID")
	var type_validation: Dictionary = FeatureTypeScript.validate(feature_type)
	if not bool(type_validation.get("success", false)):
		return type_validation
	if not GeoUtilsScript.is_json_integer(seed):
		return GeoUtilsScript.failure("INVALID_FEATURE_SEED")
	if not GeoUtilsScript.is_semantic_version(generator_version):
		return GeoUtilsScript.failure("INVALID_FEATURE_GENERATOR_VERSION")
	if not GeoUtilsScript.is_canonical_id(stable_key, 2) or not stable_key.begins_with(STABLE_KEY_PREFIX):
		return GeoUtilsScript.failure("INVALID_FEATURE_STABLE_KEY")
	var identity_payload: Dictionary = {
		"body_id": body_id,
		"feature_type": feature_type,
		"seed": seed,
		"generator_version": generator_version,
		"stable_key": stable_key,
	}
	var identity_hash: String = GeoUtilsScript.payload_hash(identity_payload)
	var type_slug: String = feature_type.get_slice("/", feature_type.get_slice_count("/") - 1)
	var feature_id: String = "%s%s/%s" % [PREFIX, type_slug, identity_hash]
	return GeoUtilsScript.success({
		"feature_id": feature_id,
		"identity_hash": identity_hash,
	})


static func validate(value) -> Dictionary:
	if not GeoUtilsScript.is_canonical_id(value, 3):
		return GeoUtilsScript.failure("INVALID_FEATURE_ID")
	var text: String = String(value)
	if not text.begins_with(PREFIX):
		return GeoUtilsScript.failure("INVALID_FEATURE_ID_NAMESPACE")
	var parts: PackedStringArray = text.split("/", true)
	if parts.size() != 3 or not GeoUtilsScript.is_lower_hex_64(parts[2]):
		return GeoUtilsScript.failure("INVALID_FEATURE_ID_FORMAT")
	return GeoUtilsScript.success()
