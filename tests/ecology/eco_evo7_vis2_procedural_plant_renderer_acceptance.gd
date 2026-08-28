extends SceneTree

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const ViewerScene = preload("res://scenes/labs/ecology/eco_evo7_vis2_procedural_plant_viewer.tscn")
const Adapter = preload("res://scripts/labs/ecology/eco_evo7_vis2_phenotype_render_adapter.gd")
const PlantOverlay = preload("res://scripts/labs/ecology/eco_evo7_vis2_plant_overlay.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
    var world = EarthWorld.new(); root.add_child(world)
    _check(world.setup(null), "real Earth initializes")

    var viewer = ViewerScene.instantiate(); viewer.auto_initialize = false; viewer.ensure_ui_built(); root.add_child(viewer)
    _check(viewer.initialize_runtime(world), "VIS2 initializes over accepted VIS1/Workbench")
    var contract: Dictionary = viewer.get_ui_contract()
    _check(bool(contract.get("procedural_plants", false)), "VIS2 exposes procedural plants")
    _check(bool(contract.get("phenotype_driven", false)), "VIS2 declares phenotype-driven rendering")
    _check(bool(contract.get("root_debug", false)), "VIS2 exposes root debug toggle")
    _check(bool(contract.get("founder_markers", false)), "VIS2 supports founder markers before phenotype evidence")
    _check(bool(contract.get("presentation_only", false)), "VIS2 remains presentation-only")
    var identity: Dictionary = viewer.get_runtime_identity()
    _check(String(identity.get("scene_name", "")) == "EcoEvo7VIS2ProceduralPlantViewer", "VIS2 runtime identity names the expected scene")
    _check(String(identity.get("viewer_title", "")).contains("VIS2 Procedural Plant Viewer"), "VIS2 runtime identity has an unambiguous VIS2 title")
    _check(String(identity.get("revision", "")) == "ECO.EVO7-VIS2.R2", "VIS2 runtime identity exposes R2 revision")
    var top_title := viewer.get_node_or_null("VIS1UI/Root/Top").get_child(0) as Label
    _check(top_title != null and top_title.text.contains("VIS2"), "VIS2 replaces inherited VIS1 top title")
    var visual_help := viewer.get_node_or_null("VIS1UI/Root/Body/ControlPanel/Controls/VIS2VisualHelp") as Label
    _check(visual_help != null and visual_help.text.contains("Press +1"), "VIS2 explains founder-to-phenotype transition in UI")

    var initial_state: Dictionary = viewer.get_view_state()
    var initial_ecology_hash := String(initial_state.get("ecology_state_hash", ""))
    var initial_workbench_hash := String(initial_state.get("workbench_hash", ""))
    var initial_render: Dictionary = viewer.get_phenotype_render_snapshot()
    _check(not initial_render.is_empty(), "VIS2 builds generation-zero render snapshot")
    _check(Adapter.new().validate_result(initial_render), "generation-zero render snapshot validates")
    _check(int(initial_render.get("generation", -1)) == 0, "VIS2 render snapshot starts at generation zero")
    _check(int(initial_render.get("descriptor_count", -1)) == 64, "VIS2 has one founder descriptor per living record")
    _check(int(initial_render.get("founder_marker_count", -1)) == 64 and int(initial_render.get("phenotype_evidence_count", -1)) == 0, "generation zero uses neutral founder markers only")
    _check(String(initial_render.get("source_ecology_state_hash", "")) == initial_ecology_hash, "VIS2 render snapshot is source-bound to ecology")
    var founder_descriptor: Dictionary = Array(initial_render["descriptors"])[0]
    _check(String(founder_descriptor.get("evidence_level", "")) == Adapter.FOUNDER_EVIDENCE, "founder descriptor is explicitly non-phenotype evidence")
    _check(String(founder_descriptor.get("phenotype_hash", "")).is_empty(), "founder marker does not fabricate phenotype hash")
    var readability_overlay = PlantOverlay.new()
    _check(readability_overlay.stem_height_px(founder_descriptor, 18.0) >= 5.0, "generation-zero founder sprout has readable minimum stem at 1x")
    _check(readability_overlay.crown_radius_px(founder_descriptor, 18.0) >= 2.2, "generation-zero founder sprout has readable minimum leaves at 1x")
    readability_overlay.free()

    _check(viewer.set_show_roots(true), "VIS2 root debug toggles on")
    _check(viewer.set_camera_state(1.8, Vector2(44.0, -20.0)), "VIS2 camera still works")
    _check(viewer.select_cell(333), "VIS2 cell selection still works")
    var presentation_state: Dictionary = viewer.get_view_state()
    _check(String(presentation_state.get("ecology_state_hash", "")) == initial_ecology_hash, "root/camera/selection controls cannot change ecology")
    _check(String(presentation_state.get("workbench_hash", "")) == initial_workbench_hash, "root/camera/selection controls cannot change causal Workbench identity")

    _check(viewer.manual_step(1), "VIS2 advances one real generation")
    var g1_state: Dictionary = viewer.get_view_state()
    var g1_render: Dictionary = viewer.get_phenotype_render_snapshot()
    _check(int(g1_state.get("generation", -1)) == 1 and int(g1_render.get("generation", -1)) == 1, "VIS2 render snapshot follows generation one")
    _check(Adapter.new().validate_result(g1_render), "generation-one render snapshot validates")
    _check(int(g1_render.get("founder_marker_count", -1)) == 0, "generation one contains no fabricated founder phenotype")
    _check(int(g1_render.get("phenotype_evidence_count", -1)) == int(g1_render.get("descriptor_count", -1)), "every living generation-one plant is backed by LS3.4 phenotype evidence")
    _check(int(g1_render.get("descriptor_count", -1)) > 0, "generation one has living procedural plants")
    _check(String(g1_render.get("source_ecology_state_hash", "")) == String(g1_state.get("ecology_state_hash", "")), "generation-one render evidence remains exact-source bound")

    var ecology: Dictionary = viewer.workbench.get_ecology_snapshot()
    var evaluations := {}
    for value in Array(Dictionary(ecology.get("competition_field", {})).get("evaluations", [])):
        if value is Dictionary:
            evaluations[String(Dictionary(value).get("record_id", ""))] = Dictionary(value)
    var checked_mapping := false
    for value in Array(g1_render["descriptors"]):
        var descriptor: Dictionary = value
        var record_id := String(descriptor["record_id"])
        if evaluations.has(record_id):
            var evaluation: Dictionary = evaluations[record_id]
            _check(String(descriptor["phenotype_hash"]) == String(evaluation["phenotype_hash"]), "VIS2 preserves exact phenotype hash")
            _check(is_equal_approx(float(descriptor["realized_height_m"]), float(evaluation["realized_height_m"])), "VIS2 height comes from LS3.4 evidence")
            _check(is_equal_approx(float(descriptor["leaf_area_index_proxy"]), float(evaluation["leaf_area_index_proxy"])), "VIS2 LAI comes from LS3.4 evidence")
            _check(is_equal_approx(float(descriptor["realized_root_depth_m"]), float(evaluation["realized_root_depth_m"])), "VIS2 root depth comes from LS3.4 evidence")
            _check(is_equal_approx(float(descriptor["root_shoot_ratio"]), float(evaluation["root_shoot_ratio"])), "VIS2 root/shoot comes from LS3.4 evidence")
            _check(is_equal_approx(float(descriptor["water_satisfaction"]), float(evaluation["water_satisfaction"])), "VIS2 water state comes from LS3.4 evidence")
            _check(is_equal_approx(float(descriptor["realized_resource_balance"]), float(evaluation["realized_resource_balance"])), "VIS2 health resource signal comes from LS3.4 evidence")
            checked_mapping = true
            break
    _check(checked_mapping, "VIS2 finds exact source evaluation for a living plant")

    var overlay = PlantOverlay.new(); overlay.size = Vector2(900, 780); root.add_child(overlay)
    var base := {
        "record_id":"render-probe", "cell_index":0, "bundle_checksum":"a".repeat(64), "lineage_id":"lineage-a",
        "evidence_level":Adapter.PHENOTYPE_EVIDENCE, "phenotype_hash":"b".repeat(64),
        "realized_height_m":2.0, "leaf_area_index_proxy":0.5, "realized_root_depth_m":1.0,
        "realized_root_spread_m":1.0, "root_shoot_ratio":0.5, "water_satisfaction":0.8,
        "effective_light":0.8, "realized_resource_balance":0.3, "descriptor_hash":"c".repeat(64),
    }
    var taller: Dictionary = base.duplicate(true); taller["realized_height_m"] = 10.0
    _check(overlay.stem_height_px(taller, 30.0) > overlay.stem_height_px(base, 30.0), "greater realized height produces taller visual stem")
    var leafier: Dictionary = base.duplicate(true); leafier["leaf_area_index_proxy"] = 3.5
    _check(overlay.crown_radius_px(leafier, 30.0) > overlay.crown_radius_px(base, 30.0), "greater LAI produces larger crown")
    var deeper: Dictionary = base.duplicate(true); deeper["realized_root_depth_m"] = 4.5
    _check(overlay.root_depth_px(deeper, 30.0) > overlay.root_depth_px(base, 30.0), "greater root depth produces deeper root debug geometry")
    var wider: Dictionary = base.duplicate(true); wider["realized_root_spread_m"] = 5.5
    _check(overlay.root_spread_px(wider, 30.0) > overlay.root_spread_px(base, 30.0), "greater root spread produces wider root debug geometry")
    var dry: Dictionary = base.duplicate(true); dry["water_satisfaction"] = 0.05; dry["realized_resource_balance"] = -0.7
    _check(overlay.health_factor(dry) < overlay.health_factor(base), "water/resource stress visibly lowers health factor")
    _check(overlay.lineage_color("same-lineage", 0.8) == overlay.lineage_color("same-lineage", 0.8), "lineage color is deterministic")
    _check(overlay.get_render_contract().get("presentation_only", false), "pure plant renderer declares presentation-only contract")
    overlay.queue_free()

    # Terminal extinction must render as a valid empty plant set.
    _check(viewer.apply_physical_controls(362365, 310031, "WATER_GRADIENT_STRONG"), "VIS2 accepts frozen wet-surface counterfactual")
    _check(viewer.manual_step(1), "wet-surface extinction generation remains valid through VIS2")
    var extinct_render: Dictionary = viewer.get_phenotype_render_snapshot()
    _check(not extinct_render.is_empty() and int(extinct_render.get("descriptor_count", -1)) == 0, "VIS2 represents terminal extinction as zero living plants")
    _check(int(extinct_render.get("generation", -1)) == 1, "empty plant renderer remains generation-bound")

    _source_guard()
    viewer.queue_free(); world.queue_free()
    _finish()

func _source_guard() -> void:
    var adapter_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_vis2_phenotype_render_adapter.gd").to_lower()
    var overlay_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_vis2_plant_overlay.gd").to_lower()
    var viewer_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_vis2_procedural_plant_viewer.gd").to_lower()
    var launcher_ps1 := FileAccess.get_file_as_string("res://OPEN_ECO_EVO7_VIS2_PROCEDURAL_PLANT_VIEWER.ps1").to_lower()
    var launcher_sh := FileAccess.get_file_as_string("res://OPEN_ECO_EVO7_VIS2_PROCEDURAL_PLANT_VIEWER.sh").to_lower()
    _check(not adapter_source.contains("preload(") and not adapter_source.contains("load("), "VIS2 adapter imports no simulation implementation")
    _check(not overlay_source.contains("preload(") and not overlay_source.contains("load(") and not overlay_source.contains("workbench"), "VIS2 plant renderer is pure presentation")
    _check(viewer_source.contains("vis1_spatial_world_viewer") and viewer_source.contains("phenotype_render_adapter"), "VIS2 extends accepted VIS1 and uses read-only adapter")
    _check(not viewer_source.contains("eco_evo7_ls33") and not viewer_source.contains("eco_evo7_ls34") and not viewer_source.contains("eco_evo7_ls35"), "VIS2 viewer does not bypass Workbench into ecology stages")
    _check(viewer_source.contains("eco.evo7 vis2 ready") and viewer_source.contains("eco.evo7-vis2.r2"), "VIS2 emits explicit runtime identity marker")
    for launcher_source in [launcher_ps1, launcher_sh]:
        _check(launcher_source.contains("--scene") and launcher_source.contains("eco_evo7_vis2_procedural_plant_viewer.tscn"), "VIS2 launcher explicitly selects the VIS2 scene instead of project main_scene")
    for source in [adapter_source, overlay_source, viewer_source]:
        _check(not source.contains("reproduce_bundle(") and not source.contains("mutation_seed(") and not source.contains("dispersal_seed("), "VIS2 owns no reproduction/mutation/dispersal authority")
        _check(not source.contains("genome[") and not source.contains("core.records") and not source.contains("fitness ="), "VIS2 owns no genome/population/fitness write path")
        _check(not source.contains("fileaccess.open") and not source.contains("diraccess") and not source.contains("multiplayer"), "VIS2 owns no persistence/network authority")

func _check(condition: bool, label: String) -> void:
    assertions += 1
    if not condition:
        failures.append(label)

func _finish() -> void:
    if failures.is_empty():
        print("ECO.EVO7 VIS2 Procedural Plant Renderer: PASS (%d assertions)" % assertions)
        quit(0)
        return
    for failure in failures:
        push_error("ECO.EVO7 VIS2 FAIL: %s" % failure)
    print("ECO.EVO7 VIS2 Procedural Plant Renderer: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
    quit(1)
