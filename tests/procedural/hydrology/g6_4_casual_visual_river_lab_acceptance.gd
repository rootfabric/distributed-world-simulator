extends SceneTree

const LAB_SCRIPT := "res://scripts/labs/procedural/g6_4_casual_visual_river_lab.gd"
const LAB_SCENE := "res://scenes/labs/procedural/g6_4_casual_visual_river_lab.tscn"
const MANIFEST := "res://config/procedural/g6-4-casual-visual-river-lab.v1.json"

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_manifest()
	_test_files_and_scene_contract()
	_test_visual_source_contract()
	_test_p0_boundaries()
	_finish()


func _test_manifest() -> void:
	_check(FileAccess.file_exists(MANIFEST), "G6.4 manifest exists")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	_check(parsed is Dictionary, "G6.4 manifest parses")
	if not parsed is Dictionary:
		return
	_check(String(parsed.get("checkpoint", "")) == "g6.4-casual-visual-river-lab", "G6.4 checkpoint pinned")
	_check(String(parsed.get("status", "")) == "IMPLEMENTED_CANDIDATE", "G6.4 candidate status pinned")
	_check(String(parsed.get("global_program_revision", "")) == "GLOBAL-P0-2026-08-08-R1", "G6.4 global revision pinned")
	_check(String(parsed.get("scene", "")) == LAB_SCENE, "G6.4 scene pinned")
	_check(String(parsed.get("script", "")) == LAB_SCRIPT, "G6.4 script pinned")
	var dependencies: Dictionary = parsed.get("dependencies", {})
	_check(String(dependencies.get("g6_1_canonical_geography", "")) == "ACCEPTED", "G6.4 consumes accepted G6.1")
	_check(String(dependencies.get("g6_2_cross_cell_cross_lod_continuity", "")) == "ACCEPTED", "G6.4 consumes accepted G6.2")
	_check(String(dependencies.get("g6_3_runtime_water_surface_query", "")) == "ACCEPTED", "G6.4 consumes accepted G6.3")
	var presentation: Dictionary = parsed.get("presentation", {})
	_check(bool(presentation.get("water_ribbon", false)), "G6.4 water ribbon enabled")
	_check(bool(presentation.get("canonical_centerline", false)), "G6.4 centerline overlay enabled")
	_check(bool(presentation.get("bank_guides", false)), "G6.4 bank guides enabled")
	_check(bool(presentation.get("query_probes", false)), "G6.4 query probes enabled")
	_check(bool(presentation.get("cube_face_seam_marker", false)), "G6.4 seam marker enabled")
	_check(float(presentation.get("water_width_exaggeration", 0.0)) > 1.0, "G6.4 visual width exaggeration explicit")
	_check(String(parsed.get("next_if_accepted", "")) == "G6_FULL_ACCEPTANCE", "G6.4 next gate pinned")


func _test_files_and_scene_contract() -> void:
	_check(FileAccess.file_exists(LAB_SCRIPT), "G6.4 lab script exists")
	_check(FileAccess.file_exists(LAB_SCENE), "G6.4 lab scene exists")
	var scene_source := FileAccess.get_file_as_string(LAB_SCENE)
	_check(scene_source.find("G64CasualVisualRiverLab") >= 0, "G6.4 scene root pinned")
	_check(scene_source.find("SphereMesh") >= 0, "G6.4 scene has globe presentation")
	_check(scene_source.find("Camera3D") >= 0, "G6.4 scene has camera")
	_check(scene_source.find("DirectionalLight3D") >= 0, "G6.4 scene has lighting")
	_check(scene_source.find("HUD") >= 0, "G6.4 scene has HUD")
	_check(scene_source.find(LAB_SCRIPT) >= 0, "G6.4 scene loads lab script")


func _test_visual_source_contract() -> void:
	var source := FileAccess.get_file_as_string(LAB_SCRIPT)
	_check(source.find("CasualRiverProvider.compile") >= 0, "G6.4 compiles accepted canonical geography")
	_check(source.find("WaterSurfaceQuery.create") >= 0, "G6.4 creates accepted query contract")
	_check(source.find("WaterSurfaceResolver.resolve") >= 0, "G6.4 consumes accepted G6.3 resolver")
	_check(source.find("CubeSphereAddressing") >= 0, "G6.4 uses G2 addressing for debug seam only")
	_check(source.find("RiverRibbon") >= 0, "G6.4 ribbon presentation exists")
	_check(source.find("CanonicalCenterline") >= 0, "G6.4 centerline debug exists")
	_check(source.find("BankGuides") >= 0, "G6.4 bank debug exists")
	_check(source.find("QueryProbes") >= 0, "G6.4 query probe debug exists")
	_check(source.find("CubeFaceSeamMarkers") >= 0, "G6.4 seam debug exists")
	_check(source.find("WIDTH_EXAGGERATION") >= 0, "G6.4 visual width exaggeration explicit in source")
	_check(source.find("DisplayServer.get_name() == \"headless\"") >= 0, "G6.4 supports headless smoke")
	_check(source.find("PX") >= 0 and source.find("PZ") >= 0, "G6.4 PX/PZ coverage asserted")
	for control in ["KEY_A", "KEY_D", "KEY_Q", "KEY_E", "KEY_W", "KEY_S", "KEY_SPACE", "KEY_R", "KEY_1", "KEY_2", "KEY_3", "KEY_4", "KEY_5"]:
		_check(source.find(control) >= 0, "G6.4 control %s present" % control)


func _test_p0_boundaries() -> void:
	var source := FileAccess.get_file_as_string(LAB_SCRIPT)
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if manifest is Dictionary:
		var boundaries: Dictionary = manifest.get("architecture_boundaries", {})
		for key in [
			"renderer_is_canonical_truth",
			"visual_width_is_canonical_width",
			"surface_cell_is_fluid_identity",
			"lod_is_fluid_identity",
			"cube_face_is_fluid_identity",
			"query_cache_is_fluid_identity",
			"visual_lab_owns_authority",
			"visual_lab_mutates_world_state",
			"visual_lab_owns_persistence",
			"visual_lab_owns_network_transport",
		]:
			_check(not bool(boundaries.get(key, true)), "G6.4 P0 boundary %s false" % key)

	for forbidden in [
		"FeatureIdScript.derive",
		"FluidRegionIdScript.derive",
		"WorldFeature.create",
		"SurfaceCellKey.create",
		"MultiplayerPeer",
		"ENetMultiplayerPeer",
		"AuthorityRegion",
		"InterestRegion",
		"FileAccess.store_",
		"DirAccess.remove",
		"RandomNumberGenerator",
		"randf(",
		"randi(",
	]:
		_check(source.find(forbidden) == -1, "G6.4 lab excludes %s" % forbidden)


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("G6.4 Casual Visual River Lab contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("G6.4 Casual Visual River Lab contracts: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)
