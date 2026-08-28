extends Control

signal cell_selected(cell_index: int)
signal camera_changed(zoom: float, pan: Vector2)

## ECO.EVO7 VIS1 presentation-only spatial canvas.
## Pure renderer: owns no Workbench/ecology reference and receives immutable projections.

const GRID_SIZE := 32
const CELL_COUNT := GRID_SIZE * GRID_SIZE
const BASE_CELL_PX := 18.0
const MIN_ZOOM := 0.45
const MAX_ZOOM := 4.0

var active_group := "environment"
var projection: Array[Dictionary] = []
var occupancy: Array[int] = []
var camera_zoom := 1.0
var camera_pan := Vector2.ZERO
var selected_cell := -1
var dragging := false
var drag_last := Vector2.ZERO

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    clip_contents = true
    set_process(false)

func set_projection(group: String, values: Array[Dictionary], population_counts: Array[int]) -> bool:
    if not group in ["environment", "population", "biome"]:
        return false
    if values.size() != CELL_COUNT or population_counts.size() != CELL_COUNT:
        return false
    for index in CELL_COUNT:
        var entry: Dictionary = values[index]
        if int(entry.get("index", -1)) != index or int(entry.get("x", -1)) != index % GRID_SIZE or int(entry.get("y", -1)) != index / GRID_SIZE:
            return false
        if population_counts[index] < 0:
            return false
    active_group = group
    projection = values.duplicate(true)
    occupancy = population_counts.duplicate()
    queue_redraw()
    return true

func set_selected_cell(index: int) -> bool:
    if index < 0 or index >= CELL_COUNT:
        return false
    selected_cell = index
    queue_redraw()
    return true

func set_camera_state(zoom_value: float, pan_value: Vector2) -> bool:
    if not is_finite(zoom_value) or zoom_value < MIN_ZOOM or zoom_value > MAX_ZOOM:
        return false
    if not is_finite(pan_value.x) or not is_finite(pan_value.y):
        return false
    camera_zoom = zoom_value
    camera_pan = pan_value
    queue_redraw()
    camera_changed.emit(camera_zoom, camera_pan)
    return true

func reset_camera() -> void:
    camera_zoom = 1.0
    camera_pan = Vector2.ZERO
    queue_redraw()
    camera_changed.emit(camera_zoom, camera_pan)

func get_camera_state() -> Dictionary:
    return {"zoom": camera_zoom, "pan_x": camera_pan.x, "pan_y": camera_pan.y}

func get_render_contract() -> Dictionary:
    return {
        "grid_size": GRID_SIZE,
        "cell_count": CELL_COUNT,
        "pan": true,
        "zoom": true,
        "cell_selection": true,
        "population_markers": true,
        "presentation_only": true,
    }

func screen_to_cell(position: Vector2) -> int:
    var origin := _grid_origin()
    var cell_px := BASE_CELL_PX * camera_zoom
    if cell_px <= 0.0:
        return -1
    var local := position - origin
    var x := int(floor(local.x / cell_px))
    var y := int(floor(local.y / cell_px))
    if x < 0 or x >= GRID_SIZE or y < 0 or y >= GRID_SIZE:
        return -1
    return y * GRID_SIZE + x

func cell_center_screen(index: int) -> Vector2:
    if index < 0 or index >= CELL_COUNT:
        return Vector2(INF, INF)
    var cell_px := BASE_CELL_PX * camera_zoom
    return _grid_origin() + Vector2((index % GRID_SIZE + 0.5) * cell_px, (index / GRID_SIZE + 0.5) * cell_px)

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        var mouse := event as InputEventMouseButton
        if mouse.button_index == MOUSE_BUTTON_WHEEL_UP and mouse.pressed:
            _zoom_at(mouse.position, 1.12); accept_event(); return
        if mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse.pressed:
            _zoom_at(mouse.position, 1.0 / 1.12); accept_event(); return
        if mouse.button_index == MOUSE_BUTTON_MIDDLE or mouse.button_index == MOUSE_BUTTON_RIGHT:
            dragging = mouse.pressed
            drag_last = mouse.position
            accept_event(); return
        if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
            var index := screen_to_cell(mouse.position)
            if index >= 0:
                set_selected_cell(index)
                cell_selected.emit(index)
            accept_event(); return
    if event is InputEventMouseMotion and dragging:
        var motion := event as InputEventMouseMotion
        camera_pan += motion.position - drag_last
        drag_last = motion.position
        queue_redraw()
        camera_changed.emit(camera_zoom, camera_pan)
        accept_event()

func _zoom_at(position: Vector2, factor: float) -> void:
    var old_zoom := camera_zoom
    var new_zoom := clampf(old_zoom * factor, MIN_ZOOM, MAX_ZOOM)
    if is_equal_approx(old_zoom, new_zoom):
        return
    var old_origin := _grid_origin()
    var world_px := (position - old_origin) / old_zoom
    camera_zoom = new_zoom
    var centered_origin := _centered_origin(new_zoom)
    camera_pan = position - centered_origin - world_px * new_zoom
    queue_redraw()
    camera_changed.emit(camera_zoom, camera_pan)

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.03, 0.04, 1.0), true)
    if projection.size() != CELL_COUNT or occupancy.size() != CELL_COUNT:
        _draw_empty_message()
        return
    var cell_px := BASE_CELL_PX * camera_zoom
    var origin := _grid_origin()
    var value_range := _numeric_range()
    for index in CELL_COUNT:
        var x := index % GRID_SIZE
        var y := index / GRID_SIZE
        var rect := Rect2(origin + Vector2(x * cell_px, y * cell_px), Vector2(cell_px, cell_px))
        if rect.end.x < 0.0 or rect.end.y < 0.0 or rect.position.x > size.x or rect.position.y > size.y:
            continue
        var fill := _entry_color(projection[index], value_range)
        draw_rect(rect.grow(-0.45), fill, true)
        if camera_zoom >= 0.7:
            draw_rect(rect, Color(0.0, 0.0, 0.0, 0.20), false, maxf(1.0, camera_zoom * 0.45))
        var count := occupancy[index]
        if count > 0 and cell_px >= 8.0:
            var radius := clampf(1.4 + sqrt(float(count)) * 0.65, 2.0, cell_px * 0.28)
            draw_circle(rect.get_center(), radius, Color(0.96, 0.96, 0.92, 0.90))
    if selected_cell >= 0:
        var sx := selected_cell % GRID_SIZE
        var sy := selected_cell / GRID_SIZE
        var selected_rect := Rect2(origin + Vector2(sx * cell_px, sy * cell_px), Vector2(cell_px, cell_px))
        draw_rect(selected_rect.grow(1.5), Color(1.0, 0.88, 0.30, 1.0), false, maxf(2.0, camera_zoom * 1.5))

func _draw_empty_message() -> void:
    var font := ThemeDB.fallback_font
    draw_string(font, Vector2(22, 36), "No spatial projection", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.7, 0.75, 0.82))

func _grid_origin() -> Vector2:
    return _centered_origin(camera_zoom) + camera_pan

func _centered_origin(zoom_value: float) -> Vector2:
    var extent := Vector2(GRID_SIZE * BASE_CELL_PX * zoom_value, GRID_SIZE * BASE_CELL_PX * zoom_value)
    return (size - extent) * 0.5

func _numeric_range() -> Vector2:
    if active_group == "biome":
        return Vector2.ZERO
    var lo := INF
    var hi := -INF
    for entry in projection:
        var value := float(entry.get("value", 0.0))
        lo = minf(lo, value)
        hi = maxf(hi, value)
    if not is_finite(lo) or not is_finite(hi):
        return Vector2(0.0, 1.0)
    return Vector2(lo, hi)

func _entry_color(entry: Dictionary, range_value: Vector2) -> Color:
    if active_group == "biome":
        return _biome_color(String(entry.get("label", "")))
    var span := maxf(range_value.y - range_value.x, 0.000000001)
    var t := clampf((float(entry.get("value", 0.0)) - range_value.x) / span, 0.0, 1.0)
    if active_group == "population":
        return Color(0.10 + 0.18 * t, 0.16 + 0.70 * t, 0.18 + 0.20 * t, 1.0)
    return Color(0.08 + 0.72 * t, 0.14 + 0.70 * t, 0.35 + 0.45 * (1.0 - t), 1.0)

func _biome_color(label: String) -> Color:
    match label:
        "desert-like": return Color(0.78, 0.67, 0.28)
        "wetland-like": return Color(0.15, 0.55, 0.62)
        "forest-like": return Color(0.12, 0.48, 0.20)
        "grass/shrub-like": return Color(0.46, 0.68, 0.26)
        "alpine-like": return Color(0.72, 0.76, 0.82)
        "ecotone": return Color(0.72, 0.38, 0.72)
    return Color(0.08, 0.08, 0.08)
