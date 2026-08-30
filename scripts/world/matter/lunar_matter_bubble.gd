extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const MaterialCatalogScript = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const MoonSamplerScript = preload("res://scripts/simulation/matter/generation/moon_geology_sampler.gd")
const MoonFeaturesScript = preload(
	"res://scripts/simulation/matter/generation/moon_surface_feature_catalog.gd"
)
const GridProfileScript = preload(
	"res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd"
)
const CellGridScript = preload("res://scripts/simulation/matter/spatial/matter_cell_grid.gd")
const BrickLayoutScript = preload("res://scripts/simulation/matter/spatial/matter_brick_layout.gd")
const MaterializerScript = preload(
	"res://scripts/simulation/matter/storage/matter_brick_materializer.gd"
)
const ExcavationServiceScript = preload(
	"res://scripts/simulation/matter/mutation/matter_excavation_service.gd"
)
const QueryServiceScript = preload(
	"res://scripts/simulation/matter/query/matter_continuous_query_service.gd"
)

const DEFAULT_HALF_EXTENT_M: float = 64.0
const DEFAULT_MUTATION_LEVEL: int = 3
const DEFAULT_PRESENTATION_LEVEL: int = 1
const DEFAULT_MAX_LEVEL: int = 4
const DEFAULT_BRICK_RESOLUTION: int = 8
const DEFAULT_GHOST_SAMPLES: int = 1
const DEFAULT_CONTAINER_ID: String = "container/p7-moon-bubble"
const DEFAULT_MAX_RECEIVER_MASS_KG: float = 1000000000.0
const DEFAULT_MAX_RECEIVER_VOLUME_M3: float = 1000000.0

var _configured := false
var _enabled := true
var _anchor_direction := Vector3.UP
var _surface_radius_m := MoonSamplerScript.REFERENCE_RADIUS_M
var _half_extent_m := DEFAULT_HALF_EXTENT_M
var _mutation_level := DEFAULT_MUTATION_LEVEL
var _presentation_level := DEFAULT_PRESENTATION_LEVEL
var _body: Dictionary = {}
var _material_catalog: Dictionary = {}
var _profile: Dictionary = {}
var _feature_catalog: Dictionary = {}
var _grid_profile: Dictionary = {}
var _excavation_service = null
var _query_service = null


func configure(data: Dictionary = {}) -> Dictionary:
	if _configured:
		return MatterUtilsScript.failure("P7_LUNAR_MATTER_BUBBLE_ALREADY_CONFIGURED")
	var anchor_value = data.get("anchor_direction", [0.0, 1.0, 0.0])
	if typeof(anchor_value) != TYPE_ARRAY or Array(anchor_value).size() != 3:
		return MatterUtilsScript.failure("P7_LUNAR_MATTER_BUBBLE_ANCHOR_INVALID")
	var anchor := Vector3(
		float(anchor_value[0]), float(anchor_value[1]), float(anchor_value[2])
	)
	if not _finite_vector(anchor) or anchor.length_squared() <= 0.000000000001:
		return MatterUtilsScript.failure("P7_LUNAR_MATTER_BUBBLE_ANCHOR_INVALID")
	anchor = anchor.normalized()
	var surface_radius_m := float(data.get(
		"canonical_surface_radius_m", MoonSamplerScript.REFERENCE_RADIUS_M
	))
	var half_extent_m := float(data.get("half_extent_m", DEFAULT_HALF_EXTENT_M))
	var mutation_level := int(data.get("mutation_level", DEFAULT_MUTATION_LEVEL))
	var presentation_level := int(data.get(
		"presentation_level", DEFAULT_PRESENTATION_LEVEL
	))
	var max_level := int(data.get("max_level", DEFAULT_MAX_LEVEL))
	if not MatterUtilsScript.is_positive_number(surface_radius_m) 		or not MatterUtilsScript.is_positive_number(half_extent_m) 		or max_level < 1 or max_level > 8 		or mutation_level < 1 or mutation_level > max_level 		or presentation_level < 0 or presentation_level > max_level:
		return MatterUtilsScript.failure("P7_LUNAR_MATTER_BUBBLE_BOUNDS_INVALID")

	var material_catalog := MaterialCatalogScript.default_catalog()
	var profile := MoonSamplerScript.create_profile({
		"generator_seed": int(data.get("generator_seed", MoonSamplerScript.DEFAULT_SEED)),
		"canonical_surface_radius_m": surface_radius_m,
		"regolith_loose_depth_m": float(data.get("regolith_loose_depth_m", 2.0)),
		"regolith_compacted_depth_m": float(data.get("regolith_compacted_depth_m", 8.0)),
		"fractured_basalt_depth_m": float(data.get("fractured_basalt_depth_m", 28.0)),
	})
	var feature_catalog := MoonFeaturesScript.default_catalog(int(profile["generator_seed"]))
	var body := MoonSamplerScript.default_body_definition(
		material_catalog, profile, feature_catalog
	)
	if body.is_empty():
		return MatterUtilsScript.failure("P7_LUNAR_MATTER_BUBBLE_BODY_BUILD_FAILED")
	var root_center := anchor * surface_radius_m
	var grid_profile := GridProfileScript.create({
		"universe_id": String(data.get("universe_id", "main")),
		"instance_id": String(data.get("instance_id", "persistent")),
		"space_id": String(data.get("space_id", "moon")),
		"grid_id": String(data.get("grid_id", "p7-moon-matter")),
		"grid_revision": int(data.get("grid_revision", 1)),
		"root_id": String(data.get("root_id", "p7-moon-bubble-root")),
		"body_id": MoonSamplerScript.BODY_ID,
		"body_frame_id": MoonSamplerScript.BODY_FRAME_ID,
		"root_center_m": _array(root_center),
		"root_half_extent_m": half_extent_m,
		"max_level": max_level,
		"brick_interior_resolution": int(data.get(
			"brick_interior_resolution", DEFAULT_BRICK_RESOLUTION
		)),
		"ghost_border_samples": int(data.get(
			"ghost_border_samples", DEFAULT_GHOST_SAMPLES
		)),
	})
	if not bool(GridProfileScript.validate(grid_profile).get("success", false)):
		return MatterUtilsScript.failure("P7_LUNAR_MATTER_BUBBLE_GRID_BUILD_FAILED")

	var excavation = ExcavationServiceScript.new()
	var excavation_setup := excavation.configure(
		body,
		material_catalog,
		profile,
		feature_catalog,
		grid_profile,
		mutation_level,
		String(data.get("container_id", DEFAULT_CONTAINER_ID)),
		float(data.get("maximum_receiver_mass_kg", DEFAULT_MAX_RECEIVER_MASS_KG)),
		float(data.get(
			"maximum_receiver_volume_m3", DEFAULT_MAX_RECEIVER_VOLUME_M3
		)),
		null,
		null,
		null,
		MoonSamplerScript
	)
	if not bool(excavation_setup.get("success", false)):
		return excavation_setup
	var query = QueryServiceScript.new()
	var query_setup := query.configure(
		body,
		material_catalog,
		profile,
		feature_catalog,
		grid_profile,
		excavation.snapshot_store(),
		MoonSamplerScript
	)
	if not bool(query_setup.get("success", false)):
		return query_setup

	_anchor_direction = anchor
	_surface_radius_m = surface_radius_m
	_half_extent_m = half_extent_m
	_mutation_level = mutation_level
	_presentation_level = presentation_level
	_body = body
	_material_catalog = material_catalog
	_profile = profile
	_feature_catalog = feature_catalog
	_grid_profile = grid_profile
	_excavation_service = excavation
	_query_service = query
	_enabled = bool(data.get("enabled", true))
	_configured = true
	return MatterUtilsScript.success(contract_report())


func set_enabled(enabled: bool) -> void:
	_enabled = enabled


func is_enabled() -> bool:
	return _configured and _enabled


func contains_body_fixed_position(position_m: Vector3) -> bool:
	if not is_enabled() or not _finite_vector(position_m):
		return false
	var root := Vector3(
		float(_grid_profile["root_center_m"][0]),
		float(_grid_profile["root_center_m"][1]),
		float(_grid_profile["root_center_m"][2])
	)
	var delta := position_m - root
	return absf(delta.x) <= _half_extent_m 		and absf(delta.y) <= _half_extent_m 		and absf(delta.z) <= _half_extent_m


func route_for_body_fixed_position(position_m: Vector3) -> String:
	return "MATTER" if contains_body_fixed_position(position_m) else "LEGACY"


func sample_body_fixed(position_m: Vector3, level: int = -1) -> Dictionary:
	if not contains_body_fixed_position(position_m):
		return {}
	var selected_level := _mutation_level if level < 0 else level
	return _query_service.sample(position_m, selected_level)


func create_excavation_request(
	operation_id: String,
	actor_id: String,
	tool_id: String,
	start_position_m: Vector3,
	end_position_m: Vector3,
	radius_m: float,
	energy_budget_j: float,
	client_tick: int = 0
) -> Dictionary:
	if not is_enabled() or not _capsule_fully_inside_root(
		start_position_m, end_position_m, radius_m
	):
		return {}
	return _excavation_service.create_excavation_request(
		operation_id,
		actor_id,
		tool_id,
		start_position_m,
		end_position_m,
		radius_m,
		energy_budget_j,
		client_tick
	)


func execute(request: Dictionary) -> Dictionary:
	if not is_enabled() or typeof(request.get("shape")) != TYPE_DICTIONARY:
		return {}
	var shape: Dictionary = request["shape"]
	var start := _vector3(Array(shape.get("start_position_m", [])))
	var end := _vector3(Array(shape.get("end_position_m", [])))
	var radius_m := float(shape.get("radius_m", 0.0))
	if not _capsule_fully_inside_root(start, end, radius_m):
		return {}
	return _excavation_service.execute(request)


func ensure_materialized_cell(cell_address: Dictionary, state_revision: int = 0) -> Dictionary:
	if not is_enabled() or not bool(
		CellGridScript.validate_address(_grid_profile, cell_address).get("success", false)
	):
		return {}
	var address := BrickLayoutScript.brick_address(_grid_profile, cell_address)
	if address.is_empty():
		return {}
	var store = _excavation_service.snapshot_store()
	if store.has(address):
		return store.get_snapshot(address)
	var snapshot := MaterializerScript.materialize(
		_body,
		_material_catalog,
		_profile,
		_feature_catalog,
		_grid_profile,
		cell_address,
		state_revision,
		MoonSamplerScript
	)
	if snapshot.is_empty():
		return {}
	var put := store.put(snapshot)
	return snapshot if bool(put.get("success", false)) else {}


func materialize_presentation_level() -> Array:
	if not is_enabled():
		return []
	var level := _presentation_level
	var count := 1 << level
	var root_center := _vector3(_grid_profile["root_center_m"])
	var root_min := root_center - Vector3.ONE * _half_extent_m
	var edge := (_half_extent_m * 2.0) / float(count)
	var result: Array = []
	var seen: Dictionary = {}
	for z in range(count):
		for y in range(count):
			for x in range(count):
				var center := root_min + Vector3(
					(float(x) + 0.5) * edge,
					(float(y) + 0.5) * edge,
					(float(z) + 0.5) * edge
				)
				var cell := CellGridScript.address_for_position(
					_grid_profile, center, level
				)
				if cell.is_empty():
					continue
				var cell_id := String(cell["cell_id"])
				if seen.has(cell_id):
					continue
				seen[cell_id] = true
				var snapshot := ensure_materialized_cell(cell, 0)
				if not snapshot.is_empty():
					result.append(snapshot)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["address"]["address_id"]) < String(b["address"]["address_id"])
	)
	return result


func body_definition() -> Dictionary:
	return _body.duplicate(true)


func generator_profile() -> Dictionary:
	return _profile.duplicate(true)


func feature_catalog() -> Dictionary:
	return _feature_catalog.duplicate(true)


func grid_profile() -> Dictionary:
	return _grid_profile.duplicate(true)


func snapshot_store():
	return _excavation_service.snapshot_store() if _excavation_service != null else null


func excavation_service():
	return _excavation_service


func query_service():
	return _query_service


func anchor_body_fixed_m() -> Vector3:
	return _anchor_direction * _surface_radius_m


func anchor_direction() -> Vector3:
	return _anchor_direction


func half_extent_m() -> float:
	return _half_extent_m


func surface_radius_m() -> float:
	return _surface_radius_m


func presentation_level() -> int:
	return _presentation_level


func mutation_level() -> int:
	return _mutation_level


func contract_report() -> Dictionary:
	return {
		"configured": _configured,
		"enabled": _enabled,
		"body_id": String(_body.get("body_id", MoonSamplerScript.BODY_ID)),
		"body_frame_id": String(_body.get(
			"body_frame_id", MoonSamplerScript.BODY_FRAME_ID
		)),
		"root_center_m": Array(_grid_profile.get("root_center_m", [])).duplicate(),
		"root_half_extent_m": _half_extent_m,
		"mutation_level": _mutation_level,
		"presentation_level": _presentation_level,
		"canonical_geometry_owner": "MATTER",
		"canonical_query_owner": "MATTER",
		"canonical_collision_source": "MATTER_MESH",
		"outside_route": "LEGACY_MOON",
		"canonical_state_owned_by_adapter": false,
	}


func _capsule_fully_inside_root(
	start_position_m: Vector3,
	end_position_m: Vector3,
	radius_m: float
) -> bool:
	if not _finite_vector(start_position_m) or not _finite_vector(end_position_m) 		or not MatterUtilsScript.is_positive_number(radius_m):
		return false
	var root := _vector3(_grid_profile.get("root_center_m", []))
	var interior := _half_extent_m - radius_m
	if interior <= 0.0:
		return false
	for point in [start_position_m, end_position_m]:
		var delta: Vector3 = point - root
		if absf(delta.x) > interior or absf(delta.y) > interior 			or absf(delta.z) > interior:
			return false
	return true


static func _finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


static func _vector3(value: Array) -> Vector3:
	if value.size() != 3:
		return Vector3(INF, INF, INF)
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


static func _array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
