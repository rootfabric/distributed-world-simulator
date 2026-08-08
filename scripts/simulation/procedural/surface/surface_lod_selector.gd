extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const PlanetDefinitionScript = preload("res://scripts/simulation/procedural/contracts/planet_definition.gd")
const BodyFixedPositionScript = preload("res://scripts/simulation/procedural/contracts/body_fixed_position.gd")
const SurfaceCellKeyScript = preload("res://scripts/simulation/procedural/contracts/surface_cell_key.gd")
const SurfaceLodPolicyScript = preload("res://scripts/simulation/procedural/contracts/surface_lod_policy.gd")
const CubeSphereAddressingScript = preload("res://scripts/simulation/procedural/surface/cube_sphere_addressing.gd")

const FACE_ARC_RADIANS: float = PI * 0.5

var _configured: bool = false
var _planet_definition: Dictionary = {}
var _policy: Dictionary = {}
var _addressing = CubeSphereAddressingScript.new()
var _leaf_budget: int = 0
var _leaf_count: int = 0
var _previous_leaves: Array = []
var _previous_split_tokens: Dictionary = {}


func configure(planet_definition: Dictionary, policy: Dictionary) -> Dictionary:
	_clear()
	var definition_validation: Dictionary = PlanetDefinitionScript.validate(planet_definition)
	if not bool(definition_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_LOD_PLANET_DEFINITION", {"cause": definition_validation.get("error_code", "")})
	var policy_validation: Dictionary = SurfaceLodPolicyScript.validate(policy)
	if not bool(policy_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_SURFACE_LOD_POLICY", {"cause": policy_validation.get("error_code", "")})
	_planet_definition = planet_definition.duplicate(true)
	_policy = policy.duplicate(true)
	_configured = true
	return GeoUtilsScript.success({
		"body_id": String(_planet_definition["body_id"]),
		"policy_checksum": String(_policy["checksum"]),
	})


func is_configured() -> bool:
	return _configured


func evaluate_cell(cell: Dictionary, observer_body_fixed_position: Dictionary, was_split: bool) -> Dictionary:
	var common: Dictionary = _validate_query(cell, observer_body_fixed_position)
	if not bool(common.get("success", false)):
		return common
	var center_result: Dictionary = _addressing.cell_center_direction(cell)
	if not bool(center_result.get("success", false)):
		return center_result
	var radius_m: float = float(_planet_definition["nominal_radius_m"])
	var center_direction: Vector3 = _vector3(Array(center_result["details"]["direction"]))
	var center_position: Vector3 = center_direction * radius_m
	var observer: Vector3 = _vector3(Array(observer_body_fixed_position["position_m"]))
	var distance_m: float = maxf(observer.distance_to(center_position), float(_policy["minimum_distance_m"]))
	var lod: int = int(cell["lod"])
	var edge_m: float = radius_m * FACE_ARC_RADIANS / float(1 << lod)
	var ratio: float = edge_m / distance_m
	var threshold: float = float(_policy["coarsen_ratio"]) if was_split else float(_policy["refine_ratio"])
	var should_refine: bool = lod < int(_policy["min_lod"]) or (
		lod < int(_policy["max_lod"]) and ratio >= threshold
	)
	return GeoUtilsScript.success({
		"should_refine": should_refine,
		"ratio": ratio,
		"threshold": threshold,
		"distance_m": distance_m,
		"estimated_edge_m": edge_m,
		"was_split": was_split,
	})


func select_cells(observer_body_fixed_position: Dictionary, previous_leaf_cells: Array = []) -> Dictionary:
	if not _configured:
		return GeoUtilsScript.failure("SURFACE_LOD_SELECTOR_NOT_CONFIGURED")
	var observer_validation: Dictionary = BodyFixedPositionScript.validate(observer_body_fixed_position)
	if not bool(observer_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_LOD_OBSERVER_POSITION", {"cause": observer_validation.get("error_code", "")})
	if String(observer_body_fixed_position["body_id"]) != String(_planet_definition["body_id"]):
		return GeoUtilsScript.failure("SURFACE_LOD_BODY_MISMATCH")
	var previous_validation: Dictionary = _validate_previous_leaves(previous_leaf_cells)
	if not bool(previous_validation.get("success", false)):
		return previous_validation
	_previous_leaves = previous_leaf_cells.duplicate(true)
	_previous_leaves.sort_custom(func(a, b): return SurfaceCellKeyScript.identity_token(a) < SurfaceCellKeyScript.identity_token(b))
	_build_previous_split_index()
	_leaf_budget = int(_policy["max_leaf_cells"])
	_leaf_count = 6
	var roots_result: Dictionary = _addressing.root_cells(String(_planet_definition["body_id"]))
	if not bool(roots_result.get("success", false)):
		return roots_result
	var leaves: Array = []
	for root in roots_result["details"]["cells"]:
		_select_recursive(Dictionary(root), observer_body_fixed_position, leaves)
	leaves.sort_custom(func(a, b): return SurfaceCellKeyScript.identity_token(a) < SurfaceCellKeyScript.identity_token(b))
	var max_selected_lod: int = 0
	for cell in leaves:
		max_selected_lod = maxi(max_selected_lod, int(cell["lod"]))
	var payload: Array = []
	for cell in leaves:
		payload.append({
			"body_id": cell["body_id"],
			"face": cell["face"],
			"lod": cell["lod"],
			"x": cell["x"],
			"y": cell["y"],
		})
	return GeoUtilsScript.success({
		"leaves": leaves,
		"leaf_count": leaves.size(),
		"max_selected_lod": max_selected_lod,
		"selection_hash": GeoUtilsScript.payload_hash(payload),
		"leaf_budget": _leaf_budget,
	})


func _select_recursive(cell: Dictionary, observer: Dictionary, leaves: Array) -> void:
	var was_split: bool = _previous_has_descendant(cell)
	var evaluation: Dictionary = evaluate_cell(cell, observer, was_split)
	if not bool(evaluation.get("success", false)):
		leaves.append(cell)
		return
	var should_refine: bool = bool(evaluation["details"]["should_refine"])
	if should_refine and _leaf_count + 3 <= _leaf_budget:
		var children_result: Dictionary = _addressing.children(cell)
		if bool(children_result.get("success", false)):
			_leaf_count += 3
			for child in children_result["details"]["cells"]:
				_select_recursive(Dictionary(child), observer, leaves)
			return
	leaves.append(cell)


func _previous_has_descendant(cell: Dictionary) -> bool:
	return _previous_split_tokens.has(SurfaceCellKeyScript.identity_token(cell))


func _build_previous_split_index() -> void:
	_previous_split_tokens = {}
	for previous in _previous_leaves:
		var previous_lod: int = int(previous["lod"])
		var previous_x: int = int(previous["x"])
		var previous_y: int = int(previous["y"])
		for ancestor_lod in range(previous_lod - 1, -1, -1):
			var shift: int = previous_lod - ancestor_lod
			var ancestor := SurfaceCellKeyScript.create(
				String(previous["body_id"]),
				String(previous["face"]),
				ancestor_lod,
				previous_x >> shift,
				previous_y >> shift
			)
			_previous_split_tokens[SurfaceCellKeyScript.identity_token(ancestor)] = true


func _validate_previous_leaves(previous_leaf_cells: Array) -> Dictionary:
	var seen: Dictionary = {}
	for raw_cell in previous_leaf_cells:
		if not raw_cell is Dictionary:
			return GeoUtilsScript.failure("INVALID_PREVIOUS_SURFACE_LOD_CELL")
		var cell: Dictionary = raw_cell
		var validation: Dictionary = SurfaceCellKeyScript.validate(cell)
		if not bool(validation.get("success", false)):
			return GeoUtilsScript.failure("INVALID_PREVIOUS_SURFACE_LOD_CELL", {"cause": validation.get("error_code", "")})
		if String(cell["body_id"]) != String(_planet_definition["body_id"]):
			return GeoUtilsScript.failure("SURFACE_LOD_BODY_MISMATCH")
		var token: String = SurfaceCellKeyScript.identity_token(cell)
		if seen.has(token):
			return GeoUtilsScript.failure("DUPLICATE_PREVIOUS_SURFACE_LOD_CELL", {"cell": token})
		seen[token] = true
	return GeoUtilsScript.success()


func _validate_query(cell: Dictionary, observer_body_fixed_position: Dictionary) -> Dictionary:
	if not _configured:
		return GeoUtilsScript.failure("SURFACE_LOD_SELECTOR_NOT_CONFIGURED")
	var cell_validation: Dictionary = SurfaceCellKeyScript.validate(cell)
	if not bool(cell_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_SURFACE_CELL_KEY", {"cause": cell_validation.get("error_code", "")})
	var observer_validation: Dictionary = BodyFixedPositionScript.validate(observer_body_fixed_position)
	if not bool(observer_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_LOD_OBSERVER_POSITION", {"cause": observer_validation.get("error_code", "")})
	if String(cell["body_id"]) != String(_planet_definition["body_id"]) or String(observer_body_fixed_position["body_id"]) != String(_planet_definition["body_id"]):
		return GeoUtilsScript.failure("SURFACE_LOD_BODY_MISMATCH")
	return GeoUtilsScript.success()


func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _clear() -> void:
	_configured = false
	_planet_definition = {}
	_policy = {}
	_previous_leaves = []
	_previous_split_tokens = {}
	_leaf_budget = 0
	_leaf_count = 0
