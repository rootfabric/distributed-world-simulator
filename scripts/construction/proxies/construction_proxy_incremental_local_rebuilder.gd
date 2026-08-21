extends RefCounted

const C = preload("res://scripts/construction/proxies/construction_proxy_contract_utils.gd")
const CompileRequest = preload("res://scripts/construction/proxies/construction_proxy_compile_request.gd")
const Topology = preload("res://scripts/construction/proxies/construction_proxy_section_topology.gd")
const GreedyCompiler = preload("res://scripts/construction/proxies/construction_greedy_mesh_compiler.gd")
const Artifact = preload("res://scripts/construction/proxies/construction_proxy_artifact.gd")
const Manifest = preload("res://scripts/construction/proxies/construction_proxy_manifest.gd")
const Invalidation = preload("res://scripts/construction/proxies/construction_proxy_invalidation_plan.gd")
const ArtifactMerger = preload("res://scripts/construction/proxies/construction_proxy_artifact_merger.gd")

const TOPOLOGY_SCHEMA := "planet_simulator.construction_proxy_section_topology.v1"
const NEIGHBOR_SECTION_RADIUS := 1

static func try_rebuild(request: Dictionary, dirty_part_ids: Array, previous: Dictionary, cache) -> Dictionary:
	var checked := CompileRequest.validate(request)
	if not bool(checked.get("success", false)):
		return checked
	if cache == null:
		return C.failure("CONSTRUCTION_PROXY_INCREMENTAL_CACHE_REQUIRED")
	if previous.is_empty() or not previous.has("manifest") or not previous.has("topology") or not previous.has("request"):
		return _fallback("PREVIOUS_COMPILED_RECORD_INCOMPLETE")
	var previous_topology: Dictionary = previous["topology"]
	if previous_topology.is_empty():
		return _fallback("PREVIOUS_TOPOLOGY_NOT_ATTACHED")
	checked = Topology.validate(previous_topology)
	if not bool(checked.get("success", false)):
		return _fallback("PREVIOUS_TOPOLOGY_INVALID")
	if not Array(request.get("interior_cells", [])).is_empty() or not Array(previous["manifest"].get("interior_artifacts", [])).is_empty():
		return _fallback("INTERIOR_ARTIFACTS_REQUIRE_FULL_COMPILE")
	if not Dictionary(previous.get("descriptor_by_part", {})).is_empty():
		return _fallback("INTERACTIVE_DESCRIPTORS_REQUIRE_FULL_COMPILE")
	if not _same_compile_policy(previous["request"], request):
		return _fallback("COMPILE_POLICY_CHANGED")

	var sorted_dirty := C.sorted_strings(dirty_part_ids)
	if not C.sorted_unique_strings(sorted_dirty, "part/"):
		return C.failure("INVALID_CONSTRUCTION_PROXY_DIRTY_PARTS")
	if sorted_dirty.is_empty():
		return _fallback("EMPTY_DIRTY_SET")

	var previous_snapshot: Dictionary = previous["request"]["runtime_projection_request"]["construct_snapshot"]
	var snapshot: Dictionary = request["runtime_projection_request"]["construct_snapshot"]
	var previous_manifest: Dictionary = previous["manifest"]
	if String(snapshot.get("construct_id", "")) != String(previous_manifest.get("construct_id", "")):
		return C.failure("CONSTRUCTION_PROXY_INCREMENTAL_CONSTRUCT_MISMATCH")
	if int(request["authority_epoch"]) < int(previous_manifest["authority_epoch"]):
		return C.failure("STALE_CONSTRUCTION_PROXY_AUTHORITY_EPOCH")
	if int(request["authority_epoch"]) == int(previous_manifest["authority_epoch"]) and int(snapshot["state_revision"]) < int(previous_manifest["source_revision"]):
		return C.failure("STALE_CONSTRUCTION_PROXY_SOURCE_REVISION")
	if int(snapshot["state_revision"]) == int(previous_manifest["source_revision"]) and String(snapshot["checksum"]) != String(previous_manifest["source_checksum"]):
		return C.failure("CONSTRUCTION_PROXY_SOURCE_SAME_REVISION_MUTATION")

	var section_size := float(request["section_size_m"])
	var previous_sections_by_id := _sections_by_id(previous_topology["sections"])
	var current_dirty_parts: Dictionary = {}
	var base_dirty_coords: Dictionary = {}
	var part_lookup_count := 0
	for part_id_value in sorted_dirty:
		var part_id := String(part_id_value)
		var old_section_id := String(previous_topology["part_section_index"].get(part_id, ""))
		if not old_section_id.is_empty() and previous_sections_by_id.has(old_section_id):
			var old_section: Dictionary = previous_sections_by_id[old_section_id]
			var old_coord: Array = old_section["grid_coord"]
			base_dirty_coords[_coord_key(old_coord)] = old_coord.duplicate(true)
		var current_part := _find_part(snapshot, part_id)
		part_lookup_count += int(current_part["lookups"])
		if bool(current_part["found"]):
			var part: Dictionary = current_part["part"]
			if not _is_unit_axis_part(part):
				return _fallback("DIRTY_PART_NOT_UNIT_AXIS_GRID")
			current_dirty_parts[part_id] = part
			var new_coord := _section_coord(part["local_position_m"], section_size)
			base_dirty_coords[_coord_key(new_coord)] = new_coord
	if base_dirty_coords.is_empty():
		return _fallback("DIRTY_PARTS_NOT_FOUND_IN_OLD_OR_NEW_SNAPSHOT")

	var topology_result := _build_incremental_topology(
		snapshot,
		previous_topology,
		previous_sections_by_id,
		current_dirty_parts,
		sorted_dirty,
		base_dirty_coords,
		section_size
	)
	if not bool(topology_result.get("success", false)):
		return topology_result
	part_lookup_count += int(topology_result.get("part_lookups", 0))
	var topology: Dictionary = topology_result["topology"]
	checked = Topology.validate(topology)
	if not bool(checked.get("success", false)):
		return checked

	var rebuild_coords := _expand_coords(base_dirty_coords, NEIGHBOR_SECTION_RADIUS)
	var topology_sections_by_id := _sections_by_id(topology["sections"])
	var target_section_ids: Array = []
	var target_section_set: Dictionary = {}
	for section_value in topology["sections"]:
		var section: Dictionary = section_value
		if rebuild_coords.has(_coord_key(section["grid_coord"])):
			var section_id := String(section["section_id"])
			target_section_ids.append(section_id)
			target_section_set[section_id] = true
	target_section_ids.sort()

	var context_coords := _expand_coords(rebuild_coords, NEIGHBOR_SECTION_RADIUS)
	var context_section_ids: Array = []
	for section_value in topology["sections"]:
		var section: Dictionary = section_value
		if context_coords.has(_coord_key(section["grid_coord"])):
			context_section_ids.append(String(section["section_id"]))
	context_section_ids.sort()

	var local_surface := _extract_local_grid_faces(snapshot, topology_sections_by_id, target_section_set, context_section_ids)
	if not bool(local_surface.get("success", false)):
		if String(local_surface.get("error_code", "")) == "CONSTRUCTION_PROXY_INCREMENTAL_CONTEXT_NOT_UNIT_AXIS_GRID":
			return _fallback(String(local_surface["error_code"]))
		return local_surface
	part_lookup_count += int(local_surface.get("part_lookups", 0))

	var faces_by_section: Dictionary = {}
	for face_value in local_surface["faces"]:
		var face: Dictionary = face_value
		var section_id := String(face["section_id"])
		if not faces_by_section.has(section_id):
			faces_by_section[section_id] = []
		faces_by_section[section_id].append(face)

	var rebuilt_artifacts: Dictionary = {}
	for section_id_value in target_section_ids:
		var section_id := String(section_id_value)
		var section: Dictionary = topology_sections_by_id[section_id]
		var compiled_section := GreedyCompiler.compile_artifact(
			String(snapshot["construct_id"]),
			int(snapshot["state_revision"]),
			String(snapshot["checksum"]),
			int(request["authority_epoch"]),
			Artifact.SECTION,
			"SIMPLIFIED",
			[section_id],
			section["bounds_min_m"],
			section["bounds_max_m"],
			int(section["part_count"]),
			Array(faces_by_section.get(section_id, [])),
			section["interactive_part_ids"]
		)
		if not bool(compiled_section.get("success", false)):
			return compiled_section
		var artifact: Dictionary = compiled_section["artifact"]
		var publish: Dictionary = cache.publish(artifact, _operation_id(snapshot, "section", String(artifact["content_hash"])))
		if not bool(publish.get("success", false)):
			return publish
		rebuilt_artifacts[section_id] = artifact

	var old_refs := _refs_by_section(previous_manifest["section_artifacts"])
	var section_artifacts: Array = []
	var new_artifact_id_by_section: Dictionary = {}
	var reused_section_count := 0
	for section_value in topology["sections"]:
		var section: Dictionary = section_value
		var section_id := String(section["section_id"])
		var artifact: Dictionary = {}
		if rebuilt_artifacts.has(section_id):
			artifact = rebuilt_artifacts[section_id]
		else:
			if not old_refs.has(section_id):
				return _fallback("NEW_SECTION_OUTSIDE_REBUILD_SCOPE")
			artifact = cache.get_artifact(String(old_refs[section_id]["artifact_id"]))
			if artifact.is_empty():
				return _fallback("REUSED_SECTION_ARTIFACT_MISSING")
			reused_section_count += 1
		section_artifacts.append(artifact)
		new_artifact_id_by_section[section_id] = String(artifact["artifact_id"])

	var bounds := _construct_bounds(topology["sections"])
	if not bool(bounds.get("success", false)):
		return _fallback("EMPTY_CONSTRUCT_REQUIRES_FULL_COMPILE")
	var shell_result := ArtifactMerger.merge_to_shell(
		String(snapshot["construct_id"]),
		int(snapshot["state_revision"]),
		String(snapshot["checksum"]),
		int(request["authority_epoch"]),
		section_artifacts,
		bounds["bounds_min_m"],
		bounds["bounds_max_m"],
		Array(snapshot["parts"]).size()
	)
	if not bool(shell_result.get("success", false)):
		return shell_result
	var shell_artifact: Dictionary = shell_result["artifact"]
	var shell_publish: Dictionary = cache.publish(shell_artifact, _operation_id(snapshot, "shell", String(shell_artifact["content_hash"])))
	if not bool(shell_publish.get("success", false)):
		return shell_publish

	var estimated_cache_bytes := int(shell_artifact["estimated_bytes"])
	var total_exposed_faces := 0
	for artifact_value in section_artifacts:
		var artifact: Dictionary = artifact_value
		estimated_cache_bytes += int(artifact["estimated_bytes"])
		total_exposed_faces += int(artifact["exposed_face_count"])
	var manifest := Manifest.create(
		request,
		topology,
		shell_artifact,
		section_artifacts,
		[],
		request["portals"],
		bounds["bounds_min_m"],
		bounds["bounds_max_m"],
		total_exposed_faces,
		estimated_cache_bytes
	)
	checked = Manifest.validate(manifest)
	if not bool(checked.get("success", false)):
		return checked

	var invalidated: Array = []
	var reused: Array = []
	var dirty_section_ids: Dictionary = {}
	var previous_section_id_by_coord := _section_ids_by_coord(previous_topology["sections"])
	var current_section_id_by_coord := _section_ids_by_coord(topology["sections"])
	for coord_key_value in rebuild_coords.keys():
		var coord_key := String(coord_key_value)
		var old_id := String(previous_section_id_by_coord.get(coord_key, ""))
		var new_id := String(current_section_id_by_coord.get(coord_key, ""))
		if not old_id.is_empty(): dirty_section_ids[old_id] = true
		if not new_id.is_empty(): dirty_section_ids[new_id] = true
	for section_id_value in old_refs.keys():
		var section_id := String(section_id_value)
		var old_artifact_id := String(old_refs[section_id]["artifact_id"])
		var new_artifact_id := String(new_artifact_id_by_section.get(section_id, ""))
		if not new_artifact_id.is_empty() and new_artifact_id == old_artifact_id:
			reused.append(old_artifact_id)
		else:
			invalidated.append(old_artifact_id)
	var shell_rebuilt := String(previous_manifest["shell_artifact_id"]) != String(shell_artifact["artifact_id"])
	if shell_rebuilt:
		invalidated.append(String(previous_manifest["shell_artifact_id"]))
	else:
		reused.append(String(previous_manifest["shell_artifact_id"]))
	var plan := Invalidation.create(
		String(snapshot["construct_id"]),
		String(previous_manifest["source_checksum"]),
		String(manifest["source_checksum"]),
		sorted_dirty,
		C.sorted_strings(dirty_section_ids.keys()),
		_unique_sorted(invalidated),
		_unique_sorted(reused),
		shell_rebuilt
	)
	checked = Invalidation.validate(plan)
	if not bool(checked.get("success", false)):
		return checked

	var previous_visible := int(previous.get("stats", {}).get("raw_face_count", 0)) / 6
	var visible_delta := 0
	for part_id_value in sorted_dirty:
		var part_id := String(part_id_value)
		var old_part := _find_part(previous_snapshot, part_id)
		part_lookup_count += int(old_part["lookups"])
		if bool(old_part["found"]) and _part_visible(old_part["part"]): visible_delta -= 1
		if current_dirty_parts.has(part_id) and _part_visible(current_dirty_parts[part_id]): visible_delta += 1
	var visible_part_count := previous_visible + visible_delta
	var raw_face_count := visible_part_count * 6
	var stats := {
		"raw_face_count": raw_face_count,
		"exposed_face_count": total_exposed_faces,
		"culled_face_count": raw_face_count - total_exposed_faces,
		"shell_quad_count": int(shell_artifact["merged_quad_count"]),
		"section_count": section_artifacts.size(),
		"cache_bytes": estimated_cache_bytes,
		"exact_descriptor_count": 0,
		"incremental_fast_path": true,
		"full_compile_used": false,
		"full_snapshot_scan_used": false,
		"base_dirty_section_count": base_dirty_coords.size(),
		"rebuild_section_count": target_section_ids.size(),
		"reused_section_count": reused_section_count,
		"context_section_count": context_section_ids.size(),
		"context_occupancy_cells": int(local_surface.get("occupancy_cells", 0)),
		"snapshot_binary_search_lookups": part_lookup_count,
	}
	return C.success({
		"fast_path_applied": true,
		"manifest": manifest,
		"topology": topology,
		"descriptor_by_part": {},
		"stats": stats,
		"invalidation_plan": plan,
	})

static func _build_incremental_topology(
	snapshot: Dictionary,
	previous_topology: Dictionary,
	previous_sections_by_id: Dictionary,
	current_dirty_parts: Dictionary,
	sorted_dirty: Array,
	base_dirty_coords: Dictionary,
	section_size: float
) -> Dictionary:
	var sections_by_id: Dictionary = previous_sections_by_id.duplicate(true)
	var part_section_index: Dictionary = Dictionary(previous_topology["part_section_index"]).duplicate(true)
	for part_id_value in sorted_dirty:
		part_section_index.erase(String(part_id_value))
	var dirty_set: Dictionary = {}
	for part_id_value in sorted_dirty: dirty_set[String(part_id_value)] = true
	var part_lookups := 0
	for coord_value in base_dirty_coords.values():
		var coord: Array = coord_value
		var section_id := _section_id(String(snapshot["construct_id"]), coord)
		var part_ids: Array = []
		if sections_by_id.has(section_id):
			for part_id_value in sections_by_id[section_id]["part_ids"]:
				var part_id := String(part_id_value)
				if not dirty_set.has(part_id): part_ids.append(part_id)
		for part_id_value in current_dirty_parts.keys():
			var part_id := String(part_id_value)
			var part: Dictionary = current_dirty_parts[part_id]
			if _coord_key(_section_coord(part["local_position_m"], section_size)) == _coord_key(coord):
				part_ids.append(part_id)
		part_ids.sort()
		if part_ids.is_empty():
			sections_by_id.erase(section_id)
		else:
			var built := _build_section(snapshot, coord, part_ids)
			if not bool(built.get("success", false)): return built
			part_lookups += int(built.get("part_lookups", 0))
			sections_by_id[section_id] = built["section"]
	for part_id_value in current_dirty_parts.keys():
		var part_id := String(part_id_value)
		var part: Dictionary = current_dirty_parts[part_id]
		part_section_index[part_id] = _section_id(String(snapshot["construct_id"]), _section_coord(part["local_position_m"], section_size))
	var sections: Array = sections_by_id.values()
	sections.sort_custom(func(a, b): return String(a["section_id"]) < String(b["section_id"]))
	var topology := {
		"schema": TOPOLOGY_SCHEMA,
		"construct_id": String(snapshot["construct_id"]),
		"source_revision": int(snapshot["state_revision"]),
		"source_checksum": String(snapshot["checksum"]),
		"section_size_m": section_size,
		"sections": sections,
		"part_section_index": part_section_index,
		"checksum": "",
	}
	topology["checksum"] = Topology.compute_checksum(topology)
	return C.success({"topology": topology, "part_lookups": part_lookups})

static func _build_section(snapshot: Dictionary, coord: Array, part_ids: Array) -> Dictionary:
	var interactive_part_ids: Array = []
	var cell_ids: Dictionary = {}
	var min_v: Array = [INF, INF, INF]
	var max_v: Array = [-INF, -INF, -INF]
	var lookups := 0
	for part_id_value in part_ids:
		var found := _find_part(snapshot, String(part_id_value))
		lookups += int(found["lookups"])
		if not bool(found["found"]):
			return C.failure("CONSTRUCTION_PROXY_INCREMENTAL_SECTION_PART_MISSING")
		var part: Dictionary = found["part"]
		var metadata: Dictionary = part["metadata"]
		if bool(metadata.get("proxy_interactive", false)):
			return C.failure("CONSTRUCTION_PROXY_INCREMENTAL_INTERACTIVE_PART_REQUIRES_FULL_COMPILE")
		var cell_id := String(metadata.get("proxy_interior_cell_id", ""))
		if not cell_id.is_empty(): cell_ids[cell_id] = true
		var dimensions: Array = Topology.part_dimensions(part)
		var position: Array = part["local_position_m"]
		for axis in range(3):
			min_v[axis] = minf(float(min_v[axis]), float(position[axis]) - float(dimensions[axis]) * 0.5)
			max_v[axis] = maxf(float(max_v[axis]), float(position[axis]) + float(dimensions[axis]) * 0.5)
	var cells: Array = cell_ids.keys(); cells.sort()
	var section := {
		"section_id": _section_id(String(snapshot["construct_id"]), coord),
		"grid_coord": coord.duplicate(true),
		"bounds_min_m": min_v,
		"bounds_max_m": max_v,
		"part_ids": part_ids.duplicate(true),
		"interactive_part_ids": interactive_part_ids,
		"interior_cell_ids": cells,
		"part_count": part_ids.size(),
		"checksum": "",
	}
	section["checksum"] = _section_checksum(section)
	return C.success({"section": section, "part_lookups": lookups})

static func _extract_local_grid_faces(snapshot: Dictionary, sections_by_id: Dictionary, target_section_set: Dictionary, context_section_ids: Array) -> Dictionary:
	var occupancy: Dictionary = {}
	var lookups := 0
	for section_id_value in context_section_ids:
		var section_id := String(section_id_value)
		if not sections_by_id.has(section_id): continue
		var section: Dictionary = sections_by_id[section_id]
		for part_id_value in section["part_ids"]:
			var found := _find_part(snapshot, String(part_id_value))
			lookups += int(found["lookups"])
			if not bool(found["found"]):
				return C.failure("CONSTRUCTION_PROXY_INCREMENTAL_CONTEXT_PART_MISSING")
			var part: Dictionary = found["part"]
			if not _part_visible(part): continue
			if not _is_unit_axis_part(part):
				return C.failure("CONSTRUCTION_PROXY_INCREMENTAL_CONTEXT_NOT_UNIT_AXIS_GRID")
			var p: Array = part["local_position_m"]
			var x := int(round(float(p[0]))); var y := int(round(float(p[1]))); var z := int(round(float(p[2])))
			var key := _voxel_key(x, y, z)
			if occupancy.has(key): return C.failure("CONSTRUCTION_PROXY_DUPLICATE_VOXEL_OCCUPANCY")
			var metadata: Dictionary = part["metadata"]
			occupancy[key] = {
				"part_id": String(part["part_id"]),
				"section_id": section_id,
				"material_key": String(metadata.get("proxy_material_key", part["role"])),
				"x": x, "y": y, "z": z,
			}
	var directions := [
		{"axis": "X", "direction": -1, "delta": [-1, 0, 0]}, {"axis": "X", "direction": 1, "delta": [1, 0, 0]},
		{"axis": "Y", "direction": -1, "delta": [0, -1, 0]}, {"axis": "Y", "direction": 1, "delta": [0, 1, 0]},
		{"axis": "Z", "direction": -1, "delta": [0, 0, -1]}, {"axis": "Z", "direction": 1, "delta": [0, 0, 1]},
	]
	var faces: Array = []
	var keys: Array = occupancy.keys(); keys.sort()
	for key_value in keys:
		var voxel: Dictionary = occupancy[key_value]
		if not target_section_set.has(String(voxel["section_id"])): continue
		for direction in directions:
			var nx := int(voxel["x"]) + int(direction["delta"][0])
			var ny := int(voxel["y"]) + int(direction["delta"][1])
			var nz := int(voxel["z"]) + int(direction["delta"][2])
			if occupancy.has(_voxel_key(nx, ny, nz)): continue
			faces.append(_grid_face(voxel, String(direction["axis"]), int(direction["direction"])))
	faces.sort_custom(func(a, b): return _face_key(a) < _face_key(b))
	return C.success({"faces": faces, "part_lookups": lookups, "occupancy_cells": occupancy.size()})

static func _same_compile_policy(previous_request: Dictionary, request: Dictionary) -> bool:
	for field in ["authority_epoch", "authority_mode", "compiler_node_id", "section_size_m", "local_distance_m", "section_distance_m", "shell_distance_m"]:
		if previous_request.get(field) != request.get(field): return false
	return true

static func _is_unit_axis_part(part: Dictionary) -> bool:
	var metadata: Dictionary = part.get("metadata", {})
	var dimensions := Topology.part_dimensions(part)
	for value in dimensions:
		if absf(float(value) - 1.0) > 0.000001: return false
	var rotation: Array = Array(metadata.get("local_rotation_quaternion", [0.0, 0.0, 0.0, 1.0]))
	if rotation.size() != 4 or absf(float(rotation[0])) > 0.000001 or absf(float(rotation[1])) > 0.000001 or absf(float(rotation[2])) > 0.000001 or absf(float(rotation[3]) - 1.0) > 0.000001: return false
	for value in part["local_position_m"]:
		if absf(float(value) - round(float(value))) > 0.000001: return false
	return true

static func _part_visible(part: Dictionary) -> bool:
	return String(Dictionary(part["metadata"]).get("condition", "INTACT")) != "DESTROYED"

static func _find_part(snapshot: Dictionary, part_id: String) -> Dictionary:
	var parts: Array = snapshot["parts"]
	var low := 0
	var high := parts.size() - 1
	var lookups := 0
	while low <= high:
		var mid := (low + high) / 2
		lookups += 1
		var candidate_id := String(parts[mid]["part_id"])
		if candidate_id == part_id:
			return {"found": true, "part": parts[mid], "lookups": lookups}
		if candidate_id < part_id: low = mid + 1
		else: high = mid - 1
	return {"found": false, "part": {}, "lookups": lookups}

static func _expand_coords(source: Dictionary, radius: int) -> Dictionary:
	var result: Dictionary = {}
	for coord_value in source.values():
		var coord: Array = coord_value
		for dz in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1):
					var expanded := [int(coord[0]) + dx, int(coord[1]) + dy, int(coord[2]) + dz]
					result[_coord_key(expanded)] = expanded
	return result

static func _construct_bounds(sections: Array) -> Dictionary:
	if sections.is_empty(): return {"success": false}
	var min_v: Array = [INF, INF, INF]
	var max_v: Array = [-INF, -INF, -INF]
	for section_value in sections:
		var section: Dictionary = section_value
		for axis in range(3):
			min_v[axis] = minf(float(min_v[axis]), float(section["bounds_min_m"][axis]))
			max_v[axis] = maxf(float(max_v[axis]), float(section["bounds_max_m"][axis]))
	return {"success": true, "bounds_min_m": min_v, "bounds_max_m": max_v}

static func _sections_by_id(sections: Array) -> Dictionary:
	var result: Dictionary = {}
	for section_value in sections:
		var section: Dictionary = section_value
		result[String(section["section_id"])] = section.duplicate(true)
	return result

static func _section_ids_by_coord(sections: Array) -> Dictionary:
	var result: Dictionary = {}
	for section_value in sections:
		var section: Dictionary = section_value
		result[_coord_key(section["grid_coord"])] = String(section["section_id"])
	return result

static func _refs_by_section(refs: Array) -> Dictionary:
	var result: Dictionary = {}
	for ref_value in refs:
		var ref: Dictionary = ref_value
		result[String(ref["section_id"])] = ref
	return result

static func _section_coord(position: Array, section_size: float) -> Array:
	return [
		int(floor(float(position[0]) / section_size)),
		int(floor(float(position[1]) / section_size)),
		int(floor(float(position[2]) / section_size)),
	]

static func _section_id(construct_id: String, coord: Array) -> String:
	return "section/%s/%s" % [construct_id.trim_prefix("construct/"), _coord_key(coord).replace("/", "_")]

static func _coord_key(coord: Array) -> String:
	return "%s/%s/%s" % [_coord_token(int(coord[0])), _coord_token(int(coord[1])), _coord_token(int(coord[2]))]

static func _coord_token(value: int) -> String:
	return "n%06d" % abs(value) if value < 0 else "p%06d" % value

static func _section_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload["checksum"] = ""
	return preload("res://scripts/network/contracts/network_contract_utils.gd").payload_hash(payload)

static func _grid_face(voxel: Dictionary, axis: String, direction: int) -> Dictionary:
	var x := int(voxel["x"]); var y := int(voxel["y"]); var z := int(voxel["z"])
	var plane := 0; var u := 0; var v := 0
	match axis:
		"X": plane = x * 2 + direction; u = y; v = z
		"Y": plane = y * 2 + direction; u = x; v = z
		"Z": plane = z * 2 + direction; u = x; v = y
	return {"kind": "GRID", "axis": axis, "direction": direction, "plane_q2": plane, "u": u, "v": v, "part_id": String(voxel["part_id"]), "section_id": String(voxel["section_id"]), "material_key": String(voxel["material_key"])}

static func _voxel_key(x: int, y: int, z: int) -> String:
	return "%d,%d,%d" % [x, y, z]

static func _face_key(face: Dictionary) -> String:
	return "%s/%d/%012d/%012d/%012d/%s/%s" % [face["axis"], int(face["direction"]), int(face["plane_q2"]) + 1000000, int(face["u"]) + 1000000, int(face["v"]) + 1000000, face["material_key"], face["part_id"]]

static func _operation_id(snapshot: Dictionary, kind: String, content_hash: String) -> String:
	return "operation/proxy-compile/%s/%s/%s" % [String(snapshot["construct_id"]).trim_prefix("construct/").replace("/", "-"), kind, content_hash]

static func _unique_sorted(values: Array) -> Array:
	var seen: Dictionary = {}
	for value in values: seen[String(value)] = true
	var result: Array = seen.keys(); result.sort(); return result

static func _fallback(reason: String) -> Dictionary:
	return C.success({"fast_path_applied": false, "fallback_reason": reason})