extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const BodyScript = preload("res://scripts/simulation/matter/contracts/matter_body_definition.gd")
const CompositionScript = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const SampleScript = preload("res://scripts/simulation/matter/contracts/matter_sample.gd")
const MaterialCatalogScript = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const FieldScript = preload("res://scripts/simulation/matter/generation/deterministic_field_3d.gd")
const ProfileScript = preload("res://scripts/simulation/matter/generation/fixed_seed_asteroid_profile.gd")
const FeatureCatalogScript = preload("res://scripts/simulation/matter/generation/asteroid_feature_catalog.gd")

const BODY_ID: String = "body/asteroid-mw0"
const BODY_FRAME_ID: String = "body/asteroid-mw0/fixed"
const SURFACE_SCAN_STEPS: int = 96
const SURFACE_BISECTION_STEPS: int = 36
const SURFACE_DIRECTION_EPSILON: float = 0.000000001


static func default_profile() -> Dictionary:
	return ProfileScript.default_profile()


static func default_feature_catalog(profile: Dictionary = {}) -> Dictionary:
	var effective_profile: Dictionary = profile if not profile.is_empty() else default_profile()
	return FeatureCatalogScript.create(effective_profile)


static func default_body_definition(
	profile: Dictionary = {},
	material_catalog: Dictionary = {},
	feature_catalog: Dictionary = {}
) -> Dictionary:
	var effective_profile: Dictionary = profile if not profile.is_empty() else default_profile()
	var effective_catalog: Dictionary = material_catalog if not material_catalog.is_empty() \
		else MaterialCatalogScript.default_catalog()
	var effective_features: Dictionary = feature_catalog if not feature_catalog.is_empty() \
		else default_feature_catalog(effective_profile)
	if not bool(ProfileScript.validate(effective_profile).get("success", false)) \
		or not bool(MaterialCatalogScript.validate(effective_catalog).get("success", false)) \
		or not bool(FeatureCatalogScript.validate(effective_features).get("success", false)):
		return {}
	return BodyScript.create({
		"body_id": BODY_ID,
		"body_kind": "ASTEROID",
		"body_frame_id": BODY_FRAME_ID,
		"generator_id": effective_profile["generator_id"],
		"generator_version": effective_profile["generator_version"],
		"generator_seed": effective_profile["generator_seed"],
		"reference_radius_m": effective_profile["reference_radius_m"],
		"default_material_id": "matter/basalt",
		"material_catalog_id": effective_catalog["catalog_id"],
		"material_catalog_hash": effective_catalog["catalog_hash"],
		"metadata": {
			"feature_catalog_hash": effective_features["catalog_hash"],
			"generator_profile_checksum": effective_profile["checksum"],
			"laboratory": true,
			"purpose": "mw1-fixed-seed-volumetric-asteroid",
		},
	})


static func validate_configuration(
	body: Dictionary,
	material_catalog: Dictionary,
	profile: Dictionary,
	feature_catalog: Dictionary
) -> Dictionary:
	if not bool(BodyScript.validate(body).get("success", false)):
		return MatterUtilsScript.failure("INVALID_ASTEROID_BODY_DEFINITION")
	if not bool(MaterialCatalogScript.validate(material_catalog).get("success", false)):
		return MatterUtilsScript.failure("INVALID_ASTEROID_MATERIAL_CATALOG")
	if not bool(ProfileScript.validate(profile).get("success", false)):
		return MatterUtilsScript.failure("INVALID_ASTEROID_GENERATOR_PROFILE")
	if not bool(FeatureCatalogScript.validate(feature_catalog).get("success", false)):
		return MatterUtilsScript.failure("INVALID_ASTEROID_FEATURE_CATALOG")
	if String(body["body_id"]) != BODY_ID or String(body["body_frame_id"]) != BODY_FRAME_ID:
		return MatterUtilsScript.failure("ASTEROID_BODY_IDENTITY_MISMATCH")
	for field in ["generator_id", "generator_version", "generator_seed", "reference_radius_m"]:
		if body[field] != profile[field]:
			return MatterUtilsScript.failure("ASTEROID_PROFILE_BODY_MISMATCH", {"field": field})
	if String(body["material_catalog_id"]) != String(material_catalog["catalog_id"]) \
		or String(body["material_catalog_hash"]) != String(material_catalog["catalog_hash"]):
		return MatterUtilsScript.failure("ASTEROID_BODY_CATALOG_MISMATCH")
	if int(feature_catalog["generator_seed"]) != int(profile["generator_seed"]) \
		or String(feature_catalog["generator_version"]) != String(profile["generator_version"]):
		return MatterUtilsScript.failure("ASTEROID_FEATURE_PROFILE_MISMATCH")
	var metadata: Dictionary = body["metadata"]
	if String(metadata.get("generator_profile_checksum", "")) != String(profile["checksum"]):
		return MatterUtilsScript.failure("ASTEROID_PROFILE_CHECKSUM_MISMATCH")
	if String(metadata.get("feature_catalog_hash", "")) != String(feature_catalog["catalog_hash"]):
		return MatterUtilsScript.failure("ASTEROID_FEATURE_HASH_MISMATCH")
	return MatterUtilsScript.success()


static func sample(
	body: Dictionary,
	material_catalog: Dictionary,
	profile: Dictionary,
	feature_catalog: Dictionary,
	local_position_m: Vector3
) -> Dictionary:
	if not bool(validate_configuration(body, material_catalog, profile, feature_catalog).get("success", false)):
		return {}
	return sample_validated(material_catalog, profile, feature_catalog, local_position_m)


static func sample_validated(
	material_catalog: Dictionary,
	profile: Dictionary,
	feature_catalog: Dictionary,
	local_position_m: Vector3
) -> Dictionary:
	var signed_distance: float = signed_distance_validated(profile, feature_catalog, local_position_m)
	if signed_distance > 0.0:
		return SampleScript.vacuum(signed_distance, float(profile["vacuum_temperature_k"]))
	# Geological depth follows the solid envelope before enclosed natural voids
	# are subtracted. Cave walls therefore retain deep host-rock geology instead
	# of being misclassified as external regolith. The query remains O(1).
	var envelope_distance: float = solid_envelope_signed_distance_validated(
		profile, feature_catalog, local_position_m
	)
	var depth_m: float = maxf(-envelope_distance, 0.0)
	var geological: Dictionary = _geological_properties(
		material_catalog,
		profile,
		feature_catalog,
		local_position_m,
		depth_m
	)
	return SampleScript.create(
		signed_distance,
		1.0,
		float(geological["density_kg_m3"]),
		geological["composition"],
		float(geological["integrity_ratio"]),
		float(geological["temperature_k"]),
		float(geological["porosity_ratio"]),
		geological["flags"]
	)


static func signed_distance_m(
	body: Dictionary,
	profile: Dictionary,
	feature_catalog: Dictionary,
	local_position_m: Vector3
) -> float:
	if not bool(BodyScript.validate(body).get("success", false)) \
		or not bool(ProfileScript.validate(profile).get("success", false)) \
		or not bool(FeatureCatalogScript.validate(feature_catalog).get("success", false)):
		return INF
	for field in ["generator_id", "generator_version", "generator_seed", "reference_radius_m"]:
		if body[field] != profile[field]:
			return INF
	if int(feature_catalog["generator_seed"]) != int(profile["generator_seed"]) \
		or String(feature_catalog["generator_version"]) != String(profile["generator_version"]):
		return INF
	return signed_distance_validated(profile, feature_catalog, local_position_m)


static func signed_distance_validated(
	profile: Dictionary,
	feature_catalog: Dictionary,
	local_position_m: Vector3
) -> float:
	var result: float = solid_envelope_signed_distance_validated(
		profile, feature_catalog, local_position_m
	)
	for feature in feature_catalog["features"]:
		if String(feature["feature_kind"]) != "NATURAL_VOID":
			continue
		var feature_distance: float = _ellipsoid_signed_distance(
			local_position_m,
			_vector3(feature["center_m"]),
			_vector3(feature["radii_m"])
		)
		result = maxf(result, -feature_distance)
	return result


static func solid_envelope_signed_distance_validated(
	profile: Dictionary,
	feature_catalog: Dictionary,
	local_position_m: Vector3
) -> float:
	var radius: float = float(profile["reference_radius_m"])
	var axis: Vector3 = _vector3(profile["axis_scale"])
	var base_radii: Vector3 = axis * radius
	var result: float = _ellipsoid_signed_distance(local_position_m, Vector3.ZERO, base_radii)
	var direction: Vector3 = _safe_direction(local_position_m)
	var directional_position: Vector3 = direction * radius
	var frequencies: Array = profile["surface_noise_frequencies_per_m"]
	var amplitudes: Array = profile["surface_noise_amplitudes_m"]
	var seed: int = int(profile["generator_seed"])
	var displacement_m: float = 0.0
	for index in range(frequencies.size()):
		displacement_m += FieldScript.value_noise_3d(
			directional_position,
			float(frequencies[index]),
			seed,
			1000 + index * 97
		) * float(amplitudes[index])
	result -= displacement_m
	for feature in feature_catalog["features"]:
		var kind: String = String(feature["feature_kind"])
		if kind not in ["ADD_LOBE", "IMPACT_CRATER"]:
			continue
		var feature_distance: float = _ellipsoid_signed_distance(
			local_position_m,
			_vector3(feature["center_m"]),
			_vector3(feature["radii_m"])
		)
		if kind == "ADD_LOBE":
			result = minf(result, feature_distance)
		else:
			result = maxf(result, -feature_distance)
	return result


static func surface_radius_m(
	body: Dictionary,
	profile: Dictionary,
	feature_catalog: Dictionary,
	direction: Vector3
) -> float:
	if not bool(BodyScript.validate(body).get("success", false)) \
		or not bool(ProfileScript.validate(profile).get("success", false)) \
		or not bool(FeatureCatalogScript.validate(feature_catalog).get("success", false)):
		return 0.0
	for field in ["generator_id", "generator_version", "generator_seed", "reference_radius_m"]:
		if body[field] != profile[field]:
			return 0.0
	if int(feature_catalog["generator_seed"]) != int(profile["generator_seed"]):
		return 0.0
	return surface_radius_validated(profile, feature_catalog, direction)


static func surface_radius_validated(
	profile: Dictionary,
	feature_catalog: Dictionary,
	direction: Vector3
) -> float:
	var normalized_direction: Vector3 = _safe_direction(direction)
	var bound: float = float(profile["reference_radius_m"]) \
		* float(profile["root_bounds_radius_ratio"])
	var outside_radius: float = bound
	var outside_distance: float = signed_distance_validated(
		profile, feature_catalog, normalized_direction * outside_radius
	)
	if outside_distance <= 0.0:
		return bound
	for step in range(1, SURFACE_SCAN_STEPS + 1):
		var inside_radius: float = bound * (1.0 - float(step) / float(SURFACE_SCAN_STEPS))
		var inside_distance: float = signed_distance_validated(
			profile, feature_catalog, normalized_direction * inside_radius
		)
		if inside_distance <= 0.0:
			var low: float = inside_radius
			var high: float = outside_radius
			for _iteration in range(SURFACE_BISECTION_STEPS):
				var middle: float = (low + high) * 0.5
				var middle_distance: float = signed_distance_validated(
					profile, feature_catalog, normalized_direction * middle
				)
				if middle_distance <= 0.0:
					low = middle
				else:
					high = middle
			return (low + high) * 0.5
		outside_radius = inside_radius
		outside_distance = inside_distance
	return 0.0


static func control_points_m(profile: Dictionary, feature_catalog: Dictionary) -> Array:
	if not bool(ProfileScript.validate(profile).get("success", false)) \
		or not bool(FeatureCatalogScript.validate(feature_catalog).get("success", false)):
		return []
	var radius: float = float(profile["reference_radius_m"])
	var points: Array = [
		Vector3.ZERO,
		Vector3(radius * 0.5, 0.0, 0.0),
		Vector3(-radius * 0.5, 0.0, 0.0),
		Vector3(0.0, radius * 0.5, 0.0),
		Vector3(0.0, -radius * 0.5, 0.0),
		Vector3(0.0, 0.0, radius * 0.5),
		Vector3(0.0, 0.0, -radius * 0.5),
		Vector3(radius * 1.4, 0.0, 0.0),
		Vector3(-radius * 1.4, 0.0, 0.0),
	]
	for feature in feature_catalog["features"]:
		points.append(_vector3(feature["center_m"]))
	var seed: int = int(profile["generator_seed"])
	var bound: float = radius * float(profile["root_bounds_radius_ratio"])
	var index: int = 0
	while points.size() < 128:
		points.append(Vector3(
			FieldScript.signed_hash(index, 0, 0, seed, 3000) * bound,
			FieldScript.signed_hash(index, 0, 0, seed, 3001) * bound,
			FieldScript.signed_hash(index, 0, 0, seed, 3002) * bound
		))
		index += 1
	return points


static func control_fixture_hash(
	material_catalog: Dictionary,
	profile: Dictionary,
	feature_catalog: Dictionary
) -> String:
	if not bool(MaterialCatalogScript.validate(material_catalog).get("success", false)) \
		or not bool(ProfileScript.validate(profile).get("success", false)) \
		or not bool(FeatureCatalogScript.validate(feature_catalog).get("success", false)):
		return ""
	var signatures: Array = []
	for point_value in control_points_m(profile, feature_catalog):
		var point: Vector3 = point_value
		var sample_value: Dictionary = sample_validated(material_catalog, profile, feature_catalog, point)
		signatures.append({
			"position_cm": [
				int(round(point.x * 100.0)),
				int(round(point.y * 100.0)),
				int(round(point.z * 100.0)),
			],
			"sample": quantized_sample_signature(sample_value),
		})
	return MatterUtilsScript.payload_hash(signatures)


static func quantized_sample_signature(sample_value: Dictionary) -> Dictionary:
	if not bool(SampleScript.validate(sample_value).get("success", false)):
		return {}
	var components: Array = []
	for component in sample_value["composition"]["components"]:
		components.append({
			"material_id": String(component["material_id"]),
			"mass_fraction_ppm": int(round(float(component["mass_fraction"]) * 1000000.0)),
		})
	return {
		"signed_distance_cm": int(round(float(sample_value["signed_distance_m"]) * 100.0)),
		"occupancy_ppm": int(round(float(sample_value["occupancy_ratio"]) * 1000000.0)),
		"density_kg_m3": int(round(float(sample_value["density_kg_m3"]))),
		"integrity_ppm": int(round(float(sample_value["integrity_ratio"]) * 1000000.0)),
		"temperature_mk": int(round(float(sample_value["temperature_k"]) * 1000.0)),
		"porosity_ppm": int(round(float(sample_value["porosity_ratio"]) * 1000000.0)),
		"composition": components,
		"flags": Array(sample_value["flags"]).duplicate(),
	}


static func _geological_properties(
	material_catalog: Dictionary,
	profile: Dictionary,
	feature_catalog: Dictionary,
	local_position_m: Vector3,
	depth_m: float
) -> Dictionary:
	var weights: Dictionary = {}
	var flags: Array = ["matter-state/bonded"]
	var base_porosity: float = 0.045
	var base_integrity: float = 0.96
	if depth_m <= float(profile["surface_regolith_depth_m"]):
		weights = {
			"matter/regolith-compacted": 0.72,
			"matter/fractured-basalt": 0.28,
		}
		base_porosity = 0.24
		base_integrity = 0.48
		flags.append("matter-zone/surface-shell")
	elif depth_m <= float(profile["fractured_shell_depth_m"]):
		weights = {
			"matter/fractured-basalt": 0.82,
			"matter/basalt": 0.18,
		}
		base_porosity = 0.15
		base_integrity = 0.7
		flags.append("matter-zone/fractured-shell")
	else:
		weights = {"matter/basalt": 1.0}
		flags.append("matter-zone/interior")
	var ore_fraction: float = 0.0
	var ice_fraction: float = 0.0
	for feature in feature_catalog["features"]:
		var kind: String = String(feature["feature_kind"])
		if kind not in ["ORE_LENS", "ICE_POCKET"]:
			continue
		var influence: float = _ellipsoid_influence(
			local_position_m,
			_vector3(feature["center_m"]),
			_vector3(feature["radii_m"])
		)
		if influence <= 0.0:
			continue
		var channel: int = 4100 if kind == "ORE_LENS" else 4200
		var modulation: float = 0.82 + 0.18 * FieldScript.value_noise_3d(
			local_position_m,
			0.0065,
			int(profile["generator_seed"]),
			channel
		)
		var fraction: float = clampf(
			influence * float(feature["influence_ratio"]) * modulation,
			0.0,
			float(feature["influence_ratio"])
		)
		if kind == "ORE_LENS":
			ore_fraction = maxf(ore_fraction, fraction)
		else:
			ice_fraction = maxf(ice_fraction, fraction)
	var resource_total: float = minf(ore_fraction + ice_fraction, 0.82)
	var base_scale: float = 1.0 - resource_total
	for material_id in weights.keys():
		weights[material_id] = float(weights[material_id]) * base_scale
	if ore_fraction > 0.0:
		weights["matter/iron-nickel-ore"] = ore_fraction
		flags.append("matter-resource/iron-nickel")
	if ice_fraction > 0.0:
		weights["matter/water-ice"] = ice_fraction
		flags.append("matter-resource/water-ice")
	var composition: Dictionary = CompositionScript.from_weights(weights)
	var porosity_noise: float = FieldScript.value_noise_3d(
		local_position_m,
		0.0042,
		int(profile["generator_seed"]),
		4300
	)
	var porosity: float = clampf(base_porosity + porosity_noise * 0.025, 0.01, 0.42)
	var density: float = _bulk_density_kg_m3(material_catalog, composition, porosity)
	var integrity: float = clampf(base_integrity - porosity * 0.18 + ore_fraction * 0.08, 0.1, 1.0)
	var thermal_depth_ratio: float = clampf(
		depth_m / maxf(float(profile["reference_radius_m"]) * 0.55, 1.0),
		0.0,
		1.0
	)
	var temperature: float = lerpf(
		float(profile["surface_temperature_k"]),
		float(profile["interior_temperature_k"]),
		thermal_depth_ratio
	)
	return {
		"composition": composition,
		"density_kg_m3": density,
		"integrity_ratio": integrity,
		"temperature_k": temperature,
		"porosity_ratio": porosity,
		"flags": MatterUtilsScript.sorted_unique_ids(flags),
	}


static func _bulk_density_kg_m3(
	material_catalog: Dictionary,
	composition: Dictionary,
	porosity_ratio: float
) -> float:
	var materials_by_id: Dictionary = {}
	for material in material_catalog["materials"]:
		materials_by_id[String(material["material_id"])] = material
	var specific_volume: float = 0.0
	for component in composition["components"]:
		var material_id: String = String(component["material_id"])
		if not materials_by_id.has(material_id):
			return 0.0
		var material: Dictionary = materials_by_id[material_id]
		specific_volume += float(component["mass_fraction"]) / float(material["density_kg_m3"])
	if specific_volume <= 0.0:
		return 0.0
	return (1.0 / specific_volume) * (1.0 - porosity_ratio)


static func _ellipsoid_signed_distance(position_m: Vector3, center_m: Vector3, radii_m: Vector3) -> float:
	var local: Vector3 = position_m - center_m
	var scaled: Vector3 = Vector3(
		local.x / radii_m.x,
		local.y / radii_m.y,
		local.z / radii_m.z
	)
	return (scaled.length() - 1.0) * minf(radii_m.x, minf(radii_m.y, radii_m.z))


static func _ellipsoid_influence(position_m: Vector3, center_m: Vector3, radii_m: Vector3) -> float:
	var local: Vector3 = position_m - center_m
	var normalized_distance: float = Vector3(
		local.x / radii_m.x,
		local.y / radii_m.y,
		local.z / radii_m.z
	).length()
	var raw: float = clampf(1.0 - normalized_distance, 0.0, 1.0)
	return raw * raw * (3.0 - 2.0 * raw)


static func _safe_direction(value: Vector3) -> Vector3:
	if value.length_squared() <= SURFACE_DIRECTION_EPSILON:
		return Vector3.RIGHT
	return value.normalized()


static func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
