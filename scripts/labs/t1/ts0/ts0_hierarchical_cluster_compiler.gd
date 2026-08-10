extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const C = preload("res://scripts/construction/proxies/construction_proxy_contract_utils.gd")
const Artifact = preload("res://scripts/construction/proxies/construction_proxy_artifact.gd")

const DEFAULT_CLUSTER_EDGE_SECTIONS := 3

static func compile(
	manifest: Dictionary,
	topology: Dictionary,
	artifact_cache,
	cluster_edge_sections: int = DEFAULT_CLUSTER_EDGE_SECTIONS
) -> Dictionary:
	if cluster_edge_sections < 2:
		return C.failure("TS0_HIERARCHY_INVALID_CLUSTER_EDGE")
	if artifact_cache == null:
		return C.failure("TS0_HIERARCHY_ARTIFACT_CACHE_REQUIRED")
	if String(manifest.get("construct_id", "")) != String(topology.get("construct_id", "")):
		return C.failure("TS0_HIERARCHY_CONSTRUCT_MISMATCH")
	if String(manifest.get("source_checksum", "")) != String(topology.get("source_checksum", "")):
		return C.failure("TS0_HIERARCHY_SOURCE_MISMATCH")

	var refs_by_section: Dictionary = {}
	var section_artifact_ids: Dictionary = {}
	for ref_value in manifest.get("section_artifacts", []):
		if typeof(ref_value) != TYPE_DICTIONARY:
			return C.failure("TS0_HIERARCHY_INVALID_SECTION_REFERENCE")
		var ref: Dictionary = ref_value
		var section_id := String(ref.get("section_id", ""))
		var artifact_id := String(ref.get("artifact_id", ""))
		if section_id.is_empty() or artifact_id.is_empty():
			return C.failure("TS0_HIERARCHY_INVALID_SECTION_REFERENCE")
		if refs_by_section.has(section_id):
			return C.failure("TS0_HIERARCHY_DUPLICATE_SECTION_REFERENCE")
		refs_by_section[section_id] = ref
		section_artifact_ids[section_id] = artifact_id

	var groups: Dictionary = {}
	for section_value in topology.get("sections", []):
		if typeof(section_value) != TYPE_DICTIONARY:
			return C.failure("TS0_HIERARCHY_INVALID_SECTION")
		var section: Dictionary = section_value
		var section_id := String(section.get("section_id", ""))
		if not refs_by_section.has(section_id):
			return C.failure("TS0_HIERARCHY_SECTION_REFERENCE_MISSING")
		var coord: Array = section.get("grid_coord", [])
		if coord.size() != 3:
			return C.failure("TS0_HIERARCHY_INVALID_SECTION_COORD")
		var cluster_coord := [
			int(floor(float(coord[0]) / float(cluster_edge_sections))),
			int(floor(float(coord[1]) / float(cluster_edge_sections))),
			int(floor(float(coord[2]) / float(cluster_edge_sections))),
		]
		var key := _coord_key(cluster_coord)
		if not groups.has(key):
			groups[key] = {
				"grid_coord": cluster_coord,
				"sections": [],
			}
		groups[key]["sections"].append(section)

	var clusters: Array = []
	var section_to_cluster: Dictionary = {}
	var group_keys: Array = groups.keys()
	group_keys.sort()
	for key_value in group_keys:
		var key := String(key_value)
		var compiled_cluster: Dictionary = _compile_cluster(
			String(manifest["construct_id"]),
			int(manifest["source_revision"]),
			String(manifest["source_checksum"]),
			int(manifest["authority_epoch"]),
			key,
			groups[key],
			refs_by_section,
			artifact_cache
		)
		if not bool(compiled_cluster.get("success", false)):
			return compiled_cluster
		var cluster: Dictionary = compiled_cluster["cluster"]
		clusters.append(cluster)
		for section_id in cluster["section_ids"]:
			if section_to_cluster.has(section_id):
				return C.failure("TS0_HIERARCHY_SECTION_COVERAGE_OVERLAP")
			section_to_cluster[section_id] = String(cluster["cluster_id"])

	var covered_section_ids: Array = section_to_cluster.keys()
	covered_section_ids.sort()
	if covered_section_ids.size() != int(manifest.get("total_section_count", -1)):
		return C.failure("TS0_HIERARCHY_SECTION_COVERAGE_INCOMPLETE")
	if covered_section_ids.size() != refs_by_section.size():
		return C.failure("TS0_HIERARCHY_REFERENCE_COVERAGE_INCOMPLETE")

	var coverage_rows: Array = []
	var total_cluster_quads := 0
	var nonempty_cluster_count := 0
	for cluster_value in clusters:
		var cluster: Dictionary = cluster_value
		var artifact: Dictionary = cluster["artifact"]
		total_cluster_quads += int(artifact.get("merged_quad_count", 0))
		if int(artifact.get("merged_quad_count", 0)) > 0:
			nonempty_cluster_count += 1
		coverage_rows.append({
			"cluster_id": String(cluster["cluster_id"]),
			"section_ids": Array(cluster["section_ids"]).duplicate(true),
			"artifact_content_hash": String(artifact["content_hash"]),
		})

	var coverage_checksum := Utils.payload_hash({
		"construct_id": String(manifest["construct_id"]),
		"source_checksum": String(manifest["source_checksum"]),
		"cluster_edge_sections": cluster_edge_sections,
		"clusters": coverage_rows,
	})
	return C.success({
		"schema": "distributed_world_simulator.ts0_hierarchical_cluster_compilation.v1",
		"construct_id": String(manifest["construct_id"]),
		"source_revision": int(manifest["source_revision"]),
		"source_checksum": String(manifest["source_checksum"]),
		"cluster_edge_sections": cluster_edge_sections,
		"source_section_count": covered_section_ids.size(),
		"cluster_count": clusters.size(),
		"nonempty_cluster_count": nonempty_cluster_count,
		"total_cluster_quads": total_cluster_quads,
		"clusters": clusters,
		"section_to_cluster": section_to_cluster,
		"section_artifact_ids": section_artifact_ids,
		"coverage_checksum": coverage_checksum,
	})

static func _compile_cluster(
	construct_id: String,
	source_revision: int,
	source_checksum: String,
	authority_epoch: int,
	cluster_key: String,
	group: Dictionary,
	refs_by_section: Dictionary,
	artifact_cache
) -> Dictionary:
	var sections: Array = Array(group.get("sections", [])).duplicate(false)
	sections.sort_custom(func(a, b): return String(a.get("section_id", "")) < String(b.get("section_id", "")))

	var section_ids: Array = []
	var source_artifact_ids: Array = []
	var source_artifacts: Array = []
	var bounds_min: Array = [INF, INF, INF]
	var bounds_max: Array = [-INF, -INF, -INF]
	var part_count := 0
	var exposed_face_count := 0

	for section_value in sections:
		var section: Dictionary = section_value
		var section_id := String(section["section_id"])
		var ref: Dictionary = refs_by_section[section_id]
		var artifact_id := String(ref["artifact_id"])
		var source_artifact: Dictionary = artifact_cache.get_artifact(artifact_id)
		if source_artifact.is_empty():
			return C.failure("TS0_HIERARCHY_SOURCE_ARTIFACT_MISSING")
		if String(source_artifact.get("source_checksum", "")) != source_checksum:
			return C.failure("TS0_HIERARCHY_SOURCE_ARTIFACT_MISMATCH")
		section_ids.append(section_id)
		source_artifact_ids.append(artifact_id)
		source_artifacts.append(source_artifact)
		part_count += int(source_artifact.get("part_count", 0))
		exposed_face_count += int(source_artifact.get("exposed_face_count", 0))
		for axis in range(3):
			bounds_min[axis] = minf(float(bounds_min[axis]), float(source_artifact["bounds_min_m"][axis]))
			bounds_max[axis] = maxf(float(bounds_max[axis]), float(source_artifact["bounds_max_m"][axis]))

	var merged: Dictionary = _merge_artifacts(source_artifacts)
	if not bool(merged.get("success", false)):
		return merged
	var artifact := Artifact.create(
		construct_id,
		source_revision,
		source_checksum,
		authority_epoch,
		Artifact.SECTION,
		"SIMPLIFIED",
		section_ids,
		bounds_min,
		bounds_max,
		part_count,
		exposed_face_count,
		int(merged["merged_quad_count"]),
		merged["material_batches"],
		[],
		[]
	)
	var checked: Dictionary = Artifact.validate(artifact)
	if not bool(checked.get("success", false)):
		return checked

	var cluster_coord: Array = group["grid_coord"]
	var cluster_id := "ts0-cluster/%s/%s" % [
		construct_id.trim_prefix("construct/").replace("/", "-"),
		_coord_key(cluster_coord),
	]
	return C.success({
		"cluster": {
			"cluster_id": cluster_id,
			"grid_coord": Array(cluster_coord).duplicate(true),
			"section_ids": section_ids,
			"source_artifact_ids": source_artifact_ids,
			"bounds_min_m": bounds_min,
			"bounds_max_m": bounds_max,
			"part_count": part_count,
			"artifact": artifact,
			"cluster_key": cluster_key,
		},
	})

static func _merge_artifacts(source_artifacts: Array) -> Dictionary:
	var grid_groups: Dictionary = {}
	var fallback_by_material: Dictionary = {}
	for artifact_value in source_artifacts:
		var artifact: Dictionary = artifact_value
		for batch_value in artifact.get("material_batches", []):
			var batch: Dictionary = batch_value
			var material := String(batch.get("material_key", ""))
			for quad_value in batch.get("quads", []):
				var quad: Dictionary = quad_value
				var kind := String(quad.get("kind", ""))
				if kind == "GRID_QUAD":
					var key := "%s|%s|%d|%d" % [
						material,
						String(quad["axis"]),
						int(quad["direction"]),
						int(quad["plane_q2"]),
					]
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
								return C.failure("TS0_HIERARCHY_DUPLICATE_SURFACE_CELL")
							cells[token] = [u, v]
				elif kind == "FALLBACK_QUAD":
					if not fallback_by_material.has(material):
						fallback_by_material[material] = []
					fallback_by_material[material].append(quad.duplicate(true))
				else:
					return C.failure("TS0_HIERARCHY_UNSUPPORTED_SOURCE_QUAD")

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
	return C.success({
		"material_batches": material_batches,
		"merged_quad_count": merged_quad_count,
	})

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

static func _coord_key(coord: Array) -> String:
	return "%s_%s_%s" % [
		_coord_token(int(coord[0])),
		_coord_token(int(coord[1])),
		_coord_token(int(coord[2])),
	]

static func _coord_token(value: int) -> String:
	return "n%04d" % abs(value) if value < 0 else "p%04d" % value
