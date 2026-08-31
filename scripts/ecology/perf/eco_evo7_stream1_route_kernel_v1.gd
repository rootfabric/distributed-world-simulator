extends RefCounted

class_name EcoEvo7Stream1RouteKernel

## ECO.EVO7 STREAM1 — pure deterministic dispersal route kernel.
##
## This file owns the LS3.3 route formulas that used to live directly in the
## coordinator. Both the legacy monolithic path and STREAM1 chunked proposals
## call this single implementation. No worker identity, chunk size, schedule,
## wall clock, renderer, filesystem or network state enters route identity.

const KERNEL_SCHEMA := "distributed_world_simulator.ecology.evo7_stream1_route_kernel.v1"
const KERNEL_VERSION := "1.0.0"

## PERF2.4 optimized chunk seam. Preserves input candidate order and
## defers candidate_hash canonicalization to the full-generation boundary.
static func build_in_input_order(
	candidates: Array,
	next_generation: int,
	schema: String,
	version: String,
	evolution_seed: int,
	cell_size_m: float,
	grid_size: int
) -> Array[Dictionary]:
	if next_generation < 1 or schema.is_empty() or version.is_empty():
		return []
	if not is_finite(cell_size_m) or cell_size_m <= 0.0 or grid_size < 1:
		return []
	var out: Array[Dictionary] = []
	for candidate_value in candidates:
		if not candidate_value is Dictionary:
			return []
		var candidate: Dictionary = candidate_value
		var route: Dictionary = build_route(
			candidate, next_generation, schema, version,
			evolution_seed, cell_size_m, grid_size)
		if route.is_empty():
			return []
		out.append(route)
	return out

static func build_all(
	candidates: Array,
	next_generation: int,
	schema: String,
	version: String,
	evolution_seed: int,
	cell_size_m: float,
	grid_size: int
) -> Array[Dictionary]:
	var out: Array[Dictionary] = build_in_input_order(
		candidates, next_generation, schema, version,
		evolution_seed, cell_size_m, grid_size)
	if out.size() != candidates.size():
		return []
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["candidate_hash"]) < String(b["candidate_hash"])
	)
	return out

static func build_route(
	candidate: Dictionary,
	next_generation: int,
	schema: String,
	version: String,
	evolution_seed: int,
	cell_size_m: float,
	grid_size: int
) -> Dictionary:
	var candidate_hash := String(candidate.get("candidate_hash", ""))
	var bundle_value = candidate.get("child_bundle")
	if candidate_hash.is_empty() or not bundle_value is Dictionary:
		return {}
	var bundle: Dictionary = bundle_value
	var parent_cell_index := int(candidate.get("parent_cell_index", -1))
	var route_seed := dispersal_seed(candidate, next_generation, schema, evolution_seed)
	if route_seed < 0:
		return {}
	return route_for_child(
		candidate_hash, bundle, parent_cell_index, route_seed,
		next_generation, schema, version, cell_size_m, grid_size)

static func dispersal_seed(
	candidate: Dictionary,
	next_generation: int,
	schema: String,
	evolution_seed: int
) -> int:
	var child_individual_id := String(candidate.get("child_individual_id", ""))
	var child_bundle_checksum := String(candidate.get("child_bundle_checksum", ""))
	var offspring_ordinal := int(candidate.get("offspring_ordinal", -1))
	if child_individual_id.is_empty() or child_bundle_checksum.is_empty() or offspring_ordinal < 0:
		return -1
	var key := "%s|dispersal|%d|%s|%s|%d|%d" % [
		schema, evolution_seed, child_individual_id,
		child_bundle_checksum, next_generation, offspring_ordinal,
	]
	return _seed48(key)

static func route_for_child(
	candidate_hash: String,
	bundle: Dictionary,
	parent_cell_index: int,
	route_seed: int,
	next_generation: int,
	schema: String,
	version: String,
	cell_size_m: float,
	grid_size: int
) -> Dictionary:
	if parent_cell_index < 0 or parent_cell_index >= grid_size * grid_size:
		return {}
	var genome_value = bundle.get("genome")
	if not genome_value is Dictionary:
		return {}
	var genome: Dictionary = genome_value
	if not genome.has("seed_dispersal_distance_m"):
		return {}
	var inherited_distance := maxf(0.0, float(genome["seed_dispersal_distance_m"]))
	var angle_u := _unit01("%d|angle" % route_seed)
	var distance_u := _unit01("%d|distance" % route_seed)
	var angle := angle_u * TAU
	var distance_m := inherited_distance * (0.20 + 1.80 * distance_u)
	var dx_cells := int(round(cos(angle) * distance_m / cell_size_m))
	var dy_cells := int(round(sin(angle) * distance_m / cell_size_m))
	var parent_x := parent_cell_index % grid_size
	var parent_y := parent_cell_index / grid_size
	var destination_x := parent_x + dx_cells
	var destination_y := parent_y + dy_cells
	var in_patch := destination_x >= 0 and destination_x < grid_size and destination_y >= 0 and destination_y < grid_size
	var destination_index := destination_y * grid_size + destination_x if in_patch else -1
	var route := {
		"candidate_hash": candidate_hash,
		"generation": next_generation,
		"dispersal_seed": route_seed,
		"parent_cell_index": parent_cell_index,
		"dx_cells": dx_cells,
		"dy_cells": dy_cells,
		"distance_m": snappedf(distance_m, 1e-9),
		"destination_cell_index": destination_index,
		"in_patch": in_patch,
		"out_of_patch_rule": "REJECT",
	}
	route["route_hash"] = route_hash(route, schema, version)
	return route

static func route_hash(route: Dictionary, schema: String, version: String) -> String:
	return "|".join(PackedStringArray([
		schema, version, "route",
		String(route.get("candidate_hash", "")),
		str(int(route.get("generation", -1))),
		str(int(route.get("dispersal_seed", 0))),
		str(int(route.get("parent_cell_index", -1))),
		str(int(route.get("dx_cells", 0))), str(int(route.get("dy_cells", 0))),
		"%.9f" % float(route.get("distance_m", 0.0)),
		str(int(route.get("destination_cell_index", -1))),
		"1" if bool(route.get("in_patch", false)) else "0",
		String(route.get("out_of_patch_rule", "")),
	])).sha256_text()

static func route_pool_hash(source: Array, schema: String, version: String) -> String:
	var hashes := PackedStringArray()
	for value in source:
		if not value is Dictionary:
			return ""
		hashes.append(String(Dictionary(value).get("route_hash", "")))
	hashes.sort()
	return (schema + "|" + version + "|route-pool|" + "|".join(hashes)).sha256_text()

static func _seed48(key: String) -> int:
	return key.sha256_text().substr(0, 12).hex_to_int()

static func _unit01(key: String) -> float:
	return float(key.sha256_text().substr(0, 12).hex_to_int()) / 281474976710655.0
