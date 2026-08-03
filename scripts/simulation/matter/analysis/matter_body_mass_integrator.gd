extends RefCounted

const BodyScript = preload("res://scripts/simulation/matter/contracts/matter_body_definition.gd")
const MassEstimateScript = preload("res://scripts/simulation/matter/contracts/matter_body_mass_estimate.gd")
const MaterialCatalogScript = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const ProfileScript = preload("res://scripts/simulation/matter/generation/fixed_seed_asteroid_profile.gd")
const FeatureCatalogScript = preload("res://scripts/simulation/matter/generation/asteroid_feature_catalog.gd")
const GeneratorScript = preload("res://scripts/simulation/matter/generation/fixed_seed_asteroid_generator.gd")

const MIN_RESOLUTION: int = 4
const MAX_RESOLUTION: int = 128


static func integrate(
	body: Dictionary,
	material_catalog: Dictionary,
	profile: Dictionary,
	feature_catalog: Dictionary,
	resolution: int
) -> Dictionary:
	if resolution < MIN_RESOLUTION or resolution > MAX_RESOLUTION:
		return {}
	if not bool(GeneratorScript.validate_configuration(
		body, material_catalog, profile, feature_catalog
	).get("success", false)):
		return {}
	var bounds_radius_m: float = float(profile["reference_radius_m"]) \
		* float(profile["root_bounds_radius_ratio"])
	var voxel_edge_m: float = bounds_radius_m * 2.0 / float(resolution)
	var voxel_volume_m3: float = voxel_edge_m * voxel_edge_m * voxel_edge_m
	var occupied_sample_count: int = 0
	var estimated_volume_m3: float = 0.0
	var estimated_mass_kg: float = 0.0
	var weighted_center: Vector3 = Vector3.ZERO
	var material_masses: Dictionary = {}
	for z_index in range(resolution):
		var z: float = -bounds_radius_m + (float(z_index) + 0.5) * voxel_edge_m
		for y_index in range(resolution):
			var y: float = -bounds_radius_m + (float(y_index) + 0.5) * voxel_edge_m
			for x_index in range(resolution):
				var x: float = -bounds_radius_m + (float(x_index) + 0.5) * voxel_edge_m
				var position_m: Vector3 = Vector3(x, y, z)
				var sample_value: Dictionary = GeneratorScript.sample_validated(
					material_catalog,
					profile,
					feature_catalog,
					position_m
				)
				var occupancy: float = float(sample_value["occupancy_ratio"])
				if occupancy <= 0.0:
					continue
				occupied_sample_count += 1
				var occupied_volume_m3: float = voxel_volume_m3 * occupancy
				var sample_mass_kg: float = float(sample_value["density_kg_m3"]) * occupied_volume_m3
				estimated_volume_m3 += occupied_volume_m3
				estimated_mass_kg += sample_mass_kg
				weighted_center += position_m * sample_mass_kg
				for component in sample_value["composition"]["components"]:
					var material_id: String = String(component["material_id"])
					material_masses[material_id] = float(material_masses.get(material_id, 0.0)) \
						+ sample_mass_kg * float(component["mass_fraction"])
	if occupied_sample_count <= 0 or estimated_mass_kg <= 0.0:
		return {}
	var material_entries: Array = []
	var material_ids: Array = material_masses.keys()
	material_ids.sort()
	for material_id in material_ids:
		var mass_kg: float = float(material_masses[material_id])
		if mass_kg > 0.0:
			material_entries.append({
				"material_id": String(material_id),
				"mass_kg": mass_kg,
			})
	var center_of_mass_m: Vector3 = weighted_center / estimated_mass_kg
	return MassEstimateScript.create({
		"body_id": body["body_id"],
		"body_checksum": body["checksum"],
		"generator_profile_checksum": profile["checksum"],
		"feature_catalog_hash": feature_catalog["catalog_hash"],
		"sample_resolution": resolution,
		"integration_bounds_radius_m": bounds_radius_m,
		"voxel_edge_m": voxel_edge_m,
		"occupied_sample_count": occupied_sample_count,
		"estimated_volume_m3": estimated_volume_m3,
		"estimated_mass_kg": estimated_mass_kg,
		"center_of_mass_m": [center_of_mass_m.x, center_of_mass_m.y, center_of_mass_m.z],
		"material_masses": material_entries,
	})


static func relative_difference(a: float, b: float) -> float:
	var denominator: float = maxf(absf(a), absf(b))
	if denominator <= 0.0:
		return 0.0
	return absf(a - b) / denominator
