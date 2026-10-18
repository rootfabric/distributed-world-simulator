extends RefCounted
## ECO ARCH2 A14.6 R1: READ-ONLY A4 demand collision/frontier probe.
## Computes the conservative dependency graph of the existing GLOBAL
## Field.allocate_demands contract. This is a diagnostic hypothesis for R2,
## NOT an allocator, not a biological owner, and never an execution permit.
##
## The second residual pro-rata pass can bind demands in a bucket even if a
## first-pass claim rounds to ZERO. Therefore graph edges use EVERY covered
## cell/resource for each demand, NOT just its positive primary claims.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Ports = preload("res://scripts/research/ecology/v2/organism_environment_ports_v1.gd")

const SCHEMA := "dws.ecology.a14-6-allocation-frontier-probe.v1"
const MAX_ANALYSIS_LINKS := 131072

static func analyze(field: Dictionary, demands: Array) -> Dictionary:
	var error: String = F.validate_state(field)
	if not error.is_empty():
		return _fail("A14_6_FIELD:" + error)
	if demands.size() > F.MAX_BATCH:
		return _fail("A14_6_DEMAND_BATCH")
	var normalized: Array = []
	var seen := {}
	for d in demands:
		var d_error := Ports.validate_demand(d)
		if not d_error.is_empty():
			return _fail("A14_6_DEMAND:" + d_error)
		if seen.has(String(d.request_id)):
			return _fail("A14_6_DUPLICATE_REQUEST")
		seen[String(d.request_id)] = true
		var indices: Array = covered_cells(field, d.position_mm, d.extent_mm)
		if indices.is_empty():
			return _fail("A14_6_OUT_OF_BOUNDS")
		normalized.append({
			"id": String(d.request_id),
			"resource": String(d.resource),
			"amount": int(d.amount),
			"cells": indices,
			"demand": d.duplicate(true),
		})
	normalized.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.id) < String(b.id))
	var buckets := {}
	var demand_resources := {}
	var parent := {}
	var total_links := 0
	var primary_claim_links := 0
	var cross_cell_demands := 0
	var zero_primary_links := 0
	var max_cells_per_demand := 0
	var sorted_demands: Array = []
	for item in normalized:
		var id: String = String(item.id)
		sorted_demands.append(item.demand)
		parent[id] = id
		demand_resources[id] = String(item.resource)
		var cells: Array = item.cells
		var count: int = cells.size()
		max_cells_per_demand = maxi(max_cells_per_demand, count)
		if count > 1:
			cross_cell_demands += 1
		if total_links > MAX_ANALYSIS_LINKS - count:
			return _fail("A14_6_ANALYSIS_LINK_LIMIT")
		total_links += count
		# Reproduce *topology* of both authoritative allocation passes,
		# but never perform rounding, mutation or resource allocation.
		var base_amount: int = int(item.amount / count)
		var remainder: int = int(item.amount) % count
		for index_in_cells in count:
			var cell_id: int = int(cells[index_in_cells])
			var bucket_key := "%04d|%s" % [cell_id, String(item.resource)]
			if not buckets.has(bucket_key):
				buckets[bucket_key] = []
			buckets[bucket_key].append(id)
			if base_amount + (1 if index_in_cells < remainder else 0) > 0:
				primary_claim_links += 1
			else:
				zero_primary_links += 1
	var bucket_keys: Array = buckets.keys()
	bucket_keys.sort()
	for key in bucket_keys:
		var member_ids: Array = buckets[key]
		member_ids.sort()
		var first: String = String(member_ids[0])
		for index in range(1, member_ids.size()):
			_union(parent, first, String(member_ids[index]))
	var groups := {}
	for item in normalized:
		var root: String = _root(parent, String(item.id))
		if not groups.has(root):
			groups[root] = {
				"resource": String(item.resource),
				"request_ids": [],
				"bucket_keys": [],
				"claim_links": 0,
			}
		groups[root].request_ids.append(String(item.id))
	for key in bucket_keys:
		var ids: Array = buckets[key]
		var root: String = _root(parent, String(ids[0]))
		groups[root].bucket_keys.append(String(key))
		groups[root].claim_links += ids.size()
	var roots: Array = groups.keys()
	roots.sort()
	var components: Array = []
	var max_component_demands := 0
	var max_component_buckets := 0
	var max_bucket_requests := 0
	for key in bucket_keys:
		max_bucket_requests = maxi(max_bucket_requests, buckets[key].size())
	for root in roots:
		var g: Dictionary = groups[root]
		g.request_ids.sort()
		g.bucket_keys.sort()
		max_component_demands = maxi(max_component_demands, g.request_ids.size())
		max_component_buckets = maxi(max_component_buckets, g.bucket_keys.size())
		components.append({
			"resource": String(g.resource),
			"request_ids": g.request_ids.duplicate(),
			"bucket_keys": g.bucket_keys.duplicate(),
			"request_count": g.request_ids.size(),
			"bucket_count": g.bucket_keys.size(),
			"residual_claim_links": int(g.claim_links),
		})
	# Use content identity to prove permutation invariance. Every output
	# is a pure function of the validated canonical field and sorted demands.
	var digest := C.digest({"field_hash": String(field.integrity_hash),
		"demands": sorted_demands})
	if digest.is_empty():
		return _fail("A14_6_SOURCE_HASH")
	var result := {
		"schema": SCHEMA,
		"field_hash": String(field.integrity_hash),
		"input_hash": digest,
		"demand_count": normalized.size(),
		"residual_bucket_count": bucket_keys.size(),
		"residual_claim_links": total_links,
		"primary_claim_links": primary_claim_links,
		"zero_primary_links": zero_primary_links,
		"cross_cell_demands": cross_cell_demands,
		"max_cells_per_demand": max_cells_per_demand,
		"max_requests_per_bucket": max_bucket_requests,
		"component_count": components.size(),
		"max_component_demands": max_component_demands,
		"max_component_buckets": max_component_buckets,
		"components": components,
	}
	# No time/memory observation is stored in this deterministic result.
	return {"success": true, "plan": result, "plan_hash": C.digest(result)}

## Exact A4 rectangle/index topology, duplicated ONLY for independent
## diagnostics, not used as biology or as a substitute for Field._indices.
static func covered_cells(field: Dictionary, position_mm: Array,
		extent_mm: int) -> Array:
	var min_x: int = _floor_div(
		int(position_mm[0]) - extent_mm - int(field.origin_mm[0]),
		int(field.cell_size_mm))
	var max_x: int = _floor_div(
		int(position_mm[0]) + extent_mm - int(field.origin_mm[0]),
		int(field.cell_size_mm))
	var min_z: int = _floor_div(
		int(position_mm[2]) - extent_mm - int(field.origin_mm[2]),
		int(field.cell_size_mm))
	var max_z: int = _floor_div(
		int(position_mm[2]) + extent_mm - int(field.origin_mm[2]),
		int(field.cell_size_mm))
	if max_x < 0 or max_z < 0 \
			or min_x >= int(field.width) or min_z >= int(field.depth):
		return []
	min_x = clampi(min_x, 0, int(field.width) - 1)
	max_x = clampi(max_x, 0, int(field.width) - 1)
	min_z = clampi(min_z, 0, int(field.depth) - 1)
	max_z = clampi(max_z, 0, int(field.depth) - 1)
	var indices: Array = []
	for z in range(min_z, max_z + 1):
		for x in range(min_x, max_x + 1):
			indices.append(z * int(field.width) + x)
	return indices

static func _floor_div(value: int, divisor: int) -> int:
	if value >= 0:
		return int(value / divisor)
	return -int((-value + divisor - 1) / divisor)

static func _root(parents: Dictionary, id: String) -> String:
	var current := id
	while String(parents[current]) != current:
		current = String(parents[current])
	return current

static func _union(parents: Dictionary, left: String, right: String) -> void:
	var a := _root(parents, left)
	var b := _root(parents, right)
	if a == b:
		return
	if a < b:
		parents[b] = a
	else:
		parents[a] = b

static func _fail(error: String) -> Dictionary:
	return {"success": false, "error": error}
