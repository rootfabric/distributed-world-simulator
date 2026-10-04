extends RefCounted
## ECO ARCH2 A13 active/sleeping cadence scheduler R1.
##
## This is scheduler-only state. It classifies stable spatial addresses as
## ACTIVE/SLEEPING and decides when deferred canonical work is due. It never
## becomes ecology truth and never enters Runtime/checkpoint bytes.
##
## R1 intentionally preserves exact global ecology coupling: while any
## SLEEPING tile carries debt, a canonical tick cannot be committed by
## advancing ACTIVE tiles alone. At wake, EcologyRuntime replays every missed
## canonical tick through the ordinary spatial scheduler and its ONE GLOBAL
## resource allocation barrier.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Spatial = preload("res://scripts/research/ecology/v2/population_spatial_workset_plan_v1.gd")

const SCHEMA := "dws.ecology.activity-cadence-plan.v1"
const CLASS_ACTIVE := "ACTIVE"
const CLASS_SLEEPING := "SLEEPING"
const DEFAULT_SLEEP_CADENCE_TICKS := 4
const MAX_SLEEP_CADENCE_TICKS := 64
const MAX_CATCH_UP_TICKS := 64

const PLAN_KEYS := [
	"schema",
	"committed_scheduler_tick",
	"target_scheduler_tick",
	"debt_ticks",
	"sleep_cadence_ticks",
	"tile_span_cells",
	"max_members",
	"field_geometry_hash",
	"population_hash",
	"spatial_plan_hash",
	"active_addresses",
	"tile_count",
	"active_tile_count",
	"sleeping_tile_count",
	"global_commit_ready",
	"catch_up_ticks",
	"tiles",
]
const TILE_KEYS := [
	"address",
	"classification",
	"cadence_ticks",
	"next_due_scheduler_tick",
	"due",
	"member_count",
	"shard_count",
]

static func create(field: Dictionary, population: Array, active_addresses: Array,
		committed_scheduler_tick: int, target_scheduler_tick: int,
		sleep_cadence_ticks: int = DEFAULT_SLEEP_CADENCE_TICKS,
		tile_span_cells: int = Spatial.DEFAULT_TILE_SPAN_CELLS,
		max_members: int = Spatial.DEFAULT_MAX_MEMBERS) -> Dictionary:
	var plan := _build(
		field, population, active_addresses,
		committed_scheduler_tick, target_scheduler_tick,
		sleep_cadence_ticks, tile_span_cells, max_members)
	if plan.is_empty():
		return {}
	return plan if validate(plan, field, population).is_empty() else {}

static func validate(plan: Variant, field: Dictionary, population: Array) -> String:
	if not C.keys(plan, PLAN_KEYS) or String(plan.schema) != SCHEMA:
		return "ACTIVITY_PLAN_SCHEMA"
	if not C.integer(plan.committed_scheduler_tick, 0, F.MAX_TICK) \
			or not C.integer(plan.target_scheduler_tick, 0, F.MAX_TICK):
		return "ACTIVITY_PLAN_TICKS"
	if int(plan.target_scheduler_tick) < int(plan.committed_scheduler_tick):
		return "ACTIVITY_PLAN_TICKS"
	if not C.integer(plan.debt_ticks, 0, MAX_CATCH_UP_TICKS):
		return "ACTIVITY_PLAN_DEBT"
	if int(plan.debt_ticks) != int(plan.target_scheduler_tick) - int(plan.committed_scheduler_tick):
		return "ACTIVITY_PLAN_DEBT"
	if not C.integer(plan.sleep_cadence_ticks, 1, MAX_SLEEP_CADENCE_TICKS):
		return "ACTIVITY_PLAN_CADENCE"
	if not C.integer(plan.tile_span_cells, 1, Spatial.MAX_TILE_SPAN_CELLS):
		return "ACTIVITY_PLAN_TILE_SPAN"
	if not C.integer(plan.max_members, 1, Spatial.MAX_MEMBERS):
		return "ACTIVITY_PLAN_MAX_MEMBERS"
	if not plan.active_addresses is Array or not plan.tiles is Array:
		return "ACTIVITY_PLAN_COLLECTIONS"
	if not C.integer(plan.tile_count, 1, Spatial.MAX_MEMBERS) \
			or not C.integer(plan.active_tile_count, 0, Spatial.MAX_MEMBERS) \
			or not C.integer(plan.sleeping_tile_count, 0, Spatial.MAX_MEMBERS):
		return "ACTIVITY_PLAN_COUNTS"
	if int(plan.active_tile_count) + int(plan.sleeping_tile_count) != int(plan.tile_count):
		return "ACTIVITY_PLAN_COUNTS"
	if not plan.global_commit_ready is bool:
		return "ACTIVITY_PLAN_READY"
	if not C.integer(plan.catch_up_ticks, 0, MAX_CATCH_UP_TICKS):
		return "ACTIVITY_PLAN_CATCH_UP"
	for tile in plan.tiles:
		if not C.keys(tile, TILE_KEYS):
			return "ACTIVITY_PLAN_TILE_SCHEMA"
		if String(tile.classification) not in [CLASS_ACTIVE, CLASS_SLEEPING]:
			return "ACTIVITY_PLAN_TILE_CLASS"
		if not C.integer(tile.cadence_ticks, 1, MAX_SLEEP_CADENCE_TICKS):
			return "ACTIVITY_PLAN_TILE_CADENCE"
		if not C.integer(tile.next_due_scheduler_tick, 0, F.MAX_TICK):
			return "ACTIVITY_PLAN_TILE_DUE_TICK"
		if not tile.due is bool:
			return "ACTIVITY_PLAN_TILE_DUE"
		if not C.integer(tile.member_count, 1, Spatial.MAX_MEMBERS) \
				or not C.integer(tile.shard_count, 1, Spatial.MAX_MEMBERS):
			return "ACTIVITY_PLAN_TILE_COUNTS"

	var expected := _build(
		field, population, plan.active_addresses,
		int(plan.committed_scheduler_tick), int(plan.target_scheduler_tick),
		int(plan.sleep_cadence_ticks), int(plan.tile_span_cells), int(plan.max_members))
	if expected.is_empty():
		return "ACTIVITY_PLAN_INPUT"
	if C.encode(plan) != C.encode(expected):
		return "ACTIVITY_PLAN_CONTENT"
	return "ACTIVITY_PLAN_NONCANONICAL" if C.encode(plan).is_empty() else ""

static func _build(field: Dictionary, population: Array, active_addresses: Array,
		committed_scheduler_tick: int, target_scheduler_tick: int,
		sleep_cadence_ticks: int, tile_span_cells: int, max_members: int) -> Dictionary:
	if not C.integer(committed_scheduler_tick, 0, F.MAX_TICK) \
			or not C.integer(target_scheduler_tick, 0, F.MAX_TICK):
		return {}
	if target_scheduler_tick < committed_scheduler_tick:
		return {}
	var debt_ticks := target_scheduler_tick - committed_scheduler_tick
	if debt_ticks > MAX_CATCH_UP_TICKS:
		return {}
	if sleep_cadence_ticks < 1 or sleep_cadence_ticks > MAX_SLEEP_CADENCE_TICKS:
		return {}
	if not active_addresses is Array:
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
	for address in addresses:
		valid_addresses[String(address)] = true
	var active_set := {}
	for raw_address in active_addresses:
		if not raw_address is String:
			return {}
		var address := String(raw_address)
		if not valid_addresses.has(address):
			return {}
		active_set[address] = true
	var normalized_active: Array = active_set.keys()
	normalized_active.sort()

	var tiles: Array = []
	var active_count := 0
	var sleeping_count := 0
	for raw_address in addresses:
		var address := String(raw_address)
		var is_active := active_set.has(address)
		var cadence := 1 if is_active else sleep_cadence_ticks
		var next_due := committed_scheduler_tick + cadence
		if next_due > F.MAX_TICK:
			return {}
		var due := target_scheduler_tick >= next_due
		if is_active:
			active_count += 1
		else:
			sleeping_count += 1
		tiles.append({
			"address": address,
			"classification": CLASS_ACTIVE if is_active else CLASS_SLEEPING,
			"cadence_ticks": cadence,
			"next_due_scheduler_tick": next_due,
			"due": due,
			"member_count": int(summary[address].member_count),
			"shard_count": int(summary[address].shard_count),
		})

	# Exact R1 rule: if sleeping work exists, no canonical commit may get ahead
	# of it. Once its cadence is due, every missed canonical tick is replayed.
	var ready := debt_ticks == 0 or sleeping_count == 0 or debt_ticks >= sleep_cadence_ticks
	var catch_up := debt_ticks if ready else 0
	return {
		"schema": SCHEMA,
		"committed_scheduler_tick": committed_scheduler_tick,
		"target_scheduler_tick": target_scheduler_tick,
		"debt_ticks": debt_ticks,
		"sleep_cadence_ticks": sleep_cadence_ticks,
		"tile_span_cells": int(spatial.tile_span_cells),
		"max_members": int(spatial.max_members),
		"field_geometry_hash": String(spatial.field_geometry_hash),
		"population_hash": String(spatial.population_hash),
		"spatial_plan_hash": C.digest(spatial),
		"active_addresses": normalized_active,
		"tile_count": tiles.size(),
		"active_tile_count": active_count,
		"sleeping_tile_count": sleeping_count,
		"global_commit_ready": ready,
		"catch_up_ticks": catch_up,
		"tiles": tiles,
	}
