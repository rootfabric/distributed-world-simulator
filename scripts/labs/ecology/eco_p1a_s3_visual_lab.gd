extends Control

const Dataset = preload("res://scripts/research/ecology/eco_p1a_s3_lab_dataset_v1.gd")
const Probes = preload("res://scripts/research/ecology/controlled_trait_probes_v1.gd")
const Fixture = preload("res://scripts/research/ecology/synthetic_environment_fixture_v1.gd")

const LAB_GRID_SIZE := 33
const MAP_MARGIN := 18.0
const HUD_WIDTH := 430.0

@onready var status_label: Label = $Status
@onready var help_label: Label = $Help

var current_view_index := 0
var current_probe_index := 0
var current_dataset: Dictionary = {}
var selected_ix := -1
var selected_iz := -1
var selected_record: Dictionary = {}
var map_rect := Rect2()


func _ready() -> void:
	set_process_unhandled_input(true)
	_rebuild_dataset()
	if current_dataset.is_empty():
		push_error("ECO.P1A-S3 Visual Lab failed to build dataset")
		if DisplayServer.get_name() == "headless":
			get_tree().quit(1)
		return
	if DisplayServer.get_name() == "headless":
		var smoke := _headless_smoke()
		if not bool(smoke.get("success", false)):
			push_error("ECO.P1A-S3 headless smoke failed: %s" % str(smoke))
			get_tree().quit(1)
			return
		print("ECO.P1A-S3 Visual Lab: PASS (grid=%dx%d probe=%s dataset_hash=%s)" % [
			LAB_GRID_SIZE,
			LAB_GRID_SIZE,
			_current_probe_id(),
			String(current_dataset["dataset_hash"]),
		])
		get_tree().quit(0)
		return
	_update_labels()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	if current_dataset.is_empty():
		return
	var available_width := maxf(size.x - HUD_WIDTH - MAP_MARGIN * 3.0, 100.0)
	var available_height := maxf(size.y - 90.0 - MAP_MARGIN * 2.0, 100.0)
	var map_size := minf(available_width, available_height)
	map_rect = Rect2(Vector2(MAP_MARGIN, 58.0 + MAP_MARGIN), Vector2(map_size, map_size))
	draw_rect(map_rect, Color(0.06, 0.07, 0.09, 1.0), true)
	var grid_size := int(current_dataset["grid_size"])
	var cell := map_size / float(grid_size)
	var view_id := _current_view_id()
	for iz in range(grid_size):
		for ix in range(grid_size):
			var value := Dataset.record(current_dataset, ix, iz)
			var rect := Rect2(map_rect.position + Vector2(float(ix) * cell, float(iz) * cell), Vector2(cell + 0.5, cell + 0.5))
			draw_rect(rect, _record_color(value, view_id), true)
	if selected_ix >= 0 and selected_iz >= 0:
		var selected_rect := Rect2(map_rect.position + Vector2(float(selected_ix) * cell, float(selected_iz) * cell), Vector2(cell, cell))
		draw_rect(selected_rect.grow(2.0), Color.WHITE, false, 2.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_at(event.position)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8:
			current_view_index = int(event.keycode - KEY_1)
			_update_labels()
			queue_redraw()
		KEY_Q:
			current_probe_index = posmod(current_probe_index - 1, Probes.ORDER.size())
			_rebuild_dataset()
		KEY_E:
			current_probe_index = posmod(current_probe_index + 1, Probes.ORDER.size())
			_rebuild_dataset()
		KEY_R:
			current_view_index = 0
			current_probe_index = 0
			selected_ix = -1
			selected_iz = -1
			selected_record = {}
			_rebuild_dataset()


func _rebuild_dataset() -> void:
	current_dataset = Dataset.build(_current_probe_id(), LAB_GRID_SIZE)
	if selected_ix >= 0 and selected_iz >= 0:
		selected_record = Dataset.record(current_dataset, selected_ix, selected_iz)
	_update_labels()
	queue_redraw()


func _select_at(position: Vector2) -> void:
	if not map_rect.has_point(position) or current_dataset.is_empty():
		return
	var grid_size := int(current_dataset["grid_size"])
	var relative := position - map_rect.position
	selected_ix = clampi(int(floor(relative.x / map_rect.size.x * float(grid_size))), 0, grid_size - 1)
	selected_iz = clampi(int(floor(relative.y / map_rect.size.y * float(grid_size))), 0, grid_size - 1)
	selected_record = Dataset.record(current_dataset, selected_ix, selected_iz)
	_update_labels()
	queue_redraw()


func _record_color(record_value: Dictionary, view_id: String) -> Color:
	if view_id == Dataset.VIEW_LIMITING_FACTOR:
		match String(record_value.get("dominant_limiting_factor", "")):
			"LIGHT": return Color(0.92, 0.78, 0.25)
			"WATER": return Color(0.18, 0.46, 0.92)
			"NUTRIENT": return Color(0.38, 0.72, 0.28)
			"TEMPERATURE": return Color(0.86, 0.31, 0.24)
			"FLOOD": return Color(0.25, 0.80, 0.90)
		return Color(0.2, 0.2, 0.2)
	var t := Dataset.normalized_value(current_dataset, record_value, view_id)
	if view_id == Dataset.VIEW_NET_BALANCE:
		if float(record_value.get(view_id, 0.0)) < 0.0:
			return Color(0.50 + 0.35 * t, 0.10 + 0.18 * t, 0.12 + 0.12 * t)
		return Color(0.12 + 0.18 * t, 0.32 + 0.55 * t, 0.18 + 0.18 * t)
	if view_id == Dataset.VIEW_BIOMASS:
		return Color(0.07 + 0.16 * t, 0.12 + 0.76 * t, 0.08 + 0.20 * t)
	return Color(0.08 + 0.82 * t, 0.12 + 0.46 * t, 0.72 - 0.58 * t)


func _update_labels() -> void:
	if not is_instance_valid(status_label) or current_dataset.is_empty():
		return
	var view_id := _current_view_id()
	var ranges: Dictionary = current_dataset.get("ranges", {})
	var range_text := "categorical"
	if ranges.has(view_id):
		var value_range: Dictionary = ranges[view_id]
		range_text = "%.3f .. %.3f" % [float(value_range["min"]), float(value_range["max"])]
	var text := "ECO.P1A-S3 — Diagnostic Visual Lab\n"
	text += "View [%d/8]: %s   range=%s\n" % [current_view_index + 1, view_id, range_text]
	text += "Probe [%d/%d]: %s\n" % [current_probe_index + 1, Probes.ORDER.size(), _current_probe_id()]
	text += "dataset_hash=%s\n" % String(current_dataset.get("dataset_hash", ""))
	text += "env_hash=%s\n" % String(current_dataset.get("environment_hash", ""))
	text += "viability=%s\n" % str(current_dataset.get("viability_counts", {}))
	text += "limits=%s\n" % str(current_dataset.get("limiting_counts", {}))
	if not selected_record.is_empty():
		text += "\nSelected patch [%d,%d] @ (%.1f, %.1f)m\n" % [selected_ix, selected_iz, float(selected_record["world_x_m"]), float(selected_record["world_z_m"])]
		text += "T=%.2fC moisture=%.3f light=%.3f nutrient=%.3f flood=%.3f\n" % [
			float(selected_record["temperature_c"]), float(selected_record["soil_moisture"]), float(selected_record["sunlight"]),
			float(selected_record["nutrients"]), float(selected_record["flood_frequency"]),
		]
		text += "gross=%.3f maintenance=%.3f root=%.3f structural=%.3f\n" % [
			float(selected_record["gross_photosynthetic_income"]), float(selected_record["maintenance_cost"]),
			float(selected_record["root_cost"]), float(selected_record["structural_cost"]),
		]
		text += "growth=%.3f reproduction=%.3f water_stress=%.3f flood_penalty=%.3f\n" % [
			float(selected_record["growth_allocation_cost"]), float(selected_record["reproduction_allocation_cost"]),
			float(selected_record["water_stress_penalty"]), float(selected_record["flood_penalty"]),
		]
		text += "net=%.3f biomass=%.3f limit=%s class=%s\n" % [
			float(selected_record["net_resource_balance"]), float(selected_record["final_biomass_kg_m2"]),
			String(selected_record["dominant_limiting_factor"]), String(selected_record["viability_class"]),
		]
	status_label.text = text
	if is_instance_valid(help_label):
		help_label.text = "1-8: field  |  Q/E: controlled probe  |  click: inspect patch  |  R: reset   (presentation only; S1/S2 truth unchanged)"


func _current_view_id() -> String:
	return Dataset.VIEW_IDS[clampi(current_view_index, 0, Dataset.VIEW_IDS.size() - 1)]


func _current_probe_id() -> String:
	return Probes.ORDER[clampi(current_probe_index, 0, Probes.ORDER.size() - 1)]


func _headless_smoke() -> Dictionary:
	if String(current_dataset.get("environment_hash", "")) != Fixture.environment_hash():
		return {"success": false, "error_code": "ECO_P1A_S3_ENV_HASH_MISMATCH"}
	if Array(current_dataset.get("records", [])).size() != LAB_GRID_SIZE * LAB_GRID_SIZE:
		return {"success": false, "error_code": "ECO_P1A_S3_RECORD_COUNT_MISMATCH"}
	if String(current_dataset.get("dataset_hash", "")).length() != 64:
		return {"success": false, "error_code": "ECO_P1A_S3_INVALID_DATASET_HASH"}
	return {"success": true, "error_code": ""}
