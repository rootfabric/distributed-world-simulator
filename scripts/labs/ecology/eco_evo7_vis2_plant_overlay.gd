extends Control

## ECO.EVO7 VIS2 pure renderer. No ecology imports, no simulation references.
## Draw geometry is a deterministic presentation mapping from read-only descriptors.

signal plant_selected(record_id: String, cell_index: int)

const GRID_SIZE := 32
const CELL_COUNT := GRID_SIZE * GRID_SIZE
const BASE_CELL_PX := 18.0
const MIN_ZOOM := 0.45
const MAX_ZOOM := 4.0
const FOUNDER_EVIDENCE := "FOUNDER_RECORD_ONLY"

var descriptors: Array[Dictionary] = []
var camera_zoom := 1.0
var camera_pan := Vector2.ZERO
var show_roots := false
var selected_cell := -1
var selected_record_id := ""

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    clip_contents = true

func set_descriptors(values: Array[Dictionary]) -> bool:
    var ordered: Array[Dictionary] = []
    for value in values:
        if not value is Dictionary:
            return false
        var descriptor: Dictionary = value
        var cell_index := int(descriptor.get("cell_index", -1))
        var record_id := String(descriptor.get("record_id", ""))
        if cell_index < 0 or cell_index >= CELL_COUNT or record_id.is_empty():
            return false
        ordered.append(descriptor.duplicate(true))
    ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return String(a["record_id"]) < String(b["record_id"])
    )
    descriptors = ordered
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
    return true

func set_show_roots(value: bool) -> void:
    show_roots = value
    queue_redraw()

func set_selected_cell(index: int) -> bool:
    if index < 0 or index >= CELL_COUNT:
        return false
    selected_cell = index
    queue_redraw()
    return true

func get_render_contract() -> Dictionary:
    return {
        "procedural_plants": true,
        "phenotype_driven": true,
        "lineage_stable_color": true,
        "root_debug": true,
        "founder_markers": true,
        "presentation_only": true,
    }

func stem_height_px(descriptor: Dictionary, cell_px: float) -> float:
    if String(descriptor.get("evidence_level", "")) == FOUNDER_EVIDENCE:
        return maxf(5.0, cell_px * 0.28)
    var height_m := maxf(float(descriptor.get("realized_height_m", 0.0)), 0.0)
    var normalized := clampf(height_m / 12.0, 0.0, 1.0)
    return clampf(cell_px * (0.24 + 0.68 * sqrt(normalized)), 5.0, cell_px * 0.95)

func crown_radius_px(descriptor: Dictionary, cell_px: float) -> float:
    if String(descriptor.get("evidence_level", "")) == FOUNDER_EVIDENCE:
        return maxf(2.2, cell_px * 0.12)
    var lai := maxf(float(descriptor.get("leaf_area_index_proxy", 0.0)), 0.0)
    var lai_norm := clampf(lai / 4.0, 0.0, 1.0)
    var shoot_fraction := 1.0 - clampf(float(descriptor.get("root_shoot_ratio", 0.5)), 0.0, 1.0) * 0.45
    return clampf(cell_px * (0.10 + 0.24 * sqrt(lai_norm)) * shoot_fraction, 2.2, cell_px * 0.34)

func root_depth_px(descriptor: Dictionary, cell_px: float) -> float:
    var depth_m := maxf(float(descriptor.get("realized_root_depth_m", 0.0)), 0.0)
    return clampf(cell_px * 0.48 * sqrt(clampf(depth_m / 5.0, 0.0, 1.0)), 0.0, cell_px * 0.48)

func root_spread_px(descriptor: Dictionary, cell_px: float) -> float:
    var spread_m := maxf(float(descriptor.get("realized_root_spread_m", 0.0)), 0.0)
    return clampf(cell_px * 0.38 * sqrt(clampf(spread_m / 6.0, 0.0, 1.0)), 0.0, cell_px * 0.38)

func health_factor(descriptor: Dictionary) -> float:
    if String(descriptor.get("evidence_level", "")) == FOUNDER_EVIDENCE:
        return 0.72
    var water := clampf(float(descriptor.get("water_satisfaction", 0.0)), 0.0, 1.0)
    var balance := clampf(float(descriptor.get("realized_resource_balance", 0.0)), -1.0, 1.0)
    return clampf(0.30 + 0.50 * water + 0.20 * maxf(balance, 0.0), 0.20, 1.0)

func lineage_color(lineage_id: String, health: float = 1.0) -> Color:
    var token := lineage_id.sha256_text().substr(0, 8)
    var hue := float(token.hex_to_int()) / 4294967295.0
    var saturation := clampf(0.50 + 0.28 * health, 0.45, 0.82)
    var value := clampf(0.42 + 0.50 * health, 0.40, 0.95)
    return Color.from_hsv(hue, saturation, value, 0.96)

func _draw() -> void:
    if descriptors.is_empty():
        return
    var cell_px := BASE_CELL_PX * camera_zoom
    var origin := _grid_origin()
    for descriptor in descriptors:
        var cell_index := int(descriptor["cell_index"])
        var base_center := origin + Vector2((cell_index % GRID_SIZE + 0.5) * cell_px, (cell_index / GRID_SIZE + 0.5) * cell_px)
        var plant_center := base_center + _stable_jitter(String(descriptor["record_id"]), cell_px)
        if plant_center.x < -cell_px or plant_center.y < -cell_px or plant_center.x > size.x + cell_px or plant_center.y > size.y + cell_px:
            continue
        _draw_plant(descriptor, plant_center, cell_px)

func _draw_plant(descriptor: Dictionary, center: Vector2, cell_px: float) -> void:
    var founder := String(descriptor.get("evidence_level", "")) == FOUNDER_EVIDENCE
    var height_px := stem_height_px(descriptor, cell_px)
    var crown_px := crown_radius_px(descriptor, cell_px)
    var health := health_factor(descriptor)
    var color := Color(0.48, 0.88, 0.48, 0.96) if founder else lineage_color(String(descriptor.get("lineage_id", "")), health)
    var stem_color := Color(color.r * 0.58, color.g * 0.48, color.b * 0.34, 0.95)
    var ground := center + Vector2(0.0, cell_px * 0.22)
    var top := ground - Vector2(0.0, height_px)
    var root_shoot := clampf(float(descriptor.get("root_shoot_ratio", 0.5)), 0.0, 1.0)
    var stem_width := clampf(1.4 + camera_zoom * (0.55 + (1.0 - root_shoot) * 0.95), 1.4, 4.8)

    if show_roots and not founder:
        var root_depth := root_depth_px(descriptor, cell_px)
        var root_spread := root_spread_px(descriptor, cell_px)
        var root_color := Color(0.72, 0.46, 0.22, 0.82)
        draw_line(ground, ground + Vector2(0.0, root_depth), root_color, maxf(1.0, stem_width * 0.72), true)
        draw_line(ground + Vector2(0.0, root_depth * 0.46), ground + Vector2(-root_spread, root_depth * 0.80), root_color, 1.4, true)
        draw_line(ground + Vector2(0.0, root_depth * 0.52), ground + Vector2(root_spread, root_depth * 0.84), root_color, 1.4, true)

    draw_line(ground, top, stem_color, stem_width, true)
    if founder:
        draw_circle(top + Vector2(-crown_px * 0.55, 0.0), crown_px, color)
        draw_circle(top + Vector2(crown_px * 0.55, -crown_px * 0.12), crown_px, color)
    else:
        var lai := maxf(float(descriptor.get("leaf_area_index_proxy", 0.0)), 0.0)
        var leaf_count := clampi(2 + int(round(clampf(lai, 0.0, 4.0) * 1.4)), 2, 8)
        var drought := 1.0 - clampf(float(descriptor.get("water_satisfaction", 0.0)), 0.0, 1.0)
        for i in leaf_count:
            var fraction := (float(i) + 0.5) / float(leaf_count)
            var side := -1.0 if i % 2 == 0 else 1.0
            var vertical := top.y + height_px * (0.08 + 0.46 * fraction)
            var droop := drought * crown_px * 0.85 * fraction
            var leaf_center := Vector2(top.x + side * crown_px * (0.52 + 0.22 * fraction), vertical + droop)
            draw_circle(leaf_center, crown_px * (0.74 - 0.18 * fraction), color)
        draw_circle(top, crown_px * 0.88, color)

    if selected_cell == int(descriptor["cell_index"]):
        draw_arc(ground - Vector2(0.0, height_px * 0.48), maxf(crown_px * 1.6, 3.0), 0.0, TAU, 16, Color(1.0, 0.88, 0.30, 0.75), 1.0, true)

func _grid_origin() -> Vector2:
    var extent := Vector2(GRID_SIZE * BASE_CELL_PX * camera_zoom, GRID_SIZE * BASE_CELL_PX * camera_zoom)
    return (size - extent) * 0.5 + camera_pan

func _stable_jitter(record_id: String, cell_px: float) -> Vector2:
    var token := record_id.sha256_text()
    var ux := float(token.substr(0, 6).hex_to_int()) / 16777215.0
    var uy := float(token.substr(6, 6).hex_to_int()) / 16777215.0
    return Vector2((ux - 0.5) * cell_px * 0.48, (uy - 0.5) * cell_px * 0.30)
