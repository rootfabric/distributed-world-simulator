extends RefCounted

## ECO.EVO7 LS2.1 — read-only evolutionary observatory.
## Consumes LS1 snapshots only. It never mutates populations, the world, rules,
## persistence, network state, or mutation authority.

const SCHEMA := "distributed_world_simulator.ecology.evo7_evolution_observatory.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-LS2.1.1"
const MAX_HISTORY := 4096
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
