extends RefCounted

const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const RecruitmentTraits = preload("res://scripts/research/ecology/plant_recruitment_traits_v1.gd")
const ResourceModel = preload("res://scripts/research/ecology/plant_resource_model_v1.gd")
const Lifecycle = preload("res://scripts/research/ecology/plant_lifecycle_payoff_v1.gd")
const PopulationTurnover = preload("res://scripts/research/ecology/plant_local_population_succession_v1.gd")
const PatchMigration = preload("res://scripts/research/ecology/plant_patch_migration_v1.gd")
const DisturbanceRecovery = preload("res://scripts/research/ecology/plant_disturbance_recovery_v1.gd")
const PatchBaseline = preload("res://scripts/research/ecology/single_plant_patch_simulator_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo1_p2_6_long_horizon_biogeography.v1"
const VERSION := "1.0.0"
const EPSILON := 0.000000000001
const MAX_PATCHES := 32
const MAX_YEARS := 200

static func simulate(
	patch_states: Array,
	strategies: Dictionary,
	years: int,
	source_patch_ids: Array,
	transport_schedule: Array,
	disturbance_schedule: Dictionary
) -> Dictionary:
	if patch_states.is_empty() or patch_states.size() > MAX_PATCHES or years <= 0 or years > MAX_YEARS:
		return {}
	if not _valid_strategies(strategies) or transport_schedule.is_empty():
		return {}

	var patches := {}
	var states := {}
	for value in patch_states:
		var entry: Dictionary = value
		var patch: Dictionary = Dictionary(entry.get("patch", {}))
		var state: Dictionary = Dictionary(entry.get("state", {}))
		if not PatchMigration.validate_patch(patch) or not _state_shape_valid(state):
			return {}
		var patch_id := String(patch["patch_id"])
		if patches.has(patch_id):
			return {}
		patches[patch_id] = patch
		states[patch_id] = _copy_state(state)

	var source_ids: Array[String] = []
	for source_value in source_patch_ids:
		var source_id := String(source_value)
		if not patches.has(source_id) or source_id in source_ids:
			return {}
		source_ids.append(source_id)
	source_ids.sort()
	if source_ids.is_empty():
		return {}
	if not _validate_transport_schedule(transport_schedule):
		return {}
	var events_by_patch_year := _index_disturbances(disturbance_schedule, patches, years)
	if events_by_patch_year.is_empty() and not disturbance_schedule.is_empty():
		return {}

	var history: Array = []
	var transition_log: Array = []
	var migration_log: Array = []
	var disturbance_log: Array = []
	var cumulative_emitted := 0
	var cumulative_routed := 0
	var cumulative_unresolved := 0
	var cumulative_recruited := 0
	var cumulative_banked := 0
	var cumulative_reactivated := 0
	var migration_all_conserve := true
	var disturbance_all_conserve := true
	var max_adult_cohorts := 0
	var max_bank_cohorts := 0

	var initial_summary := _regional_summary(0, patches, states, strategies)
	if initial_summary.is_empty():
		return {}
	history.append(initial_summary)
	var previous_occupancy := _adult_occupancy_map(initial_summary, strategies)
	var ever_occupied := previous_occupancy.duplicate(true)
	max_adult_cohorts = int(initial_summary["total_adult_cohorts"])
	max_bank_cohorts = int(initial_summary["total_bank_cohorts"])

	for year in range(1, years + 1):
		var transport := _transport_for_year(transport_schedule, year)
		if transport.is_empty():
			return {}
		var target_patch_array: Array = []
		for patch_id in _sorted_keys(patches):
			target_patch_array.append(patches[patch_id])

		# Regional propagule flow happens first. If a disturbance occurs in the same year,
		# immigrants are exposed to that event too; this prevents a hidden post-event rescue bonus.
		for source_id in source_ids:
			var source_patch: Dictionary = patches[source_id]
			var source_state: Dictionary = states[source_id]
			var aggregates := _lineage_aggregates(Array(source_state["adults"]), strategies)
			if aggregates.is_empty():
				continue
			var targets: Array = []
			for target_value in target_patch_array:
				var target: Dictionary = target_value
				if String(target["patch_id"]) != source_id:
					targets.append(target)
			var environment: Dictionary = source_patch["environment"]
			var total_source_biomass := _total_biomass(Array(source_state["adults"]))
			for lineage in _sorted_keys(aggregates):
				var aggregate: Dictionary = aggregates[lineage]
				var strategy: Dictionary = strategies[lineage]
				var genome: Dictionary = strategy["genome"]
				var emitted := _emitted_seed_count(lineage, year, aggregate, genome, environment, total_source_biomass)
				if emitted <= 0:
					continue
				var bounds := Rect2(source_patch["bounds"])
				var source_position := bounds.position + bounds.size * 0.5
				var migration := PatchMigration.migrate_reproduction_event(
					source_patch,
					targets,
					genome,
					strategy["recruitment_traits"],
					lineage,
					"p2-6/year/%d/%s/%s" % [year, source_id, lineage],
					source_position,
					emitted,
					maxf(float(aggregate["mean_height_m"]), 0.05),
					Vector2(transport["transport_vector"]),
					float(transport["turbulence"])
				)
				if migration.is_empty():
					return {}
				migration_all_conserve = migration_all_conserve and bool(migration.get("migration_conservation_ok", false)) and bool(migration.get("target_conservation_ok", false))
				cumulative_emitted += int(migration["emitted_seed_count"])
				cumulative_routed += int(migration["routed_seed_count"])
				cumulative_unresolved += int(migration["unresolved_export_seed_count"])
				var migration_record := {
					"year": year,
					"source_patch_id": source_id,
					"lineage_id": lineage,
					"emitted": int(migration["emitted_seed_count"]),
					"routed": int(migration["routed_seed_count"]),
					"unresolved": int(migration["unresolved_export_seed_count"]),
					"migration_hash": String(migration["result_hash"]),
				}
				migration_record["record_hash"] = _migration_record_hash(migration_record)
				migration_log.append(migration_record)
				for target_value in targets:
					var target: Dictionary = target_value
					var target_id := String(target["patch_id"])
					var target_summary := PatchMigration.target_summary(migration, target_id)
					if target_summary.is_empty():
						return {}
					var recruited := int(target_summary["recruited_seed_count"])
					var banked := int(target_summary["seed_bank_seed_count"])
					if recruited <= 0 and banked <= 0:
						continue
					var target_state: Dictionary = states[target_id]
					var arrival := _apply_arrival(target_state, target, strategy, lineage, year, recruited, banked, String(migration["result_hash"]))
					if arrival.is_empty():
						return {}
					states[target_id] = arrival["state"]
					cumulative_recruited += recruited
					cumulative_banked += banked

		# Disturbance is patch-local and uses the accepted P2.5 event response directly.
		for patch_id in _sorted_keys(patches):
			var event_key := "%s|%d" % [patch_id, year]
			if not events_by_patch_year.has(event_key):
				continue
			var event: Dictionary = events_by_patch_year[event_key]
			var applied := DisturbanceRecovery.apply_event(states[patch_id], strategies, Dictionary(patches[patch_id])["environment"], event)
			if applied.is_empty():
				return {}
			states[patch_id] = applied["state"]
			var record: Dictionary = applied["event_record"]
			disturbance_all_conserve = disturbance_all_conserve and bool(record.get("adult_conservation_ok", false)) and bool(record.get("seed_bank_conservation_ok", false))
			var logged := record.duplicate(true)
			logged["patch_id"] = patch_id
			disturbance_log.append(logged)

		# Accepted P2.5 local recovery/turnover advances every patch exactly one year.
		for patch_id in _sorted_keys(patches):
			var annual := DisturbanceRecovery.advance_year(states[patch_id], strategies, Dictionary(patches[patch_id])["environment"], year)
			if annual.is_empty():
				return {}
			states[patch_id] = annual["state"]
			cumulative_reactivated += int(annual["reactivated_seed_count"])

		var summary := _regional_summary(year, patches, states, strategies)
		if summary.is_empty():
			return {}
		var current_occupancy := _adult_occupancy_map(summary, strategies)
		for key in _sorted_keys(current_occupancy):
			var before := bool(previous_occupancy.get(key, false))
			var after := bool(current_occupancy[key])
			if before == after:
				continue
			var transition_type := "LOCAL_ADULT_EXTINCTION"
			if after:
				transition_type = "RECOLONIZATION" if bool(ever_occupied.get(key, false)) else "COLONIZATION"
				ever_occupied[key] = true
			var parts := key.split("|", false, 1)
			var transition := {
				"year": year,
				"patch_id": String(parts[0]),
				"lineage_id": String(parts[1]),
				"transition": transition_type,
			}
			transition["transition_hash"] = _transition_hash(transition)
			transition_log.append(transition)
		previous_occupancy = current_occupancy
		history.append(summary)
		max_adult_cohorts = maxi(max_adult_cohorts, int(summary["total_adult_cohorts"]))
		max_bank_cohorts = maxi(max_bank_cohorts, int(summary["total_bank_cohorts"]))

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"years": years,
		"patch_count": patches.size(),
		"source_patch_ids": source_ids,
		"history": history,
		"transition_log": transition_log,
		"migration_log": migration_log,
		"disturbance_log": disturbance_log,
		"final_states": states,
		"final_summary": history[history.size() - 1],
		"cumulative_emitted_seed_count": cumulative_emitted,
		"cumulative_routed_seed_count": cumulative_routed,
		"cumulative_unresolved_export_seed_count": cumulative_unresolved,
		"cumulative_recruited_seed_count": cumulative_recruited,
		"cumulative_seed_bank_arrival_count": cumulative_banked,
		"cumulative_reactivated_seed_count": cumulative_reactivated,
		"migration_all_conserve": migration_all_conserve,
		"disturbance_all_conserve": disturbance_all_conserve,
		"max_adult_cohorts": max_adult_cohorts,
		"max_bank_cohorts": max_bank_cohorts,
	}
	result["result_hash"] = _result_hash(result)
	return result

static func transition_year(result: Dictionary, patch_id: String, lineage_id: String, transition_type: String, after_year: int = -1) -> int:
	for value in Array(result.get("transition_log", [])):
		var transition: Dictionary = value
		if String(transition.get("patch_id", "")) == patch_id and String(transition.get("lineage_id", "")) == lineage_id and String(transition.get("transition", "")) == transition_type and int(transition.get("year", -1)) > after_year:
			return int(transition["year"])
	return -1

static func patch_years_adult_occupied(result: Dictionary, patch_id: String, lineage_id: String) -> int:
	var count := 0
	for value in Array(result.get("history", [])):
		var summary: Dictionary = value
		var patch_summary := _patch_summary_from_regional(summary, patch_id)
		if not patch_summary.is_empty() and float(Dictionary(patch_summary["adult_biomass_by_lineage"]).get(lineage_id, 0.0)) > PopulationTurnover.EXTINCTION_BIOMASS_KG_M2:
			count += 1
	return count

static func lineage_patch_years(result: Dictionary, lineage_id: String) -> int:
	var total := 0
	for value in Array(result.get("history", [])):
		var summary: Dictionary = value
		total += int(Dictionary(summary.get("adult_range_patch_count", {})).get(lineage_id, 0))
	return total

static func max_adult_range(result: Dictionary, lineage_id: String) -> int:
	var maximum := 0
	for value in Array(result.get("history", [])):
		var summary: Dictionary = value
		maximum = maxi(maximum, int(Dictionary(summary.get("adult_range_patch_count", {})).get(lineage_id, 0)))
	return maximum

static func regional_adult_never_absent(result: Dictionary, lineage_id: String) -> bool:
	for value in Array(result.get("history", [])):
		var summary: Dictionary = value
		if int(Dictionary(summary.get("adult_range_patch_count", {})).get(lineage_id, 0)) <= 0:
			return false
	return true

static func final_patch_adult_occupied(result: Dictionary, patch_id: String, lineage_id: String) -> bool:
	var summary: Dictionary = result.get("final_summary", {})
	var patch_summary := _patch_summary_from_regional(summary, patch_id)
	return not patch_summary.is_empty() and float(Dictionary(patch_summary["adult_biomass_by_lineage"]).get(lineage_id, 0.0)) > PopulationTurnover.EXTINCTION_BIOMASS_KG_M2

static func _apply_arrival(state: Dictionary, patch: Dictionary, strategy: Dictionary, lineage: String, year: int, recruited: int, banked: int, source_hash: String) -> Dictionary:
	var next_state := _copy_state(state)
	var genome: Dictionary = strategy["genome"]
	var traits: Dictionary = strategy["recruitment_traits"]
	var environment: Dictionary = patch["environment"]
	if recruited > 0:
		var biomass := PatchBaseline.DEFAULT_INITIAL_BIOMASS_KG_M2 * float(recruited) / maxf(float(genome["seed_count"]), 1.0)
		var adult := DisturbanceRecovery.create_adult(lineage, genome, 0.0, maxf(biomass, EPSILON * 10.0), maxf(float(genome["height_m"]) * 0.10, 0.05), (source_hash + "|adult|" + String(patch["patch_id"]) + "|" + str(year)).sha256_text())
		if adult.is_empty():
			return {}
		var adults: Array = next_state["adults"]
		adults.append(adult)
		next_state["adults"] = adults
	if banked > 0:
		var bank := DisturbanceRecovery.create_seed_bank(lineage, genome, traits, environment, banked, 0.0, (source_hash + "|bank|" + String(patch["patch_id"]) + "|" + str(year)).sha256_text())
		if bank.is_empty():
			return {}
		var banks: Array = next_state["banks"]
		banks.append(bank)
		next_state["banks"] = banks
	return {"state": next_state}

static func _emitted_seed_count(lineage: String, year: int, aggregate: Dictionary, genome: Dictionary, environment: Dictionary, total_biomass: float) -> int:
	var resource := ResourceModel.evaluate(environment, genome, total_biomass)
	if resource.is_empty():
		return 0
	var reserve_resource := maxf(float(resource["net_resource_balance"]), 0.0) * float(aggregate["biomass_kg_m2"])
	var lifecycle_state := Lifecycle.create_state(float(aggregate["mean_height_m"]), float(aggregate["biomass_kg_m2"]), reserve_resource, float(aggregate["mean_age_years"]))
	var lifecycle := Lifecycle.evaluate(genome, environment, lifecycle_state, Lifecycle.create_disturbance(0.0))
	if lifecycle.is_empty():
		return 0
	var cohort_scale := clampf(float(aggregate["biomass_kg_m2"]) / maxf(PatchBaseline.DEFAULT_INITIAL_BIOMASS_KG_M2, EPSILON), 0.0, 1.0)
	var expected := float(lifecycle["realized_seed_output_per_year"]) * cohort_scale
	return _deterministic_count(int(genome["seed_count"]), expected / maxf(float(genome["seed_count"]), 1.0), "p2-6|%s|%d|emit" % [lineage, year])

static func _lineage_aggregates(adults: Array, strategies: Dictionary) -> Dictionary:
	var grouped := {}
	for value in adults:
		var adult: Dictionary = value
		var lineage := String(adult.get("lineage_id", ""))
		if not strategies.has(lineage):
			continue
		if not grouped.has(lineage):
			grouped[lineage] = {"biomass_kg_m2": 0.0, "age_weight": 0.0, "height_weight": 0.0}
		var entry: Dictionary = grouped[lineage]
		var biomass := float(adult.get("biomass_kg_m2", 0.0))
		entry["biomass_kg_m2"] = float(entry["biomass_kg_m2"]) + biomass
		entry["age_weight"] = float(entry["age_weight"]) + float(adult.get("age_years", 0.0)) * biomass
		entry["height_weight"] = float(entry["height_weight"]) + float(adult.get("current_height_m", 0.0)) * biomass
		grouped[lineage] = entry
	for lineage in _sorted_keys(grouped):
		var entry: Dictionary = grouped[lineage]
		var biomass := float(entry["biomass_kg_m2"])
		if biomass <= EPSILON:
			grouped.erase(lineage)
			continue
		entry["mean_age_years"] = float(entry["age_weight"]) / biomass
		entry["mean_height_m"] = float(entry["height_weight"]) / biomass
		grouped[lineage] = entry
	return grouped

static func _regional_summary(year: int, patches: Dictionary, states: Dictionary, strategies: Dictionary) -> Dictionary:
	var patch_summaries: Array = []
	var adult_range := {}
	var presence_range := {}
	for lineage in _sorted_keys(strategies):
		adult_range[lineage] = 0
		presence_range[lineage] = 0
	var total_adult_cohorts := 0
	var total_bank_cohorts := 0
	for patch_id in _sorted_keys(patches):
		var state: Dictionary = states[patch_id]
		var adult_biomass := {}
		var bank_counts := {}
		for lineage in _sorted_keys(strategies):
			adult_biomass[lineage] = 0.0
			bank_counts[lineage] = 0
		for value in Array(state["adults"]):
			var adult: Dictionary = value
			var lineage := String(adult["lineage_id"])
			adult_biomass[lineage] = float(adult_biomass.get(lineage, 0.0)) + float(adult["biomass_kg_m2"])
		for value in Array(state["banks"]):
			var bank: Dictionary = value
			var lineage := String(bank["lineage_id"])
			bank_counts[lineage] = int(bank_counts.get(lineage, 0)) + int(bank["seed_count"])
		for lineage in _sorted_keys(strategies):
			var adult_present := float(adult_biomass[lineage]) > PopulationTurnover.EXTINCTION_BIOMASS_KG_M2
			var bank_present := int(bank_counts[lineage]) > 0
			if adult_present:
				adult_range[lineage] = int(adult_range[lineage]) + 1
			if adult_present or bank_present:
				presence_range[lineage] = int(presence_range[lineage]) + 1
		var patch_summary := {
			"patch_id": patch_id,
			"adult_biomass_by_lineage": adult_biomass,
			"seed_bank_by_lineage": bank_counts,
			"adult_cohort_count": Array(state["adults"]).size(),
			"bank_cohort_count": Array(state["banks"]).size(),
		}
		patch_summary["summary_hash"] = _patch_summary_hash(patch_summary)
		patch_summaries.append(patch_summary)
		total_adult_cohorts += int(patch_summary["adult_cohort_count"])
		total_bank_cohorts += int(patch_summary["bank_cohort_count"])
	var summary := {
		"year": year,
		"patch_summaries": patch_summaries,
		"adult_range_patch_count": adult_range,
		"presence_range_patch_count": presence_range,
		"total_adult_cohorts": total_adult_cohorts,
		"total_bank_cohorts": total_bank_cohorts,
	}
	summary["summary_hash"] = _regional_summary_hash(summary)
	return summary

static func _adult_occupancy_map(summary: Dictionary, strategies: Dictionary) -> Dictionary:
	var result := {}
	for patch_value in Array(summary.get("patch_summaries", [])):
		var patch: Dictionary = patch_value
		var patch_id := String(patch["patch_id"])
		var biomass: Dictionary = patch["adult_biomass_by_lineage"]
		for lineage in _sorted_keys(strategies):
			result[patch_id + "|" + lineage] = float(biomass.get(lineage, 0.0)) > PopulationTurnover.EXTINCTION_BIOMASS_KG_M2
	return result

static func _patch_summary_from_regional(summary: Dictionary, patch_id: String) -> Dictionary:
	for value in Array(summary.get("patch_summaries", [])):
		var patch: Dictionary = value
		if String(patch.get("patch_id", "")) == patch_id:
			return patch
	return {}

static func _validate_transport_schedule(schedule: Array) -> bool:
	var previous := -1
	for value in schedule:
		var entry: Dictionary = value
		var year_start := int(entry.get("year_start", -1))
		var vector := Vector2(entry.get("transport_vector", Vector2(INF, INF)))
		var turbulence := float(entry.get("turbulence", -1.0))
		if year_start < 1 or year_start <= previous or not is_finite(vector.x) or not is_finite(vector.y) or vector.length() > 1.0 + EPSILON or not is_finite(turbulence) or turbulence < 0.0 or turbulence > 1.0:
			return false
		previous = year_start
	return true

static func _transport_for_year(schedule: Array, year: int) -> Dictionary:
	var selected := {}
	for value in schedule:
		var entry: Dictionary = value
		if int(entry["year_start"]) <= year:
			selected = entry
		else:
			break
	return selected

static func _index_disturbances(schedule: Dictionary, patches: Dictionary, years: int) -> Dictionary:
	var indexed := {}
	for patch_value in schedule.keys():
		var patch_id := String(patch_value)
		if not patches.has(patch_id):
			return {}
		for event_value in Array(schedule[patch_id]):
			var event: Dictionary = event_value
			var year := int(event.get("year", -1))
			if year <= 0 or year > years:
				return {}
			var key := "%s|%d" % [patch_id, year]
			if indexed.has(key):
				return {}
			indexed[key] = event
	return indexed

static func _valid_strategies(strategies: Dictionary) -> bool:
	if strategies.is_empty():
		return false
	for lineage in strategies.keys():
		var strategy: Dictionary = strategies[lineage]
		if String(lineage).is_empty() or not bool(PlantGenome.validate(Dictionary(strategy.get("genome", {}))).get("success", false)) or not RecruitmentTraits.validate(Dictionary(strategy.get("recruitment_traits", {}))):
			return false
	return true

static func _state_shape_valid(state: Dictionary) -> bool:
	return state.has("adults") and state.has("banks") and typeof(state["adults"]) == TYPE_ARRAY and typeof(state["banks"]) == TYPE_ARRAY

static func _copy_state(state: Dictionary) -> Dictionary:
	return {"adults": Array(state.get("adults", [])).duplicate(true), "banks": Array(state.get("banks", [])).duplicate(true)}

static func _total_biomass(adults: Array) -> float:
	var total := 0.0
	for value in adults:
		total += float(Dictionary(value).get("biomass_kg_m2", 0.0))
	return total

static func _deterministic_count(total: int, fraction: float, key: String) -> int:
	if total <= 0:
		return 0
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

static func _sorted_keys(dictionary: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for value in dictionary.keys():
		result.append(String(value))
	result.sort()
	return result

static func _migration_record_hash(record: Dictionary) -> String:
	return "|".join(PackedStringArray([str(int(record.get("year", 0))), String(record.get("source_patch_id", "")), String(record.get("lineage_id", "")), str(int(record.get("emitted", 0))), str(int(record.get("routed", 0))), str(int(record.get("unresolved", 0))), String(record.get("migration_hash", ""))])).sha256_text()

static func _transition_hash(transition: Dictionary) -> String:
	return "|".join(PackedStringArray([str(int(transition.get("year", 0))), String(transition.get("patch_id", "")), String(transition.get("lineage_id", "")), String(transition.get("transition", ""))])).sha256_text()

static func _patch_summary_hash(summary: Dictionary) -> String:
	var tokens := PackedStringArray([String(summary.get("patch_id", "")), str(int(summary.get("adult_cohort_count", 0))), str(int(summary.get("bank_cohort_count", 0)))])
	var biomass: Dictionary = summary.get("adult_biomass_by_lineage", {})
	for lineage in _sorted_keys(biomass):
		tokens.append(lineage + "=%.12f" % float(biomass[lineage]))
	var banks: Dictionary = summary.get("seed_bank_by_lineage", {})
	for lineage in _sorted_keys(banks):
		tokens.append(lineage + "=" + str(int(banks[lineage])))
	return "|".join(tokens).sha256_text()

static func _regional_summary_hash(summary: Dictionary) -> String:
	var tokens := PackedStringArray([str(int(summary.get("year", 0))), str(int(summary.get("total_adult_cohorts", 0))), str(int(summary.get("total_bank_cohorts", 0)))])
	for value in Array(summary.get("patch_summaries", [])):
		tokens.append(String(Dictionary(value).get("summary_hash", "")))
	var adult_range: Dictionary = summary.get("adult_range_patch_count", {})
	for lineage in _sorted_keys(adult_range):
		tokens.append("adult|" + lineage + "=" + str(int(adult_range[lineage])))
	var presence_range: Dictionary = summary.get("presence_range_patch_count", {})
	for lineage in _sorted_keys(presence_range):
		tokens.append("presence|" + lineage + "=" + str(int(presence_range[lineage])))
	return "\n".join(tokens).sha256_text()

static func _result_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		str(int(result.get("years", 0))),
		str(int(result.get("patch_count", 0))),
		str(int(result.get("cumulative_emitted_seed_count", 0))),
		str(int(result.get("cumulative_routed_seed_count", 0))),
		str(int(result.get("cumulative_unresolved_export_seed_count", 0))),
		str(int(result.get("cumulative_recruited_seed_count", 0))),
		str(int(result.get("cumulative_seed_bank_arrival_count", 0))),
		str(int(result.get("cumulative_reactivated_seed_count", 0))),
		str(bool(result.get("migration_all_conserve", false))),
		str(bool(result.get("disturbance_all_conserve", false))),
	])
	for value in Array(result.get("history", [])):
		tokens.append(String(Dictionary(value).get("summary_hash", "")))
	for value in Array(result.get("transition_log", [])):
		tokens.append(String(Dictionary(value).get("transition_hash", "")))
	for value in Array(result.get("migration_log", [])):
		tokens.append(String(Dictionary(value).get("record_hash", "")))
	for value in Array(result.get("disturbance_log", [])):
		tokens.append(String(Dictionary(value).get("record_hash", "")))
	return "\n".join(tokens).sha256_text()
