extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const BodyScript = preload("res://scripts/simulation/matter/contracts/matter_body_definition.gd")
const SnapshotScript = preload("res://scripts/simulation/matter/contracts/matter_brick_snapshot.gd")
const GridProfileScript = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const CellGridScript = preload("res://scripts/simulation/matter/spatial/matter_cell_grid.gd")
const BrickLayoutScript = preload("res://scripts/simulation/matter/spatial/matter_brick_layout.gd")
const SnapshotSamplerScript = preload("res://scripts/simulation/matter/query/matter_snapshot_sampler.gd")
const GeneratorScript = preload("res://scripts/simulation/matter/generation/fixed_seed_asteroid_generator.gd")

var _configured: bool = false
var _body: Dictionary = {}
var _material_catalog: Dictionary = {}
var _generator_profile: Dictionary = {}
var _feature_catalog: Dictionary = {}
var _grid_profile: Dictionary = {}
var _store = null


func configure(
	body: Dictionary,
	material_catalog: Dictionary,
	generator_profile: Dictionary,
	feature_catalog: Dictionary,
	grid_profile: Dictionary,
	snapshot_store
) -> Dictionary:
	if snapshot_store == null or not snapshot_store.has_method("get_snapshot") \
		or not snapshot_store.has_method("has") \
		or not bool(BodyScript.validate(body).get("success", false)) \
		or not bool(GridProfileScript.validate(grid_profile).get("success", false)) \
		or not bool(GeneratorScript.validate_configuration(
			body, material_catalog, generator_profile, feature_catalog
		).get("success", false)):
		return MatterUtilsScript.failure("INVALID_CONTINUOUS_MATTER_QUERY_CONFIGURATION")
	_body = body.duplicate(true)
	_material_catalog = material_catalog.duplicate(true)
	_generator_profile = generator_profile.duplicate(true)
	_feature_catalog = feature_catalog.duplicate(true)
	_grid_profile = grid_profile.duplicate(true)
	_store = snapshot_store
	_configured = true
	return MatterUtilsScript.success()


func sample(local_position_m: Vector3, level: int) -> Dictionary:
	if not _configured or not _finite_vector(local_position_m) \
		or level < 0 or level > int(_grid_profile["max_level"]):
		return {}
	var cell_address: Dictionary = CellGridScript.address_for_position(
		_grid_profile, local_position_m, level
	)
	if cell_address.is_empty():
		return {}
	var brick_address: Dictionary = BrickLayoutScript.brick_address(_grid_profile, cell_address)
	if _store.has(brick_address):
		return SnapshotSamplerScript.sample_continuous(
			_store.get_snapshot(brick_address), _grid_profile, local_position_m
		)
	return GeneratorScript.sample_validated(
		_material_catalog, _generator_profile, _feature_catalog, local_position_m
	)


func raycast(
	origin_m: Vector3,
	direction: Vector3,
	maximum_distance_m: float,
	level: int,
	hit_tolerance_m: float = 0.25,
	minimum_step_m: float = 0.25,
	maximum_steps: int = 512
) -> Dictionary:
	if not _configured or not _finite_vector(origin_m) or not _finite_vector(direction) \
		or direction.length_squared() <= 0.000000000001 \
		or not MatterUtilsScript.is_positive_number(maximum_distance_m) \
		or not MatterUtilsScript.is_positive_number(hit_tolerance_m) \
		or not MatterUtilsScript.is_positive_number(minimum_step_m) \
		or maximum_steps < 1:
		return MatterUtilsScript.failure("INVALID_CONTINUOUS_MATTER_RAYCAST")
	var ray_direction: Vector3 = direction.normalized()
	var distance_m: float = 0.0
	var previous_sdf_m: float = INF
	var previous_position_m: Vector3 = origin_m
	var snapshot_cache_by_address_id: Dictionary = {}
	for step_index in range(maximum_steps):
		var position_m: Vector3 = origin_m + ray_direction * distance_m
		var matter_sample: Dictionary = _sample_for_operation(
			position_m, level, snapshot_cache_by_address_id
		)
		if matter_sample.is_empty():
			return MatterUtilsScript.failure("CONTINUOUS_MATTER_RAY_LEFT_ROOT", {
				"distance_m": distance_m,
			})
		var sdf_m: float = float(matter_sample["signed_distance_m"])
		if absf(sdf_m) <= hit_tolerance_m:
			return MatterUtilsScript.success({
				"hit": true,
				"position_m": position_m,
				"distance_m": distance_m,
				"sample": matter_sample,
				"step_count": step_index + 1,
			})
		if is_finite(previous_sdf_m) and previous_sdf_m * sdf_m < 0.0:
			var refined: Dictionary = _refine_crossing(
				origin_m,
				previous_position_m,
				position_m,
				level,
				hit_tolerance_m,
				step_index + 1,
				snapshot_cache_by_address_id
			)
			if bool(refined.get("success", false)):
				return refined
		var step_m: float = maxf(absf(sdf_m) * 0.8, minimum_step_m)
		previous_sdf_m = sdf_m
		previous_position_m = position_m
		distance_m += step_m
		if distance_m > maximum_distance_m:
			break
	return MatterUtilsScript.success({
		"hit": false,
		"position_m": origin_m + ray_direction * maximum_distance_m,
		"distance_m": maximum_distance_m,
		"sample": {},
		"step_count": maximum_steps,
	})


func _refine_crossing(
	origin_m: Vector3,
	start_m: Vector3,
	end_m: Vector3,
	level: int,
	tolerance_m: float,
	step_count: int,
	snapshot_cache_by_address_id: Dictionary
) -> Dictionary:
	var low_m: Vector3 = start_m
	var high_m: Vector3 = end_m
	var low_sample: Dictionary = _sample_for_operation(
		low_m, level, snapshot_cache_by_address_id
	)
	if low_sample.is_empty():
		return MatterUtilsScript.failure("CONTINUOUS_MATTER_RAY_REFINE_FAILED")
	var low_sdf_m: float = float(low_sample["signed_distance_m"])
	for _iteration in range(32):
		var middle_m: Vector3 = (low_m + high_m) * 0.5
		var middle_sample: Dictionary = _sample_for_operation(
			middle_m, level, snapshot_cache_by_address_id
		)
		if middle_sample.is_empty():
			return MatterUtilsScript.failure("CONTINUOUS_MATTER_RAY_REFINE_FAILED")
		var middle_sdf_m: float = float(middle_sample["signed_distance_m"])
		if absf(middle_sdf_m) <= tolerance_m or low_m.distance_to(high_m) <= tolerance_m:
			return MatterUtilsScript.success({
				"hit": true,
				"position_m": middle_m,
				"distance_m": origin_m.distance_to(middle_m),
				"sample": middle_sample,
				"step_count": step_count,
			})
		if low_sdf_m * middle_sdf_m <= 0.0:
			high_m = middle_m
		else:
			low_m = middle_m
			low_sdf_m = middle_sdf_m
	return MatterUtilsScript.failure("CONTINUOUS_MATTER_RAY_REFINE_FAILED")


func _sample_for_operation(
	local_position_m: Vector3,
	level: int,
	snapshot_cache_by_address_id: Dictionary
) -> Dictionary:
	var cell_address: Dictionary = CellGridScript.address_for_position(
		_grid_profile, local_position_m, level
	)
	if cell_address.is_empty():
		return {}
	var brick_address: Dictionary = BrickLayoutScript.brick_address(_grid_profile, cell_address)
	if _store.has(brick_address):
		var address_id: String = String(brick_address["address_id"])
		if not snapshot_cache_by_address_id.has(address_id):
			var snapshot: Dictionary = _store.get_snapshot(brick_address)
			if not bool(SnapshotScript.validate(snapshot).get("success", false)):
				return {}
			snapshot_cache_by_address_id[address_id] = snapshot
		return SnapshotSamplerScript.sample_continuous_validated(
			snapshot_cache_by_address_id[address_id], _grid_profile, local_position_m
		)
	return GeneratorScript.sample_validated(
		_material_catalog, _generator_profile, _feature_catalog, local_position_m
	)


func _finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
