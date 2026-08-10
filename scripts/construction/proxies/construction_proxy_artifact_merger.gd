extends RefCounted

const C = preload("res://scripts/construction/proxies/construction_proxy_contract_utils.gd")
const Artifact = preload("res://scripts/construction/proxies/construction_proxy_artifact.gd")

static func merge_to_shell(
	construct_id: String,
	source_revision: int,
	source_checksum: String,
	authority_epoch: int,
	section_artifacts: Array,
	bounds_min_m: Array,
	bounds_max_m: Array,
	part_count: int
) -> Dictionary:
	var merged := merge_material_batches(section_artifacts)
	if not bool(merged.get("success", false)):
		return merged
	var section_ids: Array = []
	var exposed_face_count := 0
	for artifact_value in section_artifacts:
		if typeof(artifact_value) != TYPE_DICTIONARY:
			return C.failure("CONSTRUCTION_PROXY_ARTIFACT_MERGER_INVALID_SOURCE")
		var artifact: Dictionary = artifact_value
		if String(artifact.get("artifact_kind", "")) != Artifact.SECTION:
			return C.failure("CONSTRUCTION_PROXY_ARTIFACT_MERGER_REQUIRES_SECTIONS")
		for section_id in artifact.get("section_ids", []):
			section_ids.append(String(section_id))
		exposed_face_count += int(artifact.get("exposed_face_count", 0))
	section_ids.sort()
	var collision_boxes := [{
		"center_m": [
			(float(bounds_min_m[0]) + float(bounds_max_m[0])) * 0.5,
			(float(bounds_min_m[1]) + float(bounds_max_m[1])) * 0.5,
			(float(bounds_min_m[2]) + float(bounds_max_m[2])) * 0.5,
		],
		"size_m": [
			float(bounds_max_m[0]) - float(bounds_min_m[0]),
			float(bounds_max_m[1]) - float(bounds_min_m[1]),
			float(bounds_max_m[2]) - float(bounds_min_m[2]),
		],
	}]
	var shell := Artifact.create(
		construct_id,
		source_revision,
		source_checksum,
		authority_epoch,
		Artifact.SHELL,
		"IMPOSTOR",
		section_ids,
		bounds_min_m,
		bounds_max_m,
		part_count,
		exposed_face_count,
		int(merged["merged_quad_count"]),
		merged["material_batches"],
		collision_boxes,
		[]
	)
	var checked := Artifact.validate(shell)
	return C.success({"artifact": shell}) if bool(checked.get("success", false)) else checked

static func merge_material_batches(source_artifacts: Array) -> Dictionary:
	var grid_groups: Dictionary = {}
	var fallback_by_material: Dictionary = {}
	for artifact_value in source_artifacts:
		if typeof(artifact_value) != TYPE_DICTIONARY:
			return C.failure("CONSTRUCTION_PROXY_ARTIFACT_MERGER_INVALID_SOURCE")
		var artifact: Dictionary = artifact_value
		for batch_value in artifact.get("material_batches", []):
			if typeof(batch_value) != TYPE_DICTIONARY:
				return C.failure("CONSTRUCTION_PROXY_ARTIFACT_MERGER_INVALID_BATCH")
			var batch: Dictionary = batch_value
			var material := String(batch.get("material_key", ""))
			for quad_value in batch.get("quads", []):
				if typeof(quad_value) != TYPE_DICTIONARY:
					return C.failure("CONSTRUCTION_PROXY_ARTIFACT_MERGER_INVALID_QUAD")
				var quad: Dictionary = quad_value
				var kind := String(quad.get("kind", ""))
				if kind == "GRID_QUAD":
					var key := "%s|%s|%d|%d" % [material, String(quad["axis"]), int(quad["direction"]), int(quad["plane_q2"])]
					if not grid_groups.has(key):
						grid_groups[key] = {
							"material_key": material,
							"axis": String(quad["axis"]),
							"direction": int(quad["direction"]),
							"plane_q2": int(quad["plane_q2"]),
							"cells": {},
						}
					var cells: Dictionary = grid_groups[key]["cells"]
					for dv in range(int(quad["height"])):
						for du in range(int(quad["width"])):
							var u := int(quad["u"]) + du
							var v := int(quad["v"]) + dv
							var token := "%d,%d" % [u, v]
							if cells.has(token):
								return C.failure("CONSTRUCTION_PROXY_ARTIFACT_MERGER_DUPLICATE_GRID_CELL")
							cells[token] = [u, v]
				elif kind == "FALLBACK_QUAD":
					if not fallback_by_material.has(material):
						fallback_by_material[material] = []
					fallback_by_material[material].append(quad.duplicate(true))
				else:
					return C.failure("CONSTRUCTION_PROXY_ARTIFACT_MERGER_UNSUPPORTED_QUAD")

	var quads_by_material: Dictionary = {}
	var group_keys: Array = grid_groups.keys()
	group_keys.sort()
	for key_value in group_keys:
		var group: Dictionary = grid_groups[key_value]
		var material := String(group["material_key"])
		if not quads_by_material.has(material):
			quads_by_material[material] = []
		for rectangle in _greedy_rectangles(group["cells"]):
			quads_by_material[material].append({
				"kind": "GRID_QUAD",
				"axis": String(group["axis"]),
				"direction": int(group["direction"]),
				"plane_q2": int(group["plane_q2"]),
				"u": int(rectangle[0]),
				"v": int(rectangle[1]),
				"width": int(rectangle[2]),
				"height": int(rectangle[3]),
			})

	var fallback_materials: Array = fallback_by_material.keys()
	fallback_materials.sort()
	for material_value in fallback_materials:
		var material := String(material_value)
		if not quads_by_material.has(material):
			quads_by_material[material] = []
		quads_by_material[material].append_array(fallback_by_material[material])

	var material_batches: Array = []
	var merged_quad_count := 0
	var materials: Array = quads_by_material.keys()
	materials.sort()
	for material_value in materials:
		var material := String(material_value)
		var quads: Array = quads_by_material[material]
		if quads.is_empty():
			continue
		merged_quad_count += quads.size()
		material_batches.append({
			"material_key": material,
			"quad_count": quads.size(),
			"quads": quads,
		})
	return C.success({"material_batches": material_batches, "merged_quad_count": merged_quad_count})

static func _greedy_rectangles(raw_cells: Dictionary) -> Array:
	var cells := raw_cells.duplicate(true)
	var result: Array = []
	while not cells.is_empty():
		var coords: Array = cells.values()
		coords.sort_custom(func(a, b):
			return int(a[1]) < int(b[1]) or (int(a[1]) == int(b[1]) and int(a[0]) < int(b[0]))
		)
		var start: Array = coords[0]
		var u0 := int(start[0])
		var v0 := int(start[1])
		var width := 1
		while cells.has("%d,%d" % [u0 + width, v0]):
			width += 1
		var height := 1
		while true:
			var next_v := v0 + height
			var full := true
			for offset in range(width):
				if not cells.has("%d,%d" % [u0 + offset, next_v]):
					full = false
					break
			if not full:
				break
			height += 1
		for dv in range(height):
			for du in range(width):
				cells.erase("%d,%d" % [u0 + du, v0 + dv])
		result.append([u0, v0, width, height])
	return result
