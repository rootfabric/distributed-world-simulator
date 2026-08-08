extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const FeatureIdScript = preload("res://scripts/simulation/procedural/contracts/feature_id.gd")
const FeatureTypeScript = preload("res://scripts/simulation/procedural/contracts/feature_type.gd")
const FeatureBoundsScript = preload("res://scripts/simulation/procedural/contracts/feature_bounds.gd")
const FeatureAnchorScript = preload("res://scripts/simulation/procedural/contracts/feature_anchor.gd")
const FeatureRelationScript = preload("res://scripts/simulation/procedural/contracts/feature_relation.gd")

const SCHEMA: String = "planet_simulator.world_feature.v1"
const FIELDS: Array[String] = [
	"schema",
	"feature_id",
	"body_id",
	"feature_type",
	"seed",
	"generator_version",
	"stable_key",
	"frame_id",
	"bounds",
	"anchors",
	"parent_feature_id",
	"relations",
	"attributes",
	"checksum",
]


static func create(
	body_id: String,
	feature_type: String,
	seed: int,
	generator_version: String,
	stable_key: String,
	frame_id: String,
	bounds: Dictionary,
	anchors: Array = [],
	parent_feature_id: String = "",
	relations: Array = [],
	attributes: Dictionary = {}
) -> Dictionary:
	var id_result: Dictionary = FeatureIdScript.derive(body_id, feature_type, seed, generator_version, stable_key)
	var feature_id: String = String(id_result.get("details", {}).get("feature_id", ""))
	var canonical_anchors: Array = []
	for raw_anchor in anchors:
		if raw_anchor is Dictionary:
			canonical_anchors.append(Dictionary(raw_anchor).duplicate(true))
	canonical_anchors.sort_custom(func(a, b): return String(a.get("anchor_id", "")) < String(b.get("anchor_id", "")))
	var canonical_relations: Array = []
	for raw_relation in relations:
		if raw_relation is Dictionary:
			canonical_relations.append(Dictionary(raw_relation).duplicate(true))
	canonical_relations.sort_custom(func(a, b): return FeatureRelationScript.identity_token(a) < FeatureRelationScript.identity_token(b))
	var value: Dictionary = {
		"schema": SCHEMA,
		"feature_id": feature_id,
		"body_id": body_id,
		"feature_type": feature_type,
		"seed": seed,
		"generator_version": generator_version,
		"stable_key": stable_key,
		"frame_id": frame_id,
		"bounds": bounds.duplicate(true),
		"anchors": canonical_anchors,
		"parent_feature_id": parent_feature_id,
		"relations": canonical_relations,
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
		return GeoUtilsScript.failure("UNSUPPORTED_WORLD_FEATURE_SCHEMA")
	if not GeoUtilsScript.is_canonical_id(value.get("body_id"), 2):
		return GeoUtilsScript.failure("INVALID_WORLD_FEATURE_BODY_ID")
	var type_validation: Dictionary = FeatureTypeScript.validate(value.get("feature_type"))
	if not bool(type_validation.get("success", false)):
		return type_validation
	if not GeoUtilsScript.is_json_integer(value.get("seed")):
		return GeoUtilsScript.failure("INVALID_WORLD_FEATURE_SEED")
	if not GeoUtilsScript.is_semantic_version(value.get("generator_version")):
		return GeoUtilsScript.failure("INVALID_WORLD_FEATURE_GENERATOR_VERSION")
	if not GeoUtilsScript.is_canonical_id(value.get("stable_key"), 2) or not String(value["stable_key"]).begins_with(FeatureIdScript.STABLE_KEY_PREFIX):
		return GeoUtilsScript.failure("INVALID_WORLD_FEATURE_STABLE_KEY")
	if not GeoUtilsScript.is_canonical_id(value.get("frame_id"), 2):
		return GeoUtilsScript.failure("INVALID_WORLD_FEATURE_FRAME_ID")
	var id_result: Dictionary = FeatureIdScript.derive(
		String(value["body_id"]), String(value["feature_type"]), int(value["seed"]),
		String(value["generator_version"]), String(value["stable_key"])
	)
	if not bool(id_result.get("success", false)) or String(value.get("feature_id", "")) != String(id_result["details"]["feature_id"]):
		return GeoUtilsScript.failure("WORLD_FEATURE_IDENTITY_MISMATCH")
	var bounds_value = value.get("bounds")
	if typeof(bounds_value) != TYPE_DICTIONARY:
		return GeoUtilsScript.failure("INVALID_WORLD_FEATURE_BOUNDS")
	var bounds_validation: Dictionary = FeatureBoundsScript.validate(bounds_value)
	if not bool(bounds_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_WORLD_FEATURE_BOUNDS", {"cause": bounds_validation.get("error_code", "")})
	if String(bounds_value["frame_id"]) != String(value["frame_id"]):
		return GeoUtilsScript.failure("WORLD_FEATURE_BOUNDS_FRAME_MISMATCH")
	if typeof(value.get("anchors")) != TYPE_ARRAY:
		return GeoUtilsScript.failure("INVALID_WORLD_FEATURE_ANCHORS")
	var previous_anchor: String = ""
	for index in range(value["anchors"].size()):
		var anchor_value = value["anchors"][index]
		if typeof(anchor_value) != TYPE_DICTIONARY:
			return GeoUtilsScript.failure("INVALID_WORLD_FEATURE_ANCHOR", {"index": index})
		var anchor_validation: Dictionary = FeatureAnchorScript.validate(anchor_value)
		if not bool(anchor_validation.get("success", false)):
			return GeoUtilsScript.failure("INVALID_WORLD_FEATURE_ANCHOR", {"index": index, "cause": anchor_validation.get("error_code", "")})
		if String(anchor_value["frame_id"]) != String(value["frame_id"]):
			return GeoUtilsScript.failure("WORLD_FEATURE_ANCHOR_FRAME_MISMATCH", {"index": index})
		var anchor_id: String = String(anchor_value["anchor_id"])
		if index > 0 and anchor_id <= previous_anchor:
			return GeoUtilsScript.failure("WORLD_FEATURE_ANCHORS_NOT_SORTED_UNIQUE")
		previous_anchor = anchor_id
	if typeof(value.get("parent_feature_id")) != TYPE_STRING:
		return GeoUtilsScript.failure("INVALID_WORLD_FEATURE_PARENT")
	var parent_id: String = String(value["parent_feature_id"])
	if not parent_id.is_empty() and not bool(FeatureIdScript.validate(parent_id).get("success", false)):
		return GeoUtilsScript.failure("INVALID_WORLD_FEATURE_PARENT")
	if parent_id == String(value["feature_id"]):
		return GeoUtilsScript.failure("WORLD_FEATURE_SELF_PARENT")
	if typeof(value.get("relations")) != TYPE_ARRAY:
		return GeoUtilsScript.failure("INVALID_WORLD_FEATURE_RELATIONS")
	var previous_relation: String = ""
	for index in range(value["relations"].size()):
		var relation_value = value["relations"][index]
		if typeof(relation_value) != TYPE_DICTIONARY:
			return GeoUtilsScript.failure("INVALID_WORLD_FEATURE_RELATION", {"index": index})
		var relation_validation: Dictionary = FeatureRelationScript.validate(relation_value)
		if not bool(relation_validation.get("success", false)):
			return GeoUtilsScript.failure("INVALID_WORLD_FEATURE_RELATION", {"index": index, "cause": relation_validation.get("error_code", "")})
		if String(relation_value["target_feature_id"]) == String(value["feature_id"]):
			return GeoUtilsScript.failure("WORLD_FEATURE_SELF_RELATION", {"index": index})
		var relation_token: String = FeatureRelationScript.identity_token(relation_value)
		if index > 0 and relation_token <= previous_relation:
			return GeoUtilsScript.failure("WORLD_FEATURE_RELATIONS_NOT_SORTED_UNIQUE")
		previous_relation = relation_token
	if typeof(value.get("attributes")) != TYPE_DICTIONARY:
		return GeoUtilsScript.failure("INVALID_WORLD_FEATURE_ATTRIBUTES")
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.world_feature")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return GeoUtilsScript.normalize(value, validate)
