extends SceneTree

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const ViewerScene = preload("res://scenes/labs/ecology/eco_evo7_vis3_planet_biome_viewer.tscn")
const TerrainOverlay = preload("res://scripts/labs/ecology/eco_evo7_vis3_terrain_biome_overlay.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
    var world = EarthWorld.new(); root.add_child(world)
    _check(world.setup(null), "real Earth source initializes")

    var viewer = ViewerScene.instantiate(); viewer.auto_initialize = false; viewer.ensure_ui_built(); root.add_child(viewer)
    _check(viewer.initialize_runtime(world), "VIS3 initializes over accepted VIS2/Workbench")

    var identity: Dictionary = viewer.get_runtime_identity()
    _check(String(identity.get("scene_name", "")) == "EcoEvo7VIS3PlanetBiomeViewer", "VIS3 runtime identity names exact scene")
    _check(String(identity.get("viewer_title", "")) == "ECO EVO7 — VIS3 Planet Patch / Biome Viewer", "VIS3 runtime title is unambiguous")
    _check(String(identity.get("revision", "")) == "ECO.EVO7-VIS3.R1", "VIS3 runtime revision is R1")
    var top_title := viewer.get_node_or_null("VIS1UI/Root/Top").get_child(0) as Label
    _check(top_title != null and top_title.text.contains("VIS3 Planet Patch"), "VIS3 replaces inherited VIS2 title")

    var contract: Dictionary = viewer.get_ui_contract()
    for key in ["terrain_overlay", "hillshade", "biome_boundaries", "multi_scale_camera", "history_timeline", "performance_hud", "region_lod", "patch_lod", "plant_lod"]:
        _check(bool(contract.get(key, false)), "VIS3 UI contract exposes %s" % key)
    _check(bool(contract.get("procedural_plants", false)) and bool(contract.get("phenotype_driven", false)), "VIS3 preserves accepted VIS2 procedural plants")
    _check(bool(contract.get("presentation_only", false)), "VIS3 remains presentation-only")

    var render_contract: Dictionary = viewer.terrain_overlay.get_render_contract()
    for key in ["terrain", "hillshade", "contours", "biome_boundaries", "region_lod", "patch_lod", "plant_lod", "history_summary", "presentation_only"]:
        _check(bool(render_contract.get(key, false)), "terrain renderer contract exposes %s" % key)

    var terrain: Dictionary = viewer.get_terrain_summary()
    _check(int(terrain.get("grid_size", 0)) == 32 and int(terrain.get("cell_count", 0)) == 1024, "VIS3 terrain is the accepted 32x32 patch")
    _check(is_equal_approx(float(terrain.get("cell_size_m", 0.0)), 16.0), "VIS3 terrain preserves physical 16m cell size")
    _check(is_equal_approx(float(terrain.get("patch_width_m", 0.0)), 512.0), "VIS3 terrain exposes 512m physical patch width")
    _check(float(terrain.get("elevation_span_m", 0.0)) > 1.0, "VIS3 terrain has real non-flat elevation span")
    _check(String(terrain.get("effective_lod", "")) == TerrainOverlay.LOD_PATCH, "1x camera resolves to PATCH LOD")
    _check(not bool(terrain.get("history_mode", true)), "VIS3 starts in live terrain mode")

    var initial_state: Dictionary = viewer.get_view_state()
    var initial_ecology_hash := String(initial_state.get("ecology_state_hash", ""))
    var initial_workbench_hash := String(initial_state.get("workbench_hash", ""))
    _check(initial_ecology_hash.length() == 64 and initial_workbench_hash.length() == 64, "initial causal identities are valid")

    var history0: Dictionary = viewer.get_history_state()
    _check(int(history0.get("frame_count", 0)) == 1, "VIS3 captures one initial observed frame")
    _check(bool(history0.get("history_live", false)), "initial history cursor is live")
    _check(int(history0.get("displayed_generation", -1)) == 0 and int(history0.get("live_generation", -1)) == 0, "initial history is generation zero")
    _check(int(history0.get("history_limit", 0)) == 64, "VIS3 history is explicitly bounded")
    var frame0: Dictionary = viewer.get_history_frame(0)
    _check(_exact_history_frame(frame0), "initial history frame has compact canonical VIS3 fields")
    _check(Array(frame0.get("population_counts", [])).size() == 1024 and Array(frame0.get("biome_labels", [])).size() == 1024, "history frame stores per-cell population/biome summaries")
    _check(_sum_counts(Array(frame0["population_counts"])) == int(frame0.get("population_count", -1)), "history population summary is internally consistent")
    _check(int(frame0.get("population_count", 0)) == 64, "generation-zero history captures 64 founders")

    _check(viewer.set_lod_mode(TerrainOverlay.LOD_REGION, true), "VIS3 selects REGION LOD")
    var region_state: Dictionary = viewer.get_view_state()
    _check(is_equal_approx(float(region_state.get("camera_zoom", 0.0)), 0.55), "REGION preset sets wide camera")
    _check(String(viewer.get_terrain_summary().get("effective_lod", "")) == TerrainOverlay.LOD_REGION, "terrain resolves REGION LOD")
    _check(not viewer.plant_overlay.visible, "REGION LOD hides individual plant geometry")
    _check(String(viewer.get_view_state().get("ecology_state_hash", "")) == initial_ecology_hash, "LOD/camera cannot change ecology")
    _check(String(viewer.get_view_state().get("workbench_hash", "")) == initial_workbench_hash, "LOD/camera cannot change Workbench identity")

    _check(viewer.set_lod_mode(TerrainOverlay.LOD_PATCH, true), "VIS3 selects PATCH LOD")
    _check(viewer.plant_overlay.visible, "PATCH LOD restores live plants")
    _check(viewer.set_show_roots(true), "root debug can be enabled before LOD demotion")
    _check(viewer.set_lod_mode(TerrainOverlay.LOD_REGION, true), "REGION LOD can be re-entered")
    _check(not bool(viewer.plant_overlay.show_roots), "non-PLANT LOD disables expensive root debug")
    _check(not viewer.set_lod_mode("INVALID", false), "VIS3 rejects unknown LOD")
    _check(not viewer.terrain_overlay.set_camera_state(9.0, Vector2.ZERO), "terrain renderer rejects invalid zoom")

    _check(viewer.set_lod_mode(TerrainOverlay.LOD_PATCH, true), "return to PATCH before evolution")
    _check(viewer.manual_step(1), "VIS3 advances one real ecology generation")
    var state1: Dictionary = viewer.get_view_state()
    _check(int(state1.get("generation", -1)) == 1, "VIS3 live generation advances to one")
    _check(String(state1.get("ecology_state_hash", "")) != initial_ecology_hash, "real evolution changes ecology state")
    var history1: Dictionary = viewer.get_history_state()
    _check(int(history1.get("frame_count", 0)) == 2 and int(history1.get("displayed_generation", -1)) == 1, "generation one is appended to visual history")
    var frame1: Dictionary = viewer.get_history_frame(1)
    _check(_exact_history_frame(frame1), "generation-one history frame validates")
    _check(int(frame1.get("generation", -1)) == 1, "history frame is generation-bound")
    _check(String(frame1.get("ecology_state_hash", "")) == String(state1.get("ecology_state_hash", "")), "history frame is exact-source bound to ecology")
    _check(_sum_counts(Array(frame1["population_counts"])) == int(frame1.get("population_count", -1)), "generation-one per-cell counts sum to population")
    _check(_nonempty_label_count(Array(frame1["biome_labels"])) > 0, "generation-one history captures emergent biome labels")
    _check(not Dictionary(frame1.get("spatial_summary", {})).is_empty(), "VIS3 history includes accepted spatial-observatory summary")

    var ecology1: Dictionary = viewer.workbench.get_ecology_snapshot()
    var first_record: Dictionary = {}
    for value in Array(ecology1.get("records", [])):
        if value is Dictionary:
            first_record = Dictionary(value)
            break
    _check(not first_record.is_empty(), "generation one has a live record for lineage check")
    var occupied_cell := int(first_record.get("cell_index", -1))
    _check(viewer.select_cell(occupied_cell), "VIS3 selects an occupied cell")
    var observation: Dictionary = viewer.get_cell_observation(occupied_cell)
    _check(int(observation.get("population_count", 0)) > 0, "selected occupied cell reports population")
    _check(int(observation.get("lineage_richness", 0)) >= 1, "VIS3 reads canonical hereditary_bundle.lineage field")

    _check(viewer.manual_step(1), "VIS3 advances second observed generation")
    var live_state: Dictionary = viewer.get_view_state()
    var live_ecology_hash := String(live_state.get("ecology_state_hash", ""))
    var live_workbench_hash := String(live_state.get("workbench_hash", ""))
    var history2: Dictionary = viewer.get_history_state()
    _check(int(history2.get("frame_count", 0)) == 3 and int(history2.get("live_generation", -1)) == 2, "VIS3 has three observed frames at generation two")

    _check(viewer.set_active_overlay_group("biome"), "VIS3 selects biome overlay")
    _check(viewer.set_history_index(1), "VIS3 scrubs back to observed generation one")
    var scrubbed: Dictionary = viewer.get_history_state()
    _check(not bool(scrubbed.get("history_live", true)) and int(scrubbed.get("displayed_generation", -1)) == 1, "history cursor displays generation one")
    _check(int(scrubbed.get("live_generation", -1)) == 2, "history scrub does not rewind live Workbench generation")
    _check(String(viewer.get_view_state().get("ecology_state_hash", "")) == live_ecology_hash, "history scrub cannot mutate live ecology")
    _check(String(viewer.get_view_state().get("workbench_hash", "")) == live_workbench_hash, "history scrub cannot mutate Workbench identity")
    _check(bool(viewer.get_terrain_summary().get("history_mode", false)), "terrain renderer enters explicit history mode")
    _check(not viewer.plant_overlay.visible, "historical summary hides current individual plant geometry")
    var historical_observation_before: Dictionary = viewer.get_cell_observation(occupied_cell)
    _check(int(historical_observation_before.get("population_count", -1)) >= 0, "live cell observation remains available while history is presentation-only")

    _check(viewer.return_to_live(), "VIS3 returns to live state")
    var returned: Dictionary = viewer.get_history_state()
    _check(bool(returned.get("history_live", false)) and int(returned.get("displayed_generation", -1)) == 2, "return-to-live restores latest observed generation")
    _check(not bool(viewer.get_terrain_summary().get("history_mode", true)), "terrain leaves history mode")
    _check(viewer.plant_overlay.visible, "live PATCH mode restores procedural plants")

    _check(viewer.set_lod_mode(TerrainOverlay.LOD_PLANT, true), "VIS3 selects PLANT LOD")
    var plant_state: Dictionary = viewer.get_view_state()
    _check(is_equal_approx(float(plant_state.get("camera_zoom", 0.0)), 3.0), "PLANT preset zooms to morphology scale")
    _check(String(viewer.get_terrain_summary().get("effective_lod", "")) == TerrainOverlay.LOD_PLANT, "terrain resolves PLANT LOD")
    _check(viewer.plant_overlay.visible, "PLANT LOD keeps individual plants visible")
    _check(String(viewer.get_view_state().get("ecology_state_hash", "")) == live_ecology_hash, "PLANT focus remains non-causal")

    var perf: Dictionary = viewer.get_performance_snapshot()
    _check(float(perf.get("last_step_ms", -1.0)) >= 0.0, "VIS3 exposes measured step time")
    _check(float(perf.get("last_refresh_ms", -1.0)) >= 0.0, "VIS3 exposes measured refresh time")
    _check(float(perf.get("last_history_capture_ms", -1.0)) >= 0.0, "VIS3 exposes history-capture time")
    _check(int(perf.get("population", -1)) == int(viewer.workbench.get_ecology_snapshot().get("record_count", -2)), "performance HUD population matches ecology")
    _check(int(perf.get("visible_plants", -1)) == viewer.plant_overlay.descriptors.size(), "performance HUD reports visible plant geometry")
    _check(int(perf.get("history_frames", -1)) == int(viewer.get_history_state().get("frame_count", -2)), "performance HUD reports history frame count")
    _check(String(perf.get("effective_lod", "")) == TerrainOverlay.LOD_PLANT, "performance HUD reports effective LOD")

    _source_guard()
    viewer.queue_free(); world.queue_free()
    _finish()

func _exact_history_frame(frame: Dictionary) -> bool:
    var expected := [
        "generation", "ecology_state_hash", "workbench_hash", "classification_hash",
        "population_count", "occupied_cells", "population_counts", "biome_labels", "spatial_summary",
    ]
    if frame.keys().size() != expected.size():
        return false
    for key in expected:
        if not frame.has(key):
            return false
    if int(frame.get("generation", -1)) < 0 or String(frame.get("ecology_state_hash", "")).length() != 64 or String(frame.get("workbench_hash", "")).length() != 64:
        return false
    if int(frame.get("population_count", -1)) < 0 or int(frame.get("occupied_cells", -1)) < 0 or int(frame.get("occupied_cells", 1025)) > 1024:
        return false
    return true

func _sum_counts(values: Array) -> int:
    var total := 0
    for value in values:
        var count := int(value)
        if count < 0:
            return -1
        total += count
    return total

func _nonempty_label_count(values: Array) -> int:
    var count := 0
    for value in values:
        if not String(value).is_empty():
            count += 1
    return count

func _source_guard() -> void:
    var terrain_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_vis3_terrain_biome_overlay.gd").to_lower()
    var viewer_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_vis3_planet_biome_viewer.gd").to_lower()
    _check(not terrain_source.contains("preload(") and not terrain_source.contains("load("), "VIS3 terrain renderer imports no simulation implementation")
    _check(not terrain_source.contains("advance_generations") and not terrain_source.contains("tick()") and not terrain_source.contains("workbench.get"), "VIS3 terrain renderer has no simulation control path")
    _check(viewer_source.contains("vis2_procedural_plant_viewer") and viewer_source.contains("vis3_terrain_biome_overlay"), "VIS3 extends accepted VIS2 and adds pure terrain renderer")
    _check(not viewer_source.contains("eco_evo7_ls33") and not viewer_source.contains("eco_evo7_ls34") and not viewer_source.contains("eco_evo7_ls35"), "VIS3 does not bypass Workbench into ecology stages")
    _check(viewer_source.contains("get_patch()") and viewer_source.contains("get_classification()") and viewer_source.contains("get_spatial_history()"), "VIS3 consumes only public Workbench observability facades")
    for source in [terrain_source, viewer_source]:
        _check(not source.contains("reproduce_bundle(") and not source.contains("mutation_seed(") and not source.contains("dispersal_seed("), "VIS3 owns no reproduction/mutation/dispersal authority")
        _check(not source.contains("genome[") and not source.contains("core.records") and not source.contains("fitness ="), "VIS3 owns no genome/population/fitness write path")
        _check(not source.contains("fileaccess.open") and not source.contains("diraccess") and not source.contains("multiplayer"), "VIS3 owns no persistence/network authority")

func _check(condition: bool, label: String) -> void:
    assertions += 1
    if not condition:
        failures.append(label)

func _finish() -> void:
    if failures.is_empty():
        print("ECO.EVO7 VIS3 Planet Patch / Biome Viewer: PASS (%d assertions)" % assertions)
        quit(0)
        return
    for failure in failures:
        push_error("ECO.EVO7 VIS3 FAIL: %s" % failure)
    print("ECO.EVO7 VIS3 Planet Patch / Biome Viewer: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
    quit(1)
