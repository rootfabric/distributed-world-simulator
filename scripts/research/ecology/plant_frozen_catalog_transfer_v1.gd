extends RefCounted

const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const SpeciesCatalog = preload("res://scripts/research/ecology/plant_species_catalog_v1.gd")
const BakeExport = preload("res://scripts/research/ecology/plant_evolution_bake_export_v1.gd")
const PatchMigration = preload("res://scripts/research/ecology/plant_patch_migration_v1.gd")
const DisturbanceRecovery = preload("res://scripts/research/ecology/plant_disturbance_recovery_v1.gd")
const Biogeography = preload("res://scripts/research/ecology/plant_long_horizon_biogeography_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo2_frozen_catalog_transfer.v1"
const TARGET_SCHEMA := SCHEMA + ".target"
const VERSION := "1.0.0"
const PARENT_E2_2_ACCEPTED_AGGREGATE := "56d4b8bfd3064ad37b720d5bff2bc98bb72b0ab7ad871877fc268d5e6df703ce"
const ACCEPTED_E2_2_BAKE_HASH := "45496eb67aac5cc0a65babfeb0c49fa99616df17c2f7e8b9e8b95d04cb2b4e5b"
const ACCEPTED_E2_2_CATALOG_HASH := "5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219"
const EVOLUTION_ENABLED := false
const CANONICAL_SPECIES_DECLARED := false
const PRODUCTION_AUTHORITY_CLAIMED := false
const SOURCE_PORT_ID := "eco-evo2-transfer/source-port"
const SOURCE_PORT_BOUNDS := Rect2(-1.0, -1.0, 2.0, 2.0)
const MAX_YEARS := 60
const EPSILON := 0.000000000001

static func create_target(target_id: String, patches: Array, years: int, transport_schedule: Array) -> Dictionary:
	if target_id.is_empty() or target_id != target_id.strip_edges() or patches.is_empty() or years <= 0 or years > MAX_YEARS:
		return {}
	var canonical_patches: Array = []
	var seen := {}
	for value in patches:
		if typeof(value) != TYPE_DICTIONARY:
			return {}
		var patch: Dictionary = Dictionary(value).duplicate(true)
		if not PatchMigration.validate_patch(patch):
			return {}
		var patch_id := String(patch["patch_id"])
		if seen.has(patch_id) or patch_id == SOURCE_PORT_ID or SOURCE_PORT_BOUNDS.intersects(Rect2(patch["bounds"])):
			return {}
		for prior_value in canonical_patches:
			if Rect2(Dictionary(prior_value)["bounds"]).intersects(Rect2(patch["bounds"])):
				return {}
		seen[patch_id] = true
		canonical_patches.append(patch)
	canonical_patches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["patch_id"]) < String(b["patch_id"]))
	var schedule := _canonical_schedule(transport_schedule, years)
	if schedule.is_empty():
		return {}
	var target := {"schema": TARGET_SCHEMA, "version": VERSION, "target_id": target_id, "patches": canonical_patches, "years": years, "transport_schedule": schedule}
	target["target_hash"] = compute_target_hash(target)
	return target

static func validate_target(target: Dictionary) -> bool:
	if target.keys().size() != 7:
		return false
	for key in ["schema", "version", "target_id", "patches", "years", "transport_schedule", "target_hash"]:
		if not target.has(key): return false
	if String(target["schema"]) != TARGET_SCHEMA or String(target["version"]) != VERSION:
		return false
	var rebuilt := create_target(String(target["target_id"]), Array(target["patches"]), int(target["years"]), Array(target["transport_schedule"]))
	return not rebuilt.is_empty() and rebuilt == target

static func transfer(bake_export: Dictionary, target: Dictionary) -> Dictionary:
	if not _valid_frozen_bake(bake_export) or not validate_target(target) or not _target_hidden_from_bake(bake_export, target):
		return {}
	return _execute(bake_export, target)

static func validate_result(bake_export: Dictionary, target: Dictionary, result: Dictionary) -> bool:
	if result.is_empty() or not _valid_frozen_bake(bake_export) or not validate_target(target) or not _target_hidden_from_bake(bake_export, target):
		return false
	var expected := _execute(bake_export, target)
	return not expected.is_empty() and expected == result

static func compute_target_hash(target: Dictionary) -> String:
	var tokens := PackedStringArray([TARGET_SCHEMA, VERSION, String(target.get("target_id", "")), str(int(target.get("years", 0)))])
	for value in Array(target.get("patches", [])):
		var patch: Dictionary = value
		tokens.append("patch=" + String(patch.get("patch_id", "")) + "|" + String(patch.get("checksum", "")))
	for value in Array(target.get("transport_schedule", [])):
		var entry: Dictionary = value
		var v := Vector2(entry.get("transport_vector", Vector2.ZERO))
		tokens.append("transport=%d|%.12f,%.12f|%.12f" % [int(entry.get("year_start", 0)), v.x, v.y, float(entry.get("turbulence", 0.0))])
	return "\n".join(tokens).sha256_text()

static func compute_result_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA, VERSION, PARENT_E2_2_ACCEPTED_AGGREGATE,
		String(result.get("e2_2_bake_hash", "")), String(result.get("catalog_hash", "")),
		String(result.get("target_hash", "")), str(bool(result.get("evolution_enabled", true))),
		String(result.get("initial_state_hash", "")), String(result.get("colonization_status", "")),
		str(int(result.get("first_colonization_year", -1))), String(result.get("final_population_state_hash", "")),
		String(Dictionary(result.get("biogeography", {})).get("result_hash", "")),
	])
	for value in Array(result.get("initial_inoculum", [])): tokens.append(String(Dictionary(value).get("inoculum_hash", "")))
	for value in Array(result.get("population_events", [])): tokens.append(String(Dictionary(value).get("event_hash", "")))
	return "\n".join(tokens).sha256_text()

static func _execute(bake_export: Dictionary, target: Dictionary) -> Dictionary:
	var catalog: Dictionary = Dictionary(bake_export["species_catalog"]).duplicate(true)
	var source_environment := EnvironmentSample.create(0.0, 0.0, 17.0, 0.58, 0.94, 0.82, 0.02, 2303001, "eco-evo2-e2-3-transfer-port")
	var source_patch: Dictionary = PatchMigration.create_patch(SOURCE_PORT_ID, SOURCE_PORT_BOUNDS, source_environment)
	if source_patch.is_empty(): return {}
	var strategies := {}
	var adults: Array = []
	var banks: Array = []
	var inoculum: Array = []
	for value in Array(catalog["entries"]):
		var entry: Dictionary = value
		var species_id := String(entry["research_species_id"])
		var genome: Dictionary = Dictionary(entry["genome"]).duplicate(true)
		var traits: Dictionary = Dictionary(entry["recruitment_traits"]).duplicate(true)
		strategies[species_id] = {"genome": genome, "recruitment_traits": traits}
		var adult: Dictionary = DisturbanceRecovery.create_adult(species_id, genome, 5.0, 0.08, maxf(float(genome["height_m"]), 0.05), ("e23|adult|" + species_id).sha256_text())
		var bank: Dictionary = DisturbanceRecovery.create_seed_bank(species_id, genome, traits, source_environment, int(genome["seed_count"]), 0.0, ("e23|bank|" + species_id).sha256_text())
		if adult.is_empty() or bank.is_empty(): return {}
		adults.append(adult); banks.append(bank)
		var item := {"research_species_id": species_id, "adult_cohort_hash": String(adult["cohort_hash"]), "seed_bank_cohort_hash": String(bank["cohort_hash"]), "genome_checksum": String(genome["checksum"]), "recruitment_traits_checksum": String(traits["checksum"])}
		item["inoculum_hash"] = "|".join(PackedStringArray([species_id, String(adult["cohort_hash"]), String(bank["cohort_hash"]), String(genome["checksum"]), String(traits["checksum"])] )).sha256_text()
		inoculum.append(item)
	inoculum.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["research_species_id"]) < String(b["research_species_id"]))
	var states: Array = [{"patch": source_patch, "state": {"adults": adults, "banks": banks}}]
	for value in Array(target["patches"]): states.append({"patch": Dictionary(value).duplicate(true), "state": {"adults": [], "banks": []}})
	var initial_hash := _initial_state_hash(catalog, target, source_patch, inoculum)
	var run: Dictionary = Biogeography.simulate(states, strategies, int(target["years"]), [SOURCE_PORT_ID], Array(target["transport_schedule"]).duplicate(true), {})
	if run.is_empty(): return {}
	var events := _events(run, target)
	var first := _first_colonization_year(events)
	var result := {
		"schema": SCHEMA, "version": VERSION, "parent_e2_2_accepted_aggregate": PARENT_E2_2_ACCEPTED_AGGREGATE,
		"e2_2_bake_hash": String(bake_export["bake_hash"]), "catalog_hash": String(catalog["catalog_hash"]),
		"target_id": String(target["target_id"]), "target_hash": String(target["target_hash"]),
		"evolution_enabled": EVOLUTION_ENABLED, "canonical_species_declared": CANONICAL_SPECIES_DECLARED, "production_authority_claimed": PRODUCTION_AUTHORITY_CLAIMED,
		"source_port_id": SOURCE_PORT_ID, "initial_inoculum": inoculum, "initial_state_hash": initial_hash,
		"history": _enriched_history(run), "population_events": events,
		"colonization_status": "COLONIZED" if first >= 0 else "VALID_NO_COLONIZATION", "first_colonization_year": first,
		"final_population_state_hash": _final_target_hash(run, target), "biogeography": run.duplicate(true),
	}
	if String(result["final_population_state_hash"]).length() != 64: return {}
	result["result_hash"] = compute_result_hash(result)
	return result

static func _valid_frozen_bake(bake: Dictionary) -> bool:
	if not BakeExport.validate_export(bake): return false
	if String(bake.get("bake_hash", "")) != ACCEPTED_E2_2_BAKE_HASH or String(bake.get("catalog_hash", "")) != ACCEPTED_E2_2_CATALOG_HASH: return false
	var catalog: Dictionary = bake.get("species_catalog", {})
	return SpeciesCatalog.validate_catalog(catalog) and String(catalog.get("catalog_hash", "")) == ACCEPTED_E2_2_CATALOG_HASH

static func _target_hidden_from_bake(bake: Dictionary, target: Dictionary) -> bool:
	var patch_ids := {}; var environment_hashes := {}
	for value in Array(Dictionary(bake["species_catalog"])["entries"]):
		for patch_id in Array(Dictionary(value).get("observed_patch_ids", [])): patch_ids[String(patch_id)] = true
	for lineage_value in Array(Dictionary(bake["source"]).get("lineages", [])):
		for observation_value in Array(Dictionary(lineage_value).get("observations", [])):
			var observation: Dictionary = observation_value
			for geography_value in Array(observation.get("geography_history", [])):
				for patch_id in Array(Dictionary(geography_value).get("patch_ids", [])): patch_ids[String(patch_id)] = true
			for ecology_value in Array(observation.get("ecology_history", [])):
				var environment: Dictionary = Dictionary(ecology_value).get("environment", {})
				environment_hashes[String(environment.get("checksum", ""))] = true
	for value in Array(target["patches"]):
		var patch: Dictionary = value
		if patch_ids.has(String(patch["patch_id"])) or environment_hashes.has(String(Dictionary(patch["environment"]).get("checksum", ""))): return false
	return true

static func _canonical_schedule(schedule: Array, years: int) -> Array:
	if schedule.is_empty(): return []
	var result: Array = []
	for value in schedule:
		if typeof(value) != TYPE_DICTIONARY: return []
		var e: Dictionary = value
		if e.keys().size() != 3 or not e.has("year_start") or not e.has("transport_vector") or not e.has("turbulence") or typeof(e["year_start"]) != TYPE_INT: return []
		var year := int(e["year_start"]); var v := Vector2(e["transport_vector"]); var t := float(e["turbulence"])
		if year < 1 or year > years or not is_finite(v.x) or not is_finite(v.y) or v.length() > 1.0 + EPSILON or not is_finite(t) or t < 0.0 or t > 1.0: return []
		result.append({"year_start": year, "transport_vector": v, "turbulence": t})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["year_start"]) < int(b["year_start"]))
	if int(Dictionary(result[0])["year_start"]) != 1: return []
	for i in range(1, result.size()):
		if int(Dictionary(result[i])["year_start"]) <= int(Dictionary(result[i - 1])["year_start"]): return []
	return result

static func _enriched_history(run: Dictionary) -> Array:
	var history: Array = Array(run.get("history", [])).duplicate(true)
	for summary_value in history:
		var summary: Dictionary = summary_value
		for patch_value in Array(summary.get("patch_summaries", [])):
			var patch: Dictionary = patch_value
			var adult: Dictionary = patch.get("adult_biomass_by_lineage", {})
			var banks: Dictionary = patch.get("seed_bank_by_lineage", {})
			var total_adult := 0.0; var total_bank := 0; var occupied := 0
			for key in adult.keys():
				var biomass := float(adult[key]); total_adult += biomass
				if biomass > 0.000001: occupied += 1
			for key in banks.keys(): total_bank += int(banks[key])
			patch["total_adult_biomass_kg_m2"] = total_adult
			patch["total_seed_bank_seed_count"] = total_bank
			patch["occupied_species_count"] = occupied
	return history

static func _events(run: Dictionary, target: Dictionary) -> Array:
	var ids := {}; for value in Array(target["patches"]): ids[String(Dictionary(value)["patch_id"])] = true
	var result: Array = []
	for value in Array(run.get("transition_log", [])):
		var transition: Dictionary = value
		if not ids.has(String(transition.get("patch_id", ""))): continue
		var kind := String(transition.get("transition", ""))
		if kind == "COLONIZATION": kind = "RECRUITMENT_COLONIZATION"
		elif kind == "LOCAL_ADULT_EXTINCTION": kind = "EXTINCTION"
		var event := {"year": int(transition.get("year", -1)), "patch_id": String(transition.get("patch_id", "")), "research_species_id": String(transition.get("lineage_id", "")), "event_type": kind, "source_transition_hash": String(transition.get("transition_hash", ""))}
		event["event_hash"] = "|".join(PackedStringArray([str(event["year"]), event["patch_id"], event["research_species_id"], event["event_type"], event["source_transition_hash"]])).sha256_text(); result.append(event)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["event_hash"]) < String(b["event_hash"]))
	return result

static func _first_colonization_year(events: Array) -> int:
	var first := -1
	for value in events:
		var e: Dictionary = value
		if String(e["event_type"]) == "RECRUITMENT_COLONIZATION" and (first < 0 or int(e["year"]) < first): first = int(e["year"])
	return first

static func _initial_state_hash(catalog: Dictionary, target: Dictionary, source_patch: Dictionary, inoculum: Array) -> String:
	var tokens := PackedStringArray([String(catalog["catalog_hash"]), String(target["target_hash"]), String(source_patch["checksum"])])
	for value in inoculum: tokens.append(String(Dictionary(value)["inoculum_hash"]))
	for value in Array(target["patches"]): tokens.append("empty=" + String(Dictionary(value)["checksum"]))
	return "\n".join(tokens).sha256_text()

static func _final_target_hash(run: Dictionary, target: Dictionary) -> String:
	var states: Dictionary = run.get("final_states", {}); var tokens := PackedStringArray()
	for value in Array(target["patches"]):
		var patch_id := String(Dictionary(value)["patch_id"])
		if not states.has(patch_id): return ""
		var state: Dictionary = states[patch_id]; var hashes: Array[String] = []
		for adult in Array(state.get("adults", [])): hashes.append("a=" + String(Dictionary(adult).get("cohort_hash", "")))
		for bank in Array(state.get("banks", [])): hashes.append("b=" + String(Dictionary(bank).get("cohort_hash", "")))
		hashes.sort(); tokens.append("patch=" + patch_id); for h in hashes: tokens.append(h)
	return "\n".join(tokens).sha256_text()
