extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const BrickSnapshotScript = preload("res://scripts/simulation/matter/contracts/matter_brick_snapshot.gd")
const GridProfileScript = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const CellGridScript = preload("res://scripts/simulation/matter/spatial/matter_cell_grid.gd")
const BrickLayoutScript = preload("res://scripts/simulation/matter/spatial/matter_brick_layout.gd")
const MaterializerScript = preload("res://scripts/simulation/matter/storage/matter_brick_materializer.gd")
const SparseStoreScript = preload("res://scripts/simulation/matter/storage/matter_sparse_brick_store.gd")
const QueryResultScript = preload("res://scripts/simulation/matter/query/matter_query_result.gd")
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
	grid_profile: Dictionary
) -> Dictionary:
	var generator_validation: Dictionary = GeneratorScript.validate_configuration(
		body, material_catalog, generator_profile, feature_catalog
	)
	if not bool(generator_validation.get("success", false)):
		return generator_validation
	if not bool(GridProfileScript.validate(grid_profile).get("success", false)):
		return MatterUtilsScript.failure("INVALID_QUERY_GRID_PROFILE")
	if String(grid_profile["body_id"]) != String(body["body_id"]) \
		or String(grid_profile["body_frame_id"]) != String(body["body_frame_id"]):
		return MatterUtilsScript.failure("QUERY_GRID_BODY_MISMATCH")
	var required_root_radius_m: float = GeneratorScript.required_root_bounds_radius_m(
		generator_profile, feature_catalog
	)
	var root_center: Array = grid_profile["root_center_m"]
	var maximum_center_offset_m: float = maxf(
		absf(float(root_center[0])),
		maxf(absf(float(root_center[1])), absf(float(root_center[2])))
	)
	var required_half_extent_m: float = required_root_radius_m + maximum_center_offset_m
	if float(grid_profile["root_half_extent_m"]) + MatterUtilsScript.DEFAULT_FLOAT_TOLERANCE \
		< required_half_extent_m:
		return MatterUtilsScript.failure("QUERY_GRID_DOES_NOT_CONTAIN_BODY", {
			"grid_root_half_extent_m": float(grid_profile["root_half_extent_m"]),
			"required_root_radius_m": required_root_radius_m,
			"maximum_center_offset_m": maximum_center_offset_m,
			"required_half_extent_m": required_half_extent_m,
		})
	_body = body.duplicate(true)
	_material_catalog = material_catalog.duplicate(true)
	_generator_profile = generator_profile.duplicate(true)
	_feature_catalog = feature_catalog.duplicate(true)
	_grid_profile = grid_profile.duplicate(true)
	_store = SparseStoreScript.new()
	var store_result: Dictionary = _store.configure(_body, _grid_profile)
	if not bool(store_result.get("success", false)):
		_store = null
		return store_result
	_configured = true
	return MatterUtilsScript.success()


func materialize_cell(cell_address: Dictionary, state_revision: int = 0) -> Dictionary:
	if not _configured:
		return {}
	var snapshot: Dictionary = MaterializerScript.materialize(
		_body,
		_material_catalog,
		_generator_profile,
		_feature_catalog,
		_grid_profile,
		cell_address,
		state_revision
	)
	if snapshot.is_empty():
		return {}
	var put_result: Dictionary = _store.put(snapshot)
	return snapshot if bool(put_result.get("success", false)) else {}


func query(local_position_m: Vector3, requested_level: int) -> Dictionary:
	if not _configured:
		return {}
	var cell_address: Dictionary = CellGridScript.address_for_position(
		_grid_profile, local_position_m, requested_level
	)
	if cell_address.is_empty():
		return {}
	var brick_address: Dictionary = BrickLayoutScript.brick_address(_grid_profile, cell_address)
	var lattice_index: Array = BrickLayoutScript.lattice_coordinates_for_position(
		_grid_profile, cell_address, local_position_m
	)
	if not lattice_index.is_empty() and _store.has(brick_address):
		var snapshot: Dictionary = _store.get_snapshot(brick_address)
		var flat_index: int = BrickLayoutScript.flat_index(
			_grid_profile,
			int(lattice_index[0]),
			int(lattice_index[1]),
			int(lattice_index[2])
		)
		var sample: Dictionary = BrickSnapshotScript.sample_at_validated(snapshot, flat_index)
		return _result(
			local_position_m,
			requested_level,
			"MATERIALIZED_BRICK",
			cell_address,
			brick_address,
			lattice_index,
			int(snapshot["state_revision"]),
			sample
		)
	var generated_sample: Dictionary = GeneratorScript.sample_validated(
		_material_catalog, _generator_profile, _feature_catalog, local_position_m
	)
	return _result(
		local_position_m,
		requested_level,
		"PROCEDURAL_BASE",
		cell_address,
		brick_address,
		[-1, -1, -1],
		0,
		generated_sample
	)


func query_cell_lattice(
	cell_address: Dictionary,
	x: int,
	y: int,
	z: int
) -> Dictionary:
	if not _configured \
		or not bool(CellGridScript.validate_address(_grid_profile, cell_address).get("success", false)):
		return {}
	var flat_index: int = BrickLayoutScript.flat_index(_grid_profile, x, y, z)
	if flat_index < 0:
		return {}
	var local_position_m: Vector3 = BrickLayoutScript.sample_position_m(
		_grid_profile, cell_address, x, y, z
	)
	var brick_address: Dictionary = BrickLayoutScript.brick_address(_grid_profile, cell_address)
	if _store.has(brick_address):
		var snapshot: Dictionary = _store.get_snapshot(brick_address)
		return _result(
			local_position_m,
			int(cell_address["level"]),
			"MATERIALIZED_BRICK",
			cell_address,
			brick_address,
			[x, y, z],
			int(snapshot["state_revision"]),
			BrickSnapshotScript.sample_at_validated(snapshot, flat_index)
		)
	return _result(
		local_position_m,
		int(cell_address["level"]),
		"PROCEDURAL_BASE",
		cell_address,
		brick_address,
		[-1, -1, -1],
		0,
		GeneratorScript.sample_validated(
			_material_catalog, _generator_profile, _feature_catalog, local_position_m
		)
	)


func materialized_count() -> int:
	return _store.size() if _configured else 0


func sparse_content_hash() -> String:
	return _store.content_hash() if _configured else ""


func grid_profile() -> Dictionary:
	return _grid_profile.duplicate(true) if _configured else {}


func _result(
	local_position_m: Vector3,
	requested_level: int,
	source: String,
	cell_address: Dictionary,
	brick_address: Dictionary,
	lattice_index: Array,
	state_revision: int,
	sample: Dictionary
) -> Dictionary:
	var query_payload: Dictionary = {
		"body_id": String(_body["body_id"]),
		"body_definition_hash": String(_body["checksum"]),
		"generator_version": String(_generator_profile["generator_version"]),
		"generator_seed": int(_generator_profile["generator_seed"]),
		"grid_profile_hash": GridProfileScript.content_hash(_grid_profile),
		"local_position_m": [
			local_position_m.x,
			local_position_m.y,
			local_position_m.z,
		],
		"requested_level": requested_level,
		"source": source,
		"cell_id": String(cell_address["cell_id"]),
		"state_revision": state_revision,
	}
	var value: Dictionary = QueryResultScript.create({
		"query_id": "matter-query/%s" % MatterUtilsScript.payload_hash(query_payload),
		"body_id": _body["body_id"],
		"body_frame_id": _body["body_frame_id"],
		"body_definition_hash": _body["checksum"],
		"grid_profile_hash": GridProfileScript.content_hash(_grid_profile),
		"generator_version": _generator_profile["generator_version"],
		"generator_seed": _generator_profile["generator_seed"],
		"local_position_m": local_position_m,
		"requested_level": requested_level,
		"source": source,
		"cell_address": cell_address,
		"brick_address": brick_address,
		"sample_lattice_index": lattice_index,
		"state_revision": state_revision,
		"sample": sample,
	})
	return value if bool(QueryResultScript.validate(value).get("success", false)) else {}
