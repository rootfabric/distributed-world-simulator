extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const BrickSnapshot = preload("res://scripts/simulation/matter/contracts/matter_brick_snapshot.gd")
const BrickLayout = preload("res://scripts/simulation/matter/spatial/matter_brick_layout.gd")
const GridProfile = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const CellGrid = preload("res://scripts/simulation/matter/spatial/matter_cell_grid.gd")
const CellAddress = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")
const RepresentationUtils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const DependencySet = preload("res://scripts/simulation/representation/contracts/representation_dependency_set.gd")
const SummaryNode = preload("res://scripts/simulation/representation/matter/contracts/matter_summary_node.gd")

const SURFACE_EPSILON_M: float = 0.000000001


static func from_brick_snapshot(
	snapshot: Dictionary,
	grid_profile: Dictionary,
	authority_epoch: int,
	summary_revision: int,
	build_generation: int
) -> Dictionary:
	if not bool(BrickSnapshot.validate(snapshot).get("success", false)):
		return {}
	if not bool(GridProfile.validate(grid_profile).get("success", false)):
		return {}
	if not bool(BrickLayout.validate_brick_address(grid_profile, snapshot["address"]).get("success", false)):
		return {}
	if int(snapshot["sample_count"]) != GridProfile.sample_count(grid_profile):
		return {}
	if authority_epoch < 1 or summary_revision < int(snapshot["state_revision"]) or build_generation < 1:
		return {}
	var cell_address: Dictionary = snapshot["address"]["cell_address"]
	var cell_bounds: Dictionary = CellGrid.bounds(grid_profile, cell_address)
	if cell_bounds.is_empty():
		return {}
	var geometry: Dictionary = snapshot["geometry_channel"]
	var composition_channel: Dictionary = snapshot["composition_channel"]
	var minimum_distance: float = INF
	var maximum_distance: float = -INF
	var minimum_occupancy: float = INF
	var maximum_occupancy: float = -INF
	var occupied_count: int = 0
	var surface_count: int = 0
	var material_weights: Dictionary = {}
	var total_weight: float = 0.0
	for index in range(int(snapshot["sample_count"])):
		var distance_m: float = float(geometry["signed_distance_m"][index])
		var occupancy: float = float(geometry["occupancy_ratio"][index])
		minimum_distance = minf(minimum_distance, distance_m)
		maximum_distance = maxf(maximum_distance, distance_m)
		minimum_occupancy = minf(minimum_occupancy, occupancy)
		maximum_occupancy = maxf(maximum_occupancy, occupancy)
		if occupancy > 0.0:
			occupied_count += 1
			var palette_index: int = int(composition_channel["palette_indices"][index])
			var composition: Dictionary = composition_channel["palette"][palette_index]
			for component_value in composition["components"]:
				var component: Dictionary = component_value
				var material_id: String = String(component["material_id"])
				var weight: float = occupancy * float(component["mass_fraction"])
				material_weights[material_id] = float(material_weights.get(material_id, 0.0)) + weight
				total_weight += weight
		if absf(distance_m) <= SURFACE_EPSILON_M or (occupancy > 0.0 and occupancy < 1.0):
			surface_count += 1
	var snapshot_dependency: Dictionary = {
		"source_domain": "MATTER",
		"source_id": String(snapshot["snapshot_id"]),
		"authority_epoch": authority_epoch,
		"source_revision": int(snapshot["state_revision"]),
		"source_hash": String(snapshot["checksum"]),
	}
	var dependency_set: Dictionary = DependencySet.create(
		"MATTER",
		String(grid_profile["body_id"]),
		SummaryNode.scope_id_for(String(grid_profile["body_id"]), cell_address),
		[snapshot_dependency]
	)
	if dependency_set.is_empty():
		return {}
	var descendant_descriptor: Array = [{
		"source_id": String(snapshot["snapshot_id"]),
		"authority_epoch": authority_epoch,
		"source_revision": int(snapshot["state_revision"]),
		"source_hash": String(snapshot["checksum"]),
	}]
	return SummaryNode.create({
		"body_id": String(grid_profile["body_id"]),
		"cell_address": cell_address,
		"bounds_m": _bounds_array(cell_bounds),
		"authority_epoch": authority_epoch,
		"summary_revision": summary_revision,
		"build_generation": build_generation,
		"child_count": 0,
		"leaf_count": 1,
		"sample_count": int(snapshot["sample_count"]),
		"occupied_sample_count": occupied_count,
		"surface_sample_count": surface_count,
		"minimum_signed_distance_m": minimum_distance,
		"maximum_signed_distance_m": maximum_distance,
		"minimum_occupancy_ratio": minimum_occupancy,
		"maximum_occupancy_ratio": maximum_occupancy,
		"contains_matter": maximum_occupancy > 0.0,
		"contains_vacuum": minimum_occupancy < 1.0,
		"contains_surface": surface_count > 0 \
			or (minimum_distance <= SURFACE_EPSILON_M and maximum_distance >= -SURFACE_EPSILON_M),
		"material_occupancy_weights": _material_entries(material_weights),
		"total_occupancy_weight": total_weight,
		"minimum_descendant_revision": int(snapshot["state_revision"]),
		"maximum_descendant_revision": int(snapshot["state_revision"]),
		"dependency_hash": String(dependency_set["dependency_hash"]),
		"descendant_revision_hash": RepresentationUtils.payload_hash(descendant_descriptor),
	})


static func from_children(
	body_id: String,
	parent_address: Dictionary,
	grid_profile: Dictionary,
	children: Array,
	authority_epoch: int,
	summary_revision: int,
	build_generation: int
) -> Dictionary:
	if not MatterUtils.is_canonical_id(body_id, 2) \
		or not bool(GridProfile.validate(grid_profile).get("success", false)) \
		or String(grid_profile["body_id"]) != body_id \
		or not bool(CellGrid.validate_address(grid_profile, parent_address).get("success", false)) \
		or children.is_empty() or children.size() > 8 \
		or authority_epoch < 1 or summary_revision < 0 or build_generation < 1:
		return {}
	var sorted_children: Array = _sorted_children(children)
	var previous_cell_id: String = ""
	var dependency_children: Array = []
	var descendant_descriptors: Array = []
	var minimum_distance: float = INF
	var maximum_distance: float = -INF
	var minimum_occupancy: float = INF
	var maximum_occupancy: float = -INF
	var leaf_count: int = 0
	var sample_count: int = 0
	var occupied_count: int = 0
	var surface_count: int = 0
	var material_weights: Dictionary = {}
	var total_weight: float = 0.0
	var minimum_descendant_revision: int = 0x7fffffff
	var maximum_descendant_revision: int = -1
	for index in range(sorted_children.size()):
		var child_value = sorted_children[index]
		if typeof(child_value) != TYPE_DICTIONARY:
			return {}
		var child: Dictionary = child_value
		if not bool(SummaryNode.validate(child).get("success", false)) \
			or String(child["body_id"]) != body_id \
			or int(child["authority_epoch"]) != authority_epoch:
			return {}
		var child_address: Dictionary = child["cell_address"]
		var direct_parent: Dictionary = CellAddress.parent(child_address)
		if direct_parent.is_empty() or direct_parent != parent_address:
			return {}
		var cell_id: String = String(child_address["cell_id"])
		if index > 0 and cell_id <= previous_cell_id:
			return {}
		previous_cell_id = cell_id
		dependency_children.append({
			"source_domain": "MATTER",
			"source_id": String(child["summary_id"]),
			"authority_epoch": authority_epoch,
			"source_revision": int(child["summary_revision"]),
			"source_hash": String(child["checksum"]),
		})
		descendant_descriptors.append({
			"summary_id": String(child["summary_id"]),
			"authority_epoch": authority_epoch,
			"summary_revision": int(child["summary_revision"]),
			"summary_hash": String(child["checksum"]),
			"descendant_revision_hash": String(child["descendant_revision_hash"]),
		})
		minimum_distance = minf(minimum_distance, float(child["minimum_signed_distance_m"]))
		maximum_distance = maxf(maximum_distance, float(child["maximum_signed_distance_m"]))
		minimum_occupancy = minf(minimum_occupancy, float(child["minimum_occupancy_ratio"]))
		maximum_occupancy = maxf(maximum_occupancy, float(child["maximum_occupancy_ratio"]))
		leaf_count += int(child["leaf_count"])
		sample_count += int(child["sample_count"])
		occupied_count += int(child["occupied_sample_count"])
		surface_count += int(child["surface_sample_count"])
		total_weight += float(child["total_occupancy_weight"])
		minimum_descendant_revision = mini(
			minimum_descendant_revision, int(child["minimum_descendant_revision"])
		)
		maximum_descendant_revision = maxi(
			maximum_descendant_revision, int(child["maximum_descendant_revision"])
		)
		for material_value in child["material_occupancy_weights"]:
			var material: Dictionary = material_value
			var material_id: String = String(material["material_id"])
			material_weights[material_id] = float(material_weights.get(material_id, 0.0)) \
				+ float(material["occupancy_weight"])
	if summary_revision < maximum_descendant_revision:
		return {}
	var dependency_set: Dictionary = DependencySet.create(
		"MATTER",
		body_id,
		SummaryNode.scope_id_for(body_id, parent_address),
		dependency_children
	)
	if dependency_set.is_empty():
		return {}
	var cell_bounds: Dictionary = CellGrid.bounds(grid_profile, parent_address)
	if cell_bounds.is_empty():
		return {}
	return SummaryNode.create({
		"body_id": body_id,
		"cell_address": parent_address,
		"bounds_m": _bounds_array(cell_bounds),
		"authority_epoch": authority_epoch,
		"summary_revision": summary_revision,
		"build_generation": build_generation,
		"child_count": sorted_children.size(),
		"leaf_count": leaf_count,
		"sample_count": sample_count,
		"occupied_sample_count": occupied_count,
		"surface_sample_count": surface_count,
		"minimum_signed_distance_m": minimum_distance,
		"maximum_signed_distance_m": maximum_distance,
		"minimum_occupancy_ratio": minimum_occupancy,
		"maximum_occupancy_ratio": maximum_occupancy,
		"contains_matter": maximum_occupancy > 0.0,
		"contains_vacuum": minimum_occupancy < 1.0,
		"contains_surface": surface_count > 0 \
			or (minimum_distance <= SURFACE_EPSILON_M and maximum_distance >= -SURFACE_EPSILON_M),
		"material_occupancy_weights": _material_entries(material_weights),
		"total_occupancy_weight": total_weight,
		"minimum_descendant_revision": minimum_descendant_revision,
		"maximum_descendant_revision": maximum_descendant_revision,
		"dependency_hash": String(dependency_set["dependency_hash"]),
		"descendant_revision_hash": RepresentationUtils.payload_hash(descendant_descriptors),
	})


static func _bounds_array(cell_bounds: Dictionary) -> Array:
	var minimum_m: Array = cell_bounds["minimum_m"]
	var maximum_m: Array = cell_bounds["maximum_m"]
	return [
		float(minimum_m[0]), float(minimum_m[1]), float(minimum_m[2]),
		float(maximum_m[0]), float(maximum_m[1]), float(maximum_m[2]),
	]


static func _material_entries(weights: Dictionary) -> Array:
	var material_ids: Array = weights.keys()
	material_ids.sort()
	var result: Array = []
	for material_id in material_ids:
		var weight: float = float(weights[material_id])
		if weight > 0.0:
			result.append({"material_id": String(material_id), "occupancy_weight": weight})
	return result


static func _sorted_children(children: Array) -> Array:
	var result: Array = []
	for child in children:
		result.append(child.duplicate(true) if typeof(child) == TYPE_DICTIONARY else child)
	result.sort_custom(func(a, b) -> bool:
		return String(Dictionary(a).get("cell_address", {}).get("cell_id", "")) \
			< String(Dictionary(b).get("cell_address", {}).get("cell_id", ""))
	)
	return result
