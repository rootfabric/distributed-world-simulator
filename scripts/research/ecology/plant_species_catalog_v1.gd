extends RefCounted

const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const RecruitmentTraits = preload("res://scripts/research/ecology/plant_recruitment_traits_v1.gd")
const DivergenceDiagnostics = preload("res://scripts/research/ecology/plant_lineage_divergence_diagnostics_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo2_species_catalog.v1"
const ENTRY_SCHEMA := SCHEMA + ".entry"
const VERSION := "1.0.0"
const SPECIES_CONCEPT := "ECO_RESEARCH_LINEAGE_HYPOTHESIS_V1"
const PARENT_P2_7_ACCEPTED_AGGREGATE := "7e814c0d8bdff952f9b86579b95fe305212ec02017c2298437e2ba3e46d2babe"

const CATALOG_FIELDS: Array[String] = [
	"schema",
	"version",
	"species_concept",
	"parent_p2_7_accepted_aggregate",
	"bake_id",
	"source_run_hash",
	"canonical_species_declared",
	"entries",
	"catalog_hash",
]

const ENTRY_FIELDS: Array[String] = [
	"schema",
	"version",
	"research_species_id",
	"lineage_id",
	"ancestry_path",
	"parent_lineage_id",
	"split_year",
	"genome",
	"genome_checksum",
	"recruitment_traits",
	"recruitment_traits_checksum",
	"observed_patch_ids",
	"source_observation_hash",
	"canonical_species_declared",
	"entry_hash",
]


static func build(observations: Array, bake_id: String, source_run_hash: String) -> Dictionary:
	if not _valid_id(bake_id) or not _is_lower_hex_64(source_run_hash) or observations.is_empty():
		return {}

	var entries: Array = []
	var seen_lineages := {}
	for value in observations:
		if typeof(value) != TYPE_DICTIONARY:
			return {}
		var observation: Dictionary = value
		var entry := create_entry(observation)
		if entry.is_empty():
			return {}
		var lineage_id := String(entry["lineage_id"])
		if seen_lineages.has(lineage_id):
			return {}
		seen_lineages[lineage_id] = true
		entries.append(entry)

	entries.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["research_species_id"]) < String(right["research_species_id"])
	)

	var catalog := {
		"schema": SCHEMA,
		"version": VERSION,
		"species_concept": SPECIES_CONCEPT,
		"parent_p2_7_accepted_aggregate": PARENT_P2_7_ACCEPTED_AGGREGATE,
		"bake_id": bake_id,
		"source_run_hash": source_run_hash,
		"canonical_species_declared": false,
		"entries": entries,
	}
	catalog["catalog_hash"] = compute_catalog_hash(catalog)
	if not validate_catalog(catalog):
		return {}
	return catalog


static func create_entry(observation: Dictionary) -> Dictionary:
	if not DivergenceDiagnostics.validate_observation(observation):
		return {}
	var lineage_id := String(observation.get("lineage_id", ""))
	var ancestry: Array = Array(observation.get("ancestry_path", [])).duplicate(true)
	if ancestry.is_empty() or String(ancestry[ancestry.size() - 1]) != lineage_id:
		return {}
	var parent_lineage_id := ""
	if ancestry.size() > 1:
		parent_lineage_id = String(ancestry[ancestry.size() - 2])
	var genome: Dictionary = Dictionary(observation.get("genome", {})).duplicate(true)
	var recruitment_traits: Dictionary = Dictionary(observation.get("recruitment_traits", {})).duplicate(true)
	var entry := {
		"schema": ENTRY_SCHEMA,
		"version": VERSION,
		"research_species_id": research_species_id(lineage_id),
		"lineage_id": lineage_id,
		"ancestry_path": ancestry,
		"parent_lineage_id": parent_lineage_id,
		"split_year": int(observation.get("split_year", -1)),
		"genome": genome,
		"genome_checksum": String(genome.get("checksum", "")),
		"recruitment_traits": recruitment_traits,
		"recruitment_traits_checksum": String(recruitment_traits.get("checksum", "")),
		"observed_patch_ids": _observed_patch_ids(Array(observation.get("geography_history", []))),
		"source_observation_hash": String(observation.get("observation_hash", "")),
		"canonical_species_declared": false,
	}
	entry["entry_hash"] = compute_entry_hash(entry)
	if not validate_entry(entry):
		return {}
	return entry


static func research_species_id(lineage_id: String) -> String:
	if not _valid_id(lineage_id):
		return ""
	var identity := "|".join(PackedStringArray([
		SCHEMA,
		VERSION,
		SPECIES_CONCEPT,
		lineage_id,
	])).sha256_text()
	return "eco-research-species/%s" % identity.substr(0, 24)


static func validate_catalog(catalog: Dictionary) -> bool:
	if not _has_exact_fields(catalog, CATALOG_FIELDS):
		return false
	if String(catalog.get("schema", "")) != SCHEMA or String(catalog.get("version", "")) != VERSION:
		return false
	if String(catalog.get("species_concept", "")) != SPECIES_CONCEPT:
		return false
	if String(catalog.get("parent_p2_7_accepted_aggregate", "")) != PARENT_P2_7_ACCEPTED_AGGREGATE:
		return false
	if not _valid_id(String(catalog.get("bake_id", ""))) or not _is_lower_hex_64(String(catalog.get("source_run_hash", ""))):
		return false
	if typeof(catalog.get("canonical_species_declared")) != TYPE_BOOL or bool(catalog.get("canonical_species_declared")):
		return false
	if typeof(catalog.get("entries")) != TYPE_ARRAY:
		return false
	var entries: Array = catalog.get("entries", [])
	if entries.is_empty():
		return false

	var seen_lineages := {}
	var seen_species := {}
	var previous_species_id := ""
	for index in range(entries.size()):
		if typeof(entries[index]) != TYPE_DICTIONARY:
			return false
		var entry: Dictionary = entries[index]
		if not validate_entry(entry):
			return false
		var lineage_id := String(entry["lineage_id"])
		var species_id := String(entry["research_species_id"])
		if seen_lineages.has(lineage_id) or seen_species.has(species_id):
			return false
		if index > 0 and species_id <= previous_species_id:
			return false
		seen_lineages[lineage_id] = true
		seen_species[species_id] = true
		previous_species_id = species_id

	var catalog_hash := String(catalog.get("catalog_hash", ""))
	return _is_lower_hex_64(catalog_hash) and catalog_hash == compute_catalog_hash(catalog)


static func validate_entry(entry: Dictionary) -> bool:
	if not _has_exact_fields(entry, ENTRY_FIELDS):
		return false
	if String(entry.get("schema", "")) != ENTRY_SCHEMA or String(entry.get("version", "")) != VERSION:
		return false
	var lineage_id := String(entry.get("lineage_id", ""))
	if not _valid_id(lineage_id):
		return false
	if String(entry.get("research_species_id", "")) != research_species_id(lineage_id):
		return false
	if typeof(entry.get("canonical_species_declared")) != TYPE_BOOL or bool(entry.get("canonical_species_declared")):
		return false
	if typeof(entry.get("split_year")) != TYPE_INT or int(entry.get("split_year")) < 0:
		return false
	if typeof(entry.get("ancestry_path")) != TYPE_ARRAY:
		return false
	var ancestry: Array = entry.get("ancestry_path", [])
	if not _valid_ancestry(ancestry, lineage_id):
		return false
	var expected_parent := ""
	if ancestry.size() > 1:
		expected_parent = String(ancestry[ancestry.size() - 2])
	if String(entry.get("parent_lineage_id", "")) != expected_parent:
		return false

	if typeof(entry.get("genome")) != TYPE_DICTIONARY or typeof(entry.get("recruitment_traits")) != TYPE_DICTIONARY:
		return false
	var genome: Dictionary = entry.get("genome", {})
	var recruitment_traits: Dictionary = entry.get("recruitment_traits", {})
	if not bool(PlantGenome.validate(genome).get("success", false)) or not RecruitmentTraits.validate(recruitment_traits):
		return false
	if String(entry.get("genome_checksum", "")) != String(genome.get("checksum", "")):
		return false
	if String(entry.get("recruitment_traits_checksum", "")) != String(recruitment_traits.get("checksum", "")):
		return false
	if typeof(entry.get("observed_patch_ids")) != TYPE_ARRAY:
		return false
	if not _is_canonical_string_set(Array(entry.get("observed_patch_ids", []))):
		return false
	if not _is_lower_hex_64(String(entry.get("source_observation_hash", ""))):
		return false
	var entry_hash := String(entry.get("entry_hash", ""))
	return _is_lower_hex_64(entry_hash) and entry_hash == compute_entry_hash(entry)


static func compute_entry_hash(entry: Dictionary) -> String:
	var tokens := PackedStringArray([
		ENTRY_SCHEMA,
		VERSION,
		String(entry.get("research_species_id", "")),
		String(entry.get("lineage_id", "")),
		String(entry.get("parent_lineage_id", "")),
		str(int(entry.get("split_year", -1))),
		String(entry.get("genome_checksum", "")),
		String(entry.get("recruitment_traits_checksum", "")),
		String(entry.get("source_observation_hash", "")),
		"canonical_species_declared=false",
	])
	for value in Array(entry.get("ancestry_path", [])):
		tokens.append("ancestor=" + String(value))
	for value in Array(entry.get("observed_patch_ids", [])):
		tokens.append("patch=" + String(value))
	return "\n".join(tokens).sha256_text()


static func compute_catalog_hash(catalog: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		SPECIES_CONCEPT,
		PARENT_P2_7_ACCEPTED_AGGREGATE,
		String(catalog.get("bake_id", "")),
		String(catalog.get("source_run_hash", "")),
		"canonical_species_declared=false",
	])
	for value in Array(catalog.get("entries", [])):
		if typeof(value) != TYPE_DICTIONARY:
			tokens.append("invalid-entry")
			continue
		tokens.append(String(Dictionary(value).get("entry_hash", "")))
	return "\n".join(tokens).sha256_text()


static func _observed_patch_ids(geography_history: Array) -> Array:
	var seen := {}
	for value in geography_history:
		if typeof(value) != TYPE_DICTIONARY:
			return []
		var entry: Dictionary = value
		for patch_value in Array(entry.get("patch_ids", [])):
			var patch_id := String(patch_value)
			if not _valid_id(patch_id):
				return []
			seen[patch_id] = true
	var result: Array = []
	for patch_id in seen.keys():
		result.append(String(patch_id))
	result.sort()
	return result


static func _valid_ancestry(ancestry: Array, lineage_id: String) -> bool:
	if ancestry.is_empty() or String(ancestry[ancestry.size() - 1]) != lineage_id:
		return false
	var seen := {}
	for value in ancestry:
		var ancestor := String(value)
		if not _valid_id(ancestor) or seen.has(ancestor):
			return false
		seen[ancestor] = true
	return true


static func _is_canonical_string_set(values: Array) -> bool:
	var canonical: Array = []
	var seen := {}
	for value in values:
		if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
			return false
		var text := String(value)
		if not _valid_id(text) or seen.has(text):
			return false
		seen[text] = true
		canonical.append(text)
	canonical.sort()
	if canonical.size() != values.size():
		return false
	for index in range(canonical.size()):
		if String(values[index]) != String(canonical[index]):
			return false
	return true


static func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.keys().size() != fields.size():
		return false
	for field_name in fields:
		if not value.has(field_name):
			return false
	for key in value.keys():
		if not String(key) in fields:
			return false
	return true


static func _valid_id(value: String) -> bool:
	return not value.is_empty() and value == value.strip_edges()


static func _is_lower_hex_64(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for character in value:
		if not String(character) in [
			"0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
			"a", "b", "c", "d", "e", "f",
		]:
			return false
	return true
