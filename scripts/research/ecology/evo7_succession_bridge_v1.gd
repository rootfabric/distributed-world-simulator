extends RefCounted

## ECO.EVO7 FFF6 - closed community evolution / succession bridge.
## One feedback loop combines inherited morphology, canopy light, bounded soil water,
## and slow soil legacy for >=100 deterministic cycles. No renderer or environment
## writes genome state; all offspring still pass through LineageExtension.
const Morphology = preload("res://scripts/research/ecology/evo7_morphology_evolution_bridge_v1.gd")
const LineageExtension = preload("res://scripts/research/ecology/plant_mutation_lineage_extension_evo7_v1.gd")
const Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const CoupledDevelopment = preload("res://scripts/research/ecology/plant_environment_coupled_development_v1.gd")
const FunctionalPhenotype = preload("res://scripts/research/ecology/plant_functional_phenotype_v1.gd")
const EnvSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const LightField = preload("res://scripts/research/ecology/understory_light_field_v1.gd")
const WaterField = preload("res://scripts/research/ecology/soil_water_field_v1.gd")
const Legacy = preload("res://scripts/research/ecology/soil_legacy_field_v1.gd")
const EffectV3 = preload("res://scripts/research/ecology/plant_environment_effect_v3.gd")
const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const ExtensionTraits = preload("res://scripts/research/ecology/plant_development_traits_extension_evo7_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_succession_bridge.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-FFF6.1"
const MIN_CYCLES := 100
const POPULATION_SIZE := 12
const OFFSPRING_PER_PARENT := 2
const GAP_REMOVAL_CYCLE := 50
const GRID_SIDE := 5
const SPACING_M := 0.45

const ZONES := {
	"flooded": {"texture":"clay", "moisture_ppm":950000, "sunlight":0.82, "nutrients":0.68, "temperature_c":19.0, "flood":0.78, "canopy":"none"},
	"riparian": {"texture":"loam", "moisture_ppm":680000, "sunlight":0.86, "nutrients":0.62, "temperature_c":20.0, "flood":0.32, "canopy":"none"},
	"mesic_loam": {"texture":"loam", "moisture_ppm":480000, "sunlight":0.84, "nutrients":0.50, "temperature_c":21.0, "flood":0.02, "canopy":"none"},
	"dry_sand": {"texture":"sand", "moisture_ppm":180000, "sunlight":0.95, "nutrients":0.25, "temperature_c":28.0, "flood":0.0, "canopy":"none"},
	"under_canopy": {"texture":"loam", "moisture_ppm":450000, "sunlight":0.85, "nutrients":0.45, "temperature_c":21.0, "flood":0.02, "canopy":"persistent"},
	"canopy_gap": {"texture":"loam", "moisture_ppm":450000, "sunlight":0.85, "nutrients":0.45, "temperature_c":21.0, "flood":0.02, "canopy":"gap"},
}
const ZONE_ORDER: Array[String] = ["flooded", "riparian", "mesic_loam", "dry_sand", "under_canopy", "canopy_gap"]
const FEATURE_FIELDS: Array[String] = [
	"realized_height_m", "realized_crown_radius_m", "realized_crown_density",
	"leaf_area_index_proxy", "realized_root_depth_m", "realized_root_spread_m",
	"structural_investment",
]

static func run_all(lineage_seed := 20260823, cycles := MIN_CYCLES, feedback_enabled := true) -> Dictionary:
	if cycles < MIN_CYCLES:
		return {}
	var ancestor := Morphology.default_ancestor_bundle(lineage_seed)
	if ancestor.is_empty():
		return {}
	var policy := LineageExtension.default_policy()
	policy["morphology_probability"] = 0.48
	policy["genome_policy"]["mutation_probability"] = 0.48
	policy["genome_policy"]["root_depth_m_step"] = 0.40
	policy["genome_policy"]["shade_tolerance_step"] = 0.10
	if LineageExtension.policy_hash(policy).is_empty():
		return {}

	var zones := {}
	var common_first_pool := ""
	for zone_name in ZONE_ORDER:
		var zone := _run_zone(ancestor, zone_name, ZONES[zone_name], lineage_seed, cycles, policy, feedback_enabled)
		if zone.is_empty():
			return {}
		if common_first_pool.is_empty():
			common_first_pool = String(zone["first_candidate_pool_hash"])
		elif common_first_pool != String(zone["first_candidate_pool_hash"]):
			return {}
		zones[zone_name] = zone

	var cluster_count := _geometry_cluster_count(zones)
	var distinct_population_hashes := {}
	for zone_name in ZONE_ORDER:
		distinct_population_hashes[String(zones[zone_name]["final_population_hash"])] = true
	var result := {
		"schema":SCHEMA, "version":VERSION, "revision":REVISION,
		"lineage_seed":lineage_seed, "cycles":cycles, "feedback_enabled":feedback_enabled,
		"population_size":POPULATION_SIZE, "offspring_per_parent":OFFSPRING_PER_PARENT,
		"policy_hash":LineageExtension.policy_hash(policy),
		"common_first_candidate_pool_hash":common_first_pool,
		"zones":zones,
		"geometry_cluster_count":cluster_count,
		"distinct_final_population_count":distinct_population_hashes.size(),
		"gap_light_recovery":snappedf(float(zones["canopy_gap"]["gap_light_after"]) - float(zones["canopy_gap"]["gap_light_before"]), 1e-9),
	}
	result["result_hash"] = _result_hash(result)
	return result

static func _run_zone(ancestor: Dictionary, zone_name: String, cfg: Dictionary, lineage_seed: int,
		cycles: int, policy: Dictionary, feedback_enabled: bool) -> Dictionary:
	var population := _initial_population(ancestor)
	var soil := Legacy.create_pristine()
	var first_pool_hash := ""
	var gap_light_before := -1.0
	var gap_light_after := -1.0
	var final_mean_light := 0.0
	var final_mean_water := 0.0
	var final_mean_fitness := 0.0
	var final_mean_features := {}
	var final_saturation_fraction := 0.0
	var final_mean_root_shoot := 0.0
	var final_mean_shade_tolerance := 0.0
	var final_mean_water_preference := 0.0
	var final_population_hash := ""

	for cycle in range(1, cycles + 1):
		var candidates: Array[Dictionary] = []
		var mutation_tokens := PackedStringArray()
		for parent_index in population.size():
			var parent: Dictionary = population[parent_index]
			for offspring_index in OFFSPRING_PER_PARENT:
				var mutation_seed := ("EVO7-FFF6|%d|%d|%d|%d" % [lineage_seed, cycle, parent_index, offspring_index]).hash()
				var child := LineageExtension.reproduce_bundle(parent["bundle"], mutation_seed, offspring_index, policy)
				if child.is_empty():
					return {}
				candidates.append({"bundle":child["bundle"], "mutation_result_hash":String(child["result_hash"])})
				mutation_tokens.append(String(child["result_hash"]))
		if cycle == 1:
			first_pool_hash = "|".join(mutation_tokens).sha256_text()

		var evaluated := _evaluate_candidates(candidates, zone_name, cfg, soil, lineage_seed, cycle, feedback_enabled)
		if evaluated.is_empty():
			return {}
		evaluated.sort_custom(_rank_order)
		population = evaluated.slice(0, POPULATION_SIZE)

		if feedback_enabled:
			var effects := _selected_soil_effects(population, cycle)
			if effects.is_empty():
				return {}
			soil = Legacy.apply_cycle(soil, effects)
			if soil.is_empty():
				return {}

		var cycle_means := _population_means(population)
		final_mean_light = float(cycle_means["mean_light"])
		final_mean_water = float(cycle_means["mean_water"])
		final_mean_fitness = float(cycle_means["mean_fitness"])
		final_mean_features = cycle_means["mean_features"]
		final_saturation_fraction = float(cycle_means["saturation_fraction"])
		final_mean_root_shoot = float(cycle_means["mean_root_shoot_ratio"])
		final_mean_shade_tolerance = float(cycle_means["mean_shade_tolerance"])
		final_mean_water_preference = float(cycle_means["mean_water_preference"])
		final_population_hash = String(cycle_means["population_hash"])
		if zone_name == "canopy_gap" and cycle == GAP_REMOVAL_CYCLE:
			gap_light_before = final_mean_light
		if zone_name == "canopy_gap" and cycle == GAP_REMOVAL_CYCLE + 1:
			gap_light_after = final_mean_light

	if zone_name != "canopy_gap":
		gap_light_before = final_mean_light
		gap_light_after = final_mean_light
	return {
		"zone":zone_name, "texture":String(cfg["texture"]),
		"first_candidate_pool_hash":first_pool_hash,
		"final_population_hash":final_population_hash,
		"final_soil_state_hash":String(soil["state_hash"]),
		"organic_matter_ppm":int(soil["organic_matter_ppm"]),
		"mean_understory_light":snappedf(final_mean_light,1e-9),
		"mean_water_satisfaction":snappedf(final_mean_water,1e-9),
		"mean_fitness":snappedf(final_mean_fitness,1e-9),
		"mean_features":final_mean_features,
		"saturation_fraction":snappedf(final_saturation_fraction,1e-9),
		"mean_root_shoot_ratio":snappedf(final_mean_root_shoot,1e-9),
		"mean_shade_tolerance":snappedf(final_mean_shade_tolerance,1e-9),
		"mean_water_preference":snappedf(final_mean_water_preference,1e-9),
		"gap_light_before":snappedf(gap_light_before,1e-9),
		"gap_light_after":snappedf(gap_light_after,1e-9),
	}

static func _initial_population(ancestor: Dictionary) -> Array[Dictionary]:
	var population: Array[Dictionary] = []
	for index in POPULATION_SIZE:
		var bundle: Dictionary = ancestor.duplicate(true)
		var individual_seed := Contract.derive_individual_seed(String(bundle["lineage"]["lineage_id"]), "evo7-fff6-gen0|%d" % index, index, String(bundle["genome"]["version"]))
		bundle["individual_seed"] = individual_seed
		bundle["bundle_checksum"] = LineageExtension.bundle_checksum(bundle["genome"], bundle["dev_traits"], bundle["ext_traits"], bundle["lineage"], individual_seed)
		population.append({"bundle":bundle, "fitness":0.0})
	return population

static func _evaluate_candidates(candidates: Array[Dictionary], zone_name: String, cfg: Dictionary, soil: Dictionary,
		lineage_seed: int, cycle: int, feedback_enabled: bool) -> Array[Dictionary]:
	var legacy_retention := float(soil["retention_bonus_ppm"]) / 1000000.0 if feedback_enabled else 0.0
	var legacy_nutrients := float(soil["nutrient_bonus_ppm"]) / 1000000.0 if feedback_enabled else 0.0
	var base_moisture := clampf(float(cfg["moisture_ppm"]) / 1000000.0 + legacy_retention * 0.55, 0.0, 1.0)
	var base_nutrients := clampf(float(cfg["nutrients"]) + legacy_nutrients * 0.75, 0.0, 1.0)
	var base_env := EnvSample.create(0.0,0.0,float(cfg["temperature_c"]),base_moisture,float(cfg["sunlight"]),base_nutrients,float(cfg["flood"]),lineage_seed,"ECO.EVO7-FFF6|%s|base|c%d" % [zone_name,cycle])
	var provisional: Array[Dictionary] = []
	var light_records: Array = []
	var water_records: Array = []
	for index in candidates.size():
		var bundle: Dictionary = candidates[index]["bundle"]
		var fp := _functional(bundle, base_env, "fff6-provisional|%s|%d|%d" % [zone_name,cycle,index])
		if fp.is_empty(): return []
		var pos := _position(index)
		var identity := "c%03d" % index
		provisional.append({"identity":identity,"bundle":bundle,"fp":fp,"x":float(pos.x),"z":float(pos.y)})
		light_records.append(_light_record(identity,float(pos.x),float(pos.y),fp,float(cfg["sunlight"])))
		water_records.append(_water_record(identity,fp))
	if feedback_enabled and _static_canopy_present(String(cfg["canopy"]),cycle):
		for canopy_index in 8:
			var canopy_light := _static_canopy_light_record(canopy_index,float(cfg["sunlight"]))
			light_records.append(canopy_light)
			water_records.append(_static_canopy_water_record(canopy_index, canopy_light))

	var light_field := LightField.compute(light_records)
	if light_field.is_empty(): return []
	var water_field := WaterField.compute(int(round(base_moisture * 1000000.0)),String(cfg["texture"]),float(cfg["sunlight"]),water_records,cycle)
	if water_field.is_empty(): return []
	var evaluated: Array[Dictionary] = []
	for item in provisional:
		var identity := String(item["identity"])
		var effective_light := float(cfg["sunlight"])
		var effective_moisture := base_moisture
		var water_satisfaction := 1.0
		if feedback_enabled:
			effective_light = float(light_field["plant_light"][identity]["understory_light"])
			var water_item: Dictionary = water_field["plant_water"][identity]
			effective_moisture = float(water_item["effective_soil_moisture"])
			water_satisfaction = float(water_item["water_satisfaction"])
		var env := EnvSample.create(float(item["x"]),float(item["z"]),float(cfg["temperature_c"]),clampf(effective_moisture,0.0,1.0),clampf(effective_light,0.0,1.0),base_nutrients,float(cfg["flood"]),lineage_seed,"ECO.EVO7-FFF6|%s|c%d|%s" % [zone_name,cycle,identity])
		var fp := _functional(item["bundle"],env,"fff6-final|%s|%d|%s" % [zone_name,cycle,identity])
		if fp.is_empty(): return []
		var shade_tolerance := float(item["bundle"]["genome"]["shade_tolerance"])
		var water_preference := float(item["bundle"]["genome"]["water_preference"])
		var light_stress := 1.0 - clampf(effective_light / maxf(float(cfg["sunlight"]),0.001),0.0,1.0)
		var shade_adaptation := shade_tolerance * light_stress * 0.45
		var water_match := 1.0 - absf(water_preference - effective_moisture)
		var drought_cost := (1.0 - water_satisfaction) * (0.30 + 0.20 * float(fp["leaf_area_index_proxy"]))
		var establishment_legacy := float(soil["establishment_bonus_ppm"]) / 1000000.0 if feedback_enabled else 0.0
		var fitness := float(fp["net_resource_proxy"]) + 0.35 * float(fp["establishment_capacity"]) + 0.30 * water_match + shade_adaptation + 0.55 * establishment_legacy - drought_cost
		evaluated.append({"bundle":item["bundle"],"fitness":snappedf(fitness,1e-9),"fp":fp,"understory_light":snappedf(effective_light,1e-9),"water_satisfaction":snappedf(water_satisfaction,1e-9),"water_uptake_ppm":int(water_field["plant_water"][identity]["water_uptake_ppm"]) if feedback_enabled else 0,"evaporation_suppression_ppm":_effect_suppression(water_field,identity) if feedback_enabled else 0})
	return evaluated

static func _selected_soil_effects(population: Array[Dictionary], cycle: int) -> Array:
	var effects: Array = []
	for index in population.size():
		var entry: Dictionary = population[index]
		var fp: Dictionary = entry["fp"]
		var binding := maxi(int(floor((float(fp["realized_root_depth_m"]) + float(fp["realized_root_spread_m"])) * 2600.0)),0)
		var effect := EffectV3.create("selected-%02d" % index,"zone-cell",cycle,int(fp["shade_output_ppm"]),int(entry.get("water_uptake_ppm",0)),int(entry.get("evaporation_suppression_ppm",0)),int(fp["litter_flux_ppm"]),binding,String(fp["phenotype_hash"]))
		if effect.is_empty(): return []
		effects.append(effect)
	return effects

static func _population_means(population: Array[Dictionary]) -> Dictionary:
	var sums := {}
	for field_name in FEATURE_FIELDS: sums[field_name] = 0.0
	var light_sum := 0.0
	var water_sum := 0.0
	var fitness_sum := 0.0
	var root_shoot_sum := 0.0
	var shade_tolerance_sum := 0.0
	var water_preference_sum := 0.0
	var saturated := 0
	var checksums := PackedStringArray()
	for entry in population:
		var fp: Dictionary = entry["fp"]
		checksums.append(String(entry["bundle"]["bundle_checksum"]))
		light_sum += float(entry["understory_light"])
		water_sum += float(entry["water_satisfaction"])
		fitness_sum += float(entry["fitness"])
		root_shoot_sum += float(fp["root_shoot_ratio"])
		shade_tolerance_sum += float(entry["bundle"]["genome"]["shade_tolerance"])
		water_preference_sum += float(entry["bundle"]["genome"]["water_preference"])
		for field_name in FEATURE_FIELDS: sums[field_name] += float(fp[field_name])
		if _near_all_max(entry["bundle"]): saturated += 1
	var means := {}
	for field_name in FEATURE_FIELDS: means[field_name] = snappedf(float(sums[field_name])/float(population.size()),1e-9)
	checksums.sort()
	return {"mean_features":means,"mean_light":snappedf(light_sum/float(population.size()),1e-9),"mean_water":snappedf(water_sum/float(population.size()),1e-9),"mean_fitness":snappedf(fitness_sum/float(population.size()),1e-9),"saturation_fraction":snappedf(float(saturated)/float(population.size()),1e-9),
		"mean_root_shoot_ratio":snappedf(root_shoot_sum/float(population.size()),1e-9),
		"mean_shade_tolerance":snappedf(shade_tolerance_sum/float(population.size()),1e-9),
		"mean_water_preference":snappedf(water_preference_sum/float(population.size()),1e-9),
		"population_hash":"|".join(checksums).sha256_text()}

static func _near_all_max(bundle: Dictionary) -> bool:
	var axes := [
		[float(bundle["dev_traits"]["max_height_m"]), float(Traits.BOUNDS["max_height_m"][1])],
		[float(bundle["dev_traits"]["crown_spread_m"]), float(Traits.BOUNDS["crown_spread_m"][1])],
		[float(bundle["dev_traits"]["apical_dominance"]), float(Traits.BOUNDS["apical_dominance"][1])],
		[float(bundle["ext_traits"]["foliage_density"]), float(ExtensionTraits.BOUNDS["foliage_density"][1])],
		[float(bundle["ext_traits"]["leaf_economics_proxy"]), float(ExtensionTraits.BOUNDS["leaf_economics_proxy"][1])],
		[float(bundle["ext_traits"]["structural_investment"]), float(ExtensionTraits.BOUNDS["structural_investment"][1])],
		[float(bundle["ext_traits"]["root_spread_m"]), float(ExtensionTraits.BOUNDS["root_spread_m"][1])],
		[float(bundle["ext_traits"]["root_shoot_ratio"]), float(ExtensionTraits.BOUNDS["root_shoot_ratio"][1])],
	]
	var maxed := 0
	for axis in axes:
		if float(axis[0]) >= float(axis[1]) * 0.99: maxed += 1
	return maxed >= 7

static func _functional(bundle: Dictionary, env: Dictionary, seed_tag: String) -> Dictionary:
	var envelope := Contract.create_seed_envelope(bundle["genome"],bundle["dev_traits"],String(bundle["lineage"]["lineage_id"]),seed_tag,0,1.25)
	var ph2 := CoupledDevelopment.realize(envelope,bundle["dev_traits"],env)
	return FunctionalPhenotype.compile({"genome":bundle["genome"],"ph2_realized":ph2,"traits_extension":bundle["ext_traits"],"environment_sample":env,"age_fraction":1.0})

static func _position(index: int) -> Vector2:
	var ix := index % GRID_SIDE
	var iz := int(index / GRID_SIDE)
	var half := float(GRID_SIDE - 1) * SPACING_M * 0.5
	return Vector2(snappedf(float(ix)*SPACING_M-half,1e-9),snappedf(float(iz)*SPACING_M-half,1e-9))

static func _light_record(identity:String,x:float,z:float,fp:Dictionary,base_sunlight:float)->Dictionary:
	return {"identity":identity,"world_x_m":x,"world_z_m":z,"realized_height_m":float(fp["realized_height_m"]),"realized_crown_radius_m":float(fp["realized_crown_radius_m"]),"realized_crown_density":float(fp["realized_crown_density"]),"leaf_area_index_proxy":float(fp["leaf_area_index_proxy"]),"base_sunlight":base_sunlight,"shade_output_ppm":int(fp["shade_output_ppm"]),"source_phenotype_hash":String(fp["phenotype_hash"])}

static func _water_record(identity:String,fp:Dictionary)->Dictionary:
	return {"identity":identity,"cell_identity":"zone-cell","realized_root_depth_m":float(fp["realized_root_depth_m"]),"realized_root_spread_m":float(fp["realized_root_spread_m"]),"root_shoot_ratio":float(fp["root_shoot_ratio"]),"leaf_area_index_proxy":float(fp["leaf_area_index_proxy"]),"transpiration_demand_ppm":int(fp["transpiration_demand_ppm"]),"shade_output_ppm":int(fp["shade_output_ppm"]),"source_phenotype_hash":String(fp["phenotype_hash"])}

static func _static_canopy_present(canopy_mode:String,cycle:int)->bool:
	return canopy_mode == "persistent" or (canopy_mode == "gap" and cycle <= GAP_REMOVAL_CYCLE)

static func _static_canopy_light_record(index:int,base_sunlight:float)->Dictionary:
	var angle := TAU * float(index) / 8.0
	return {"identity":"static-canopy-%02d" % index,"world_x_m":cos(angle)*1.1,"world_z_m":sin(angle)*1.1,"realized_height_m":7.5,"realized_crown_radius_m":1.8,"realized_crown_density":0.88,"leaf_area_index_proxy":2.8,"base_sunlight":base_sunlight,"shade_output_ppm":230000,"source_phenotype_hash":("static-canopy-%02d" % index).sha256_text()}

static func _static_canopy_water_record(index:int,light_record:Dictionary)->Dictionary:
	return {"identity":"static-canopy-%02d" % index,"cell_identity":"zone-cell","realized_root_depth_m":2.8,"realized_root_spread_m":2.5,"root_shoot_ratio":0.55,"leaf_area_index_proxy":2.8,"transpiration_demand_ppm":170000,"shade_output_ppm":int(light_record["shade_output_ppm"]),"source_phenotype_hash":String(light_record["source_phenotype_hash"])}

static func _effect_suppression(water_field:Dictionary,identity:String)->int:
	for effect in water_field.get("effects",[]):
		if String(effect.get("plant_identity","")) == identity: return int(effect.get("evaporation_suppression_ppm",0))
	return 0

static func _rank_order(a:Dictionary,b:Dictionary)->bool:
	if float(a["fitness"]) != float(b["fitness"]): return float(a["fitness"]) > float(b["fitness"])
	return String(a["bundle"]["bundle_checksum"]) < String(b["bundle"]["bundle_checksum"])

static func _geometry_distinct(a:Dictionary,b:Dictionary)->bool:
	for field_name in FEATURE_FIELDS:
		if absf(float(a[field_name])-float(b[field_name])) >= float(Morphology.GEOMETRY_THRESHOLDS[field_name]): return true
	return false

static func _geometry_cluster_count(zones:Dictionary)->int:
	var representatives: Array[Dictionary] = []
	for zone_name in ZONE_ORDER:
		var features: Dictionary = zones[zone_name]["mean_features"]
		var matched := false
		for representative in representatives:
			if not _geometry_distinct(features,representative):
				matched = true
				break
		if not matched: representatives.append(features)
	return representatives.size()

static func _result_hash(result:Dictionary)->String:
	var tokens := PackedStringArray([SCHEMA,VERSION,REVISION,str(int(result["lineage_seed"])),str(int(result["cycles"])),"1" if bool(result["feedback_enabled"]) else "0",String(result["policy_hash"]),String(result["common_first_candidate_pool_hash"])])
	for zone_name in ZONE_ORDER:
		var zone:Dictionary = result["zones"][zone_name]
		tokens.append("%s:%s:%s:%d" % [zone_name,String(zone["final_population_hash"]),String(zone["final_soil_state_hash"]),int(zone["organic_matter_ppm"])])
	return "|".join(tokens).sha256_text()
