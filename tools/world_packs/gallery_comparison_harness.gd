extends SceneTree

## WP0.10 — pack gallery comparison harness.
##
## For every registered pack this captures the WP0.10 record fields:
## pack id/version, asset set, surface/POI catalogs, renderer, Godot build,
## object budget (mesh instances + MultiMesh instances) and node/mesh counts.
## Draw calls require a graphical run and are recorded as pending.
## Also boots the gallery scene headless as a boot check.
##
## Headless usage:
##   godot --headless --path <project> --script res://tools/world_packs/gallery_comparison_harness.gd
##
## Exit codes:
##   0 = capture written and gallery boots
##   1 = capture or boot failed
##   2 = usage error

const RegistryScript = preload("res://scripts/world_packs/pack_registry.gd")

const GALLERY_SCENE: String = "res://scenes/labs/world_packs/world_packs_gallery.tscn"
const OUTPUT_PATH: String = "res://validation/world_packs/wp0_10_gallery_comparison.v1.json"


func _init() -> void:
	_run()


func _run() -> void:
	var failures: PackedStringArray = PackedStringArray()
	var pack_records: Array = []

	for pack_id in RegistryScript.ids():
		var profile: RefCounted = RegistryScript.make_profile(String(pack_id))
		var manifest: Dictionary = profile.manifest()
		if manifest.is_empty():
			failures.append("%s: manifest unreadable" % pack_id)
			continue
		var root := Node3D.new()
		profile.apply_environment(root)
		profile.build_pad(root)
		var stats: Dictionary = _count_objects(root)
		if int(stats["meshes"]) < 5:
			failures.append("%s: too few meshes (%d)" % [pack_id, int(stats["meshes"])])
		pack_records.append({
			"pack_id": String(pack_id),
			"version": String(manifest.get("version", "")),
			"display_name": String(manifest.get("display_name", "")),
			"asset_set": "asset-free-procedural-r1",
			"surface_catalog": manifest.get("materials", {}).get("surface_catalog", []),
			"poi_catalog": manifest.get("poi", {}).get("catalog", []),
			"nodes": int(stats["nodes"]),
			"mesh_instances": int(stats["meshes"]),
			"multimesh_instances": int(stats["multimesh_instances"]),
			"object_budget": int(stats["object_budget"]),
			"draw_calls": "pending_graphical_run",
		})
		root.free()

	var gallery_boot: Dictionary = await _boot_gallery()
	if not bool(gallery_boot["ok"]):
		failures.append("gallery scene did not boot: %s" % String(gallery_boot["error"]))

	var record: Dictionary = {
		"schema": "planet_simulator.world_packs_gallery_comparison.v1",
		"generated": Time.get_date_string_from_system(),
		"engine": {
			"version_string": Engine.get_version_info().get("string", ""),
			"build": _build_string(),
			"precision": "double",
			"renderer": String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
			"mode": "headless",
		},
		"gallery_scene": GALLERY_SCENE,
		"gallery_boot": gallery_boot,
		"capture": {
			"screenshot": "pending_graphical_mcp_capture",
		},
		"packs": pack_records,
	}

	DirAccess.make_dir_recursive_absolute("res://validation/world_packs")
	var file: FileAccess = FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		print("WORLD_PACKS_GALLERY_HARNESS: FAILED (cannot write %s)" % OUTPUT_PATH)
		quit(1)
		return
	file.store_string(JSON.stringify(record, "\t"))
	file.close()

	if not failures.is_empty():
		for failure in failures:
			print("WORLD_PACKS_GALLERY_HARNESS: FAIL %s" % failure)
		print("WORLD_PACKS_GALLERY_HARNESS: FAILED")
		quit(1)
		return

	print("WORLD_PACKS_GALLERY_HARNESS: PASS (%d pack(s) captured)" % pack_records.size())
	print("WORLD_PACKS_GALLERY_HARNESS_READY")
	quit(0)


func _boot_gallery() -> Dictionary:
	var packed: PackedScene = load(GALLERY_SCENE)
	if packed == null:
		return {"ok": false, "error": "scene failed to load"}
	var instance: Node = packed.instantiate()
	if instance == null:
		return {"ok": false, "error": "scene failed to instantiate"}
	root.add_child(instance)
	# _ready of the gallery fires on the first tree iteration for a root
	# added from a SceneTree script's _init; count only after one frame.
	await process_frame
	var pads: int = 0
	for child in instance.get_children():
		if String(child.name).begins_with("WP-"):
			pads += 1
	var node_count: int = _count_nodes(instance)
	instance.queue_free()
	await process_frame
	return {"ok": true, "pads": pads, "nodes": node_count}


func _build_string() -> String:
	var info: Dictionary = Engine.get_version_info()
	return "%d.%d.%d.%s.%s" % [
		int(info.get("major", 0)), int(info.get("minor", 0)), int(info.get("patch", 0)),
		String(info.get("status", "")), String(info.get("hash", "")).substr(0, 9),
	]


func _count_objects(root: Node) -> Dictionary:
	var nodes: int = 0
	var meshes: int = 0
	var multimesh_instances: int = 0
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		nodes += 1
		if node is MeshInstance3D:
			meshes += 1
		if node is MultiMeshInstance3D:
			var mm: MultiMesh = (node as MultiMeshInstance3D).multimesh
			if mm != null:
				multimesh_instances += mm.instance_count
		for child in node.get_children():
			stack.append(child)
	return {
		"nodes": nodes,
		"meshes": meshes,
		"multimesh_instances": multimesh_instances,
		"object_budget": meshes + multimesh_instances,
	}


func _count_nodes(root: Node) -> int:
	var count: int = 0
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		count += 1
		for child in node.get_children():
			stack.append(child)
	return count
