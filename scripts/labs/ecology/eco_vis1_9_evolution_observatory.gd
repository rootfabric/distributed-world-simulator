extends "res://scripts/labs/ecology/eco_vis1_8b_continuous_population_field.gd"

const ObservatoryModel = preload("res://scripts/labs/ecology/eco_vis1_9_observatory_model.gd")
const ObservatoryPanel = preload("res://scripts/labs/ecology/eco_vis1_9_observatory_panel.gd")
const VIS16 = preload("res://scripts/labs/ecology/eco_vis1_6_lineage_genome_bridge.gd")
const DevelopmentContract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const EnvironmentDevelopment = preload("res://scripts/research/ecology/plant_environment_coupled_development_v1.gd")
const RenderDescription = preload("res://scripts/research/ecology/plant_render_description_v1.gd")
const VIS19_Materializer3D = preload("res://scripts/research/ecology/plant_3d_materializer_v1.gd")

const VIS1_9_STAGE := "ECO.VIS1.9"
const VIS19_MODE := "EVOLUTION_OBSERVATORY_PROGRESSIVE_DETAIL"
const VIS19_MAX_PROGRESSIVE_PH5 := 5
const VIS19_DETAIL_BUILD_INTERVAL_SECONDS := 0.18

var _vis19_layer: CanvasLayer
var _vis19_panel: Control
var _vis19_observatory_visible := true
var _vis19_selected_generation := -1
var _vis19_follow_live := true
var _vis19_last_history_hash := ""
var _vis19_detail_root: Node3D
var _vis19_detail_queue: Array[Dictionary] = []
var _vis19_detail_nodes := {}
var _vis19_detail_generation := -1
var _vis19_detail_accumulator := 0.0
var _vis19_progressive_detail_builds := 0

func _ready() -> void:
	super._ready()
	_create_vis19_observatory()
	_create_vis19_detail_root()
	_vis19_selected_generation = _vis18r_generation
	_refresh_vis19_observatory(true)
	_reset_vis19_detail_queue()
	if is_instance_valid(_controls_label):
		_controls_label.text = "WASD move | Q/E down/up | Shift boost | mouse look | Esc capture | Home reset | Left/Right generation | Space play/pause | R restart G0 | O observatory | PgUp/PgDn inspect history | F1-F5 diagnostics\nVIS1.9: observatory graphs track population/turnover/fitness/diversity/composition; while paused, up to 5 nearest realtime proxies are progressively replaced by detailed PH5 without whole-field rebuild"
	_update_status()

func _process(delta: float) -> void:
	var generation_before := _vis18r_generation
	var playing_before := _vis18r_playing
	super._process(delta)
	if _vis19_follow_live:
		_vis19_selected_generation = _vis18r_generation
	_refresh_vis19_observatory(false)
	if _vis18r_playing:
		if not playing_before or not _vis19_detail_nodes.is_empty():
			_clear_vis19_progressive_detail()
		return
	if _vis18r_generation != generation_before or _vis19_detail_generation != _vis18r_generation:
		_reset_vis19_detail_queue()
	if _vis18r_generation <= 0:
		_clear_vis19_progressive_detail()
		return
	_vis19_detail_accumulator += delta
	if _vis19_detail_accumulator < VIS19_DETAIL_BUILD_INTERVAL_SECONDS:
		return
	_vis19_detail_accumulator = 0.0
	if not _vis19_detail_queue.is_empty() and _vis19_detail_nodes.size() < VIS19_MAX_PROGRESSIVE_PH5:
		var record: Dictionary = _vis19_detail_queue.pop_front()
		_build_vis19_progressive_detail(record)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			match key_event.keycode:
				KEY_O:
					_vis19_observatory_visible = not _vis19_observatory_visible
					if is_instance_valid(_vis19_panel):
						_vis19_panel.call("set_observatory_visible", _vis19_observatory_visible)
					get_viewport().set_input_as_handled()
					return
				KEY_PAGEUP:
					_step_vis19_selected_generation(-1)
					get_viewport().set_input_as_handled()
					return
				KEY_PAGEDOWN:
					_step_vis19_selected_generation(1)
					get_viewport().set_input_as_handled()
					return
	super._unhandled_input(event)

func set_realtime_turnover_generation(generation: int) -> void:
	super.set_realtime_turnover_generation(generation)
	if _vis19_follow_live:
		_vis19_selected_generation = _vis18r_generation
	_refresh_vis19_observatory(true)
	_reset_vis19_detail_queue()

func get_observatory_state() -> Dictionary:
	var summary := ObservatoryModel.summarize(get_continuous_history(), _vis19_selected_generation)
	return {
		"stage": VIS1_9_STAGE,
		"mode": VIS19_MODE,
		"visible": _vis19_observatory_visible,
		"follow_live": _vis19_follow_live,
		"selected_generation": _vis19_selected_generation,
		"history_point_count": int(summary.get("point_count", 0)),
		"history_hash": String(summary.get("history_hash", "")),
		"progressive_detail_count": _vis19_detail_nodes.size(),
		"progressive_detail_builds": _vis19_progressive_detail_builds,
		"progressive_detail_limit": VIS19_MAX_PROGRESSIVE_PH5,
		"detail_generation": _vis19_detail_generation,
		"whole_field_ph5_rebuilds": _vis18r_ph5_rebuilds_during_turnover,
		"canonical_population_truth": false,
		"canonical_timeline_truth": false,
	}

func get_observatory_summary() -> Dictionary:
	return ObservatoryModel.summarize(get_continuous_history(), _vis19_selected_generation)

func _create_vis19_observatory() -> void:
	_vis19_layer = CanvasLayer.new()
	_vis19_layer.name = "VIS19ObservatoryLayer"
	_vis19_layer.layer = 20
	add_child(_vis19_layer)
	_vis19_panel = ObservatoryPanel.new()
	_vis19_panel.name = "EvolutionObservatory"
	_vis19_panel.position = Vector2(1018.0, 476.0)
	_vis19_panel.size = Vector2(404.0, 408.0)
	_vis19_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vis19_layer.add_child(_vis19_panel)

func _create_vis19_detail_root() -> void:
	var projection := get_node_or_null("SpatialEcologyProjection") as Node3D
	if projection == null:
		return
	_vis19_detail_root = Node3D.new()
	_vis19_detail_root.name = "VIS19ProgressivePH5Detail"
	projection.add_child(_vis19_detail_root)

func _refresh_vis19_observatory(force: bool) -> void:
	if not is_instance_valid(_vis19_panel):
		return
	var history := get_continuous_history()
	var summary := ObservatoryModel.summarize(history, _vis19_selected_generation)
	var history_hash := String(summary.get("history_hash", ""))
	if not force and history_hash == _vis19_last_history_hash:
		return
	_vis19_last_history_hash = history_hash
	_vis19_panel.call("set_observatory_data", history, _vis19_selected_generation)

func _step_vis19_selected_generation(direction: int) -> void:
	var history := get_continuous_history()
	if history.is_empty():
		return
	var generations: Array[int] = []
	for point in history:
		generations.append(int(point.get("generation", 0)))
	generations.sort()
	var current := _vis19_selected_generation
	if current < 0:
		current = _vis18r_generation
	var selected_index := 0
	var best_distance := 2147483647
	for index in range(generations.size()):
		var distance := absi(generations[index] - current)
		if distance < best_distance:
			best_distance = distance
			selected_index = index
	selected_index = clampi(selected_index + direction, 0, generations.size() - 1)
	_vis19_selected_generation = generations[selected_index]
	_vis19_follow_live = _vis19_selected_generation == _vis18r_generation
	_refresh_vis19_observatory(true)
	_update_status()

func _reset_vis19_detail_queue() -> void:
	_clear_vis19_progressive_detail()
	_vis19_detail_generation = _vis18r_generation
	_vis19_detail_accumulator = 0.0
	if _vis18r_generation <= 0 or _vis18r_playing:
		return
	var generation_map: Dictionary = _vis18r_model.generation_map(_vis18r_generation)
	if generation_map.is_empty():
		return
	var ranked: Array[Dictionary] = []
	for state_variant in generation_map.values():
		if typeof(state_variant) != TYPE_DICTIONARY:
			continue
		for record_variant in Array(Dictionary(state_variant).get("records", [])):
			if typeof(record_variant) != TYPE_DICTIONARY:
				continue
			var record: Dictionary = Dictionary(record_variant).duplicate(true)
			var dx := float(record.get("world_x", 0.0)) - _camera.global_position.x
			var dz := float(record.get("world_z", 0.0)) - _camera.global_position.z
			record["_vis19_distance_sq"] = dx * dx + dz * dz
			_insert_vis19_ranked(ranked, record)
	while ranked.size() > VIS19_MAX_PROGRESSIVE_PH5:
		ranked.pop_back()
	_vis19_detail_queue = ranked

func _insert_vis19_ranked(ranked: Array[Dictionary], record: Dictionary) -> void:
	var distance := float(record.get("_vis19_distance_sq", INF))
	var inserted := false
	for index in range(ranked.size()):
		if distance < float(ranked[index].get("_vis19_distance_sq", INF)):
			ranked.insert(index, record)
			inserted = true
			break
	if not inserted:
		ranked.append(record)

func _build_vis19_progressive_detail(record: Dictionary) -> void:
	if not is_instance_valid(_vis19_detail_root):
		return
	var stable_id := String(record.get("stable_id", ""))
	if stable_id.is_empty() or _vis19_detail_nodes.has(stable_id):
		return
	var population_id := String(record.get("population_id", ""))
	var genome: Dictionary = record.get("genome", {})
	var lineage: Dictionary = record.get("lineage", {})
	var inherited_traits := VIS16.development_traits_from_genome(genome, population_id)
	if inherited_traits.is_empty():
		return
	var world_x := float(record.get("world_x", 0.0))
	var world_z := float(record.get("world_z", 0.0))
	var environment := sample_environment_at(world_x, world_z)
	var lineage_id := String(lineage.get("lineage_id", ""))
	if lineage_id.is_empty():
		lineage_id = stable_id
	var seed_index := stable_id.sha256_text().substr(0, 7).hex_to_int()
	var envelope := DevelopmentContract.create_seed_envelope(
		genome,
		inherited_traits,
		lineage_id,
		"vis1-9/detail/%d/%s" % [_vis18r_generation, stable_id],
		seed_index
	)
	if envelope.is_empty():
		return
	var phenotype := EnvironmentDevelopment.realize(envelope, inherited_traits, environment)
	if phenotype.is_empty():
		return
	var description := RenderDescription.build(Dictionary(phenotype.get("growth_graph", {})))
	if description.is_empty():
		return
	var materialization := VIS19_Materializer3D.build(description, _ph5_profile)
	if materialization.is_empty():
		return

	var detail := Node3D.new()
	detail.name = "Detail_%s" % stable_id.sha256_text().substr(0, 10)
	detail.position = Vector3(world_x, sample_terrain_height(world_x, world_z) + 0.03, world_z)
	detail.rotation.y = float(record.get("rotation_y", 0.0))
	detail.set_meta("stable_id", stable_id)
	detail.set_meta("vis19_progressive_ph5", true)
	detail.set_meta("geometry_hash", String(materialization.get("geometry_hash", "")))
	detail.set_meta("canonical_population_truth", false)

	var branch_mesh := materialization.get("branch_mesh") as ArrayMesh
	if branch_mesh != null:
		var branches := MeshInstance3D.new()
		branches.name = "Branches"
		branches.mesh = branch_mesh
		branches.material_override = _branch_material(population_id)
		detail.add_child(branches)
	var foliage_multimesh := materialization.get("foliage_multimesh") as MultiMesh
	if foliage_multimesh != null:
		var foliage := MultiMeshInstance3D.new()
		foliage.name = "Foliage"
		foliage.multimesh = foliage_multimesh
		foliage.material_override = _foliage_material(population_id)
		detail.add_child(foliage)

	if detail.get_child_count() == 0:
		detail.queue_free()
		return
	_vis19_detail_root.add_child(detail)
	_vis19_detail_nodes[stable_id] = detail
	_vis19_progressive_detail_builds += 1
	var proxy := _vis18r_renderer.nodes_by_id.get(stable_id) as Node3D
	if is_instance_valid(proxy):
		proxy.visible = false
	_update_status()

func _clear_vis19_progressive_detail() -> void:
	for stable_id_variant in _vis19_detail_nodes.keys():
		var stable_id := String(stable_id_variant)
		var proxy := _vis18r_renderer.nodes_by_id.get(stable_id) as Node3D
		if is_instance_valid(proxy):
			proxy.visible = true
		var detail := _vis19_detail_nodes.get(stable_id) as Node3D
		if is_instance_valid(detail):
			detail.queue_free()
	_vis19_detail_nodes.clear()
	_vis19_detail_queue.clear()
	_vis19_detail_accumulator = 0.0

func _update_status() -> void:
	super._update_status()
	var status := get_node_or_null("HUD/Margin/Panel/VBox/Status") as Label
	if status == null:
		return
	var selected_label := "LIVE" if _vis19_follow_live else "G%d" % _vis19_selected_generation
	status.text += "\nVIS1.9=ACTIVE observatory=%s selected=%s | charts=population,turnover,fitness,diversity,alpha/beta | progressive_PH5=%d/%d builds=%d | whole_field_PH5_rebuilds=%d" % [
		"ON" if _vis19_observatory_visible else "OFF",
		selected_label,
		_vis19_detail_nodes.size(),
		VIS19_MAX_PROGRESSIVE_PH5,
		_vis19_progressive_detail_builds,
		_vis18r_ph5_rebuilds_during_turnover,
	]
