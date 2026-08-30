extends Control

## ECO.EVO7 VIS4.2 — pure diagnostic morphology renderer.
##
## Consumes only VIS4.2 diagnostic descriptors. All geometry mappings below are
## presentation-only and deterministic. No biology implementation is imported.

const GRID_SIZE := 32
const CELL_COUNT := GRID_SIZE * GRID_SIZE
const BASE_CELL_PX := 22.0
const MIN_ZOOM := 0.55
const MAX_ZOOM := 4.0

var descriptors: Array[Dictionary] = []
var camera_zoom := 1.0
var camera_pan := Vector2.ZERO
var neutral_color := true
var selected_record_id := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

func set_descriptors(values: Array) -> bool:
	var ordered: Array[Dictionary] = []
	for value in values:
		if not value is Dictionary:
			return false
		var descriptor: Dictionary = value
		if int(descriptor.get("cell_index", -1)) < 0 or int(descriptor.get("cell_index", -1)) >= CELL_COUNT:
			return false
		if String(descriptor.get("record_id", "")).is_empty() or String(descriptor.get("silhouette_hash", "")).length() != 64:
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

func set_neutral_color(value: bool) -> void:
	neutral_color = value
	queue_redraw()

func set_selected_record(record_id: String) -> bool:
	if record_id.is_empty():
		selected_record_id = ""
		queue_redraw()
		return true
	for descriptor in descriptors:
		if String(descriptor.get("record_id", "")) == record_id:
			selected_record_id = record_id
			queue_redraw()
			return true
	return false

func get_render_contract() -> Dictionary:
	return {
		"descriptor_v2_only": true,
		"realized_height": true,
		"realized_crown_radius": true,
		"realized_crown_density": true,
		"branch_silhouette": true,
		"structural_cue": true,
		"leaf_strategy_cue": true,
		"neutral_color": true,
		"presentation_only": true,
		"diagnostic_only": true,
		"seed_shape_jitter": false,
	}

func stem_height_px(descriptor: Dictionary, cell_px: float) -> float:
	var height_m := maxf(float(descriptor.get("realized_height_m", 0.0)), 0.0)
	var normalized := clampf(height_m / 12.0, 0.0, 1.0)
	return clampf(cell_px * (0.30 + 0.62 * sqrt(normalized)), 5.0, cell_px * 0.95)

func crown_radius_px(descriptor: Dictionary, cell_px: float) -> float:
	# Honest VIS4.2 mapping: crown size comes from realized_crown_radius_m,
	# never from LAI or a renderer-side phenotype approximation.
	var radius_m := maxf(float(descriptor.get("realized_crown_radius_m", 0.0)), 0.0)
	var normalized := clampf(radius_m / 6.0, 0.0, 1.0)
	return clampf(cell_px * (0.10 + 0.32 * sqrt(normalized)), 2.0, cell_px * 0.42)

func crown_alpha(descriptor: Dictionary) -> float:
	var density := clampf(float(descriptor.get("realized_crown_density", 0.0)), 0.0, 1.0)
	return 0.24 + density * 0.68

func foliage_cluster_count(descriptor: Dictionary) -> int:
	var density := clampf(float(descriptor.get("realized_crown_density", 0.0)), 0.0, 1.0)
	return clampi(2 + int(round(density * 7.0)), 2, 9)

func leaf_cluster_radius_px(descriptor: Dictionary, crown_px: float) -> float:
	var conservative := clampf(float(descriptor.get("leaf_conservative_strategy", 0.0)), 0.0, 1.0)
	return crown_px * lerpf(0.30, 0.17, conservative)

func stem_width_px(descriptor: Dictionary, cell_px: float) -> float:
	var structural := clampf(float(descriptor.get("structural_investment", 0.0)), 0.0, 1.0)
	return clampf(cell_px * (0.035 + 0.055 * structural), 1.2, cell_px * 0.10)

func branch_count(descriptor: Dictionary) -> int:
	var probability := clampf(float(descriptor.get("branch_probability", 0.0)), 0.0, 1.0)
	var depth := maxi(int(descriptor.get("branching_depth", 0)), 0)
	return clampi(int(round(probability * float(depth) * 4.0)), 0, 18)

func branch_lateral_reach_px(descriptor: Dictionary, crown_px: float) -> float:
	var angle := deg_to_rad(clampf(float(descriptor.get("branch_angle_deg", 0.0)), 0.0, 180.0))
	var ratio := maxf(float(descriptor.get("branch_length_ratio", 0.0)), 0.0)
	return absf(sin(angle)) * crown_px * clampf(0.45 + 0.80 * ratio, 0.25, 1.35)

func crown_vertical_scale(descriptor: Dictionary) -> float:
	var apical := clampf(float(descriptor.get("apical_dominance", 0.0)), 0.0, 1.0)
	return lerpf(0.82, 1.38, apical)

func foliage_color(descriptor: Dictionary) -> Color:
	if neutral_color:
		return Color(0.33, 0.68, 0.30, crown_alpha(descriptor))
	var lineage_id := String(descriptor.get("lineage_id", ""))
	var token := lineage_id.sha256_text().substr(0, 8)
	var hue := float(token.hex_to_int()) / 4294967295.0
	return Color.from_hsv(hue, 0.58, 0.78, crown_alpha(descriptor))

func stem_color(descriptor: Dictionary) -> Color:
	if neutral_color:
		return Color(0.32, 0.22, 0.12, 0.96)
	var foliage := foliage_color(descriptor)
	return Color(foliage.r * 0.44, foliage.g * 0.34, foliage.b * 0.22, 0.96)

func shape_signature(descriptor: Dictionary) -> String:
	return String(descriptor.get("silhouette_hash", ""))

func branch_segments(descriptor: Dictionary, cell_px: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var count := branch_count(descriptor)
	if count <= 0:
		return out
	var height := stem_height_px(descriptor, cell_px)
	var crown := crown_radius_px(descriptor, cell_px)
	var reach := branch_lateral_reach_px(descriptor, crown)
	var angle := deg_to_rad(clampf(float(descriptor.get("branch_angle_deg", 0.0)), 0.0, 180.0))
	var ratio := clampf(float(descriptor.get("branch_length_ratio", 0.0)), 0.0, 1.5)
	var apical := clampf(float(descriptor.get("apical_dominance", 0.0)), 0.0, 1.0)
	var width := stem_width_px(descriptor, cell_px) * 0.62
	for i in count:
		var fraction := (float(i) + 1.0) / (float(count) + 1.0)
		var side := -1.0 if i % 2 == 0 else 1.0
		var origin_y := -height * lerpf(0.30, 0.82, fraction)
		var vertical_bias := cos(angle) * crown * (0.18 + 0.22 * ratio)
		var apical_bias := -height * 0.08 * apical * (1.0 - fraction)
		var start := Vector2(0.0, origin_y)
		var finish := start + Vector2(side * reach * (0.70 + 0.30 * (1.0 - fraction)), vertical_bias + apical_bias)
		out.append({"from": start, "to": finish, "width": maxf(1.0, width * (1.0 - 0.35 * fraction))})
	return out

func _draw() -> void:
	if descriptors.is_empty():
		return
	var cell_px := BASE_CELL_PX * camera_zoom
	var origin := _grid_origin()
	for descriptor in descriptors:
		var cell_index := int(descriptor.get("cell_index", -1))
		var center := origin + Vector2((cell_index % GRID_SIZE + 0.5) * cell_px, (cell_index / GRID_SIZE + 0.5) * cell_px)
		if center.x < -cell_px or center.y < -cell_px or center.x > size.x + cell_px or center.y > size.y + cell_px:
			continue
		_draw_plant(descriptor, center, cell_px)

func _draw_plant(descriptor: Dictionary, center: Vector2, cell_px: float) -> void:
	var height := stem_height_px(descriptor, cell_px)
	var crown := crown_radius_px(descriptor, cell_px)
	var ground := center + Vector2(0.0, cell_px * 0.30)
	var top := ground - Vector2(0.0, height)
	var stem_w := stem_width_px(descriptor, cell_px)
	var stem_c := stem_color(descriptor)
	var foliage_c := foliage_color(descriptor)
	var vertical_scale := crown_vertical_scale(descriptor)

	draw_line(ground, top, stem_c, stem_w, true)

	for segment in branch_segments(descriptor, cell_px):
		var start: Vector2 = ground + Vector2(segment["from"])
		var finish: Vector2 = ground + Vector2(segment["to"])
		draw_line(start, finish, stem_c, float(segment["width"]), true)

	var clusters := foliage_cluster_count(descriptor)
	var leaf_radius := leaf_cluster_radius_px(descriptor, crown)
	for i in clusters:
		var fraction := (float(i) + 0.5) / float(clusters)
		var phase := fraction * TAU
		var horizontal := cos(phase) * crown * (0.30 + 0.62 * fraction)
		var vertical := sin(phase) * crown * vertical_scale * 0.70
		var cluster_center := top + Vector2(horizontal, vertical + crown * 0.26)
		draw_circle(cluster_center, maxf(1.2, leaf_radius * (0.82 + 0.18 * fraction)), foliage_c)
	draw_circle(top + Vector2(0.0, crown * 0.18), maxf(1.5, crown * 0.48), foliage_c)

	if selected_record_id == String(descriptor.get("record_id", "")):
		draw_arc(top + Vector2(0.0, crown * 0.20), maxf(crown * 1.35, 4.0), 0.0, TAU, 24, Color(1.0, 0.86, 0.24, 0.92), 1.4, true)

func _grid_origin() -> Vector2:
	var extent := Vector2(GRID_SIZE * BASE_CELL_PX * camera_zoom, GRID_SIZE * BASE_CELL_PX * camera_zoom)
	return (size - extent) * 0.5 + camera_pan
