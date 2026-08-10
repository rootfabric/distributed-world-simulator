extends RefCounted

const SCHEMA := "distributed_world_simulator.ts0_local_dirty_rebuild_probe.v1"

static func run_cube_corner_probe(
	dimensions: Vector3i = Vector3i(46, 46, 46),
	section_size: int = 8,
	cluster_edge_sections: int = 3,
	remove_size: Vector3i = Vector3i(10, 10, 10)
) -> Dictionary:
	if section_size <= 0 or cluster_edge_sections <= 0:
		return _failure("TS0_DIRTY_INVALID_GRID")
	var total_sections_xyz := Vector3i(
		ceili(float(dimensions.x) / float(section_size)),
		ceili(float(dimensions.y) / float(section_size)),
		ceili(float(dimensions.z) / float(section_size))
	)
	var total_section_count := total_sections_xyz.x * total_sections_xyz.y * total_sections_xyz.z
	var remove_min := dimensions - remove_size
	var remove_max := dimensions - Vector3i.ONE
	var base_dirty := _section_coords_for_aabb(remove_min, remove_max, section_size, total_sections_xyz)
	var rebuild_sections := _expand_section_coords(base_dirty, 1, total_sections_xyz)
	var context_sections := _expand_section_coords(rebuild_sections, 1, total_sections_xyz)
	var occupancy := _build_context_occupancy(context_sections, dimensions, section_size, remove_min, remove_max)
	var section_records: Dictionary = {}
	var scanned_cells := 0
	var rebuilt_nonempty := 0
	var removed_sections := 0
	for section_coord in rebuild_sections:
		var record := _compile_section(section_coord, dimensions, section_size, remove_min, remove_max, occupancy)
		scanned_cells += int(record["scanned_cells"])
		if int(record["part_count"]) == 0:
			removed_sections += 1
		else:
			rebuilt_nonempty += 1
			section_records[_coord_key(section_coord)] = record
	var dirty_clusters: Dictionary = {}
	for section_coord in rebuild_sections:
		var cluster_coord := Vector3i(
			floori(float(section_coord.x) / float(cluster_edge_sections)),
			floori(float(section_coord.y) / float(cluster_edge_sections)),
			floori(float(section_coord.z) / float(cluster_edge_sections))
		)
		dirty_clusters[_coord_key(cluster_coord)] = cluster_coord
	var removed_part_count := remove_size.x * remove_size.y * remove_size.z
	var current_part_count := dimensions.x * dimensions.y * dimensions.z - removed_part_count
	return _success({
		"schema": SCHEMA,
		"dimensions": dimensions,
		"section_size": section_size,
		"cluster_edge_sections": cluster_edge_sections,
		"initial_part_count": dimensions.x * dimensions.y * dimensions.z,
		"current_part_count": current_part_count,
		"removed_part_count": removed_part_count,
		"total_section_count": total_section_count,
		"base_dirty_section_count": base_dirty.size(),
		"rebuild_section_count": rebuild_sections.size(),
		"context_section_count": context_sections.size(),
		"rebuilt_nonempty_section_count": rebuilt_nonempty,
		"removed_section_count": removed_sections,
		"reused_section_count": total_section_count - rebuild_sections.size(),
		"dirty_cluster_count": dirty_clusters.size(),
		"scanned_rebuild_cells": scanned_cells,
		"context_occupancy_cells": occupancy.size(),
		"full_snapshot_part_scan_required": false,
		"full_c22_compile_required": false,
		"affected_section_ratio": float(rebuild_sections.size()) / float(total_section_count),
		"section_records": section_records,
		"dirty_cluster_keys": _sorted_keys(dirty_clusters),
	})

static func _compile_section(section_coord: Vector3i, dimensions: Vector3i, section_size: int, remove_min: Vector3i, remove_max: Vector3i, occupancy: Dictionary) -> Dictionary:
	var min_cell := section_coord * section_size
	var max_cell := Vector3i(
		mini(min_cell.x + section_size - 1, dimensions.x - 1),
		mini(min_cell.y + section_size - 1, dimensions.y - 1),
		mini(min_cell.z + section_size - 1, dimensions.z - 1)
	)
	var groups: Dictionary = {}
	var part_count := 0
	var scanned_cells := 0
	for z in range(min_cell.z, max_cell.z + 1):
		for y in range(min_cell.y, max_cell.y + 1):
			for x in range(min_cell.x, max_cell.x + 1):
				var c := Vector3i(x, y, z)
				scanned_cells += 1
				if _inside_removed(c, remove_min, remove_max):
					continue
				part_count += 1
				_add_face(groups, occupancy, c, "X", -1, Vector3i(-1, 0, 0))
				_add_face(groups, occupancy, c, "X", 1, Vector3i(1, 0, 0))
				_add_face(groups, occupancy, c, "Y", -1, Vector3i(0, -1, 0))
				_add_face(groups, occupancy, c, "Y", 1, Vector3i(0, 1, 0))
				_add_face(groups, occupancy, c, "Z", -1, Vector3i(0, 0, -1))
				_add_face(groups, occupancy, c, "Z", 1, Vector3i(0, 0, 1))
	var material_batches := _compile_groups(groups)
	var quads := 0
	for batch in material_batches:
		quads += int(batch["quad_count"])
	return {
		"section_key": _coord_key(section_coord),
		"grid_coord": section_coord,
		"part_count": part_count,
		"merged_quad_count": quads,
		"material_batches": material_batches,
		"scanned_cells": scanned_cells,
	}

static func _build_context_occupancy(section_coords: Array, dimensions: Vector3i, section_size: int, remove_min: Vector3i, remove_max: Vector3i) -> Dictionary:
	var occupancy: Dictionary = {}
	for section_coord in section_coords:
		var min_cell: Vector3i = section_coord * section_size
		var max_cell := Vector3i(
			mini(min_cell.x + section_size - 1, dimensions.x - 1),
			mini(min_cell.y + section_size - 1, dimensions.y - 1),
			mini(min_cell.z + section_size - 1, dimensions.z - 1)
		)
		for z in range(min_cell.z, max_cell.z + 1):
			for y in range(min_cell.y, max_cell.y + 1):
				for x in range(min_cell.x, max_cell.x + 1):
					var c := Vector3i(x, y, z)
					if not _inside_removed(c, remove_min, remove_max):
						occupancy[c] = true
	return occupancy

static func _add_face(groups: Dictionary, occupancy: Dictionary, c: Vector3i, axis: String, direction: int, delta: Vector3i) -> void:
	if occupancy.has(c + delta):
		return
	var plane_q2 := 0
	var u := 0
	var v := 0
	match axis:
		"X":
			plane_q2 = c.x * 2 + direction
			u = c.y
			v = c.z
		"Y":
			plane_q2 = c.y * 2 + direction
			u = c.x
			v = c.z
		"Z":
			plane_q2 = c.z * 2 + direction
			u = c.x
			v = c.y
	var key := "%s|%d|%d" % [axis, direction, plane_q2]
	if not groups.has(key):
		groups[key] = {"axis": axis, "direction": direction, "plane_q2": plane_q2, "cells": {}}
	groups[key]["cells"][Vector2i(u, v)] = true

static func _compile_groups(groups: Dictionary) -> Array:
	var quads: Array = []
	var keys: Array = groups.keys()
	keys.sort()
	for key_value in keys:
		var group: Dictionary = groups[key_value]
		for rect in _greedy_rectangles(group["cells"]):
			quads.append({
				"kind": "GRID_QUAD",
				"axis": String(group["axis"]),
				"direction": int(group["direction"]),
				"plane_q2": int(group["plane_q2"]),
				"u": int(rect[0]),
				"v": int(rect[1]),
				"width": int(rect[2]),
				"height": int(rect[3]),
			})
	return [] if quads.is_empty() else [{"material_key": "structure", "quad_count": quads.size(), "quads": quads}]

static func _greedy_rectangles(raw_cells: Dictionary) -> Array:
	var cells := raw_cells.duplicate()
	var result: Array = []
	while not cells.is_empty():
		var coords: Array = cells.keys()
		coords.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
		var start: Vector2i = coords[0]
		var width := 1
		while cells.has(Vector2i(start.x + width, start.y)):
			width += 1
		var height := 1
		while true:
			var full := true
			for du in range(width):
				if not cells.has(Vector2i(start.x + du, start.y + height)):
					full = false
					break
			if not full:
				break
			height += 1
		for dv in range(height):
			for du in range(width):
				cells.erase(Vector2i(start.x + du, start.y + dv))
		result.append([start.x, start.y, width, height])
	return result

static func _section_coords_for_aabb(min_cell: Vector3i, max_cell: Vector3i, section_size: int, limits: Vector3i) -> Array:
	var min_s := Vector3i(floori(float(min_cell.x) / section_size), floori(float(min_cell.y) / section_size), floori(float(min_cell.z) / section_size))
	var max_s := Vector3i(floori(float(max_cell.x) / section_size), floori(float(max_cell.y) / section_size), floori(float(max_cell.z) / section_size))
	var result: Array = []
	for z in range(min_s.z, mini(max_s.z, limits.z - 1) + 1):
		for y in range(min_s.y, mini(max_s.y, limits.y - 1) + 1):
			for x in range(min_s.x, mini(max_s.x, limits.x - 1) + 1):
				result.append(Vector3i(x, y, z))
	return result

static func _expand_section_coords(source: Array, radius: int, limits: Vector3i) -> Array:
	var found: Dictionary = {}
	for source_coord in source:
		for dz in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1):
					var c: Vector3i = source_coord + Vector3i(dx, dy, dz)
					if c.x >= 0 and c.y >= 0 and c.z >= 0 and c.x < limits.x and c.y < limits.y and c.z < limits.z:
						found[c] = true
	var result: Array = found.keys()
	result.sort_custom(func(a, b): return a.z < b.z or (a.z == b.z and (a.y < b.y or (a.y == b.y and a.x < b.x))))
	return result

static func _inside_removed(c: Vector3i, min_c: Vector3i, max_c: Vector3i) -> bool:
	return c.x >= min_c.x and c.y >= min_c.y and c.z >= min_c.z and c.x <= max_c.x and c.y <= max_c.y and c.z <= max_c.z

static func _coord_key(c: Vector3i) -> String:
	return "%d/%d/%d" % [c.x, c.y, c.z]

static func _sorted_keys(d: Dictionary) -> Array:
	var a: Array = d.keys()
	a.sort()
	return a

static func _success(extra: Dictionary) -> Dictionary:
	var r := {"success": true, "error_code": ""}
	for k in extra:
		r[k] = extra[k]
	return r

static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code}
