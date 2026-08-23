extends RefCounted

## ECO.EVO7 FFF3 - understory light field aggregator (spec sections 8, 13).
## Deterministic, order-invariant, cell-bucketed. R1 operates at crown microcosm
## scale (meter cells): skeleton crowns are sub-meter, so the community plot is
## a few meters across. Real spatial scale arrives with FFF6/FFF7.
##
## MODEL (R1):
##   - Beer-Lambert transmission per plant point:
##       overlap_lai(p) = SUM_q!=p, height_q > height_p  of  lai_q * w(q->p)
##       w(q->p)        = clamp01(1 - dist(p,q) / crown_radius_q)   (soft disc edge)
##       transmittance  = exp(-K * overlap_lai)
##       understory     = base_sunlight_p * transmittance
##   - Vertical structure: only TALLER canopies shade a plant; equal-height plants
##     do not shade each other; a short plant never shades a tall one.
##   - Canonical order: records are sorted by plant identity; every float sum runs
##     in that order, so input permutation cannot change any hash (G12).
##   - Cell buckets (CELL_SIZE_M) give deterministic membership and per-cell canopy
##     load observability; per-plant light does not depend on bucket traversal order.
##   - FFF6 BUCKET-PRUNED NEIGHBOR SEARCH: sources are indexed into their
##     cell_identity_for(...) buckets once per compute; for each target only the
##     sources in cells within Chebyshev range ceil(max_crown_radius / CELL_SIZE_M) + 1
##     of the target's cell are visited (candidates re-sorted to ascending validated
##     index = canonical identity order). A skipped pair is provably zero-weight:
##     weight w = clamp01(1 - dist/radius_source) is positive only when the source is
##     taller and dist < radius_source <= max_crown_radius, and any such source lies in
##     the scanned cell range. Byte-identical outputs: dropped terms are exactly 0.0,
##     kept terms accumulate in the same canonical order, so field_hash /
##     plant_light_hash / per-plant understory light are unchanged (FFF3 regression
##     stays bit-exact). Complexity drops from O(N^2) to O(N + C + local).

const SCHEMA := "distributed_world_simulator.ecology.understory_light_field.v1"
const VERSION := "1.0.0"
const CELL_SIZE_M := 1.0
const EXTINCTION_K := 0.9
const Effect = preload("res://scripts/research/ecology/plant_environment_effect_v1.gd")

## Required record fields (research read-model over realized phenotypes):
##   identity (String, unique), world_x_m, world_z_m (finite),
##   realized_height_m >= 0, realized_crown_radius_m >= 0,
##   realized_crown_density in [0,1], leaf_area_index_proxy >= 0,
##   base_sunlight in [0,1], shade_output_ppm (int >= 0, optional).
static func validate_record(record: Dictionary) -> Dictionary:
	for field_name in ["identity", "world_x_m", "world_z_m", "realized_height_m", "realized_crown_radius_m", "realized_crown_density", "leaf_area_index_proxy", "base_sunlight"]:
		if not record.has(field_name):
			return _failure("ECO_LIGHT_FIELD_RECORD_MISSING", {"field": field_name})
	if String(record["identity"]).is_empty():
		return _failure("ECO_LIGHT_FIELD_RECORD_EMPTY_IDENTITY")
	for coordinate in ["world_x_m", "world_z_m"]:
		if not is_finite(float(record[coordinate])):
			return _failure("ECO_LIGHT_FIELD_RECORD_NON_FINITE", {"field": coordinate})
	for value_field in ["realized_height_m", "realized_crown_radius_m", "leaf_area_index_proxy"]:
		if not is_finite(float(record[value_field])) or float(record[value_field]) < 0.0:
			return _failure("ECO_LIGHT_FIELD_RECORD_NEGATIVE", {"field": value_field})
	if float(record["realized_crown_density"]) < 0.0 or float(record["realized_crown_density"]) > 1.0:
		return _failure("ECO_LIGHT_FIELD_RECORD_DENSITY_RANGE")
	if float(record["base_sunlight"]) < 0.0 or float(record["base_sunlight"]) > 1.0:
		return _failure("ECO_LIGHT_FIELD_RECORD_SUNLIGHT_RANGE")
	if record.has("shade_output_ppm") and (typeof(record["shade_output_ppm"]) != TYPE_INT or int(record["shade_output_ppm"]) < 0):
		return _failure("ECO_LIGHT_FIELD_RECORD_SHADE_PPM")
	return _success()

static func cell_identity_for(world_x_m: float, world_z_m: float) -> String:
	return "%d|%d" % [floori(world_x_m / CELL_SIZE_M), floori(world_z_m / CELL_SIZE_M)]

static func compute(records: Array) -> Dictionary:
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

	# FFF6 bucket-pruned neighbor search: index sources by cell once, then visit
	# only the cells that can contain a nonzero-weight source for each target.
	# Candidate indices are consumed in ascending order, which is exactly the
	# canonical (identity-sorted) validated order, so every float sum below keeps
	# its canonical accumulation order and the outputs are byte-identical to the
	# previous all-pairs scan.
	var max_crown_radius := 0.0
	for record in validated:
		max_crown_radius = maxf(max_crown_radius, float(record["realized_crown_radius_m"]))
	var prune_range := ceili(max_crown_radius / CELL_SIZE_M) + 1
	var source_buckets := {}
	for index in validated.size():
		var bucket_source: Dictionary = validated[index]
		var bucket_cell := cell_identity_for(float(bucket_source["world_x_m"]), float(bucket_source["world_z_m"]))
		if not source_buckets.has(bucket_cell):
			source_buckets[bucket_cell] = PackedInt32Array()
		source_buckets[bucket_cell].append(index)

	var cells := {}
	var plant_light := {}
	for index in validated.size():
		var target: Dictionary = validated[index]
		var target_cell_x := floori(float(target["world_x_m"]) / CELL_SIZE_M)
		var target_cell_z := floori(float(target["world_z_m"]) / CELL_SIZE_M)
		var candidate_indices := PackedInt32Array()
		for dx in range(-prune_range, prune_range + 1):
			for dz in range(-prune_range, prune_range + 1):
				var nearby_cell := "%d|%d" % [target_cell_x + dx, target_cell_z + dz]
				if source_buckets.has(nearby_cell):
					candidate_indices.append_array(source_buckets[nearby_cell])
		candidate_indices.sort()
		var overlap := 0.0
		for source_index in candidate_indices:
			var source: Dictionary = validated[source_index]
			if String(source["identity"]) == String(target["identity"]):
				continue
			if float(source["realized_height_m"]) <= float(target["realized_height_m"]):
				continue
			var radius := float(source["realized_crown_radius_m"])
			if radius <= 0.0:
				continue
			var distance := Vector2(
				float(source["world_x_m"]) - float(target["world_x_m"]),
				float(source["world_z_m"]) - float(target["world_z_m"])).length()
			if distance >= radius:
				continue
			overlap += float(source["leaf_area_index_proxy"]) * (1.0 - distance / radius)
		overlap = snappedf(overlap, 1e-9)
		var transmittance := snappedf(exp(-EXTINCTION_K * overlap), 1e-12)
		var understory := snappedf(float(target["base_sunlight"]) * transmittance, 1e-9)
		var cell_id := cell_identity_for(float(target["world_x_m"]), float(target["world_z_m"]))
		plant_light[String(target["identity"])] = {
			"cell_identity": cell_id,
			"overlap_lai": overlap,
			"transmittance": transmittance,
			"understory_light": understory,
		}
		var canopy_load := float(target["leaf_area_index_proxy"]) * float(target["realized_crown_density"])
		if not cells.has(cell_id):
			cells[cell_id] = {"canopy_load": 0.0, "plant_count": 0}
		cells[cell_id]["canopy_load"] = snappedf(float(cells[cell_id]["canopy_load"]) + canopy_load, 1e-9)
		cells[cell_id]["plant_count"] = int(cells[cell_id]["plant_count"]) + 1

	var field := {
		"schema": SCHEMA,
		"version": VERSION,
		"cell_size_m": CELL_SIZE_M,
		"extinction_k": EXTINCTION_K,
		"record_count": validated.size(),
		"cells": cells,
		"plant_light": plant_light,
	}
	field["field_hash"] = _field_hash(field)
	field["plant_light_hash"] = _plant_light_hash(field)
	return field

## Deterministic effect-record publication in canonical identity order (spec section 7).
static func effect_records(records: Array, generation: int) -> Array:
	var field := compute(records)
	if field.is_empty():
		return []
	var published: Array = []
	var ordered := records.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["identity"]) < String(b["identity"]))
	for record in ordered:
		var identity := String(record["identity"])
		var light_entry: Dictionary = field["plant_light"][identity]
		var shade_ppm := int(record.get("shade_output_ppm", 0))
		var effect := Effect.create(
			identity, String(light_entry["cell_identity"]), generation,
			shade_ppm, String(record.get("source_phenotype_hash", "0".repeat(64))))
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
		cell_tokens.append("%s:%.9f:%d" % [String(cell_id), float(cell["canopy_load"]), int(cell["plant_count"])])
	return "|".join(PackedStringArray([
		SCHEMA, VERSION, "%.1f" % float(field["cell_size_m"]), "%.2f" % float(field["extinction_k"]),
		str(int(field["record_count"])), ";".join(cell_tokens),
	])).sha256_text()

static func _plant_light_hash(field: Dictionary) -> String:
	var plant_tokens := PackedStringArray()
	var identities: Array = field["plant_light"].keys()
	identities.sort()
	for identity in identities:
		var entry: Dictionary = field["plant_light"][identity]
		plant_tokens.append("%s:%s:%.9f:%.9f:%.9f" % [
			String(identity), String(entry["cell_identity"]),
			float(entry["overlap_lai"]), float(entry["transmittance"]), float(entry["understory_light"]),
		])
	return "|".join(PackedStringArray([SCHEMA, VERSION, "plant_light", ";".join(plant_tokens)])).sha256_text()

static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
