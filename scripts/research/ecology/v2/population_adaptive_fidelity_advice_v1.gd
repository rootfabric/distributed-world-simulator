extends RefCounted
## A14.2 R1: conservative, noncanonical advisory scheduler.
##
## One A5 global allocator forbids exact advancement of active worksets while
## sleeping peers are in debt. R1 therefore defers ONLY when every tile is
## inactive. Any active tile forces all-FULL exact execution.
## PATCH requires external A9 historical refinement/provenance and is NEVER
## selected automatically from a live exact population.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Fidelity = preload("res://scripts/research/ecology/v2/population_fidelity_schedule_plan_v1.gd")
const Spatial = preload("res://scripts/research/ecology/v2/population_spatial_workset_plan_v1.gd")

const SCHEMA := "dws.ecology.adaptive-fidelity-advice.v1"
const DEFAULT_CADENCE := 4
const MAX_COST_US := 1000000000
const MAX_BUDGET_US := 1000000000
const ADVICE_KEYS := [
	"schema", "committed_tick", "target_tick", "budget_us",
	"estimated_full_tick_us", "active_addresses", "mode", "reason",
	"tile_span_cells", "max_members", "reduced_cadence_ticks",
	"spatial_plan_hash", "fidelity_plan",
]

static func create(field: Dictionary, population: Array,
		active_addresses: Array, estimated_full_tick_us: int, budget_us: int,
		committed_tick: int, target_tick: int,
		reduced_cadence_ticks: int = DEFAULT_CADENCE,
		tile_span_cells: int = Spatial.DEFAULT_TILE_SPAN_CELLS,
		max_members: int = Spatial.DEFAULT_MAX_MEMBERS) -> Dictionary:
	var advice := _build(field, population, active_addresses,
		estimated_full_tick_us, budget_us, committed_tick, target_tick,
		reduced_cadence_ticks, tile_span_cells, max_members)
	if advice.is_empty():
		return {}
	return advice if validate(advice, field, population).is_empty() else {}

static func validate(advice: Variant, field: Dictionary, population: Array) -> String:
	if not C.keys(advice, ADVICE_KEYS) or String(advice.schema) != SCHEMA:
		return "ADAPTIVE_SCHEMA"
	if not advice.active_addresses is Array or not advice.fidelity_plan is Dictionary:
		return "ADAPTIVE_TYPES"
	if not C.integer(advice.budget_us, 1, MAX_BUDGET_US) or not C.integer(
			advice.estimated_full_tick_us, 1, MAX_COST_US):
		return "ADAPTIVE_BUDGET"
	if not C.integer(advice.committed_tick, 0, 2147483647) or not C.integer(
			advice.target_tick, 0, 2147483647):
		return "ADAPTIVE_TICKS"
	if not C.integer(advice.reduced_cadence_ticks, 2, Fidelity.MAX_CADENCE_TICKS):
		return "ADAPTIVE_CADENCE"
	if not C.integer(advice.tile_span_cells, 1, Spatial.MAX_TILE_SPAN_CELLS) or not C.integer(
			advice.max_members, 1, Spatial.MAX_MEMBERS):
		return "ADAPTIVE_SPATIAL_PARAMETERS"
	var expected := _build(field, population, advice.active_addresses,
		int(advice.estimated_full_tick_us), int(advice.budget_us),
		int(advice.committed_tick), int(advice.target_tick),
		int(advice.reduced_cadence_ticks), int(advice.tile_span_cells),
		int(advice.max_members))
	if expected.is_empty() or C.encode(expected) != C.encode(advice):
		return "ADAPTIVE_CONTENT"
	var plan_error := Fidelity.validate(advice.fidelity_plan, field, population)
	if not plan_error.is_empty():
		return "ADAPTIVE_FIDELITY:" + plan_error
	return ""

static func _build(field: Dictionary, population: Array, active_addresses: Array,
		estimated_full_tick_us: int, budget_us: int,
		committed_tick: int, target_tick: int, reduced_cadence_ticks: int,
		tile_span_cells: int, max_members: int) -> Dictionary:
	if not C.integer(estimated_full_tick_us, 1, MAX_COST_US) or not C.integer(
			budget_us, 1, MAX_BUDGET_US):
		return {}
	if not C.integer(reduced_cadence_ticks, 2, Fidelity.MAX_CADENCE_TICKS):
		return {}
	if not active_addresses is Array:
		return {}
	if committed_tick < 0 or target_tick < committed_tick:
		return {}
	if target_tick - committed_tick > Fidelity.MAX_CATCH_UP_TICKS:
		return {}
	var spatial := Spatial.create(field, population, tile_span_cells, max_members)
	if spatial.is_empty():
		return {}
	var known := {}
	for unit in spatial.worksets:
		known[String(unit.address)] = true
	var active: Array = []
	var seen := {}
	for raw_address in active_addresses:
		if not raw_address is String:
			return {}
		var address := String(raw_address)
		if not known.has(address) or seen.has(address):
			return {}
		seen[address] = true
		active.append(address)
	active.sort()
	# A live active tile must never be held back by an automatically
	# classified REDUCED tile. Whole-world defer is permitted only if
	# NO tile is active, which preserves A5 global causal ordering.
	var reduced := active.is_empty() and estimated_full_tick_us > budget_us
	var overrides := {}
	if reduced:
		for address in known.keys():
			overrides[String(address)] = Fidelity.MODE_REDUCED
	var plan := Fidelity.create(field, population, overrides,
		committed_tick, target_tick, reduced_cadence_ticks,
		Fidelity.DEFAULT_PATCH_CADENCE_TICKS, tile_span_cells, max_members)
	if plan.is_empty():
		return {}
	return {
		"schema": SCHEMA,
		"committed_tick": committed_tick,
		"target_tick": target_tick,
		"budget_us": budget_us,
		"estimated_full_tick_us": estimated_full_tick_us,
		"active_addresses": active,
		"mode": Fidelity.MODE_REDUCED if reduced else Fidelity.MODE_FULL,
		"reason": "ALL_INACTIVE_OVER_BUDGET" if reduced else (
			"ACTIVE_GLOBAL_ALLOCATOR" if not active.is_empty() else "WITHIN_BUDGET"),
		"tile_span_cells": tile_span_cells,
		"max_members": max_members,
		"reduced_cadence_ticks": reduced_cadence_ticks,
		"spatial_plan_hash": C.digest(spatial),
		"fidelity_plan": plan,
	}
