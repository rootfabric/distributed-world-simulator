extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const FeatureAnchorScript = preload("res://scripts/simulation/procedural/contracts/feature_anchor.gd")
const FeatureTypeScript = preload("res://scripts/simulation/procedural/contracts/feature_type.gd")
const WorldFeatureScript = preload("res://scripts/simulation/procedural/contracts/world_feature.gd")
const RiverSplineScript = preload("res://scripts/simulation/procedural/contracts/river_spline.gd")
const RiverChannelProfileScript = preload("res://scripts/simulation/procedural/contracts/river_channel_profile.gd")
const FluidSurfaceDescriptorScript = preload("res://scripts/simulation/procedural/contracts/fluid_surface_descriptor.gd")

const ATTRIBUTE_SCHEMA: String = "planet_simulator.river_feature_attributes.v1"
const ATTRIBUTE_FIELDS: Array[String] = ["schema", "geometry_kind", "river_spline", "channel_profile", "fluid_surface"]


static func create(
	body_id: String,
	seed: int,
	generator_version: String,
	stable_key: String,
	frame_id: String,
	bounds: Dictionary,
	river_spline: Dictionary,
	channel_profile: Dictionary,
	fluid_surface: Dictionary,
	parent_feature_id: String = "",
	relations: Array = []
) -> Dictionary:
	var anchors: Array = []
	if river_spline.has("points") and river_spline["points"] is Array:
		for index in range(river_spline["points"].size()):
			var point_value: Dictionary = river_spline["points"][index]
			var point_slug := String(point_value.get("point_id", "river-point/%02d" % index)).get_slice("/", 1)
			var role := "feature-anchor-role/control-point"
			if index == 0:
				role = "feature-anchor-role/source"
			elif index == river_spline["points"].size() - 1:
				role = "feature-anchor-role/mouth"
			anchors.append(FeatureAnchorScript.create(
				"feature-anchor/river-%s" % point_slug,
				frame_id,
				role,
				Array(point_value.get("position_m", [])).duplicate()
			))
	var attributes: Dictionary = {
		"schema": ATTRIBUTE_SCHEMA,
		"geometry_kind": "river-spline",
		"river_spline": river_spline.duplicate(true),
		"channel_profile": channel_profile.duplicate(true),
		"fluid_surface": fluid_surface.duplicate(true),
	}
	return WorldFeatureScript.create(
		body_id,
		FeatureTypeScript.RIVER,
		seed,
		generator_version,
		stable_key,
		frame_id,
		bounds,
		anchors,
		parent_feature_id,
		relations,
		attributes
	)


static func validate(value: Dictionary) -> Dictionary:
	var world_validation: Dictionary = WorldFeatureScript.validate(value)
	if not bool(world_validation.get("success", false)):
		return world_validation
	if String(value.get("feature_type", "")) != FeatureTypeScript.RIVER:
		return GeoUtilsScript.failure("NOT_A_RIVER_FEATURE")
	var attributes_value = value.get("attributes")
	if typeof(attributes_value) != TYPE_DICTIONARY:
		return GeoUtilsScript.failure("INVALID_RIVER_FEATURE_ATTRIBUTES")
	var attributes: Dictionary = attributes_value
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(attributes, ATTRIBUTE_FIELDS)
	if not bool(exact.get("success", false)):
		return GeoUtilsScript.failure("INVALID_RIVER_FEATURE_ATTRIBUTES", {"cause": exact.get("error_code", "")})
	if String(attributes.get("schema", "")) != ATTRIBUTE_SCHEMA or String(attributes.get("geometry_kind", "")) != "river-spline":
		return GeoUtilsScript.failure("INVALID_RIVER_FEATURE_ATTRIBUTE_SCHEMA")
	var spline_validation: Dictionary = RiverSplineScript.validate(attributes.get("river_spline", {}))
	if not bool(spline_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_RIVER_FEATURE_SPLINE", {"cause": spline_validation.get("error_code", "")})
	var profile_validation: Dictionary = RiverChannelProfileScript.validate(attributes.get("channel_profile", {}))
	if not bool(profile_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_RIVER_FEATURE_CHANNEL_PROFILE", {"cause": profile_validation.get("error_code", "")})
	var fluid_validation: Dictionary = FluidSurfaceDescriptorScript.validate(attributes.get("fluid_surface", {}))
	if not bool(fluid_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_RIVER_FEATURE_FLUID_SURFACE", {"cause": fluid_validation.get("error_code", "")})
	if String(attributes["river_spline"]["frame_id"]) != String(value["frame_id"]):
		return GeoUtilsScript.failure("RIVER_FEATURE_SPLINE_FRAME_MISMATCH")
	if String(attributes["fluid_surface"]["frame_id"]) != String(value["frame_id"]):
		return GeoUtilsScript.failure("RIVER_FEATURE_FLUID_FRAME_MISMATCH")
	if String(attributes["fluid_surface"]["body_id"]) != String(value["body_id"]):
		return GeoUtilsScript.failure("RIVER_FEATURE_FLUID_BODY_MISMATCH")
	return GeoUtilsScript.success()


static func spline(value: Dictionary) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	return Dictionary(value["attributes"]["river_spline"]).duplicate(true)


static func channel_profile(value: Dictionary) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	return Dictionary(value["attributes"]["channel_profile"]).duplicate(true)


static func fluid_surface(value: Dictionary) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	return Dictionary(value["attributes"]["fluid_surface"]).duplicate(true)
