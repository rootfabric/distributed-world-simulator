extends Node2D

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const LS41 = preload("res://scripts/ecology/shadow/eco_evo7_ls41_multi_species_ecology_v1.gd")
const EnvironmentField = preload("res://scripts/ecology/shadow/eco_evo7_ls31_environment_field_v1.gd")

## ECO.EVO7 LS4-VIS1 — derived-only multi-species distribution observatory.
## Rendering and cell selection never participate in ecology hashes.

const TITLE := "ECO EVO7 — LS4.1 Multi-Species Observatory"
const GRID_SIZE := 32
const CELL_PX := 18.0
const GRID_ORIGIN := Vector2(28.0, 110.0)
const GRID_EXTENT := Vector2(GRID_SIZE * CELL_PX, GRID_SIZE * CELL_PX)
const SPECIES_COLORS := {
    "riparian_pioneer": Color(0.20, 0.70, 0.95),
    "xeric_anchor": Color(0.95, 0.62, 0.18),
    "shade_weaver": Color(0.48, 0.82, 0.38),
}

var world = null
var ecology = null
var projection: Array[Dictionary] = []
var selected_cell := -1
var status_label: Label
var details_label: Label
var recipe_label: Label

func _ready() -> void:
    DisplayServer.window_set_title(TITLE)
    world = EarthWorld.new()
    add_child(world)
    if not world.setup(null):
        push_error("LS4-VIS1: failed to initialize Earth")
        return
    ecology = LS41.new()
    if not ecology.setup(world):
        push_error("LS4-VIS1: failed to initialize LS4.1")
        return
    _build_ui()
    _refresh_projection()
    print("ECO.EVO7 LS4-VIS1 READY")

func get_visual_contract() -> Dictionary:
    return {
        "revision": "ECO.EVO7-LS4-VIS1-R1",
        "derived_only": true,
        "ecology_write": false,
        "world_write": false,
        "species_distribution_overlay": true,
        "cell_species_composition": true,
        "manual_generation_controls": true,
        "physical_counterfactual_control": true,
    }

func _draw() -> void:
    draw_rect(Rect2(GRID_ORIGIN - Vector2(2, 2), GRID_EXTENT + Vector2(4, 4)), Color(0.06, 0.07, 0.08), true)
    if projection.size() != GRID_SIZE * GRID_SIZE:
        return
    for cell in projection:
        var index := int(cell.get("index", -1))
        if index < 0:
            continue
        var x := int(cell.get("x", 0))
        var y := int(cell.get("y", 0))
        var dominant := String(cell.get("dominant_species_id", ""))
        var total := int(cell.get("total_records", 0))
        var richness := int(cell.get("species_richness", 0))
        var rect := Rect2(GRID_ORIGIN + Vector2(x, y) * CELL_PX, Vector2(CELL_PX - 1.0, CELL_PX - 1.0))
        if total <= 0 or dominant.is_empty():
            draw_rect(rect, Color(0.10, 0.11, 0.12), true)
        else:
            var base: Color = SPECIES_COLORS.get(dominant, Color(0.75, 0.75, 0.75))
            var strength := clampf(0.35 + float(total) * 0.12, 0.35, 1.0)
            var color := Color(base.r * strength, base.g * strength, base.b * strength, 1.0)
            draw_rect(rect, color, true)
            if richness > 1:
                draw_rect(rect.grow(-2.0), Color(1, 1, 1, 0.45), false, 1.0)
        if index == selected_cell:
            draw_rect(rect.grow(1.0), Color.WHITE, false, 2.0)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        var local := event.position - GRID_ORIGIN
        if local.x >= 0.0 and local.y >= 0.0 and local.x < GRID_EXTENT.x and local.y < GRID_EXTENT.y:
            var x := int(local.x / CELL_PX)
            var y := int(local.y / CELL_PX)
            selected_cell = y * GRID_SIZE + x
            _refresh_details()
            queue_redraw()

func _build_ui() -> void:
    var layer := CanvasLayer.new()
    layer.name = "LS4VIS1UI"
    add_child(layer)

    var top := PanelContainer.new()
    top.position = Vector2(20, 14)
    top.size = Vector2(1100, 82)
    layer.add_child(top)
    var top_box := VBoxContainer.new()
    top.add_child(top_box)
    var title := Label.new()
    title.text = TITLE
    top_box.add_child(title)
    var row := HBoxContainer.new()
    top_box.add_child(row)
    _button(row, "+1 generation", func(): _advance(1))
    _button(row, "+10 generations", func(): _advance(10))
    _button(row, "Reset same inputs", _reset_same)
    _button(row, "Next environment recipe", _next_recipe)
    status_label = Label.new()
    status_label.custom_minimum_size = Vector2(420, 0)
    row.add_child(status_label)

    var side := PanelContainer.new()
    side.position = Vector2(GRID_ORIGIN.x + GRID_EXTENT.x + 24.0, GRID_ORIGIN.y)
    side.size = Vector2(430, 510)
    layer.add_child(side)
    var side_box := VBoxContainer.new()
    side_box.add_theme_constant_override("separation", 8)
    side.add_child(side_box)

    var legend_title := Label.new()
    legend_title.text = "Species / functional strategies"
    side_box.add_child(legend_title)
    for entry in ecology.get_species_catalog():
        var species_id := String(entry["species_id"])
        var axes: Dictionary = entry["functional_axes"]
        var label := Label.new()
        label.text = "%s  (%s)\n growth %.2f | water %.2f | light %.2f | stress %.2f | repro %.2f" % [
            String(entry["display_name"]), species_id,
            float(axes["growth_strategy"]), float(axes["water_demand"]),
            float(axes["light_demand"]), float(axes["stress_tolerance"]),
            float(axes["reproduction_strategy"]),
        ]
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        side_box.add_child(label)

    var divider := HSeparator.new()
    side_box.add_child(divider)
    recipe_label = Label.new()
    recipe_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    side_box.add_child(recipe_label)
    details_label = Label.new()
    details_label.text = "Click a cell to inspect species composition.\nWhite inset = >1 species in the same cell overlay."
    details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    side_box.add_child(details_label)

func _button(parent: Control, text_value: String, callback: Callable) -> void:
    var button := Button.new()
    button.text = text_value
    button.pressed.connect(callback)
    parent.add_child(button)

func _advance(count: int) -> void:
    if ecology == null:
        return
    var result: Dictionary = ecology.step_generations(count)
    if result.is_empty():
        status_label.text = "STEP FAILED / aggregate publication blocked"
        return
    _refresh_projection()

func _reset_same() -> void:
    if ecology != null and ecology.reset_same_inputs():
        selected_cell = -1
        _refresh_projection()

func _next_recipe() -> void:
    if ecology == null:
        return
    var snapshot: Dictionary = ecology.get_snapshot()
    var current := String(snapshot.get("environment_recipe_id", ""))
    var recipes := EnvironmentField.new().recipe_ids()
    if recipes.is_empty():
        return
    var next_index := 0
    for index in recipes.size():
        if String(recipes[index]) == current:
            next_index = (index + 1) % recipes.size()
            break
    if ecology.apply_physical_controls(
        int(snapshot.get("world_seed", LS41.DEFAULT_WORLD_SEED)),
        int(snapshot.get("environment_seed", LS41.DEFAULT_ENVIRONMENT_SEED)),
        String(recipes[next_index])
    ):
        selected_cell = -1
        _refresh_projection()

func _refresh_projection() -> void:
    if ecology == null:
        return
    projection = ecology.get_species_projection()
    var snapshot: Dictionary = ecology.get_snapshot()
    if status_label != null:
        status_label.text = "generation %d | species %d | records %d | occupied overlay cells %d" % [
            int(snapshot.get("generation", -1)),
            int(snapshot.get("species_count", 0)),
            int(snapshot.get("total_record_count", 0)),
            _occupied_cells(),
        ]
    if recipe_label != null:
        recipe_label.text = "Environment recipe: %s\nEnvironment hash: %s…\nCatalog hash: %s…" % [
            String(snapshot.get("environment_recipe_id", "")),
            String(snapshot.get("environment_field_hash", "")).substr(0, 16),
            String(snapshot.get("species_catalog_hash", "")).substr(0, 16),
        ]
    _refresh_details()
    queue_redraw()

func _occupied_cells() -> int:
    var count := 0
    for cell in projection:
        if int(cell.get("total_records", 0)) > 0:
            count += 1
    return count

func _refresh_details() -> void:
    if details_label == null or selected_cell < 0 or selected_cell >= projection.size():
        return
    var cell: Dictionary = projection[selected_cell]
    var counts: Dictionary = cell.get("species_counts", {})
    var lines := PackedStringArray([
        "Cell %d  (%d, %d)" % [selected_cell, int(cell["x"]), int(cell["y"])],
        "richness: %d" % int(cell["species_richness"]),
        "total records: %d" % int(cell["total_records"]),
        "dominant: %s" % String(cell["dominant_species_id"]),
        "",
    ])
    var ids := PackedStringArray(counts.keys())
    ids.sort()
    for species_id in ids:
        lines.append("%s: %d" % [species_id, int(counts[species_id])])
    details_label.text = "\n".join(lines)
