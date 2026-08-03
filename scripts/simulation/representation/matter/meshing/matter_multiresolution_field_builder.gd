extends RefCounted

const RepresentationUtils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const GridProfile = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const CellGrid = preload("res://scripts/simulation/matter/spatial/matter_cell_grid.gd")
const BrickLayout = preload("res://scripts/simulation/matter/spatial/matter_brick_layout.gd")
const BrickSnapshot = preload("res://scripts/simulation/matter/contracts/matter_brick_snapshot.gd")
const SummaryNode = preload("res://scripts/simulation/representation/matter/contracts/matter_summary_node.gd")
const RepresentationKey = preload("res://scripts/simulation/representation/contracts/representation_key.gd")
const SourceSet = preload("res://scripts/simulation/representation/matter/meshing/contracts/matter_meshing_source_set.gd")
const Field = preload("res://scripts/simulation/representation/matter/meshing/contracts/matter_multiresolution_field.gd")

const SAMPLE_TOLERANCE_M: float = 0.0000001
const DISTANCE_TOLERANCE_M: float = 0.000000001
const COLOR_TOLERANCE: float = 0.000001
const DEFAULT_VARIANT_ID := "representation-variant/matter-surface-default"


static func build(
	summary_node: Dictionary,
	snapshots: Array,
	grid_profile: Dictionary,
	iso_level_m: float = 0.0,
	variant_id: String = DEFAULT_VARIANT_ID
) -> Dictionary:
	if not bool(SummaryNode.validate(summary_node).get("success", false)) \
		or not bool(GridProfile.validate(grid_profile).get("success", false)) \
		or not is_finite(iso_level_m):
		return {}
	var source_set: Dictionary = SourceSet.create(summary_node, snapshots, grid_profile)
	if source_set.is_empty():
		return {}
	var target_address: Dictionary = summary_node["cell_address"]
	var target_bounds: Dictionary = CellGrid.bounds(grid_profile, target_address)
	if target_bounds.is_empty():
		return {}
	var lod_level: int = int(source_set["lod_level"])
	var representation_key: Dictionary = RepresentationKey.create(
		source_set["source_revision"],
		String(source_set["target_scope_id"]),
		lod_level,
		_artifact_kind(lod_level),
		variant_id
	)
	if representation_key.is_empty():
		return {}
	var sorted_snapshots: Array = snapshots.duplicate()
	sorted_snapshots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["address"]["cell_address"]["cell_id"]) \
			< String(b["address"]["cell_address"]["cell_id"])
	)
	for raw_snapshot in sorted_snapshots:
		if typeof(raw_snapshot) != TYPE_DICTIONARY \
			or not bool(BrickSnapshot.validate(raw_snapshot).get("success", false)):
			return {}
	var resolution: int = int(grid_profile["brick_interior_resolution"])
	var minimum_m := Vector3(
		float(target_bounds["minimum_m"][0]),
		float(target_bounds["minimum_m"][1]),
		float(target_bounds["minimum_m"][2])
	)
	var maximum_m := Vector3(
		float(target_bounds["maximum_m"][0]),
		float(target_bounds["maximum_m"][1]),
		float(target_bounds["maximum_m"][2])
	)
	var sample_spacing_m: float = float(target_bounds["edge_length_m"]) / float(resolution)
	var signed_distance_m: Array = []
	var colors_rgba: Array = []
	for z in range(resolution + 1):
		for y in range(resolution + 1):
			for x in range(resolution + 1):
				var position_m := Vector3(
					maximum_m.x if x == resolution else minimum_m.x + float(x) * sample_spacing_m,
					maximum_m.y if y == resolution else minimum_m.y + float(y) * sample_spacing_m,
					maximum_m.z if z == resolution else minimum_m.z + float(z) * sample_spacing_m
				)
				var sampled: Dictionary = _sample_consistent(sorted_snapshots, grid_profile, position_m)
				if not bool(sampled.get("success", false)):
					return {}
				signed_distance_m.append(float(sampled["signed_distance_m"]))
				colors_rgba.append(Array(sampled["color_rgba"]).duplicate())
	var bounds_m: Array = [
		minimum_m.x, minimum_m.y, minimum_m.z,
		maximum_m.x, maximum_m.y, maximum_m.z,
	]
	return Field.create(
		source_set,
		representation_key,
		target_address,
		bounds_m,
		resolution,
		sample_spacing_m,
		iso_level_m,
		signed_distance_m,
		colors_rgba,
		grid_profile
	)


static func _sample_consistent(
	snapshots: Array,
	grid_profile: Dictionary,
	position_m: Vector3
) -> Dictionary:
	var witnesses: Array = []
	for raw_snapshot in snapshots:
		var snapshot: Dictionary = raw_snapshot
		var cell_address: Dictionary = snapshot["address"]["cell_address"]
		var coordinates: Array = BrickLayout.lattice_coordinates_for_position(
			grid_profile, cell_address, position_m, SAMPLE_TOLERANCE_M
		)
		if coordinates.is_empty():
			continue
		var flat_index: int = BrickLayout.flat_index(
			grid_profile, int(coordinates[0]), int(coordinates[1]), int(coordinates[2])
		)
		if flat_index < 0:
			continue
		var payload: Dictionary = BrickSnapshot.sample_payload_at_validated(snapshot, flat_index)
		if payload.is_empty():
			return {"success": false, "error_code": "MISSING_MATTER_FIELD_SAMPLE"}
		witnesses.append({
			"cell_id": String(cell_address["cell_id"]),
			"signed_distance_m": float(payload["signed_distance_m"]),
			"color_rgba": _composition_color(payload["composition"]),
		})
	if witnesses.is_empty():
		return {"success": false, "error_code": "MISSING_MATTER_FIELD_COVERAGE"}
	witnesses.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["cell_id"]) < String(b["cell_id"])
	)
	var selected: Dictionary = witnesses[0]
	for witness_value in witnesses:
		var witness: Dictionary = witness_value
		if absf(float(witness["signed_distance_m"]) - float(selected["signed_distance_m"])) \
			> DISTANCE_TOLERANCE_M:
			return {"success": false, "error_code": "MATTER_FIELD_SHARED_SAMPLE_DISTANCE_MISMATCH"}
		if not _colors_equal(Array(witness["color_rgba"]), Array(selected["color_rgba"])):
			return {"success": false, "error_code": "MATTER_FIELD_SHARED_SAMPLE_COLOR_MISMATCH"}
	return {
		"success": true,
		"signed_distance_m": float(selected["signed_distance_m"]),
		"color_rgba": Array(selected["color_rgba"]).duplicate(),
	}


static func _artifact_kind(lod_level: int) -> String:
	match lod_level:
		0:
			return "DETAIL"
		1:
			return "SIMPLIFIED_MESH"
		_:
			return "MACRO_PROXY"


static func _composition_color(composition: Dictionary) -> Array:
	var components: Array = Array(composition.get("components", []))
	if components.is_empty():
		return [0.08, 0.09, 0.11, 1.0]
	var dominant_id: String = ""
	var dominant_fraction: float = -1.0
	for component_value in components:
		var component: Dictionary = component_value
		var fraction: float = float(component.get("mass_fraction", 0.0))
		if fraction > dominant_fraction:
			dominant_fraction = fraction
			dominant_id = String(component.get("material_id", ""))
	match dominant_id:
		"matter/regolith-compacted", "material/regolith-compacted":
			return [0.48, 0.43, 0.38, 1.0]
		"matter/fractured-basalt", "matter/basalt", "material/basalt":
			return [0.19, 0.20, 0.22, 1.0]
		"matter/iron-nickel-ore", "material/iron-nickel-ore":
			return [0.36, 0.24, 0.18, 1.0]
		"matter/water-ice", "material/ice", "material/water-ice":
			return [0.58, 0.76, 0.88, 1.0]
		_:
			var digest: String = dominant_id.sha256_text()
			var red_seed: int = digest.substr(0, 8).hex_to_int()
			var green_seed: int = digest.substr(8, 8).hex_to_int()
			var blue_seed: int = digest.substr(16, 8).hex_to_int()
			return [
				0.18 + float(red_seed % 23) / 100.0,
				0.20 + float(green_seed % 19) / 100.0,
				0.22 + float(blue_seed % 17) / 100.0,
				1.0,
			]


static func _colors_equal(a: Array, b: Array) -> bool:
	if a.size() != 4 or b.size() != 4:
		return false
	for index in range(4):
		if absf(float(a[index]) - float(b[index])) > COLOR_TOLERANCE:
			return false
	return true
