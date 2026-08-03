extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const BrickSnapshotScript = preload("res://scripts/simulation/matter/contracts/matter_brick_snapshot.gd")
const GridProfileScript = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const CellGridScript = preload("res://scripts/simulation/matter/spatial/matter_cell_grid.gd")
const BrickLayoutScript = preload("res://scripts/simulation/matter/spatial/matter_brick_layout.gd")
const GeneratorScript = preload("res://scripts/simulation/matter/generation/fixed_seed_asteroid_generator.gd")


static func materialize(
	body: Dictionary,
	material_catalog: Dictionary,
	generator_profile: Dictionary,
	feature_catalog: Dictionary,
	grid_profile: Dictionary,
	cell_address: Dictionary,
	state_revision: int = 0
) -> Dictionary:
	if not bool(GeneratorScript.validate_configuration(
		body, material_catalog, generator_profile, feature_catalog
	).get("success", false)):
		return {}
	if not bool(GridProfileScript.validate(grid_profile).get("success", false)) \
		or String(grid_profile["body_id"]) != String(body["body_id"]) \
		or String(grid_profile["body_frame_id"]) != String(body["body_frame_id"]):
		return {}
	if not bool(CellGridScript.validate_address(grid_profile, cell_address).get("success", false)) \
		or state_revision < 0:
		return {}
	var address: Dictionary = BrickLayoutScript.brick_address(grid_profile, cell_address)
	if address.is_empty():
		return {}
	var samples: Array = []
	var cell_bounds: Dictionary = CellGridScript.bounds_validated(grid_profile, cell_address)
	var axis_count: int = BrickLayoutScript.sample_axis_count(grid_profile)
	for z in range(axis_count):
		for y in range(axis_count):
			for x in range(axis_count):
				var local_position_m: Vector3 = BrickLayoutScript.sample_position_validated(
					grid_profile, cell_bounds, x, y, z
				)
				if not is_finite(local_position_m.x) or not is_finite(local_position_m.y) \
					or not is_finite(local_position_m.z):
					return {}
				samples.append(GeneratorScript.sample_validated(
					material_catalog,
					generator_profile,
					feature_catalog,
					local_position_m
				))
	var snapshot_id: String = "matter-snapshot/%s/revision/%d" % [
		String(address["address_id"]).sha256_text(),
		state_revision,
	]
	var snapshot: Dictionary = BrickSnapshotScript.create(
		snapshot_id,
		address,
		String(body["checksum"]),
		String(generator_profile["generator_version"]),
		int(generator_profile["generator_seed"]),
		state_revision,
		samples
	)
	return snapshot if bool(BrickSnapshotScript.validate(snapshot).get("success", false)) else {}


static func materialized_content_hash(snapshot: Dictionary) -> String:
	return MatterUtilsScript.payload_hash(snapshot) \
		if bool(BrickSnapshotScript.validate(snapshot).get("success", false)) else ""
