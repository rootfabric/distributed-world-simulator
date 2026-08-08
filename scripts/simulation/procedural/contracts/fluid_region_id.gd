extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")

const PREFIX: String = "fluid-region/"
const STABLE_KEY_PREFIX: String = "fluid-region-key/"
const FLUID_TYPE_PREFIX: String = "fluid/"


static func derive(
	body_id: String,
	fluid_type_id: String,
	seed: int,
	generator_version: String,
	stable_key: String
) -> Dictionary:
	if not GeoUtilsScript.is_canonical_id(body_id, 2):
		return GeoUtilsScript.failure("INVALID_FLUID_REGION_BODY_ID")
	if not GeoUtilsScript.is_canonical_id(fluid_type_id, 2) or not fluid_type_id.begins_with(FLUID_TYPE_PREFIX):
		return GeoUtilsScript.failure("INVALID_FLUID_TYPE_ID")
	if not GeoUtilsScript.is_json_integer(seed):
		return GeoUtilsScript.failure("INVALID_FLUID_REGION_SEED")
	if not GeoUtilsScript.is_semantic_version(generator_version):
		return GeoUtilsScript.failure("INVALID_FLUID_REGION_GENERATOR_VERSION")
	if not GeoUtilsScript.is_canonical_id(stable_key, 2) or not stable_key.begins_with(STABLE_KEY_PREFIX):
		return GeoUtilsScript.failure("INVALID_FLUID_REGION_STABLE_KEY")
	var identity_payload: Dictionary = {
		"body_id": body_id,
		"fluid_type_id": fluid_type_id,
		"seed": seed,
		"generator_version": generator_version,
		"stable_key": stable_key,
	}
	var identity_hash: String = GeoUtilsScript.payload_hash(identity_payload)
	var fluid_slug: String = fluid_type_id.get_slice("/", fluid_type_id.get_slice_count("/") - 1)
	return GeoUtilsScript.success({
		"fluid_region_id": "%s%s/%s" % [PREFIX, fluid_slug, identity_hash],
		"identity_hash": identity_hash,
	})


static func validate(value) -> Dictionary:
	if not GeoUtilsScript.is_canonical_id(value, 3):
		return GeoUtilsScript.failure("INVALID_FLUID_REGION_ID")
	var text: String = String(value)
	if not text.begins_with(PREFIX):
		return GeoUtilsScript.failure("INVALID_FLUID_REGION_ID_NAMESPACE")
	var parts: PackedStringArray = text.split("/", true)
	if parts.size() != 3 or not GeoUtilsScript.is_lower_hex_64(parts[2]):
		return GeoUtilsScript.failure("INVALID_FLUID_REGION_ID_FORMAT")
	return GeoUtilsScript.success()
