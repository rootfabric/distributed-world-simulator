extends RefCounted

## ECO.EVO7 LS2.1 — read-only evolutionary observatory.
## Consumes LS1 snapshots only. It never mutates populations, the world, rules,
## persistence, network state, or mutation authority.

const SCHEMA := "distributed_world_simulator.ecology.evo7_evolution_observatory.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-LS2.1.1"
const MAX_HISTORY := 4096
const SPATIAL_REVISION := "ECO.EVO7-LS3.6.1"
const TRAIT_FIELDS := [
	"fitness",
	"leaf_area_index_proxy",
	"realized_root_depth_m",
	"root_shoot_ratio",
	"realized_height_m",
]
const COMPONENT_FIELDS := [
	"water_limited_resource",
	"fitness_establishment_term",
	"fitness_water_match_term",
	"fitness_shade_term",
	"fitness_drought_cost",
]

var history: Array[Dictionary] = []
var fixation_generation: Array[int] = [-1, -1, -1]
var source_session_seed := 0
var initialized := false

# LS3.6 spatial extension of the existing observability stack.
var spatial_history: Array[Dictionary] = []
var spatial_initialized := false
var spatial_environment_hash := ""

func setup(initial_snapshot: Dictionary) -> bool:
	history.clear()
	fixation_generation = [-1, -1, -1]
	source_session_seed = int(initial_snapshot.get("session_seed", 0))
	initialized = false
	if not _valid_snapshot(initial_snapshot):
		return false
	initialized = true
	return record_snapshot(initial_snapshot)

func record_snapshot(snapshot: Dictionary) -> bool:
	if not initialized or not _valid_snapshot(snapshot):
		return false
	if int(snapshot.get("session_seed", -1)) != source_session_seed:
		return false
	var generation := int(snapshot.get("generation", -1))
	if not history.is_empty():
		var previous_generation := int(history[-1].get("generation", -1))
		if generation < previous_generation:
			return false
	var entry := _build_entry(snapshot)
	if entry.is_empty():
		return false
	if not history.is_empty() and int(history[-1].get("generation", -1)) == generation:
		history[-1] = entry
	else:
		history.append(entry)
		if history.size() > MAX_HISTORY:
			history.pop_front()
	return true

func get_latest() -> Dictionary:
	return {} if history.is_empty() else history[-1].duplicate(true)

func get_history() -> Array[Dictionary]:
	return history.duplicate(true)

func get_history_size() -> int:
	return history.size()

func get_zone_history(zone_index: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if zone_index < 0 or zone_index >= 3:
		return result
	for entry in history:
		var zones: Array = entry.get("zones", [])
		if zones.size() > zone_index:
			result.append(Dictionary(zones[zone_index]).duplicate(true))
	return result

func get_fixation_generation(zone_index: int) -> int:
	return fixation_generation[zone_index] if zone_index >= 0 and zone_index < fixation_generation.size() else -1

func _valid_snapshot(snapshot: Dictionary) -> bool:
	if snapshot.is_empty() or not bool(snapshot.get("shadow_only", false)):
		return false
	var zones: Array = snapshot.get("zones", [])
	if zones.size() != 3:
		return false
	for zone_value in zones:
		var zone: Dictionary = zone_value
		if Array(zone.get("members", [])).is_empty():
			return false
	return true

func _build_entry(snapshot: Dictionary) -> Dictionary:
	var generation := int(snapshot.get("generation", -1))
	var zones_out: Array[Dictionary] = []
	for zone_index in 3:
		var zone := _zone_entry(Dictionary(snapshot["zones"][zone_index]), generation, zone_index)
		if zone.is_empty():
			return {}
		zones_out.append(zone)
	var entry := {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"shadow_only": true,
		"session_seed": source_session_seed,
		"generation": generation,
		"source_state_hash": String(snapshot.get("state_hash", "")),
		"history_index": history.size(),
		"zones": zones_out,
	}
	entry["observatory_hash"] = _entry_hash(entry)
	return entry

func _zone_entry(zone: Dictionary, generation: int, zone_index: int) -> Dictionary:
	var members: Array = zone.get("members", [])
	if members.is_empty():
		return {}
	var counts := {}
	for member_value in members:
		var member: Dictionary = member_value
		var lineage := String(member.get("lineage_id", ""))
		counts[lineage] = int(counts.get(lineage, 0)) + 1
	var richness := counts.size()
	var entropy := 0.0
	for count_value in counts.values():
		var p := float(int(count_value)) / float(members.size())
		if p > 0.0:
			entropy -= p * log(p)
	var dominant_count := int(zone.get("dominant_lineage_count", 0))
	var fixed := richness == 1 or dominant_count == members.size()
	if fixed and fixation_generation[zone_index] < 0:
		fixation_generation[zone_index] = generation

	var trait_moments := {}
	for field in TRAIT_FIELDS:
		trait_moments[field] = _moments(members, String(field))
	var component_means := {}
	for field in COMPONENT_FIELDS:
		component_means[field] = _mean(members, String(field))
	component_means["realized_photosynthetic_gain"] = _mean(members, "realized_photosynthetic_gain")
	component_means["maintenance_cost_proxy"] = _mean(members, "maintenance_cost_proxy")

	var reconstructed := float(component_means["water_limited_resource"]) \
		+ float(component_means["fitness_establishment_term"]) \
		+ float(component_means["fitness_water_match_term"]) \
		+ float(component_means["fitness_shade_term"]) \
		- float(component_means["fitness_drought_cost"])
	var observed_fitness := float(Dictionary(trait_moments["fitness"])["mean"])
	return {
		"zone_index": zone_index,
		"label": String(zone.get("label", "ZONE")),
		"moisture": float(zone.get("moisture", 0.0)),
		"sunlight": float(zone.get("sunlight", 0.0)),
		"lineage_richness": richness,
		"shannon_entropy": snappedf(entropy, 1e-9),
		"dominant_lineage": String(zone.get("dominant_lineage", "")),
		"dominant_fraction": snappedf(float(dominant_count) / float(members.size()), 1e-9),
		"fixed": fixed,
		"fixation_generation": fixation_generation[zone_index],
		"trait_moments": trait_moments,
		"fitness_components_mean": component_means,
		"fitness_balance_error": snappedf(absf(observed_fitness - reconstructed), 1e-9),
		"population_hash": String(zone.get("population_hash", "")),
	}

func _moments(members: Array, field: String) -> Dictionary:
	var mean := _mean(members, field)
	var variance := 0.0
	for member_value in members:
		var value := float(Dictionary(member_value).get(field, 0.0))
		var d := value - mean
		variance += d * d
	variance /= float(members.size())
	return {"mean": snappedf(mean, 1e-9), "variance": snappedf(variance, 1e-9)}

func _mean(members: Array, field: String) -> float:
	var total := 0.0
	for member_value in members:
		total += float(Dictionary(member_value).get(field, 0.0))
	return total / float(members.size())

func _entry_hash(entry: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA, VERSION, REVISION,
		str(int(entry.get("session_seed", 0))),
		str(int(entry.get("generation", -1))),
		String(entry.get("source_state_hash", "")),
	])
	for zone_value in Array(entry.get("zones", [])):
		var zone: Dictionary = zone_value
		var moments: Dictionary = zone.get("trait_moments", {})
		tokens.append("%d|%d|%.9f|%.9f|%.9f|%d|%s" % [
			int(zone.get("zone_index", -1)), int(zone.get("lineage_richness", 0)),
			float(zone.get("shannon_entropy", 0.0)),
			float(Dictionary(moments.get("leaf_area_index_proxy", {})).get("variance", 0.0)),
			float(zone.get("fitness_balance_error", 0.0)),
			int(zone.get("fixation_generation", -1)), String(zone.get("population_hash", "")),
		])
	return "|".join(tokens).sha256_text()


## LS3.6 spatial observability extension. Legacy LS2.1 zone APIs above remain unchanged.
func setup_spatial(environment_field: Dictionary, ecology_snapshot: Dictionary) -> bool:
	spatial_history.clear()
	spatial_initialized = false
	spatial_environment_hash = String(environment_field.get("field_hash", ""))
	if spatial_environment_hash.length() != 64 or Array(environment_field.get("cells", [])).size() != 1024:
		return false
	if ecology_snapshot.is_empty() or not bool(ecology_snapshot.get("shadow_only", false)):
		return false
	spatial_initialized = true
	return record_spatial_snapshot(environment_field, ecology_snapshot, {})

func record_spatial_snapshot(environment_field: Dictionary, ecology_snapshot: Dictionary, classification: Dictionary = {}) -> bool:
	if not spatial_initialized:
		return false
	var current_environment_hash := String(environment_field.get("field_hash", ""))
	if current_environment_hash.length() != 64:
		return false
	if ecology_snapshot.is_empty() or not bool(ecology_snapshot.get("shadow_only", false)):
		return false
	if String(ecology_snapshot.get("environment_field_hash", "")) != current_environment_hash:
		return false
	if String(ecology_snapshot.get("state_hash", "")).length() != 64:
		return false
	if int(ecology_snapshot.get("generation", 0)) > 0 and String(ecology_snapshot.get("postcompetition_population_hash", "")).length() != 64:
		return false
	if not classification.is_empty():
		if String(classification.get("source_environment_field_hash", "")) != current_environment_hash:
			return false
		if String(classification.get("source_ecology_state_hash", "")) != String(ecology_snapshot.get("state_hash", "")):
			return false
		if String(classification.get("source_population_hash", "")) != String(ecology_snapshot.get("postcompetition_population_hash", "")):
			return false
		if int(classification.get("generation", -1)) != int(ecology_snapshot.get("generation", -2)):
			return false
	var generation := int(ecology_snapshot.get("generation", -1))
	if generation < 0:
		return false
	if not spatial_history.is_empty() and generation < int(spatial_history[-1].get("generation", -1)):
		return false
	var entry := _spatial_entry(environment_field, ecology_snapshot, classification)
	if entry.is_empty() or not validate_spatial_entry(entry):
		return false
	## LS4: the observatory follows the exact environment already bound into
	## the accepted ecology snapshot; it never invents or writes that field.
	spatial_environment_hash = current_environment_hash
	if not spatial_history.is_empty() and generation == int(spatial_history[-1].get("generation", -2)):
		spatial_history[-1] = entry
	else:
		spatial_history.append(entry)
		if spatial_history.size() > MAX_HISTORY:
			spatial_history.pop_front()
	return true

func get_spatial_latest() -> Dictionary:
	return {} if spatial_history.is_empty() else spatial_history[-1].duplicate(true)

func get_spatial_history() -> Array[Dictionary]:
	return spatial_history.duplicate(true)

func _spatial_entry(environment_field: Dictionary, ecology_snapshot: Dictionary, classification: Dictionary) -> Dictionary:
	var records: Array = ecology_snapshot.get("records", [])
	var occupied := {}
	var lineage_counts := {}
	for value in records:
		if not value is Dictionary:
			return {}
		var record: Dictionary = value
		occupied[int(record.get("cell_index", -1))] = true
		var bundle_value = record.get("hereditary_bundle")
		if bundle_value is Dictionary:
			var lineage_value = Dictionary(bundle_value).get("lineage_record")
			if lineage_value is Dictionary:
				var lineage_id := String(Dictionary(lineage_value).get("lineage_id", ""))
				if not lineage_id.is_empty():
					lineage_counts[lineage_id] = int(lineage_counts.get(lineage_id, 0)) + 1
	var entropy := 0.0
	var dominant := 0
	for count_value in lineage_counts.values():
		var count := int(count_value)
		dominant = maxi(dominant, count)
		if records.size() > 0:
			var probability := float(count) / float(records.size())
			if probability > 0.0:
				entropy -= probability * log(probability)

	var evaluations: Array = Dictionary(ecology_snapshot.get("competition_field", {})).get("evaluations", [])
	var survivor_ids := {}
	for value in records:
		survivor_ids[String(Dictionary(value).get("record_id", ""))] = true
	var survivor_evaluations: Array[Dictionary] = []
	for value in evaluations:
		if value is Dictionary and survivor_ids.has(String(Dictionary(value).get("record_id", ""))):
			survivor_evaluations.append(Dictionary(value))
	var trait_moments := {}
	for field in ["leaf_area_index_proxy", "realized_root_depth_m", "root_shoot_ratio", "realized_height_m", "water_satisfaction", "realized_resource_balance"]:
		trait_moments[field] = _spatial_moments(survivor_evaluations, field)

	var class_counts := {}
	var mean_cover := 0.0; var mean_continuity := 0.0; var mean_fragmentation := 0.0
	if not classification.is_empty():
		var summary: Dictionary = classification.get("summary", {})
		class_counts = Dictionary(summary.get("class_counts", {})).duplicate(true)
		mean_cover = float(summary.get("mean_cover_proxy", 0.0))
		mean_continuity = float(summary.get("mean_continuity", 0.0))
		mean_fragmentation = float(summary.get("mean_fragmentation", 0.0))

	var source_population_hash := String(ecology_snapshot.get("postcompetition_population_hash", ""))
	if source_population_hash.is_empty():
		source_population_hash = _spatial_record_set_hash(records)
	var entry := {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"spatial_revision": SPATIAL_REVISION,
		"shadow_only": true,
		"spatial": true,
		"generation": int(ecology_snapshot.get("generation", 0)),
		"source_environment_hash": String(environment_field.get("field_hash", "")),
		"source_ecology_state_hash": String(ecology_snapshot.get("state_hash", "")),
		"source_population_hash": source_population_hash,
		"source_classification_hash": String(classification.get("classification_hash", "")),
		"population_count": records.size(),
		"occupied_cells": occupied.size(),
		"occupancy_fraction": snappedf(float(occupied.size()) / 1024.0, 1e-9),
		"lineage_richness": lineage_counts.size(),
		"shannon_entropy": snappedf(entropy, 1e-9),
		"dominant_fraction": snappedf(float(dominant) / float(maxi(records.size(), 1)), 1e-9),
		"trait_moments": trait_moments,
		"class_counts": class_counts,
		"mean_cover_proxy": snappedf(mean_cover, 1e-9),
		"mean_continuity": snappedf(mean_continuity, 1e-9),
		"mean_fragmentation": snappedf(mean_fragmentation, 1e-9),
	}
	entry["observatory_hash"] = _spatial_entry_hash(entry)
	return entry

func _spatial_moments(values: Array[Dictionary], field: String) -> Dictionary:
	if values.is_empty():
		return {"mean": 0.0, "variance": 0.0}
	var total := 0.0
	for value in values:
		total += float(value.get(field, 0.0))
	var mean := total / float(values.size())
	var variance := 0.0
	for value in values:
		var delta := float(value.get(field, 0.0)) - mean
		variance += delta * delta
	variance /= float(values.size())
	return {"mean": snappedf(mean, 1e-9), "variance": snappedf(variance, 1e-9)}

func _spatial_record_set_hash(records: Array) -> String:
	var tokens: Array[String] = []
	for value in records:
		if not value is Dictionary:
			return ""
		var record: Dictionary = value
		var record_hash := String(record.get("record_hash", ""))
		if record_hash.is_empty():
			record_hash = "%s|%s|%d|%d" % [String(record.get("record_id", "")), String(record.get("bundle_checksum", "")), int(record.get("cell_index", -1)), int(record.get("slot_index", -1))]
		tokens.append(record_hash)
	tokens.sort()
	return "|".join(PackedStringArray(tokens)).sha256_text()

func validate_spatial_entry(entry: Dictionary) -> bool:
	if String(entry.get("schema", "")) != SCHEMA or String(entry.get("version", "")) != VERSION or String(entry.get("revision", "")) != REVISION or String(entry.get("spatial_revision", "")) != SPATIAL_REVISION:
		return false
	if not bool(entry.get("shadow_only", false)) or not bool(entry.get("spatial", false)):
		return false
	if int(entry.get("generation", -1)) < 0 or int(entry.get("population_count", -1)) < 0:
		return false
	var occupied := int(entry.get("occupied_cells", -1))
	if occupied < 0 or occupied > 1024:
		return false
	var occupancy := float(entry.get("occupancy_fraction", -1.0))
	if occupancy < 0.0 or occupancy > 1.0 or absf(occupancy - snappedf(float(occupied) / 1024.0, 1e-9)) > 1e-9:
		return false
	if int(entry.get("lineage_richness", -1)) < 0 or float(entry.get("shannon_entropy", -1.0)) < 0.0:
		return false
	if float(entry.get("dominant_fraction", -1.0)) < 0.0 or float(entry.get("dominant_fraction", 2.0)) > 1.0:
		return false
	for key in ["mean_cover_proxy", "mean_continuity", "mean_fragmentation"]:
		var value := float(entry.get(key, -1.0))
		if not is_finite(value) or value < 0.0 or value > 1.0:
			return false
	var moments_value = entry.get("trait_moments")
	if not moments_value is Dictionary:
		return false
	for field in ["leaf_area_index_proxy", "realized_root_depth_m", "root_shoot_ratio", "realized_height_m", "water_satisfaction", "realized_resource_balance"]:
		var moment_value = Dictionary(moments_value).get(field)
		if not moment_value is Dictionary:
			return false
		for component in ["mean", "variance"]:
			var number := float(Dictionary(moment_value).get(component, NAN))
			if not is_finite(number) or (component == "variance" and number < 0.0):
				return false
	return String(entry.get("observatory_hash", "")) == _spatial_entry_hash(entry)

func _spatial_entry_hash(entry: Dictionary) -> String:
	var moments: Dictionary = entry.get("trait_moments", {})
	var tokens := PackedStringArray([
		SCHEMA, VERSION, REVISION, SPATIAL_REVISION, "spatial",
		str(int(entry.get("generation", 0))),
		String(entry.get("source_environment_hash", "")),
		String(entry.get("source_ecology_state_hash", "")),
		String(entry.get("source_population_hash", "")),
		String(entry.get("source_classification_hash", "")),
		str(int(entry.get("population_count", 0))), str(int(entry.get("occupied_cells", 0))),
		"%.9f" % float(entry.get("occupancy_fraction", 0.0)),
		str(int(entry.get("lineage_richness", 0))), "%.9f" % float(entry.get("shannon_entropy", 0.0)),
		"%.9f" % float(entry.get("dominant_fraction", 0.0)),
		"%.9f" % float(entry.get("mean_cover_proxy", 0.0)),
		"%.9f" % float(entry.get("mean_continuity", 0.0)),
		"%.9f" % float(entry.get("mean_fragmentation", 0.0)),
	])
	for field in ["leaf_area_index_proxy", "realized_root_depth_m", "root_shoot_ratio", "realized_height_m", "water_satisfaction", "realized_resource_balance"]:
		var moment: Dictionary = moments.get(field, {})
		tokens.append("%s|%.9f|%.9f" % [field, float(moment.get("mean", 0.0)), float(moment.get("variance", 0.0))])
	var class_counts: Dictionary = entry.get("class_counts", {})
	var labels := class_counts.keys(); labels.sort()
	for label in labels:
		tokens.append("class|%s|%d" % [String(label), int(class_counts[label])])
	return "|".join(tokens).sha256_text()
