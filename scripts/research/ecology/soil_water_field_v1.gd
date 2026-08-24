extends RefCounted

## ECO.EVO7 FFF4 - soil water field aggregator (spec sections 9, 13; gates G8/G9/G12).
## Two-sided water loop: plants publish transpiration demand, the field returns
## bounded uptake and updated cell moisture, and canopy cover suppresses
## evaporation (the counter-effect of a big crown, spec section 9.3).
## Soil texture is a VERSIONED FIXTURE CHANNEL (spec section 9.4) - an ecological
## input map, NOT new geology and NOT a morphology rule.
##
## MODEL (R1):
##   - root access (research-derived, spec section 9.2):
##       root_access_i = clamp01(0.3 + 0.4*root_depth_norm + 0.3*root_spread_norm)
##       root_depth_norm  = clamp01(realized_root_depth_m  / ROOT_DEPTH_NORM_REF_M)
##       root_spread_norm = clamp01(realized_root_spread_m / ROOT_SPREAD_NORM_REF_M)
##   - texture fixture scales uptake efficiency (sand 0.85 / loam 1.0 / clay 0.9)
##     and bare-soil evaporation (sand 1.35 / loam 1.0 / clay 0.8).
##   - per cell, water is depleted in canonical identity order:
##       uptake_i = min(transpiration_demand_i, remaining * root_access_i * texture_eff_i)
##     so per-cell total uptake can never exceed available water (structurally
##     re-asserted, fail closed). Identity-priority rationing is a declared R1
##     simplification; the canonical order is permutation-independent, so results
##     are order-invariant (G12).
##   - canopy cover per cell is sampled at the cell center with the understory
##     light field soft-disc weight w = clamp01(1 - dist/crown_radius), weighted
##     by crown density; shade_suppression = clamp01(canopy_cover * 0.6);
##     evaporation_cell = base_evaporation_rate * texture_evap_mult * (1 - shade_suppression).
##   - FFF5 ORGANIC RETENTION COUPLING (optional): field_inputs may carry an
##     "organic_map" (cell_identity -> organic proxy in [0,1], produced by
##     soil_organic_field_v1). When present, each occupied cell's evaporation
##     additionally scales by 1 / retention_multiplier(organic_cell) where
##     retention_multiplier(o) = 1 + 0.35 * o (see soil_organic_field_v1):
##     organic matter slows bare-soil evaporation ("mulch effect"). The scaled
##     evaporation is clamped into [0, unscaled] so it can never go negative or
##     exceed the base value; uptake and everything else are untouched. When the
##     map is ABSENT the field computes exactly as before this coupling existed
##     (pristine path is bit-identical, FFF4 regression stays green).
##   - moisture_after = clamp01(base_moisture - (total_uptake + evaporation) / CELL_WATER_CAPACITY_PPM).
##
## Deterministic: no RNG, no SceneTree, canonical identity order for every float
## sum, snapped floats, fail-closed on invalid input (empty result).

const SCHEMA := "distributed_world_simulator.ecology.soil_water_field.v1"
const VERSION := "1.0.0"
const CELL_SIZE_M := 1.0

## Versioned texture fixture channel identity (spec section 9.4).
const TEXTURE_FIXTURE_SCHEMA := "distributed_world_simulator.ecology.soil_texture_fixture.v1"

## Root access constants (documented R1 calibration; refs keep norms in [0,1]
## for skeleton-scale root systems, realized depth O(0-3 m), spread O(0-2 m)).
const ROOT_ACCESS_BASE := 0.3
const ROOT_ACCESS_DEPTH_WEIGHT := 0.4
const ROOT_ACCESS_SPREAD_WEIGHT := 0.3
const ROOT_DEPTH_NORM_REF_M := 3.0
const ROOT_SPREAD_NORM_REF_M := 2.0

## Texture fixture parameters (spec section 9.4): sand drains and evaporates
## fast, clay holds water but caps infiltration, loam is the reference.
const TEXTURE_UPTAKE_EFFICIENCY := {"sand": 0.85, "loam": 1.0, "clay": 0.9}
const TEXTURE_EVAPORATION_MULTIPLIER := {"sand": 1.35, "loam": 1.0, "clay": 0.8}
const VALID_TEXTURES: Array[String] = ["sand", "loam", "clay"]

## Canopy counter-effect (spec section 9.3): full cover suppresses at most 60%
## of bare-soil evaporation in R1.
const SHADE_EVAPORATION_SUPPRESSION := 0.6

## Cell water held at moisture 1.0, in effect-record ppm units. FFF4 calibration:
## keeps uptake demand-limited in both fixture scenarios while making the
## plant-driven moisture drop visible (~45% of base in dry sand, see FFF4
## checkpoint calibration history).
const CELL_WATER_CAPACITY_PPM := 4000000.0

## Effect-record scale for the evaporation-suppression channel (same order as
## the phenotype shade scale).
const EVAPORATION_SUPPRESSION_PPM_SCALE := 90000.0

const Effect = preload("res://scripts/research/ecology/plant_environment_effect_v1.gd")
const SoilOrganic = preload("res://scripts/research/ecology/soil_organic_field_v1.gd")

## Required record fields (research read-model over realized phenotypes):
##   identity (String, unique), world_x_m, world_z_m (finite),
##   transpiration_demand_ppm (int >= 0), realized_crown_radius_m >= 0,
##   realized_crown_density in [0,1], realized_root_depth_m >= 0,
##   realized_root_spread_m >= 0, root_shoot_ratio in [0,1]
##   (root_shoot_ratio rides the record for FFF5 water-use coupling; the R1
##   access formula uses depth/spread only),
##   shade_output_ppm (int >= 0, optional), source_phenotype_hash (optional).
## field_inputs:
##   fixture_id (non-empty String), fixture_version (non-empty String),
##   textures (cell_identity -> "sand"|"loam"|"clay", must cover every occupied cell),
##   base_moisture (cell_identity -> float in [0,1], must cover every occupied cell),
##   base_evaporation_rate (finite float >= 0),
##   organic_map (OPTIONAL cell_identity -> float in [0,1], FFF5 retention
##   coupling from soil_organic_field_v1; absent = pristine behavior).
static func validate_record(record: Dictionary) -> Dictionary:
	for field_name in ["identity", "world_x_m", "world_z_m", "transpiration_demand_ppm", "realized_crown_radius_m", "realized_crown_density", "realized_root_depth_m", "realized_root_spread_m", "root_shoot_ratio"]:
		if not record.has(field_name):
			return _failure("ECO_WATER_FIELD_RECORD_MISSING", {"field": field_name})
	if String(record["identity"]).is_empty():
		return _failure("ECO_WATER_FIELD_RECORD_EMPTY_IDENTITY")
	for coordinate in ["world_x_m", "world_z_m"]:
		if not is_finite(float(record[coordinate])):
			return _failure("ECO_WATER_FIELD_RECORD_NON_FINITE", {"field": coordinate})
	if typeof(record["transpiration_demand_ppm"]) != TYPE_INT or int(record["transpiration_demand_ppm"]) < 0:
		return _failure("ECO_WATER_FIELD_RECORD_DEMAND")
	for value_field in ["realized_crown_radius_m", "realized_root_depth_m", "realized_root_spread_m"]:
		if not is_finite(float(record[value_field])) or float(record[value_field]) < 0.0:
			return _failure("ECO_WATER_FIELD_RECORD_NEGATIVE", {"field": value_field})
	for ratio_field in ["realized_crown_density", "root_shoot_ratio"]:
		if not is_finite(float(record[ratio_field])) or float(record[ratio_field]) < 0.0 or float(record[ratio_field]) > 1.0:
			return _failure("ECO_WATER_FIELD_RECORD_RATIO_RANGE", {"field": ratio_field})
	if record.has("shade_output_ppm") and (typeof(record["shade_output_ppm"]) != TYPE_INT or int(record["shade_output_ppm"]) < 0):
		return _failure("ECO_WATER_FIELD_RECORD_SHADE_PPM")
	return _success()

static func validate_field_inputs(field_inputs: Dictionary) -> Dictionary:
	for field_name in ["fixture_id", "fixture_version", "textures", "base_moisture", "base_evaporation_rate"]:
		if not field_inputs.has(field_name):
			return _failure("ECO_WATER_FIELD_INPUTS_MISSING", {"field": field_name})
	if String(field_inputs["fixture_id"]).is_empty() or String(field_inputs["fixture_version"]).is_empty():
		return _failure("ECO_WATER_FIELD_INPUTS_FIXTURE_IDENTITY")
	if not is_finite(float(field_inputs["base_evaporation_rate"])) or float(field_inputs["base_evaporation_rate"]) < 0.0:
		return _failure("ECO_WATER_FIELD_INPUTS_EVAPORATION_RATE")
	if field_inputs.has("organic_map") and typeof(field_inputs["organic_map"]) != TYPE_DICTIONARY:
		return _failure("ECO_WATER_FIELD_INPUTS_ORGANIC_MAP_TYPE")
	for cell_id in (field_inputs.get("organic_map", {}) as Dictionary).keys():
		var raw_organic = field_inputs["organic_map"][cell_id]
		if not is_finite(float(raw_organic)) or float(raw_organic) < 0.0 or float(raw_organic) > SoilOrganic.ORGANIC_CAPACITY:
			return _failure("ECO_WATER_FIELD_INPUTS_ORGANIC_RANGE", {"cell": String(cell_id)})
	return _success()

static func cell_identity_for(world_x_m: float, world_z_m: float) -> String:
	return "%d|%d" % [floori(world_x_m / CELL_SIZE_M), floori(world_z_m / CELL_SIZE_M)]

static func cell_center(cell_identity: String) -> Vector2:
	var parts := String(cell_identity).split("|")
	return Vector2((float(parts[0]) + 0.5) * CELL_SIZE_M, (float(parts[1]) + 0.5) * CELL_SIZE_M)

static func root_access(realized_root_depth_m: float, realized_root_spread_m: float) -> float:
	var depth_norm := clampf(realized_root_depth_m / ROOT_DEPTH_NORM_REF_M, 0.0, 1.0)
	var spread_norm := clampf(realized_root_spread_m / ROOT_SPREAD_NORM_REF_M, 0.0, 1.0)
	return clampf(ROOT_ACCESS_BASE + ROOT_ACCESS_DEPTH_WEIGHT * depth_norm + ROOT_ACCESS_SPREAD_WEIGHT * spread_norm, 0.0, 1.0)

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
	var base_moisture: Dictionary = field_inputs["base_moisture"]
	var base_evaporation := snappedf(float(field_inputs["base_evaporation_rate"]), 1e-9)
	# FFF5 optional retention coupling: absent map = pristine behavior.
	var organic_map: Dictionary = field_inputs.get("organic_map", {})
	var organic_coupling: bool = not organic_map.is_empty()

	# Deterministic cell membership from the canonical record order.
	var cell_plants := {}
	var plant_order: Array[String] = []
	for record in validated:
		var cell_id := cell_identity_for(float(record["world_x_m"]), float(record["world_z_m"]))
		if not cell_plants.has(cell_id):
			cell_plants[cell_id] = []
			plant_order.append(cell_id)
		cell_plants[cell_id].append(record)

	var cells := {}
	var plant_uptake := {}
	for cell_id in plant_order:
		if not textures.has(cell_id) or not base_moisture.has(cell_id):
			return {}
		var texture := String(textures[cell_id])
		if not texture in VALID_TEXTURES:
			return {}
		var raw_moisture = base_moisture[cell_id]
		if not is_finite(float(raw_moisture)) or float(raw_moisture) < 0.0 or float(raw_moisture) > 1.0:
			return {}
		var moisture_before := snappedf(float(raw_moisture), 1e-9)
		var uptake_efficiency := float(TEXTURE_UPTAKE_EFFICIENCY[texture])
		var evaporation_multiplier := float(TEXTURE_EVAPORATION_MULTIPLIER[texture])
		var center := cell_center(cell_id)

		# Canopy cover sampled at the cell center (soft-disc weight from the
		# light field), summed in canonical identity order.
		var cover_sum := 0.0
		for source in validated:
			var radius := float(source["realized_crown_radius_m"])
			if radius <= 0.0:
				continue
			var distance := Vector2(
				float(source["world_x_m"]) - center.x,
				float(source["world_z_m"]) - center.y).length()
			if distance >= radius:
				continue
			cover_sum += float(source["realized_crown_density"]) * (1.0 - distance / radius)
		cover_sum = snappedf(cover_sum, 1e-9)
		var canopy_cover := clampf(cover_sum, 0.0, 1.0)
		var shade_suppression := clampf(canopy_cover * SHADE_EVAPORATION_SUPPRESSION, 0.0, 1.0)
		var unscaled_evaporation := snappedf(base_evaporation * evaporation_multiplier * (1.0 - shade_suppression), 1e-9)
		var evaporation := unscaled_evaporation
		var organic_input := 0.0
		var evaporation_retention := 1.0
		if organic_coupling:
			if not organic_map.has(cell_id):
				return {}
			var raw_cell_organic = organic_map[cell_id]
			if not is_finite(float(raw_cell_organic)) or float(raw_cell_organic) < 0.0 or float(raw_cell_organic) > SoilOrganic.ORGANIC_CAPACITY:
				return {}
			organic_input = snappedf(float(raw_cell_organic), 1e-9)
			evaporation_retention = snappedf(SoilOrganic.retention_multiplier(organic_input), 1e-9)
			# Organic mulch slows evaporation: scale by 1/retention, clamped so
			# evaporation never goes negative and never exceeds the base value.
			evaporation = snappedf(clampf(unscaled_evaporation / evaporation_retention, 0.0, unscaled_evaporation), 1e-9)

		# Bounded uptake: the cell reservoir is depleted in canonical identity
		# order, so the per-cell total can never exceed available water.
		var available := snappedf(moisture_before * CELL_WATER_CAPACITY_PPM, 1e-6)
		var remaining := available
		var total_uptake := 0
		for record: Dictionary in cell_plants[cell_id]:
			var identity := String(record["identity"])
			var demand := int(record["transpiration_demand_ppm"])
			var access := snappedf(root_access(float(record["realized_root_depth_m"]), float(record["realized_root_spread_m"])), 1e-9)
			var cap := snappedf(remaining * access * uptake_efficiency, 1e-6)
			var uptake := mini(demand, int(floor(cap)))
			if uptake < 0:
				return {}
			remaining = snappedf(remaining - float(uptake), 1e-6)
			total_uptake += uptake
			plant_uptake[identity] = {
				"cell_identity": cell_id,
				"transpiration_demand_ppm": demand,
				"root_access": access,
				"texture_efficiency": uptake_efficiency,
				"actual_uptake_ppm": uptake,
			}
		# Structural conservation gate (fail closed): uptake never exceeds the
		# water that was available in the cell.
		if float(total_uptake) > available + 1e-3:
			return {}
		var moisture_after := snappedf(clampf(
			moisture_before - (float(total_uptake) + evaporation) / CELL_WATER_CAPACITY_PPM, 0.0, 1.0), 1e-12)
		cells[cell_id] = {
			"texture": texture,
			"base_moisture": moisture_before,
			"moisture_after": moisture_after,
			"total_uptake_ppm": total_uptake,
			"evaporation_ppm": evaporation,
			"canopy_cover": canopy_cover,
			"shade_suppression": shade_suppression,
			"plant_count": (cell_plants[cell_id] as Array).size(),
		}
		if organic_coupling:
			cells[cell_id]["organic_input"] = organic_input
			cells[cell_id]["evaporation_retention"] = evaporation_retention

	var field := {
		"schema": SCHEMA,
		"version": VERSION,
		"fixture_schema": TEXTURE_FIXTURE_SCHEMA,
		"fixture_id": String(field_inputs["fixture_id"]),
		"fixture_version": String(field_inputs["fixture_version"]),
		"cell_size_m": CELL_SIZE_M,
		"water_capacity_ppm": CELL_WATER_CAPACITY_PPM,
		"base_evaporation_rate": base_evaporation,
		"organic_coupling": organic_coupling,
		"record_count": validated.size(),
		"cells": cells,
		"plant_uptake": plant_uptake,
	}
	field["field_hash"] = _field_hash(field)
	field["plant_uptake_hash"] = _plant_uptake_hash(field)
	return field

## Deterministic effect-record publication in canonical identity order (spec
## section 7): water_uptake_ppm carries the bounded uptake, the evaporation
## suppression channel carries the cell shade suppression.
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
		var uptake_entry: Dictionary = field["plant_uptake"][identity]
		var cell: Dictionary = field["cells"][String(uptake_entry["cell_identity"])]
		var suppression_ppm := int(round(float(cell["shade_suppression"]) * EVAPORATION_SUPPRESSION_PPM_SCALE))
		var effect := Effect.create(
			identity, String(uptake_entry["cell_identity"]), generation,
			int(record.get("shade_output_ppm", 0)),
			String(record.get("source_phenotype_hash", "0".repeat(64))),
			int(uptake_entry["actual_uptake_ppm"]), suppression_ppm)
		if effect.is_empty():
			return []
		published.append(effect)
	return published

static func _field_hash(field: Dictionary) -> String:
	var cell_tokens := PackedStringArray()
	var cell_ids: Array = field["cells"].keys()
	cell_ids.sort()
	for cell_id in cell_ids:
		var cell: Dictionary = field["cells"][cell_id]
		var token := "%s:%s:%.9f:%.9f:%d:%.9f:%.9f" % [
			String(cell_id), String(cell["texture"]),
			float(cell["base_moisture"]), float(cell["moisture_after"]),
			int(cell["total_uptake_ppm"]), float(cell["evaporation_ppm"]), float(cell["canopy_cover"]),
		]
		# FFF5 retention-coupling extension: extra tokens appear ONLY when an
		# organic map was supplied, so the pristine hash format is unchanged.
		if bool(field.get("organic_coupling", false)):
			token += ":%.9f:%.9f" % [float(cell.get("organic_input", 0.0)), float(cell.get("evaporation_retention", 1.0))]
		cell_tokens.append(token)
	return "|".join(PackedStringArray([
		SCHEMA, VERSION, String(field["fixture_id"]), String(field["fixture_version"]),
		"%.1f" % float(field["cell_size_m"]), "%.1f" % float(field["water_capacity_ppm"]),
		"%.9f" % float(field["base_evaporation_rate"]), str(int(field["record_count"])), ";".join(cell_tokens),
	])).sha256_text()

static func _plant_uptake_hash(field: Dictionary) -> String:
	var plant_tokens := PackedStringArray()
	var identities: Array = field["plant_uptake"].keys()
	identities.sort()
	for identity in identities:
		var entry: Dictionary = field["plant_uptake"][identity]
		plant_tokens.append("%s:%s:%d:%.9f:%.9f:%d" % [
			String(identity), String(entry["cell_identity"]),
			int(entry["transpiration_demand_ppm"]), float(entry["root_access"]),
			float(entry["texture_efficiency"]), int(entry["actual_uptake_ppm"]),
		])
	return "|".join(PackedStringArray([SCHEMA, VERSION, "plant_uptake", ";".join(plant_tokens)])).sha256_text()

static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
