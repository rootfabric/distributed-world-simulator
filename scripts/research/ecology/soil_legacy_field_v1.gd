extends RefCounted

## ECO.EVO7 FFF5 - slow deterministic soil legacy / ecological memory.
## No microbe entities and no canonical soil authority: this is a bounded research-derived state.
const EffectV3 = preload("res://scripts/research/ecology/plant_environment_effect_v3.gd")
const SCHEMA := "distributed_world_simulator.ecology.soil_legacy_field.v1"
const VERSION := "1.0.0"
const MAX_PPM := 1000000

static func create_pristine()->Dictionary:
	var state := {"schema":SCHEMA,"version":VERSION,"cycle":0,"organic_matter_ppm":0,"retention_bonus_ppm":0,"nutrient_bonus_ppm":0,"establishment_bonus_ppm":0}
	state["state_hash"] = compute_state_hash(state)
	return state

static func validate(state:Dictionary)->bool:
	for key in ["schema","version","cycle","organic_matter_ppm","retention_bonus_ppm","nutrient_bonus_ppm","establishment_bonus_ppm","state_hash"]:
		if not state.has(key): return false
	if String(state["schema"]) != SCHEMA or String(state["version"]) != VERSION or int(state["cycle"]) < 0: return false
	for key in ["organic_matter_ppm","retention_bonus_ppm","nutrient_bonus_ppm","establishment_bonus_ppm"]:
		if typeof(state[key]) != TYPE_INT or int(state[key]) < 0 or int(state[key]) > MAX_PPM: return false
	return String(state["state_hash"]) == compute_state_hash(state)

static func apply_cycle(state:Dictionary, effects:Array)->Dictionary:
	if not validate(state) or effects.is_empty(): return {}
	var sorted := EffectV3.canonical_sort(effects)
	var litter_total := 0
	var binding_total := 0
	for effect in sorted:
		if not bool(EffectV3.validate(effect).get("success",false)): return {}
		litter_total += int(effect["litter_input_ppm"])
		binding_total += int(effect["soil_binding_ppm"])
	var old_organic := int(state["organic_matter_ppm"])
	var decay := int(floor(float(old_organic) * 0.04))
	var addition := int(floor(float(litter_total) * 0.45 + float(binding_total) * 0.20))
	var organic := clampi(old_organic - decay + addition, 0, MAX_PPM)
	var next := {"schema":SCHEMA,"version":VERSION,"cycle":int(state["cycle"])+1,"organic_matter_ppm":organic,
		"retention_bonus_ppm":clampi(int(floor(float(organic)*0.30)),0,MAX_PPM),
		"nutrient_bonus_ppm":clampi(int(floor(float(organic)*0.20)),0,MAX_PPM),
		"establishment_bonus_ppm":clampi(int(floor(float(organic)*0.22)),0,MAX_PPM)}
	next["state_hash"] = compute_state_hash(next)
	next["last_effects_hash"] = EffectV3.combined_hash(sorted)
	next["last_litter_total_ppm"] = litter_total
	next["last_binding_total_ppm"] = binding_total
	return next

static func compute_state_hash(state:Dictionary)->String:
	return "|".join(PackedStringArray([SCHEMA,VERSION,str(int(state.get("cycle",-1))),str(int(state.get("organic_matter_ppm",-1))),str(int(state.get("retention_bonus_ppm",-1))),str(int(state.get("nutrient_bonus_ppm",-1))),str(int(state.get("establishment_bonus_ppm",-1)))] )).sha256_text()