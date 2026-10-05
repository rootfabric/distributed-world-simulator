extends RefCounted
## ECO ARCH2 A13 fidelity-aware scheduler R1.
##
## This is scheduler-only state. It inherits A9 representation semantics:
## FULL/REDUCED retain exact history, PATCH does not. It never approximates
## biology, owns no resource state and never enters Runtime/checkpoint bytes.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Spatial = preload("res://scripts/research/ecology/v2/population_spatial_workset_plan_v1.gd")

const SCHEMA := "dws.ecology.fidelity-schedule-plan.v1"
const MODE_FULL := "FULL"
const MODE_REDUCED := "REDUCED"
const MODE_PATCH := "PATCH"
const MODES := [MODE_FULL, MODE_REDUCED, MODE_PATCH]

const DEFAULT_REDUCED_CADENCE_TICKS := 4
const DEFAULT_PATCH_CADENCE_TICKS := 16
const MAX_CADENCE_TICKS := 64
const MAX_CATCH_UP_TICKS := 64

const PLAN_KEYS := [
	"schema",
	"committed_scheduler_tick",
	"target_scheduler_tick",
	"debt_ticks",
	"reduced_cadence_ticks",
	"patch_cadence_ticks",
	"tile_span_cells",
	"max_members",
	"field_geometry_hash",
	"population_hash",
	"spatial_plan_hash",
	"fidelity_overrides",
	"tile_count",
	"full_tile_count",
	"reduced_tile_count",
	"patch_tile_count",
	"global_commit_ready",
	"catch_up_ticks",
	"refinement_required",
	"refinement_addresses",
	"tiles",
]

const OVERRIDE_KEYS := ["address", "fidelity"]
const TILE_KEYS := [
	"address",
	"fidelity",
	"cadence_ticks",
	"next_due_scheduler_tick",
	"due",
	"exact_history_retained",
	"member_count",
	"shard_count",
]

static func create(field: Dictionary, population: Array, fidelity_overrides: Dictionary,
		committed_scheduler_tick: int, target_scheduler_tick: int,
		reduced_cadence_ticks: int = DEFAULT_REDUCED_CADENCE_TICKS,
		patch_cadence_ticks: int = DEFAULT_PATCH_CADENCE_TICKS,
		tile_span_cells: int = Spatial.DEFAULT_TILE_SPAN_CELLS,
		max_members: int = Spatial.DEFAULT_MAX_MEMBERS) -> Dictionary:
	var plan := _build(
		field, population, fidelity_overrides,
		committed_scheduler_tick, target_scheduler_tick,
		reduced_cadence_ticks, patch_cadence_ticks,
		tile_span_cells, max_members)
	if plan.is_empty():
		return {}
	return plan if validate(plan, field, population).is_empty() else {}

static func validate(plan: Variant, field: Dictionary, population: Array) -> String:
	if not C.keys(plan, PLAN_KEYS) or String(plan.schema) != SCHEMA:
		return "FIDELITY_PLAN_SCHEMA"
	if not C.integer(plan.committed_scheduler_tick, 0, F.MAX_TICK) 			or not C.integer(plan.target_scheduler_tick, 0, F.MAX_TICK):
		return "FIDELITY_PLAN_TICKS"
	if int(plan.target_scheduler_tick) < int(plan.committed_scheduler_tick):
		return "FIDELITY_PLAN_TICKS"
	if not C.integer(plan.debt_ticks, 0, MAX_CATCH_UP_TICKS):
		return "FIDELITY_PLAN_DEBT"
	if int(plan.debt_ticks) != int(plan.target_scheduler_tick) - int(plan.committed_scheduler_tick):
		return "FIDELITY_PLAN_DEBT"
	if not C.integer(plan.reduced_cadence_ticks, 1, MAX_CADENCE_TICKS) 			or not C.integer(plan.patch_cadence_ticks, 1, MAX_CADENCE_TICKS):
		return "FIDELITY_PLAN_CADENCE"
	if not C.integer(plan.tile_span_cells, 1, Spatial.MAX_TILE_SPAN_CELLS):
		return "FIDELITY_PLAN_TILE_SPAN"
	if not C.integer(plan.max_members, 1, Spatial.MAX_MEMBERS):
		return "FIDELITY_PLAN_MAX_MEMBERS"
	if not plan.fidelity_overrides is Array or not plan.tiles is Array 			or not plan.refinement_addresses is Array:
		return "FIDELITY_PLAN_COLLECTIONS"
	if not C.integer(plan.tile_count, 1, Spatial.MAX_MEMBERS) 			or not C.integer(plan.full_tile_count, 0, Spatial.MAX_MEMBERS) 			or not C.integer(plan.reduced_tile_count, 0, Spatial.MAX_MEMBERS) 			or not C.integer(plan.patch_tile_count, 0, Spatial.MAX_MEMBERS):
		return "FIDELITY_PLAN_COUNTS"
	if int(plan.full_tile_count) + int(plan.reduced_tile_count) + int(plan.patch_tile_count) != int(plan.tile_count):
		return "FIDELITY_PLAN_COUNTS"
	if not plan.global_commit_ready is bool or not plan.refinement_required is bool:
		return "FIDELITY_PLAN_FLAGS"
	if not C.integer(plan.catch_up_ticks, 0, MAX_CATCH_UP_TICKS):
		return "FIDELITY_PLAN_CATCH_UP"

	var prior_override := ""
	for override in plan.fidelity_overrides:
		if not C.keys(override, OVERRIDE_KEYS):
			return "FIDELITY_PLAN_OVERRIDE_SCHEMA"
		var address := String(override.address)
		var mode := String(override.fidelity)
		if address.is_empty() or address <= prior_override or mode not in MODES:
			return "FIDELITY_PLAN_OVERRIDE_ORDER"
		prior_override = address

	var prior_tile := ""
	for tile in plan.tiles:
		if not C.keys(tile, TILE_KEYS):
			return "FIDELITY_PLAN_TILE_SCHEMA"
		var address := String(tile.address)
		var mode := String(tile.fidelity)
		if address.is_empty() or address <= prior_tile or mode not in MODES:
			return "FIDELITY_PLAN_TILE_ORDER"
		prior_tile = address
		if not C.integer(tile.cadence_ticks, 1, MAX_CADENCE_TICKS) 				or not C.integer(tile.next_due_scheduler_tick, 0, F.MAX_TICK):
			return "FIDELITY_PLAN_TILE_CADENCE"
		if not tile.due is bool or not tile.exact_history_retained is bool:
			return "FIDELITY_PLAN_TILE_FLAGS"
		if not C.integer(tile.member_count, 1, Spatial.MAX_MEMBERS) 				or not C.integer(tile.shard_count, 1, Spatial.MAX_MEMBERS):
			return "FIDELITY_PLAN_TILE_COUNTS"
		if bool(tile.exact_history_retained) != (mode != MODE_PATCH):
			return "FIDELITY_PLAN_HISTORY"

	var override_input := {}
	for override in plan.fidelity_overrides:
		override_input[String(override.address)] = String(override.fidelity)
	var expected := _build(
		field, population, override_input,
		int(plan.committed_scheduler_tick), int(plan.target_scheduler_tick),
		int(plan.reduced_cadence_ticks), int(plan.patch_cadence_ticks),
		int(plan.tile_span_cells), int(plan.max_members))
	if expected.is_empty():
		return "FIDELITY_PLAN_INPUT"
	if C.encode(plan) != C.encode(expected):
		return "FIDELITY_PLAN_CONTENT"
	return "FIDELITY_PLAN_NONCANONICAL" if C.encode(plan).is_empty() else ""

static func _build(field: Dictionary, population: Array, fidelity_overrides: Dictionary,
		committed_scheduler_tick: int, target_scheduler_tick: int,
		reduced_cadence_ticks: int, patch_cadence_ticks: int,
		tile_span_cells: int, max_members: int) -> Dictionary:
	if not C.integer(committed_scheduler_tick, 0, F.MAX_TICK) 			or not C.integer(target_scheduler_tick, 0, F.MAX_TICK):
		return {}
	if target_scheduler_tick < committed_scheduler_tick:
		return {}
	var debt_ticks := target_scheduler_tick - committed_scheduler_tick
	if debt_ticks > MAX_CATCH_UP_TICKS:
		return {}
	if reduced_cadence_ticks < 1 or reduced_cadence_ticks > MAX_CADENCE_TICKS 			or patch_cadence_ticks < 1 or patch_cadence_ticks > MAX_CADENCE_TICKS:
		return {}
	if not fidelity_overrides is Dictionary:
		return {}

	var spatial := Spatial.create(field, population, tile_span_cells, max_members)
	if spatial.is_empty():
		return {}

	var summary := {}
	for unit in spatial.worksets:
		var address := String(unit.address)
		if not summary.has(address):
			summary[address] = {"member_count": 0, "shard_count": 0}
		summary[address].member_count = int(summary[address].member_count) + unit.member_ids.size()
		summary[address].shard_count = int(summary[address].shard_count) + 1
	var addresses: Array = summary.keys()
	addresses.sort()
	if addresses.is_empty():
		return {}

	var valid_addresses := {}
	for raw_address in addresses:
		valid_addresses[String(raw_address)] = true

	var normalized_overrides: Array = []
	for raw_address in fidelity_overrides.keys():
		if not raw_address is String:
			return {}
		var address := String(raw_address)
		var mode_value: Variant = fidelity_overrides[raw_address]
		if not mode_value is String:
			return {}
		var mode := String(mode_value)
		if not valid_addresses.has(address) or mode not in MODES:
			return {}
		normalized_overrides.append({"address": address, "fidelity": mode})
	normalized_overrides.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.address < b.address)

	var mode_by_address := {}
	for override in normalized_overrides:
		mode_by_address[String(override.address)] = String(override.fidelity)

	var tiles: Array = []
	var full_count := 0
	var reduced_count := 0
	var patch_count := 0
	var refinement_addresses: Array = []
	for raw_address in addresses:
		var address := String(raw_address)
		var mode := String(mode_by_address.get(address, MODE_FULL))
		var cadence := 1
		if mode == MODE_REDUCED:
			cadence = reduced_cadence_ticks
			reduced_count += 1
		elif mode == MODE_PATCH:
			cadence = patch_cadence_ticks
			patch_count += 1
		else:
			full_count += 1
		var next_due := committed_scheduler_tick + cadence
		if next_due > F.MAX_TICK:
			return {}
		var due := target_scheduler_tick >= next_due
		if mode == MODE_PATCH and debt_ticks > 0 and due:
			refinement_addresses.append(address)
		tiles.append({
			"address": address,
			"fidelity": mode,
			"cadence_ticks": cadence,
			"next_due_scheduler_tick": next_due,
			"due": due,
			"exact_history_retained": mode != MODE_PATCH,
			"member_count": int(summary[address].member_count),
			"shard_count": int(summary[address].shard_count),
		})

	var refinement_required := not refinement_addresses.is_empty()
	var ready := false
	var catch_up := 0
	if debt_ticks == 0:
		ready = true
	elif patch_count > 0:
		# A PATCH source has no exact historical individuals. A global ecology
		# tick cannot commit around it because A5 owns one population-wide
		# allocator. Before PATCH cadence we defer; at cadence we request exact
		# external refinement. We never silently read current FULL truth as PATCH.
		ready = false
	elif reduced_count > 0:
		ready = debt_ticks >= reduced_cadence_ticks
		catch_up = debt_ticks if ready else 0
	else:
		ready = true
		catch_up = debt_ticks

	return {
		"schema": SCHEMA,
		"committed_scheduler_tick": committed_scheduler_tick,
		"target_scheduler_tick": target_scheduler_tick,
		"debt_ticks": debt_ticks,
		"reduced_cadence_ticks": reduced_cadence_ticks,
		"patch_cadence_ticks": patch_cadence_ticks,
		"tile_span_cells": int(spatial.tile_span_cells),
		"max_members": int(spatial.max_members),
		"field_geometry_hash": String(spatial.field_geometry_hash),
		"population_hash": String(spatial.population_hash),
		"spatial_plan_hash": C.digest(spatial),
		"fidelity_overrides": normalized_overrides,
		"tile_count": tiles.size(),
		"full_tile_count": full_count,
		"reduced_tile_count": reduced_count,
		"patch_tile_count": patch_count,
		"global_commit_ready": ready,
		"catch_up_ticks": catch_up,
		"refinement_required": refinement_required,
		"refinement_addresses": refinement_addresses,
		"tiles": tiles,
	}
