extends Node

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const Workbench = preload("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd")
const EnvironmentField = preload("res://scripts/ecology/shadow/eco_evo7_ls31_environment_field_v1.gd")

## ECO.EVO7 LS3.6 minimal interactive laboratory.
## UI only calls the public Rule Workbench control/projection surface.
## It never touches ecology records, genomes, fitness, mutation or classifier internals.

@export var auto_initialize: bool = true
const AUTO_STEP_SECONDS := 0.65

var workbench = null
var planet_source = null
var owns_planet_source := false
var active_overlay_group := "environment"
var accumulator := 0.0
var ui_built := false
var grid_cells: Array[ColorRect] = []

var world_seed_input: SpinBox
var environment_seed_input: SpinBox
var recipe_select: OptionButton
var evolution_toggle: CheckButton
var competition_toggle: CheckButton
var environment_overlay_select: OptionButton
var population_overlay_select: OptionButton
var biome_overlay_select: OptionButton
var generation_label: Label
var population_label: Label
var lineage_label: Label
var entropy_label: Label
var class_label: Label
var overlay_title: Label
var overlay_grid: GridContainer

func _ready() -> void:
    ensure_ui_built()
    if auto_initialize:
        initialize_runtime()

func ensure_ui_built() -> void:
    if not ui_built:
        _build_ui()

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

func initialize_runtime(source = null) -> bool:
    if workbench != null:
        return true
    if source == null:
        planet_source = EarthWorld.new()
        planet_source.name = "WorkbenchEarthSource"
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
    _sync_controls_from_workbench()
    _refresh_all()
    return true

func get_ui_contract() -> Dictionary:
    return {
        "world_seed": world_seed_input != null,
        "environment_seed": environment_seed_input != null,
        "recipe": recipe_select != null,
        "start": get_node_or_null("WorkbenchUI/RootRow/ControlsPanel/Controls/Transport/Start") != null,
        "pause": get_node_or_null("WorkbenchUI/RootRow/ControlsPanel/Controls/Transport/Pause") != null,
        "reset": get_node_or_null("WorkbenchUI/RootRow/ControlsPanel/Controls/Transport/Reset") != null,
        "step_1": get_node_or_null("WorkbenchUI/RootRow/ControlsPanel/Controls/Steps/Step1") != null,
        "step_10": get_node_or_null("WorkbenchUI/RootRow/ControlsPanel/Controls/Steps/Step10") != null,
        "step_100": get_node_or_null("WorkbenchUI/RootRow/ControlsPanel/Controls/Steps/Step100") != null,
        "evolution": evolution_toggle != null,
        "competition": competition_toggle != null,
        "environment_overlay": environment_overlay_select != null,
        "population_overlay": population_overlay_select != null,
        "biome_overlay": biome_overlay_select != null,
        "grid_cells": grid_cells.size(),
    }

func get_grid_cell_count() -> int:
    return grid_cells.size()

func get_workbench_snapshot() -> Dictionary:
    return {} if workbench == null else workbench.get_workbench_snapshot()

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
    _sync_controls_from_workbench()
    _refresh_all()
    return true

func set_active_overlay_group(group: String) -> bool:
    if not group in ["environment", "population", "biome"]:
        return false
    active_overlay_group = group
    _refresh_overlay()
    return true

func _build_ui() -> void:
    if ui_built:
        return
    ui_built = true
    var canvas := CanvasLayer.new(); canvas.name = "WorkbenchUI"; add_child(canvas)
    var root_row := HBoxContainer.new(); root_row.name = "RootRow"; root_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); canvas.add_child(root_row)

    var controls_panel := PanelContainer.new(); controls_panel.name = "ControlsPanel"; controls_panel.custom_minimum_size = Vector2(360, 620); root_row.add_child(controls_panel)
    var controls := VBoxContainer.new(); controls.name = "Controls"; controls.add_theme_constant_override("separation", 7); controls_panel.add_child(controls)
    var title := Label.new(); title.text = "ECO EVO7 — LS3.6 Rule Workbench"; title.name = "Title"; controls.add_child(title)

    world_seed_input = _spin_box("WorldSeed", Workbench.DEFAULT_WORLD_SEED); _row(controls, "World seed", world_seed_input)
    environment_seed_input = _spin_box("EnvironmentSeed", Workbench.DEFAULT_ENVIRONMENT_SEED); _row(controls, "Environment seed", environment_seed_input)
    recipe_select = OptionButton.new(); recipe_select.name = "Recipe"
    for recipe in EnvironmentField.new().recipe_ids(): recipe_select.add_item(String(recipe))
    _row(controls, "Environment recipe", recipe_select)
    var apply := Button.new(); apply.name = "ApplyPhysical"; apply.text = "Apply physical controls + reset"; apply.pressed.connect(_on_apply_physical); controls.add_child(apply)

    var transport := HBoxContainer.new(); transport.name = "Transport"; controls.add_child(transport)
    _button(transport, "Start", "Start", _on_start)
    _button(transport, "Pause", "Pause", _on_pause)
    _button(transport, "Reset", "Reset", _on_reset)
    var steps := HBoxContainer.new(); steps.name = "Steps"; controls.add_child(steps)
    _button(steps, "Step1", "+1", func(): manual_step(1))
    _button(steps, "Step10", "+10", func(): manual_step(10))
    _button(steps, "Step100", "+100", func(): manual_step(100))

    evolution_toggle = CheckButton.new(); evolution_toggle.name = "Evolution"; evolution_toggle.text = "Evolution"; evolution_toggle.toggled.connect(_on_evolution_toggled); controls.add_child(evolution_toggle)
    competition_toggle = CheckButton.new(); competition_toggle.name = "Competition"; competition_toggle.text = "Competition"; competition_toggle.toggled.connect(_on_competition_toggled); controls.add_child(competition_toggle)

    environment_overlay_select = _selector("EnvironmentOverlay", Workbench.OVERLAY_SELECTORS["environment"], _on_environment_overlay); _row(controls, "Environment overlay", environment_overlay_select)
    population_overlay_select = _selector("PopulationOverlay", Workbench.OVERLAY_SELECTORS["population"], _on_population_overlay); _row(controls, "Population overlay", population_overlay_select)
    biome_overlay_select = _selector("BiomeOverlay", Workbench.OVERLAY_SELECTORS["biome"], _on_biome_overlay); _row(controls, "Emergent biome overlay", biome_overlay_select)

    var show := HBoxContainer.new(); show.name = "OverlayGroup"; controls.add_child(show)
    _button(show, "ShowEnvironment", "Show Env", func(): set_active_overlay_group("environment"))
    _button(show, "ShowPopulation", "Show Pop", func(): set_active_overlay_group("population"))
    _button(show, "ShowBiome", "Show Biome", func(): set_active_overlay_group("biome"))

    generation_label = Label.new(); generation_label.name = "Generation"; controls.add_child(generation_label)
    population_label = Label.new(); population_label.name = "Population"; controls.add_child(population_label)
    lineage_label = Label.new(); lineage_label.name = "Lineages"; controls.add_child(lineage_label)
    entropy_label = Label.new(); entropy_label.name = "Entropy"; controls.add_child(entropy_label)
    class_label = Label.new(); class_label.name = "Classes"; class_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; controls.add_child(class_label)

    var display := VBoxContainer.new(); display.name = "Display"; display.size_flags_horizontal = Control.SIZE_EXPAND_FILL; root_row.add_child(display)
    overlay_title = Label.new(); overlay_title.name = "OverlayTitle"; overlay_title.text = "Overlay"; display.add_child(overlay_title)
    var scroll := ScrollContainer.new(); scroll.name = "OverlayScroll"; scroll.custom_minimum_size = Vector2(520, 520); scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; display.add_child(scroll)
    overlay_grid = GridContainer.new(); overlay_grid.name = "OverlayGrid"; overlay_grid.columns = 32; scroll.add_child(overlay_grid)
    for index in Workbench.GRID_SIZE * Workbench.GRID_SIZE:
        var cell := ColorRect.new(); cell.name = "Cell_%04d" % index; cell.custom_minimum_size = Vector2(14, 14); cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
        overlay_grid.add_child(cell); grid_cells.append(cell)

func _spin_box(node_name: String, initial: int) -> SpinBox:
    var spin := SpinBox.new(); spin.name = node_name; spin.min_value = -2147483648.0; spin.max_value = 2147483647.0; spin.step = 1.0; spin.value = initial; spin.rounded = true; return spin

func _selector(node_name: String, values, callback: Callable) -> OptionButton:
    var select := OptionButton.new(); select.name = node_name
    for value in Array(values): select.add_item(String(value))
    select.item_selected.connect(callback)
    return select

func _row(parent: VBoxContainer, label_text: String, control: Control) -> void:
    var row := HBoxContainer.new(); row.name = "%sRow" % control.name; parent.add_child(row)
    var label := Label.new(); label.text = label_text; label.custom_minimum_size.x = 150; row.add_child(label)
    control.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(control)

func _button(parent: Container, node_name: String, text_value: String, callback: Callable) -> Button:
    var button := Button.new(); button.name = node_name; button.text = text_value; button.pressed.connect(callback); parent.add_child(button); return button

func _sync_controls_from_workbench() -> void:
    if workbench == null: return
    var snapshot: Dictionary = workbench.get_workbench_snapshot(); if snapshot.is_empty(): return
    var current: Dictionary = snapshot["spec"]
    world_seed_input.set_value_no_signal(float(current["world_seed"]))
    environment_seed_input.set_value_no_signal(float(current["environment_seed"]))
    _select_text(recipe_select, String(current["environment_recipe"]))
    evolution_toggle.set_pressed_no_signal(bool(current["evolution_enabled"]))
    competition_toggle.set_pressed_no_signal(bool(current["competition_enabled"]))
    _select_text(environment_overlay_select, String(current["environment_overlay"]))
    _select_text(population_overlay_select, String(current["population_overlay"]))
    _select_text(biome_overlay_select, String(current["biome_overlay"]))

func _select_text(select: OptionButton, value: String) -> void:
    for index in select.item_count:
        if select.get_item_text(index) == value:
            select.select(index); return

func _on_apply_physical() -> void:
    if workbench == null: return
    var recipe := recipe_select.get_item_text(recipe_select.selected)
    if workbench.apply_physical_controls(int(world_seed_input.value), int(environment_seed_input.value), recipe):
        _sync_controls_from_workbench(); _refresh_all()

func _on_start() -> void:
    if workbench != null: workbench.start()

func _on_pause() -> void:
    if workbench != null: workbench.pause(); accumulator = 0.0

func _on_reset() -> void:
    reset_same_seeds()

func _on_evolution_toggled(value: bool) -> void:
    if workbench != null and workbench.set_evolution_enabled(value): _refresh_all()

func _on_competition_toggled(value: bool) -> void:
    if workbench != null and workbench.set_competition_enabled(value): _refresh_all()

func _on_environment_overlay(index: int) -> void:
    if workbench != null: workbench.set_overlay_selector("environment", environment_overlay_select.get_item_text(index)); _refresh_overlay()

func _on_population_overlay(index: int) -> void:
    if workbench != null: workbench.set_overlay_selector("population", population_overlay_select.get_item_text(index)); _refresh_overlay()

func _on_biome_overlay(index: int) -> void:
    if workbench != null: workbench.set_overlay_selector("biome", biome_overlay_select.get_item_text(index)); _refresh_overlay()

func _refresh_all() -> void:
    _refresh_status(); _refresh_overlay()

func _refresh_status() -> void:
    if workbench == null: return
    var snapshot: Dictionary = workbench.get_workbench_snapshot(); if snapshot.is_empty(): return
    var ecology: Dictionary = workbench.get_ecology_snapshot()
    var history: Array[Dictionary] = workbench.get_spatial_history()
    var latest: Dictionary = history[-1] if not history.is_empty() else {}
    generation_label.text = "Generation: %d" % int(snapshot["generation"])
    population_label.text = "Population: %d | occupied cells: %d" % [int(ecology.get("record_count", 0)), int(latest.get("occupied_cells", 0))]
    lineage_label.text = "Lineages: %d" % int(latest.get("lineage_richness", 0))
    entropy_label.text = "Shannon entropy: %.5f" % float(latest.get("shannon_entropy", 0.0))
    var counts: Dictionary = latest.get("class_counts", {})
    var parts: PackedStringArray = []
    var keys := counts.keys(); keys.sort()
    for key in keys: parts.append("%s=%d" % [String(key), int(counts[key])])
    class_label.text = "Classes: %s" % (", ".join(parts) if not parts.is_empty() else "not classified yet")

func _refresh_overlay() -> void:
    if workbench == null or grid_cells.is_empty(): return
    var projection: Array[Dictionary] = workbench.get_overlay_projection(active_overlay_group)
    overlay_title.text = "%s overlay" % active_overlay_group.capitalize()
    if projection.size() != grid_cells.size():
        for cell in grid_cells: cell.color = Color(0.08, 0.08, 0.08, 1.0)
        return
    if active_overlay_group == "biome":
        for index in projection.size(): grid_cells[index].color = _biome_color(String(projection[index].get("label", "")))
        return
    var min_value := INF; var max_value := -INF
    for value in projection:
        var number := float(value.get("value", 0.0)); min_value = minf(min_value, number); max_value = maxf(max_value, number)
    var span := maxf(max_value - min_value, 0.000000001)
    for index in projection.size():
        var t := clampf((float(projection[index].get("value", 0.0)) - min_value) / span, 0.0, 1.0)
        grid_cells[index].color = Color(0.08 + 0.72 * t, 0.14 + 0.70 * t, 0.35 + 0.45 * (1.0 - t), 1.0)

func _biome_color(label: String) -> Color:
    match label:
        "desert-like": return Color(0.78, 0.67, 0.28)
        "wetland-like": return Color(0.15, 0.55, 0.62)
        "forest-like": return Color(0.12, 0.48, 0.20)
        "grass/shrub-like": return Color(0.46, 0.68, 0.26)
        "alpine-like": return Color(0.72, 0.76, 0.82)
        "ecotone": return Color(0.72, 0.38, 0.72)
    return Color(0.08, 0.08, 0.08)
