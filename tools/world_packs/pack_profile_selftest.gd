extends SceneTree

## WORLD PACKS — presentation profile selftest (WP0.3+).
##
## For every pack: loads its manifest, builds the presentation from the pack
## profile and asserts the structural contract (environment, sun, ground,
## scatter, POI coverage from the manifest catalog).
##
## Headless usage:
##   godot --headless --path <project> --script res://tools/world_packs/pack_profile_selftest.gd -- --pack=WP-MOON-INDUSTRIAL
##   godot --headless --path <project> --script res://tools/world_packs/pack_profile_selftest.gd -- --all
##
## Exit codes:
##   0 = every requested pack passed
##   1 = at least one pack failed
##   2 = usage error

const RegistryScript = preload("res://scripts/world_packs/pack_registry.gd")

const MANIFEST_SCHEMA_CONST: String = "dws.world_pack.v1"


func _init() -> void:
	var options: Dictionary = _parse_options(OS.get_cmdline_user_args())
	if options.is_empty():
		print("WORLD_PACKS_PROFILE: USAGE ERROR (expected --pack=ID or --all)")
		quit(2)
		return

	var pack_ids: PackedStringArray = PackedStringArray()
	if bool(options["all"]):
		pack_ids = RegistryScript.ids()
	else:
		var requested: String = String(options["pack"])
		if not RegistryScript.has(requested):
			print("WORLD_PACKS_PROFILE: USAGE ERROR (unknown pack id: %s)" % requested)
			quit(2)
			return
		pack_ids.append(requested)

	var failed: int = 0
	for pack_id in pack_ids:
		if not _check_pack(String(pack_id)):
			failed += 1

	if failed == 0:
		print("WORLD_PACKS_PROFILE: PASS (%d pack(s))" % pack_ids.size())
		quit(0)
	else:
		print("WORLD_PACKS_PROFILE: FAIL (%d of %d pack(s) failed)" % [failed, pack_ids.size()])
		quit(1)


func _parse_options(user_args: PackedStringArray) -> Dictionary:
	var options: Dictionary = {"all": false, "pack": ""}
	for raw_arg in user_args:
		var arg: String = String(raw_arg)
		if arg == "--all":
			options["all"] = true
		elif arg.begins_with("--pack="):
			options["pack"] = arg.substr("--pack=".length())
		else:
			print("WORLD_PACKS_PROFILE: USAGE ERROR (unexpected argument: %s)" % arg)
			return {}
	if not bool(options["all"]) and String(options["pack"]).is_empty():
		return {}
	return options


func _check_pack(pack_id: String) -> bool:
	var profile: RefCounted = RegistryScript.make_profile(pack_id)
	var failures: PackedStringArray = PackedStringArray()

	if String(profile.pack_id()) != pack_id:
		failures.append("profile pack_id mismatch: %s" % profile.pack_id())

	var manifest: Dictionary = profile.manifest()
	if manifest.is_empty():
		failures.append("manifest unreadable: %s" % profile.manifest_path())
		return _report(pack_id, null, failures)
	if String(manifest.get("schema", "")) != MANIFEST_SCHEMA_CONST:
		failures.append("manifest schema const mismatch")
	if String(manifest.get("pack_id", "")) != pack_id:
		failures.append("manifest pack_id mismatch: %s" % String(manifest.get("pack_id", "")))

	var root := Node3D.new()
	profile.apply_environment(root)
	profile.build_pad(root)

	if root.get_node_or_null("WP_Environment") == null:
		failures.append("missing WP_Environment")
	var sun: Node = root.get_node_or_null("WP_Sun")
	if sun == null or not (sun is DirectionalLight3D):
		failures.append("missing or invalid WP_Sun")
	var ground: Node = root.get_node_or_null("WP_Ground")
	if ground == null or not (ground is MeshInstance3D):
		failures.append("missing or invalid WP_Ground")
	elif (ground as MeshInstance3D).material_override == null:
		failures.append("WP_Ground has no material_override")

	var scatter_spec: Dictionary = profile.spec().get("scatter", {})
	var expected_scatter: int = int(scatter_spec.get("count", 0))
	var scatter: Node = root.get_node_or_null("WP_Scatter")
	if expected_scatter > 0:
		if scatter == null or not (scatter is MultiMeshInstance3D):
			failures.append("missing or invalid WP_Scatter")
		elif (scatter as MultiMeshInstance3D).multimesh.instance_count != expected_scatter:
			failures.append("WP_Scatter instance count %d != expected %d" % [
				(scatter as MultiMeshInstance3D).multimesh.instance_count, expected_scatter,
			])

	var catalog: Array = []
	if manifest.has("poi") and manifest["poi"].has("catalog"):
		catalog = manifest["poi"]["catalog"]
	for poi_id in catalog:
		if root.get_node_or_null("POI_%s" % String(poi_id)) == null:
			failures.append("manifest POI missing from pad: %s" % String(poi_id))

	var mesh_count: int = 0
	for node in _descendants(root):
		if node is MeshInstance3D:
			mesh_count += 1
	if mesh_count < 5:
		failures.append("too few MeshInstance3D nodes: %d" % mesh_count)

	print("STATS %s: nodes=%d meshes=%d poi=%d" % [pack_id, _descendants(root).size(), mesh_count, catalog.size()])
	var ok: bool = failures.is_empty()
	var sentinel: String = "WORLD_PACKS_PROFILE_%s_%s" % [
		pack_id.replace("-", "_"),
		"READY" if ok else "FAILED",
	]
	root.free()
	return _report(pack_id, sentinel, failures)


func _report(pack_id: String, sentinel: Variant, failures: PackedStringArray) -> bool:
	if sentinel != null:
		print(sentinel)
	if not failures.is_empty():
		for failure in failures:
			print("FAIL %s: %s" % [pack_id, failure])
		return false
	return true


func _descendants(root: Node) -> Array:
	var result: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			result.append(child)
			stack.append(child)
	return result
