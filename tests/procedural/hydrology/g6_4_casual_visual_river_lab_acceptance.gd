extends SceneTree

const LAB_SCRIPT := "res://scripts/labs/procedural/g6_4_casual_visual_river_lab.gd"
const SURFACE_SCRIPT := "res://scripts/labs/procedural/g6_4_adaptive_macro_surface_presenter.gd"
const LAB_SCENE := "res://scenes/labs/procedural/g6_4_casual_visual_river_lab.tscn"
const MANIFEST := "res://config/procedural/g6-4-casual-visual-river-lab.v1.json"

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_manifest()
	_test_files_and_scene_contract()
	_test_visual_source_contract()
	_test_adaptive_lod_contract()
	_test_adaptive_macro_surface_contract()
	_test_p0_boundaries()
	_finish()


func _test_manifest() -> void:
	_check(FileAccess.file_exists(MANIFEST), "G6.4 manifest exists")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	_check(parsed is Dictionary, "G6.4 manifest parses")
	if not parsed is Dictionary:
		return
	_check(String(parsed.get("checkpoint", "")) == "g6.4-casual-visual-river-lab", "G6.4 checkpoint pinned")
	_check(String(parsed.get("status", "")) == "FIX3_IMPLEMENTED_CANDIDATE", "G6.4 fix3 candidate status pinned")
	_check(String(parsed.get("global_program_revision", "")) == "GLOBAL-P0-2026-08-08-R1", "G6.4 global revision pinned")
	_check(String(parsed.get("scene", "")) == LAB_SCENE, "G6.4 scene pinned")
	_check(String(parsed.get("script", "")) == LAB_SCRIPT, "G6.4 lab script pinned")
	_check(String(parsed.get("adaptive_macro_surface_script", "")) == SURFACE_SCRIPT, "G6.4 adaptive surface script pinned")
	var dependencies: Dictionary = parsed.get("dependencies", {})
	_check(String(dependencies.get("g2_surface_lod_selector", "")) == "ACCEPTED", "G6.4 consumes accepted G2 LOD")
	_check(String(dependencies.get("g3_casual_macro_surface_provider", "")) == "ACCEPTED", "G6.4 consumes accepted G3 macro provider")
	_check(String(dependencies.get("g6_1_canonical_geography", "")) == "ACCEPTED", "G6.4 consumes accepted G6.1")
	_check(String(dependencies.get("g6_2_cross_cell_cross_lod_continuity", "")) == "ACCEPTED", "G6.4 consumes accepted G6.2")
	_check(String(dependencies.get("g6_3_runtime_water_surface_query", "")) == "ACCEPTED", "G6.4 consumes accepted G6.3")
	var presentation: Dictionary = parsed.get("presentation", {})
	_check(bool(presentation.get("water_ribbon", false)), "G6.4 water ribbon enabled")
	_check(bool(presentation.get("canonical_centerline", false)), "G6.4 centerline overlay enabled")
	_check(bool(presentation.get("bank_guides", false)), "G6.4 bank guides enabled")
	_check(bool(presentation.get("query_probes", false)), "G6.4 query probes enabled")
	_check(bool(presentation.get("cube_face_seam_marker", false)), "G6.4 seam marker enabled")
	_check(bool(presentation.get("adaptive_surface_lod_grid", false)), "G6.4 adaptive LOD grid enabled")
	_check(bool(presentation.get("adaptive_river_sampling", false)), "G6.4 adaptive river sampling enabled")
	_check(bool(presentation.get("adaptive_macro_surface_mesh", false)), "G6.4 adaptive macro surface enabled")
	_check(String(presentation.get("macro_surface_provider", "")) == "geo-provider/casual-macro-terrain-v1", "G6.4 G3 macro provider pinned")
	_check(int(presentation.get("macro_cell_segments", 0)) >= 2, "G6.4 macro surface has per-cell geometry")
	_check(float(presentation.get("macro_height_display_exaggeration", 0.0)) > 1.0, "G6.4 macro height display exaggeration explicit")
	_check(bool(presentation.get("macro_height_exaggeration_is_presentation_only", false)), "G6.4 macro height exaggeration presentation-only")
	_check(int(presentation.get("lod_min", -1)) == 0, "G6.4 LOD min pinned")
	_check(int(presentation.get("lod_max", -1)) == 12, "G6.4 LOD max pinned")
	_check(int(presentation.get("lod_leaf_budget", 0)) >= 1024, "G6.4 LOD leaf budget meaningful")
	_check(float(presentation.get("water_width_exaggeration", 0.0)) > 1.0, "G6.4 visual width exaggeration explicit")
	var acceptance: Dictionary = parsed.get("acceptance", {})
	_check(String(acceptance.get("adaptive_macro_surface_explicit_pass_marker", "")) == "REQUIRED", "G6.4 adaptive surface marker required")
	_check(String(acceptance.get("near_macro_surface_triangle_count_greater_than_far", "")) == "REQUIRED", "G6.4 adaptive surface geometry refinement required")
	_check(String(parsed.get("next_if_accepted", "")) == "G6_FULL_ACCEPTANCE", "G6.4 next gate pinned")


func _test_files_and_scene_contract() -> void:
	_check(FileAccess.file_exists(LAB_SCRIPT), "G6.4 lab script exists")
	_check(FileAccess.file_exists(SURFACE_SCRIPT), "G6.4 adaptive macro surface script exists")
	_check(FileAccess.file_exists(LAB_SCENE), "G6.4 lab scene exists")
	var scene_source := FileAccess.get_file_as_string(LAB_SCENE)
	_check(scene_source.find("G64CasualVisualRiverLab") >= 0, "G6.4 scene root pinned")
	_check(scene_source.find("AdaptiveMacroSurface") >= 0, "G6.4 scene has adaptive macro surface node")
	_check(scene_source.find(SURFACE_SCRIPT) >= 0, "G6.4 scene loads adaptive macro surface script")
	_check(scene_source.find("visible = false") >= 0, "G6.4 fixed sphere hidden behind adaptive surface")
	_check(scene_source.find("Camera3D") >= 0, "G6.4 scene has camera")
	_check(scene_source.find("near = 0.001") >= 0, "G6.4 camera supports near-surface LOD inspection")
	_check(scene_source.find("DirectionalLight3D") >= 0, "G6.4 scene has lighting")
	_check(scene_source.find("HUD") >= 0, "G6.4 scene has HUD")
	_check(scene_source.find(LAB_SCRIPT) >= 0, "G6.4 scene loads lab script")


func _test_visual_source_contract() -> void:
	var source := FileAccess.get_file_as_string(LAB_SCRIPT)
	_check(source.find("CasualRiverProvider.compile") >= 0, "G6.4 compiles accepted canonical geography")
	_check(source.find("WaterSurfaceQuery.create") >= 0, "G6.4 creates accepted query contract")
	_check(source.find("WaterSurfaceResolver.resolve") >= 0, "G6.4 consumes accepted G6.3 resolver")
	_check(source.find("CubeSphereAddressing") >= 0, "G6.4 uses G2 addressing for representation/debug")
	_check(source.find("RiverRibbon") >= 0, "G6.4 ribbon presentation exists")
	_check(source.find("CanonicalCenterline") >= 0, "G6.4 centerline debug exists")
	_check(source.find("BankGuides") >= 0, "G6.4 bank debug exists")
	_check(source.find("QueryProbes") >= 0, "G6.4 query probe debug exists")
	_check(source.find("CubeFaceSeamMarkers") >= 0, "G6.4 seam debug exists")
	_check(source.find("SurfaceLodGrid") >= 0, "G6.4 LOD grid presentation exists")
	_check(source.find("WIDTH_EXAGGERATION") >= 0, "G6.4 visual width exaggeration explicit in source")
	_check(source.find("DisplayServer.get_name() == \"headless\"") >= 0, "G6.4 supports headless smoke")
	_check(source.find("PX") >= 0 and source.find("PZ") >= 0, "G6.4 PX/PZ coverage asserted")
	for control in ["KEY_A", "KEY_D", "KEY_Q", "KEY_E", "KEY_W", "KEY_S", "KEY_SPACE", "KEY_R", "KEY_1", "KEY_2", "KEY_3", "KEY_4", "KEY_5", "KEY_6"]:
		_check(source.find(control) >= 0, "G6.4 control %s present" % control)


func _test_adaptive_lod_contract() -> void:
	var source := FileAccess.get_file_as_string(LAB_SCRIPT)
	for required in [
		"SurfaceLodPolicy",
		"SurfaceLodSelector",
		"BodyFixedPosition",
		"selector.configure",
		"selector.select_cells",
		"_refresh_lod_presentation",
		"_selected_lod_for_direction",
		"_subdivisions_for_lod",
		"representation_lod",
		"_build_lod_grid_mesh",
		"_lod_profile_for_distance",
		"planned_river_samples",
		"G6_4_HEADLESS_LOD_DID_NOT_REFINE",
		"G6_4_HEADLESS_RIVER_REPRESENTATION_DID_NOT_REFINE",
	]:
		_check(source.find(required) >= 0, "G6.4 adaptive LOD source includes %s" % required)
	_check(source.find("current_selection_hash") >= 0, "G6.4 LOD rebuild keyed by derived selection hash")
	_check(source.find("current_max_lod") >= 0, "G6.4 exposes active max LOD")
	_check(source.find("current_min_river_lod") >= 0 and source.find("current_max_river_lod") >= 0, "G6.4 exposes river representation LOD range")
	_check(source.find("River samples:") >= 0, "G6.4 HUD exposes adaptive river sample count")
	_check(source.find("Max LOD:") >= 0, "G6.4 HUD exposes adaptive max LOD")


func _test_adaptive_macro_surface_contract() -> void:
	var source := FileAccess.get_file_as_string(SURFACE_SCRIPT)
	for required in [
		"CasualMacroTerrainProviderV1",
		"casual_macro_terrain_provider_v1.gd",
		"SurfaceLodSelector",
		"selector.select_cells",
		"cell_uv_bounds",
		"face_uv_to_direction",
		"MacroProvider.FIELD_SURFACE_HEIGHT_M",
		"CELL_SEGMENTS",
		"HEIGHT_DISPLAY_EXAGGERATION",
		"_rebuild_mesh",
		"surface_add_vertex",
		"last_triangle_count",
		"_headless_detail_smoke",
		"G6_4_MACRO_SURFACE_LOD_DID_NOT_REFINE",
		"G6_4_MACRO_SURFACE_GEOMETRY_DID_NOT_REFINE",
		"G6.4 Adaptive Macro Surface: PASS",
	]:
		_check(source.find(required) >= 0, "G6.4 adaptive macro surface includes %s" % required)
	_check(source.find("planned_triangles") >= 0, "G6.4 adaptive macro surface exposes planned triangle detail")
	_check(source.find("near[\"planned_triangles\"]") >= 0 and source.find("far[\"planned_triangles\"]") >= 0, "G6.4 macro surface compares near/far geometry")


func _test_p0_boundaries() -> void:
	var lab_source := FileAccess.get_file_as_string(LAB_SCRIPT)
	var surface_source := FileAccess.get_file_as_string(SURFACE_SCRIPT)
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
			"lod_selector_changes_canonical_geography",
			"lod_selector_changes_fluid_region_id",
			"lod_selector_changes_feature_id",
			"macro_surface_mesh_is_canonical_truth",
			"macro_height_display_exaggeration_changes_geo_sample",
			"macro_surface_carves_river_valley",
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
		_check(lab_source.find(forbidden) == -1, "G6.4 lab excludes %s" % forbidden)
		_check(surface_source.find(forbidden) == -1, "G6.4 adaptive surface excludes %s" % forbidden)


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
