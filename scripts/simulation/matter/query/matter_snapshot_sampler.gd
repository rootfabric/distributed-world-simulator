extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const SnapshotScript = preload("res://scripts/simulation/matter/contracts/matter_brick_snapshot.gd")
const CompositionScript = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const SampleScript = preload("res://scripts/simulation/matter/contracts/matter_sample.gd")
const CellGridScript = preload("res://scripts/simulation/matter/spatial/matter_cell_grid.gd")
const BrickLayoutScript = preload("res://scripts/simulation/matter/spatial/matter_brick_layout.gd")


static func sample_continuous(
	snapshot: Dictionary,
	grid_profile: Dictionary,
	local_position_m: Vector3
) -> Dictionary:
	if not bool(SnapshotScript.validate(snapshot).get("success", false)) \
		or not _finite_vector(local_position_m):
		return {}
	return sample_continuous_validated(snapshot, grid_profile, local_position_m)


# The snapshot must be validated once by the caller. This is used by raycasts,
# where repeatedly validating the same 1331-sample brick dominates runtime.
static func sample_continuous_validated(
	snapshot: Dictionary,
	grid_profile: Dictionary,
	local_position_m: Vector3
) -> Dictionary:
	if not _finite_vector(local_position_m):
		return {}
	var cell_address: Dictionary = snapshot["address"]["cell_address"]
	var cell_bounds: Dictionary = CellGridScript.bounds(grid_profile, cell_address)
	if cell_bounds.is_empty() or not CellGridScript.contains_position(
		grid_profile, cell_address, local_position_m
	):
		return {}
	var minimum_m: Vector3 = _vector3(cell_bounds["minimum_m"])
	var resolution: int = int(grid_profile["brick_interior_resolution"])
	var ghost: int = int(grid_profile["ghost_border_samples"])
	var spacing_m: float = float(cell_bounds["edge_length_m"]) / float(resolution)
	var logical: Vector3 = (local_position_m - minimum_m) / spacing_m
	var cell_x: int = clampi(int(floor(logical.x)), 0, resolution - 1)
	var cell_y: int = clampi(int(floor(logical.y)), 0, resolution - 1)
	var cell_z: int = clampi(int(floor(logical.z)), 0, resolution - 1)
	var fraction: Vector3 = Vector3(
		clampf(logical.x - float(cell_x), 0.0, 1.0),
		clampf(logical.y - float(cell_y), 0.0, 1.0),
		clampf(logical.z - float(cell_z), 0.0, 1.0)
	)
	var signed_distance_m: float = 0.0
	var occupancy_ratio: float = 0.0
	var density_kg_m3: float = 0.0
	var integrity_ratio: float = 0.0
	var temperature_k: float = 0.0
	var porosity_ratio: float = 0.0
	var material_weights: Dictionary = {}
	var flags: Array = []
	for corner_z in range(2):
		for corner_y in range(2):
			for corner_x in range(2):
				var weight: float = _corner_weight(corner_x, corner_y, corner_z, fraction)
				var index: int = BrickLayoutScript.flat_index(
					grid_profile,
					ghost + cell_x + corner_x,
					ghost + cell_y + corner_y,
					ghost + cell_z + corner_z
				)
				var sample: Dictionary = SnapshotScript.sample_payload_at_validated(snapshot, index)
				if sample.is_empty():
					return {}
				signed_distance_m += weight * float(sample["signed_distance_m"])
				occupancy_ratio += weight * float(sample["occupancy_ratio"])
				density_kg_m3 += weight * float(sample["density_kg_m3"])
				integrity_ratio += weight * float(sample["integrity_ratio"])
				temperature_k += weight * float(sample["temperature_k"])
				porosity_ratio += weight * float(sample["porosity_ratio"])
				for flag in sample["flags"]:
					flags.append(String(flag))
				var matter_weight: float = weight * float(sample["density_kg_m3"]) \
					* float(sample["occupancy_ratio"])
				for component in sample["composition"]["components"]:
					var material_id: String = String(component["material_id"])
					material_weights[material_id] = float(material_weights.get(material_id, 0.0)) \
						+ matter_weight * float(component["mass_fraction"])
	if signed_distance_m >= 0.0 or material_weights.is_empty() or density_kg_m3 <= 0.0:
		return SampleScript.vacuum(maxf(signed_distance_m, 0.0), temperature_k)
	var composition: Dictionary = CompositionScript.from_weights(material_weights)
	if composition.is_empty():
		return {}
	var occupied_flags: Array = MatterUtilsScript.sorted_unique_ids(flags)
	occupied_flags.erase("matter-state/vacuum")
	return SampleScript.create(
		signed_distance_m,
		clampf(maxf(occupancy_ratio, 0.000001), 0.0, 1.0),
		density_kg_m3,
		composition,
		clampf(integrity_ratio, 0.0, 1.0),
		maxf(temperature_k, 0.0),
		clampf(porosity_ratio, 0.0, 1.0),
		occupied_flags
	)


static func _corner_weight(x: int, y: int, z: int, fraction: Vector3) -> float:
	var weight_x: float = fraction.x if x == 1 else 1.0 - fraction.x
	var weight_y: float = fraction.y if y == 1 else 1.0 - fraction.y
	var weight_z: float = fraction.z if z == 1 else 1.0 - fraction.z
	return weight_x * weight_y * weight_z


static func _finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


static func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
