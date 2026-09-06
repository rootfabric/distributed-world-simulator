extends RefCounted
## Bounded deterministic 2D local field. This is research state, not canonical world authority.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Ports = preload("res://scripts/research/ecology/v2/organism_environment_ports_v1.gd")

static func create(owner_token: String = "research.patch", owner_epoch: int = 0, origin_mm: Array = [0, 0, 0], cell_size_mm: int = 1000, width: int = 4, depth: int = 4, initial_stock: Dictionary = F.stock(500000), capacities: Dictionary = F.stock(1000000), signals: Dictionary = F.signals()) -> Dictionary:
	if not C.identifier(owner_token) or not C.integer(owner_epoch, 0, F.MAX_OWNER_EPOCH) or not C.vector(origin_mm, 10000000):
		return {}
	if not C.integer(cell_size_mm, 1, 1000000) or not C.integer(width, 1, 64) or not C.integer(depth, 1, 64) or width * depth > F.MAX_CELLS:
		return {}
	if not F.valid_stock(initial_stock) or not F.valid_stock(capacities, false) or not F.valid_signals(signals):
		return {}
	for name in F.RESOURCES:
		if initial_stock[name] > capacities[name]:
			return {}
	var cells: Array = []
	for z in depth:
		for x in width:
			var index := z * width + x
			cells.append(F.seal_cell({"id": "c%04d" % index, "x": x, "z": z, "stocks": initial_stock.duplicate(true), "capacities": capacities.duplicate(true), "signals": signals.duplicate(true), "integrity_hash": ""}))
	var initial := F.totals(cells)
	var state := {"schema": F.FIELD_SCHEMA, "owner_token": owner_token, "owner_epoch": owner_epoch, "revision": 0, "tick": 0, "origin_mm": origin_mm.duplicate(), "cell_size_mm": cell_size_mm, "width": width, "depth": depth, "cells": cells, "ledger": {"initial": initial, "inputs": F.stock(), "outputs": F.stock(), "sinks": F.stock()}, "operation_count": 0, "integrity_hash": ""}
	state = F.seal_state(state)
	return state if F.validate_state(state).is_empty() else {}

static func state_hash(state: Dictionary) -> String:
	return state.integrity_hash if F.validate_read_header(state).is_empty() else ""

static func sample(state: Dictionary, request: Dictionary, supports: Array = [{"id": "ground", "kind": "plane_y", "position_mm": [0, 0, 0]}]) -> Dictionary:
	var error := F.validate_read_header(state)
	if not error.is_empty():
		return _fail(error)
	error = Ports.validate_sample_request(request)
	if not error.is_empty() or not F.validate_supports(supports):
		return _fail(error if not error.is_empty() else "SAMPLE_SUPPORTS")
	var indices := _indices(state, request.position_mm, request.extent_mm)
	if indices.is_empty():
		return _fail("SAMPLE_OUT_OF_BOUNDS")
	var resources := F.stock()
	var capacities := F.stock()
	var signal_totals := {"light": 0, "temperature": 0, "competition": 0, "mechanical": 0}
	var ids: Array = []
	for index in indices:
		var cell: Dictionary = state.cells[index]
		if not F.valid_cell(cell, index, state.width):
			return _fail("SAMPLE_CELL_INTEGRITY")
		ids.append(cell.id)
		for name in F.RESOURCES:
			resources[name] += cell.stocks[name]
			capacities[name] += cell.capacities[name]
		for name in F.SIGNALS:
			signal_totals[name] += cell.signals[name]
	var channels := {"light": 0, "water": 0, "temperature": 0, "competition": 0, "mechanical": 0}
	channels.water = int(resources.water_mg * 1000 / maxi(1, capacities.water_mg))
	for name in F.SIGNALS:
		channels[name] = int(signal_totals[name] / indices.size())
	var out := {"schema": F.SAMPLE_SCHEMA, "channels": channels, "resources": resources, "capacities": capacities, "supports": supports.duplicate(true), "source": {"owner_token": state.owner_token, "owner_epoch": state.owner_epoch, "revision": state.revision, "tick": state.tick, "field_hash": state_hash(state), "cells": ids}}
	return {"success": F.validate_sample(out).is_empty(), "sample": out, "visited_cells": indices.size()}

static func allocate_demands(source: Dictionary, demands: Array, owner_token: String, owner_epoch: int, revision: int) -> Dictionary:
	var pre := _write_precondition(source, owner_token, owner_epoch, revision)
	if not pre.is_empty():
		return _fail(pre)
	if demands.is_empty():
		return _fail("DEMAND_BATCH_EMPTY")
	if demands.size() > F.MAX_BATCH:
		return _fail("DEMAND_BATCH_LIMIT")
	if source.operation_count > C.MAX_INT - demands.size():
		return _fail("OPERATION_COUNT_LIMIT")
	var normalized: Array = []
	var seen := {}
	for demand in demands:
		var error := Ports.validate_demand(demand)
		if not error.is_empty() or seen.has(demand.request_id):
			return _fail(error if not error.is_empty() else "DUPLICATE_REQUEST")
		seen[demand.request_id] = true
		var indices := _indices(source, demand.position_mm, demand.extent_mm)
		if indices.is_empty():
			return _fail("DEMAND_OUT_OF_BOUNDS")
		normalized.append({"demand": demand.duplicate(true), "indices": indices})
	normalized.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.demand.request_id < b.demand.request_id)
	var claim_buckets := {}
	var grants := {}
	for item in normalized:
		var d: Dictionary = item.demand
		grants[d.request_id] = {"request_id": d.request_id, "organism_id": d.organism_id, "resource": d.resource, "requested": d.amount, "granted": 0, "unmet": d.amount}
		var count: int = item.indices.size()
		var base: int = int(d.amount / count)
		var remainder: int = d.amount % count
		for i in count:
			var claim := base + (1 if i < remainder else 0)
			if claim == 0:
				continue
			var index: int = item.indices[i]
			var key := "%04d|%s" % [index, d.resource]
			if not claim_buckets.has(key):
				claim_buckets[key] = []
			claim_buckets[key].append({"request_id": d.request_id, "amount": claim})
	var state := source.duplicate(true)
	var keys: Array = claim_buckets.keys()
	keys.sort()
	for key in keys:
		var parts: PackedStringArray = String(key).split("|")
		var index := int(parts[0])
		var resource := String(parts[1])
		var claims: Array = claim_buckets[key]
		claims.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.request_id < b.request_id)
		var total_claim := 0
		for claim in claims:
			total_claim += claim.amount
		var available: int = state.cells[index].stocks[resource]
		var target := mini(available, total_claim)
		var used := 0
		var cell_grants: Array = []
		for claim in claims:
			var amount: int = claim.amount if total_claim <= available else int(target * claim.amount / total_claim)
			cell_grants.append({"request_id": claim.request_id, "amount": amount, "claim": claim.amount})
			used += amount
		var leftover := target - used
		for grant in cell_grants:
			if leftover <= 0:
				break
			if grant.amount < grant.claim:
				grant.amount += 1
				leftover -= 1
		for grant in cell_grants:
			if grant.amount <= 0:
				continue
			state.cells[index].stocks[resource] -= grant.amount
			state.ledger.outputs[resource] += grant.amount
			grants[grant.request_id].granted += grant.amount
	# Residual sweep: the primary pass is per-cell pro-rata. If a demand still has unmet
	# quantity while another reachable cell retains stock, consume that residual in stable
	# request/cell order so a sparse cell does not strand accessible stock.
	for item in normalized:
		var d: Dictionary = item.demand
		var remaining: int = grants[d.request_id].requested - grants[d.request_id].granted
		if remaining <= 0:
			continue
		for index in item.indices:
			var available: int = state.cells[index].stocks[d.resource]
			var extra := mini(available, remaining)
			if extra <= 0:
				continue
			state.cells[index].stocks[d.resource] -= extra
			state.ledger.outputs[d.resource] += extra
			grants[d.request_id].granted += extra
			remaining -= extra
			if remaining == 0:
				break
	for id in grants:
		grants[id].unmet = grants[id].requested - grants[id].granted
	state.revision += 1
	state.operation_count += normalized.size()
	state = _seal_mutated_state(state)
	var state_error := F.validate_state(state)
	if not state_error.is_empty():
		return _fail(state_error)
	var result_grants: Array = grants.values()
	result_grants.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.request_id < b.request_id)
	return {"success": true, "state": state, "grants": result_grants, "revision": state.revision, "state_hash": state_hash(state)}

static func apply_effects(source: Dictionary, effects: Array, owner_token: String, owner_epoch: int, revision: int) -> Dictionary:
	var pre := _write_precondition(source, owner_token, owner_epoch, revision)
	if not pre.is_empty():
		return _fail(pre)
	if effects.is_empty():
		return _fail("EFFECT_BATCH_EMPTY")
	if effects.size() > F.MAX_BATCH:
		return _fail("EFFECT_BATCH_LIMIT")
	if source.operation_count > C.MAX_INT - effects.size():
		return _fail("OPERATION_COUNT_LIMIT")
	var normalized: Array = []
	var seen := {}
	for effect in effects:
		var error := Ports.validate_effect(effect)
		if not error.is_empty() or seen.has(effect.effect_id):
			return _fail(error if not error.is_empty() else "DUPLICATE_EFFECT")
		seen[effect.effect_id] = true
		var indices := _indices(source, effect.position_mm, effect.extent_mm)
		if indices.is_empty():
			return _fail("EFFECT_OUT_OF_BOUNDS")
		normalized.append({"effect": effect.duplicate(true), "indices": indices})
	normalized.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.effect.effect_id < b.effect.effect_id)
	var state := source.duplicate(true)
	var applied: Array = []
	for item in normalized:
		var e: Dictionary = item.effect
		var remaining: int = e.amount
		var cells: Array = item.indices
		if e.mode == "deposit":
			var free := 0
			for index in cells:
				free += state.cells[index].capacities[e.resource] - state.cells[index].stocks[e.resource]
			if free < e.amount:
				return _fail("FIELD_CAPACITY")
			for index in cells:
				var room: int = state.cells[index].capacities[e.resource] - state.cells[index].stocks[e.resource]
				var amount := mini(room, remaining)
				state.cells[index].stocks[e.resource] += amount
				remaining -= amount
				if remaining == 0: break
			state.ledger.inputs[e.resource] += e.amount
		else:
			var available := 0
			for index in cells:
				available += state.cells[index].stocks[e.resource]
			if available < e.amount:
				return _fail("FIELD_STOCK")
			for index in cells:
				var amount := mini(state.cells[index].stocks[e.resource], remaining)
				state.cells[index].stocks[e.resource] -= amount
				remaining -= amount
				if remaining == 0: break
			state.ledger.sinks[e.resource] += e.amount
		applied.append({"effect_id": e.effect_id, "mode": e.mode, "resource": e.resource, "amount": e.amount, "source_kind": e.source_kind})
	state.revision += 1
	state.operation_count += normalized.size()
	state = _seal_mutated_state(state)
	var state_error := F.validate_state(state)
	if not state_error.is_empty():
		return _fail(state_error)
	return {"success": true, "state": state, "applied": applied, "revision": state.revision, "state_hash": state_hash(state)}


static func set_cell_signals(source: Dictionary, x: int, z: int, signals: Dictionary, owner_token: String, owner_epoch: int, revision: int) -> Dictionary:
	var pre := _write_precondition(source, owner_token, owner_epoch, revision)
	if not pre.is_empty(): return _fail(pre)
	if not F.valid_signals(signals) or x < 0 or z < 0 or x >= source.width or z >= source.depth: return _fail("CELL_SIGNALS")
	if source.operation_count >= C.MAX_INT: return _fail("OPERATION_COUNT_LIMIT")
	var state := source.duplicate(true)
	state.cells[z * state.width + x].signals = signals.duplicate(true)
	state.revision += 1
	state.operation_count += 1
	state = _seal_mutated_state(state)
	return {"success": true, "state": state, "revision": state.revision, "state_hash": state_hash(state)} if F.validate_state(state).is_empty() else _fail("CELL_SIGNAL_STATE")

static func set_signals(source: Dictionary, signals: Dictionary, owner_token: String, owner_epoch: int, revision: int) -> Dictionary:
	var pre := _write_precondition(source, owner_token, owner_epoch, revision)
	if not pre.is_empty(): return _fail(pre)
	if not F.valid_signals(signals): return _fail("SIGNALS")
	if source.operation_count >= C.MAX_INT: return _fail("OPERATION_COUNT_LIMIT")
	var state := source.duplicate(true)
	for cell in state.cells: cell.signals = signals.duplicate(true)
	state.revision += 1
	state.operation_count += 1
	state = _seal_mutated_state(state)
	return {"success": true, "state": state, "revision": state.revision, "state_hash": state_hash(state)} if F.validate_state(state).is_empty() else _fail("SIGNAL_STATE")

static func advance_tick(source: Dictionary, owner_token: String, owner_epoch: int, revision: int) -> Dictionary:
	var pre := _write_precondition(source, owner_token, owner_epoch, revision)
	if not pre.is_empty(): return _fail(pre)
	if source.tick >= F.MAX_TICK: return _fail("TICK_LIMIT")
	if source.operation_count >= C.MAX_INT: return _fail("OPERATION_COUNT_LIMIT")
	var state := source.duplicate(true)
	state.tick += 1
	state.revision += 1
	state.operation_count += 1
	state = _seal_mutated_state(state)
	return {"success": true, "state": state, "revision": state.revision, "state_hash": state_hash(state)} if F.validate_state(state).is_empty() else _fail("TICK_STATE")

static func _seal_mutated_state(source: Dictionary) -> Dictionary:
	var state := source.duplicate(true)
	for i in state.cells.size():
		state.cells[i] = F.seal_cell(state.cells[i])
	return F.seal_state(state)

static func _write_precondition(state: Dictionary, owner_token: String, owner_epoch: int, revision: int) -> String:
	var error := F.validate_state(state)
	if not error.is_empty(): return error
	if owner_token != state.owner_token: return "STALE_OWNER"
	if owner_epoch != state.owner_epoch: return "STALE_OWNER_EPOCH"
	if revision != state.revision: return "STALE_REVISION"
	if state.revision >= F.MAX_REVISION: return "REVISION_LIMIT"
	return ""

static func _indices(state: Dictionary, position_mm: Array, extent_mm: int) -> Array:
	if not C.vector(position_mm, 10000000) or not C.integer(extent_mm, 0, 1000000): return []
	var min_x := _floor_div(position_mm[0] - extent_mm - state.origin_mm[0], state.cell_size_mm)
	var max_x := _floor_div(position_mm[0] + extent_mm - state.origin_mm[0], state.cell_size_mm)
	var min_z := _floor_div(position_mm[2] - extent_mm - state.origin_mm[2], state.cell_size_mm)
	var max_z := _floor_div(position_mm[2] + extent_mm - state.origin_mm[2], state.cell_size_mm)
	if max_x < 0 or max_z < 0 or min_x >= state.width or min_z >= state.depth: return []
	min_x = clampi(min_x, 0, state.width - 1); max_x = clampi(max_x, 0, state.width - 1)
	min_z = clampi(min_z, 0, state.depth - 1); max_z = clampi(max_z, 0, state.depth - 1)
	var out: Array = []
	for z in range(min_z, max_z + 1):
		for x in range(min_x, max_x + 1):
			out.append(z * state.width + x)
	return out

static func _floor_div(value: int, divisor: int) -> int:
	if value >= 0: return int(value / divisor)
	return -int((-value + divisor - 1) / divisor)

static func _fail(error: String) -> Dictionary:
	return {"success": false, "error": error}
