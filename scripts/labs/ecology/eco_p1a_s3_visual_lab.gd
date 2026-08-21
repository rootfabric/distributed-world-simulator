extends Control

const Dataset = preload("res://scripts/research/ecology/eco_p1a_s3_lab_dataset_v1.gd")
const Probes = preload("res://scripts/research/ecology/controlled_trait_probes_v1.gd")
const Fixture = preload("res://scripts/research/ecology/synthetic_environment_fixture_v1.gd")

const LAB_GRID_SIZE := 33
const MAP_MARGIN := 18.0
const TOP_CONTENT_Y := 64.0

@onready var status_panel: PanelContainer = $StatusPanel
@onready var status_label: Label = $StatusPanel/Margin/Scroll/Status
@onready var help_label: Label = $HelpPanel/Margin/Help

var current_view_index := 0
var current_probe_index := 0
var current_dataset: Dictionary = {}
var base_dataset: Dictionary = {}
var selected_ix := -1
var selected_iz := -1
var selected_record: Dictionary = {}
var map_rect := Rect2()


func _ready() -> void:
	set_process_unhandled_input(true)
	base_dataset = Dataset.build(Probes.BASE, LAB_GRID_SIZE)
	_rebuild_dataset()
	if current_dataset.is_empty() or base_dataset.is_empty():
		push_error("ECO.P1A-S3 Visual Lab failed to build dataset")
		if DisplayServer.get_name() == "headless":
			get_tree().quit(1)
		return
	_update_labels()
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
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	if current_dataset.is_empty():
		return
	var panel_left := _panel_left()
	var available_width := maxf(panel_left - MAP_MARGIN * 2.0, 100.0)
	var available_height := maxf(size.y - TOP_CONTENT_Y - MAP_MARGIN * 2.0, 100.0)
	var map_size := minf(available_width, available_height)
	map_rect = Rect2(Vector2(MAP_MARGIN, TOP_CONTENT_Y + MAP_MARGIN), Vector2(map_size, map_size))
	draw_rect(map_rect.grow(4.0), Color(0.02, 0.025, 0.035, 1.0), true)
	draw_rect(map_rect.grow(4.0), Color(0.32, 0.35, 0.42, 1.0), false, 1.0)
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
	if _current_probe_id() == Probes.BASE and not base_dataset.is_empty():
		current_dataset = base_dataset
	else:
		current_dataset = Dataset.build(_current_probe_id(), LAB_GRID_SIZE)
	if selected_ix >= 0 and selected_iz >= 0 and not current_dataset.is_empty():
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
	var text := "ECO.P1A-S3 — Diagnostic Visual Lab\n"
	text += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
	text += "VIEW %d/8  %s\n" % [current_view_index + 1, view_id]
	text += "%s\n" % _view_explanation(view_id)
	text += "%s\n" % _view_legend(view_id)
	text += "\nPROBE %d/%d  %s\n" % [current_probe_index + 1, Probes.ORDER.size(), _current_probe_id()]
	text += "%s\n" % _probe_trait_summary()
	text += "%s\n" % _probe_trait_delta_summary()
	text += "\nGLOBAL OUTCOME  (%d patches, %d seasons)\n" % [Array(current_dataset.get("records", [])).size(), int(current_dataset.get("seasons", 0))]
	text += "%s\n" % _viability_summary()
	text += "%s\n" % _limiting_summary()
	text += "avg net=%+.3f  avg biomass=%.3f kg/m²\n" % [
		_dataset_average(current_dataset, "net_resource_balance"),
		_dataset_average(current_dataset, "final_biomass_kg_m2"),
	]
	text += "PROBE EFFECT VS BASE: %s\n" % _probe_effect_summary()
	text += "\nTRUTH IDS\n"
	text += "environment  %s\n" % _short_hash(String(current_dataset.get("environment_hash", "")))
	text += "dataset      %s\n" % _short_hash(String(current_dataset.get("dataset_hash", "")))
	if not selected_record.is_empty():
		text += _selected_patch_text()
	else:
		text += "\nCLICK A PATCH\nSelect a map cell to see resource responses, limitations, costs, biomass history summary and the local difference from BASE.\n"
	status_label.text = text
	if is_instance_valid(help_label):
		help_label.text = "1-8 view   |   Q/E probe   |   click map: inspect patch   |   R reset   |   presentation only; S1/S2 truth unchanged"


func _selected_patch_text() -> String:
	var text := "\nSELECTED PATCH [%d,%d]  (%.1f, %.1f)m\n" % [selected_ix, selected_iz, float(selected_record["world_x_m"]), float(selected_record["world_z_m"])]
	text += "ENV  T=%.2f°C  soil=%.3f  effective=%.3f\n" % [float(selected_record["temperature_c"]), float(selected_record["soil_moisture"]), float(selected_record["effective_soil_moisture"])]
	text += "     light=%.3f  nutrient=%.3f  flood=%.3f\n" % [float(selected_record["sunlight"]), float(selected_record["nutrients"]), float(selected_record["flood_frequency"])]
	text += "RESP light=%.3f  water=%.3f  nutrient=%.3f  temp=%.3f\n" % [
		float(selected_record["light_response"]), float(selected_record["water_response"]),
		float(selected_record["nutrient_response"]), float(selected_record["temperature_response"]),
	]
	text += "LIMIT L=%.3f  W=%.3f  N=%.3f  T=%.3f  F=%.3f\n" % [
		float(selected_record["light_limitation"]), float(selected_record["water_limitation"]),
		float(selected_record["nutrient_limitation"]), float(selected_record["temperature_limitation"]), float(selected_record["flood_limitation"]),
	]
	var regular_cost := _regular_cost(selected_record)
	var stress_cost := float(selected_record["water_stress_penalty"]) + float(selected_record["flood_penalty"])
	var total_cost := regular_cost + stress_cost
	text += "ENERGY gross=%.3f  regular costs=%.3f  stress=%.3f\n" % [float(selected_record["gross_photosynthetic_income"]), regular_cost, stress_cost]
	text += "       gross - total(%.3f) = net %+.3f\n" % [total_cost, float(selected_record["net_resource_balance"])]
	text += "BIO  final=%.3f  peak=%.3f kg/m²  productive=%d  stress=%d\n" % [
		float(selected_record["final_biomass_kg_m2"]), float(selected_record["peak_biomass_kg_m2"]),
		int(selected_record["productive_seasons"]), int(selected_record["stress_seasons"]),
	]
	text += "RESULT  %s  |  primary limit=%s\n" % [String(selected_record["viability_class"]), String(selected_record["dominant_limiting_factor"])]
	text += "WHY  %s\n" % _selected_explanation(selected_record)
	var base_record := Dataset.sample_world(
		float(selected_record["world_x_m"]),
		float(selected_record["world_z_m"]),
		Probes.BASE,
		int(current_dataset.get("seasons", 24)),
		int(current_dataset.get("seed", Fixture.DEFAULT_SEED))
	)
	if _current_probe_id() == Probes.BASE:
		text += "LOCAL VS BASE  this is the BASE reference.\n"
	elif not base_record.is_empty():
		text += "LOCAL VS BASE  Δnet=%+.3f  Δbiomass=%+.3f  BASE=%s/%s\n" % [
			float(selected_record["net_resource_balance"]) - float(base_record["net_resource_balance"]),
			float(selected_record["final_biomass_kg_m2"]) - float(base_record["final_biomass_kg_m2"]),
			String(base_record["viability_class"]), String(base_record["dominant_limiting_factor"]),
		]
	return text


func _regular_cost(record_value: Dictionary) -> float:
	return (
		float(record_value["maintenance_cost"])
		+ float(record_value["root_cost"])
		+ float(record_value["structural_cost"])
		+ float(record_value["growth_allocation_cost"])
		+ float(record_value["reproduction_allocation_cost"])
		+ float(record_value["density_cost"])
	)


func _selected_explanation(record_value: Dictionary) -> String:
	var viability := String(record_value["viability_class"])
	var limiting := String(record_value["dominant_limiting_factor"])
	var net := float(record_value["net_resource_balance"])
	if viability == "FAVOURABLE":
		return "Income exceeds costs by %.3f; %s is still the strongest remaining constraint." % [net, limiting]
	if viability == "MARGINAL":
		return "Income barely covers costs (net %.3f); %s prevents a comfortable surplus." % [net, limiting]
	return "Costs/stress exceed income by %.3f; %s is the strongest local constraint." % [-net, limiting]


func _probe_trait_summary() -> String:
	var genome := Probes.genome(_current_probe_id())
	return "traits: h=%.2fm root=%.2fm growth=%.2f water=%.2f±%.2f shade=%.2f" % [
		float(genome["height_m"]), float(genome["root_depth_m"]), float(genome["growth_rate"]),
		float(genome["water_preference"]), float(genome["water_tolerance_width"]), float(genome["shade_tolerance"]),
	]


func _probe_trait_delta_summary() -> String:
	var genome := Probes.genome(_current_probe_id())
	var base := Probes.genome(Probes.BASE)
	return "vs BASE: Δroot=%+.2fm  Δwater=%+.2f  Δtol=%+.2f  Δshade=%+.2f" % [
		float(genome["root_depth_m"]) - float(base["root_depth_m"]),
		float(genome["water_preference"]) - float(base["water_preference"]),
		float(genome["water_tolerance_width"]) - float(base["water_tolerance_width"]),
		float(genome["shade_tolerance"]) - float(base["shade_tolerance"]),
	]


func _probe_effect_summary() -> String:
	if base_dataset.is_empty():
		return "BASE dataset unavailable"
	var current_counts: Dictionary = current_dataset.get("viability_counts", {})
	var base_counts: Dictionary = base_dataset.get("viability_counts", {})
	var delta_fav := int(current_counts.get("FAVOURABLE", 0)) - int(base_counts.get("FAVOURABLE", 0))
	var delta_net := _dataset_average(current_dataset, "net_resource_balance") - _dataset_average(base_dataset, "net_resource_balance")
	var delta_biomass := _dataset_average(current_dataset, "final_biomass_kg_m2") - _dataset_average(base_dataset, "final_biomass_kg_m2")
	return "Δfavourable=%+d  Δavg net=%+.3f  Δavg biomass=%+.3f" % [delta_fav, delta_net, delta_biomass]


func _dataset_average(dataset: Dictionary, field_name: String) -> float:
	var records: Array = dataset.get("records", [])
	if records.is_empty():
		return 0.0
	var total := 0.0
	for value in records:
		total += float(Dictionary(value).get(field_name, 0.0))
	return total / float(records.size())


func _viability_summary() -> String:
	var counts: Dictionary = current_dataset.get("viability_counts", {})
	var total: int = maxi(1, Array(current_dataset.get("records", [])).size())
	return "viability: F=%d (%.1f%%)  M=%d (%.1f%%)  U=%d (%.1f%%)" % [
		int(counts.get("FAVOURABLE", 0)), 100.0 * float(counts.get("FAVOURABLE", 0)) / float(total),
		int(counts.get("MARGINAL", 0)), 100.0 * float(counts.get("MARGINAL", 0)) / float(total),
		int(counts.get("UNSUSTAINABLE", 0)), 100.0 * float(counts.get("UNSUSTAINABLE", 0)) / float(total),
	]


func _limiting_summary() -> String:
	var counts: Dictionary = current_dataset.get("limiting_counts", {})
	return "limits: LIGHT=%d  WATER=%d  NUTRIENT=%d  TEMP=%d  FLOOD=%d" % [
		int(counts.get("LIGHT", 0)), int(counts.get("WATER", 0)), int(counts.get("NUTRIENT", 0)),
		int(counts.get("TEMPERATURE", 0)), int(counts.get("FLOOD", 0)),
	]


func _view_explanation(view_id: String) -> String:
	match view_id:
		Dataset.VIEW_TEMPERATURE: return "Accepted S1 ambient temperature field; probe-independent."
		Dataset.VIEW_SOIL_MOISTURE: return "Accepted S1 surface soil moisture; deeper roots may derive extra effective moisture."
		Dataset.VIEW_SUNLIGHT: return "Accepted S1 sunlight field; shade tolerance changes biological response, not this field."
		Dataset.VIEW_NUTRIENTS: return "Accepted S1 nutrient availability field."
		Dataset.VIEW_FLOOD: return "Accepted S1 flood-frequency field; high moisture can become harmful through flood stress."
		Dataset.VIEW_BIOMASS: return "Derived S2 biomass after 24 seasons; combines resources, costs and stress."
		Dataset.VIEW_NET_BALANCE: return "Derived S2 initial resource surplus: photosynthetic income minus all costs/stress."
		Dataset.VIEW_LIMITING_FACTOR: return "Derived S2 strongest local constraint among light/water/nutrient/temperature/flood."
	return ""


func _view_legend(view_id: String) -> String:
	if view_id == Dataset.VIEW_LIMITING_FACTOR:
		return "legend: LIGHT=yellow  WATER=blue  NUTRIENT=green  TEMP=red  FLOOD=cyan"
	var ranges: Dictionary = current_dataset.get("ranges", {})
	var value_range: Dictionary = ranges.get(view_id, {})
	var range_text := "%.3f .. %.3f" % [float(value_range.get("min", 0.0)), float(value_range.get("max", 0.0))]
	if view_id == Dataset.VIEW_NET_BALANCE:
		return "range %s  |  red=negative, green=positive" % range_text
	if view_id == Dataset.VIEW_BIOMASS:
		return "range %s kg/m²  |  dark=low, bright green=high" % range_text
	return "range %s  |  blue=low, orange=high" % range_text


func _short_hash(value: String) -> String:
	if value.length() <= 24:
		return value
	return "%s...%s" % [value.substr(0, 12), value.substr(value.length() - 8, 8)]


func _panel_left() -> float:
	if is_instance_valid(status_panel):
		return status_panel.position.x
	return size.x - 476.0


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
	if not status_label.text.contains("PROBE EFFECT VS BASE"):
		return {"success": false, "error_code": "ECO_P1A_S3_EXPLANATION_PANEL_MISSING"}
	if not status_label.text.contains("CLICK A PATCH"):
		return {"success": false, "error_code": "ECO_P1A_S3_PATCH_GUIDANCE_MISSING"}
	return {"success": true, "error_code": ""}
