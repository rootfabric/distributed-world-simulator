extends RefCounted
## ECO ARCH2 A14.3 R1 — deterministic PREPARATION queue only.
##
## These are scheduler-side budget grants for independent noncanonical
## preparation (not organism advance). Canonical A5 allocation is global;
## a selected tile MUST NOT be advanced independently. Inputs are explicit
## debt/telemetry snapshots, never wall-clock measurements or hidden RNG.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Spatial = preload("res://scripts/research/ecology/v2/population_spatial_workset_plan_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")

const SCHEMA := "dws.ecology.wake-priority-preparation.v1"
const MAX_BUDGET_US := 1000000000
const MAX_COST_US := 1000000000
const MAX_DEBT_UNITS := 1000000
const MAX_STARVATION_EPOCHS := 256
const PLAN_KEYS := [
	"schema", "spatial_plan_hash", "epoch", "starvation_after_epochs",
	"budget_us", "active_addresses", "debt_by_address",
	"cost_us_by_address", "last_served_epoch_by_address",
	"tile_span_cells", "max_members", "tickets", "priority_order",
	"selected_addresses", "spent_us", "remaining_us",
	"next_last_served_epoch_by_address",
]


static func create(field: Dictionary, population: Array,
		active_addresses: Array, debt_by_address: Dictionary,
		cost_us_by_address: Dictionary, last_served_epoch_by_address: Dictionary,
		budget_us: int, epoch: int, starvation_after_epochs: int = 4,
		tile_span_cells: int = Spatial.DEFAULT_TILE_SPAN_CELLS,
		max_members: int = Spatial.DEFAULT_MAX_MEMBERS) -> Dictionary:
	var plan := _build(
		field, population, active_addresses, debt_by_address,
		cost_us_by_address, last_served_epoch_by_address,
		budget_us, epoch, starvation_after_epochs, tile_span_cells, max_members)
	if plan.is_empty():
		return {}
	return plan if validate(plan, field, population).is_empty() else {}


static func validate(value: Variant, field: Dictionary, population: Array) -> String:
	if not C.keys(value, PLAN_KEYS) or String(value.schema) != SCHEMA:
		return "WAKE_PRIORITY_SCHEMA"
	if not value.active_addresses is Array or not value.debt_by_address is Dictionary \
			or not value.cost_us_by_address is Dictionary \
			or not value.last_served_epoch_by_address is Dictionary:
		return "WAKE_PRIORITY_INPUT_TYPES"
	if not C.integer(value.budget_us, 1, MAX_BUDGET_US) \
			or not C.integer(value.epoch, 0, F.MAX_TICK) \
			or not C.integer(value.starvation_after_epochs, 1, MAX_STARVATION_EPOCHS) \
			or not C.integer(value.tile_span_cells, 1, Spatial.MAX_TILE_SPAN_CELLS) \
			or not C.integer(value.max_members, 1, Spatial.MAX_MEMBERS):
		return "WAKE_PRIORITY_LIMITS"
	var expected := _build(
		field, population, value.active_addresses, value.debt_by_address,
		value.cost_us_by_address, value.last_served_epoch_by_address,
		int(value.budget_us), int(value.epoch),
		int(value.starvation_after_epochs),
		int(value.tile_span_cells), int(value.max_members))
	if expected.is_empty():
		return "WAKE_PRIORITY_INVALID_SOURCE"
	if C.encode(expected) != C.encode(value):
		return "WAKE_PRIORITY_CONTENT"
	return ""


static func _build(field: Dictionary, population: Array,
		active_addresses: Array, debt_by_address: Dictionary,
		cost_us_by_address: Dictionary, last_served_epoch_by_address: Dictionary,
		budget_us: int, epoch: int, starvation_after_epochs: int,
		tile_span_cells: int, max_members: int) -> Dictionary:
	if not C.integer(budget_us, 1, MAX_BUDGET_US) \
			or not C.integer(epoch, 0, F.MAX_TICK) \
			or not C.integer(starvation_after_epochs, 1, MAX_STARVATION_EPOCHS):
		return {}
	if not active_addresses is Array or not debt_by_address is Dictionary \
			or not cost_us_by_address is Dictionary \
			or not last_served_epoch_by_address is Dictionary:
		return {}
	var spatial := Spatial.create(field, population, tile_span_cells, max_members)
	if spatial.is_empty():
		return {}
	var known := {}
	for workset in spatial.worksets:
		known[String(workset.address)] = true
	var addresses: Array = known.keys()
	addresses.sort()
	if addresses.is_empty() or debt_by_address.size() != addresses.size() \
			or cost_us_by_address.size() != addresses.size() \
			or last_served_epoch_by_address.size() != addresses.size():
		return {}
	var active := {}
	var canonical_active: Array = []
	for raw in active_addresses:
		if not raw is String or not known.has(raw) or active.has(raw):
			return {}
		active[raw] = true
		canonical_active.append(raw)
	canonical_active.sort()
	var tickets: Array = []
	for raw in addresses:
		var address := String(raw)
		if not debt_by_address.has(address) or not cost_us_by_address.has(address) \
				or not last_served_epoch_by_address.has(address):
			return {}
		var debt: Variant = debt_by_address[address]
		var cost: Variant = cost_us_by_address[address]
		var last: Variant = last_served_epoch_by_address[address]
		if not C.integer(debt, 0, MAX_DEBT_UNITS) \
				or not C.integer(cost, 1, MAX_COST_US) \
				or not C.integer(last, 0, epoch):
			return {}
		var wait_epochs: int = epoch - int(last)
		tickets.append({
			"address": address,
			"active": active.has(address),
			"debt_units": int(debt),
			"cost_us": int(cost),
			"wait_epochs": wait_epochs,
			"starved": wait_epochs >= starvation_after_epochs and int(debt) > 0,
			"granted": false,
		})
	tickets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a.starved) != bool(b.starved):
			return bool(a.starved)
		if bool(a.starved) and int(a.wait_epochs) != int(b.wait_epochs):
			return int(a.wait_epochs) > int(b.wait_epochs)
		if bool(a.active) != bool(b.active):
			return bool(a.active)
		if int(a.debt_units) != int(b.debt_units):
			return int(a.debt_units) > int(b.debt_units)
		if int(a.wait_epochs) != int(b.wait_epochs):
			return int(a.wait_epochs) > int(b.wait_epochs)
		return String(a.address) < String(b.address))
	var order: Array = []
	var selected: Array = []
	var remaining: int = budget_us
	var next_last: Dictionary = last_served_epoch_by_address.duplicate(true)
	for ticket in tickets:
		if int(ticket.debt_units) == 0:
			continue
		order.append(String(ticket.address))
		if int(ticket.cost_us) <= remaining:
			ticket.granted = true
			selected.append(String(ticket.address))
			next_last[String(ticket.address)] = epoch
			remaining -= int(ticket.cost_us)
	return {
		"schema": SCHEMA,
		"spatial_plan_hash": C.digest(spatial),
		"epoch": epoch,
		"starvation_after_epochs": starvation_after_epochs,
		"budget_us": budget_us,
		"active_addresses": canonical_active,
		"debt_by_address": debt_by_address.duplicate(true),
		"cost_us_by_address": cost_us_by_address.duplicate(true),
		"last_served_epoch_by_address": last_served_epoch_by_address.duplicate(true),
		"tile_span_cells": tile_span_cells,
		"max_members": max_members,
		"tickets": tickets,
		"priority_order": order,
		"selected_addresses": selected,
		"spent_us": budget_us - remaining,
		"remaining_us": remaining,
		"next_last_served_epoch_by_address": next_last,
	}
