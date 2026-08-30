extends RefCounted

## ECO.EVO7 FFF3 - plant_environment_effect.v1 (spec section 7).
## A plant never writes environment state directly: it publishes this deterministic
## effect record, and the field aggregator applies records in canonical identity
## order. R1 activates ONLY the shade channel; the other channels stay zero until
## their stages land (water FFF4, litter FFF5) - a nonzero inactive channel is a
## contract violation ("no creation from nothing").

const SCHEMA := "distributed_world_simulator.ecology.plant_environment_effect.v1"
const VERSION := "1.0.0"

## Channels activated by stage: shade=FFF3, water_uptake/evaporation_suppression=FFF4,
## litter_input=FFF5, soil_binding=FFF5+.
const ACTIVE_CHANNELS: Array[String] = ["shade_ppm"]
const INACTIVE_CHANNELS: Array[String] = [
	"water_uptake_ppm", "evaporation_suppression_ppm", "litter_input_ppm", "soil_binding_ppm",
]
const FIELD_NAMES: Array[String] = [
	"schema", "version", "plant_identity", "cell_identity", "generation",
	"shade_ppm", "water_uptake_ppm", "evaporation_suppression_ppm",
	"litter_input_ppm", "soil_binding_ppm", "source_phenotype_hash", "effect_hash",
]

static func create(
	plant_identity: String,
	cell_identity: String,
	generation: int,
	shade_ppm: int,
	source_phenotype_hash: String
) -> Dictionary:
	if plant_identity.is_empty() or plant_identity != plant_identity.strip_edges():
		return {}
	if cell_identity.is_empty():
		return {}
	if generation < 0:
		return {}
	var shade := maxi(int(shade_ppm), 0)
	var effect := {
		"schema": SCHEMA,
		"version": VERSION,
		"plant_identity": plant_identity,
		"cell_identity": cell_identity,
		"generation": generation,
		"shade_ppm": shade,
		"water_uptake_ppm": 0,
		"evaporation_suppression_ppm": 0,
		"litter_input_ppm": 0,
		"soil_binding_ppm": 0,
		"source_phenotype_hash": source_phenotype_hash,
	}
	effect["effect_hash"] = compute_effect_hash(effect)
	return effect

static func validate(effect: Dictionary) -> Dictionary:
	if effect.keys().size() != FIELD_NAMES.size():
		return _failure("ECO_EFFECT_FIELD_COUNT_MISMATCH")
	for field_name in FIELD_NAMES:
		if not effect.has(field_name):
			return _failure("ECO_EFFECT_MISSING_FIELD", {"field": field_name})
	for field_name in effect.keys():
		if not String(field_name) in FIELD_NAMES:
			return _failure("ECO_EFFECT_UNEXPECTED_FIELD", {"field": String(field_name)})
	if String(effect.get("schema", "")) != SCHEMA or String(effect.get("version", "")) != VERSION:
		return _failure("ECO_EFFECT_SCHEMA_VERSION_MISMATCH")
	if String(effect.get("plant_identity", "")).is_empty():
		return _failure("ECO_EFFECT_EMPTY_PLANT_IDENTITY")
	if String(effect.get("cell_identity", "")).is_empty():
		return _failure("ECO_EFFECT_EMPTY_CELL_IDENTITY")
	if typeof(effect.get("generation")) != TYPE_INT or int(effect.get("generation")) < 0:
		return _failure("ECO_EFFECT_INVALID_GENERATION")
	for channel in ["shade_ppm"] + INACTIVE_CHANNELS:
		if typeof(effect.get(channel)) != TYPE_INT or int(effect.get(channel)) < 0:
			return _failure("ECO_EFFECT_NEGATIVE_CHANNEL", {"channel": channel})
	for channel in INACTIVE_CHANNELS:
		if int(effect.get(channel)) != 0:
			return _failure("ECO_EFFECT_INACTIVE_CHANNEL_NONZERO", {"channel": channel})
	if String(effect.get("source_phenotype_hash", "")).length() != 64:
		return _failure("ECO_EFFECT_INVALID_PHENOTYPE_HASH")
	if String(effect.get("effect_hash", "")) != compute_effect_hash(effect):
		return _failure("ECO_EFFECT_HASH_MISMATCH")
	return _success()

static func compute_effect_hash(effect: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SCHEMA, VERSION,
		String(effect.get("plant_identity", "")),
		String(effect.get("cell_identity", "")),
		str(int(effect.get("generation", -1))),
		str(int(effect.get("shade_ppm", -1))),
		str(int(effect.get("water_uptake_ppm", -1))),
		str(int(effect.get("evaporation_suppression_ppm", -1))),
		str(int(effect.get("litter_input_ppm", -1))),
		str(int(effect.get("soil_binding_ppm", -1))),
		String(effect.get("source_phenotype_hash", "")),
	])).sha256_text()

## Canonical publication order: sorted by plant identity. The aggregator and any
## consumer must apply records in this order (order invariance gate G12).
static func canonical_sort(records: Array) -> Array:
	var sorted_records := records.duplicate()
	sorted_records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("plant_identity", "")) < String(b.get("plant_identity", "")))
	return sorted_records

static func combined_hash(records: Array) -> String:
	var tokens := PackedStringArray([SCHEMA, VERSION, "combined"])
	for effect in canonical_sort(records):
		tokens.append(String(effect["effect_hash"]))
	return "|".join(tokens).sha256_text()

static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
