extends SceneTree

## WP0.9 — shared POI library contract selftest.
##
## Asserts that:
##   1. every POI referenced by any pack manifest is supported by the library;
##   2. every supported builder returns a named node with mesh content;
##   3. builders honor the skin palette (skinnability contract);
##   4. unknown ids degrade to an empty named node (documented behavior).
##
## Headless usage:
##   godot --headless --path <project> --script res://tools/world_packs/poi_library_selftest.gd
##
## Exit codes:
##   0 = library contract holds
##   1 = contract violation

const PoiLibrary = preload("res://scripts/world_packs/poi/poi_library.gd")

const PACKS_DIR: String = "res://config/world_packs/packs"


func _init() -> void:
	var failures: PackedStringArray = PackedStringArray()
	var referenced: Dictionary = {}
	for manifest_path in _list_manifests():
		var manifest: Dictionary = _read_json(manifest_path)
		if manifest.is_empty():
			failures.append("unreadable manifest: %s" % manifest_path)
			continue
		for poi_id in manifest.get("poi", {}).get("catalog", []):
			referenced[String(poi_id)] = String(manifest["pack_id"])

	var supported: PackedStringArray = PoiLibrary.supported_ids()
	for poi_id in referenced:
		if not supported.has(String(poi_id)):
			failures.append("%s references unsupported POI: %s" % [referenced[poi_id], poi_id])

	var mesh_total: int = 0
	for poi_id in supported:
		var node: Node3D = PoiLibrary.build(String(poi_id), {})
		if node == null:
			failures.append("builder returned null for %s" % poi_id)
			continue
		if node.name != "POI_%s" % String(poi_id):
			failures.append("builder name mismatch for %s: %s" % [poi_id, node.name])
		var meshes: int = _count_meshes(node)
		mesh_total += meshes
		if meshes < 2:
			failures.append("builder for %s produced only %d mesh(es)" % [poi_id, meshes])
		node.free()

	var custom_accent: Color = Color(0.1, 0.8, 0.4)
	var skinned: Node3D = PoiLibrary.build("beacon", {"emissive": custom_accent})
	var lamp: Node = skinned.get_node_or_null("Lamp")
	if lamp == null or not (lamp is MeshInstance3D):
		failures.append("beacon skin test: Lamp missing")
	elif not ((lamp as MeshInstance3D).material_override as StandardMaterial3D).emission.is_equal_approx(custom_accent):
		failures.append("beacon skin test: emissive palette was not applied")
	skinned.free()

	var unknown: Node3D = PoiLibrary.build("definitely_not_supported", {})
	if unknown == null or unknown.name != "POI_definitely_not_supported" or unknown.get_child_count() != 0:
		failures.append("unknown POI id does not degrade to an empty named node")
	unknown.free()

	if failures.is_empty():
		print("WORLD_PACKS_POI_LIBRARY: PASS (%d builders, %d meshes, %d referenced ids)" % [
			supported.size(), mesh_total, referenced.size(),
		])
		print("WORLD_PACKS_POI_LIBRARY_READY")
		quit(0)
	else:
		for failure in failures:
			print("WORLD_PACKS_POI_LIBRARY: FAIL %s" % failure)
		print("WORLD_PACKS_POI_LIBRARY: FAILED")
		quit(1)


func _list_manifests() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(PACKS_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".json"):
			result.append("%s/%s" % [PACKS_DIR, entry])
		entry = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result


func _read_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _count_meshes(root: Node) -> int:
	var count: int = 0
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			count += 1
		for child in node.get_children():
			stack.append(child)
	return count
