extends RefCounted

const Fixture = preload("res://scripts/research/ecology/synthetic_environment_fixture_v1.gd")
const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const MutationKernel = preload("res://scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd")
const ResourceModel = preload("res://scripts/research/ecology/plant_resource_model_v1.gd")
const PatchSimulator = preload("res://scripts/research/ecology/single_plant_patch_simulator_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.p1c_strategy_competition_baseline.v1"
const VERSION := "1.0.0"
const EXPERIMENT_REVISION := "ECO.P1C-S1.1"
const DEFAULT_GRID_SIZE := 7
const DEFAULT_FOUNDER_COUNT := 20
const DEFAULT_WINNERS_PER_PATCH := 4
const DEFAULT_EVALUATION_SEASONS := 20
const DEFAULT_FOUNDER_SEED := 1138701
const ALT_FOUNDER_SEED := 1138702
const REGION_NAMES: Array[String] = ["DRY", "WET", "SHADED", "SUNLIT"]
const TRAITS: Array[String] = [
	"height_m", "growth_rate", "root_depth_m", "water_preference",
	"water_tolerance_width", "shade_tolerance", "seed_count", "lifespan_years"
]

static func run(
	grid_size: int = DEFAULT_GRID_SIZE,
	founder_count: int = DEFAULT_FOUNDER_COUNT,
	winners_per_patch: int = DEFAULT_WINNERS_PER_PATCH,
	evaluation_seasons: int = DEFAULT_EVALUATION_SEASONS,
	founder_seed: int = DEFAULT_FOUNDER_SEED,
	uniform_control: bool = false
) -> Dictionary:
	if grid_size < 5 or founder_count < 8 or winners_per_patch < 2 or winners_per_patch >= founder_count or evaluation_seasons <= 0:
		return {}
	var founders := create_founder_pool(founder_count, founder_seed)
	if founders.size() != founder_count:
		return {}
	var patches: Array = []
	var uniform_environment := _uniform_environment_for_grid(grid_size) if uniform_control else {}
	if uniform_control and uniform_environment.is_empty():
		return {}
	var global_win_counts := {}
	var global_top1_counts := {}
	for founder in founders:
		global_win_counts[int(founder["founder_index"])] = 0
		global_top1_counts[int(founder["founder_index"])] = 0
	for iz in range(grid_size):
		for ix in range(grid_size):
			var patch_index := iz * grid_size + ix
			var position := Fixture.grid_position(ix, iz, grid_size)
			var environment := Fixture.sample_at(position.x, position.y)
			var selection_environment: Dictionary = uniform_environment if uniform_control else environment
			var evaluations: Array = []
			for founder in founders:
				var genome: Dictionary = founder["genome"]
				var sim := PatchSimulator.simulate(selection_environment, genome, evaluation_seasons, PatchSimulator.DEFAULT_INITIAL_BIOMASS_KG_M2)
				var balance := ResourceModel.evaluate(selection_environment, genome, PatchSimulator.DEFAULT_INITIAL_BIOMASS_KG_M2)
				if sim.is_empty() or balance.is_empty():
					return {}
				evaluations.append({
					"founder_index": int(founder["founder_index"]),
					"genome_checksum": String(genome["checksum"]),
					"lineage_id": String(founder["lineage"]["lineage_id"]),
					"cumulative_recruitment": float(sim["cumulative_recruitment_kg_m2"]),
					"final_biomass": float(sim["final_biomass_kg_m2"]),
					"final_net": float(sim["final_net_resource_balance"]),
					"initial_net": float(balance["net_resource_balance"]),
				})
			evaluations.sort_custom(_candidate_before)
			var winners: Array = []
			for rank in range(winners_per_patch):
				var winner: Dictionary = evaluations[rank]
				winners.append(winner.duplicate(true))
				var wi := int(winner["founder_index"])
				global_win_counts[wi] = int(global_win_counts[wi]) + 1
				if rank == 0:
					global_top1_counts[wi] = int(global_top1_counts[wi]) + 1
			patches.append({
				"patch_index": patch_index,
				"ix": ix,
				"iz": iz,
				"world_x_m": position.x,
				"world_z_m": position.y,
				"environment": environment,
				"winners": winners,
				"winner_hash": _winner_hash(winners),
			})
	var diagnostics := _diagnostic_regions(patches)
	var region_competition := _region_competition(patches, diagnostics)
	var diversity := _diversity_summary(founders, global_win_counts, global_top1_counts, patches.size(), winners_per_patch)
	var tradeoffs := _tradeoff_audit(founders)
	if region_competition.is_empty() or diversity.is_empty() or tradeoffs.is_empty():
		return {}
	var founder_tokens := PackedStringArray()
	for founder in founders:
		founder_tokens.append("%d|%s|%s" % [int(founder["founder_index"]), String(founder["genome"]["checksum"]), String(founder["lineage"]["checksum"])])
	var patch_tokens := PackedStringArray()
	for patch in patches:
		patch_tokens.append("%d|%s" % [int(patch["patch_index"]), String(patch["winner_hash"])])
	var unique_patch_winner_sets := {}
	for patch in patches:
		unique_patch_winner_sets[String(patch["winner_hash"])] = true
	diversity["unique_patch_winner_sets"] = unique_patch_winner_sets.size()
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"experiment_revision": EXPERIMENT_REVISION,
		"grid_size": grid_size,
		"patch_count": patches.size(),
		"founder_count": founder_count,
		"winners_per_patch": winners_per_patch,
		"evaluation_seasons": evaluation_seasons,
		"founder_seed": founder_seed,
		"uniform_control": uniform_control,
		"founder_pool_hash": "\n".join(founder_tokens).sha256_text(),
		"field_winner_hash": "\n".join(patch_tokens).sha256_text(),
		"founders": _founder_summaries(founders, global_win_counts, global_top1_counts),
		"diagnostic_regions": diagnostics,
		"region_competition": region_competition,
		"diversity": diversity,
		"tradeoffs": tradeoffs,
	}
	result["result_hash"] = _result_hash(result)
	return result

static func create_founder_pool(founder_count: int = DEFAULT_FOUNDER_COUNT, founder_seed: int = DEFAULT_FOUNDER_SEED) -> Array:
	if founder_count < 1:
		return []
	var baseline := PlantGenome.create_default()
	var founders: Array = []
	var seen := {}
	for i in range(founder_count):
		var genome := PlantGenome.create(
			"plant-genome/p1c-s1-founder-%02d" % i,
			clampf(float(baseline["height_m"]) + _signed(founder_seed, i, "height_m") * 0.65, 0.55, 2.65),
			clampf(float(baseline["growth_rate"]) + _signed(founder_seed, i, "growth_rate") * 0.16, 0.30, 0.95),
			clampf(float(baseline["root_depth_m"]) + _signed(founder_seed, i, "root_depth_m") * 0.45, 0.20, 1.60),
			clampf(float(baseline["water_preference"]) + _signed(founder_seed, i, "water_preference") * 0.15, 0.15, 0.90),
			clampf(float(baseline["water_tolerance_width"]) + _signed(founder_seed, i, "water_tolerance_width") * 0.10, 0.08, 0.60),
			clampf(float(baseline["shade_tolerance"]) + _signed(founder_seed, i, "shade_tolerance") * 0.18, 0.05, 0.90),
			clampi(int(round(float(baseline["seed_count"]) + _signed(founder_seed, i, "seed_count") * 40.0)), 24, 160),
			float(baseline["seed_dispersal_distance_m"]),
			clampf(float(baseline["lifespan_years"]) + _signed(founder_seed, i, "lifespan_years") * 2.20, 1.5, 9.0)
		)
		if not bool(PlantGenome.validate(genome).get("success", false)):
			return []
		if seen.has(String(genome["checksum"])):
			return []
		seen[String(genome["checksum"])] = true
		var lineage := MutationKernel.create_ancestor(genome, founder_seed + i * 7919)
		if lineage.is_empty():
			return []
		founders.append({"founder_index": i, "genome": genome, "lineage": lineage})
	return founders

static func _candidate_before(a: Dictionary, b: Dictionary) -> bool:
	var ar := float(a["cumulative_recruitment"])
	var br := float(b["cumulative_recruitment"])
	if absf(ar - br) > 0.000000000001:
		return ar > br
	var ab := float(a["final_biomass"])
	var bb := float(b["final_biomass"])
	if absf(ab - bb) > 0.000000000001:
		return ab > bb
	var an := float(a["final_net"])
	var bn := float(b["final_net"])
	if absf(an - bn) > 0.000000000001:
		return an > bn
	return String(a["genome_checksum"]) < String(b["genome_checksum"])

static func _diagnostic_regions(patches: Array) -> Dictionary:
	var moisture: Array[float] = []
	var light: Array[float] = []
	for patch in patches:
		moisture.append(float(patch["environment"]["soil_moisture"]))
		light.append(float(patch["environment"]["sunlight"]))
	moisture.sort()
	light.sort()
	var mq25 := _quantile(moisture, 0.25)
	var mq75 := _quantile(moisture, 0.75)
	var lq25 := _quantile(light, 0.25)
	var lq75 := _quantile(light, 0.75)
	var regions := {"DRY": [], "WET": [], "SHADED": [], "SUNLIT": []}
	for patch in patches:
		var m := float(patch["environment"]["soil_moisture"])
		var l := float(patch["environment"]["sunlight"])
		var pi := int(patch["patch_index"])
		if m <= mq25: regions["DRY"].append(pi)
		if m >= mq75: regions["WET"].append(pi)
		if l <= lq25: regions["SHADED"].append(pi)
		if l >= lq75: regions["SUNLIT"].append(pi)
	return {"thresholds": {"moisture_q25": mq25, "moisture_q75": mq75, "sunlight_q25": lq25, "sunlight_q75": lq75}, "patches": regions}

static func _region_competition(patches: Array, diagnostics: Dictionary) -> Dictionary:
	var by_index := {}
	for patch in patches:
		by_index[int(patch["patch_index"])] = patch
	var result := {}
	for region_name in REGION_NAMES:
		var counts := {}
		var top1 := {}
		var indices: Array = diagnostics["patches"][region_name]
		for patch_index in indices:
			var patch: Dictionary = by_index[int(patch_index)]
			for rank in range(Array(patch["winners"]).size()):
				var fi := int(patch["winners"][rank]["founder_index"])
				counts[fi] = int(counts.get(fi, 0)) + 1
				if rank == 0:
					top1[fi] = int(top1.get(fi, 0)) + 1
		var ordered := _ordered_counts(counts)
		var top_founder := -1 if ordered.is_empty() else int(ordered[0]["founder_index"])
		result[region_name] = {"patch_count": indices.size(), "winner_counts": ordered, "top_founder": top_founder, "unique_winners": counts.size(), "top1_counts": _ordered_counts(top1)}
	return result

static func _diversity_summary(founders: Array, win_counts: Dictionary, top1_counts: Dictionary, patch_count: int, winners_per_patch: int) -> Dictionary:
	var persistent := 0
	var top1_persistent := 0
	var max_wins := 0
	var max_top1 := 0
	var total_slots := patch_count * winners_per_patch
	var shannon := 0.0
	for founder in founders:
		var fi := int(founder["founder_index"])
		var wins := int(win_counts.get(fi, 0))
		var tops := int(top1_counts.get(fi, 0))
		if wins > 0: persistent += 1
		if tops > 0: top1_persistent += 1
		max_wins = maxi(max_wins, wins)
		max_top1 = maxi(max_top1, tops)
		if wins > 0:
			var p := float(wins) / float(total_slots)
			shannon -= p * log(p)
	return {
		"persistent_founders": persistent,
		"top1_persistent_founders": top1_persistent,
		"dominance_ratio": float(max_wins) / float(total_slots),
		"top1_dominance_ratio": float(max_top1) / float(patch_count),
		"shannon_winner_diversity": shannon,
		"total_winner_slots": total_slots,
	}

static func _tradeoff_audit(founders: Array) -> Dictionary:
	var base := PlantGenome.create_default()
	var lower := Fixture.control_point("lower_slope")
	var dry := Fixture.control_point("dry_ridge")
	var flood := Fixture.control_point("floodplain")
	var sunny := Fixture.control_point("sunny_slope")
	var shaded := Fixture.control_point("shaded_slope")
	var low_height := _variant(base, "p1c-height-low", {"height_m": 0.8})
	var high_height := _variant(base, "p1c-height-high", {"height_m": 2.4})
	var low_root := _variant(base, "p1c-root-low", {"root_depth_m": 0.30})
	var high_root := _variant(base, "p1c-root-high", {"root_depth_m": 1.50})
	var low_growth := _variant(base, "p1c-growth-low", {"growth_rate": 0.35})
	var high_growth := _variant(base, "p1c-growth-high", {"growth_rate": 0.90})
	var low_seed := _variant(base, "p1c-seed-low", {"seed_count": 20})
	var high_seed := _variant(base, "p1c-seed-high", {"seed_count": 140})
	var low_shade := _variant(base, "p1c-shade-low", {"shade_tolerance": 0.15})
	var high_shade := _variant(base, "p1c-shade-high", {"shade_tolerance": 0.75})
	var short_life := _variant(base, "p1c-life-short", {"lifespan_years": 2.0})
	var long_life := _variant(base, "p1c-life-long", {"lifespan_years": 8.0})
	for genome in [low_height, high_height, low_root, high_root, low_growth, high_growth, low_seed, high_seed, low_shade, high_shade, short_life, long_life]:
		if genome.is_empty(): return {}
	var lh := ResourceModel.evaluate(lower, low_height); var hh := ResourceModel.evaluate(lower, high_height)
	var lr_dry := ResourceModel.evaluate(dry, low_root); var hr_dry := ResourceModel.evaluate(dry, high_root)
	var lr_flood := ResourceModel.evaluate(flood, low_root); var hr_flood := ResourceModel.evaluate(flood, high_root)
	var lg := ResourceModel.evaluate(lower, low_growth); var hg := ResourceModel.evaluate(lower, high_growth)
	var ls := ResourceModel.evaluate(lower, low_seed); var hs := ResourceModel.evaluate(lower, high_seed)
	var low_seed_sim := PatchSimulator.simulate(lower, low_seed, DEFAULT_EVALUATION_SEASONS); var high_seed_sim := PatchSimulator.simulate(lower, high_seed, DEFAULT_EVALUATION_SEASONS)
	var lsh_sun := ResourceModel.evaluate(sunny, low_shade); var hsh_sun := ResourceModel.evaluate(sunny, high_shade)
	var lsh_shade := ResourceModel.evaluate(shaded, low_shade); var hsh_shade := ResourceModel.evaluate(shaded, high_shade)
	var short_sim := PatchSimulator.simulate(lower, short_life, DEFAULT_EVALUATION_SEASONS); var long_sim := PatchSimulator.simulate(lower, long_life, DEFAULT_EVALUATION_SEASONS)
	return {
		"height_extra_cost": (float(hh["maintenance_cost"]) + float(hh["structural_cost"])) - (float(lh["maintenance_cost"]) + float(lh["structural_cost"])),
		"root_extra_cost": float(hr_dry["root_cost"]) - float(lr_dry["root_cost"]),
		"deep_root_dry_net_gain": float(hr_dry["net_resource_balance"]) - float(lr_dry["net_resource_balance"]),
		"deep_root_flood_net_gain": float(hr_flood["net_resource_balance"]) - float(lr_flood["net_resource_balance"]),
		"growth_extra_cost": (float(hg["maintenance_cost"]) + float(hg["growth_allocation_cost"])) - (float(lg["maintenance_cost"]) + float(lg["growth_allocation_cost"])),
		"seed_extra_cost": float(hs["reproduction_allocation_cost"]) - float(ls["reproduction_allocation_cost"]),
		"seed_recruitment_gain": float(high_seed_sim["cumulative_recruitment_kg_m2"]) - float(low_seed_sim["cumulative_recruitment_kg_m2"]),
		"shade_shaded_gross_gain": float(hsh_shade["gross_photosynthetic_income"]) - float(lsh_shade["gross_photosynthetic_income"]),
		"shade_sunny_net_gain": float(hsh_sun["net_resource_balance"]) - float(lsh_sun["net_resource_balance"]),
		"long_life_mortality_delta": float(long_sim["cumulative_mortality_kg_m2"]) - float(short_sim["cumulative_mortality_kg_m2"]),
		"trait_ranges": _trait_ranges(founders),
	}

static func _variant(base: Dictionary, genome_id: String, overrides: Dictionary) -> Dictionary:
	return PlantGenome.create(
		genome_id,
		float(overrides.get("height_m", base["height_m"])),
		float(overrides.get("growth_rate", base["growth_rate"])),
		float(overrides.get("root_depth_m", base["root_depth_m"])),
		float(overrides.get("water_preference", base["water_preference"])),
		float(overrides.get("water_tolerance_width", base["water_tolerance_width"])),
		float(overrides.get("shade_tolerance", base["shade_tolerance"])),
		int(overrides.get("seed_count", base["seed_count"])),
		float(overrides.get("seed_dispersal_distance_m", base["seed_dispersal_distance_m"])),
		float(overrides.get("lifespan_years", base["lifespan_years"]))
	)

static func _uniform_environment_for_grid(grid_size: int) -> Dictionary:
	var sums := {"temperature_c": 0.0, "soil_moisture": 0.0, "sunlight": 0.0, "nutrients": 0.0, "flood_frequency": 0.0}
	var count := 0
	for iz in range(grid_size):
		for ix in range(grid_size):
			var pos := Fixture.grid_position(ix, iz, grid_size)
			var env := Fixture.sample_at(pos.x, pos.y)
			for key in sums.keys(): sums[key] = float(sums[key]) + float(env[key])
			count += 1
	if count <= 0: return {}
	return EnvironmentSample.create(0.0, 0.0, float(sums["temperature_c"]) / count, float(sums["soil_moisture"]) / count, float(sums["sunlight"]) / count, float(sums["nutrients"]) / count, float(sums["flood_frequency"]) / count, Fixture.DEFAULT_SEED, Fixture.ENVIRONMENT_REVISION)

static func _founder_summaries(founders: Array, wins: Dictionary, top1: Dictionary) -> Array:
	var result: Array = []
	for founder in founders:
		var genome: Dictionary = founder["genome"]
		var traits := {}
		for trait_name in TRAITS:
			traits[trait_name] = genome[trait_name]
		var fi := int(founder["founder_index"])
		result.append({"founder_index": fi, "genome_checksum": String(genome["checksum"]), "lineage_id": String(founder["lineage"]["lineage_id"]), "traits": traits, "winner_slots": int(wins.get(fi, 0)), "top1_patches": int(top1.get(fi, 0))})
	return result

static func _trait_ranges(founders: Array) -> Dictionary:
	var result := {}
	for trait_name in TRAITS:
		var minimum := INF
		var maximum := -INF
		for founder in founders:
			var value := float(founder["genome"][trait_name])
			minimum = minf(minimum, value)
			maximum = maxf(maximum, value)
		result[trait_name] = {"min": minimum, "max": maximum, "span": maximum - minimum}
	return result

static func _ordered_counts(counts: Dictionary) -> Array:
	var result: Array = []
	for key in counts.keys():
		result.append({"founder_index": int(key), "count": int(counts[key])})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["count"]) != int(b["count"]): return int(a["count"]) > int(b["count"])
		return int(a["founder_index"]) < int(b["founder_index"]))
	return result

static func _winner_hash(winners: Array) -> String:
	var tokens := PackedStringArray()
	for winner in winners:
		tokens.append("%d|%s|%.9f|%.9f|%.9f" % [int(winner["founder_index"]), String(winner["genome_checksum"]), float(winner["cumulative_recruitment"]), float(winner["final_biomass"]), float(winner["final_net"])])
	return "\n".join(tokens).sha256_text()

static func _result_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([SCHEMA, VERSION, EXPERIMENT_REVISION, str(int(result["founder_seed"])), "1" if bool(result["uniform_control"]) else "0", String(result["founder_pool_hash"]), String(result["field_winner_hash"])])
	var diversity: Dictionary = result["diversity"]
	for key in ["persistent_founders", "top1_persistent_founders", "dominance_ratio", "top1_dominance_ratio", "shannon_winner_diversity"]:
		tokens.append("%s=%s" % [key, str(diversity[key])])
	for region_name in REGION_NAMES:
		tokens.append("%s=%d" % [region_name, int(result["region_competition"][region_name]["top_founder"])])
	return "|".join(tokens).sha256_text()

static func _signed(seed: int, founder_index: int, trait_name: String) -> float:
	var token := "%s|%d|%d|%s" % [EXPERIMENT_REVISION, seed, founder_index, trait_name]
	var unit := float(token.sha256_text().substr(0, 12).hex_to_int()) / 281474976710655.0
	return unit * 2.0 - 1.0

static func _quantile(values: Array[float], q: float) -> float:
	if values.is_empty(): return 0.0
	var i := int(round(float(values.size() - 1) * clampf(q, 0.0, 1.0)))
	return values[i]

static func _pearson(a: Array, b: Array) -> float:
	if a.size() != b.size() or a.size() < 2: return 0.0
	var ma := 0.0; var mb := 0.0
	for i in range(a.size()): ma += float(a[i]); mb += float(b[i])
	ma /= float(a.size()); mb /= float(b.size())
	var cov := 0.0; var va := 0.0; var vb := 0.0
	for i in range(a.size()):
		var da := float(a[i]) - ma; var db := float(b[i]) - mb
		cov += da * db; va += da * da; vb += db * db
	if va <= 0.0 or vb <= 0.0: return 0.0
	return cov / sqrt(va * vb)
