extends Control

## ECO.EVO7 VIS3 pure terrain/biome renderer.
## Receives immutable planet-patch, classification and population summaries.
## Owns no Workbench/ecology reference and never writes simulation state.

const GRID_SIZE := 32
const CELL_COUNT := GRID_SIZE * GRID_SIZE
const BASE_CELL_PX := 18.0
const MIN_ZOOM := 0.45
const MAX_ZOOM := 4.0
const LOD_AUTO := "AUTO"
const LOD_REGION := "REGION"
const LOD_PATCH := "PATCH"
const LOD_PLANT := "PLANT"
const LOD_VALUES: Array[String] = [LOD_AUTO, LOD_REGION, LOD_PATCH, LOD_PLANT]

var patch: Dictionary = {}
var classification: Dictionary = {}
var population_counts: Array[int] = []
var historical_biome_labels: Array[String] = []
var camera_zoom := 1.0
var camera_pan := Vector2.ZERO
var lod_mode := LOD_AUTO
var show_contours := true
var show_biome_boundaries := true
var history_mode := false
var elevation_range := Vector2.ZERO

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    clip_contents = true

func set_sources(patch_value: Dictionary, classification_value: Dictionary, counts: Array[int]) -> bool:
    if not _validate_patch(patch_value) or counts.size() != CELL_COUNT:
        return false
    for count in counts:
        if count < 0:
            return false
    if not classification_value.is_empty() and Array(classification_value.get("cells", [])).size() != CELL_COUNT:
        return false
    patch = patch_value.duplicate(true)
    classification = classification_value.duplicate(true)
    population_counts = counts.duplicate()
    historical_biome_labels.clear()
    history_mode = false
    elevation_range = _compute_elevation_range()
    queue_redraw()
    return true

func set_history_frame(frame: Dictionary) -> bool:
    if patch.is_empty():
        return false
    var counts_value = frame.get("population_counts")
    var labels_value = frame.get("biome_labels")
    if not counts_value is Array or not labels_value is Array:
        return false
    if Array(counts_value).size() != CELL_COUNT or Array(labels_value).size() != CELL_COUNT:
        return false
    var next_counts: Array[int] = []
    var next_labels: Array[String] = []
    next_counts.resize(CELL_COUNT)
    next_labels.resize(CELL_COUNT)
    for index in CELL_COUNT:
        var count := int(Array(counts_value)[index])
        if count < 0:
            return false
        next_counts[index] = count
        next_labels[index] = String(Array(labels_value)[index])
    population_counts = next_counts
    historical_biome_labels = next_labels
    history_mode = true
    queue_redraw()
    return true

func clear_history_frame() -> void:
    historical_biome_labels.clear()
    history_mode = false
    queue_redraw()

func set_camera_state(zoom_value: float, pan_value: Vector2) -> bool:
    if not is_finite(zoom_value) or zoom_value < MIN_ZOOM or zoom_value > MAX_ZOOM:
        return false
    if not is_finite(pan_value.x) or not is_finite(pan_value.y):
        return false
    camera_zoom = zoom_value
    camera_pan = pan_value
    queue_redraw()
    return true

func set_lod_mode(value: String) -> bool:
    if not value in LOD_VALUES:
        return false
    lod_mode = value
    queue_redraw()
    return true

func set_show_contours(value: bool) -> void:
    show_contours = value
    queue_redraw()

func set_show_biome_boundaries(value: bool) -> void:
    show_biome_boundaries = value
    queue_redraw()

func effective_lod() -> String:
    if lod_mode != LOD_AUTO:
        return lod_mode
    if camera_zoom < 0.82:
        return LOD_REGION
    if camera_zoom < 2.0:
        return LOD_PATCH
    return LOD_PLANT

func get_render_contract() -> Dictionary:
    return {
        "terrain": true,
        "hillshade": true,
        "contours": true,
        "biome_boundaries": true,
        "region_lod": true,
        "patch_lod": true,
        "plant_lod": true,
        "history_summary": true,
        "presentation_only": true,
    }

func get_terrain_summary() -> Dictionary:
    if patch.is_empty():
        return {}
    return {
        "grid_size": int(patch.get("grid_size", 0)),
        "cell_count": Array(patch.get("cells", [])).size(),
        "cell_size_m": float(patch.get("cell_size_m", 0.0)),
        "patch_width_m": float(patch.get("patch_width_m", 0.0)),
        "min_elevation_m": elevation_range.x,
        "max_elevation_m": elevation_range.y,
        "elevation_span_m": maxf(0.0, elevation_range.y - elevation_range.x),
        "effective_lod": effective_lod(),
        "history_mode": history_mode,
    }

func _draw() -> void:
    if patch.is_empty() or population_counts.size() != CELL_COUNT:
        return
    var cells: Array = patch.get("cells", [])
    if cells.size() != CELL_COUNT:
        return
    var cell_px := BASE_CELL_PX * camera_zoom
    var origin := _grid_origin()
    var lod := effective_lod()
    var stride := 4 if lod == LOD_REGION else 1

    # Transparent topographic shading over the accepted VIS1 scalar/biome canvas.
    for y in range(0, GRID_SIZE, stride):
        for x in range(0, GRID_SIZE, stride):
            var index := y * GRID_SIZE + x
            var rect := Rect2(origin + Vector2(x * cell_px, y * cell_px), Vector2(cell_px * stride, cell_px * stride))
            if rect.end.x < 0.0 or rect.end.y < 0.0 or rect.position.x > size.x or rect.position.y > size.y:
                continue
            var terrain := _terrain_color(Dictionary(cells[index]))
            draw_rect(rect.grow(-0.35), terrain, true)
            var biome_label := _block_biome_label(x, y, stride) if lod == LOD_REGION else _biome_label(index)
            if not biome_label.is_empty():
                var biome := _biome_color(biome_label)
                biome.a = 0.08 if lod != LOD_REGION else 0.20
                draw_rect(rect.grow(-0.8), biome, true)
            if lod == LOD_REGION:
                var count := _block_population(x, y, stride)
                if count > 0:
                    var radius := clampf(2.0 + sqrt(float(count)) * 0.7, 2.5, cell_px * stride * 0.28)
                    draw_circle(rect.get_center(), radius, Color(0.32, 0.92, 0.42, 0.70))

    if show_contours and lod != LOD_REGION:
        _draw_contours(cells, origin, cell_px, lod)
    if show_biome_boundaries:
        _draw_biome_boundaries(origin, cell_px, stride)

func _draw_contours(cells: Array, origin: Vector2, cell_px: float, lod: String) -> void:
    var span := maxf(elevation_range.y - elevation_range.x, 0.000001)
    var bands := 7.0 if lod == LOD_PATCH else 12.0
    for y in GRID_SIZE:
        for x in GRID_SIZE:
            var index := y * GRID_SIZE + x
            var band := int(floor((float(Dictionary(cells[index]).get("elevation_m", 0.0)) - elevation_range.x) / span * bands))
            var line_color := Color(0.96, 0.93, 0.80, 0.17 if lod == LOD_PATCH else 0.25)
            if x + 1 < GRID_SIZE:
                var right_band := int(floor((float(Dictionary(cells[index + 1]).get("elevation_m", 0.0)) - elevation_range.x) / span * bands))
                if band != right_band:
                    var px := origin + Vector2((x + 1) * cell_px, y * cell_px)
                    draw_line(px, px + Vector2(0.0, cell_px), line_color, maxf(1.0, camera_zoom * 0.55), true)
            if y + 1 < GRID_SIZE:
                var down_band := int(floor((float(Dictionary(cells[index + GRID_SIZE]).get("elevation_m", 0.0)) - elevation_range.x) / span * bands))
                if band != down_band:
                    var py := origin + Vector2(x * cell_px, (y + 1) * cell_px)
                    draw_line(py, py + Vector2(cell_px, 0.0), line_color, maxf(1.0, camera_zoom * 0.55), true)

func _draw_biome_boundaries(origin: Vector2, cell_px: float, stride: int) -> void:
    if stride > 1:
        # Region mode intentionally favors large connected biome shapes over cell noise.
        for y in range(0, GRID_SIZE, stride):
            for x in range(0, GRID_SIZE, stride):
                var label := _block_biome_label(x, y, stride)
                if x + stride < GRID_SIZE:
                    var right := _block_biome_label(x + stride, y, stride)
                    if not label.is_empty() and not right.is_empty() and label != right:
                        var p := origin + Vector2((x + stride) * cell_px, y * cell_px)
                        draw_line(p, p + Vector2(0.0, cell_px * stride), Color(1.0, 0.96, 0.72, 0.70), maxf(1.5, camera_zoom), true)
                if y + stride < GRID_SIZE:
                    var down := _block_biome_label(x, y + stride, stride)
                    if not label.is_empty() and not down.is_empty() and label != down:
                        var q := origin + Vector2(x * cell_px, (y + stride) * cell_px)
                        draw_line(q, q + Vector2(cell_px * stride, 0.0), Color(1.0, 0.96, 0.72, 0.70), maxf(1.5, camera_zoom), true)
        return
    for y in GRID_SIZE:
        for x in GRID_SIZE:
            var index := y * GRID_SIZE + x
            var label := _biome_label(index)
            if label.is_empty():
                continue
            var line_color := Color(1.0, 0.93, 0.62, 0.46)
            if x + 1 < GRID_SIZE and _biome_label(index + 1) != label:
                var px := origin + Vector2((x + 1) * cell_px, y * cell_px)
                draw_line(px, px + Vector2(0.0, cell_px), line_color, maxf(1.0, camera_zoom * 0.65), true)
            if y + 1 < GRID_SIZE and _biome_label(index + GRID_SIZE) != label:
                var py := origin + Vector2(x * cell_px, (y + 1) * cell_px)
                draw_line(py, py + Vector2(cell_px, 0.0), line_color, maxf(1.0, camera_zoom * 0.65), true)

func _terrain_color(cell: Dictionary) -> Color:
    var span := maxf(elevation_range.y - elevation_range.x, 0.000001)
    var height_t := clampf((float(cell.get("elevation_m", 0.0)) - elevation_range.x) / span, 0.0, 1.0)
    var slope := clampf(float(cell.get("slope_ratio", 0.0)) * 7.0, 0.0, 1.0)
    var aspect_light := clampf(0.5 + 0.32 * float(cell.get("aspect_east", 0.0)) - 0.22 * float(cell.get("aspect_north", 0.0)), 0.15, 0.95)
    var luminance := clampf(0.20 + 0.42 * height_t + 0.22 * aspect_light - 0.18 * slope, 0.08, 0.78)
    return Color(luminance * 0.88, luminance * 0.82, luminance * 0.68, 0.32)

func _biome_label(index: int) -> String:
    if history_mode and historical_biome_labels.size() == CELL_COUNT:
        return historical_biome_labels[index]
    var cells: Array = classification.get("cells", [])
    if cells.size() != CELL_COUNT:
        return ""
    return String(Dictionary(cells[index]).get("label", ""))

func _biome_color(label: String) -> Color:
    match label:
        "desert-like": return Color(0.86, 0.68, 0.24, 1.0)
        "wetland-like": return Color(0.10, 0.68, 0.78, 1.0)
        "forest-like": return Color(0.10, 0.58, 0.22, 1.0)
        "grass/shrub-like": return Color(0.52, 0.76, 0.22, 1.0)
        "alpine-like": return Color(0.82, 0.86, 0.92, 1.0)
        "ecotone": return Color(0.84, 0.40, 0.82, 1.0)
    return Color(0.25, 0.25, 0.25, 1.0)

func _block_biome_label(start_x: int, start_y: int, stride: int) -> String:
    var counts := {}
    for y in range(start_y, mini(start_y + stride, GRID_SIZE)):
        for x in range(start_x, mini(start_x + stride, GRID_SIZE)):
            var label := _biome_label(y * GRID_SIZE + x)
            if not label.is_empty():
                counts[label] = int(counts.get(label, 0)) + 1
    var best := ""
    var best_count := -1
    var labels := counts.keys(); labels.sort()
    for value in labels:
        var label := String(value)
        var count := int(counts[label])
        if count > best_count:
            best = label
            best_count = count
    return best

func _block_population(start_x: int, start_y: int, stride: int) -> int:
    var total := 0
    for y in range(start_y, mini(start_y + stride, GRID_SIZE)):
        for x in range(start_x, mini(start_x + stride, GRID_SIZE)):
            total += population_counts[y * GRID_SIZE + x]
    return total

func _validate_patch(value: Dictionary) -> bool:
    return int(value.get("grid_size", 0)) == GRID_SIZE and Array(value.get("cells", [])).size() == CELL_COUNT and String(value.get("patch_hash", "")).length() == 64

func _compute_elevation_range() -> Vector2:
    var lo := INF
    var hi := -INF
    for value in Array(patch.get("cells", [])):
        if value is Dictionary:
            var elevation := float(Dictionary(value).get("elevation_m", 0.0))
            lo = minf(lo, elevation)
            hi = maxf(hi, elevation)
    if not is_finite(lo) or not is_finite(hi):
        return Vector2.ZERO
    return Vector2(lo, hi)

func _grid_origin() -> Vector2:
    var extent := Vector2(GRID_SIZE * BASE_CELL_PX * camera_zoom, GRID_SIZE * BASE_CELL_PX * camera_zoom)
    return (size - extent) * 0.5 + camera_pan
