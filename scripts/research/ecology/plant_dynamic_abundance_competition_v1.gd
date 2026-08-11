extends RefCounted

const Fixture = preload("res://scripts/research/ecology/synthetic_environment_fixture_v1.gd")
const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const PatchSimulator = preload("res://scripts/research/ecology/single_plant_patch_simulator_v1.gd")
const S1Competition = preload("res://scripts/research/ecology/plant_strategy_competition_baseline_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.p1c_dynamic_abundance_competition.v1"
const VERSION := "1.0.0"
const EXPERIMENT_REVISION := "ECO.P1C-S2.1"
const DEFAULT_GRID_SIZE := 5
const DEFAULT_FOUNDER_COUNT := 20
const DEFAULT_CYCLES := 12
const DEFAULT_SEASONS_PER_CYCLE := 3
const DEFAULT_FOUNDER_SEED := S1Competition.DEFAULT_FOUNDER_SEED
const ALT_FOUNDER_SEED := S1Competition.ALT_FOUNDER_SEED
const DEFAULT_INITIAL_TOTAL_BIOMASS_KG_M2 := 2.0
const PATCH_SHARED_CAPACITY_KG_M2 := PatchSimulator.MAX_BIOMASS_KG_M2
const EXTINCTION_BIOMASS_KG_M2 := 0.000001

static func run(
	grid_size: int = DEFAULT_GRID_SIZE,
	founder_count: int = DEFAULT_FOUNDER_COUNT,
	cycles: int = DEFAULT_CYCLES,
	seasons_per_cycle: int = DEFAULT_SEASONS_PER_CYCLE,
	founder_seed: int = DEFAULT_FOUNDER_SEED,
	uniform_control: bool = false
) -> Dictionary:
	if grid_size < 5 or founder_count < 8 or cycles <= 0 or seasons_per_cycle <= 0:
		return {}
	var founders := S1Competition.create_founder_pool(founder_count, founder_seed)
	if founders.size() != founder_count:
		return {}
	var initial_per_founder := DEFAULT_INITIAL_TOTAL_BIOMASS_KG_M2 / float(founder_count)
	var patches: Array = []
	var uniform_environment := _uniform_environment_for_grid(grid_size) if uniform_control else {}
	if uniform_control and uniform_environment.is_empty():
		return {}
	for iz in range(grid_size):
		for ix in range(grid_size):
			var patch_index := iz * grid_size + ix
			var position := Fixture.grid_position(ix, iz, grid_size)
			var environment := Fixture.sample_at(position.x, position.y)
			var biomass: Array[float] = []
			biomass.resize(founder_count)
			for founder_index in range(founder_count):
				biomass[founder_index] = initial_per_founder
			patches.append({
				"patch_index": patch_index,
				"ix": ix,
				"iz": iz,
				"world_x_m": position.x,
				"world_z_m": position.y,
				"environment": environment,
				"biomass": biomass,
			})
	var history: Array = [_field_summary(patches, founders, uniform_environment if uniform_control else {}, 0)]
	if Dictionary(history[0]).is_empty():
		return {}
	for cycle in range(1, cycles + 1):
		for patch in patches:
			var environment: Dictionary = uniform_environment if uniform_control else patch["environment"]
			var current: Array = patch["biomass"]
			var proposed: Array[float] = []
			proposed.resize(founder_count)
			var proposed_total := 0.0
			for founder in founders:
				var founder_index := int(founder["founder_index"])
				var current_biomass := float(current[founder_index])
				if current_biomass <= EXTINCTION_BIOMASS_KG_M2:
					proposed[founder_index] = 0.0
					continue
				var sim := PatchSimulator.simulate(environment, founder["genome"], seasons_per_cycle, current_biomass)
				if sim.is_empty():
					return {}
				var next_biomass := maxf(float(sim["final_biomass_kg_m2"]), 0.0)
				if next_biomass <= EXTINCTION_BIOMASS_KG_M2:
					next_biomass = 0.0
				proposed[founder_index] = next_biomass
				proposed_total += next_biomass
			var capacity_scale := 1.0
			if proposed_total > PATCH_SHARED_CAPACITY_KG_M2:
				capacity_scale = PATCH_SHARED_CAPACITY_KG_M2 / proposed_total
			var next_values: Array[float] = []
			next_values.resize(founder_count)
			for founder_index in range(founder_count):
				var value := proposed[founder_index] * capacity_scale
				next_values[founder_index] = 0.0 if value <= EXTINCTION_BIOMASS_KG_M2 else value
			patch["biomass"] = next_values
		var summary := _field_summary(patches, founders, uniform_environment if uniform_control else {}, cycle)
		if summary.is_empty():
			return {}
		history.append(summary)
	var diagnostics := _diagnostic_regions(patches)
	var final_patches := _patch_summaries(patches, founders)
	var global := _global_abundance(final_patches, founder_count)
	var regions := _regional_abundance(final_patches, diagnostics, founder_count)
	var founder_tokens := PackedStringArray()
	for founder in founders:
		founder_tokens.append("%d|%s|%s" % [int(founder["founder_index"]), String(founder["genome"]["checksum"]), String(founder["lineage"]["checksum"])])
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"experiment_revision": EXPERIMENT_REVISION,
		"grid_size": grid_size,
		"patch_count": patches.size(),
		"founder_count": founder_count,
		"cycles": cycles,
		"seasons_per_cycle": seasons_per_cycle,
		"founder_seed": founder_seed,
		"uniform_control": uniform_control,
		"initial_total_biomass_kg_m2": DEFAULT_INITIAL_TOTAL_BIOMASS_KG_M2,
		"shared_patch_capacity_kg_m2": PATCH_SHARED_CAPACITY_KG_M2,
		"extinction_biomass_kg_m2": EXTINCTION_BIOMASS_KG_M2,
		"founder_pool_hash": "\n".join(founder_tokens).sha256_text(),
		"history": history,
		"diagnostic_regions": diagnostics,
		"global_abundance": global,
		"regional_abundance": regions,
		"patches": final_patches,
	}
	result["result_hash"] = _result_hash(result)
	return result

static func _field_summary(patches: Array, founders: Array, uniform_environment: Dictionary, cycle: int) -> Dictionary:
	var totals: Array[float] = []
	totals.resize(founders.size())
	for i in range(totals.size()): totals[i] = 0.0
	var total_biomass := 0.0
	var occupied_patch_slots := 0
	var patch_tokens := PackedStringArray()
	for patch in patches:
		var biomass: Array = patch["biomass"]
		var patch_total := 0.0
		for founder_index in range(biomass.size()):
			var value := float(biomass[founder_index])
			totals[founder_index] += value
			patch_total += value
			if value > EXTINCTION_BIOMASS_KG_M2:
				occupied_patch_slots += 1
		total_biomass += patch_total
		patch_tokens.append("%d|%s" % [int(patch["patch_index"]), _biomass_hash(biomass)])
	var persistent := 0
	var max_share := 0.0
	var shannon := 0.0
	for value in totals:
		if float(value) > EXTINCTION_BIOMASS_KG_M2:
			persistent += 1
		if total_biomass > 0.0 and float(value) > 0.0:
			var share := float(value) / total_biomass
			max_share = maxf(max_share, share)
			shannon -= share * log(share)
	return {
		"cycle": cycle,
		"total_biomass_kg_m2": total_biomass,
		"persistent_founders": persistent,
		"global_top1_biomass_share": max_share,
		"shannon_biomass_diversity": shannon,
		"occupied_patch_slots": occupied_patch_slots,
		"field_biomass_hash": "\n".join(patch_tokens).sha256_text(),
	}

static func _patch_summaries(patches: Array, founders: Array) -> Array:
	var result: Array = []
	for patch in patches:
		var biomass: Array = patch["biomass"]
		var total := 0.0
		for value in biomass: total += float(value)
		var entries: Array = []
		for founder in founders:
			var fi := int(founder["founder_index"])
			var value := float(biomass[fi])
			entries.append({
				"founder_index": fi,
				"biomass_kg_m2": value,
				"share": 0.0 if total <= 0.0 else value / total,
				"genome_checksum": String(founder["genome"]["checksum"]),
			})
		entries.sort_custom(_abundance_before)
		result.append({
			"patch_index": int(patch["patch_index"]),
			"ix": int(patch["ix"]),
			"iz": int(patch["iz"]),
			"world_x_m": float(patch["world_x_m"]),
			"world_z_m": float(patch["world_z_m"]),
			"environment": patch["environment"],
			"total_biomass_kg_m2": total,
			"abundance": entries,
			"abundance_hash": _abundance_hash(entries),
		})
	return result

static func _global_abundance(patches: Array, founder_count: int) -> Dictionary:
	var totals: Array[float] = []
	totals.resize(founder_count)
	for i in range(founder_count): totals[i] = 0.0
	var total := 0.0
	var top1_patch_counts := {}
	for patch in patches:
		for entry in Array(patch["abundance"]):
			var fi := int(entry["founder_index"])
			var value := float(entry["biomass_kg_m2"])
			totals[fi] += value
			total += value
		var top: Dictionary = patch["abundance"][0]
		if float(top["biomass_kg_m2"]) > EXTINCTION_BIOMASS_KG_M2:
			var top_index := int(top["founder_index"])
			top1_patch_counts[top_index] = int(top1_patch_counts.get(top_index, 0)) + 1
	var entries: Array = []
	var persistent := 0
	var effective_1pct := 0
	var effective_2pct := 0
	var effective_5pct := 0
	var shannon := 0.0
	var max_share := 0.0
	for fi in range(founder_count):
		var share := 0.0 if total <= 0.0 else totals[fi] / total
		if totals[fi] > EXTINCTION_BIOMASS_KG_M2: persistent += 1
		if share >= 0.01: effective_1pct += 1
		if share >= 0.02: effective_2pct += 1
		if share >= 0.05: effective_5pct += 1
		if share > 0.0: shannon -= share * log(share)
		max_share = maxf(max_share, share)
		entries.append({"founder_index": fi, "biomass_kg_m2": totals[fi], "share": share, "top1_patch_count": int(top1_patch_counts.get(fi, 0))})
	entries.sort_custom(_abundance_before)
	var max_top1 := 0
	for value in top1_patch_counts.values(): max_top1 = maxi(max_top1, int(value))
	return {
		"total_biomass_kg_m2": total,
		"persistent_founders": persistent,
		"effective_founders_1pct": effective_1pct,
		"effective_founders_2pct": effective_2pct,
		"effective_founders_5pct": effective_5pct,
		"top1_biomass_share": max_share,
		"top1_patch_dominance_ratio": float(max_top1) / float(patches.size()),
		"shannon_biomass_diversity": shannon,
		"founders": entries,
	}

static func _diagnostic_regions(patches: Array) -> Dictionary:
	var moisture: Array[float] = []
	var light: Array[float] = []
	for patch in patches:
		moisture.append(float(patch["environment"]["soil_moisture"]))
		light.append(float(patch["environment"]["sunlight"]))
	moisture.sort(); light.sort()
	var mq25 := _quantile(moisture, 0.25); var mq75 := _quantile(moisture, 0.75)
	var lq25 := _quantile(light, 0.25); var lq75 := _quantile(light, 0.75)
	var regions := {"DRY": [], "WET": [], "SHADED": [], "SUNLIT": []}
	for patch in patches:
		var m := float(patch["environment"]["soil_moisture"]); var l := float(patch["environment"]["sunlight"]); var pi := int(patch["patch_index"])
		if m <= mq25: regions["DRY"].append(pi)
		if m >= mq75: regions["WET"].append(pi)
		if l <= lq25: regions["SHADED"].append(pi)
		if l >= lq75: regions["SUNLIT"].append(pi)
	return {"thresholds": {"moisture_q25": mq25, "moisture_q75": mq75, "sunlight_q25": lq25, "sunlight_q75": lq75}, "patches": regions}

static func _regional_abundance(patches: Array, diagnostics: Dictionary, founder_count: int) -> Dictionary:
	var by_index := {}
	for patch in patches: by_index[int(patch["patch_index"])] = patch
	var result := {}
	for region_name in S1Competition.REGION_NAMES:
		var totals: Array[float] = []; totals.resize(founder_count)
		for i in range(founder_count): totals[i] = 0.0
		var total := 0.0
		var indices: Array = diagnostics["patches"][region_name]
		for patch_index in indices:
			var patch: Dictionary = by_index[int(patch_index)]
			for entry in Array(patch["abundance"]):
				var fi := int(entry["founder_index"]); var value := float(entry["biomass_kg_m2"])
				totals[fi] += value; total += value
		var entries: Array = []
		var persistent := 0
		for fi in range(founder_count):
			var share := 0.0 if total <= 0.0 else totals[fi] / total
			if totals[fi] > EXTINCTION_BIOMASS_KG_M2: persistent += 1
			entries.append({"founder_index": fi, "biomass_kg_m2": totals[fi], "share": share})
		entries.sort_custom(_abundance_before)
		result[region_name] = {"patch_count": indices.size(), "persistent_founders": persistent, "founders": entries, "top_founder": int(entries[0]["founder_index"]), "top_share": float(entries[0]["share"])}
	return result

static func _uniform_environment_for_grid(grid_size: int) -> Dictionary:
	var sums := {"temperature_c": 0.0, "soil_moisture": 0.0, "sunlight": 0.0, "nutrients": 0.0, "flood_frequency": 0.0}
	var count := 0.0
	for iz in range(grid_size):
		for ix in range(grid_size):
			var position := Fixture.grid_position(ix, iz, grid_size)
			var env := Fixture.sample_at(position.x, position.y)
			for key in sums.keys(): sums[key] = float(sums[key]) + float(env[key])
			count += 1.0
	return EnvironmentSample.create(0.0, 0.0, float(sums["temperature_c"])/count, float(sums["soil_moisture"])/count, float(sums["sunlight"])/count, float(sums["nutrients"])/count, float(sums["flood_frequency"])/count, Fixture.DEFAULT_SEED, Fixture.ENVIRONMENT_REVISION)

static func _abundance_before(a: Dictionary, b: Dictionary) -> bool:
	var av := float(a["biomass_kg_m2"]); var bv := float(b["biomass_kg_m2"])
	if absf(av - bv) > 0.000000000001: return av > bv
	return int(a["founder_index"]) < int(b["founder_index"])

static func _biomass_hash(values: Array) -> String:
	var tokens := PackedStringArray()
	for i in range(values.size()): tokens.append("%d:%s" % [i, _format_float(float(values[i]))])
	return "\n".join(tokens).sha256_text()

static func _abundance_hash(entries: Array) -> String:
	var tokens := PackedStringArray()
	for entry in entries: tokens.append("%d:%s:%s" % [int(entry["founder_index"]), _format_float(float(entry["biomass_kg_m2"])), _format_float(float(entry["share"]))])
	return "\n".join(tokens).sha256_text()

static func _result_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA, VERSION, String(result.get("experiment_revision", "")), str(int(result.get("grid_size", 0))), str(int(result.get("founder_count", 0))), str(int(result.get("cycles", 0))), str(int(result.get("seasons_per_cycle", 0))), str(int(result.get("founder_seed", 0))), str(bool(result.get("uniform_control", false))), String(result.get("founder_pool_hash", ""))
	])
	for summary in Array(result.get("history", [])):
		tokens.append("H|%d|%s|%s|%s|%s" % [int(summary["cycle"]), _format_float(float(summary["total_biomass_kg_m2"])), str(int(summary["persistent_founders"])), _format_float(float(summary["global_top1_biomass_share"])), String(summary["field_biomass_hash"])])
	for patch in Array(result.get("patches", [])): tokens.append("P|%d|%s" % [int(patch["patch_index"]), String(patch["abundance_hash"])])
	return "\n".join(tokens).sha256_text()

static func _quantile(sorted_values: Array[float], q: float) -> float:
	var position := clampf(q, 0.0, 1.0) * float(sorted_values.size() - 1)
	var lo := int(floor(position)); var hi := int(ceil(position)); var t := position - float(lo)
	return lerpf(sorted_values[lo], sorted_values[hi], t)

static func _format_float(value: float) -> String:
	return "%.9f" % value
