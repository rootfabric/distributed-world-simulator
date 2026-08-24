extends RefCounted

## ECO.EVO7 FFF5 additive successor: litter + soil-binding become active.
## v1/v2 remain unchanged so older stage contracts stay replayable.
const SCHEMA := "distributed_world_simulator.ecology.plant_environment_effect.v3"
const VERSION := "3.0.0"
const FIELD_NAMES: Array[String] = ["schema","version","plant_identity","cell_identity","generation","shade_ppm","water_uptake_ppm","evaporation_suppression_ppm","litter_input_ppm","soil_binding_ppm","source_phenotype_hash","effect_hash"]

static func create(plant_identity:String, cell_identity:String, generation:int, shade_ppm:int, water_uptake_ppm:int,
		evaporation_suppression_ppm:int, litter_input_ppm:int, soil_binding_ppm:int, source_phenotype_hash:String)->Dictionary:
	if plant_identity.is_empty() or cell_identity.is_empty() or generation < 0 or source_phenotype_hash.length() != 64:
		return {}
	var effect := {"schema":SCHEMA,"version":VERSION,"plant_identity":plant_identity,"cell_identity":cell_identity,"generation":generation,
		"shade_ppm":maxi(shade_ppm,0),"water_uptake_ppm":maxi(water_uptake_ppm,0),"evaporation_suppression_ppm":maxi(evaporation_suppression_ppm,0),
		"litter_input_ppm":maxi(litter_input_ppm,0),"soil_binding_ppm":maxi(soil_binding_ppm,0),"source_phenotype_hash":source_phenotype_hash}
	effect["effect_hash"] = compute_effect_hash(effect)
	return effect

static func validate(effect:Dictionary)->Dictionary:
	if effect.keys().size() != FIELD_NAMES.size(): return _failure("ECO_EFFECT_V3_FIELD_COUNT_MISMATCH")
	for field_name in FIELD_NAMES:
		if not effect.has(field_name): return _failure("ECO_EFFECT_V3_MISSING_FIELD", {"field":field_name})
	if String(effect.get("schema","")) != SCHEMA or String(effect.get("version","")) != VERSION: return _failure("ECO_EFFECT_V3_SCHEMA_VERSION_MISMATCH")
	if String(effect.get("plant_identity","")).is_empty() or String(effect.get("cell_identity","")).is_empty(): return _failure("ECO_EFFECT_V3_EMPTY_IDENTITY")
	if typeof(effect.get("generation")) != TYPE_INT or int(effect.get("generation")) < 0: return _failure("ECO_EFFECT_V3_INVALID_GENERATION")
	for channel in ["shade_ppm","water_uptake_ppm","evaporation_suppression_ppm","litter_input_ppm","soil_binding_ppm"]:
		if typeof(effect.get(channel)) != TYPE_INT or int(effect.get(channel)) < 0: return _failure("ECO_EFFECT_V3_INVALID_CHANNEL", {"channel":channel})
	if String(effect.get("source_phenotype_hash","")).length() != 64: return _failure("ECO_EFFECT_V3_INVALID_PHENOTYPE_HASH")
	if String(effect.get("effect_hash","")) != compute_effect_hash(effect): return _failure("ECO_EFFECT_V3_HASH_MISMATCH")
	return _success()

static func compute_effect_hash(effect:Dictionary)->String:
	return "|".join(PackedStringArray([SCHEMA,VERSION,String(effect.get("plant_identity","")),String(effect.get("cell_identity","")),str(int(effect.get("generation",-1))),str(int(effect.get("shade_ppm",-1))),str(int(effect.get("water_uptake_ppm",-1))),str(int(effect.get("evaporation_suppression_ppm",-1))),str(int(effect.get("litter_input_ppm",-1))),str(int(effect.get("soil_binding_ppm",-1))),String(effect.get("source_phenotype_hash",""))])).sha256_text()

static func canonical_sort(records:Array)->Array:
	var result := records.duplicate(true)
	result.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return String(a.get("plant_identity","")) < String(b.get("plant_identity","")))
	return result

static func combined_hash(records:Array)->String:
	var tokens := PackedStringArray([SCHEMA,VERSION,"combined"])
	for effect in canonical_sort(records):
		if not bool(validate(effect).get("success",false)): return ""
		tokens.append(String(effect["effect_hash"]))
	return "|".join(tokens).sha256_text()

static func _success(details:Dictionary={})->Dictionary:return {"success":true,"error_code":"","details":details.duplicate(true)}
static func _failure(code:String,details:Dictionary={})->Dictionary:return {"success":false,"error_code":code,"details":details.duplicate(true)}