extends RefCounted

## ECO.EVO7 FFF5 - soil organic field aggregator (spec sections 10, 13, 19 FFF5).
## Slow litter / soil-legacy feedback: leaf turnover published as litter_input
## becomes a cell-bucketed organic matter proxy; organic matter decays per
## texture (clay protects it, sand burns it) and feeds back on the water field
## through the retention multiplier and on selection through the establishment
## bonus. "The plant changes the plot; on the changed plot the next generation
## grows differently" - ecological memory without microbes/entities (spec 10:
## no biotic legacy simulation in R1).
##
## MODEL (R1):
##   - plants publish records with litter_flux_ppm (PlantFunctionalPhenotype,
##     FFF1: LAI * (0.3 + 0.7*economics) * 45000 ppm);
##   - update in canonical identity order:
##       cell_organic += litter_share_i          (litter_ppm / LITTER_PPM_PER_ORGANIC)
##       then, after all deposits:
##       cell_organic *= (1 - decay_rate * texture_decay_mult)
##       clamp to [0, ORGANIC_CAPACITY]
##     texture decay multipliers: sand 1.3 / loam 1.0 / clay 0.75 - organic
##     accumulates most in clay, vanishes fastest in sand;
##   - initial_organic (optional map) carries the previous state across updates
##     so a bridge can accumulate a multi-generation legacy deterministically;
##     the texture map must cover occupied AND carried-over cells.
##
## RETENTION COUPLING (consumed by soil_water_field_v1 as an OPTIONAL input):
##   retention_multiplier(organic) = 1 + RETENTION_PER_ORGANIC * clamp01(organic)
##   RETENTION_PER_ORGANIC = 0.35: fully organic soil loses up to ~26% less
##   water to bare-soil evaporation (evaporation scales by 1/multiplier).
##   Calibration note: 0.35 keeps the moisture effect visible but sub-dominant
##   versus uptake in the mesic scenario; the strong Experiment D signal is the
##   documented establishment bonus (see evo7_litter_feedback_bridge_v1).
##   The nutrient-availability branch of spec section 10 is DEFERRED (no
##   nutrients field yet); in R1 organic affects moisture retention and
##   establishment only.
##
## Deterministic: no RNG, no SceneTree, canonical identity order for every float
## sum, snapped floats, fail-closed on invalid input (empty result), order-
## invariant hashes (G12 discipline).

const SCHEMA := "distributed_world_simulator.ecology.soil_organic_field.v1"
const VERSION := "1.0.0"
const CELL_SIZE_M := 1.0

const Effect = preload("res://scripts/research/ecology/plant_environment_effect_v1.gd")

## Organic matter saturates at 1.0 (per-cell proxy in [0,1]).
const ORGANIC_CAPACITY := 1.0

## Evaporation-retention coupling constant: evaporation multiplier of the water
## field becomes 1 / (1 + 0.35 * organic). Documented R1 calibration.
const RETENTION_PER_ORGANIC := 0.35

## Litter ppm -> organic proxy conversion. One average ancestor plant (~20k ppm
## litter alone in a cell) adds ~0.008 organic per update; a full community
## generation on the 5x5 microcosm moves shared cells by O(0.03-0.05).
const LITTER_PPM_PER_ORGANIC := 2500000.0

## Per-update decay rate at loam (texture multiplier 1.0). Clay keeps ~25% more
## organic per update, sand loses ~30% more.
const BASE_DECAY_RATE := 0.08
const TEXTURE_DECAY_MULTIPLIER := {"sand": 1.3, "loam": 1.0, "clay": 0.75}
const VALID_TEXTURES: Array[String] = ["sand", "loam", "clay"]

## Required record fields (research read-model over realized phenotypes):
##   identity (String, unique), world_x_m, world_z_m (finite),
##   litter_flux_ppm (int >= 0, from PlantFunctionalPhenotype),
##   shade_output_ppm (int >= 0, optional), source_phenotype_hash (optional).
## field_inputs:
##   fixture_id (non-empty String), fixture_version (non-empty String),
##   textures (cell_identity -> "sand"|"loam"|"clay", must cover every occupied
##   cell and every carried-over cell),
##   decay_rate (finite float in [0,1]; defaults to BASE_DECAY_RATE when absent),
##   initial_organic (OPTIONAL cell_identity -> float in [0,ORGANIC_CAPACITY]
##   carryover map; absent = pristine start from zero; present = must cover
##   every occupied cell).
static func validate_record(record: Dictionary) -> Dictionary:
	for field_name in ["identity", "world_x_m", "world_z_m", "litter_flux_ppm"]:
		if not record.has(field_name):
			return _failure("ECO_ORGANIC_FIELD_RECORD_MISSING", {"field": field_name})
	if String(record["identity"]).is_empty():
		return _failure("ECO_ORGANIC_FIELD_RECORD_EMPTY_IDENTITY")
	for coordinate in ["world_x_m", "world_z_m"]:
		if not is_finite(float(record[coordinate])):
			return _failure("ECO_ORGANIC_FIELD_RECORD_NON_FINITE", {"field": coordinate})
	if typeof(record["litter_flux_ppm"]) != TYPE_INT or int(record["litter_flux_ppm"]) < 0:
		return _failure("ECO_ORGANIC_FIELD_RECORD_LITTER_PPM")
	if record.has("shade_output_ppm") and (typeof(record["shade_output_ppm"]) != TYPE_INT or int(record["shade_output_ppm"]) < 0):
		return _failure("ECO_ORGANIC_FIELD_RECORD_SHADE_PPM")
	return _success()

static func validate_field_inputs(field_inputs: Dictionary) -> Dictionary:
	for field_name in ["fixture_id", "fixture_version", "textures"]:
		if not field_inputs.has(field_name):
			return _failure("ECO_ORGANIC_FIELD_INPUTS_MISSING", {"field": field_name})
	if String(field_inputs["fixture_id"]).is_empty() or String(field_inputs["fixture_version"]).is_empty():
		return _failure("ECO_ORGANIC_FIELD_INPUTS_FIXTURE_IDENTITY")
	for cell_id in field_inputs["textures"].keys():
		if not String(field_inputs["textures"][cell_id]) in VALID_TEXTURES:
			return _failure("ECO_ORGANIC_FIELD_INPUTS_TEXTURE_VALUE", {"cell": String(cell_id)})
	if field_inputs.has("decay_rate"):
		var decay_rate = field_inputs["decay_rate"]
		if not is_finite(float(decay_rate)) or float(decay_rate) < 0.0 or float(decay_rate) > 1.0:
			return _failure("ECO_ORGANIC_FIELD_INPUTS_DECAY_RATE")
	if field_inputs.has("initial_organic"):
		if typeof(field_inputs["initial_organic"]) != TYPE_DICTIONARY:
			return _failure("ECO_ORGANIC_FIELD_INPUTS_INITIAL_ORGANIC_TYPE")
		for cell_id in field_inputs["initial_organic"].keys():
			var raw_value = field_inputs["initial_organic"][cell_id]
			if not is_finite(float(raw_value)) or float(raw_value) < 0.0 or float(raw_value) > ORGANIC_CAPACITY:
				return _failure("ECO_ORGANIC_FIELD_INPUTS_INITIAL_ORGANIC_RANGE", {"cell": String(cell_id)})
	return _success()

static func cell_identity_for(world_x_m: float, world_z_m: float) -> String:
	return "%d|%d" % [floori(world_x_m / CELL_SIZE_M), floori(world_z_m / CELL_SIZE_M)]

## Moisture-retention coupling consumed by the water field: organic soil loses
## proportionally less water to bare-soil evaporation. The multiplier is always
## >= 1, so scaling evaporation by 1/multiplier never increases it.
static func retention_multiplier(organic_value: float) -> float:
	return 1.0 + RETENTION_PER_ORGANIC * clampf(organic_value, 0.0, ORGANIC_CAPACITY)

static func compute(records: Array, field_inputs: Dictionary) -> Dictionary:
	if not bool(validate_field_inputs(field_inputs).get("success", false)):
		return {}
	var validated: Array[Dictionary] = []
	var identities := {}
	for raw_record in records:
		var record: Dictionary = raw_record
		if not bool(validate_record(record).get("success", false)):
			return {}
		var identity := String(record["identity"])
		if identities.has(identity):
			return {}
		identities[identity] = true
		validated.append(record.duplicate(true))
	if validated.is_empty():
		return {}
	validated.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["identity"]) < String(b["identity"]))

	var textures: Dictionary = field_inputs["textures"]
	var decay_rate := snappedf(float(field_inputs.get("decay_rate", BASE_DECAY_RATE)), 1e-9)
	var has_carryover: bool = field_inputs.has("initial_organic")
	var initial_organic: Dictionary = field_inputs.get("initial_organic", {})

	# Deposit phase: accumulate litter into cells in canonical identity order
	# (order-invariant sums, G12 discipline). Membership is deterministic.
	var deposited_litter := {}
	var plant_counts := {}
	var cell_order: Array[String] = []
	for record in validated:
		var cell_id := cell_identity_for(float(record["world_x_m"]), float(record["world_z_m"]))
		if not textures.has(cell_id):
			return {}
		if not String(textures[cell_id]) in VALID_TEXTURES:
			return {}
		if not deposited_litter.has(cell_id):
			deposited_litter[cell_id] = 0
			plant_counts[cell_id] = 0
			cell_order.append(cell_id)
			if has_carryover and not initial_organic.has(cell_id):
				# Fail closed: a carryover map must describe every occupied cell.
				return {}
		deposited_litter[cell_id] = int(deposited_litter[cell_id]) + int(record["litter_flux_ppm"])
		plant_counts[cell_id] = int(plant_counts[cell_id]) + 1

	# Tracked cells = occupied cells plus carry-over-only cells (legacy patches
	# keep decaying even without fresh litter). Texture must cover them all.
	var working_cells: Array[String] = []
	working_cells.append_array(cell_order)
	if has_carryover:
		var extra_cells: Array = initial_organic.keys()
		extra_cells.sort()
		for extra_cell in extra_cells:
			var extra_id := String(extra_cell)
			if not working_cells.has(extra_id):
				if not textures.has(extra_id):
					return {}
				if not String(textures[extra_id]) in VALID_TEXTURES:
					return {}
				working_cells.append(extra_id)

	# Decay phase: applied once, after all deposits, per texture multiplier,
	# clamped into [0, ORGANIC_CAPACITY].
	var cells := {}
	for cell_id in working_cells:
		var before := 0.0
		if has_carryover:
			before = snappedf(float(initial_organic[cell_id]), 1e-9)
		var texture := String(textures[cell_id])
		var litter_total := int(deposited_litter.get(cell_id, 0))
		var litter_share := snappedf(float(litter_total) / LITTER_PPM_PER_ORGANIC, 1e-9)
		var after_deposit := snappedf(before + litter_share, 1e-9)
		var decay_factor := snappedf(1.0 - decay_rate * float(TEXTURE_DECAY_MULTIPLIER[texture]), 1e-9)
		var organic_after := snappedf(clampf(after_deposit * decay_factor, 0.0, ORGANIC_CAPACITY), 1e-9)
		cells[cell_id] = {
			"texture": texture,
			"organic_before": before,
			"deposited_litter_ppm": litter_total,
			"litter_share": litter_share,
			"decay_factor": decay_factor,
			"organic_after": organic_after,
			"retention_multiplier": snappedf(retention_multiplier(organic_after), 1e-9),
			"plant_count": int(plant_counts.get(cell_id, 0)),
		}

	var plant_litter := {}
	for record in validated:
		plant_litter[String(record["identity"])] = {
			"cell_identity": cell_identity_for(float(record["world_x_m"]), float(record["world_z_m"])),
			"litter_flux_ppm": int(record["litter_flux_ppm"]),
		}

	var field := {
		"schema": SCHEMA,
		"version": VERSION,
		"fixture_id": String(field_inputs["fixture_id"]),
		"fixture_version": String(field_inputs["fixture_version"]),
		"cell_size_m": CELL_SIZE_M,
		"organic_capacity": ORGANIC_CAPACITY,
		"retention_per_organic": RETENTION_PER_ORGANIC,
		"litter_ppm_per_organic": LITTER_PPM_PER_ORGANIC,
		"decay_rate": decay_rate,
		"had_carryover": has_carryover,
		"record_count": validated.size(),
		"cells": cells,
		"plant_litter": plant_litter,
	}
	field["organic_field_hash"] = _organic_field_hash(field)
	field["plant_litter_hash"] = _plant_litter_hash(field)

	# Canonical carryover map for the next update (all tracked cells, sorted).
	var organic_map := {}
	var map_cell_ids: Array = cells.keys()
	map_cell_ids.sort()
	for map_cell in map_cell_ids:
		organic_map[String(map_cell)] = float(cells[map_cell]["organic_after"])
	field["organic_map"] = organic_map
	return field

## Deterministic effect-record publication in canonical identity order (spec
## section 7): the litter_input channel carries the plant's deposited litter.
## Single-channel publication discipline: this aggregator publishes ONLY its own
## channel (shade/water channels stay zero here); consumers merge records by
## plant identity if they need cross-field views.
static func effect_records(records: Array, field_inputs: Dictionary, generation: int) -> Array:
	var field := compute(records, field_inputs)
	if field.is_empty():
		return []
	var published: Array = []
	var ordered := records.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["identity"]) < String(b["identity"]))
	for record in ordered:
		var identity := String(record["identity"])
		var litter_entry: Dictionary = field["plant_litter"][identity]
		var effect := Effect.create(
			identity, String(litter_entry["cell_identity"]), generation,
			0, String(record.get("source_phenotype_hash", "0".repeat(64))),
			0, 0, int(litter_entry["litter_flux_ppm"]))
		if effect.is_empty():
			return []
		published.append(effect)
	return published

## Convenience wrapper used by bridges/tests: build organic field inputs for a
## fixture tag with a texture map, an optional carryover map and decay rate.
static func field_inputs_for(
	fixture_tag: String,
	textures: Dictionary,
	carryover: Dictionary = {},
	decay_rate := BASE_DECAY_RATE
) -> Dictionary:
	var inputs := {
		"fixture_id": "eco-soil-organic/%s" % fixture_tag,
		"fixture_version": "1.0.0",
		"textures": textures.duplicate(true),
		"decay_rate": snappedf(float(decay_rate), 1e-9),
	}
	if not carryover.is_empty():
		inputs["initial_organic"] = carryover.duplicate(true)
	return inputs

static func mean_cell_organic(field: Dictionary) -> float:
	var cells: Dictionary = field["cells"]
	var total := 0.0
	for cell_id in cells.keys():
		total += float(cells[cell_id]["organic_after"])
	return snappedf(total / float(cells.size()), 1e-9)

static func _organic_field_hash(field: Dictionary) -> String:
	var cell_tokens := PackedStringArray()
	var cell_ids: Array = field["cells"].keys()
	cell_ids.sort()
	for cell_id in cell_ids:
		var cell: Dictionary = field["cells"][cell_id]
		cell_tokens.append("%s:%s:%.9f:%d:%.9f:%.9f:%.9f" % [
			String(cell_id), String(cell["texture"]),
			float(cell["organic_before"]), int(cell["deposited_litter_ppm"]),
			float(cell["litter_share"]), float(cell["decay_factor"]), float(cell["organic_after"]),
		])
	return "|".join(PackedStringArray([
		SCHEMA, VERSION, String(field["fixture_id"]), String(field["fixture_version"]),
		"%.1f" % float(field["cell_size_m"]), "%.1f" % float(field["organic_capacity"]),
		"%.2f" % float(field["retention_per_organic"]), "%.1f" % float(field["litter_ppm_per_organic"]),
		"%.9f" % float(field["decay_rate"]), str(int(field["record_count"])), ";".join(cell_tokens),
	])).sha256_text()

static func _plant_litter_hash(field: Dictionary) -> String:
	var plant_tokens := PackedStringArray()
	var identities: Array = field["plant_litter"].keys()
	identities.sort()
	for identity in identities:
		var entry: Dictionary = field["plant_litter"][identity]
		plant_tokens.append("%s:%s:%d" % [
			String(identity), String(entry["cell_identity"]), int(entry["litter_flux_ppm"]),
		])
	return "|".join(PackedStringArray([SCHEMA, VERSION, "plant_litter", ";".join(plant_tokens)])).sha256_text()

static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
