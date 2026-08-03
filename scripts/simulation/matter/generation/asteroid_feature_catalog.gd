extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const FieldScript = preload("res://scripts/simulation/matter/generation/deterministic_field_3d.gd")
const ProfileScript = preload("res://scripts/simulation/matter/generation/fixed_seed_asteroid_profile.gd")

const SCHEMA: String = "planet_simulator.asteroid_feature_catalog.v1"
const FEATURE_KINDS: Array[String] = [
	"ADD_LOBE",
	"IMPACT_CRATER",
	"NATURAL_VOID",
	"ORE_LENS",
	"ICE_POCKET",
]
const FIELDS: Array[String] = [
	"schema",
	"generator_id",
	"generator_version",
	"generator_seed",
	"features",
	"catalog_hash",
	"checksum",
]
const FEATURE_FIELDS: Array[String] = [
	"feature_id",
	"feature_kind",
	"center_m",
	"radii_m",
	"amplitude_m",
	"material_id",
	"influence_ratio",
]


static func create(profile: Dictionary) -> Dictionary:
	if not bool(ProfileScript.validate(profile).get("success", false)):
		return {}
	var seed: int = int(profile["generator_seed"])
	var features: Array = [
		_feature(
			"matter-feature/asteroid-mw1/lobe-a",
			"ADD_LOBE",
			_perturbed_vector(Vector3(775.0, 115.0, -165.0), seed, 10, 42.0),
			Vector3(365.0, 305.0, 295.0),
			0.0,
			"",
			1.0
		),
		_feature(
			"matter-feature/asteroid-mw1/lobe-b",
			"ADD_LOBE",
			_perturbed_vector(Vector3(-705.0, -225.0, 185.0), seed, 20, 38.0),
			Vector3(325.0, 285.0, 345.0),
			0.0,
			"",
			1.0
		),
		_feature(
			"matter-feature/asteroid-mw1/crater-a",
			"IMPACT_CRATER",
			_perturbed_vector(Vector3(930.0, 245.0, 125.0), seed, 30, 28.0),
			Vector3(215.0, 175.0, 135.0),
			-118.0,
			"",
			1.0
		),
		_feature(
			"matter-feature/asteroid-mw1/crater-b",
			"IMPACT_CRATER",
			_perturbed_vector(Vector3(-455.0, -815.0, 165.0), seed, 40, 26.0),
			Vector3(165.0, 195.0, 125.0),
			-96.0,
			"",
			1.0
		),
		_feature(
			"matter-feature/asteroid-mw1/natural-void-a",
			"NATURAL_VOID",
			_perturbed_vector(Vector3(-185.0, 155.0, 95.0), seed, 50, 32.0),
			Vector3(150.0, 112.0, 128.0),
			0.0,
			"",
			1.0
		),
		_feature(
			"matter-feature/asteroid-mw1/ore-lens-a",
			"ORE_LENS",
			_perturbed_vector(Vector3(265.0, -185.0, 175.0), seed, 60, 45.0),
			Vector3(305.0, 205.0, 245.0),
			0.0,
			"matter/iron-nickel-ore",
			float(profile["ore_max_mass_fraction"])
		),
		_feature(
			"matter-feature/asteroid-mw1/ice-pocket-a",
			"ICE_POCKET",
			_perturbed_vector(Vector3(-355.0, 235.0, -135.0), seed, 70, 36.0),
			Vector3(215.0, 165.0, 195.0),
			0.0,
			"matter/water-ice",
			float(profile["ice_max_mass_fraction"])
		),
	]
	features.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("feature_id", "")) < String(b.get("feature_id", ""))
	)
	var value: Dictionary = {
		"schema": SCHEMA,
		"generator_id": String(profile["generator_id"]),
		"generator_version": String(profile["generator_version"]),
		"generator_seed": seed,
		"features": features,
		"catalog_hash": MatterUtilsScript.payload_hash(features),
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_ASTEROID_FEATURE_CATALOG_SCHEMA")
	if String(value.get("generator_id", "")) != ProfileScript.GENERATOR_ID:
		return MatterUtilsScript.failure("INVALID_ASTEROID_FEATURE_GENERATOR_ID")
	if String(value.get("generator_version", "")) != ProfileScript.GENERATOR_VERSION:
		return MatterUtilsScript.failure("INVALID_ASTEROID_FEATURE_GENERATOR_VERSION")
	if not MatterUtilsScript.is_json_integer(value.get("generator_seed")):
		return MatterUtilsScript.failure("INVALID_ASTEROID_FEATURE_SEED")
	if typeof(value.get("features")) != TYPE_ARRAY or value["features"].is_empty():
		return MatterUtilsScript.failure("EMPTY_ASTEROID_FEATURE_CATALOG")
	var previous_id: String = ""
	for index in range(value["features"].size()):
		var feature = value["features"][index]
		if typeof(feature) != TYPE_DICTIONARY:
			return MatterUtilsScript.failure("INVALID_ASTEROID_FEATURE", {"index": index})
		var feature_exact: Dictionary = MatterUtilsScript.validate_exact_fields(feature, FEATURE_FIELDS)
		if not bool(feature_exact.get("success", false)):
			return MatterUtilsScript.failure("INVALID_ASTEROID_FEATURE_FIELDS", {"index": index})
		var feature_id: String = String(feature.get("feature_id", ""))
		if not MatterUtilsScript.is_canonical_id(feature_id, 3):
			return MatterUtilsScript.failure("INVALID_ASTEROID_FEATURE_ID", {"index": index})
		if index > 0 and feature_id <= previous_id:
			return MatterUtilsScript.failure("ASTEROID_FEATURES_NOT_SORTED_UNIQUE", {"index": index})
		if typeof(feature.get("feature_kind")) != TYPE_STRING \
			or not String(feature["feature_kind"]) in FEATURE_KINDS:
			return MatterUtilsScript.failure("INVALID_ASTEROID_FEATURE_KIND", {"index": index})
		if not MatterUtilsScript.is_vector3_array(feature.get("center_m")) \
			or not _is_positive_vector3(feature.get("radii_m")):
			return MatterUtilsScript.failure("INVALID_ASTEROID_FEATURE_SHAPE", {"index": index})
		if not MatterUtilsScript.is_finite_number(feature.get("amplitude_m")):
			return MatterUtilsScript.failure("INVALID_ASTEROID_FEATURE_AMPLITUDE", {"index": index})
		var material_id = feature.get("material_id")
		if typeof(material_id) != TYPE_STRING:
			return MatterUtilsScript.failure("INVALID_ASTEROID_FEATURE_MATERIAL", {"index": index})
		if not String(material_id).is_empty() \
			and not MatterUtilsScript.is_canonical_id(material_id, 2):
			return MatterUtilsScript.failure("INVALID_ASTEROID_FEATURE_MATERIAL", {"index": index})
		if not MatterUtilsScript.is_ratio(feature.get("influence_ratio")):
			return MatterUtilsScript.failure("INVALID_ASTEROID_FEATURE_INFLUENCE", {"index": index})
		previous_id = feature_id
	if not MatterUtilsScript.is_lower_hex_64(value.get("catalog_hash")) \
		or String(value["catalog_hash"]) != MatterUtilsScript.payload_hash(value["features"]):
		return MatterUtilsScript.failure("ASTEROID_FEATURE_CATALOG_HASH_MISMATCH")
	var safe: Dictionary = MatterUtilsScript.validate_json_safe(value, "$.asteroid_feature_catalog")
	if not bool(safe.get("success", false)):
		return safe
	return MatterUtilsScript.validate_checksum(value)


static func feature_by_id(catalog: Dictionary, feature_id: String) -> Dictionary:
	if not bool(validate(catalog).get("success", false)):
		return {}
	for feature in catalog["features"]:
		if String(feature["feature_id"]) == feature_id:
			return Dictionary(feature).duplicate(true)
	return {}


static func features_of_kind(catalog: Dictionary, feature_kind: String) -> Array:
	var result: Array = []
	if not bool(validate(catalog).get("success", false)):
		return result
	for feature in catalog["features"]:
		if String(feature["feature_kind"]) == feature_kind:
			result.append(Dictionary(feature).duplicate(true))
	return result


static func _feature(
	feature_id: String,
	feature_kind: String,
	center_m: Vector3,
	radii_m: Vector3,
	amplitude_m: float,
	material_id: String,
	influence_ratio: float
) -> Dictionary:
	return {
		"feature_id": feature_id,
		"feature_kind": feature_kind,
		"center_m": [center_m.x, center_m.y, center_m.z],
		"radii_m": [radii_m.x, radii_m.y, radii_m.z],
		"amplitude_m": amplitude_m,
		"material_id": material_id,
		"influence_ratio": influence_ratio,
	}


static func _perturbed_vector(base: Vector3, seed: int, channel: int, amplitude_m: float) -> Vector3:
	return base + Vector3(
		FieldScript.signed_hash(0, 0, 0, seed, channel),
		FieldScript.signed_hash(0, 0, 0, seed, channel + 1),
		FieldScript.signed_hash(0, 0, 0, seed, channel + 2)
	) * amplitude_m


static func _is_positive_vector3(value) -> bool:
	if not MatterUtilsScript.is_vector3_array(value):
		return false
	for component in value:
		if float(component) <= 0.0:
			return false
	return true
