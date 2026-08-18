extends RefCounted

const SpeciesCatalog = preload("res://scripts/research/ecology/plant_species_catalog_v1.gd")

const SOURCE_SCHEMA := "distributed_world_simulator.ecology.evo2_evolution_bake_source.v1"
const SCHEMA := "distributed_world_simulator.ecology.evo2_evolution_bake_export.v1"
const VERSION := "1.0.0"
const POLICY_REVISION := "ECO.EVO2-E2.2.1"
const PARENT_E2_1_ACCEPTED_AGGREGATE := "aa23bc269738ace132fb1386ec01b339cc7fd82e1238223c1075b60dac5896ad"
const PARENT_P2_8_ACCEPTED_AGGREGATE := "ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6"

# Research bake-retention policy only. These thresholds decide whether a lineage
# hypothesis is portable enough for the next research experiment. They are not
# a biological species definition and do not promote canonical taxonomy.
const WINDOW_YEARS := 8
const MIN_OCCUPIED_YEARS_IN_WINDOW := 6
const MIN_LINEAGE_AGE_YEARS := 8
const MAX_REPRESENTATIVE_STALENESS_YEARS := 2

const SOURCE_FIELDS: Array[String] = [
	"schema",
	"version",
	"parent_p2_8_accepted_aggregate",
	"source_run_hash",
	"final_year",
	"lineages",
	"source_hash",
]
const LINEAGE_INPUT_FIELDS: Array[String] = ["lineage_id", "observations", "occupancy_history"]
const LINEAGE_FIELDS: Array[String] = ["lineage_id", "observations", "occupancy_history", "lineage_hash"]
const OCCUPANCY_FIELDS: Array[String] = ["year", "occupied_patch_count"]
const RESULT_FIELDS: Array[String] = [
	"schema",
	"version",
	"policy_revision",
	"parent_e2_1_accepted_aggregate",
	"parent_p2_8_accepted_aggregate",
	"source_hash",
	"source_run_hash",
	"final_year",
	"bake_id",
	"selected_lineages",
	"rejected_lineages",
	"species_catalog",
	"catalog_hash",
	"bake_hash",
]
const SELECTED_FIELDS: Array[String] = [
	"lineage_id",
	"representative_observation_hash",
	"representative_year",
	"occupied_years_in_window",
	"final_occupied_patch_count",
	"research_species_id",
	"selection_hash",
]
const REJECTED_FIELDS: Array[String] = [
	"lineage_id",
	"reason",
	"representative_observation_hash",
	"representative_year",
	"occupied_years_in_window",
	"final_occupied_patch_count",
	"rejection_hash",
]


static func create_source(lineage_histories: Array, final_year: int, source_run_hash: String) -> Dictionary:
	if final_year < WINDOW_YEARS - 1 or not _is_lower_hex_64(source_run_hash) or lineage_histories.is_empty():
		return {}
	var canonical_lineages: Array = []
	var seen := {}
	for value in lineage_histories:
		if typeof(value) != TYPE_DICTIONARY:
			return {}
		var input_record: Dictionary = value
		if not _has_exact_fields(input_record, LINEAGE_INPUT_FIELDS):
			return {}
		var record := _canonical_lineage_record(input_record, final_year)
		if record.is_empty():
			return {}
		var lineage_id := String(record["lineage_id"])
		if seen.has(lineage_id):
			return {}
		seen[lineage_id] = true
		canonical_lineages.append(record)
	canonical_lineages.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["lineage_id"]) < String(b["lineage_id"])
	)
	var source := {
		"schema": SOURCE_SCHEMA,
		"version": VERSION,
		"parent_p2_8_accepted_aggregate": PARENT_P2_8_ACCEPTED_AGGREGATE,
		"source_run_hash": source_run_hash,
		"final_year": final_year,
		"lineages": canonical_lineages,
	}
	source["source_hash"] = compute_source_hash(source)
	return source if validate_source(source) else {}


static func validate_source(source: Dictionary) -> bool:
	if not _has_exact_fields(source, SOURCE_FIELDS):
		return false
	if String(source.get("schema", "")) != SOURCE_SCHEMA or String(source.get("version", "")) != VERSION:
		return false
	if String(source.get("parent_p2_8_accepted_aggregate", "")) != PARENT_P2_8_ACCEPTED_AGGREGATE:
		return false
	if not _is_lower_hex_64(String(source.get("source_run_hash", ""))):
		return false
	if typeof(source.get("final_year")) != TYPE_INT:
		return false
	var final_year := int(source.get("final_year", -1))
	if final_year < WINDOW_YEARS - 1:
		return false
	if typeof(source.get("lineages")) != TYPE_ARRAY:
		return false
	var lineages: Array = source.get("lineages", [])
	if lineages.is_empty():
		return false
	var previous_id := ""
	var seen := {}
	for index in range(lineages.size()):
		if typeof(lineages[index]) != TYPE_DICTIONARY:
			return false
		var record: Dictionary = lineages[index]
		if not _has_exact_fields(record, LINEAGE_FIELDS):
			return false
		var canonical := _canonical_lineage_record({
			"lineage_id": record.get("lineage_id", ""),
			"observations": record.get("observations", []),
			"occupancy_history": record.get("occupancy_history", []),
		}, final_year)
		if canonical.is_empty() or canonical != record:
			return false
		var lineage_id := String(record["lineage_id"])
		if seen.has(lineage_id):
			return false
		if index > 0 and lineage_id <= previous_id:
			return false
		seen[lineage_id] = true
		previous_id = lineage_id
	var source_hash := String(source.get("source_hash", ""))
	return _is_lower_hex_64(source_hash) and source_hash == compute_source_hash(source)


static func export_catalog(source: Dictionary) -> Dictionary:
	if not validate_source(source):
		return {}
	var final_year := int(source["final_year"])
	var selected: Array = []
	var rejected: Array = []
	var selected_observations: Array = []
	for value in Array(source["lineages"]):
		var record: Dictionary = value
		var representative := _representative_observation(record)
		if representative.is_empty():
			return {}
		var observation: Dictionary = representative["observation"]
		var representative_year := int(representative["year"])
		var split_year := int(observation["split_year"])
		var occupied_years := _occupied_years_in_window(Array(record["occupancy_history"]), final_year)
		if occupied_years < 0:
			return {}
		var final_count := _occupied_patch_count(Array(record["occupancy_history"]), final_year)
		if final_count < 0:
			return {}
		var reason := _rejection_reason(split_year, representative_year, final_year, occupied_years, final_count)
		if reason.is_empty():
			var selected_record := {
				"lineage_id": String(record["lineage_id"]),
				"representative_observation_hash": String(observation["observation_hash"]),
				"representative_year": representative_year,
				"occupied_years_in_window": occupied_years,
				"final_occupied_patch_count": final_count,
				"research_species_id": SpeciesCatalog.research_species_id(String(record["lineage_id"])),
			}
			selected_record["selection_hash"] = _selection_hash(selected_record)
			selected.append(selected_record)
			selected_observations.append(observation.duplicate(true))
		else:
			var rejected_record := {
				"lineage_id": String(record["lineage_id"]),
				"reason": reason,
				"representative_observation_hash": String(observation["observation_hash"]),
				"representative_year": representative_year,
				"occupied_years_in_window": occupied_years,
				"final_occupied_patch_count": final_count,
			}
			rejected_record["rejection_hash"] = _rejection_hash(rejected_record)
			rejected.append(rejected_record)
	if selected.is_empty():
		return {}
	selected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["lineage_id"]) < String(b["lineage_id"])
	)
	rejected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["lineage_id"]) < String(b["lineage_id"])
	)
	selected_observations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["lineage_id"]) < String(b["lineage_id"])
	)
	var bake_id := _bake_id(source)
	var catalog := SpeciesCatalog.build(selected_observations, bake_id, String(source["source_run_hash"]))
	if catalog.is_empty() or not SpeciesCatalog.validate_catalog(catalog):
		return {}
	if Array(catalog["entries"]).size() != selected.size():
		return {}
	var catalog_by_lineage := {}
	for value in Array(catalog["entries"]):
		var entry: Dictionary = value
		catalog_by_lineage[String(entry["lineage_id"])] = entry
	for selection_value in selected:
		var selection: Dictionary = selection_value
		var lineage_id := String(selection["lineage_id"])
		if not catalog_by_lineage.has(lineage_id):
			return {}
		if String(Dictionary(catalog_by_lineage[lineage_id])["research_species_id"]) != String(selection["research_species_id"]):
			return {}
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"policy_revision": POLICY_REVISION,
		"parent_e2_1_accepted_aggregate": PARENT_E2_1_ACCEPTED_AGGREGATE,
		"parent_p2_8_accepted_aggregate": PARENT_P2_8_ACCEPTED_AGGREGATE,
		"source_hash": String(source["source_hash"]),
		"source_run_hash": String(source["source_run_hash"]),
		"final_year": final_year,
		"bake_id": bake_id,
		"selected_lineages": selected,
		"rejected_lineages": rejected,
		"species_catalog": catalog,
		"catalog_hash": String(catalog["catalog_hash"]),
	}
	result["bake_hash"] = compute_bake_hash(result)
	return result if validate_export(result) else {}


static func validate_export(result: Dictionary) -> bool:
	if not _has_exact_fields(result, RESULT_FIELDS):
		return false
	if String(result.get("schema", "")) != SCHEMA or String(result.get("version", "")) != VERSION:
		return false
	if String(result.get("policy_revision", "")) != POLICY_REVISION:
		return false
	if String(result.get("parent_e2_1_accepted_aggregate", "")) != PARENT_E2_1_ACCEPTED_AGGREGATE:
		return false
	if String(result.get("parent_p2_8_accepted_aggregate", "")) != PARENT_P2_8_ACCEPTED_AGGREGATE:
		return false
	for hash_field in ["source_hash", "source_run_hash", "catalog_hash", "bake_hash"]:
		if not _is_lower_hex_64(String(result.get(hash_field, ""))):
			return false
	if typeof(result.get("final_year")) != TYPE_INT or int(result.get("final_year", -1)) < WINDOW_YEARS - 1:
		return false
	if String(result.get("bake_id", "")) != _bake_id_from_hashes(String(result["source_hash"]), String(result["source_run_hash"])):
		return false
	if typeof(result.get("selected_lineages")) != TYPE_ARRAY or typeof(result.get("rejected_lineages")) != TYPE_ARRAY:
		return false
	var selected: Array = result["selected_lineages"]
	var rejected: Array = result["rejected_lineages"]
	if selected.is_empty():
		return false
	if not _validate_selected(selected) or not _validate_rejected(rejected):
		return false
	var seen := {}
	for value in selected:
		seen[String(Dictionary(value)["lineage_id"])] = true
	for value in rejected:
		if seen.has(String(Dictionary(value)["lineage_id"])):
			return false
	var catalog: Dictionary = result.get("species_catalog", {})
	if not SpeciesCatalog.validate_catalog(catalog):
		return false
	if String(catalog.get("catalog_hash", "")) != String(result.get("catalog_hash", "")):
		return false
	if String(catalog.get("source_run_hash", "")) != String(result.get("source_run_hash", "")):
		return false
	if String(catalog.get("bake_id", "")) != String(result.get("bake_id", "")):
		return false
	if Array(catalog.get("entries", [])).size() != selected.size():
		return false
	var catalog_ids := {}
	for entry_value in Array(catalog["entries"]):
		var entry: Dictionary = entry_value
		catalog_ids[String(entry["lineage_id"])] = String(entry["research_species_id"])
	for selected_value in selected:
		var selection: Dictionary = selected_value
		var lineage_id := String(selection["lineage_id"])
		if not catalog_ids.has(lineage_id) or String(catalog_ids[lineage_id]) != String(selection["research_species_id"]):
			return false
	return String(result.get("bake_hash", "")) == compute_bake_hash(result)


static func compute_source_hash(source: Dictionary) -> String:
	var tokens := PackedStringArray([
		SOURCE_SCHEMA,
		VERSION,
		PARENT_P2_8_ACCEPTED_AGGREGATE,
		String(source.get("source_run_hash", "")),
		str(int(source.get("final_year", -1))),
	])
	for value in Array(source.get("lineages", [])):
		if typeof(value) != TYPE_DICTIONARY:
			tokens.append("invalid-lineage")
			continue
		tokens.append(String(Dictionary(value).get("lineage_hash", "")))
	return "\n".join(tokens).sha256_text()


static func compute_bake_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		POLICY_REVISION,
		PARENT_E2_1_ACCEPTED_AGGREGATE,
		PARENT_P2_8_ACCEPTED_AGGREGATE,
		String(result.get("source_hash", "")),
		String(result.get("source_run_hash", "")),
		str(int(result.get("final_year", -1))),
		String(result.get("bake_id", "")),
		String(result.get("catalog_hash", "")),
	])
	for value in Array(result.get("selected_lineages", [])):
		tokens.append("selected=" + String(Dictionary(value).get("selection_hash", "")))
	for value in Array(result.get("rejected_lineages", [])):
		tokens.append("rejected=" + String(Dictionary(value).get("rejection_hash", "")))
	return "\n".join(tokens).sha256_text()


static func _canonical_lineage_record(input_record: Dictionary, final_year: int) -> Dictionary:
	var lineage_id := String(input_record.get("lineage_id", ""))
	if not _valid_id(lineage_id):
		return {}
	if typeof(input_record.get("observations")) != TYPE_ARRAY or typeof(input_record.get("occupancy_history")) != TYPE_ARRAY:
		return {}
	var observations: Array = []
	var seen_observation_hashes := {}
	var observation_year_hash := {}
	for value in Array(input_record["observations"]):
		if typeof(value) != TYPE_DICTIONARY:
			return {}
		var observation: Dictionary = value
		var entry := SpeciesCatalog.create_entry(observation)
		if entry.is_empty() or String(entry.get("lineage_id", "")) != lineage_id:
			return {}
		var year := _observation_end_year(observation)
		if year < 0 or year > final_year:
			return {}
		var observation_hash := String(observation.get("observation_hash", ""))
		if seen_observation_hashes.has(observation_hash):
			return {}
		if observation_year_hash.has(year) and String(observation_year_hash[year]) != observation_hash:
			return {}
		seen_observation_hashes[observation_hash] = true
		observation_year_hash[year] = observation_hash
		observations.append(observation.duplicate(true))
	if observations.is_empty():
		return {}
	observations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ay := _observation_end_year(a)
		var by := _observation_end_year(b)
		if ay != by:
			return ay < by
		return String(a["observation_hash"]) < String(b["observation_hash"])
	)
	var occupancy: Array = []
	var seen_years := {}
	for value in Array(input_record["occupancy_history"]):
		if typeof(value) != TYPE_DICTIONARY:
			return {}
		var item: Dictionary = value
		if not _has_exact_fields(item, OCCUPANCY_FIELDS):
			return {}
		if typeof(item.get("year")) != TYPE_INT or typeof(item.get("occupied_patch_count")) != TYPE_INT:
			return {}
		var year := int(item["year"])
		var count := int(item["occupied_patch_count"])
		if year < 0 or year > final_year or count < 0 or seen_years.has(year):
			return {}
		seen_years[year] = true
		occupancy.append({"year": year, "occupied_patch_count": count})
	occupancy.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["year"]) < int(b["year"])
	)
	if not _has_complete_window(occupancy, final_year):
		return {}
	var record := {
		"lineage_id": lineage_id,
		"observations": observations,
		"occupancy_history": occupancy,
	}
	record["lineage_hash"] = _lineage_hash(record)
	return record


static func _representative_observation(record: Dictionary) -> Dictionary:
	var observations: Array = record.get("observations", [])
	if observations.is_empty():
		return {}
	var value: Variant = observations[observations.size() - 1]
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var observation: Dictionary = value
	var year := _observation_end_year(observation)
	return {} if year < 0 else {"year": year, "observation": observation.duplicate(true)}


static func _observation_end_year(observation: Dictionary) -> int:
	if typeof(observation.get("geography_history")) != TYPE_ARRAY or typeof(observation.get("ecology_history")) != TYPE_ARRAY:
		return -1
	var geography: Array = observation.get("geography_history", [])
	var ecology: Array = observation.get("ecology_history", [])
	if geography.is_empty() or ecology.is_empty():
		return -1
	var geography_last: Variant = geography[geography.size() - 1]
	var ecology_last: Variant = ecology[ecology.size() - 1]
	if typeof(geography_last) != TYPE_DICTIONARY or typeof(ecology_last) != TYPE_DICTIONARY:
		return -1
	if typeof(Dictionary(geography_last).get("year")) != TYPE_INT or typeof(Dictionary(ecology_last).get("year")) != TYPE_INT:
		return -1
	var geo_year := int(Dictionary(geography_last)["year"])
	var eco_year := int(Dictionary(ecology_last)["year"])
	return geo_year if geo_year == eco_year else -1


static func _rejection_reason(split_year: int, representative_year: int, final_year: int, occupied_years: int, final_count: int) -> String:
	if final_year - split_year < MIN_LINEAGE_AGE_YEARS:
		return "RECENT_LINEAGE"
	if final_count <= 0:
		return "EXTINCT_AT_FINAL"
	if occupied_years < MIN_OCCUPIED_YEARS_IN_WINDOW:
		return "TRANSIENT_PERSISTENCE"
	if final_year - representative_year > MAX_REPRESENTATIVE_STALENESS_YEARS:
		return "STALE_REPRESENTATIVE"
	return ""


static func _occupied_years_in_window(history: Array, final_year: int) -> int:
	var start_year := final_year - WINDOW_YEARS + 1
	var count := 0
	for year in range(start_year, final_year + 1):
		var value := _occupied_patch_count(history, year)
		if value < 0:
			return -1
		if value > 0:
			count += 1
	return count


static func _occupied_patch_count(history: Array, target_year: int) -> int:
	for value in history:
		if typeof(value) != TYPE_DICTIONARY:
			return -1
		var item: Dictionary = value
		if int(item.get("year", -1)) == target_year:
			return int(item.get("occupied_patch_count", -1))
	return -1


static func _has_complete_window(history: Array, final_year: int) -> bool:
	var start_year := final_year - WINDOW_YEARS + 1
	for year in range(start_year, final_year + 1):
		if _occupied_patch_count(history, year) < 0:
			return false
	return true


static func _lineage_hash(record: Dictionary) -> String:
	var tokens := PackedStringArray([String(record.get("lineage_id", ""))])
	for value in Array(record.get("observations", [])):
		var observation: Dictionary = value
		tokens.append("observation|%d|%s" % [_observation_end_year(observation), String(observation.get("observation_hash", ""))])
	for value in Array(record.get("occupancy_history", [])):
		var item: Dictionary = value
		tokens.append("occupancy|%d|%d" % [int(item.get("year", -1)), int(item.get("occupied_patch_count", -1))])
	return "\n".join(tokens).sha256_text()


static func _selection_hash(selection: Dictionary) -> String:
	return "\n".join(PackedStringArray([
		String(selection.get("lineage_id", "")),
		String(selection.get("representative_observation_hash", "")),
		str(int(selection.get("representative_year", -1))),
		str(int(selection.get("occupied_years_in_window", -1))),
		str(int(selection.get("final_occupied_patch_count", -1))),
		String(selection.get("research_species_id", "")),
	])).sha256_text()


static func _rejection_hash(rejection: Dictionary) -> String:
	return "\n".join(PackedStringArray([
		String(rejection.get("lineage_id", "")),
		String(rejection.get("reason", "")),
		String(rejection.get("representative_observation_hash", "")),
		str(int(rejection.get("representative_year", -1))),
		str(int(rejection.get("occupied_years_in_window", -1))),
		str(int(rejection.get("final_occupied_patch_count", -1))),
	])).sha256_text()


static func _validate_selected(values: Array) -> bool:
	var previous_id := ""
	for index in range(values.size()):
		if typeof(values[index]) != TYPE_DICTIONARY:
			return false
		var value: Dictionary = values[index]
		if not _has_exact_fields(value, SELECTED_FIELDS):
			return false
		var lineage_id := String(value.get("lineage_id", ""))
		if not _valid_id(lineage_id) or (index > 0 and lineage_id <= previous_id):
			return false
		if String(value.get("research_species_id", "")) != SpeciesCatalog.research_species_id(lineage_id):
			return false
		if not _is_lower_hex_64(String(value.get("representative_observation_hash", ""))):
			return false
		if typeof(value.get("representative_year")) != TYPE_INT or typeof(value.get("occupied_years_in_window")) != TYPE_INT or typeof(value.get("final_occupied_patch_count")) != TYPE_INT:
			return false
		if int(value["occupied_years_in_window"]) < MIN_OCCUPIED_YEARS_IN_WINDOW or int(value["occupied_years_in_window"]) > WINDOW_YEARS:
			return false
		if int(value["final_occupied_patch_count"]) <= 0:
			return false
		if String(value.get("selection_hash", "")) != _selection_hash(value):
			return false
		previous_id = lineage_id
	return true


static func _validate_rejected(values: Array) -> bool:
	var previous_id := ""
	var allowed_reasons := ["RECENT_LINEAGE", "EXTINCT_AT_FINAL", "TRANSIENT_PERSISTENCE", "STALE_REPRESENTATIVE"]
	for index in range(values.size()):
		if typeof(values[index]) != TYPE_DICTIONARY:
			return false
		var value: Dictionary = values[index]
		if not _has_exact_fields(value, REJECTED_FIELDS):
			return false
		var lineage_id := String(value.get("lineage_id", ""))
		if not _valid_id(lineage_id) or (index > 0 and lineage_id <= previous_id):
			return false
		if not String(value.get("reason", "")) in allowed_reasons:
			return false
		if not _is_lower_hex_64(String(value.get("representative_observation_hash", ""))):
			return false
		if typeof(value.get("representative_year")) != TYPE_INT or typeof(value.get("occupied_years_in_window")) != TYPE_INT or typeof(value.get("final_occupied_patch_count")) != TYPE_INT:
			return false
		if int(value["occupied_years_in_window"]) < 0 or int(value["occupied_years_in_window"]) > WINDOW_YEARS or int(value["final_occupied_patch_count"]) < 0:
			return false
		if String(value.get("rejection_hash", "")) != _rejection_hash(value):
			return false
		previous_id = lineage_id
	return true


static func _bake_id(source: Dictionary) -> String:
	return _bake_id_from_hashes(String(source.get("source_hash", "")), String(source.get("source_run_hash", "")))


static func _bake_id_from_hashes(source_hash: String, source_run_hash: String) -> String:
	if not _is_lower_hex_64(source_hash) or not _is_lower_hex_64(source_run_hash):
		return ""
	var identity := "\n".join(PackedStringArray([
		SCHEMA,
		VERSION,
		POLICY_REVISION,
		PARENT_E2_1_ACCEPTED_AGGREGATE,
		PARENT_P2_8_ACCEPTED_AGGREGATE,
		source_hash,
		source_run_hash,
	])).sha256_text()
	return "eco-evo2-bake/%s" % identity.substr(0, 24)


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
