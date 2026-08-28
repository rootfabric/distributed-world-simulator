extends SceneTree

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const ViewerScene = preload("res://scenes/labs/ecology/eco_evo7_vis1_spatial_world_viewer.tscn")
const SpatialCanvas = preload("res://scripts/labs/ecology/eco_evo7_vis1_spatial_canvas.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
    var world = EarthWorld.new(); root.add_child(world)
    _check(world.setup(null), "real Earth initializes")

    var viewer = ViewerScene.instantiate(); viewer.auto_initialize = false; viewer.ensure_ui_built(); root.add_child(viewer)
    var contract: Dictionary = viewer.get_ui_contract()
    _check(bool(contract.get("world_seed", false)) and bool(contract.get("environment_seed", false)) and bool(contract.get("recipe", false)), "VIS1 exposes physical counterfactual controls")
    _check(bool(contract.get("start", false)) and bool(contract.get("pause", false)) and bool(contract.get("reset", false)), "VIS1 exposes live transport controls")
    _check(bool(contract.get("step_1", false)) and bool(contract.get("step_10", false)), "VIS1 exposes explicit generation stepping")
    _check(bool(contract.get("overlay_group", false)) and bool(contract.get("overlay_metric", false)), "VIS1 exposes overlay controls")
    _check(bool(contract.get("camera", false)) and bool(contract.get("cell_selection", false)), "VIS1 exposes pan/zoom camera and cell selection")
    _check(bool(contract.get("population_markers", false)) and int(contract.get("cell_count", 0)) == 1024, "VIS1 renders 32x32 world with abstract population markers")
    _check(bool(contract.get("presentation_only", false)), "VIS1 renderer declares presentation-only authority")

    _check(viewer.initialize_runtime(world), "VIS1 initializes through accepted Workbench")
    var initial: Dictionary = viewer.get_view_state()
    _check(int(initial.get("generation", -1)) == 0, "VIS1 starts at generation zero")
    var initial_ecology_hash := String(initial.get("ecology_state_hash", ""))
    var initial_workbench_hash := String(initial.get("workbench_hash", ""))
    _check(initial_ecology_hash.length() == 64 and initial_workbench_hash.length() == 64, "VIS1 publishes source identities")

    # Presentation controls must be strictly non-causal.
    _check(viewer.set_camera_state(1.75, Vector2(52.0, -31.0)), "VIS1 camera accepts bounded zoom/pan")
    _check(viewer.select_cell(511), "VIS1 selects arbitrary spatial cell")
    _check(viewer.set_active_overlay_group("population"), "VIS1 switches to population overlay")
    _check(viewer.set_active_overlay_selector("lineage_richness"), "VIS1 switches population metric")
    var presentation_state: Dictionary = viewer.get_view_state()
    _check(String(presentation_state["ecology_state_hash"]) == initial_ecology_hash, "camera/selection/overlay cannot change ecology")
    _check(String(presentation_state["workbench_hash"]) == initial_workbench_hash, "camera/selection/overlay cannot change causal Workbench identity")
    _check(int(presentation_state["selected_cell"]) == 511 and is_equal_approx(float(presentation_state["camera_zoom"]), 1.75), "VIS1 view state records camera and selection")

    var observation: Dictionary = viewer.get_cell_observation(511)
    _check(int(observation.get("index", -1)) == 511 and int(observation.get("x", -1)) == 31 and int(observation.get("y", -1)) == 15, "cell observation preserves spatial identity")
    _check(float(observation.get("soil_moisture", -1.0)) >= 0.0 and float(observation.get("surface_water_fraction", -1.0)) >= 0.0, "cell observation exposes physical field")
    _check(int(observation.get("population_count", -1)) >= 0 and int(observation.get("lineage_richness", -1)) >= 0, "cell observation exposes read-only population summary")
    _check(String(observation.get("active_overlay_selector", "")) == "lineage_richness", "cell observation binds active overlay")

    var canvas = SpatialCanvas.new(); canvas.size = Vector2(900, 780); root.add_child(canvas)
    var projection: Array[Dictionary] = []
    var counts: Array[int] = []
    counts.resize(1024); counts.fill(0)
    for index in 1024: projection.append({"index":index,"x":index%32,"y":index/32,"selector":"test","value":float(index)})
    _check(canvas.set_projection("environment", projection, counts), "pure VIS1 canvas accepts canonical 32x32 projection")
    _check(canvas.set_camera_state(1.25, Vector2(10, 20)), "pure VIS1 canvas camera state validates")
    var center := canvas.cell_center_screen(528)
    _check(canvas.screen_to_cell(center) == 528, "VIS1 camera transform round-trips screen to cell")
    _check(not canvas.set_camera_state(9.0, Vector2.ZERO), "VIS1 rejects unbounded camera zoom")
    canvas.queue_free()

    # One real generation should update source data while presentation remains a facade.
    _check(viewer.manual_step(1), "VIS1 +1 advances accepted Workbench")
    var stepped: Dictionary = viewer.get_view_state()
    _check(int(stepped.get("generation", -1)) == 1, "VIS1 reports generation one")
    _check(String(stepped.get("ecology_state_hash", "")) != initial_ecology_hash, "real evolution changes ecology behind VIS1")
    _check(viewer.set_active_overlay_group("biome"), "VIS1 switches to emergent biome overlay")
    _check(viewer.set_active_overlay_selector("emergent_biome"), "VIS1 selects emergent biome labels")
    var post_observation: Dictionary = viewer.get_cell_observation(0)
    _check(String(post_observation.get("emergent_biome", "")).length() > 0, "VIS1 shows post-competition biome classification")

    # Physical reset remains the existing Workbench causal control, not a viewer mutation.
    _check(viewer.apply_physical_controls(360053, 310031, "RELIEF_DRAINAGE_STRONG"), "VIS1 forwards explicit physical counterfactual to Workbench")
    var reset_state: Dictionary = viewer.get_view_state()
    _check(int(reset_state.get("generation", -1)) == 0, "physical counterfactual resets generation")
    _check(String(reset_state.get("ecology_state_hash", "")) != String(stepped.get("ecology_state_hash", "")), "physical counterfactual rebuilds ecology through Workbench")

    _source_guard()
    viewer.queue_free(); world.queue_free()
    _finish()

func _source_guard() -> void:
    var viewer_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_vis1_spatial_world_viewer.gd").to_lower()
    var canvas_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_vis1_spatial_canvas.gd").to_lower()
    _check(viewer_source.contains("workbench.new()") and viewer_source.contains("get_overlay_projection") and viewer_source.contains("get_ecology_snapshot"), "VIS1 consumes only public Workbench facade")
    _check(not viewer_source.contains("eco_evo7_ls33") and not viewer_source.contains("eco_evo7_ls34") and not viewer_source.contains("eco_evo7_ls35"), "VIS1 does not bypass Workbench into ecology stages")
    _check(not viewer_source.contains("reproduce_bundle(") and not viewer_source.contains("mutation_seed(") and not viewer_source.contains("dispersal_seed("), "VIS1 owns no reproduction/mutation/dispersal authority")
    _check(not viewer_source.contains("genome[") and not viewer_source.contains("core.records") and not viewer_source.contains("fitness ="), "VIS1 has no direct genome/population/fitness writes")
    _check(not viewer_source.contains("fileaccess.open") and not viewer_source.contains("diraccess") and not viewer_source.contains("multiplayer"), "VIS1 owns no persistence/network authority")
    _check(not canvas_source.contains("preload(") and not canvas_source.contains("get_ecology_snapshot") and not canvas_source.contains("get_overlay_projection") and not canvas_source.contains("genome["), "SpatialCanvas is a pure presentation renderer")

func _check(condition: bool, label: String) -> void:
    assertions += 1
    if not condition:
        failures.append(label)

func _finish() -> void:
    if failures.is_empty():
        print("ECO.EVO7 VIS1 Spatial World Viewer: PASS (%d assertions)" % assertions)
        quit(0)
        return
    for failure in failures: push_error("ECO.EVO7 VIS1 FAIL: %s" % failure)
    print("ECO.EVO7 VIS1 Spatial World Viewer: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
    quit(1)
