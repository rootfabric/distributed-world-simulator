extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const SnapshotScript = preload("res://scripts/simulation/matter/contracts/matter_brick_snapshot.gd")
const SampleScript = preload("res://scripts/simulation/matter/contracts/matter_sample.gd")
const GridProfileScript = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const CellGridScript = preload("res://scripts/simulation/matter/spatial/matter_cell_grid.gd")
const BrickLayoutScript = preload("res://scripts/simulation/matter/spatial/matter_brick_layout.gd")
const SweptShapeScript = preload("res://scripts/simulation/matter/mutation/matter_swept_shape.gd")

const SDF_CHANGE_EPSILON_M: float = 0.000000001
const MASS_EPSILON_KG: float = 0.000001


static func apply_excavation(
	snapshot: Dictionary,
	grid_profile: Dictionary,
	shape: Dictionary
) -> Dictionary:
	if not bool(SnapshotScript.validate(snapshot).get("success", false)) \
		or not bool(GridProfileScript.validate(grid_profile).get("success", false)) \
		or SweptShapeScript.bounds_m(shape).is_empty():
		return MatterUtilsScript.failure("INVALID_MATTER_EXCAVATION_KERNEL_INPUT")
	var address: Dictionary = snapshot["address"]
	if not bool(BrickLayoutScript.validate_brick_address(grid_profile, address).get("success", false)):
		return MatterUtilsScript.failure("MATTER_EXCAVATION_BRICK_GRID_MISMATCH")
	var cell_address: Dictionary = address["cell_address"]
	var mutation_band_m: float = SweptShapeScript.mutation_band_m(
		grid_profile, cell_address
	)
	if not MatterUtilsScript.is_positive_number(mutation_band_m):
		return MatterUtilsScript.failure("INVALID_MATTER_EXCAVATION_MUTATION_BAND")
	var samples_before: Array = []
	var samples_after: Array = []
	var changed: bool = false
	var cell_bounds: Dictionary = CellGridScript.bounds_validated(grid_profile, cell_address)
	var axis_count: int = BrickLayoutScript.sample_axis_count(grid_profile)
	if cell_bounds.is_empty() or axis_count < 1:
		return MatterUtilsScript.failure("MATTER_EXCAVATION_CELL_BOUNDS_FAILED")
	for z in range(axis_count):
		for y in range(axis_count):
			for x in range(axis_count):
				var index: int = BrickLayoutScript.flat_index(grid_profile, x, y, z)
				var old_sample: Dictionary = SnapshotScript.sample_payload_at_validated(
					snapshot, index
				)
				if old_sample.is_empty():
					return MatterUtilsScript.failure(
						"MATTER_EXCAVATION_SAMPLE_READ_FAILED", {"index": index}
					)
				samples_before.append(old_sample)
				var new_sample: Dictionary = old_sample
				if float(old_sample["occupancy_ratio"]) > 0.0:
					var position_m: Vector3 = BrickLayoutScript.sample_position_validated(
						grid_profile, cell_bounds, x, y, z
					)
					var tool_sdf_m: float = SweptShapeScript.signed_distance_validated(
						shape, position_m
					)
					if tool_sdf_m <= mutation_band_m:
						var old_sdf_m: float = float(old_sample["signed_distance_m"])
						var new_sdf_m: float = maxf(old_sdf_m, -tool_sdf_m)
						if new_sdf_m > old_sdf_m + SDF_CHANGE_EPSILON_M:
							changed = true
							if new_sdf_m >= 0.0:
								new_sample = SampleScript.vacuum(
									new_sdf_m, float(old_sample["temperature_k"])
								)
							else:
								var flags: Array = Array(old_sample["flags"]).duplicate()
								flags.append("matter-state/excavated-boundary")
								new_sample = SampleScript.create(
									new_sdf_m,
									float(old_sample["occupancy_ratio"]),
									float(old_sample["density_kg_m3"]),
									Dictionary(old_sample["composition"]),
									float(old_sample["integrity_ratio"]),
									float(old_sample["temperature_k"]),
									float(old_sample["porosity_ratio"]),
									MatterUtilsScript.sorted_unique_ids(flags)
								)
				samples_after.append(new_sample)
	if not changed:
		return MatterUtilsScript.success({
			"changed": false,
			"snapshot": snapshot.duplicate(true),
			"removed_mass_kg": 0.0,
			"removed_volume_m3": 0.0,
			"material_mass_kg": {},
			"mass_weighted_temperature_k": 0.0,
		})
	var estimate: Dictionary = _estimate_removed_materials(
		samples_before, samples_after, grid_profile, cell_address
	)
	var new_revision: int = int(snapshot["state_revision"]) + 1
	var snapshot_id: String = "matter-snapshot/%s/revision/%d" % [
		String(address["address_id"]).sha256_text(),
		new_revision,
	]
	var new_snapshot: Dictionary = SnapshotScript.create(
		snapshot_id,
		address,
		String(snapshot["body_definition_hash"]),
		String(snapshot["generator_version"]),
		int(snapshot["generator_seed"]),
		new_revision,
		samples_after
	)
	if not bool(SnapshotScript.validate(new_snapshot).get("success", false)):
		return MatterUtilsScript.failure("MATTER_EXCAVATION_SNAPSHOT_BUILD_FAILED")
	return MatterUtilsScript.success({
		"changed": true,
		"snapshot": new_snapshot,
		"removed_mass_kg": float(estimate["removed_mass_kg"]),
		"removed_volume_m3": float(estimate["removed_volume_m3"]),
		"material_mass_kg": Dictionary(estimate["material_mass_kg"]).duplicate(true),
		"mass_weighted_temperature_k": float(estimate["mass_weighted_temperature_k"]),
	})


static func _estimate_removed_materials(
	samples_before: Array,
	samples_after: Array,
	grid_profile: Dictionary,
	cell_address: Dictionary
) -> Dictionary:
	var spacing_m: float = BrickLayoutScript.sample_spacing_m(grid_profile, cell_address)
	var cube_volume_m3: float = spacing_m * spacing_m * spacing_m
	var minimum_index: int = BrickLayoutScript.interior_min_index(grid_profile)
	var maximum_index: int = BrickLayoutScript.interior_max_index(grid_profile)
	var material_mass_kg: Dictionary = {}
	var removed_volume_m3: float = 0.0
	var mass_weighted_temperature_k: float = 0.0
	for z in range(minimum_index, maximum_index):
		for y in range(minimum_index, maximum_index):
			for x in range(minimum_index, maximum_index):
				for corner_z in range(2):
					for corner_y in range(2):
						for corner_x in range(2):
							var index: int = BrickLayoutScript.flat_index(
								grid_profile, x + corner_x, y + corner_y, z + corner_z
							)
							var before: Dictionary = samples_before[index]
							var after: Dictionary = samples_after[index]
							var removed_fraction: float = maxf(
								_solid_fraction(before, spacing_m) - _solid_fraction(after, spacing_m),
								0.0
							)
							if removed_fraction <= 0.0:
								continue
							var volume_m3: float = cube_volume_m3 * removed_fraction / 8.0
							var mass_kg: float = volume_m3 * float(before["density_kg_m3"])
							if mass_kg <= MASS_EPSILON_KG:
								continue
							removed_volume_m3 += volume_m3
							mass_weighted_temperature_k += mass_kg * float(before["temperature_k"])
							for component in before["composition"]["components"]:
								var material_id: String = String(component["material_id"])
								var component_mass_kg: float = mass_kg * float(component["mass_fraction"])
								material_mass_kg[material_id] = float(
									material_mass_kg.get(material_id, 0.0)
								) + component_mass_kg
	var material_mass_total_kg: float = 0.0
	for material_mass in material_mass_kg.values():
		material_mass_total_kg += float(material_mass)
	return {
		"removed_mass_kg": material_mass_total_kg,
		"removed_volume_m3": removed_volume_m3,
		"material_mass_kg": material_mass_kg,
		"mass_weighted_temperature_k": mass_weighted_temperature_k,
	}


static func _solid_fraction(sample: Dictionary, spacing_m: float) -> float:
	if float(sample["occupancy_ratio"]) <= 0.0:
		return 0.0
	return clampf(0.5 - float(sample["signed_distance_m"]) / spacing_m, 0.0, 1.0)
