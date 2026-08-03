extends Node3D

const MaterialCatalogScript = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const GeneratorScript = preload("res://scripts/simulation/matter/generation/fixed_seed_asteroid_generator.gd")
const GridProfileScript = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const ExcavationServiceScript = preload("res://scripts/simulation/matter/mutation/matter_excavation_service.gd")
const ContinuousQueryScript = preload("res://scripts/simulation/matter/query/matter_continuous_query_service.gd")
const StreamerScript = preload("res://scripts/world/matter/lab/matter_local_mesh_streamer.gd")
const StateRepositoryScript = preload("res://scripts/simulation/matter/persistence/matter_state_repository.gd")
const StateCoordinatorScript = preload("res://scripts/simulation/matter/persistence/matter_state_coordinator.gd")

@export_range(1, 5, 1) var cell_level: int = 5
@export_range(0, 3, 1) var load_radius_cells: int = 1
@export_range(1, 8, 1) var max_builds_per_frame: int = 1
@export var drill_radius_m: float = 18.0
@export var drill_depth_m: float = 80.0
@export var drill_energy_budget_j: float = 9000000000000000.0
@export var persistence_root_path: String = "user://matter-labs/asteroid-mw5"

var _status_label: Label
var _camera: Camera3D
var _streamer: Node3D
var _excavation_service
var _continuous_query
var _state_repository
var _state_coordinator
var _checkpoint_generation: int = 0
var _recovery_source: String = "NEW_WORLD"
var _operation_sequence: int = 0
var _last_operation_text: String = "No excavation committed yet."


func _ready() -> void:
	_build_environment()
	_build_interface()
	_start_matter_runtime()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
		and event.pressed:
		_execute_camera_drill()
		get_viewport().set_input_as_handled()


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.002, 0.003, 0.007, 1.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.12, 0.14, 0.18, 1.0)
	environment.ambient_light_energy = 0.7
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28.0, -52.0, 0.0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	add_child(sun)


func _build_interface() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16.0, 16.0)
	panel.custom_minimum_size = Vector2(680.0, 0.0)
	layer.add_child(panel)
	_status_label = Label.new()
	_status_label.text = "MW5: configuring durable matter laboratory..."
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_status_label)


func _start_matter_runtime() -> void:
	var material_catalog: Dictionary = MaterialCatalogScript.default_catalog()
	var generator_profile: Dictionary = GeneratorScript.default_profile()
	var feature_catalog: Dictionary = GeneratorScript.default_feature_catalog(generator_profile)
	var body: Dictionary = GeneratorScript.default_body_definition(
		generator_profile, material_catalog, feature_catalog
	)
	var grid_profile: Dictionary = GridProfileScript.create({
		"body_id": body["body_id"],
		"body_frame_id": body["body_frame_id"],
		"root_half_extent_m": float(generator_profile["reference_radius_m"]) \
			* float(generator_profile["root_bounds_radius_ratio"]),
	})
	_camera = get_node_or_null("Camera3D") as Camera3D
	if _camera == null:
		_status_label.text = "MW5 lab failed: Camera3D is missing."
		return
	_camera.look_at(Vector3(1000.0, 0.0, 0.0), Vector3.UP)
	_excavation_service = ExcavationServiceScript.new()
	var excavation_configuration: Dictionary = _excavation_service.configure(
		body,
		material_catalog,
		generator_profile,
		feature_catalog,
		grid_profile,
		cell_level,
		"container/mw5-lab",
		9000000000000000.0,
		1.0e13
	)
	if not bool(excavation_configuration.get("success", false)):
		_status_label.text = "MW5 excavation failed: %s" % String(
			excavation_configuration.get("error_code", "UNKNOWN")
		)
		return
	_state_repository = StateRepositoryScript.new()
	var repository_configuration: Dictionary = _state_repository.configure(persistence_root_path)
	if not bool(repository_configuration.get("success", false)):
		_status_label.text = "MW5 repository failed: %s" % String(
			repository_configuration.get("error_code", "UNKNOWN")
		)
		return
	_state_coordinator = StateCoordinatorScript.new()
	var persistence_configuration: Dictionary = _state_coordinator.configure(
		body,
		grid_profile,
		cell_level,
		_excavation_service.snapshot_store(),
		_excavation_service.material_receiver(),
		_excavation_service.mutation_journal(),
		_state_repository
	)
	if not bool(persistence_configuration.get("success", false)):
		_status_label.text = "MW5 persistence failed: %s" % String(
			persistence_configuration.get("error_code", "UNKNOWN")
		)
		return
	var recovered: Dictionary = _state_coordinator.restore_latest()
	if bool(recovered.get("success", false)):
		var checkpoint: Dictionary = recovered["details"]["checkpoint"]
		_checkpoint_generation = int(checkpoint["generation"])
		_operation_sequence = int(checkpoint["server_tick"])
		_recovery_source = String(recovered["details"].get("source", "ACTIVE"))
		_last_operation_text = "Restored generation %d from %s." % [
			_checkpoint_generation, _recovery_source,
		]
	elif String(recovered.get("error_code", "")) != "MATTER_CHECKPOINT_NOT_FOUND":
		_status_label.text = "MW5 restore failed closed: %s" % String(
			recovered.get("error_code", "UNKNOWN")
		)
		return
	_continuous_query = ContinuousQueryScript.new()
	var query_configuration: Dictionary = _continuous_query.configure(
		body,
		material_catalog,
		generator_profile,
		feature_catalog,
		grid_profile,
		_excavation_service.snapshot_store()
	)
	if not bool(query_configuration.get("success", false)):
		_status_label.text = "MW5 query failed: %s" % String(
			query_configuration.get("error_code", "UNKNOWN")
		)
		return
	_streamer = StreamerScript.new()
	_streamer.name = "MatterLocalMeshStreamer"
	_streamer.cell_level = cell_level
	_streamer.load_radius_cells = load_radius_cells
	_streamer.max_builds_per_frame = max_builds_per_frame
	_streamer.build_collision = true
	add_child(_streamer)
	_streamer.stats_changed.connect(_on_streamer_stats_changed)
	var streamer_configuration: Dictionary = _streamer.configure(
		body,
		material_catalog,
		generator_profile,
		feature_catalog,
		grid_profile,
		_camera,
		_excavation_service.snapshot_store()
	)
	if not bool(streamer_configuration.get("success", false)):
		_status_label.text = "MW5 streamer failed: %s" % String(
			streamer_configuration.get("error_code", "UNKNOWN")
		)
		return
	_update_status()


func _execute_camera_drill() -> void:
	if _camera == null or _excavation_service == null or _continuous_query == null:
		return
	var direction: Vector3 = -_camera.basis.z.normalized()
	var ray: Dictionary = _continuous_query.raycast(
		_camera.position, direction, 800.0, cell_level, 0.5, 0.25, 512
	)
	if not bool(ray.get("success", false)) or not bool(ray.get("details", {}).get("hit", false)):
		_last_operation_text = "Drill rejected: no canonical surface hit."
		_update_status()
		return
	var hit_position_m: Vector3 = ray["details"]["position_m"]
	var start_m: Vector3 = hit_position_m - direction * 4.0
	var end_m: Vector3 = hit_position_m + direction * drill_depth_m
	_operation_sequence += 1
	var operation_id: String = "matter-operation/lab-drill-%06d" % _operation_sequence
	var request: Dictionary = _excavation_service.create_excavation_request(
		operation_id,
		"actor/mw5-lab-operator",
		"tool/mw5-lab-drill",
		start_m,
		end_m,
		drill_radius_m,
		drill_energy_budget_j,
		_operation_sequence
	)
	if request.is_empty():
		_last_operation_text = "Drill rejected: request planning failed."
		_update_status()
		return
	var result: Dictionary = _excavation_service.execute(request)
	if String(result.get("status", "")) != "COMMITTED":
		_last_operation_text = "Drill rejected: %s" % String(result.get("error_code", "UNKNOWN"))
		_update_status()
		return
	var changed_addresses: Array = []
	for changed in result["changed_bricks"]:
		changed_addresses.append(changed["address"])
	_streamer.invalidate_brick_addresses(changed_addresses)
	var saved: Dictionary = _state_coordinator.save_next(_operation_sequence)
	var persistence_text: String = ""
	if bool(saved.get("success", false)):
		_checkpoint_generation = int(saved["details"]["generation"])
		_recovery_source = "ACTIVE"
		persistence_text = " Durable generation %d." % _checkpoint_generation
	else:
		persistence_text = " WARNING: in-memory commit is not durable (%s)." % String(
			saved.get("error_code", "UNKNOWN")
		)
	_last_operation_text = (
		"Committed %s: %.1f kg, %.2f m³, %d bricks, %.3e J.%s" % [
			operation_id,
			float(result["removed_mass_kg"]),
			float(_excavation_service.material_receiver().get_batch(
				String(result["created_aggregate_ids"][0])
			)["bulk_volume_m3"]),
			result["changed_bricks"].size(),
			float(result["consumed_energy_j"]),
			persistence_text,
		]
	)
	_update_status()


func _on_streamer_stats_changed(_stats: Dictionary) -> void:
	_update_status()


func _update_status() -> void:
	if _status_label == null:
		return
	var stats: Dictionary = _streamer.stats() if _streamer != null else {}
	var stored_bricks: int = _excavation_service.snapshot_store().size() \
		if _excavation_service != null else 0
	var extracted_mass_kg: float = _excavation_service.material_receiver().total_mass_kg() \
		if _excavation_service != null else 0.0
	_status_label.text = (
		"MW5 durable asteroid excavation laboratory\n"
		+ "Body: body/asteroid-mw0 | radius: 1000 m | seed: 2026073101\n"
		+ "Checkpoint: generation %d | source: %s | path: %s\n" % [
			_checkpoint_generation, _recovery_source, persistence_root_path,
		]
		+ "Stored mutated bricks: %d | extracted mass: %.1f kg | operations: %d\n" % [
			stored_bricks, extracted_mass_kg, _operation_sequence,
		]
		+ "Desired: %d | pending: %d | surface: %d | empty: %d | failed: %d\n" % [
			int(stats.get("desired_count", 0)),
			int(stats.get("pending_count", 0)),
			int(stats.get("surface_brick_count", 0)),
			int(stats.get("empty_brick_count", 0)),
			int(stats.get("failed_brick_count", 0)),
		]
		+ "%s\n" % _last_operation_text
		+ "Controls: left click — canonical swept drill; WASD/Q/E — move; Shift — boost; Esc — mouse; F — +X surface."
	)
