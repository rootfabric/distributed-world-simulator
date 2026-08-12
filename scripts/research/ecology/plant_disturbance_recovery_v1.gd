extends RefCounted

const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const ResourceModel = preload("res://scripts/research/ecology/plant_resource_model_v1.gd")
const Lifecycle = preload("res://scripts/research/ecology/plant_lifecycle_payoff_v1.gd")
const Establishment = preload("res://scripts/research/ecology/plant_establishment_seed_bank_v1.gd")
const RecruitmentTraits = preload("res://scripts/research/ecology/plant_recruitment_traits_v1.gd")
const PopulationTurnover = preload("res://scripts/research/ecology/plant_local_population_succession_v1.gd")
const PatchBaseline = preload("res://scripts/research/ecology/single_plant_patch_simulator_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo1_p2_5_disturbance_recovery.v1"
const EVENT_SCHEMA := SCHEMA + ".event"
const ADULT_SCHEMA := SCHEMA + ".adult_cohort"
const VERSION := "1.0.0"
const EPSILON := 0.000000000001

static func create_event(event_id: String, year: int, mechanical_severity: float, seed_bank_mortality_fraction: float) -> Dictionary:
	if event_id.is_empty() or event_id != event_id.strip_edges():
		return {}
	if year <= 0 or year > 1000:
		return {}
	if not is_finite(mechanical_severity) or mechanical_severity < 0.0 or mechanical_severity > 1.0:
		return {}
	if not is_finite(seed_bank_mortality_fraction) or seed_bank_mortality_fraction < 0.0 or seed_bank_mortality_fraction > 1.0:
		return {}
	var result := {
		"schema": EVENT_SCHEMA,
		"version": VERSION,
		"event_id": event_id,
		"year": year,
		"mechanical_severity": mechanical_severity,
		"seed_bank_mortality_fraction": seed_bank_mortality_fraction,
	}
	result["checksum"] = _event_hash(result)
	return result

static func create_adult(lineage_id: String, genome: Dictionary, age_years: float, biomass_kg_m2: float, current_height_m: float, source_hash: String) -> Dictionary:
	if lineage_id.is_empty() or source_hash.is_empty():
		return {}
	if not bool(PlantGenome.validate(genome).get("success", false)):
		return {}
	if not is_finite(age_years) or not is_finite(biomass_kg_m2) or not is_finite(current_height_m):
		return {}
	if age_years < 0.0 or biomass_kg_m2 <= 0.0 or current_height_m <= 0.0:
		return {}
	var adult := {
		"schema": ADULT_SCHEMA,
		"version": VERSION,
		"lineage_id": lineage_id,
		"genome_checksum": String(genome["checksum"]),
		"age_years": age_years,
		"biomass_kg_m2": biomass_kg_m2,
		"current_height_m": current_height_m,
		"source_hash": source_hash,
	}
	adult["cohort_hash"] = _adult_hash(adult)
	return adult

static func create_seed_bank(lineage_id: String, genome: Dictionary, recruitment_traits: Dictionary, environment: Dictionary, seed_count: int, age_years: float, source_hash: String) -> Dictionary:
	if lineage_id.is_empty() or source_hash.is_empty() or seed_count <= 0:
		return {}
	if not bool(PlantGenome.validate(genome).get("success", false)):
		return {}
	if not RecruitmentTraits.validate(recruitment_traits):
		return {}
	if not bool(EnvironmentSample.validate(environment).get("success", false)):
		return {}
	if not is_finite(age_years) or age_years < 0.0:
		return {}
	var identity := {
		"lineage_id": lineage_id,
		"genome_checksum": String(genome["checksum"]),
		"reproduction_event": "p2-5/seed-bank/founder/" + lineage_id,
		"position": Vector2.ZERO,
		"source_hash": source_hash,
	}
	return Establishment._make_seed_bank_cohort(identity, recruitment_traits, environment, seed_count, age_years)

static func simulate(initial_state: Dictionary, strategies: Dictionary, environment: Dictionary, years: int, events: Array) -> Dictionary:
	if years <= 0 or years > 200:
		return {}
	if not bool(EnvironmentSample.validate(environment).get("success", false)):
		return {}
	if not _valid_strategies(strategies):
		return {}
	var state := _copy_state(initial_state)
	if not _valid_state(state, strategies):
		return {}
	var event_by_year := {}
	for event_value in events:
		var event: Dictionary = event_value
		if not _valid_event(event):
			return {}
		var year := int(event["year"])
		if year > years or event_by_year.has(year):
			return {}
		event_by_year[year] = event

	var history: Array = [_summary(0, state)]
	var event_log: Array = []
	var cumulative_reactivated := 0
	var cumulative_event_destroyed_biomass := 0.0
	var cumulative_event_killed_bank := 0
	for year in range(1, years + 1):
		if event_by_year.has(year):
			var event_result := apply_event(state, strategies, environment, event_by_year[year])
			if event_result.is_empty():
				return {}
			state = event_result["state"]
			event_log.append(event_result["event_record"])
			cumulative_event_destroyed_biomass += float(event_result["event_record"]["destroyed_adult_biomass_kg_m2"])
			cumulative_event_killed_bank += int(event_result["event_record"]["killed_seed_bank_count"])
		var annual := advance_year(state, strategies, environment, year)
		if annual.is_empty():
			return {}
		state = annual["state"]
		cumulative_reactivated += int(annual["reactivated_seed_count"])
		history.append(_summary(year, state))

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"years": years,
		"event_count": event_log.size(),
		"history": history,
		"event_log": event_log,
		"final_state": state,
		"final_summary": history[history.size() - 1],
		"cumulative_reactivated_seed_count": cumulative_reactivated,
		"cumulative_event_destroyed_biomass_kg_m2": cumulative_event_destroyed_biomass,
		"cumulative_event_killed_seed_bank_count": cumulative_event_killed_bank,
	}
	result["result_hash"] = _result_hash(result)
	return result

static func apply_event(state: Dictionary, strategies: Dictionary, environment: Dictionary, event: Dictionary) -> Dictionary:
	if not _valid_event(event) or not _valid_state(state, strategies):
		return {}
	var before_biomass := _total_biomass(Array(state["adults"]))
	var before_bank := _total_bank(Array(state["banks"]))
	var next_adults: Array = []
	var lineage_survival := {}
	var destroyed_biomass := 0.0
	for adult_value in Array(state["adults"]):
		var adult: Dictionary = adult_value
		var lineage := String(adult["lineage_id"])
		var strategy: Dictionary = strategies[lineage]
		var genome: Dictionary = strategy["genome"]
		var resource := ResourceModel.evaluate(environment, genome, before_biomass)
		if resource.is_empty():
			return {}
		var reserve := maxf(float(resource["net_resource_balance"]), 0.0) * float(adult["biomass_kg_m2"])
		var lifecycle_state := Lifecycle.create_state(float(adult["current_height_m"]), float(adult["biomass_kg_m2"]), reserve, float(adult["age_years"]))
		var disturbance := Lifecycle.create_disturbance(float(event["mechanical_severity"]))
		var evaluation := Lifecycle.evaluate(genome, environment, lifecycle_state, disturbance)
		if evaluation.is_empty():
			return {}
		var survival := float(evaluation["disturbance_survival_fraction"])
		lineage_survival[lineage] = survival
		var before := float(adult["biomass_kg_m2"])
		var after := before * survival
		destroyed_biomass += before - after
		if after > EPSILON:
			var next_adult := adult.duplicate(true)
			next_adult["biomass_kg_m2"] = after
			next_adult["source_hash"] = (String(adult["cohort_hash"]) + "|" + String(event["checksum"])).sha256_text()
			next_adult["cohort_hash"] = _adult_hash(next_adult)
			next_adults.append(next_adult)

	var next_banks: Array = []
	var killed_bank := 0
	for bank_value in Array(state["banks"]):
		var bank: Dictionary = bank_value
		var lineage := String(bank["lineage_id"])
		var strategy: Dictionary = strategies[lineage]
		var before_count := int(bank["seed_count"])
		var survival_fraction := 1.0 - float(event["seed_bank_mortality_fraction"])
		var surviving_count := _deterministic_count(before_count, survival_fraction, String(bank["cohort_hash"]) + "|" + String(event["checksum"]) + "|bank")
		killed_bank += before_count - surviving_count
		if surviving_count > 0:
			var identity := {
				"lineage_id": lineage,
				"genome_checksum": String(bank["genome_checksum"]),
				"reproduction_event": String(bank["reproduction_event"]),
				"position": Vector2(bank["position"]),
				"source_hash": (String(bank["cohort_hash"]) + "|" + String(event["checksum"])).sha256_text(),
			}
			var rebuilt := Establishment._make_seed_bank_cohort(identity, strategy["recruitment_traits"], environment, surviving_count, float(bank["age_years"]))
			if rebuilt.is_empty():
				return {}
			next_banks.append(rebuilt)

	var after_biomass := _total_biomass(next_adults)
	var after_bank := _total_bank(next_banks)
	var event_record := {
		"event_id": String(event["event_id"]),
		"year": int(event["year"]),
		"event_checksum": String(event["checksum"]),
		"mechanical_severity": float(event["mechanical_severity"]),
		"seed_bank_mortality_fraction": float(event["seed_bank_mortality_fraction"]),
		"adult_biomass_before_kg_m2": before_biomass,
		"adult_biomass_after_kg_m2": after_biomass,
		"destroyed_adult_biomass_kg_m2": destroyed_biomass,
		"seed_bank_before_count": before_bank,
		"seed_bank_after_count": after_bank,
		"killed_seed_bank_count": killed_bank,
		"lineage_survival_fraction": lineage_survival,
		"adult_conservation_ok": absf(before_biomass - after_biomass - destroyed_biomass) <= 0.000000001,
		"seed_bank_conservation_ok": before_bank == after_bank + killed_bank,
	}
	event_record["record_hash"] = _event_record_hash(event_record)
	return {"state": {"adults": next_adults, "banks": next_banks}, "event_record": event_record}

static func advance_year(state: Dictionary, strategies: Dictionary, environment: Dictionary, year: int) -> Dictionary:
	if not _valid_state(state, strategies) or year <= 0:
		return {}
	var adults: Array = Array(state["adults"]).duplicate(true)
	var banks: Array = []
	var new_adults: Array = []
	var reactivated := 0
	for bank_value in Array(state["banks"]):
		var bank: Dictionary = bank_value
		var lineage := String(bank["lineage_id"])
		var strategy: Dictionary = strategies[lineage]
		var outcome := Establishment.advance_seed_bank(bank, strategy["genome"], strategy["recruitment_traits"], environment, 1.0)
		if outcome.is_empty() or not bool(outcome.get("conservation_ok", false)):
			return {}
		var recruit := Dictionary(outcome.get("recruitment_cohort", {}))
		if not recruit.is_empty():
			var count := int(recruit["seed_count"])
			reactivated += count
			var genome: Dictionary = strategy["genome"]
			var biomass := PatchBaseline.DEFAULT_INITIAL_BIOMASS_KG_M2 * float(count) / maxf(float(genome["seed_count"]), 1.0)
			var adult := create_adult(lineage, genome, 0.0, maxf(biomass, EPSILON * 10.0), maxf(float(genome["height_m"]) * 0.10, 0.05), String(recruit["cohort_hash"]))
			if adult.is_empty():
				return {}
			new_adults.append(adult)
		var next_bank := Dictionary(outcome.get("seed_bank_cohort", {}))
		if not next_bank.is_empty():
			banks.append(next_bank)

	var total_before := _total_biomass(adults)
	var survivors: Array = []
	for adult_value in adults:
		var adult: Dictionary = adult_value
		var lineage := String(adult["lineage_id"])
		var strategy: Dictionary = strategies[lineage]
		var genome: Dictionary = strategy["genome"]
		var resource := ResourceModel.evaluate(environment, genome, total_before)
		if resource.is_empty():
			return {}
		var net := float(resource["net_resource_balance"])
		var baseline_survival := exp(-1.0 / maxf(float(genome["lifespan_years"]), EPSILON))
		var stress_survival := exp(-PopulationTurnover.STRESS_MORTALITY_RATE * maxf(-net, 0.0))
		var survived := float(adult["biomass_kg_m2"]) * baseline_survival * stress_survival
		var growth := maxf(net, 0.0) * float(genome["growth_rate"]) * survived * PopulationTurnover.VEGETATIVE_GROWTH_RATE
		var after := survived + growth
		if after > EPSILON:
			var next_adult := adult.duplicate(true)
			next_adult["age_years"] = float(adult["age_years"]) + 1.0
			next_adult["biomass_kg_m2"] = after
			var target_height := float(genome["height_m"])
			var height_gap := maxf(target_height - float(adult["current_height_m"]), 0.0)
			next_adult["current_height_m"] = minf(target_height, float(adult["current_height_m"]) + height_gap * float(genome["growth_rate"]))
			next_adult["source_hash"] = (String(adult["cohort_hash"]) + "|year|" + str(year)).sha256_text()
			next_adult["cohort_hash"] = _adult_hash(next_adult)
			survivors.append(next_adult)
	survivors.append_array(new_adults)
	var merged := _merge_adults(survivors, strategies)
	_apply_capacity(merged)
	return {"state": {"adults": merged, "banks": banks}, "reactivated_seed_count": reactivated}

static func _merge_adults(adults: Array, strategies: Dictionary) -> Array:
	var grouped := {}
	for adult_value in adults:
		var adult: Dictionary = adult_value
		var lineage := String(adult["lineage_id"])
		if not grouped.has(lineage):
			grouped[lineage] = {"biomass": 0.0, "age_weight": 0.0, "height_weight": 0.0, "tokens": PackedStringArray()}
		var entry: Dictionary = grouped[lineage]
		var biomass := float(adult["biomass_kg_m2"])
		entry["biomass"] = float(entry["biomass"]) + biomass
		entry["age_weight"] = float(entry["age_weight"]) + float(adult["age_years"]) * biomass
		entry["height_weight"] = float(entry["height_weight"]) + float(adult["current_height_m"]) * biomass
		var tokens: PackedStringArray = entry["tokens"]
		tokens.append(String(adult["cohort_hash"]))
		entry["tokens"] = tokens
		grouped[lineage] = entry
	var result: Array = []
	var keys := grouped.keys()
	keys.sort()
	for lineage_value in keys:
		var lineage := String(lineage_value)
		var entry: Dictionary = grouped[lineage]
		var biomass := float(entry["biomass"])
		if biomass <= EPSILON:
			continue
		var genome: Dictionary = Dictionary(strategies[lineage])["genome"]
		var tokens: PackedStringArray = entry["tokens"]
		tokens.sort()
		var adult := create_adult(lineage, genome, float(entry["age_weight"]) / biomass, biomass, float(entry["height_weight"]) / biomass, "|".join(tokens).sha256_text())
		if not adult.is_empty():
			result.append(adult)
	return result

static func _apply_capacity(adults: Array) -> void:
	var total := _total_biomass(adults)
	if total <= PatchBaseline.MAX_BIOMASS_KG_M2 + EPSILON:
		return
	var scale := PatchBaseline.MAX_BIOMASS_KG_M2 / total
	for index in range(adults.size()):
		var adult: Dictionary = adults[index]
		adult["biomass_kg_m2"] = float(adult["biomass_kg_m2"]) * scale
		adult["cohort_hash"] = _adult_hash(adult)
		adults[index] = adult

static func _summary(year: int, state: Dictionary) -> Dictionary:
	var adults: Array = state["adults"]
	var banks: Array = state["banks"]
	var total_biomass := _total_biomass(adults)
	var lineage_biomass := {}
	for adult_value in adults:
		var adult: Dictionary = adult_value
		var lineage := String(adult["lineage_id"])
		lineage_biomass[lineage] = float(lineage_biomass.get(lineage, 0.0)) + float(adult["biomass_kg_m2"])
	var shares := {}
	var keys := lineage_biomass.keys()
	keys.sort()
	for lineage_value in keys:
		var lineage := String(lineage_value)
		shares[lineage] = 0.0 if total_biomass <= EPSILON else float(lineage_biomass[lineage]) / total_biomass
	var result := {
		"year": year,
		"total_biomass_kg_m2": total_biomass,
		"seed_bank_count": _total_bank(banks),
		"adult_cohort_count": adults.size(),
		"seed_bank_cohort_count": banks.size(),
		"lineage_biomass_share": shares,
		"capacity_fraction": total_biomass / PatchBaseline.MAX_BIOMASS_KG_M2,
	}
	result["summary_hash"] = _summary_hash(result)
	return result

static func _valid_event(event: Dictionary) -> bool:
	return String(event.get("schema", "")) == EVENT_SCHEMA and String(event.get("version", "")) == VERSION and String(event.get("checksum", "")) == _event_hash(event)

static func _valid_strategies(strategies: Dictionary) -> bool:
	if strategies.is_empty():
		return false
	for lineage_value in strategies.keys():
		var lineage := String(lineage_value)
		var strategy: Dictionary = strategies[lineage]
		if lineage.is_empty() or not bool(PlantGenome.validate(Dictionary(strategy.get("genome", {}))).get("success", false)):
			return false
		if not RecruitmentTraits.validate(Dictionary(strategy.get("recruitment_traits", {}))):
			return false
	return true

static func _valid_state(state: Dictionary, strategies: Dictionary) -> bool:
	if not state.has("adults") or not state.has("banks"):
		return false
	for adult_value in Array(state["adults"]):
		var adult: Dictionary = adult_value
		var lineage := String(adult.get("lineage_id", ""))
		if not strategies.has(lineage) or String(adult.get("schema", "")) != ADULT_SCHEMA or String(adult.get("cohort_hash", "")) != _adult_hash(adult):
			return false
		if String(adult.get("genome_checksum", "")) != String(Dictionary(strategies[lineage])["genome"]["checksum"]):
			return false
	for bank_value in Array(state["banks"]):
		var bank: Dictionary = bank_value
		var lineage := String(bank.get("lineage_id", ""))
		if not strategies.has(lineage):
			return false
		var strategy: Dictionary = strategies[lineage]
		var probe := Establishment.advance_seed_bank(bank, strategy["genome"], strategy["recruitment_traits"], EnvironmentSample.create(0.0, 0.0, 17.0, 0.58, 0.85, 0.80, 0.04, 2505, "eco-evo1-p2-5-validation-probe"), 0.000001)
		if probe.is_empty():
			return false
	return true

static func _copy_state(state: Dictionary) -> Dictionary:
	return {"adults": Array(state.get("adults", [])).duplicate(true), "banks": Array(state.get("banks", [])).duplicate(true)}

static func _total_biomass(adults: Array) -> float:
	var total := 0.0
	for adult_value in adults:
		total += float(Dictionary(adult_value).get("biomass_kg_m2", 0.0))
	return total

static func _total_bank(banks: Array) -> int:
	var total := 0
	for bank_value in banks:
		total += int(Dictionary(bank_value).get("seed_count", 0))
	return total

static func _deterministic_count(total: int, fraction: float, key: String) -> int:
	var bounded := clampf(fraction, 0.0, 1.0)
	var expected := float(total) * bounded
	var base := int(floor(expected))
	var remainder := expected - float(base)
	if base < total and _unit_interval(key) < remainder:
		base += 1
	return mini(total, maxi(0, base))

static func _unit_interval(key: String) -> float:
	var value := key.sha256_text().substr(0, 12).hex_to_int()
	return float(value) / 281474976710655.0

static func _adult_hash(adult: Dictionary) -> String:
	return "|".join(PackedStringArray([ADULT_SCHEMA, VERSION, String(adult.get("lineage_id", "")), String(adult.get("genome_checksum", "")), "%.12f" % float(adult.get("age_years", 0.0)), "%.12f" % float(adult.get("biomass_kg_m2", 0.0)), "%.12f" % float(adult.get("current_height_m", 0.0)), String(adult.get("source_hash", ""))])).sha256_text()

static func _event_hash(event: Dictionary) -> String:
	return "|".join(PackedStringArray([EVENT_SCHEMA, VERSION, String(event.get("event_id", "")), str(int(event.get("year", 0))), "%.12f" % float(event.get("mechanical_severity", 0.0)), "%.12f" % float(event.get("seed_bank_mortality_fraction", 0.0))])).sha256_text()

static func _event_record_hash(record: Dictionary) -> String:
	var tokens := PackedStringArray([String(record.get("event_id", "")), str(int(record.get("year", 0))), String(record.get("event_checksum", "")), "%.12f" % float(record.get("adult_biomass_before_kg_m2", 0.0)), "%.12f" % float(record.get("adult_biomass_after_kg_m2", 0.0)), "%.12f" % float(record.get("destroyed_adult_biomass_kg_m2", 0.0)), str(int(record.get("seed_bank_before_count", 0))), str(int(record.get("seed_bank_after_count", 0))), str(int(record.get("killed_seed_bank_count", 0)))])
	var survival: Dictionary = record.get("lineage_survival_fraction", {})
	var keys := survival.keys()
	keys.sort()
	for lineage_value in keys:
		var lineage := String(lineage_value)
		tokens.append(lineage + "=%.12f" % float(survival[lineage]))
	return "|".join(tokens).sha256_text()

static func _summary_hash(summary: Dictionary) -> String:
	var tokens := PackedStringArray([str(int(summary.get("year", 0))), "%.12f" % float(summary.get("total_biomass_kg_m2", 0.0)), str(int(summary.get("seed_bank_count", 0))), str(int(summary.get("adult_cohort_count", 0))), str(int(summary.get("seed_bank_cohort_count", 0)))])
	var shares: Dictionary = summary.get("lineage_biomass_share", {})
	var keys := shares.keys()
	keys.sort()
	for lineage_value in keys:
		var lineage := String(lineage_value)
		tokens.append(lineage + "=%.12f" % float(shares[lineage]))
	return "|".join(tokens).sha256_text()

static func _result_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([SCHEMA, VERSION, str(int(result.get("years", 0))), str(int(result.get("event_count", 0))), str(int(result.get("cumulative_reactivated_seed_count", 0))), "%.12f" % float(result.get("cumulative_event_destroyed_biomass_kg_m2", 0.0)), str(int(result.get("cumulative_event_killed_seed_bank_count", 0)))])
	for summary_value in Array(result.get("history", [])):
		tokens.append(String(Dictionary(summary_value).get("summary_hash", "")))
	for event_value in Array(result.get("event_log", [])):
		tokens.append(String(Dictionary(event_value).get("record_hash", "")))
	return "\n".join(tokens).sha256_text()
