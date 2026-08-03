extends RefCounted

const MaterialCatalogScript = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const GeneratorScript = preload("res://scripts/simulation/matter/generation/fixed_seed_asteroid_generator.gd")
const GridProfileScript = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const RequestScript = preload("res://scripts/simulation/matter/contracts/matter_mutation_request.gd")
const SweptShapeScript = preload("res://scripts/simulation/matter/mutation/matter_swept_shape.gd")
const SnapshotScript = preload("res://scripts/simulation/matter/contracts/matter_brick_snapshot.gd")
const BrickLayoutScript = preload("res://scripts/simulation/matter/spatial/matter_brick_layout.gd")
const QueryScript = preload("res://scripts/simulation/matter/query/matter_continuous_query_service.gd")
const ServiceScript = preload("res://scripts/simulation/matter/mutation/matter_excavation_service.gd")
const RepositoryScript = preload("res://scripts/simulation/matter/persistence/matter_state_repository.gd")
const CoordinatorScript = preload("res://scripts/simulation/matter/persistence/matter_state_coordinator.gd")

const JSON_SAFE_ENERGY_BUDGET_J: float = 9000000000000000.0
const CELL_LEVEL: int = 5
const CONTAINER_ID: String = "container/mw5-persistence"
const MAXIMUM_MASS_KG: float = 9000000000000000.0
const MAXIMUM_VOLUME_M3: float = 1000000000000.0


static func create_context(repository_root: String) -> Dictionary:
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
	var service = ServiceScript.new()
	var service_configuration: Dictionary = service.configure(
		body,
		material_catalog,
		generator_profile,
		feature_catalog,
		grid_profile,
		CELL_LEVEL,
		CONTAINER_ID,
		MAXIMUM_MASS_KG,
		MAXIMUM_VOLUME_M3
	)
	if not bool(service_configuration.get("success", false)):
		return {"success": false, "error_code": service_configuration.get("error_code", "SERVICE_CONFIGURE_FAILED")}
	var repository = RepositoryScript.new()
	var repository_configuration: Dictionary = repository.configure(repository_root)
	if not bool(repository_configuration.get("success", false)):
		return {"success": false, "error_code": repository_configuration.get("error_code", "REPOSITORY_CONFIGURE_FAILED")}
	var coordinator = CoordinatorScript.new()
	var coordinator_configuration: Dictionary = coordinator.configure(
		body,
		grid_profile,
		CELL_LEVEL,
		service.snapshot_store(),
		service.material_receiver(),
		service.mutation_journal(),
		repository
	)
	if not bool(coordinator_configuration.get("success", false)):
		return {"success": false, "error_code": coordinator_configuration.get("error_code", "COORDINATOR_CONFIGURE_FAILED")}
	return {
		"success": true,
		"material_catalog": material_catalog,
		"generator_profile": generator_profile,
		"feature_catalog": feature_catalog,
		"body": body,
		"grid_profile": grid_profile,
		"service": service,
		"repository": repository,
		"coordinator": coordinator,
	}


static func single_cell_fixture(generator_profile: Dictionary, feature_catalog: Dictionary, grid_profile: Dictionary) -> Dictionary:
	for y_step in range(-4, 5):
		for z_step in range(-4, 5):
			var direction := Vector3(1.0, float(y_step) * 0.035, float(z_step) * 0.035).normalized()
			var radius_m: float = GeneratorScript.surface_radius_validated(
				generator_profile, feature_catalog, direction
			)
			var surface_m: Vector3 = direction * radius_m
			var start_m: Vector3 = surface_m + direction * 7.0
			var end_m: Vector3 = surface_m - direction * 14.0
			var shape: Dictionary = RequestScript.create_shape(
				"CAPSULE", _array(start_m), _array(end_m), 6.0
			)
			var targets: Array = SweptShapeScript.affected_brick_addresses(
				grid_profile, shape, CELL_LEVEL
			)
			if targets.size() == 1:
				return {
					"start_m": start_m,
					"end_m": end_m,
					"center_m": (start_m + end_m) * 0.5,
					"radius_m": 6.0,
					"address": targets[0],
				}
	return {}


static func find_excavation_witness(context: Dictionary, result: Dictionary) -> Dictionary:
	if not bool(context.get("success", false)) \
			or String(result.get("status", "")) != "COMMITTED" \
			or typeof(result.get("changed_bricks")) != TYPE_ARRAY:
		return {}
	var service = context["service"]
	var query = QueryScript.new()
	var query_configuration: Dictionary = query.configure(
		context["body"],
		context["material_catalog"],
		context["generator_profile"],
		context["feature_catalog"],
		context["grid_profile"],
		service.snapshot_store()
	)
	if not bool(query_configuration.get("success", false)):
		return {}
	var grid_profile: Dictionary = context["grid_profile"]
	var minimum_index: int = BrickLayoutScript.interior_min_index(grid_profile)
	var maximum_index: int = BrickLayoutScript.interior_max_index(grid_profile)
	var best_position_m := Vector3.ZERO
	var best_sdf_m: float = -INF
	var best_margin: int = -1
	var best_key: String = ""
	var best_address_id: String = ""
	for changed_value in result["changed_bricks"]:
		if typeof(changed_value) != TYPE_DICTIONARY:
			continue
		var changed: Dictionary = changed_value
		if typeof(changed.get("address")) != TYPE_DICTIONARY:
			continue
		var address: Dictionary = changed["address"]
		var snapshot: Dictionary = service.snapshot_store().get_snapshot(address)
		if not bool(SnapshotScript.validate(snapshot).get("success", false)):
			continue
		var signed_distance_values: Array = snapshot["geometry_channel"]["signed_distance_m"]
		var occupancy_values: Array = snapshot["geometry_channel"]["occupancy_ratio"]
		var cell_address: Dictionary = address["cell_address"]
		for z in range(minimum_index, maximum_index + 1):
			for y in range(minimum_index, maximum_index + 1):
				for x in range(minimum_index, maximum_index + 1):
					var index: int = BrickLayoutScript.flat_index(grid_profile, x, y, z)
					if index < 0 or float(occupancy_values[index]) > 0.0:
						continue
					var sdf_m: float = float(signed_distance_values[index])
					if sdf_m <= 0.0:
						continue
					var margin_x: int = mini(x - minimum_index, maximum_index - x)
					var margin_y: int = mini(y - minimum_index, maximum_index - y)
					var margin_z: int = mini(z - minimum_index, maximum_index - z)
					var boundary_margin: int = mini(margin_x, mini(margin_y, margin_z))
					var candidate_key: String = "%s/%08d" % [String(address["address_id"]), index]
					if boundary_margin < best_margin:
						continue
					if boundary_margin == best_margin and sdf_m < best_sdf_m:
						continue
					if boundary_margin == best_margin and sdf_m == best_sdf_m \
							and not best_key.is_empty() and candidate_key.naturalnocasecmp_to(best_key) >= 0:
						continue
					best_margin = boundary_margin
					best_sdf_m = sdf_m
					best_key = candidate_key
					best_address_id = String(address["address_id"])
					best_position_m = BrickLayoutScript.sample_position_m(
						grid_profile, cell_address, x, y, z
					)
	if best_margin < 0 or not is_finite(best_position_m.x) \
			or not is_finite(best_position_m.y) or not is_finite(best_position_m.z):
		return {}
	var witness_sample: Dictionary = query.sample(best_position_m, CELL_LEVEL)
	if witness_sample.is_empty() \
			or float(witness_sample.get("occupancy_ratio", 1.0)) > 0.0 \
			or float(witness_sample.get("signed_distance_m", -1.0)) <= 0.0:
		return {}
	return {
		"position_m": best_position_m,
		"signed_distance_m": float(witness_sample["signed_distance_m"]),
		"address_id": best_address_id,
		"sample_key": best_key,
		"boundary_margin": best_margin,
	}


static func create_request(service, fixture: Dictionary, operation_id: String) -> Dictionary:
	return service.create_excavation_request(
		operation_id,
		"actor/mw5-test-miner",
		"tool/mw5-test-drill",
		fixture["start_m"],
		fixture["end_m"],
		float(fixture["radius_m"]),
		JSON_SAFE_ENERGY_BUDGET_J,
		501
	)


static func _array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
