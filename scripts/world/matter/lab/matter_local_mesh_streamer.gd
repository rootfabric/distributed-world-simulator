extends Node3D

signal stats_changed(stats: Dictionary)

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const BodyScript = preload("res://scripts/simulation/matter/contracts/matter_body_definition.gd")
const MaterialCatalogScript = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const ProfileScript = preload("res://scripts/simulation/matter/generation/fixed_seed_asteroid_profile.gd")
const FeatureCatalogScript = preload("res://scripts/simulation/matter/generation/asteroid_feature_catalog.gd")
const GeneratorScript = preload("res://scripts/simulation/matter/generation/fixed_seed_asteroid_generator.gd")
const GridProfileScript = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const CellGridScript = preload("res://scripts/simulation/matter/spatial/matter_cell_grid.gd")
const MaterializerScript = preload("res://scripts/simulation/matter/storage/matter_brick_materializer.gd")
const MeshDataScript = preload("res://scripts/world/matter/meshing/matter_brick_mesh_data.gd")
const MesherScript = preload("res://scripts/world/matter/meshing/matter_tetrahedral_mesher.gd")
const ResourceFactoryScript = preload("res://scripts/world/matter/meshing/matter_mesh_resource_factory.gd")

@export_range(1, 5, 1) var cell_level: int = 5
@export_range(0, 3, 1) var load_radius_cells: int = 1
@export_range(1, 8, 1) var max_builds_per_frame: int = 1
@export var build_collision: bool = true

var _configured: bool = false
var _observer: Node3D
var _body: Dictionary = {}
var _material_catalog: Dictionary = {}
var _generator_profile: Dictionary = {}
var _feature_catalog: Dictionary = {}
var _grid_profile: Dictionary = {}
var _material: StandardMaterial3D
var _request_generation: int = 0
var _last_observer_cell_id: String = ""
var _desired_by_id: Dictionary = {}
var _pending: Array = []
var _presenters_by_id: Dictionary = {}
var _empty_by_id: Dictionary = {}
var _failed_by_id: Dictionary = {}
var _built_triangle_count: int = 0
var _last_build_ms: float = 0.0


func configure(
	body: Dictionary,
	material_catalog: Dictionary,
	generator_profile: Dictionary,
	feature_catalog: Dictionary,
	grid_profile: Dictionary,
	observer: Node3D
) -> Dictionary:
	if observer == null \
		or not bool(BodyScript.validate(body).get("success", false)) \
		or not bool(MaterialCatalogScript.validate(material_catalog).get("success", false)) \
		or not bool(ProfileScript.validate(generator_profile).get("success", false)) \
		or not bool(FeatureCatalogScript.validate(feature_catalog).get("success", false)) \
		or not bool(GridProfileScript.validate(grid_profile).get("success", false)) \
		or not bool(GeneratorScript.validate_configuration(
			body, material_catalog, generator_profile, feature_catalog
		).get("success", false)):
		return MatterUtilsScript.failure("INVALID_MW3_STREAMER_CONFIGURATION")
	if String(grid_profile["body_id"]) != String(body["body_id"]) \
		or String(grid_profile["body_frame_id"]) != String(body["body_frame_id"]):
		return MatterUtilsScript.failure("MW3_STREAMER_BODY_GRID_MISMATCH")
	if cell_level < 1 or cell_level > int(grid_profile["max_level"]):
		return MatterUtilsScript.failure("INVALID_MW3_STREAMER_CELL_LEVEL")
	if load_radius_cells < 0 or max_builds_per_frame < 1:
		return MatterUtilsScript.failure("INVALID_MW3_STREAMER_BUDGET")
	_body = body.duplicate(true)
	_material_catalog = material_catalog.duplicate(true)
	_generator_profile = generator_profile.duplicate(true)
	_feature_catalog = feature_catalog.duplicate(true)
	_grid_profile = grid_profile.duplicate(true)
	_observer = observer
	_material = ResourceFactoryScript.create_vertex_color_material()
	_clear_presenters()
	_configured = true
	_last_observer_cell_id = ""
	var observer_position_result: Dictionary = _observer_position_body_local()
	if not bool(observer_position_result.get("success", false)):
		_reset_failed_configuration()
		return observer_position_result
	var refresh_result: Dictionary = refresh_at_body_local_position(
		observer_position_result["details"]["position_body_local_m"]
	)
	if not bool(refresh_result.get("success", false)):
		_reset_failed_configuration()
		return refresh_result
	set_process(true)
	return MatterUtilsScript.success()


func _process(_delta: float) -> void:
	if not _configured or _observer == null or not is_instance_valid(_observer):
		return
	var observer_position_result: Dictionary = _observer_position_body_local()
	if not bool(observer_position_result.get("success", false)):
		return
	var observer_position: Vector3 = observer_position_result["details"]["position_body_local_m"]
	var observer_cell: Dictionary = CellGridScript.address_for_position(
		_grid_profile, observer_position, cell_level
	)
	if observer_cell.is_empty():
		return
	var observer_cell_id: String = String(observer_cell.get("cell_id", ""))
	if observer_cell_id != _last_observer_cell_id:
		refresh_at_body_local_position(observer_position)
	for _iteration in range(max_builds_per_frame):
		if not build_next_pending():
			break


func refresh_now() -> Dictionary:
	if not _configured or _observer == null or not is_instance_valid(_observer):
		return MatterUtilsScript.failure("MW3_STREAMER_NOT_CONFIGURED")
	var observer_position_result: Dictionary = _observer_position_body_local()
	if not bool(observer_position_result.get("success", false)):
		return observer_position_result
	return refresh_at_body_local_position(observer_position_result["details"]["position_body_local_m"])


func refresh_at_body_local_position(observer_position: Vector3) -> Dictionary:
	if not _configured:
		return MatterUtilsScript.failure("MW3_STREAMER_NOT_CONFIGURED")
	if not _is_finite_vector(observer_position):
		return MatterUtilsScript.failure("INVALID_MW3_STREAMER_OBSERVER_POSITION")
	var observer_cell: Dictionary = CellGridScript.address_for_position(
		_grid_profile, observer_position, cell_level
	)
	if observer_cell.is_empty():
		return MatterUtilsScript.failure("MW3_STREAMER_OBSERVER_OUTSIDE_ROOT")
	_last_observer_cell_id = String(observer_cell["cell_id"])
	var observer_bounds: Dictionary = CellGridScript.bounds(_grid_profile, observer_cell)
	var edge_m: float = float(observer_bounds["edge_length_m"])
	var desired_by_id: Dictionary = {}
	for offset_z in range(-load_radius_cells, load_radius_cells + 1):
		for offset_y in range(-load_radius_cells, load_radius_cells + 1):
			for offset_x in range(-load_radius_cells, load_radius_cells + 1):
				var probe: Vector3 = observer_position + Vector3(
					float(offset_x) * edge_m,
					float(offset_y) * edge_m,
					float(offset_z) * edge_m
				)
				var address: Dictionary = CellGridScript.address_for_position(
					_grid_profile, probe, cell_level
				)
				if not address.is_empty():
					desired_by_id[String(address["cell_id"])] = address
	_request_generation += 1
	_desired_by_id = desired_by_id
	_pending.clear()
	var desired_ids: Array = _desired_by_id.keys()
	desired_ids.sort()
	for address_id in desired_ids:
		_failed_by_id.erase(address_id)
		if not _presenters_by_id.has(address_id) and not _empty_by_id.has(address_id):
			_pending.append({
				"generation": _request_generation,
				"address_id": String(address_id),
				"address": Dictionary(_desired_by_id[address_id]).duplicate(true),
			})
	var loaded_ids: Array = _presenters_by_id.keys()
	for address_id in loaded_ids:
		if _desired_by_id.has(address_id):
			continue
		var presenter: Node3D = _presenters_by_id[address_id]
		_built_triangle_count -= int(presenter.get_meta("triangle_count", 0))
		_presenters_by_id.erase(address_id)
		presenter.queue_free()
	var empty_ids: Array = _empty_by_id.keys()
	for address_id in empty_ids:
		if not _desired_by_id.has(address_id):
			_empty_by_id.erase(address_id)
	var failed_ids: Array = _failed_by_id.keys()
	for address_id in failed_ids:
		if not _desired_by_id.has(address_id):
			_failed_by_id.erase(address_id)
	_emit_stats()
	return MatterUtilsScript.success({"desired_count": _desired_by_id.size()})


func build_next_pending() -> bool:
	if not _configured:
		return false
	while not _pending.is_empty():
		var request: Dictionary = _pending.pop_front()
		if int(request["generation"]) != _request_generation:
			continue
		var address_id: String = String(request["address_id"])
		if not _desired_by_id.has(address_id) \
			or _presenters_by_id.has(address_id) or _empty_by_id.has(address_id) \
			or _failed_by_id.has(address_id):
			continue
		var started_usec: int = Time.get_ticks_usec()
		var snapshot: Dictionary = MaterializerScript.materialize(
			_body,
			_material_catalog,
			_generator_profile,
			_feature_catalog,
			_grid_profile,
			request["address"],
			0
		)
		var mesh_data: Dictionary = MesherScript.build_mesh_data(snapshot, _grid_profile)
		_last_build_ms = float(Time.get_ticks_usec() - started_usec) / 1000.0
		var mesh_validation: Dictionary = MeshDataScript.validate(mesh_data)
		if not bool(mesh_validation.get("success", false)):
			_failed_by_id[address_id] = String(mesh_validation.get(
				"error_code", "MW3_MESH_BUILD_FAILED"
			))
			_emit_stats()
			return true
		if String(mesh_data["status"]) == MeshDataScript.STATUS_EMPTY:
			_empty_by_id[address_id] = true
			_emit_stats()
			return true
		var presenter: Node3D = ResourceFactoryScript.create_presenter(
			mesh_data, _material, build_collision
		)
		if presenter != null:
			presenter.set_meta("triangle_count", int(mesh_data["triangle_count"]))
			add_child(presenter)
			_presenters_by_id[address_id] = presenter
			_built_triangle_count += int(mesh_data["triangle_count"])
		_emit_stats()
		return true
	return false


func stats() -> Dictionary:
	return {
		"configured": _configured,
		"request_generation": _request_generation,
		"cell_level": cell_level,
		"load_radius_cells": load_radius_cells,
		"desired_count": _desired_by_id.size(),
		"pending_count": _pending.size(),
		"surface_brick_count": _presenters_by_id.size(),
		"empty_brick_count": _empty_by_id.size(),
		"failed_brick_count": _failed_by_id.size(),
		"triangle_count": _built_triangle_count,
		"last_build_ms": _last_build_ms,
	}


func desired_address_ids() -> Array:
	var result: Array = _desired_by_id.keys()
	result.sort()
	return result


func _observer_position_body_local() -> Dictionary:
	if _observer == null or not is_instance_valid(_observer):
		return MatterUtilsScript.failure("MW3_STREAMER_OBSERVER_MISSING")
	var observer_space: Dictionary = _transform_to_root(_observer)
	var streamer_space: Dictionary = _transform_to_root(self)
	if observer_space.is_empty() or streamer_space.is_empty() \
		or observer_space["root"] != streamer_space["root"]:
		return MatterUtilsScript.failure("MW3_STREAMER_OBSERVER_SPACE_MISMATCH")
	var observer_to_root: Transform3D = observer_space["transform_to_root"]
	var streamer_to_root: Transform3D = streamer_space["transform_to_root"]
	var position_body_local_m: Vector3 = streamer_to_root.affine_inverse() \
		* observer_to_root.origin
	if not _is_finite_vector(position_body_local_m):
		return MatterUtilsScript.failure("INVALID_MW3_STREAMER_OBSERVER_POSITION")
	return MatterUtilsScript.success({"position_body_local_m": position_body_local_m})


func _transform_to_root(node: Node3D) -> Dictionary:
	if node == null or not is_instance_valid(node):
		return {}
	var transform_to_root := Transform3D.IDENTITY
	var current: Node = node
	var root_node: Node = node
	while current != null:
		if current is Node3D:
			transform_to_root = (current as Node3D).transform * transform_to_root
		root_node = current
		current = current.get_parent()
	return {
		"root": root_node,
		"transform_to_root": transform_to_root,
	}


func _reset_failed_configuration() -> void:
	_configured = false
	_observer = null
	_clear_presenters()
	set_process(false)


func _emit_stats() -> void:
	stats_changed.emit(stats())


func _clear_presenters() -> void:
	for presenter_value in _presenters_by_id.values():
		var presenter: Node3D = presenter_value
		if is_instance_valid(presenter):
			presenter.queue_free()
	_presenters_by_id.clear()
	_empty_by_id.clear()
	_failed_by_id.clear()
	_pending.clear()
	_desired_by_id.clear()
	_built_triangle_count = 0


func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
