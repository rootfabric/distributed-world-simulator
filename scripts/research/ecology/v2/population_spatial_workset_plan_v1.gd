extends RefCounted
## ECO ARCH2 A13 spatial workset addressing.
## Spatial addresses are scheduler-only projections from canonical organism
## positions + canonical field geometry. They own no biology/resources/state.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Scale = preload("res://scripts/research/ecology/v2/ecology_scale_contract_v1.gd")
const ExactWorksets = preload("res://scripts/research/ecology/v2/population_workset_plan_v1.gd")

const SCHEMA := "dws.ecology.spatial-workset-plan.v1"
const DEFAULT_TILE_SPAN_CELLS := 4
const DEFAULT_MAX_MEMBERS := ExactWorksets.DEFAULT_WORKSET_SIZE
const MAX_TILE_SPAN_CELLS := 64
const MAX_MEMBERS := Scale.MAX_POPULATION

const PLAN_KEYS := [
	"schema", "tile_span_cells", "max_members", "field_geometry_hash",
	"population_hash", "member_count", "worksets"
]
const UNIT_KEYS := [
	"index", "address", "tile_x", "tile_z", "shard", "member_ids"
]

static func create(field: Dictionary, population: Array,
		tile_span_cells: int = DEFAULT_TILE_SPAN_CELLS,
		max_members: int = DEFAULT_MAX_MEMBERS) -> Dictionary:
	if not _valid_parameters(tile_span_cells, max_members):
		return {}
	var geometry := _geometry(field)
	if geometry.is_empty():
		return {}
	var rows := _rows(field, population, tile_span_cells)
	if rows.is_empty() and not population.is_empty():
		return {}
	if rows.size() != population.size():
		return {}

	var buckets := {}
	for row in rows:
		var address: String = row.address
		if not buckets.has(address):
			buckets[address] = {
				"tile_x": int(row.tile_x),
				"tile_z": int(row.tile_z),
				"member_ids": [],
			}
		buckets[address].member_ids.append(String(row.individual_id))

	var addresses: Array = buckets.keys()
	addresses.sort()
	var worksets: Array = []
	for raw_address in addresses:
		var address := String(raw_address)
		var member_ids: Array = buckets[address].member_ids
		member_ids.sort()
		var offset := 0
		var shard := 0
		while offset < member_ids.size():
			var chunk: Array = []
			var stop := mini(member_ids.size(), offset + max_members)
			for i in range(offset, stop):
				chunk.append(member_ids[i])
			worksets.append({
				"index": worksets.size(),
				"address": address,
				"tile_x": int(buckets[address].tile_x),
				"tile_z": int(buckets[address].tile_z),
				"shard": shard,
				"member_ids": chunk,
			})
			offset = stop
			shard += 1

	var plan := {
		"schema": SCHEMA,
		"tile_span_cells": tile_span_cells,
		"max_members": max_members,
		"field_geometry_hash": C.digest(geometry),
		"population_hash": _population_projection_hash(rows),
		"member_count": rows.size(),
		"worksets": worksets,
	}
	return plan if validate(plan, field, population).is_empty() else {}

static func validate(plan: Variant, field: Dictionary, population: Array) -> String:
	if not C.keys(plan, PLAN_KEYS) or String(plan.schema) != SCHEMA:
		return "SPATIAL_PLAN_SCHEMA"
	if not _valid_parameters(int(plan.tile_span_cells), int(plan.max_members)):
		return "SPATIAL_PLAN_PARAMETERS"
	var geometry := _geometry(field)
	if geometry.is_empty():
		return "SPATIAL_PLAN_FIELD"
	if String(plan.field_geometry_hash) != C.digest(geometry):
		return "SPATIAL_PLAN_FIELD_GEOMETRY"
	var rows := _rows(field, population, int(plan.tile_span_cells))
	if rows.size() != population.size():
		return "SPATIAL_PLAN_POPULATION"
	if not C.integer(plan.member_count, 0, Scale.MAX_POPULATION) 			or int(plan.member_count) != rows.size():
		return "SPATIAL_PLAN_MEMBER_COUNT"
	if String(plan.population_hash) != _population_projection_hash(rows):
		return "SPATIAL_PLAN_POPULATION_HASH"
	if not plan.worksets is Array:
		return "SPATIAL_PLAN_WORKSETS"

	var expected := _expected_units(rows, int(plan.max_members))
	if expected.size() != plan.worksets.size():
		return "SPATIAL_PLAN_WORKSET_COUNT"
	for i in expected.size():
		var unit: Variant = plan.worksets[i]
		if not C.keys(unit, UNIT_KEYS):
			return "SPATIAL_PLAN_WORKSET_SCHEMA"
		if int(unit.index) != i:
			return "SPATIAL_PLAN_WORKSET_INDEX"
		if C.encode(unit) != C.encode(expected[i]):
			return "SPATIAL_PLAN_WORKSET_CONTENT"
	return "SPATIAL_PLAN_NONCANONICAL" if C.encode(plan).is_empty() else ""

static func address_for_position(field: Dictionary, position_mm: Array,
		tile_span_cells: int = DEFAULT_TILE_SPAN_CELLS) -> Dictionary:
	if tile_span_cells < 1 or tile_span_cells > MAX_TILE_SPAN_CELLS:
		return {}
	if F.validate_state(field) != "" or not C.vector(position_mm, F.MAX_PORT_COORD_MM):
		return {}
	var rel_x: int = int(position_mm[0]) - int(field.origin_mm[0])
	var rel_z: int = int(position_mm[2]) - int(field.origin_mm[2])
	var width_mm: int = int(field.width) * int(field.cell_size_mm)
	var depth_mm: int = int(field.depth) * int(field.cell_size_mm)
	if rel_x < 0 or rel_z < 0 or rel_x >= width_mm or rel_z >= depth_mm:
		return {}
	var cell_x := int(rel_x / int(field.cell_size_mm))
	var cell_z := int(rel_z / int(field.cell_size_mm))
	var tile_x := int(cell_x / tile_span_cells)
	var tile_z := int(cell_z / tile_span_cells)
	return {
		"address": "tile/%04d/%04d" % [tile_z, tile_x],
		"tile_x": tile_x,
		"tile_z": tile_z,
		"cell_x": cell_x,
		"cell_z": cell_z,
	}

static func member_ids(plan: Dictionary) -> Array:
	var out: Array = []
	for unit in plan.get("worksets", []):
		for raw_id in unit.get("member_ids", []):
			out.append(String(raw_id))
	return out

static func member_address_map(plan: Dictionary) -> Dictionary:
	var out := {}
	for unit in plan.get("worksets", []):
		for raw_id in unit.get("member_ids", []):
			out[String(raw_id)] = String(unit.address)
	return out

static func _valid_parameters(tile_span_cells: int, max_members: int) -> bool:
	return tile_span_cells >= 1 and tile_span_cells <= MAX_TILE_SPAN_CELLS 		and max_members >= 1 and max_members <= MAX_MEMBERS

static func _geometry(field: Dictionary) -> Dictionary:
	if F.validate_state(field) != "":
		return {}
	return {
		"origin_mm": field.origin_mm.duplicate(),
		"cell_size_mm": int(field.cell_size_mm),
		"width": int(field.width),
		"depth": int(field.depth),
	}

static func _rows(field: Dictionary, population: Array, tile_span_cells: int) -> Array:
	var rows: Array = []
	var seen := {}
	for entry in population:
		if not entry is Dictionary or not entry.get("state") is Dictionary:
			return []
		var id: Variant = entry.state.get("individual_id", null)
		var position: Variant = entry.state.get("position_mm", null)
		if not C.identifier(id) or seen.has(id) or not position is Array:
			return []
		var spatial := address_for_position(field, position, tile_span_cells)
		if spatial.is_empty():
			return []
		seen[id] = true
		rows.append({
			"individual_id": String(id),
			"position_mm": position.duplicate(),
			"address": String(spatial.address),
			"tile_x": int(spatial.tile_x),
			"tile_z": int(spatial.tile_z),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.address != b.address:
			return a.address < b.address
		return a.individual_id < b.individual_id)
	return rows

static func _population_projection_hash(rows: Array) -> String:
	var projection: Array = []
	for row in rows:
		projection.append({
			"individual_id": String(row.individual_id),
			"position_mm": row.position_mm.duplicate(),
		})
	projection.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.individual_id < b.individual_id)
	return C.digest(projection)

static func _expected_units(rows: Array, max_members: int) -> Array:
	var buckets := {}
	for row in rows:
		if not buckets.has(row.address):
			buckets[row.address] = {
				"tile_x": int(row.tile_x),
				"tile_z": int(row.tile_z),
				"member_ids": [],
			}
		buckets[row.address].member_ids.append(String(row.individual_id))
	var addresses: Array = buckets.keys()
	addresses.sort()
	var units: Array = []
	for raw_address in addresses:
		var address := String(raw_address)
		var ids: Array = buckets[address].member_ids
		ids.sort()
		var offset := 0
		var shard := 0
		while offset < ids.size():
			var members: Array = []
			var stop := mini(ids.size(), offset + max_members)
			for i in range(offset, stop):
				members.append(ids[i])
			units.append({
				"index": units.size(),
				"address": address,
				"tile_x": int(buckets[address].tile_x),
				"tile_z": int(buckets[address].tile_z),
				"shard": shard,
				"member_ids": members,
			})
			offset = stop
			shard += 1
	return units
