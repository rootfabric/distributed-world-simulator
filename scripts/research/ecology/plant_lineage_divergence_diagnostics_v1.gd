extends RefCounted

const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const RecruitmentTraits = preload("res://scripts/research/ecology/plant_recruitment_traits_v1.gd")
const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo1_p2_7_lineage_divergence_diagnostics.v1"
const OBSERVATION_SCHEMA := SCHEMA + ".lineage_observation"
const VERSION := "1.0.0"

# Research detection policy only. These gates flag convergent evidence for further
# investigation; they do not define biological species or canonical taxonomy.
const MIN_SPLIT_AGE_YEARS := 12
const MIN_ISOLATION_FRACTION := 0.75
const MAX_CONNECTION_FRACTION := 0.10
const MIN_GENOME_DISTANCE := 0.18
const MIN_ECOLOGICAL_HISTORY_DISTANCE := 0.10
const EPSILON := 0.000000000001

static func create_observation(
	lineage_id: String,
	ancestry_path: Array,
	split_year: int,
	genome: Dictionary,
	recruitment_traits: Dictionary,
	geography_history: Array,
	ecology_history: Array
) -> Dictionary:
	if lineage_id.is_empty() or lineage_id != lineage_id.strip_edges() or split_year < 0:
		return {}
	if not bool(PlantGenome.validate(genome).get("success", false)):
		return {}
	if not RecruitmentTraits.validate(recruitment_traits):
		return {}
	var ancestry := _canonical_ancestry(ancestry_path)
	if ancestry.is_empty() or String(ancestry[ancestry.size() - 1]) != lineage_id:
		return {}
	var geography := _canonical_geography(geography_history)
	var ecology := _canonical_ecology(ecology_history)
	if geography.is_empty() or ecology.is_empty():
		return {}
	var result := {
		"schema": OBSERVATION_SCHEMA,
		"version": VERSION,
		"lineage_id": lineage_id,
		"ancestry_path": ancestry,
		"split_year": split_year,
		"genome": genome.duplicate(true),
		"genome_checksum": String(genome["checksum"]),
		"recruitment_traits": recruitment_traits.duplicate(true),
		"recruitment_traits_checksum": String(recruitment_traits["checksum"]),
		"geography_history": geography,
		"ecology_history": ecology,
	}
	result["observation_hash"] = _observation_hash(result)
	return result

static func validate_observation(observation: Dictionary) -> bool:
	if String(observation.get("schema", "")) != OBSERVATION_SCHEMA or String(observation.get("version", "")) != VERSION:
		return false
	var lineage_id := String(observation.get("lineage_id", ""))
	if lineage_id.is_empty() or int(observation.get("split_year", -1)) < 0:
		return false
	var genome: Dictionary = observation.get("genome", {})
	var traits: Dictionary = observation.get("recruitment_traits", {})
	if not bool(PlantGenome.validate(genome).get("success", false)) or not RecruitmentTraits.validate(traits):
		return false
	if String(observation.get("genome_checksum", "")) != String(genome.get("checksum", "")):
		return false
	if String(observation.get("recruitment_traits_checksum", "")) != String(traits.get("checksum", "")):
		return false
	var ancestry := _canonical_ancestry(Array(observation.get("ancestry_path", [])))
	if ancestry != Array(observation.get("ancestry_path", [])) or ancestry.is_empty() or String(ancestry[ancestry.size() - 1]) != lineage_id:
		return false
	var geography := _canonical_geography(Array(observation.get("geography_history", [])))
	var ecology := _canonical_ecology(Array(observation.get("ecology_history", [])))
	if geography != Array(observation.get("geography_history", [])) or ecology != Array(observation.get("ecology_history", [])):
		return false
	return String(observation.get("observation_hash", "")) == _observation_hash(observation)

static func diagnose_pair(left: Dictionary, right: Dictionary, connection_years: Array) -> Dictionary:
	if not validate_observation(left) or not validate_observation(right):
		return {}
	if String(left["lineage_id"]) == String(right["lineage_id"]):
		return {}
	var left_geo := _geography_map(Array(left["geography_history"]))
	var right_geo := _geography_map(Array(right["geography_history"]))
	var split_year := maxi(int(left["split_year"]), int(right["split_year"]))
	var end_year := mini(_last_year(Array(left["geography_history"])), _last_year(Array(right["geography_history"])))
	if end_year <= split_year:
		return {}

	var joint_presence_years := 0
	var isolation_years := 0
	var colocated_years := 0
	for year in range(split_year + 1, end_year + 1):
		if not left_geo.has(year) or not right_geo.has(year):
			continue
		var left_patches: Array = left_geo[year]
		var right_patches: Array = right_geo[year]
		if left_patches.is_empty() or right_patches.is_empty():
			continue
		joint_presence_years += 1
		if _patch_overlap(left_patches, right_patches):
			colocated_years += 1
		else:
			isolation_years += 1

	if joint_presence_years <= 0:
		return {}
	var canonical_connections := _canonical_connection_years(connection_years, split_year, end_year)
	var connection_count := 0
	for year_value in canonical_connections:
		var year := int(year_value)
		if left_geo.has(year) and right_geo.has(year) and not Array(left_geo[year]).is_empty() and not Array(right_geo[year]).is_empty():
			connection_count += 1

	var shared_ancestor := _shared_ancestor(Array(left["ancestry_path"]), Array(right["ancestry_path"]))
	var split_age := end_year - split_year
	var isolation_fraction := float(isolation_years) / float(joint_presence_years)
	var connection_fraction := float(connection_count) / float(joint_presence_years)
	var genome_distance := _genome_distance(Dictionary(left["genome"]), Dictionary(right["genome"]))
	var recruitment_distance := _recruitment_distance(Dictionary(left["recruitment_traits"]), Dictionary(right["recruitment_traits"]))
	var ecological_distance := _ecological_history_distance(Array(left["ecology_history"]), Array(right["ecology_history"]), split_year, end_year)

	var evidence := {
		"shared_ancestry": not shared_ancestor.is_empty(),
		"split_age_ok": split_age >= MIN_SPLIT_AGE_YEARS,
		"isolation_ok": isolation_fraction >= MIN_ISOLATION_FRACTION,
		"connectivity_ok": connection_fraction <= MAX_CONNECTION_FRACTION,
		"genome_divergence_ok": genome_distance >= MIN_GENOME_DISTANCE,
		"ecological_divergence_ok": ecological_distance >= MIN_ECOLOGICAL_HISTORY_DISTANCE,
	}
	var candidate := true
	for key in evidence.keys():
		candidate = candidate and bool(evidence[key])

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"left_lineage_id": String(left["lineage_id"]),
		"right_lineage_id": String(right["lineage_id"]),
		"left_observation_hash": String(left["observation_hash"]),
		"right_observation_hash": String(right["observation_hash"]),
		"shared_ancestor_id": shared_ancestor,
		"split_year": split_year,
		"end_year": end_year,
		"split_age_years": split_age,
		"joint_presence_years": joint_presence_years,
		"isolation_years": isolation_years,
		"colocated_years": colocated_years,
		"connection_years": canonical_connections,
		"connection_year_count": connection_count,
		"isolation_fraction": isolation_fraction,
		"connection_fraction": connection_fraction,
		"genome_distance": genome_distance,
		"recruitment_trait_distance": recruitment_distance,
		"ecological_history_distance": ecological_distance,
		"evidence": evidence,
		"speciation_candidate": candidate,
		"classification": "SPECIATION_CANDIDATE" if candidate else "DIVERGENCE_EVIDENCE_INSUFFICIENT",
		"canonical_species_declared": false,
	}
	result["result_hash"] = _result_hash(result)
	return result

static func _canonical_ancestry(values: Array) -> Array:
	if values.is_empty():
		return []
	var result: Array = []
	var seen := {}
	for value in values:
		var lineage := String(value)
		if lineage.is_empty() or lineage != lineage.strip_edges() or seen.has(lineage):
			return []
		seen[lineage] = true
		result.append(lineage)
	return result

static func _canonical_geography(history: Array) -> Array:
	var result: Array = []
	var previous_year := -1
	for value in history:
		var entry: Dictionary = value
		var year := int(entry.get("year", -1))
		if year < 0 or year <= previous_year:
			return []
		var patches: Array = []
		var seen := {}
		for patch_value in Array(entry.get("patch_ids", [])):
			var patch_id := String(patch_value)
			if patch_id.is_empty() or patch_id != patch_id.strip_edges() or seen.has(patch_id):
				return []
			seen[patch_id] = true
			patches.append(patch_id)
		patches.sort()
		result.append({"year": year, "patch_ids": patches})
		previous_year = year
	return result

static func _canonical_ecology(history: Array) -> Array:
	var result: Array = []
	var previous_year := -1
	for value in history:
		var entry: Dictionary = value
		var year := int(entry.get("year", -1))
		var environment: Dictionary = entry.get("environment", {})
		if year < 0 or year <= previous_year or not bool(EnvironmentSample.validate(environment).get("success", false)):
			return []
		result.append({"year": year, "environment": environment.duplicate(true)})
		previous_year = year
	return result

static func _canonical_connection_years(values: Array, split_year: int, end_year: int) -> Array:
	var result: Array = []
	var seen := {}
	for value in values:
		var year := int(value)
		if year <= split_year or year > end_year or seen.has(year):
			continue
		seen[year] = true
		result.append(year)
	result.sort()
	return result

static func _shared_ancestor(left: Array, right: Array) -> String:
	var shared := ""
	var limit := mini(left.size(), right.size())
	for index in range(limit):
		if String(left[index]) != String(right[index]):
			break
		shared = String(left[index])
	return shared

static func _geography_map(history: Array) -> Dictionary:
	var result := {}
	for value in history:
		var entry: Dictionary = value
		result[int(entry["year"])] = Array(entry["patch_ids"])
	return result

static func _last_year(history: Array) -> int:
	if history.is_empty():
		return -1
	return int(Dictionary(history[history.size() - 1])["year"])

static func _patch_overlap(left: Array, right: Array) -> bool:
	var right_set := {}
	for value in right:
		right_set[String(value)] = true
	for value in left:
		if right_set.has(String(value)):
			return true
	return false

static func _genome_distance(left: Dictionary, right: Dictionary) -> float:
	var fields := ["height_m", "growth_rate", "root_depth_m", "water_preference", "water_tolerance_width", "shade_tolerance", "seed_count", "seed_dispersal_distance_m", "lifespan_years"]
	var total := 0.0
	for field_name in fields:
		total += _symmetric_relative_distance(float(left[field_name]), float(right[field_name]))
	return total / float(fields.size())

static func _recruitment_distance(left: Dictionary, right: Dictionary) -> float:
	var dormancy := absf(float(left["dormancy_fraction"]) - float(right["dormancy_fraction"]))
	var half_life := _symmetric_relative_distance(float(left["seed_bank_half_life_years"]), float(right["seed_bank_half_life_years"]))
	return (dormancy + half_life) * 0.5

static func _ecological_history_distance(left: Array, right: Array, split_year: int, end_year: int) -> float:
	var left_map := {}
	for value in left:
		var entry: Dictionary = value
		left_map[int(entry["year"])] = Dictionary(entry["environment"])
	var right_map := {}
	for value in right:
		var entry: Dictionary = value
		right_map[int(entry["year"])] = Dictionary(entry["environment"])
	var total := 0.0
	var count := 0
	for year in range(split_year + 1, end_year + 1):
		if not left_map.has(year) or not right_map.has(year):
			continue
		var a: Dictionary = left_map[year]
		var b: Dictionary = right_map[year]
		var distance := 0.0
		distance += clampf(absf(float(a["temperature_c"]) - float(b["temperature_c"])) / 60.0, 0.0, 1.0)
		distance += absf(float(a["soil_moisture"]) - float(b["soil_moisture"]))
		distance += absf(float(a["sunlight"]) - float(b["sunlight"]))
		distance += absf(float(a["nutrients"]) - float(b["nutrients"]))
		distance += absf(float(a["flood_frequency"]) - float(b["flood_frequency"]))
		total += distance / 5.0
		count += 1
	return 0.0 if count == 0 else total / float(count)

static func _symmetric_relative_distance(a: float, b: float) -> float:
	return clampf(absf(a - b) / maxf(maxf(absf(a), absf(b)), EPSILON), 0.0, 1.0)

static func _observation_hash(observation: Dictionary) -> String:
	var tokens := PackedStringArray([
		OBSERVATION_SCHEMA,
		VERSION,
		String(observation.get("lineage_id", "")),
		str(int(observation.get("split_year", -1))),
		String(observation.get("genome_checksum", "")),
		String(observation.get("recruitment_traits_checksum", "")),
	])
	for value in Array(observation.get("ancestry_path", [])):
		tokens.append("ancestor=" + String(value))
	for value in Array(observation.get("geography_history", [])):
		var entry: Dictionary = value
		tokens.append("geo|%d|%s" % [int(entry["year"]), ",".join(PackedStringArray(Array(entry["patch_ids"])))])
	for value in Array(observation.get("ecology_history", [])):
		var entry: Dictionary = value
		tokens.append("eco|%d|%s" % [int(entry["year"]), String(Dictionary(entry["environment"])["checksum"])])
	return "\n".join(tokens).sha256_text()

static func _result_hash(result: Dictionary) -> String:
	var evidence: Dictionary = result.get("evidence", {})
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		String(result.get("left_lineage_id", "")),
		String(result.get("right_lineage_id", "")),
		String(result.get("left_observation_hash", "")),
		String(result.get("right_observation_hash", "")),
		String(result.get("shared_ancestor_id", "")),
		str(int(result.get("split_year", -1))),
		str(int(result.get("end_year", -1))),
		str(int(result.get("split_age_years", 0))),
		str(int(result.get("joint_presence_years", 0))),
		str(int(result.get("isolation_years", 0))),
		str(int(result.get("colocated_years", 0))),
		str(int(result.get("connection_year_count", 0))),
		"%.12f" % float(result.get("isolation_fraction", 0.0)),
		"%.12f" % float(result.get("connection_fraction", 0.0)),
		"%.12f" % float(result.get("genome_distance", 0.0)),
		"%.12f" % float(result.get("recruitment_trait_distance", 0.0)),
		"%.12f" % float(result.get("ecological_history_distance", 0.0)),
		String(result.get("classification", "")),
		str(bool(result.get("speciation_candidate", false))),
		str(bool(result.get("canonical_species_declared", true))),
	])
	var evidence_keys: Array = evidence.keys()
	evidence_keys.sort()
	for key_value in evidence_keys:
		var key := String(key_value)
		tokens.append(key + "=" + str(bool(evidence[key])))
	for year_value in Array(result.get("connection_years", [])):
		tokens.append("connection=" + str(int(year_value)))
	return "\n".join(tokens).sha256_text()
