extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const DescriptorScript = preload("res://scripts/simulation/procedural/contracts/semantic_field_descriptor.gd")
const ValueTypeScript = preload("res://scripts/simulation/procedural/contracts/semantic_field_value_type.gd")
const DomainScript = preload("res://scripts/simulation/procedural/contracts/semantic_field_domain.gd")

const REGISTRY_ID: String = "semantic-field-registry/geo-v1"
const VERSION: String = "1.0.0"

const BASE_SURFACE_HEIGHT_M: String = "geo/base-surface-height-m"
const MACRO_SURFACE_HEIGHT_M: String = "geo/macro-surface-height-m"
const SURFACE_HEIGHT_M: String = "geo/surface-height-m"
const SLOPE: String = "geo/slope"
const CURVATURE: String = "geo/curvature"
const VALLEY_INFLUENCE: String = "geo/valley-influence"
const RIVER_DISTANCE_M: String = "geo/river-distance-m"
const RIVER_WIDTH_M: String = "geo/river-width-m"
const FLUID_SURFACE_DISTANCE_M: String = "geo/fluid-surface-distance-m"
const DRAINAGE_POTENTIAL: String = "geo/drainage-potential"
const CONTINENTALNESS: String = "geo/continentalness"
const TEMPERATURE_BASELINE: String = "geo/temperature-baseline"
const MOISTURE_BASELINE: String = "geo/moisture-baseline"

const UPSTREAM_ACCEPTED: String = "UPSTREAM_ACCEPTED"
const VOCABULARY_ONLY: String = "VOCABULARY_ONLY_G7_0"


static func descriptors() -> Dictionary:
	var result: Dictionary = {}
	_register(result, BASE_SURFACE_HEIGHT_M, "m", UPSTREAM_ACCEPTED, "G4 base surface")
	_register(result, MACRO_SURFACE_HEIGHT_M, "m", UPSTREAM_ACCEPTED, "G4/G3 macro surface composition")
	_register(result, SURFACE_HEIGHT_M, "m", UPSTREAM_ACCEPTED, "G3/G4 resolved surface")
	_register(result, SLOPE, "ratio", VOCABULARY_ONLY, "derived surface slope")
	_register(result, CURVATURE, "1/m", VOCABULARY_ONLY, "derived surface curvature")
	_register(result, VALLEY_INFLUENCE, "ratio", VOCABULARY_ONLY, "feature-derived valley influence")
	_register(result, RIVER_DISTANCE_M, "m", VOCABULARY_ONLY, "distance to canonical river semantics")
	_register(result, RIVER_WIDTH_M, "m", VOCABULARY_ONLY, "canonical river width projection")
	_register(result, FLUID_SURFACE_DISTANCE_M, "m", VOCABULARY_ONLY, "distance to nearest accepted fluid surface")
	_register(result, DRAINAGE_POTENTIAL, "ratio", VOCABULARY_ONLY, "hydrology/terrain drainage potential")
	_register(result, CONTINENTALNESS, "unitless", VOCABULARY_ONLY, "large-scale landmass semantic")
	_register(result, TEMPERATURE_BASELINE, "K", VOCABULARY_ONLY, "environment baseline hook, not climate simulation")
	_register(result, MOISTURE_BASELINE, "ratio", VOCABULARY_ONLY, "environment baseline hook, not climate simulation")
	return result


static func descriptor(field_id: String) -> Dictionary:
	var registry: Dictionary = descriptors()
	return registry[field_id].duplicate(true) if registry.has(field_id) else {}


static func field_ids() -> Array:
	var ids: Array = descriptors().keys()
	ids.sort()
	return ids


static func manifest_hash() -> String:
	return GeoUtilsScript.payload_hash({"registry_id": REGISTRY_ID, "version": VERSION, "descriptors": descriptors()})


static func validate_registry() -> Dictionary:
	if not GeoUtilsScript.is_canonical_id(REGISTRY_ID, 2):
		return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_REGISTRY_ID")
	if not GeoUtilsScript.is_semantic_version(VERSION):
		return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_REGISTRY_VERSION")
	var registry: Dictionary = descriptors()
	if registry.is_empty():
		return GeoUtilsScript.failure("EMPTY_SEMANTIC_FIELD_REGISTRY")
	var ids: Array = registry.keys()
	ids.sort()
	for raw_id in ids:
		var field_id: String = String(raw_id)
		var value = registry[field_id]
		if typeof(value) != TYPE_DICTIONARY:
			return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_REGISTRY_DESCRIPTOR", {"field_id": field_id})
		var validation: Dictionary = DescriptorScript.validate(value)
		if not bool(validation.get("success", false)):
			return validation
		if String(value["field_id"]) != field_id:
			return GeoUtilsScript.failure("SEMANTIC_FIELD_REGISTRY_KEY_MISMATCH", {"field_id": field_id})
	if not GeoUtilsScript.is_lower_hex_64(manifest_hash()):
		return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_REGISTRY_MANIFEST_HASH")
	return GeoUtilsScript.success({"field_count": ids.size(), "manifest_hash": manifest_hash()})


static func _register(target: Dictionary, field_id: String, unit: String, availability: String, description: String) -> void:
	target[field_id] = DescriptorScript.create(
		field_id,
		ValueTypeScript.SCALAR_FLOAT,
		DomainScript.BODY_SURFACE_POINT,
		unit,
		VERSION,
		{"availability": availability, "description": description, "representation_owned": false}
	)
