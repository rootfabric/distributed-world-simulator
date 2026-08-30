extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const BodyScript = preload("res://scripts/simulation/matter/contracts/matter_body_definition.gd")
const SampleScript = preload("res://scripts/simulation/matter/contracts/matter_sample.gd")
const CompositionScript = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const MaterialCatalogScript = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const FeatureCatalogScript = preload(
	"res://scripts/simulation/matter/generation/moon_surface_feature_catalog.gd"
)

const PROFILE_SCHEMA: String = "planet_simulator.moon_geology_profile.v1"
const GENERATOR_ID: String = "matter-generator/moon-p7-bubble"
const GENERATOR_VERSION: String = "1.0.0"
const BODY_ID: String = "body/moon"
const BODY_FRAME_ID: String = "body/moon/fixed"
const REFERENCE_RADIUS_M: float = 1737400.0
const DEFAULT_SEED: int = 20260724
const PROFILE_FIELDS: Array[String] = [
	"schema",
	"generator_id",
	"generator_version",
	"generator_seed",
	"reference_radius_m",
	"canonical_surface_radius_m",
	"regolith_loose_depth_m",
	"regolith_compacted_depth_m",
	"fractured_basalt_depth_m",
	"surface_temperature_k",
	"deep_temperature_k",
	"checksum",
]


static func create_profile(data: Dictionary = {}) -> Dictionary:
	var value: Dictionary = {
		"schema": PROFILE_SCHEMA,
		"generator_id": GENERATOR_ID,
		"generator_version": GENERATOR_VERSION,
		"generator_seed": int(data.get("generator_seed", DEFAULT_SEED)),
		"reference_radius_m": float(data.get("reference_radius_m", REFERENCE_RADIUS_M)),
		"canonical_surface_radius_m": float(data.get(
			"canonical_surface_radius_m", REFERENCE_RADIUS_M
		)),
		"regolith_loose_depth_m": float(data.get("regolith_loose_depth_m", 2.0)),
		"regolith_compacted_depth_m": float(data.get("regolith_compacted_depth_m", 8.0)),
		"fractured_basalt_depth_m": float(data.get("fractured_basalt_depth_m", 28.0)),
		"surface_temperature_k": float(data.get("surface_temperature_k", 120.0)),
		"deep_temperature_k": float(data.get("deep_temperature_k", 240.0)),
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func validate_profile(value: Dictionary) -> Dictionary:
	var exact := MatterUtilsScript.validate_exact_fields(value, PROFILE_FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if String(value.get("schema", "")) != PROFILE_SCHEMA 		or String(value.get("generator_id", "")) != GENERATOR_ID 		or String(value.get("generator_version", "")) != GENERATOR_VERSION:
		return MatterUtilsScript.failure("INVALID_MOON_GEOLOGY_PROFILE_IDENTITY")
	if not MatterUtilsScript.is_json_integer(value.get("generator_seed")):
		return MatterUtilsScript.failure("INVALID_MOON_GEOLOGY_SEED")
	for field in [
		"reference_radius_m",
		"canonical_surface_radius_m",
		"regolith_loose_depth_m",
		"regolith_compacted_depth_m",
		"fractured_basalt_depth_m",
		"surface_temperature_k",
		"deep_temperature_k",
	]:
		if not MatterUtilsScript.is_positive_number(value.get(field)):
			return MatterUtilsScript.failure("INVALID_MOON_GEOLOGY_PROFILE_VALUE", {"field": field})
	if float(value["regolith_loose_depth_m"]) >= float(value["regolith_compacted_depth_m"]) 		or float(value["regolith_compacted_depth_m"]) >= float(value["fractured_basalt_depth_m"]):
		return MatterUtilsScript.failure("INVALID_MOON_GEOLOGY_LAYER_ORDER")
	if absf(float(value["reference_radius_m"]) - REFERENCE_RADIUS_M) > 0.001:
		return MatterUtilsScript.failure("MOON_REFERENCE_RADIUS_MISMATCH")
	var safe := MatterUtilsScript.validate_json_safe(value, "$.moon_geology_profile")
	if not bool(safe.get("success", false)):
		return safe
	return MatterUtilsScript.validate_checksum(value)


static func default_body_definition(
	material_catalog: Dictionary,
	profile: Dictionary,
	feature_catalog: Dictionary
) -> Dictionary:
	if not bool(MaterialCatalogScript.validate(material_catalog).get("success", false)) 		or not bool(validate_profile(profile).get("success", false)) 		or not bool(FeatureCatalogScript.validate(feature_catalog).get("success", false)):
		return {}
	return BodyScript.create({
		"body_id": BODY_ID,
		"body_kind": "MOON",
		"body_frame_id": BODY_FRAME_ID,
		"generator_id": GENERATOR_ID,
		"generator_version": GENERATOR_VERSION,
		"generator_seed": int(profile["generator_seed"]),
		"reference_radius_m": REFERENCE_RADIUS_M,
		"default_material_id": "matter/regolith-loose",
		"material_catalog_id": material_catalog["catalog_id"],
		"material_catalog_hash": material_catalog["catalog_hash"],
		"metadata": {
			"p7_bounded_bubble": true,
			"canonical_surface_radius_m": float(profile["canonical_surface_radius_m"]),
			"moon_feature_hash": String(feature_catalog["feature_hash"]),
		},
	})


static func validate_configuration(
	body: Dictionary,
	material_catalog: Dictionary,
	profile: Dictionary,
	feature_catalog: Dictionary
) -> Dictionary:
	if not bool(BodyScript.validate(body).get("success", false)):
		return MatterUtilsScript.failure("INVALID_MOON_MATTER_BODY")
	if not bool(MaterialCatalogScript.validate(material_catalog).get("success", false)):
		return MatterUtilsScript.failure("INVALID_MOON_MATERIAL_CATALOG")
	if not bool(validate_profile(profile).get("success", false)):
		return MatterUtilsScript.failure("INVALID_MOON_GEOLOGY_PROFILE")
	if not bool(FeatureCatalogScript.validate(feature_catalog).get("success", false)):
		return MatterUtilsScript.failure("INVALID_MOON_FEATURE_CATALOG")
	if String(body["body_id"]) != BODY_ID 		or String(body["body_frame_id"]) != BODY_FRAME_ID 		or String(body["body_kind"]) != "MOON":
		return MatterUtilsScript.failure("MOON_BODY_IDENTITY_MISMATCH")
	if String(body["generator_id"]) != GENERATOR_ID 		or String(body["generator_version"]) != GENERATOR_VERSION 		or int(body["generator_seed"]) != int(profile["generator_seed"]):
		return MatterUtilsScript.failure("MOON_GENERATOR_IDENTITY_MISMATCH")
	if String(body["material_catalog_id"]) != String(material_catalog["catalog_id"]) 		or String(body["material_catalog_hash"]) != String(material_catalog["catalog_hash"]):
		return MatterUtilsScript.failure("MOON_MATERIAL_CATALOG_BINDING_MISMATCH")
	if int(feature_catalog["generator_seed"]) != int(profile["generator_seed"]):
		return MatterUtilsScript.failure("MOON_FEATURE_CATALOG_SEED_MISMATCH")
	return MatterUtilsScript.success()


static func sample(
	body: Dictionary,
	material_catalog: Dictionary,
	profile: Dictionary,
	feature_catalog: Dictionary,
	body_fixed_position_m: Vector3
) -> Dictionary:
	if not bool(validate_configuration(
		body, material_catalog, profile, feature_catalog
	).get("success", false)):
		return {}
	return sample_validated(material_catalog, profile, feature_catalog, body_fixed_position_m)


static func sample_validated(
	material_catalog: Dictionary,
	profile: Dictionary,
	_feature_catalog: Dictionary,
	body_fixed_position_m: Vector3
) -> Dictionary:
	if not _finite_vector(body_fixed_position_m):
		return {}
	var signed_distance_m := body_fixed_position_m.length() 		- float(profile["canonical_surface_radius_m"])
	if signed_distance_m > 0.0:
		return SampleScript.vacuum(signed_distance_m, float(profile["surface_temperature_k"]))
	var depth_m := -signed_distance_m
	var material_id := "matter/basalt"
	var integrity_ratio := 0.90
	var flags: Array = ["matter-state/bonded", "matter-zone/deep-rock"]
	if depth_m <= float(profile["regolith_loose_depth_m"]):
		material_id = "matter/regolith-loose"
		integrity_ratio = 0.15
		flags = ["matter-state/loose", "matter-zone/surface-shell"]
	elif depth_m <= float(profile["regolith_compacted_depth_m"]):
		material_id = "matter/regolith-compacted"
		integrity_ratio = 0.45
		flags = ["matter-state/bonded", "matter-zone/regolith"]
	elif depth_m <= float(profile["fractured_basalt_depth_m"]):
		material_id = "matter/fractured-basalt"
		integrity_ratio = 0.65
		flags = ["matter-state/fractured", "matter-zone/impact-layer"]
	var material := MaterialCatalogScript.material_by_id(material_catalog, material_id)
	if material.is_empty():
		return {}
	var composition := CompositionScript.from_weights({material_id: 1.0})
	if composition.is_empty():
		return {}
	var thermal_t := clampf(
		depth_m / maxf(float(profile["fractured_basalt_depth_m"]), 1.0),
		0.0,
		1.0
	)
	return SampleScript.create(
		signed_distance_m,
		1.0,
		float(material["density_kg_m3"]),
		composition,
		integrity_ratio,
		lerpf(
			float(profile["surface_temperature_k"]),
			float(profile["deep_temperature_k"]),
			thermal_t
		),
		float(material["porosity_ratio"]),
		flags
	)


static func signed_distance_validated(
	profile: Dictionary,
	body_fixed_position_m: Vector3
) -> float:
	if not bool(validate_profile(profile).get("success", false)) 		or not _finite_vector(body_fixed_position_m):
		return INF
	return body_fixed_position_m.length() - float(profile["canonical_surface_radius_m"])


static func _finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
