extends RefCounted

## ECO.EVO7 FFF3.1 causality repair.
##
## The historical FFF3 bridge proved a light feedback response, but its development
## reproduction_event included environment/sunlight data. Because that event is an
## input to Contract.derive_individual_seed(), feedback ON/OFF could receive different
## stochastic growth-skeleton seeds. This probe freezes that identity explicitly:
## candidate bundle -> stable seed tag, independent of environment and mode.
## Only the EnvironmentSample sunlight assignment is allowed to differ.
const Morphology = preload("res://scripts/research/ecology/evo7_morphology_evolution_bridge_v1.gd")
const LineageExtension = preload("res://scripts/research/ecology/plant_mutation_lineage_extension_evo7_v1.gd")
const Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const CoupledDevelopment = preload("res://scripts/research/ecology/plant_environment_coupled_development_v1.gd")
const FunctionalPhenotype = preload("res://scripts/research/ecology/plant_functional_phenotype_v1.gd")
const EnvSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const LightField = preload("res://scripts/research/ecology/understory_light_field_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_light_feedback_counterfactual.v2"
const VERSION := "2.0.0"
const REVISION := "ECO.EVO7-FFF3.1-R1"
const CANDIDATE_COUNT := 36
const SELECTED_COUNT := 12
const GRID_SIDE := 6
const SPACING_M := 0.28
const LIGHT_SELECTION_STRENGTH := 1.50

static func stable_seed_tag(bundle: Dictionary) -> String:
	var individual_seed := int(bundle.get("individual_seed", -1))
	if individual_seed < 0:
		return ""
	return "evo7-fff31-eval|%d" % individual_seed

static func run_all(lineage_seed := 20260824) -> Dictionary:
	var ancestor := Morphology.default_ancestor_bundle(lineage_seed)
	if ancestor.is_empty():
		return {}
	var policy := LineageExtension.default_policy()
	policy["morphology_probability"] = 0.55
	policy["genome_policy"]["mutation_probability"] = 0.55
	if LineageExtension.policy_hash(policy).is_empty():
		return {}

	var candidates: Array[Dictionary] = []
	var pool_tokens := PackedStringArray()
	for index in CANDIDATE_COUNT:
		var mutation_seed := ("EVO7-FFF31|%d|%d" % [lineage_seed, index]).hash()
		var child := LineageExtension.reproduce_bundle(ancestor, mutation_seed, index, policy)
		if child.is_empty():
			return {}
		candidates.append({"identity": "c%03d" % index, "bundle": child["bundle"]})
		pool_tokens.append(String(child["result_hash"]))
	var candidate_pool_hash := "|".join(pool_tokens).sha256_text()

	var base_env := EnvSample.create(0.0, 0.0, 21.0, 0.52, 0.86, 0.52, 0.02, lineage_seed, "ECO.EVO7-FFF31|base")
	if base_env.is_empty():
		return {}
	var records: Array = []
	for index in candidates.size():
		var candidate: Dictionary = candidates[index]
		var fp := _functional(candidate["bundle"], base_env)
		if fp.is_empty():
			return {}
		var pos := _position(index)
		records.append({
			"identity": String(candidate["identity"]),
			"world_x_m": float(pos.x),
			"world_z_m": float(pos.y),
			"realized_height_m": float(fp["realized_height_m"]),
			"realized_crown_radius_m": float(fp["realized_crown_radius_m"]),
			"realized_crown_density": float(fp["realized_crown_density"]),
			"leaf_area_index_proxy": float(fp["leaf_area_index_proxy"]),
			"base_sunlight": float(base_env["sunlight"]),
			"shade_output_ppm": int(fp["shade_output_ppm"]),
			"source_phenotype_hash": String(fp["phenotype_hash"]),
		})
	var field := LightField.compute(records)
	if field.is_empty():
		return {}

	var feedback_on := _score_mode(candidates, field, base_env, true)
	var feedback_off := _score_mode(candidates, field, base_env, false)
	if feedback_on.is_empty() or feedback_off.is_empty():
		return {}
	if String(feedback_on["realization_seed_hash"]) != String(feedback_off["realization_seed_hash"]):
		return {}

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"lineage_seed": lineage_seed,
		"candidate_count": CANDIDATE_COUNT,
		"selected_count": SELECTED_COUNT,
		"candidate_pool_hash": candidate_pool_hash,
		"field_hash": String(field["field_hash"]),
		"feedback_on": feedback_on,
		"feedback_off": feedback_off,
		"counterfactual_identity_equal": true,
	}
	result["result_hash"] = _result_hash(result)
	return result

static func _score_mode(candidates: Array[Dictionary], field: Dictionary, base_env: Dictionary, feedback_enabled: bool) -> Dictionary:
	var scored: Array[Dictionary] = []
	var seed_tokens := PackedStringArray()
	var score_tokens := PackedStringArray()
	var env_tokens := PackedStringArray()
	var light_sum := 0.0
	for index in candidates.size():
		var candidate: Dictionary = candidates[index]
		var identity := String(candidate["identity"])
		var effective_light := float(base_env["sunlight"])
		if feedback_enabled:
			effective_light = float(field["plant_light"][identity]["understory_light"])
		var env := EnvSample.create(
			0.0, 0.0,
			float(base_env["temperature_c"]), float(base_env["soil_moisture"]),
			clampf(effective_light, 0.0, 1.0), float(base_env["nutrients"]),
			float(base_env["flood_frequency"]), int(base_env["seed"]),
			"ECO.EVO7-FFF31|%s|%s" % ["on" if feedback_enabled else "off", identity]
		)
		var fp := _functional(candidate["bundle"], env)
		if fp.is_empty():
			return {}
		var shade_tolerance := float(candidate["bundle"]["genome"]["shade_tolerance"])
		var light_fraction := clampf(effective_light / maxf(float(base_env["sunlight"]), 0.001), 0.0, 1.0)
		var light_deficit := 1.0 - light_fraction
		var light_selection := LIGHT_SELECTION_STRENGTH * light_deficit * (2.0 * shade_tolerance - 1.0)
		var fitness := snappedf(float(fp["net_resource_proxy"]) + light_selection, 1e-9)
		scored.append({"identity": identity, "bundle": candidate["bundle"], "fitness": fitness})
		seed_tokens.append("%s:%d" % [identity, int(fp["individual_seed"])])
		score_tokens.append("%s:%.9f" % [identity, fitness])
		env_tokens.append("%s:%.9f" % [identity, effective_light])
		light_sum += effective_light
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a["fitness"]) != float(b["fitness"]):
			return float(a["fitness"]) > float(b["fitness"])
		return String(a["bundle"]["bundle_checksum"]) < String(b["bundle"]["bundle_checksum"]))
	var selected_tokens := PackedStringArray()
	for index in mini(SELECTED_COUNT, scored.size()):
		selected_tokens.append(String(scored[index]["bundle"]["bundle_checksum"]))
	selected_tokens.sort()
	return {
		"mode": "feedback_on" if feedback_enabled else "feedback_off",
		"realization_seed_hash": "|".join(seed_tokens).sha256_text(),
		"score_hash": "|".join(score_tokens).sha256_text(),
		"environment_assignment_hash": "|".join(env_tokens).sha256_text(),
		"selected_population_hash": "|".join(selected_tokens).sha256_text(),
		"mean_effective_light": snappedf(light_sum / float(candidates.size()), 1e-9),
	}

static func _functional(bundle: Dictionary, env: Dictionary) -> Dictionary:
	var seed_tag := stable_seed_tag(bundle)
	if seed_tag.is_empty():
		return {}
	var envelope := Contract.create_seed_envelope(
		bundle["genome"], bundle["dev_traits"], String(bundle["lineage"]["lineage_id"]), seed_tag, 0, 1.25)
	var ph2 := CoupledDevelopment.realize(envelope, bundle["dev_traits"], env)
	return FunctionalPhenotype.compile({
		"genome": bundle["genome"],
		"ph2_realized": ph2,
		"traits_extension": bundle["ext_traits"],
		"environment_sample": env,
		"age_fraction": 1.0,
	})

static func _position(index: int) -> Vector2:
	var x := index % GRID_SIDE
	var z := index / GRID_SIDE
	var half := float(GRID_SIDE - 1) * 0.5 * SPACING_M
	return Vector2(snappedf(float(x) * SPACING_M - half, 1e-9), snappedf(float(z) * SPACING_M - half, 1e-9))

static func _result_hash(result: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SCHEMA, VERSION, REVISION,
		str(int(result.get("lineage_seed", 0))),
		String(result.get("candidate_pool_hash", "")),
		String(result.get("field_hash", "")),
		String(result.get("feedback_on", {}).get("realization_seed_hash", "")),
		String(result.get("feedback_on", {}).get("selected_population_hash", "")),
		String(result.get("feedback_off", {}).get("selected_population_hash", "")),
	])).sha256_text()
