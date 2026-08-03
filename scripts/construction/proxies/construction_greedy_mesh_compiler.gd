extends RefCounted

const C = preload("res://scripts/construction/proxies/construction_proxy_contract_utils.gd")
const Artifact = preload("res://scripts/construction/proxies/construction_proxy_artifact.gd")

static func compile_artifact(construct_id: String, source_revision: int, source_checksum: String, authority_epoch: int, artifact_kind: String, lod_tier: String, section_ids: Array, bounds_min_m: Array, bounds_max_m: Array, part_count: int, faces: Array, interactive_part_ids: Array = []) -> Dictionary:
	var groups := {}
	var fallback_batches := {}
	for face in faces:
		var material := String(face["material_key"])
		if String(face["kind"]) == "GRID":
			var group_key := "%s|%d|%d|%s" % [face["axis"], int(face["direction"]), int(face["plane_q2"]), material]
			if not groups.has(group_key): groups[group_key] = {"axis": face["axis"], "direction": face["direction"], "plane_q2": face["plane_q2"], "material_key": material, "cells": {}}
			groups[group_key]["cells"]["%d,%d" % [int(face["u"]), int(face["v"])]] = [int(face["u"]), int(face["v"])]
		else:
			if not fallback_batches.has(material): fallback_batches[material] = []
			fallback_batches[material].append({"kind": "FALLBACK_QUAD", "axis": face["axis"], "direction": face["direction"], "position_m": face["position_m"], "dimensions_m": face["dimensions_m"]})
	var quads_by_material := {}
	var group_keys: Array = groups.keys(); group_keys.sort()
	for group_key in group_keys:
		var group: Dictionary = groups[group_key]
		var rectangles := _greedy_rectangles(group["cells"])
		var material := String(group["material_key"])
		if not quads_by_material.has(material): quads_by_material[material] = []
		for rectangle in rectangles:
			quads_by_material[material].append({"kind": "GRID_QUAD", "axis": String(group["axis"]), "direction": int(group["direction"]), "plane_q2": int(group["plane_q2"]), "u": int(rectangle[0]), "v": int(rectangle[1]), "width": int(rectangle[2]), "height": int(rectangle[3])})
	for material in fallback_batches:
		if not quads_by_material.has(material): quads_by_material[material] = []
		quads_by_material[material].append_array(fallback_batches[material])
	var batches: Array = []
	var merged_quad_count := 0
	var materials: Array = quads_by_material.keys(); materials.sort()
	for material in materials:
		var quads: Array = quads_by_material[material]
		merged_quad_count += quads.size()
		batches.append({"material_key": material, "quad_count": quads.size(), "quads": quads})
	var collision_boxes := [{"center_m": _center(bounds_min_m, bounds_max_m), "size_m": _size(bounds_min_m, bounds_max_m)}]
	var artifact := Artifact.create(construct_id, source_revision, source_checksum, authority_epoch, artifact_kind, lod_tier, section_ids, bounds_min_m, bounds_max_m, part_count, faces.size(), merged_quad_count, batches, collision_boxes, interactive_part_ids)
	var checked := Artifact.validate(artifact)
	return C.success({"artifact": artifact}) if bool(checked.get("success", false)) else checked

static func _greedy_rectangles(raw_cells: Dictionary) -> Array:
	var cells := raw_cells.duplicate(true)
	var result: Array = []
	while not cells.is_empty():
		var coords: Array = cells.values()
		coords.sort_custom(func(a, b): return int(a[1]) < int(b[1]) or (int(a[1]) == int(b[1]) and int(a[0]) < int(b[0])))
		var start: Array = coords[0]; var u0 := int(start[0]); var v0 := int(start[1])
		var width := 1
		while cells.has("%d,%d" % [u0 + width, v0]): width += 1
		var height := 1
		while true:
			var next_v := v0 + height; var full := true
			for offset in range(width):
				if not cells.has("%d,%d" % [u0 + offset, next_v]): full = false; break
			if not full: break
			height += 1
		for dv in range(height):
			for du in range(width): cells.erase("%d,%d" % [u0 + du, v0 + dv])
		result.append([u0, v0, width, height])
	return result

static func _center(min_v: Array, max_v: Array) -> Array: return [(float(min_v[0]) + float(max_v[0])) * 0.5, (float(min_v[1]) + float(max_v[1])) * 0.5, (float(min_v[2]) + float(max_v[2])) * 0.5]
static func _size(min_v: Array, max_v: Array) -> Array: return [float(max_v[0]) - float(min_v[0]), float(max_v[1]) - float(min_v[1]), float(max_v[2]) - float(min_v[2])]
