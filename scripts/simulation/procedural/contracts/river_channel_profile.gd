extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const FluidRegionIdScript = preload("res://scripts/simulation/procedural/contracts/fluid_region_id.gd")

const SCHEMA: String = "planet_simulator.river_channel_profile.v1"
const PREFIX: String = "river-channel-profile/"
const SAMPLE_FIELDS: Array[String] = ["t", "width_m", "depth_m", "bank_width_m"]
const FIELDS: Array[String] = [
	"schema",
	"profile_id",
	"fluid_region_id",
	"samples",
	"attributes",
	"checksum",
]


static func sample(t: float, width_m: float, depth_m: float, bank_width_m: float) -> Dictionary:
	return {
		"t": t,
		"width_m": width_m,
		"depth_m": depth_m,
		"bank_width_m": bank_width_m,
	}


static func create(fluid_region_id: String, samples: Array, attributes: Dictionary = {}) -> Dictionary:
	var canonical_samples: Array = []
	var sortable: bool = true
	for raw_sample in samples:
		if raw_sample is Dictionary:
			canonical_samples.append(Dictionary(raw_sample).duplicate(true))
		else:
			sortable = false
			canonical_samples.append(raw_sample)
	if sortable:
		canonical_samples.sort_custom(func(a, b): return float(a.get("t", 0.0)) < float(b.get("t", 0.0)))
	var value: Dictionary = {
		"schema": SCHEMA,
		"profile_id": _derive_id(fluid_region_id),
		"fluid_region_id": fluid_region_id,
		"samples": canonical_samples,
		"attributes": attributes.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_RIVER_CHANNEL_PROFILE_SCHEMA")
	var region_validation: Dictionary = FluidRegionIdScript.validate(value.get("fluid_region_id"))
	if not bool(region_validation.get("success", false)):
		return region_validation
	if typeof(value.get("profile_id")) != TYPE_STRING or String(value["profile_id"]) != _derive_id(String(value["fluid_region_id"])):
		return GeoUtilsScript.failure("RIVER_CHANNEL_PROFILE_IDENTITY_MISMATCH")
	if typeof(value.get("samples")) != TYPE_ARRAY or value["samples"].size() < 2:
		return GeoUtilsScript.failure("INVALID_RIVER_CHANNEL_SAMPLES")
	var previous_t: float = -1.0
	for index in range(value["samples"].size()):
		var raw_sample = value["samples"][index]
		if typeof(raw_sample) != TYPE_DICTIONARY:
			return GeoUtilsScript.failure("INVALID_RIVER_CHANNEL_SAMPLE", {"index": index})
		var exact_sample: Dictionary = GeoUtilsScript.validate_exact_fields(raw_sample, SAMPLE_FIELDS)
		if not bool(exact_sample.get("success", false)):
			return GeoUtilsScript.failure("INVALID_RIVER_CHANNEL_SAMPLE", {"index": index, "cause": exact_sample.get("error_code", "")})
		if not GeoUtilsScript.is_ratio(raw_sample.get("t")):
			return GeoUtilsScript.failure("INVALID_RIVER_CHANNEL_SAMPLE_T", {"index": index})
		var t: float = float(raw_sample["t"])
		if index > 0 and t <= previous_t:
			return GeoUtilsScript.failure("RIVER_CHANNEL_SAMPLES_NOT_SORTED_UNIQUE", {"index": index})
		if not GeoUtilsScript.is_positive_number(raw_sample.get("width_m")):
			return GeoUtilsScript.failure("INVALID_RIVER_CHANNEL_WIDTH", {"index": index})
		if not GeoUtilsScript.is_non_negative_number(raw_sample.get("depth_m")):
			return GeoUtilsScript.failure("INVALID_RIVER_CHANNEL_DEPTH", {"index": index})
		if not GeoUtilsScript.is_non_negative_number(raw_sample.get("bank_width_m")):
			return GeoUtilsScript.failure("INVALID_RIVER_CHANNEL_BANK_WIDTH", {"index": index})
		previous_t = t
	if not GeoUtilsScript.approximately_equal(float(value["samples"][0]["t"]), 0.0):
		return GeoUtilsScript.failure("RIVER_CHANNEL_PROFILE_MISSING_START_SAMPLE")
	if not GeoUtilsScript.approximately_equal(float(value["samples"][value["samples"].size() - 1]["t"]), 1.0):
		return GeoUtilsScript.failure("RIVER_CHANNEL_PROFILE_MISSING_END_SAMPLE")
	if typeof(value.get("attributes")) != TYPE_DICTIONARY:
		return GeoUtilsScript.failure("INVALID_RIVER_CHANNEL_ATTRIBUTES")
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.river_channel_profile")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return GeoUtilsScript.normalize(value, validate)


static func _derive_id(fluid_region_id: String) -> String:
	if not bool(FluidRegionIdScript.validate(fluid_region_id).get("success", false)):
		return ""
	return "%s%s" % [PREFIX, GeoUtilsScript.payload_hash({"fluid_region_id": fluid_region_id})]
