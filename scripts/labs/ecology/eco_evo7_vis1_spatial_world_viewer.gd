extends Node

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const Workbench = preload("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd")
const EnvironmentField = preload("res://scripts/ecology/shadow/eco_evo7_ls31_environment_field_v1.gd")
const SpatialCanvas = preload("res://scripts/labs/ecology/eco_evo7_vis1_spatial_canvas.gd")

## ECO.EVO7 VIS1 — Spatial World Viewer.
## Presentation/read-only layer over the accepted LS3.6 Workbench facade.
## Camera, selection and rendering are intentionally excluded from ecology identity.

@export var auto_initialize: bool = true
const AUTO_STEP_SECONDS := 0.65
const GRID_SIZE := 32
const CELL_COUNT := GRID_SIZE * GRID_SIZE

var workbench = null
var planet_source = null
var owns_planet_source := false
var accumulator := 0.0
var ui_built := false
var active_overlay_group := "environment"
var selected_cell := 0

var world_seed_input: SpinBox
var environment_seed_input: SpinBox
var recipe_select: OptionButton
var overlay_group_select: OptionButton
var overlay_metric_select: OptionButton
var generation_label: Label
var population_label: Label
var camera_label: Label
var selected_label: Label
var selected_details: RichTextLabel
var world_canvas = null

func _ready() -> void:
    ensure_ui_built()
    if auto_initialize:
        initialize_runtime()

func _process(delta: float) -> void:
    if workbench == null or not workbench.is_playing():
        return
    accumulator += delta
    if accumulator < AUTO_STEP_SECONDS:
        return
    accumulator = 0.0
    if workbench.tick().is_empty():
        workbench.pause()
    _refresh_all()

func ensure_ui_built() -> void:
    if not ui_built:
        _build_ui()

func initialize_runtime(source = null) -> bool:
    ensure_ui_built()
    if workbench != null:
        return true
    if source == null:
        planet_source = EarthWorld.new()
        planet_source.name = "VIS1EarthSource"
        add_child(planet_source)
        owns_planet_source = true
        if not planet_source.setup(null):
            return false
    else:
        planet_source = source
        owns_planet_source = false
    workbench = Workbench.new()
    if not workbench.setup(planet_source):
        workbench = null
        return false
    _sync_controls()
    select_cell(0)
    _refresh_all()
    return true

func get_ui_contract() -> Dictionary:
    var canvas_contract: Dictionary = {} if world_canvas == null else world_canvas.get_render_contract()
    return {
        "world_seed": world_seed_input != null,
        "environment_seed": environment_seed_input != null,
        "recipe": recipe_select != null,
        "start": get_node_or_null("VIS1UI/Root/Body/ControlPanel/Controls/Transport/Start") != null,
        "pause": get_node_or_null("VIS1UI/Root/Body/ControlPanel/Controls/Transport/Pause") != null,
        "reset": get_node_or_null("VIS1UI/Root/Body/ControlPanel/Controls/Transport/Reset") != null,
        "step_1": get_node_or_null("VIS1UI/Root/Body/ControlPanel/Controls/Steps/Step1") != null,
        "step_10": get_node_or_null("VIS1UI/Root/Body/ControlPanel/Controls/Steps/Step10") != null,
        "overlay_group": overlay_group_select != null,
        "overlay_metric": overlay_metric_select != null,
        "camera": world_canvas != null and bool(canvas_contract.get("pan", false)) and bool(canvas_contract.get("zoom", false)),
        "cell_selection": world_canvas != null and bool(canvas_contract.get("cell_selection", false)),
        "population_markers": world_canvas != null and bool(canvas_contract.get("population_markers", false)),
        "cell_count": int(canvas_contract.get("cell_count", 0)),
        "presentation_only": bool(canvas_contract.get("presentation_only", false)),
    }

func get_workbench_snapshot() -> Dictionary:
    return {} if workbench == null else workbench.get_workbench_snapshot()

func get_view_state() -> Dictionary:
    if workbench == null or world_canvas == null:
        return {}
    var snapshot: Dictionary = workbench.get_workbench_snapshot()
    var camera: Dictionary = world_canvas.get_camera_state()
    return {
        "generation": int(snapshot.get("generation", -1)),
        "ecology_state_hash": String(snapshot.get("ecology_state_hash", "")),
        "workbench_hash": String(snapshot.get("workbench_hash", "")),
        "active_overlay_group": active_overlay_group,
        "active_overlay_selector": _active_selector(),
        "selected_cell": selected_cell,
        "camera_zoom": float(camera.get("zoom", 1.0)),
        "camera_pan_x": float(camera.get("pan_x", 0.0)),
        "camera_pan_y": float(camera.get("pan_y", 0.0)),
    }

func manual_step(count: int) -> bool:
    if workbench == null:
        return false
    var result: Dictionary = workbench.advance_generations(count)
    if result.is_empty():
        return false
    _refresh_all()
    return true

func reset_same_seeds() -> bool:
    if workbench == null or not workbench.reset_same_seeds():
        return false
    _sync_controls()
    _refresh_all()
    return true

func apply_physical_controls(world_seed: int, environment_seed: int, recipe: String) -> bool:
    if workbench == null or not workbench.apply_physical_controls(world_seed, environment_seed, recipe):
        return false
    _sync_controls()
    _refresh_all()
    return true

func set_active_overlay_group(group: String) -> bool:
    if workbench == null or not group in ["environment", "population", "biome"]:
        return false
    active_overlay_group = group
    _select_text(overlay_group_select, group)
    _populate_metric_selector()
    _refresh_world()
    _refresh_selection()
    return true

func set_active_overlay_selector(selector: String) -> bool:
    if workbench == null:
        return false
    if not workbench.set_overlay_selector(active_overlay_group, selector):
        return false
    _select_text(overlay_metric_select, selector)
    _refresh_world()
    _refresh_selection()
    return true

func select_cell(index: int) -> bool:
    if index < 0 or index >= CELL_COUNT or world_canvas == null:
        return false
    selected_cell = index
    world_canvas.set_selected_cell(index)
    _refresh_selection()
    return true

func set_camera_state(zoom_value: float, pan_value: Vector2) -> bool:
    return world_canvas != null and world_canvas.set_camera_state(zoom_value, pan_value)

func reset_camera() -> void:
    if world_canvas != null:
        world_canvas.reset_camera()

func get_cell_observation(index: int) -> Dictionary:
    if workbench == null or index < 0 or index >= CELL_COUNT:
        return {}
    var environment: Dictionary = workbench.get_environment_field()
    var cells: Array = Array(environment.get("cells", []))
    if cells.size() != CELL_COUNT:
        return {}
    var env_cell: Dictionary = Dictionary(cells[index]).duplicate(true)
    var ecology: Dictionary = workbench.get_ecology_snapshot()
    var population_count := 0
    var lineages := {}
    for value in Array(ecology.get("records", [])):
        if not value is Dictionary:
            continue
        var record: Dictionary = value
        if int(record.get("cell_index", -1)) != index:
            continue
        population_count += 1
        var lineage := _record_lineage(record)
        if not lineage.is_empty():
            lineages[lineage] = true
    var lineage_ids: Array = lineages.keys(); lineage_ids.sort()
    var classification_label := ""
    var base_label := ""
    var classification: Dictionary = workbench.get_classification()
    var class_cells: Array = Array(classification.get("cells", []))
    if class_cells.size() == CELL_COUNT:
        classification_label = String(Dictionary(class_cells[index]).get("label", ""))
        base_label = String(Dictionary(class_cells[index]).get("base_label", ""))
    var projection: Array[Dictionary] = workbench.get_overlay_projection(active_overlay_group)
    var active_value = null
    var active_label := ""
    if projection.size() == CELL_COUNT:
        active_value = projection[index].get("value")
        active_label = String(projection[index].get("label", ""))
    return {
        "index": index,
        "x": index % GRID_SIZE,
        "y": index / GRID_SIZE,
        "east_m": float(env_cell.get("east_m", 0.0)),
        "north_m": float(env_cell.get("north_m", 0.0)),
        "elevation_m": float(env_cell.get("elevation_m", 0.0)),
        "soil_moisture": float(env_cell.get("soil_moisture", 0.0)),
        "surface_water_fraction": float(env_cell.get("surface_water_fraction", 0.0)),
        "incident_light": float(env_cell.get("incident_light", 0.0)),
        "temperature_c": float(env_cell.get("temperature_c", 0.0)),
        "population_count": population_count,
        "lineage_ids": lineage_ids,
        "lineage_richness": lineage_ids.size(),
        "emergent_biome": classification_label,
        "base_biome": base_label,
        "active_overlay_group": active_overlay_group,
        "active_overlay_selector": _active_selector(),
        "active_overlay_value": active_value,
        "active_overlay_label": active_label,
    }

func _build_ui() -> void:
    if ui_built:
        return
    ui_built = true
    var canvas_layer := CanvasLayer.new(); canvas_layer.name = "VIS1UI"; add_child(canvas_layer)
    var root_box := VBoxContainer.new(); root_box.name = "Root"; root_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); canvas_layer.add_child(root_box)
    var top := HBoxContainer.new(); top.name = "Top"; root_box.add_child(top)
    var title := Label.new(); title.text = "ECO EVO7 — VIS1 Spatial World Viewer"; title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top.add_child(title)
    generation_label = Label.new(); generation_label.name = "Generation"; top.add_child(generation_label)
    population_label = Label.new(); population_label.name = "Population"; top.add_child(population_label)

    var body := HBoxContainer.new(); body.name = "Body"; body.size_flags_vertical = Control.SIZE_EXPAND_FILL; body.size_flags_horizontal = Control.SIZE_EXPAND_FILL; root_box.add_child(body)
    var panel := PanelContainer.new(); panel.name = "ControlPanel"; panel.custom_minimum_size = Vector2(355, 680); body.add_child(panel)
    var controls := VBoxContainer.new(); controls.name = "Controls"; controls.add_theme_constant_override("separation", 7); panel.add_child(controls)

    world_seed_input = _spin_box("WorldSeed", Workbench.DEFAULT_WORLD_SEED); _row(controls, "World seed", world_seed_input)
    environment_seed_input = _spin_box("EnvironmentSeed", Workbench.DEFAULT_ENVIRONMENT_SEED); _row(controls, "Environment seed", environment_seed_input)
    recipe_select = OptionButton.new(); recipe_select.name = "Recipe"
    for recipe in EnvironmentField.new().recipe_ids(): recipe_select.add_item(String(recipe))
    _row(controls, "Environment", recipe_select)
    _button(controls, "ApplyPhysical", "Apply physical + reset", _on_apply_physical)

    var transport := HBoxContainer.new(); transport.name = "Transport"; controls.add_child(transport)
    _button(transport, "Start", "Start", _on_start)
    _button(transport, "Pause", "Pause", _on_pause)
    _button(transport, "Reset", "Reset", _on_reset)
    var steps := HBoxContainer.new(); steps.name = "Steps"; controls.add_child(steps)
    _button(steps, "Step1", "+1", func(): manual_step(1))
    _button(steps, "Step10", "+10", func(): manual_step(10))

    overlay_group_select = OptionButton.new(); overlay_group_select.name = "OverlayGroup"
    for group in ["environment", "population", "biome"]: overlay_group_select.add_item(group)
    overlay_group_select.item_selected.connect(_on_overlay_group_selected)
    _row(controls, "Overlay group", overlay_group_select)
    overlay_metric_select = OptionButton.new(); overlay_metric_select.name = "OverlayMetric"; overlay_metric_select.item_selected.connect(_on_overlay_metric_selected)
    _row(controls, "Overlay metric", overlay_metric_select)

    var camera_row := HBoxContainer.new(); camera_row.name = "Camera"; controls.add_child(camera_row)
    _button(camera_row, "ResetCamera", "Reset camera", reset_camera)
    camera_label = Label.new(); camera_label.name = "CameraState"; camera_row.add_child(camera_label)

    selected_label = Label.new(); selected_label.name = "SelectedCell"; controls.add_child(selected_label)
    selected_details = RichTextLabel.new(); selected_details.name = "SelectedDetails"; selected_details.bbcode_enabled = true; selected_details.fit_content = false; selected_details.custom_minimum_size = Vector2(330, 280); selected_details.scroll_active = true; controls.add_child(selected_details)
    var help := Label.new(); help.text = "LMB select • wheel zoom • MMB/RMB drag"; controls.add_child(help)

    var world_panel := PanelContainer.new(); world_panel.name = "WorldPanel"; world_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL; world_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL; body.add_child(world_panel)
    world_canvas = SpatialCanvas.new(); world_canvas.name = "SpatialCanvas"; world_canvas.custom_minimum_size = Vector2(720, 680); world_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL; world_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL; world_panel.add_child(world_canvas)
    world_canvas.cell_selected.connect(_on_canvas_cell_selected)
    world_canvas.camera_changed.connect(_on_camera_changed)
    _populate_metric_selector()
    _on_camera_changed(1.0, Vector2.ZERO)

func _sync_controls() -> void:
    if workbench == null:
        return
    var snapshot: Dictionary = workbench.get_workbench_snapshot()
    if snapshot.is_empty():
        return
    var spec: Dictionary = snapshot["spec"]
    world_seed_input.set_value_no_signal(float(spec["world_seed"]))
    environment_seed_input.set_value_no_signal(float(spec["environment_seed"]))
    _select_text(recipe_select, String(spec["environment_recipe"]))
    _select_text(overlay_group_select, active_overlay_group)
    _populate_metric_selector()

func _populate_metric_selector() -> void:
    if overlay_metric_select == null:
        return
    overlay_metric_select.clear()
    var values: Array = Array(Workbench.OVERLAY_SELECTORS.get(active_overlay_group, []))
    for value in values:
        overlay_metric_select.add_item(String(value))
    if workbench != null:
        _select_text(overlay_metric_select, _active_selector())

func _active_selector() -> String:
    if workbench == null:
        return ""
    var snapshot: Dictionary = workbench.get_workbench_snapshot()
    var spec: Dictionary = snapshot.get("spec", {})
    return String(spec.get("%s_overlay" % active_overlay_group, ""))

func _population_counts() -> Array[int]:
    var counts: Array[int] = []
    counts.resize(CELL_COUNT); counts.fill(0)
    if workbench == null:
        return counts
    var ecology: Dictionary = workbench.get_ecology_snapshot()
    for value in Array(ecology.get("records", [])):
        if not value is Dictionary:
            continue
        var index := int(Dictionary(value).get("cell_index", -1))
        if index >= 0 and index < CELL_COUNT:
            counts[index] += 1
    return counts

func _record_lineage(record: Dictionary) -> String:
    var bundle_value = record.get("hereditary_bundle")
    if not bundle_value is Dictionary:
        return ""
    var lineage_value = Dictionary(bundle_value).get("lineage_record")
    if not lineage_value is Dictionary:
        return ""
    return String(Dictionary(lineage_value).get("lineage_id", ""))

func _refresh_all() -> void:
    _refresh_status()
    _refresh_world()
    _refresh_selection()

func _refresh_status() -> void:
    if workbench == null:
        return
    var snapshot: Dictionary = workbench.get_workbench_snapshot()
    var ecology: Dictionary = workbench.get_ecology_snapshot()
    generation_label.text = "Generation %d" % int(snapshot.get("generation", 0))
    population_label.text = "Population %d" % int(ecology.get("record_count", 0))

func _refresh_world() -> void:
    if workbench == null or world_canvas == null:
        return
    var projection: Array[Dictionary] = workbench.get_overlay_projection(active_overlay_group)
    if projection.size() != CELL_COUNT:
        var empty_projection: Array[Dictionary] = []
        for index in CELL_COUNT:
            empty_projection.append({"index": index, "x": index % GRID_SIZE, "y": index / GRID_SIZE, "label": "", "value": 0.0})
        projection = empty_projection
    world_canvas.set_projection(active_overlay_group, projection, _population_counts())

func _refresh_selection() -> void:
    if selected_label == null or selected_details == null or workbench == null:
        return
    var observation := get_cell_observation(selected_cell)
    if observation.is_empty():
        return
    selected_label.text = "Selected cell %d  [%d,%d]" % [selected_cell, int(observation["x"]), int(observation["y"])]
    var lineage_text := "-"
    var lineage_ids: Array = observation["lineage_ids"]
    if not lineage_ids.is_empty():
        var sample := PackedStringArray()
        for i in mini(4, lineage_ids.size()): sample.append(String(lineage_ids[i]))
        lineage_text = ", ".join(sample)
        if lineage_ids.size() > 4: lineage_text += " …"
    var overlay_text := String(observation["active_overlay_label"])
    if overlay_text.is_empty() and observation["active_overlay_value"] != null:
        overlay_text = "%.5f" % float(observation["active_overlay_value"])
    selected_details.text = "[b]Physical[/b]\nElevation: %.1f m\nSoil moisture: %.4f\nSurface water: %.4f\nLight: %.4f\nTemperature: %.2f C\n\n[b]Ecology[/b]\nPopulation: %d\nLineages: %d\nBiome: %s\nBase biome: %s\n\n[b]Overlay[/b]\n%s / %s = %s\n\n[b]Lineage sample[/b]\n%s" % [
        float(observation["elevation_m"]), float(observation["soil_moisture"]), float(observation["surface_water_fraction"]), float(observation["incident_light"]), float(observation["temperature_c"]),
        int(observation["population_count"]), int(observation["lineage_richness"]), String(observation["emergent_biome"]), String(observation["base_biome"]),
        String(observation["active_overlay_group"]), String(observation["active_overlay_selector"]), overlay_text, lineage_text,
    ]

func _spin_box(node_name: String, initial: int) -> SpinBox:
    var spin := SpinBox.new(); spin.name = node_name; spin.min_value = -2147483648.0; spin.max_value = 2147483647.0; spin.step = 1.0; spin.value = initial; spin.rounded = true; return spin

func _row(parent: VBoxContainer, label_text: String, control: Control) -> void:
    var row := HBoxContainer.new(); row.name = "%sRow" % control.name; parent.add_child(row)
    var label := Label.new(); label.text = label_text; label.custom_minimum_size.x = 130; row.add_child(label)
    control.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(control)

func _button(parent: Container, node_name: String, text_value: String, callback: Callable) -> Button:
    var button := Button.new(); button.name = node_name; button.text = text_value; button.pressed.connect(callback); parent.add_child(button); return button

func _select_text(select: OptionButton, value: String) -> void:
    for index in select.item_count:
        if select.get_item_text(index) == value:
            select.select(index); return

func _on_apply_physical() -> void:
    if recipe_select == null:
        return
    apply_physical_controls(int(world_seed_input.value), int(environment_seed_input.value), recipe_select.get_item_text(recipe_select.selected))

func _on_start() -> void:
    if workbench != null: workbench.start()

func _on_pause() -> void:
    if workbench != null: workbench.pause(); accumulator = 0.0

func _on_reset() -> void:
    reset_same_seeds()

func _on_overlay_group_selected(index: int) -> void:
    set_active_overlay_group(overlay_group_select.get_item_text(index))

func _on_overlay_metric_selected(index: int) -> void:
    set_active_overlay_selector(overlay_metric_select.get_item_text(index))

func _on_canvas_cell_selected(index: int) -> void:
    select_cell(index)

func _on_camera_changed(zoom_value: float, pan_value: Vector2) -> void:
    if camera_label != null:
        camera_label.text = "%.2fx  pan %.0f,%.0f" % [zoom_value, pan_value.x, pan_value.y]
