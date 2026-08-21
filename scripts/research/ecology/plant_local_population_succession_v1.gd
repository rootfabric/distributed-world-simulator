extends RefCounted

const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const ResourceModel = preload("res://scripts/research/ecology/plant_resource_model_v1.gd")
const Lifecycle = preload("res://scripts/research/ecology/plant_lifecycle_payoff_v1.gd")
const Dispersal = preload("res://scripts/research/ecology/plant_seed_dispersal_kernel_v1.gd")
const Establishment = preload("res://scripts/research/ecology/plant_establishment_seed_bank_v1.gd")
const RecruitmentTraits = preload("res://scripts/research/ecology/plant_recruitment_traits_v1.gd")
const PatchBaseline = preload("res://scripts/research/ecology/single_plant_patch_simulator_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo1_p2_3_local_population_succession.v1"
const VERSION := "1.0.0"
const LOCAL_DOMAIN := Rect2(-40.0, -40.0, 80.0, 80.0)
const EXTINCTION_BIOMASS_KG_M2 := 0.000001
const STRESS_MORTALITY_RATE := 0.24
const VEGETATIVE_GROWTH_RATE := 0.20
const EPSILON := 0.000000000001

static func simulate(
	strategies: Array,
	environment_schedule: Array,
	years: int,
	reproduction_enabled: bool = true
) -> Dictionary:
	if strategies.is_empty() or environment_schedule.is_empty() or years <= 0 or years > 200:
		return {}
	var by_lineage := {}
	for strategy_value in strategies:
		var strategy: Dictionary = strategy_value
		if not _valid_strategy(strategy):
			return {}
		var lineage := String(strategy["lineage_id"])
		if by_lineage.has(lineage):
			return {}
		by_lineage[lineage] = strategy
	for entry_value in environment_schedule:
		var entry: Dictionary = entry_value
		if int(entry.get("year_start", -1)) < 0:
			return {}
		if not bool(EnvironmentSample.validate(Dictionary(entry.get("environment", {}))).get("success", false)):
			return {}

	var context := Dispersal.create_context(Vector2.ZERO, 0.0, LOCAL_DOMAIN)
	if context.is_empty():
		return {}
	var adults: Array = []
	var banks: Array = []
	var cumulative_recruited := 0
	var cumulative_bank_reactivated := 0
	var cumulative_exported := 0
	var cumulative_emitted := 0
	var cumulative_mortality := 0.0
	var reproduction_events := 0
	var initial_environment := _environment_for_year(environment_schedule, 0)
	if initial_environment.is_empty():
		return {}

	var initial_recruits: Array = []
	for strategy_value in strategies:
		var strategy: Dictionary = strategy_value
		var genome: Dictionary = strategy["genome"]
		var emitted := int(genome["seed_count"])
		var event := _disperse_and_settle(
			strategy,
			initial_environment,
			context,
			"p2-3/initial/" + String(strategy["lineage_id"]),
			emitted,
			maxf(float(genome["height_m"]) * 0.50, 0.05),
			Vector2(strategy["source_position"])
		)
		if event.is_empty():
			return {}
		initial_recruits.append_array(Array(event["recruits"]))
		banks.append_array(Array(event["banks"]))
		cumulative_recruited += int(event["recruited_seed_count"])
		cumulative_exported += int(event["exported_seed_count"])
		cumulative_emitted += emitted
	adults.append_array(_adults_from_recruits(initial_recruits, by_lineage))
	adults = _merge_adults(adults)
	_apply_capacity(adults)

	var history: Array = []
	var initial_summary := _summary(0, adults, banks, by_lineage, cumulative_recruited, cumulative_bank_reactivated, cumulative_exported, cumulative_emitted, cumulative_mortality, reproduction_events)
	if initial_summary.is_empty():
		return {}
	history.append(initial_summary)
	var max_total_biomass := float(initial_summary["total_biomass_kg_m2"])
	var max_adult_cohorts := int(initial_summary["adult_cohort_count"])
	var max_bank_cohorts := int(initial_summary["seed_bank_cohort_count"])

	for year in range(1, years + 1):
		var environment := _environment_for_year(environment_schedule, year)
		if environment.is_empty():
			return {}

		var reactivated_recruits: Array = []
		var next_banks: Array = []
		for bank_value in banks:
			var bank: Dictionary = bank_value
			var lineage := String(bank.get("lineage_id", ""))
			if not by_lineage.has(lineage):
				return {}
			var strategy: Dictionary = by_lineage[lineage]
			var outcome := Establishment.advance_seed_bank(bank, strategy["genome"], strategy["recruitment_traits"], environment, 1.0)
			if outcome.is_empty() or not bool(outcome.get("conservation_ok", false)):
				return {}
			var recruit := Dictionary(outcome.get("recruitment_cohort", {}))
			if not recruit.is_empty():
				reactivated_recruits.append(recruit)
				cumulative_recruited += int(recruit["seed_count"])
				cumulative_bank_reactivated += int(recruit["seed_count"])
			var next_bank := Dictionary(outcome.get("seed_bank_cohort", {}))
			if not next_bank.is_empty():
				next_banks.append(next_bank)
		banks = next_banks

		var total_before := _total_biomass(adults)
		var updated_adults: Array = []
		for adult_value in adults:
			var adult: Dictionary = adult_value
			var lineage := String(adult["lineage_id"])
			var strategy: Dictionary = by_lineage[lineage]
			var genome: Dictionary = strategy["genome"]
			var resource := ResourceModel.evaluate(environment, genome, total_before)
			if resource.is_empty():
				return {}
			var biomass_before := float(adult["biomass_kg_m2"])
			var age_after := float(adult["age_years"]) + 1.0
			var net := float(resource["net_resource_balance"])
			var negative_net := maxf(-net, 0.0)
			var baseline_survival := exp(-1.0 / maxf(float(genome["lifespan_years"]), EPSILON))
			var stress_survival := exp(-STRESS_MORTALITY_RATE * negative_net)
			var survived := biomass_before * baseline_survival * stress_survival
			var mortality := maxf(biomass_before - survived, 0.0)
			var growth := maxf(net, 0.0) * float(genome["growth_rate"]) * survived * VEGETATIVE_GROWTH_RATE
			var biomass_after := survived + growth
			cumulative_mortality += mortality
			if biomass_after > EXTINCTION_BIOMASS_KG_M2:
				var next_adult := adult.duplicate(true)
				next_adult["age_years"] = age_after
				next_adult["biomass_kg_m2"] = biomass_after
				next_adult["last_resource_balance"] = net
				next_adult["cohort_hash"] = _adult_hash(next_adult)
				updated_adults.append(next_adult)
		adults = updated_adults

		var reproduction_recruits: Array = []
		if reproduction_enabled:
			var lineage_aggregates := _lineage_aggregates(adults, by_lineage)
			for lineage in _sorted_keys(lineage_aggregates):
				var aggregate: Dictionary = lineage_aggregates[lineage]
				var strategy: Dictionary = by_lineage[lineage]
				var genome: Dictionary = strategy["genome"]
				var resource := ResourceModel.evaluate(environment, genome, _total_biomass(adults))
				if resource.is_empty():
					return {}
				var maturity_time := float(genome["height_m"]) / maxf(float(genome["growth_rate"]), EPSILON)
				var maturity_fraction := clampf(float(aggregate["mean_age_years"]) / maxf(maturity_time, EPSILON), 0.0, 1.0)
				var current_height := maxf(float(genome["height_m"]) * maturity_fraction, 0.05)
				var reserve_resource := maxf(float(resource["net_resource_balance"]), 0.0) * float(aggregate["biomass_kg_m2"])
				var state := Lifecycle.create_state(current_height, float(aggregate["biomass_kg_m2"]), reserve_resource, float(aggregate["mean_age_years"]))
				var lifecycle := Lifecycle.evaluate(genome, environment, state, Lifecycle.create_disturbance(0.0))
				if lifecycle.is_empty():
					return {}
				var cohort_scale := clampf(float(aggregate["biomass_kg_m2"]) / maxf(PatchBaseline.DEFAULT_INITIAL_BIOMASS_KG_M2, EPSILON), 0.0, 1.0)
				var expected_seeds := float(lifecycle["realized_seed_output_per_year"]) * cohort_scale
				var emitted := _deterministic_count(int(genome["seed_count"]), expected_seeds / maxf(float(genome["seed_count"]), 1.0), "p2-3|%s|%d|emit" % [lineage, year])
				if emitted <= 0:
					continue
				var event := _disperse_and_settle(strategy, environment, context, "p2-3/year/%d/%s" % [year, lineage], emitted, current_height, Vector2(aggregate["mean_position"]))
				if event.is_empty():
					return {}
				reproduction_events += 1
				cumulative_emitted += emitted
				cumulative_exported += int(event["exported_seed_count"])
				cumulative_recruited += int(event["recruited_seed_count"])
				reproduction_recruits.append_array(Array(event["recruits"]))
				banks.append_array(Array(event["banks"]))

		var all_new_recruits: Array = []
		all_new_recruits.append_array(reactivated_recruits)
		all_new_recruits.append_array(reproduction_recruits)
		adults.append_array(_adults_from_recruits(all_new_recruits, by_lineage))
		adults = _merge_adults(adults)
		_apply_capacity(adults)

		var summary := _summary(year, adults, banks, by_lineage, cumulative_recruited, cumulative_bank_reactivated, cumulative_exported, cumulative_emitted, cumulative_mortality, reproduction_events)
		if summary.is_empty():
			return {}
		history.append(summary)
		max_total_biomass = maxf(max_total_biomass, float(summary["total_biomass_kg_m2"]))
		max_adult_cohorts = maxi(max_adult_cohorts, int(summary["adult_cohort_count"]))
		max_bank_cohorts = maxi(max_bank_cohorts, int(summary["seed_bank_cohort_count"]))

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"years": years,
		"reproduction_enabled": reproduction_enabled,
		"strategy_count": strategies.size(),
		"history": history,
		"final_summary": history[history.size() - 1],
		"max_total_biomass_kg_m2": max_total_biomass,
		"max_adult_cohort_count": max_adult_cohorts,
		"max_seed_bank_cohort_count": max_bank_cohorts,
		"cumulative_recruited_seed_count": cumulative_recruited,
		"cumulative_bank_reactivated_seed_count": cumulative_bank_reactivated,
		"cumulative_exported_seed_count": cumulative_exported,
		"cumulative_emitted_seed_count": cumulative_emitted,
		"cumulative_adult_mortality_kg_m2": cumulative_mortality,
		"reproduction_event_count": reproduction_events,
	}
	result["result_hash"] = _result_hash(result)
	return result

static func _disperse_and_settle(strategy: Dictionary, environment: Dictionary, context: Dictionary, event_id: String, emitted: int, release_height: float, source_position: Vector2) -> Dictionary:
	var dispersed := Dispersal.disperse(strategy["genome"], String(strategy["lineage_id"]), event_id, source_position, emitted, release_height, context)
	if dispersed.is_empty():
		return {}
	var recruits: Array = []
	var banks: Array = []
	var exported := 0
	var recruited := 0
	for packet_value in Array(dispersed["packets"]):
		var outcome := Establishment.settle_packet(packet_value, strategy["genome"], strategy["recruitment_traits"], environment, 0.0)
		if outcome.is_empty() or not bool(outcome.get("conservation_ok", false)):
			return {}
		exported += int(outcome["exported_seed_count"])
		recruited += int(outcome["recruited_seed_count"])
		var recruit := Dictionary(outcome.get("recruitment_cohort", {}))
		if not recruit.is_empty():
			recruits.append(recruit)
		var bank := Dictionary(outcome.get("seed_bank_cohort", {}))
		if not bank.is_empty():
			banks.append(bank)
	return {"recruits": recruits, "banks": banks, "exported_seed_count": exported, "recruited_seed_count": recruited, "dispersal_hash": String(dispersed["result_hash"])}

static func _adults_from_recruits(recruits: Array, by_lineage: Dictionary) -> Array:
	var grouped := {}
	for recruit_value in recruits:
		var recruit: Dictionary = recruit_value
		var lineage := String(recruit.get("lineage_id", ""))
		if not by_lineage.has(lineage):
			continue
		if not grouped.has(lineage):
			grouped[lineage] = {"count": 0, "weighted_position": Vector2.ZERO, "source_tokens": PackedStringArray()}
		var entry: Dictionary = grouped[lineage]
		var count := int(recruit.get("seed_count", 0))
		entry["count"] = int(entry["count"]) + count
		entry["weighted_position"] = Vector2(entry["weighted_position"]) + Vector2(recruit["position"]) * float(count)
		var tokens: PackedStringArray = entry["source_tokens"]
		tokens.append(String(recruit["cohort_hash"]))
		entry["source_tokens"] = tokens
		grouped[lineage] = entry
	var adults: Array = []
	for lineage in _sorted_keys(grouped):
		var entry: Dictionary = grouped[lineage]
		var count := int(entry["count"])
		if count <= 0:
			continue
		var strategy: Dictionary = by_lineage[lineage]
		var genome: Dictionary = strategy["genome"]
		var biomass := PatchBaseline.DEFAULT_INITIAL_BIOMASS_KG_M2 * float(count) / maxf(float(genome["seed_count"]), 1.0)
		var position := Vector2(entry["weighted_position"]) / float(count)
		var source_tokens: PackedStringArray = entry["source_tokens"]
		source_tokens.sort()
		var adult := {
			"lineage_id": lineage,
			"genome_checksum": String(genome["checksum"]),
			"recruitment_traits_checksum": String(strategy["recruitment_traits"]["checksum"]),
			"age_years": 0.0,
			"biomass_kg_m2": biomass,
			"origin_recruit_count": count,
			"position": position,
			"source_hash": "\n".join(source_tokens).sha256_text(),
			"last_resource_balance": 0.0,
		}
		adult["cohort_hash"] = _adult_hash(adult)
		adults.append(adult)
	return adults

static func _merge_adults(adults: Array) -> Array:
	var grouped := {}
	for adult_value in adults:
		var adult: Dictionary = adult_value
		var key := "%s|%.6f" % [String(adult["lineage_id"]), float(adult["age_years"])]
		if not grouped.has(key):
			grouped[key] = adult.duplicate(true)
			continue
		var current: Dictionary = grouped[key]
		var b0 := float(current["biomass_kg_m2"])
		var b1 := float(adult["biomass_kg_m2"])
		var total := b0 + b1
		if total > EPSILON:
			current["position"] = (Vector2(current["position"]) * b0 + Vector2(adult["position"]) * b1) / total
		current["biomass_kg_m2"] = total
		current["origin_recruit_count"] = int(current["origin_recruit_count"]) + int(adult["origin_recruit_count"])
		current["source_hash"] = "%s|%s" % [String(current["source_hash"]), String(adult["source_hash"])]
		current["cohort_hash"] = _adult_hash(current)
		grouped[key] = current
	var result: Array = []
	var keys: Array = grouped.keys()
	keys.sort()
	for key in keys:
		result.append(grouped[key])
	return result

static func _lineage_aggregates(adults: Array, by_lineage: Dictionary) -> Dictionary:
	var result := {}
	for lineage in by_lineage.keys():
		result[lineage] = {"biomass_kg_m2": 0.0, "weighted_age": 0.0, "weighted_position": Vector2.ZERO}
	for adult_value in adults:
		var adult: Dictionary = adult_value
		var lineage := String(adult["lineage_id"])
		var entry: Dictionary = result[lineage]
		var biomass := float(adult["biomass_kg_m2"])
		entry["biomass_kg_m2"] = float(entry["biomass_kg_m2"]) + biomass
		entry["weighted_age"] = float(entry["weighted_age"]) + float(adult["age_years"]) * biomass
		entry["weighted_position"] = Vector2(entry["weighted_position"]) + Vector2(adult["position"]) * biomass
		result[lineage] = entry
	for lineage in result.keys():
		var entry: Dictionary = result[lineage]
		var biomass := float(entry["biomass_kg_m2"])
		if biomass <= EPSILON:
			result.erase(lineage)
			continue
		entry["mean_age_years"] = float(entry["weighted_age"]) / biomass
		entry["mean_position"] = Vector2(entry["weighted_position"]) / biomass
		result[lineage] = entry
	return result

static func _summary(year: int, adults: Array, banks: Array, by_lineage: Dictionary, cumulative_recruited: int, cumulative_reactivated: int, cumulative_exported: int, cumulative_emitted: int, cumulative_mortality: float, reproduction_events: int) -> Dictionary:
	var total := _total_biomass(adults)
	var lineage_biomass := {}
	for lineage in by_lineage.keys():
		lineage_biomass[lineage] = 0.0
	for adult_value in adults:
		var adult: Dictionary = adult_value
		var lineage := String(adult["lineage_id"])
		lineage_biomass[lineage] = float(lineage_biomass.get(lineage, 0.0)) + float(adult["biomass_kg_m2"])
	var shares := {}
	var top_lineage := ""
	var top_share := -1.0
	for lineage in _sorted_keys(lineage_biomass):
		var share := 0.0 if total <= EPSILON else float(lineage_biomass[lineage]) / total
		shares[lineage] = share
		if share > top_share + EPSILON:
			top_share = share
			top_lineage = lineage
	var bank_seed_count := 0
	for bank_value in banks:
		bank_seed_count += int(Dictionary(bank_value).get("seed_count", 0))
	var summary := {
		"year": year,
		"total_biomass_kg_m2": total,
		"capacity_fraction": total / PatchBaseline.MAX_BIOMASS_KG_M2,
		"adult_cohort_count": adults.size(),
		"seed_bank_cohort_count": banks.size(),
		"seed_bank_seed_count": bank_seed_count,
		"lineage_biomass_kg_m2": lineage_biomass,
		"lineage_biomass_share": shares,
		"top_lineage": top_lineage,
		"top_share": maxf(top_share, 0.0),
		"cumulative_recruited_seed_count": cumulative_recruited,
		"cumulative_bank_reactivated_seed_count": cumulative_reactivated,
		"cumulative_exported_seed_count": cumulative_exported,
		"cumulative_emitted_seed_count": cumulative_emitted,
		"cumulative_adult_mortality_kg_m2": cumulative_mortality,
		"reproduction_event_count": reproduction_events,
	}
	summary["summary_hash"] = _summary_hash(summary)
	return summary

static func _apply_capacity(adults: Array) -> void:
	var total := _total_biomass(adults)
	if total <= PatchBaseline.MAX_BIOMASS_KG_M2 or total <= EPSILON:
		return
	var scale := PatchBaseline.MAX_BIOMASS_KG_M2 / total
	for adult_value in adults:
		var adult: Dictionary = adult_value
		adult["biomass_kg_m2"] = float(adult["biomass_kg_m2"]) * scale
		adult["cohort_hash"] = _adult_hash(adult)

static func _environment_for_year(schedule: Array, year: int) -> Dictionary:
	var selected: Dictionary = {}
	var best_start := -1
	for entry_value in schedule:
		var entry: Dictionary = entry_value
		var start := int(entry["year_start"])
		if start <= year and start >= best_start:
			selected = Dictionary(entry["environment"])
			best_start = start
	return selected

static func _valid_strategy(strategy: Dictionary) -> bool:
	var lineage := String(strategy.get("lineage_id", ""))
	if lineage.is_empty() or lineage != lineage.strip_edges():
		return false
	if not bool(PlantGenome.validate(Dictionary(strategy.get("genome", {}))).get("success", false)):
		return false
	if not RecruitmentTraits.validate(Dictionary(strategy.get("recruitment_traits", {}))):
		return false
	var position := Vector2(strategy.get("source_position", Vector2(INF, INF)))
	return is_finite(position.x) and is_finite(position.y) and LOCAL_DOMAIN.has_point(position)

static func _total_biomass(adults: Array) -> float:
	var total := 0.0
	for adult_value in adults:
		total += float(Dictionary(adult_value).get("biomass_kg_m2", 0.0))
	return total

static func _deterministic_count(count: int, fraction: float, key: String) -> int:
	if count <= 0:
		return 0
	var bounded := clampf(fraction, 0.0, 1.0)
	var expected := float(count) * bounded
	var lower := int(floor(expected))
	var remainder := expected - float(lower)
	var unit := float(key.sha256_text().substr(0, 12).hex_to_int()) / 281474976710655.0
	if remainder > EPSILON and unit < remainder:
		lower += 1
	return clampi(lower, 0, count)

static func _adult_hash(adult: Dictionary) -> String:
	return "|".join(PackedStringArray([
		String(adult.get("lineage_id", "")), String(adult.get("genome_checksum", "")), String(adult.get("recruitment_traits_checksum", "")),
		"%.12f" % float(adult.get("age_years", 0.0)), "%.12f" % float(adult.get("biomass_kg_m2", 0.0)), str(int(adult.get("origin_recruit_count", 0))),
		"%.12f,%.12f" % [Vector2(adult.get("position", Vector2.ZERO)).x, Vector2(adult.get("position", Vector2.ZERO)).y], String(adult.get("source_hash", "")),
		"%.12f" % float(adult.get("last_resource_balance", 0.0))
	])).sha256_text()

static func _summary_hash(summary: Dictionary) -> String:
	var tokens := PackedStringArray([SCHEMA, VERSION, str(int(summary["year"])), "%.12f" % float(summary["total_biomass_kg_m2"]), str(int(summary["adult_cohort_count"])), str(int(summary["seed_bank_cohort_count"])), str(int(summary["seed_bank_seed_count"])), String(summary["top_lineage"]), "%.12f" % float(summary["top_share"])])
	var shares: Dictionary = summary["lineage_biomass_share"]
	for lineage in _sorted_keys(shares):
		tokens.append("%s|%.12f" % [lineage, float(shares[lineage])])
	for field_name in ["cumulative_recruited_seed_count", "cumulative_bank_reactivated_seed_count", "cumulative_exported_seed_count", "cumulative_emitted_seed_count", "reproduction_event_count"]:
		tokens.append(str(int(summary[field_name])))
	tokens.append("%.12f" % float(summary["cumulative_adult_mortality_kg_m2"]))
	return "\n".join(tokens).sha256_text()

static func _result_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([SCHEMA, VERSION, str(int(result["years"])), str(bool(result["reproduction_enabled"])), str(int(result["strategy_count"]))])
	for summary_value in Array(result["history"]):
		tokens.append(String(Dictionary(summary_value)["summary_hash"]))
	for field_name in ["cumulative_recruited_seed_count", "cumulative_bank_reactivated_seed_count", "cumulative_exported_seed_count", "cumulative_emitted_seed_count", "reproduction_event_count", "max_adult_cohort_count", "max_seed_bank_cohort_count"]:
		tokens.append(str(int(result[field_name])))
	tokens.append("%.12f" % float(result["cumulative_adult_mortality_kg_m2"]))
	tokens.append("%.12f" % float(result["max_total_biomass_kg_m2"]))
	return "\n".join(tokens).sha256_text()

static func _sorted_keys(dictionary: Dictionary) -> Array:
	var keys: Array = dictionary.keys()
	keys.sort()
	return keys
