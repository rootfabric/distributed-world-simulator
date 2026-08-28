extends "res://scripts/labs/ecology/eco_evo7_vis2_procedural_plant_viewer.gd"

const TerrainBiomeOverlay = preload("res://scripts/labs/ecology/eco_evo7_vis3_terrain_biome_overlay.gd")

## ECO.EVO7 VIS3 — Planet Patch / Biome Viewer R1.
## Presentation-only multi-scale observer over accepted VIS2 + LS3.6 Workbench.
## Adds topographic terrain, biome boundaries, bounded visual history and perf telemetry.

const VIS3_VIEWER_TITLE := "ECO EVO7 — VIS3 Planet Patch / Biome Viewer"
const VIS3_RUNTIME_REVISION := "ECO.EVO7-VIS3.R1"
const VIS3_HISTORY_LIMIT := 64
const VIS3_CELL_COUNT := 1024

var terrain_overlay = null
var vis3_panel: PanelContainer
var lod_select: OptionButton
var contours_toggle: CheckButton
var boundaries_toggle: CheckButton
var history_slider: HSlider
var history_label: Label
var performance_label: Label
var history: Array[Dictionary] = []
var history_index := -1
var history_live := true
var last_captured_ecology_hash := ""
var last_step_ms := 0.0
var last_refresh_ms := 0.0
var last_history_capture_ms := 0.0
var last_profile_text_update_usec := 0

func _ready() -> void:
    ensure_ui_built()
    _apply_vis2_identity()
    _ensure_vis2_ui()
    _apply_vis3_identity()
    _ensure_vis3_ui()
    print("ECO.EVO7 VIS3 READY scene=%s revision=%s" % [name, VIS3_RUNTIME_REVISION])
    if auto_initialize:
        initialize_runtime()

func _process(delta: float) -> void:
    var before_generation := -1
    if workbench != null:
        before_generation = int(workbench.get_workbench_snapshot().get("generation", -1))
    var started := Time.get_ticks_usec()
    super._process(delta)
    if workbench != null:
        var snapshot: Dictionary = workbench.get_workbench_snapshot()
        var after_generation := int(snapshot.get("generation", -1))
        if after_generation != before_generation and after_generation >= 0:
            last_step_ms = float(Time.get_ticks_usec() - started) / 1000.0
        var ecology_hash := String(snapshot.get("ecology_state_hash", ""))
        if ecology_hash.length() == 64 and ecology_hash != last_captured_ecology_hash:
            _capture_current_frame(false)
            _refresh_vis3()
    var now := Time.get_ticks_usec()
    if now - last_profile_text_update_usec >= 250000:
        last_profile_text_update_usec = now
        _refresh_performance_hud()

func initialize_runtime(source = null) -> bool:
    ensure_ui_built()
    _apply_vis2_identity()
    _ensure_vis2_ui()
    _apply_vis3_identity()
    _ensure_vis3_ui()
    var ok := super.initialize_runtime(source)
    _apply_vis3_identity()
    if ok:
        history.clear()
        history_index = -1
        history_live = true
        last_captured_ecology_hash = ""
        _capture_current_frame(true)
        _refresh_vis3()
        _refresh_selection()
    return ok

func manual_step(count: int) -> bool:
    if workbench == null or count <= 0:
        return false
    var started := Time.get_ticks_usec()
    var result: Dictionary = workbench.advance_generations(count)
    last_step_ms = float(Time.get_ticks_usec() - started) / 1000.0
    if result.is_empty():
        return false
    history_live = true
    history_index = history.size() - 1
    var refresh_started := Time.get_ticks_usec()
    _refresh_all()
    _capture_current_frame(false)
    _refresh_vis3()
    _refresh_selection()
    last_refresh_ms = float(Time.get_ticks_usec() - refresh_started) / 1000.0
    return true

func reset_same_seeds() -> bool:
    var ok := super.reset_same_seeds()
    if ok:
        history.clear()
        history_index = -1
        history_live = true
        last_captured_ecology_hash = ""
        _capture_current_frame(true)
        _refresh_vis3()
        _refresh_selection()
    return ok

func apply_physical_controls(world_seed: int, environment_seed: int, recipe: String) -> bool:
    var ok := super.apply_physical_controls(world_seed, environment_seed, recipe)
    if ok:
        history.clear()
        history_index = -1
        history_live = true
        last_captured_ecology_hash = ""
        _capture_current_frame(true)
        _refresh_vis3()
        _refresh_selection()
    return ok

func get_runtime_identity() -> Dictionary:
    return {
        "scene_name": String(name),
        "viewer_title": VIS3_VIEWER_TITLE,
        "revision": VIS3_RUNTIME_REVISION,
    }

func get_ui_contract() -> Dictionary:
    var contract: Dictionary = super.get_ui_contract()
    contract["terrain_overlay"] = terrain_overlay != null
    contract["hillshade"] = terrain_overlay != null
    contract["biome_boundaries"] = terrain_overlay != null and boundaries_toggle != null
    contract["multi_scale_camera"] = lod_select != null
    contract["history_timeline"] = history_slider != null
    contract["performance_hud"] = performance_label != null
    contract["region_lod"] = terrain_overlay != null
    contract["patch_lod"] = terrain_overlay != null
    contract["plant_lod"] = terrain_overlay != null
    return contract

func get_history_state() -> Dictionary:
    var live_generation := -1 if workbench == null else int(workbench.get_workbench_snapshot().get("generation", -1))
    var displayed_generation := live_generation
    if not history_live and history_index >= 0 and history_index < history.size():
        displayed_generation = int(history[history_index].get("generation", -1))
    return {
        "frame_count": history.size(),
        "history_limit": VIS3_HISTORY_LIMIT,
        "history_live": history_live,
        "history_index": history_index,
        "displayed_generation": displayed_generation,
        "live_generation": live_generation,
    }

func get_history_frame(index: int) -> Dictionary:
    if index < 0 or index >= history.size():
        return {}
    return history[index].duplicate(true)

func get_terrain_summary() -> Dictionary:
    return {} if terrain_overlay == null else terrain_overlay.get_terrain_summary()

func get_performance_snapshot() -> Dictionary:
    var population := 0
    if workbench != null:
        population = int(workbench.get_ecology_snapshot().get("record_count", 0))
    var visible_plants := 0
    if plant_overlay != null and plant_overlay.visible:
        visible_plants = plant_overlay.descriptors.size()
    var generation_profile: Dictionary = {}
    if workbench != null and workbench.has_method("get_last_generation_profile"):
        generation_profile = workbench.get_last_generation_profile()
    return {
        "last_step_ms": last_step_ms,
        "last_refresh_ms": last_refresh_ms,
        "last_history_capture_ms": last_history_capture_ms,
        "fps": Engine.get_frames_per_second(),
        "population": population,
        "visible_plants": visible_plants,
        "history_frames": history.size(),
        "effective_lod": "" if terrain_overlay == null else terrain_overlay.effective_lod(),
        "generation_profile": generation_profile,
    }

func set_lod_mode(value: String, apply_camera_preset: bool = true) -> bool:
    if terrain_overlay == null or not terrain_overlay.set_lod_mode(value):
        return false
    if lod_select != null:
        _select_text(lod_select, value)
    if apply_camera_preset and value != TerrainBiomeOverlay.LOD_AUTO:
        _apply_lod_camera_preset(value)
    _sync_lod_visibility()
    _refresh_performance_hud()
    return true

func set_history_index(index: int) -> bool:
    if index < 0 or index >= history.size() or terrain_overlay == null:
        return false
    history_index = index
    history_live = index == history.size() - 1
    if history_live:
        terrain_overlay.clear_history_frame()
        _refresh_world()
    else:
        if not terrain_overlay.set_history_frame(history[index]):
            return false
        _apply_history_projection(history[index])
    if history_slider != null:
        history_slider.set_value_no_signal(float(index))
    _sync_lod_visibility()
    _refresh_history_label()
    _refresh_selection()
    return true

func return_to_live() -> bool:
    if history.is_empty():
        return false
    return set_history_index(history.size() - 1)

func select_cell(index: int) -> bool:
    var ok := super.select_cell(index)
    if ok and terrain_overlay != null and terrain_overlay.effective_lod() == TerrainBiomeOverlay.LOD_PLANT:
        _center_selected_cell()
    return ok

func _record_lineage(record: Dictionary) -> String:
    # VIS3 fixes the inherited VIS1 legacy field lookup while preserving fallback.
    var bundle_value = record.get("hereditary_bundle")
    if not bundle_value is Dictionary:
        return ""
    var bundle: Dictionary = bundle_value
    var lineage_value = bundle.get("lineage", bundle.get("lineage_record"))
    if not lineage_value is Dictionary:
        return ""
    return String(Dictionary(lineage_value).get("lineage_id", ""))

func _refresh_world() -> void:
    if history_live:
        super._refresh_world()
    elif history_index >= 0 and history_index < history.size():
        _apply_history_projection(history[history_index])
    _sync_terrain_sources()

func _refresh_selection() -> void:
    super._refresh_selection()
    if selected_details == null:
        return
    if not history_live and history_index >= 0 and history_index < history.size():
        var frame: Dictionary = history[history_index]
        var counts: Array = frame.get("population_counts", [])
        var labels: Array = frame.get("biome_labels", [])
        if counts.size() == VIS3_CELL_COUNT and labels.size() == VIS3_CELL_COUNT:
            selected_details.text += "\n\n[b]VIS3 historical frame[/b]\nGeneration: %d\nPopulation in cell: %d\nBiome: %s\nCurrent Workbench remains at generation %d." % [
                int(frame.get("generation", -1)), int(counts[selected_cell]), String(labels[selected_cell]),
                int(workbench.get_workbench_snapshot().get("generation", -1)) if workbench != null else -1,
            ]
    elif terrain_overlay != null:
        var terrain: Dictionary = terrain_overlay.get_terrain_summary()
        selected_details.text += "\n\n[b]VIS3 terrain[/b]\nPatch: %.0f m\nElevation span: %.1f m\nLOD: %s" % [
            float(terrain.get("patch_width_m", 0.0)), float(terrain.get("elevation_span_m", 0.0)), String(terrain.get("effective_lod", "")),
        ]

func _on_camera_changed(zoom_value: float, pan_value: Vector2) -> void:
    super._on_camera_changed(zoom_value, pan_value)
    if terrain_overlay != null:
        terrain_overlay.set_camera_state(zoom_value, pan_value)
    _sync_lod_visibility()
    _refresh_performance_hud()

func _apply_vis3_identity() -> void:
    DisplayServer.window_set_title(VIS3_VIEWER_TITLE)
    var top := get_node_or_null("VIS1UI/Root/Top") as HBoxContainer
    if top != null and top.get_child_count() > 0 and top.get_child(0) is Label:
        (top.get_child(0) as Label).text = VIS3_VIEWER_TITLE

func _ensure_vis3_ui() -> void:
    if terrain_overlay != null:
        return
    var body := get_node_or_null("VIS1UI/Root/Body") as HBoxContainer
    if world_canvas != null:
        terrain_overlay = TerrainBiomeOverlay.new()
        terrain_overlay.name = "TerrainBiomeOverlay"
        world_canvas.add_child(terrain_overlay)
        terrain_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        # Terrain is below procedural plants but above VIS1 scalar cells.
        world_canvas.move_child(terrain_overlay, 0)
        var camera: Dictionary = world_canvas.get_camera_state()
        terrain_overlay.set_camera_state(float(camera.get("zoom", 1.0)), Vector2(float(camera.get("pan_x", 0.0)), float(camera.get("pan_y", 0.0))))
    if body == null:
        return

    vis3_panel = PanelContainer.new(); vis3_panel.name = "VIS3Panel"; vis3_panel.custom_minimum_size = Vector2(285, 680); body.add_child(vis3_panel)
    var controls := VBoxContainer.new(); controls.name = "VIS3Controls"; controls.add_theme_constant_override("separation", 7); vis3_panel.add_child(controls)
    var title := Label.new(); title.text = "VIS3 Planet Patch / Biomes"; controls.add_child(title)
    var intro := Label.new(); intro.text = "Topography + biome boundaries + observed history. History scrub never rewinds ecology."; intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; controls.add_child(intro)

    lod_select = OptionButton.new(); lod_select.name = "LODMode"
    for value in TerrainBiomeOverlay.LOD_VALUES: lod_select.add_item(value)
    lod_select.item_selected.connect(_on_lod_selected)
    _row(controls, "View scale", lod_select)
    _select_text(lod_select, TerrainBiomeOverlay.LOD_AUTO)

    contours_toggle = CheckButton.new(); contours_toggle.name = "Contours"; contours_toggle.text = "Topographic contours"; contours_toggle.button_pressed = true; contours_toggle.toggled.connect(_on_contours_toggled); controls.add_child(contours_toggle)
    boundaries_toggle = CheckButton.new(); boundaries_toggle.name = "BiomeBoundaries"; boundaries_toggle.text = "Biome boundaries"; boundaries_toggle.button_pressed = true; boundaries_toggle.toggled.connect(_on_boundaries_toggled); controls.add_child(boundaries_toggle)

    var focus_row := HBoxContainer.new(); focus_row.name = "Focus"; controls.add_child(focus_row)
    _button(focus_row, "Region", "Region", func(): set_lod_mode(TerrainBiomeOverlay.LOD_REGION, true))
    _button(focus_row, "Patch", "Patch", func(): set_lod_mode(TerrainBiomeOverlay.LOD_PATCH, true))
    _button(focus_row, "Plant", "Plant", func(): set_lod_mode(TerrainBiomeOverlay.LOD_PLANT, true))

    var divider := HSeparator.new(); controls.add_child(divider)
    var history_title := Label.new(); history_title.text = "Observed evolution history"; controls.add_child(history_title)
    history_slider = HSlider.new(); history_slider.name = "HistoryTimeline"; history_slider.min_value = 0; history_slider.max_value = 0; history_slider.step = 1; history_slider.value_changed.connect(_on_history_slider); controls.add_child(history_slider)
    var live_button := Button.new(); live_button.name = "ReturnLive"; live_button.text = "Return to live"; live_button.pressed.connect(return_to_live); controls.add_child(live_button)
    history_label = Label.new(); history_label.name = "HistoryState"; history_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; controls.add_child(history_label)

    var divider2 := HSeparator.new(); controls.add_child(divider2)
    var perf_title := Label.new(); perf_title.text = "Performance telemetry"; controls.add_child(perf_title)
    performance_label = Label.new(); performance_label.name = "PerformanceHUD"; performance_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; controls.add_child(performance_label)
    var perf_note := Label.new(); perf_note.text = "Step time is measured around Workbench generation advance; refresh time is VIS/UI work. Region LOD hides individual plants."; perf_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; controls.add_child(perf_note)
    _refresh_history_label()
    _refresh_performance_hud()

func _refresh_vis3() -> void:
    if workbench == null or terrain_overlay == null:
        return
    var started := Time.get_ticks_usec()
    _sync_terrain_sources()
    _sync_lod_visibility()
    _refresh_history_label()
    _refresh_performance_hud()
    last_refresh_ms = float(Time.get_ticks_usec() - started) / 1000.0

func _sync_terrain_sources() -> void:
    if workbench == null or terrain_overlay == null:
        return
    var patch: Dictionary = workbench.get_patch()
    var classification_value: Dictionary = workbench.get_classification()
    terrain_overlay.set_sources(patch, classification_value, _population_counts())
    if not history_live and history_index >= 0 and history_index < history.size():
        terrain_overlay.set_history_frame(history[history_index])
    var camera: Dictionary = world_canvas.get_camera_state() if world_canvas != null else {}
    terrain_overlay.set_camera_state(float(camera.get("zoom", 1.0)), Vector2(float(camera.get("pan_x", 0.0)), float(camera.get("pan_y", 0.0))))

func _capture_current_frame(force: bool) -> bool:
    if workbench == null:
        return false
    var started := Time.get_ticks_usec()
    var snapshot: Dictionary = workbench.get_workbench_snapshot()
    var ecology_hash := String(snapshot.get("ecology_state_hash", ""))
    if ecology_hash.length() != 64:
        return false
    if not force and ecology_hash == last_captured_ecology_hash:
        return false
    var counts := _population_counts()
    var labels: Array[String] = []
    labels.resize(VIS3_CELL_COUNT); labels.fill("")
    var classification_value: Dictionary = workbench.get_classification()
    var class_cells: Array = classification_value.get("cells", [])
    if class_cells.size() == VIS3_CELL_COUNT:
        for index in VIS3_CELL_COUNT:
            labels[index] = String(Dictionary(class_cells[index]).get("label", ""))
    var occupied := 0
    var population := 0
    for count in counts:
        population += count
        if count > 0:
            occupied += 1
    var spatial_history: Array = workbench.get_spatial_history()
    var spatial_latest: Dictionary = {} if spatial_history.is_empty() else Dictionary(spatial_history[-1]).duplicate(true)
    var frame := {
        "generation": int(snapshot.get("generation", -1)),
        "ecology_state_hash": ecology_hash,
        "workbench_hash": String(snapshot.get("workbench_hash", "")),
        "classification_hash": String(snapshot.get("classification_hash", "")),
        "population_count": population,
        "occupied_cells": occupied,
        "population_counts": counts.duplicate(),
        "biome_labels": labels.duplicate(),
        "spatial_summary": spatial_latest,
    }
    history.append(frame)
    if history.size() > VIS3_HISTORY_LIMIT:
        history.pop_front()
    history_index = history.size() - 1
    history_live = true
    last_captured_ecology_hash = ecology_hash
    if history_slider != null:
        history_slider.max_value = maxf(0.0, float(history.size() - 1))
        history_slider.set_value_no_signal(float(history_index))
    last_history_capture_ms = float(Time.get_ticks_usec() - started) / 1000.0
    _refresh_history_label()
    return true

func _apply_history_projection(frame: Dictionary) -> void:
    if world_canvas == null:
        return
    var projection: Array[Dictionary] = []
    var counts: Array = frame.get("population_counts", [])
    var labels: Array = frame.get("biome_labels", [])
    if counts.size() != VIS3_CELL_COUNT or labels.size() != VIS3_CELL_COUNT:
        return
    if active_overlay_group == "environment" and workbench != null:
        projection = workbench.get_overlay_projection("environment")
    else:
        for index in VIS3_CELL_COUNT:
            if active_overlay_group == "biome":
                projection.append({"index": index, "x": index % 32, "y": index / 32, "label": String(labels[index]), "value": 0.0})
            else:
                projection.append({"index": index, "x": index % 32, "y": index / 32, "label": "", "value": float(counts[index])})
    if projection.size() != VIS3_CELL_COUNT:
        return
    var no_markers: Array[int] = []
    no_markers.resize(VIS3_CELL_COUNT); no_markers.fill(0)
    world_canvas.set_projection(active_overlay_group, projection, no_markers)

func _apply_lod_camera_preset(value: String) -> void:
    if world_canvas == null:
        return
    match value:
        TerrainBiomeOverlay.LOD_REGION:
            world_canvas.set_camera_state(0.55, Vector2.ZERO)
        TerrainBiomeOverlay.LOD_PATCH:
            world_canvas.set_camera_state(1.15, Vector2.ZERO)
        TerrainBiomeOverlay.LOD_PLANT:
            world_canvas.set_camera_state(3.0, Vector2.ZERO)
            _center_selected_cell()

func _center_selected_cell() -> void:
    if world_canvas == null or selected_cell < 0:
        return
    var center: Vector2 = world_canvas.cell_center_screen(selected_cell)
    if not is_finite(center.x) or not is_finite(center.y):
        return
    var delta: Vector2 = world_canvas.size * 0.5 - center
    var camera: Dictionary = world_canvas.get_camera_state()
    var pan: Vector2 = Vector2(float(camera.get("pan_x", 0.0)), float(camera.get("pan_y", 0.0))) + delta
    world_canvas.set_camera_state(float(camera.get("zoom", 1.0)), pan)

func _sync_lod_visibility() -> void:
    if terrain_overlay == null:
        return
    var lod: String = terrain_overlay.effective_lod()
    if plant_overlay != null:
        plant_overlay.visible = history_live and lod != TerrainBiomeOverlay.LOD_REGION
        if lod != TerrainBiomeOverlay.LOD_PLANT and bool(plant_overlay.show_roots):
            plant_overlay.set_show_roots(false)
            if roots_toggle != null:
                roots_toggle.set_pressed_no_signal(false)

func _refresh_history_label() -> void:
    if history_label == null:
        return
    if history.is_empty():
        history_label.text = "No observed frames yet."
        return
    var frame: Dictionary = history[clampi(history_index, 0, history.size() - 1)]
    var mode := "LIVE" if history_live else "HISTORICAL — ecology is not rewound"
    history_label.text = "%s\nFrame %d/%d • generation %d\nPopulation %d • occupied cells %d" % [
        mode, history_index + 1, history.size(), int(frame.get("generation", -1)), int(frame.get("population_count", 0)), int(frame.get("occupied_cells", 0)),
    ]

func _refresh_performance_hud() -> void:
    if performance_label == null:
        return
    var perf := get_performance_snapshot()
    var profile: Dictionary = perf.get("generation_profile", {})
    var ecology_profile: Dictionary = profile.get("ecology", {})
    var competition_profile: Dictionary = ecology_profile.get("competition", {})
    var ls33_profile: Dictionary = ecology_profile.get("ls33", {})
    var observability_profile: Dictionary = profile.get("observability", {})
    var classification_detail: Dictionary = observability_profile.get("classification_detail", {})
    performance_label.text = "FPS: %d\nStep: %.2f ms\nVIS3 refresh: %.2f ms\nHistory capture: %.2f ms\nPopulation: %d\nVisible plants: %d\nLOD: %s\nHistory frames: %d/%d\n--- PERF1 generation ---\nEcology step: %.2f ms\n  LS3.3 total: %.2f ms\n    parents/candidates: %d/%d\n    pre/post competition: %d/%d\n    candidates: %.2f\n    routes: %.2f\n    recruitment: %.2f\n    materialize: %.2f\n  competition: %.2f ms\n    geometry: %.2f\n    light: %.2f\n    water: %.2f\n    evaluation: %.2f\nEcology validate: %.2f ms\nRepeated validate: %.2f ms\nClassification: %.2f ms\n  primary: %.2f\n  validation: %.2f\n  recompute oracle: %.2f\nSpatial observatory: %.2f ms" % [
        int(perf.get("fps", 0)), float(perf.get("last_step_ms", 0.0)), float(perf.get("last_refresh_ms", 0.0)), float(perf.get("last_history_capture_ms", 0.0)),
        int(perf.get("population", 0)), int(perf.get("visible_plants", 0)), String(perf.get("effective_lod", "")), int(perf.get("history_frames", 0)), VIS3_HISTORY_LIMIT,
        float(profile.get("ecology_step_ms", 0.0)), float(ecology_profile.get("ls33_total_ms", 0.0)),
        int(ls33_profile.get("parent_count", 0)), int(ls33_profile.get("candidate_count", 0)), int(ecology_profile.get("record_count_precompetition", 0)), int(ecology_profile.get("record_count_postcompetition", 0)),
        float(ls33_profile.get("candidate_build_ms", 0.0)), float(ls33_profile.get("route_build_ms", 0.0)), float(ls33_profile.get("recruitment_eval_ms", 0.0)), float(ls33_profile.get("materialize_ms", 0.0)),
        float(ecology_profile.get("competition_pass_ms", 0.0)), float(competition_profile.get("geometry_ms", 0.0)), float(competition_profile.get("light_field_ms", 0.0)), float(competition_profile.get("water_fields_ms", 0.0)), float(competition_profile.get("evaluation_ms", 0.0)),
        float(profile.get("ecology_validation_ms", 0.0)), float(observability_profile.get("repeated_ecology_validation_ms", 0.0)), float(observability_profile.get("classification_ms", 0.0)),
        float(classification_detail.get("primary_compute_ms", 0.0)), float(classification_detail.get("validation_ms", 0.0)), float(classification_detail.get("validation_recompute_ms", 0.0)), float(observability_profile.get("spatial_observatory_ms", 0.0)),
    ]

func _on_lod_selected(index: int) -> void:
    if lod_select != null:
        set_lod_mode(lod_select.get_item_text(index), true)

func _on_contours_toggled(value: bool) -> void:
    if terrain_overlay != null:
        terrain_overlay.set_show_contours(value)

func _on_boundaries_toggled(value: bool) -> void:
    if terrain_overlay != null:
        terrain_overlay.set_show_biome_boundaries(value)

func _on_history_slider(value: float) -> void:
    if history.is_empty():
        return
    set_history_index(clampi(int(round(value)), 0, history.size() - 1))
