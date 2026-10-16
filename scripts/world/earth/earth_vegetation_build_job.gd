extends RefCounted

# R3C3 R2 STAGE A: CPU-only deterministic staged vegetation preparation.
# NO Node, SceneTree, MultiMesh, RenderingServer or worker thread here.
# The owning Earth scene advances a bounded number of placement attempts per
# frame. The RNG sequence is IDENTICAL to the legacy synchronous generator
# (earth_placement_system._generate_trees/_grass/_rocks): the same draws happen
# in the same order for the same attempt index, and the RNG is never reset
# between slices. Order: TREES -> GRASS -> ROCKS -> TRANSFORMS_READY.
const STAGE_TREES := "TREES"
const STAGE_GRASS := "GRASS"
const STAGE_ROCKS := "ROCKS"
const STAGE_READY := "TRANSFORMS_READY"
const STAGE_FAILED := "FAILED"

var _world
var _config: Dictionary = {}
var _tree_types: Array = []
var _grass_types: Array = []
var _anchor_direction := Vector3.UP
var _east := Vector3.RIGHT
var _north := Vector3.FORWARD
var _anchor_world := Vector3.ZERO
var _generation_token := 0
var _seed := 0
var _stage := STAGE_FAILED
var _attempt_cursor := 0
var _attempts_total := 0
var _rng := RandomNumberGenerator.new()
var _near_buckets: Dictionary = {}
var _billboard_buckets: Dictionary = {}
var _grass_buckets: Dictionary = {}
var _rock_buckets: Array = [[], [], []]
var _near_count := 0
var _billboard_count := 0
var _grass_count := 0
var _rock_count := 0
var _sample_draw_count := 0
var _failure := ""


func configure(
	world_reference,
	placement_config: Dictionary,
	tree_types: Array,
	grass_types: Array,
	anchor_direction: Vector3,
	east: Vector3,
	north: Vector3,
	anchor_world: Vector3,
	generation_token: int
) -> Dictionary:
	if world_reference == null or not world_reference.has_method("get_surface_point"):
		return _fail("R3C3R2_WORLD_REQUIRED")
	if placement_config.is_empty():
		return _fail("R3C3R2_PLACEMENT_CONFIG_REQUIRED")
	if tree_types.is_empty() or grass_types.is_empty():
		return _fail("R3C3R2_TYPE_DEFINITIONS_REQUIRED")
	if anchor_direction.length_squared() < 0.000001:
		return _fail("R3C3R2_ANCHOR_DIRECTION_INVALID")
	if east.length_squared() < 0.99 or north.length_squared() < 0.99:
		return _fail("R3C3R2_BASIS_INVALID")
	if generation_token < 1:
		return _fail("R3C3R2_GENERATION_TOKEN_INVALID")
	_world = world_reference
	_config = placement_config
	_tree_types = tree_types
	_grass_types = grass_types
	_anchor_direction = anchor_direction.normalized()
	_east = east
	_north = north
	_anchor_world = anchor_world
	_generation_token = generation_token
	# Exact legacy seed derivation: earth_placement_system._anchor_seed().
	var quantized := Vector3i(
		roundi(_anchor_direction.x * 10000.0),
		roundi(_anchor_direction.y * 10000.0),
		roundi(_anchor_direction.z * 10000.0)
	)
	var value: int = int(_config.get("seed", 20260726))
	value ^= quantized.x * 73856093
	value ^= quantized.y * 19349663
	value ^= quantized.z * 83492791
	_seed = absi(value)
	_rng.seed = _seed
	_stage = STAGE_TREES
	_attempt_cursor = 0
	_near_count = 0
	_billboard_count = 0
	_grass_count = 0
	_rock_count = 0
	_sample_draw_count = 0
	_failure = ""
	_near_buckets = _empty_transform_buckets(_tree_types)
	_billboard_buckets = _empty_transform_buckets(_tree_types)
	_grass_buckets = _empty_transform_buckets(_grass_types)
	_rock_buckets = [[], [], []]
	return {"success": true, "error_code": "", "details": {"seed": _seed}}


# One call = one bounded slice. budget_us is a target, not a hard guarantee:
# every individual attempt is finished once started.
func advance(max_attempts: int = 256, budget_us: int = 2000) -> Dictionary:
	if _stage == STAGE_FAILED:
		return _fail(_failure if not _failure.is_empty() else "R3C3R2_UNCONFIGURED_JOB")
	if max_attempts < 1 or budget_us < 1:
		return _fail("R3C3R2_INVALID_SLICE_BUDGET")
	var started_us: int = Time.get_ticks_usec()
	var done_attempts := 0
	while done_attempts < max_attempts and _stage != STAGE_READY:
		if done_attempts > 0 and Time.get_ticks_usec() - started_us >= budget_us:
			break
		_step_attempt()
		done_attempts += 1
	return {
		"success": true, "error_code": "",
		"details": {
			"stage": _stage, "processed_attempts": done_attempts,
			"elapsed_us": Time.get_ticks_usec() - started_us,
			"ready": is_ready(),
		},
	}


func is_ready() -> bool:
	return _stage == STAGE_READY


func get_generation_token() -> int:
	return _generation_token


func get_placement_seed() -> int:
	return _seed


func get_stage() -> String:
	return _stage


func get_error_code() -> String:
	return _failure


func get_near_buckets() -> Dictionary:
	return _near_buckets.duplicate(true) if is_ready() else {}


func get_billboard_buckets() -> Dictionary:
	return _billboard_buckets.duplicate(true) if is_ready() else {}


func get_grass_buckets() -> Dictionary:
	return _grass_buckets.duplicate(true) if is_ready() else {}


func get_rock_buckets() -> Array:
	return _rock_buckets.duplicate(true) if is_ready() else []


func get_report() -> Dictionary:
	return {
		"stage": _stage, "ready": is_ready(), "error": _failure,
		"token": _generation_token, "seed": _seed,
		"near_trees": _near_count, "billboard_trees": _billboard_count,
		"grass": _grass_count, "rocks": _rock_count,
		"attempt": _attempt_cursor,
	}


# Deterministic witness of the exact RNG draw count. The parity test proves
# this equals the legacy generator for the same anchor; any drift (extra draw,
# reordered draw, reset between slices) changes this number and the buckets.
func get_rng_draw_count() -> int:
	return _sample_draw_count


# Exactly one pipeline.sample per attempt: this equals the legacy placement
# `pipeline_samples` accounting even when slices interleave with geometry.
func get_total_attempts() -> int:
	return _attempts_total


func get_summary() -> Dictionary:
	return {
		"seed": _seed,
		"near_trees": _near_count,
		"billboard_trees": _billboard_count,
		"grass": _grass_count,
		"rocks": _rock_count,
	}


func _step_attempt() -> void:
	match _stage:
		STAGE_TREES:
			_step_trees()
		STAGE_GRASS:
			_step_grass()
		STAGE_ROCKS:
			_step_rocks()
		_:
			_fail("R3C3R2_UNKNOWN_VEGETATION_STAGE")


func _step_trees() -> void:
	var near_radius: float = float(_config.get("near_tree_radius_m", 3600.0))
	var billboard_radius: float = float(_config.get("billboard_tree_radius_m", 9200.0))
	var max_near: int = int(_config.get("max_near_trees", 1600))
	var max_billboards: int = int(_config.get("max_billboard_trees", 5200))
	var attempts: int = (max_near + max_billboards) * 4
	# Legacy loop-top early break, evaluated at the exact same attempt index.
	if _near_count >= max_near and _billboard_count >= max_billboards:
		_stage = STAGE_GRASS
		_attempt_cursor = 0
		return
	if _attempt_cursor >= attempts:
		_stage = STAGE_GRASS
		_attempt_cursor = 0
		return
	var rng := _rng
	_attempt_cursor += 1
	_attempts_total += 1
	var offset: Vector2 = _random_disk(rng, billboard_radius)
	var distance: float = offset.length()
	var direction: Vector3 = _offset_direction(_anchor_direction, _east, _north, offset)
	var state: Dictionary = _pipeline_sample(direction)
	var density: float = float(state.get("tree_density", 0.0))
	if density <= 0.0 or _draw_randf(rng) > density:
		return
	if int(state.get("water_kind", 0)) != 0:
		return
	if float(state.get("snow_mask", 0.0)) > float(_config.get("snow_tree_cutoff", 0.22)):
		return
	if float(state.get("slope_hint_deg", 90.0)) > float(_config.get("maximum_tree_slope_deg", 31.0)):
		return
	if float(state.get("rockiness", 0.0)) > 0.78:
		return
	var type_definition: Dictionary = _weighted_choice(rng, _tree_types)
	var type_id: String = String(type_definition.get("id", "broadleaf"))
	var scale_value: float = _draw_randf_range(
		rng,
		float(type_definition.get("min_scale", 0.7)),
		float(type_definition.get("max_scale", 1.3))
	)
	var transform_value: Transform3D = _surface_transform(
		direction,
		_anchor_world,
		_draw_randf_range(rng, 0.0, TAU),
		Vector3(
			scale_value * _draw_randf_range(rng, 0.82, 1.18),
			scale_value * _draw_randf_range(rng, 0.82, 1.24),
			scale_value * _draw_randf_range(rng, 0.82, 1.18)
		)
	)
	if distance <= near_radius and _near_count < max_near:
		_near_buckets[type_id].append(transform_value)
		_near_count += 1
	elif _billboard_count < max_billboards:
		_billboard_buckets[type_id].append(transform_value)
		_billboard_count += 1


func _step_grass() -> void:
	var radius: float = float(_config.get("grass_radius_m", 1250.0))
	var maximum: int = int(_config.get("max_grass_instances", 14000))
	var max_slope: float = float(_config.get("maximum_grass_slope_deg", 38.0))
	if _grass_count >= maximum or _attempt_cursor >= maximum * 3:
		_stage = STAGE_ROCKS
		_attempt_cursor = 0
		return
	var rng := _rng
	_attempt_cursor += 1
	_attempts_total += 1
	var offset: Vector2 = _random_disk(rng, radius)
	var direction: Vector3 = _offset_direction(_anchor_direction, _east, _north, offset)
	var state: Dictionary = _pipeline_sample(direction)
	var density: float = float(state.get("grass_density", 0.0))
	var cluster_noise: float = _draw_randf(rng)
	if density <= 0.0 or cluster_noise > density:
		return
	if int(state.get("water_kind", 0)) != 0:
		return
	if float(state.get("snow_mask", 0.0)) > 0.16:
		return
	if float(state.get("slope_hint_deg", 90.0)) > max_slope:
		return
	var type_definition: Dictionary = _weighted_choice(rng, _grass_types)
	var type_id: String = String(type_definition.get("id", "short"))
	var scale_value: float = _draw_randf_range(
		rng,
		float(type_definition.get("min_scale", 0.7)),
		float(type_definition.get("max_scale", 1.3))
	)
	_grass_buckets[type_id].append(_surface_transform(
		direction,
		_anchor_world,
		_draw_randf_range(rng, 0.0, TAU),
		Vector3(
			scale_value * _draw_randf_range(rng, 0.75, 1.25),
			scale_value,
			scale_value * _draw_randf_range(rng, 0.75, 1.25)
		)
	))
	_grass_count += 1


func _step_rocks() -> void:
	var radius: float = float(_config.get("rock_radius_m", 5400.0))
	var maximum: int = int(_config.get("max_rocks", 2300))
	if _rock_count >= maximum or _attempt_cursor >= maximum * 3:
		_stage = STAGE_READY
		_attempt_cursor = 0
		return
	var rng := _rng
	_attempt_cursor += 1
	_attempts_total += 1
	var offset: Vector2 = _random_disk(rng, radius)
	var direction: Vector3 = _offset_direction(_anchor_direction, _east, _north, offset)
	var state: Dictionary = _pipeline_sample(direction)
	var density: float = float(state.get("rock_density", 0.0))
	if density <= 0.0 or _draw_randf(rng) > density:
		return
	if int(state.get("water_kind", 0)) != 0:
		return
	var variant: int = rng.randi_range(0, 2)
	_sample_draw_count += 1
	var scale_value: float = _draw_randf_range(rng, 0.35, 2.8)
	_rock_buckets[variant].append(_surface_transform(
		direction,
		_anchor_world,
		_draw_randf_range(rng, 0.0, TAU),
		Vector3(
			scale_value * _draw_randf_range(rng, 0.65, 1.45),
			scale_value * _draw_randf_range(rng, 0.45, 1.10),
			scale_value * _draw_randf_range(rng, 0.65, 1.45)
		)
	))
	_rock_count += 1


# Every RNG entry point is routed through these wrappers so the parity test can
# prove the draw count matches the legacy generator attempt for attempt.
func _draw_randf(rng: RandomNumberGenerator) -> float:
	_sample_draw_count += 1
	return rng.randf()


func _draw_randf_range(rng: RandomNumberGenerator, from_value: float, to_value: float) -> float:
	_sample_draw_count += 1
	return rng.randf_range(from_value, to_value)


func _random_disk(rng: RandomNumberGenerator, radius: float) -> Vector2:
	# Two draws exactly like the legacy _random_disk.
	_sample_draw_count += 2
	var distance: float = sqrt(rng.randf()) * radius
	var angle: float = rng.randf_range(0.0, TAU)
	return Vector2(cos(angle), sin(angle)) * distance


func _weighted_choice(rng: RandomNumberGenerator, values: Array) -> Dictionary:
	_sample_draw_count += 1
	if values.is_empty():
		return {}
	var total: float = 0.0
	for value in values:
		if value is Dictionary:
			total += maxf(0.0, float(value.get("weight", 1.0)))
	var target: float = rng.randf() * maxf(total, 0.0001)
	for value in values:
		if not value is Dictionary:
			continue
		target -= maxf(0.0, float(value.get("weight", 1.0)))
		if target <= 0.0:
			return value
	var fallback = values.back()
	return fallback if fallback is Dictionary else {}


func _surface_transform(
	direction: Vector3,
	anchor_world: Vector3,
	yaw: float,
	scale_value: Vector3
) -> Transform3D:
	var up: Vector3 = direction.normalized()
	var tangent_x: Vector3 = Vector3.UP.cross(up)
	if tangent_x.length_squared() < 0.000001:
		tangent_x = Vector3.RIGHT.cross(up)
	tangent_x = tangent_x.normalized()
	var tangent_z: Vector3 = tangent_x.cross(up).normalized()
	var basis := Basis(tangent_x, up, tangent_z).rotated(up, yaw)
	basis = basis.scaled(scale_value)
	var position: Vector3 = _world.get_surface_point(direction) - anchor_world
	return Transform3D(basis, position)


func _offset_direction(
	anchor_direction: Vector3,
	east: Vector3,
	north: Vector3,
	offset: Vector2
) -> Vector3:
	return (
		anchor_direction
		+ east * (offset.x / _world.get_planet_radius())
		+ north * (offset.y / _world.get_planet_radius())
	).normalized()


func _pipeline_sample(direction: Vector3) -> Dictionary:
	# One pipeline sample per attempt, exactly like the legacy loops.
	return _world.get_surface_state(direction, 0)


func _empty_transform_buckets(definitions: Array) -> Dictionary:
	var result: Dictionary = {}
	for definition in definitions:
		if definition is Dictionary:
			result[String(definition.get("id", "default"))] = []
	return result


func _fail(error_code: String) -> Dictionary:
	_failure = error_code
	_stage = STAGE_FAILED
	return {"success": false, "error_code": error_code}
