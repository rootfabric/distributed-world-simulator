extends RefCounted

const SpatialRefScript = preload("res://scripts/simulation/spatial/spatial_ref.gd")

const SCHEMA: String = "planet_simulator.frame_graph.v1"

var root_frame_id: String = ""
var universe_id: String = SpatialRefScript.DEFAULT_UNIVERSE_ID
var instance_id: String = SpatialRefScript.DEFAULT_INSTANCE_ID
var space_id: String = SpatialRefScript.DEFAULT_SPACE_ID
var frames: Dictionary = {}
var validation_errors: PackedStringArray = PackedStringArray()


func setup(root_id: String, metadata: Dictionary = {}) -> bool:
	frames.clear()
	validation_errors.clear()
	root_frame_id = root_id.strip_edges()
	universe_id = String(metadata.get(
		"universe_id",
		SpatialRefScript.DEFAULT_UNIVERSE_ID
	)).strip_edges().to_lower()
	instance_id = String(metadata.get(
		"instance_id",
		SpatialRefScript.DEFAULT_INSTANCE_ID
	)).strip_edges().to_lower()
	space_id = String(metadata.get(
		"space_id",
		SpatialRefScript.DEFAULT_SPACE_ID
	)).strip_edges().to_lower()
	if root_frame_id.is_empty():
		validation_errors.append("ROOT_FRAME_ID_EMPTY")
		return false
	if (
		not _is_namespace_identifier(universe_id)
		or not _is_namespace_identifier(instance_id)
		or not _is_namespace_identifier(space_id)
	):
		validation_errors.append("INVALID_GRAPH_NAMESPACE")
		return false
	frames[root_frame_id] = {
		"id": root_frame_id,
		"parent_id": "",
		"provider": null,
		"metadata": metadata.duplicate(true),
	}
	return true


func add_frame(
	frame_id: String,
	parent_id: String,
	provider,
	metadata: Dictionary = {}
) -> bool:
	var normalized_id: String = frame_id.strip_edges()
	var normalized_parent: String = parent_id.strip_edges()
	if normalized_id.is_empty() or normalized_parent.is_empty():
		validation_errors.append("FRAME_OR_PARENT_ID_EMPTY:%s" % normalized_id)
		return false
	if frames.has(normalized_id):
		validation_errors.append("DUPLICATE_FRAME:%s" % normalized_id)
		return false
	if not frames.has(normalized_parent):
		validation_errors.append("UNKNOWN_PARENT:%s:%s" % [normalized_id, normalized_parent])
		return false
	if provider == null or not provider.has_method("sample_state"):
		validation_errors.append("INVALID_PROVIDER:%s" % normalized_id)
		return false
	frames[normalized_id] = {
		"id": normalized_id,
		"parent_id": normalized_parent,
		"provider": provider,
		"metadata": metadata.duplicate(true),
	}
	return true


func has_frame(frame_id: String) -> bool:
	return frames.has(frame_id)


func get_frame_metadata(frame_id: String) -> Dictionary:
	return frames.get(frame_id, {}).get("metadata", {}).duplicate(true)


func get_frame_state_in_root(frame_id: String, time_s: float) -> Dictionary:
	if not frames.has(frame_id):
		return {}
	var chain: Array[String] = []
	var cursor: String = frame_id
	var guard: int = 0
	while not cursor.is_empty():
		if not frames.has(cursor):
			return {}
		chain.push_front(cursor)
		cursor = String(frames[cursor].get("parent_id", ""))
		guard += 1
		if guard > frames.size() + 1:
			return {}
	var state: Dictionary = _identity_state()
	for chain_index in range(1, chain.size()):
		var child_id: String = chain[chain_index]
		var child_definition: Dictionary = frames[child_id]
		var provider = child_definition.get("provider")
		var child_state: Dictionary = provider.sample_state(time_s)
		state = _compose_states(state, child_state)
	return state


func transform_point(
	point: Vector3,
	source_frame_id: String,
	target_frame_id: String,
	time_s: float
) -> Vector3:
	if source_frame_id == target_frame_id:
		return point
	var source_state: Dictionary = get_frame_state_in_root(source_frame_id, time_s)
	var target_state: Dictionary = get_frame_state_in_root(target_frame_id, time_s)
	if source_state.is_empty() or target_state.is_empty():
		return Vector3.ZERO
	var root_point: Vector3 = (
		source_state["origin_root_m"]
		+ source_state["basis_root_from_frame"] * point
	)
	return target_state["basis_root_from_frame"].inverse() * (
		root_point - target_state["origin_root_m"]
	)


func transform_direction(
	direction: Vector3,
	source_frame_id: String,
	target_frame_id: String,
	time_s: float
) -> Vector3:
	if source_frame_id == target_frame_id:
		return direction
	var relative_basis: Basis = get_relative_basis(
		source_frame_id,
		target_frame_id,
		time_s
	)
	return relative_basis * direction


func get_relative_basis(
	source_frame_id: String,
	target_frame_id: String,
	time_s: float
) -> Basis:
	if source_frame_id == target_frame_id:
		return Basis.IDENTITY
	var source_state: Dictionary = get_frame_state_in_root(source_frame_id, time_s)
	var target_state: Dictionary = get_frame_state_in_root(target_frame_id, time_s)
	if source_state.is_empty() or target_state.is_empty():
		return Basis.IDENTITY
	return (
		target_state["basis_root_from_frame"].inverse()
		* source_state["basis_root_from_frame"]
	).orthonormalized()


func transform_spatial_ref(
	spatial_ref: Dictionary,
	target_frame_id: String,
	time_s: float
) -> Dictionary:
	if not SpatialRefScript.is_valid(spatial_ref) or not has_frame(target_frame_id):
		return {}
	if String(spatial_ref.get("universe_id", "")) != universe_id:
		return {}
	if String(spatial_ref.get("instance_id", "")) != instance_id:
		return {}
	if String(spatial_ref.get("space_id", "")) != space_id:
		return {}
	var source_frame_id: String = String(spatial_ref.get("frame_id", ""))
	var source_state: Dictionary = get_frame_state_in_root(source_frame_id, time_s)
	var target_state: Dictionary = get_frame_state_in_root(target_frame_id, time_s)
	if source_state.is_empty() or target_state.is_empty():
		return {}
	var source_position: Vector3 = SpatialRefScript.get_position(spatial_ref)
	var source_velocity: Vector3 = SpatialRefScript.get_linear_velocity(spatial_ref)
	var source_basis: Basis = SpatialRefScript.get_basis(spatial_ref)
	var source_angular_velocity: Vector3 = SpatialRefScript.get_angular_velocity(spatial_ref)
	var source_offset_root: Vector3 = (
		source_state["basis_root_from_frame"] * source_position
	)
	var root_position: Vector3 = source_state["origin_root_m"] + source_offset_root
	var root_velocity: Vector3 = (
		source_state["linear_velocity_root_mps"]
		+ source_state["angular_velocity_root_rps"].cross(source_offset_root)
		+ source_state["basis_root_from_frame"] * source_velocity
	)
	var root_basis: Basis = (
		source_state["basis_root_from_frame"] * source_basis
	).orthonormalized()
	var root_angular_velocity: Vector3 = (
		source_state["angular_velocity_root_rps"]
		+ source_state["basis_root_from_frame"] * source_angular_velocity
	)
	var target_offset_root: Vector3 = root_position - target_state["origin_root_m"]
	var inverse_target_basis: Basis = target_state["basis_root_from_frame"].inverse()
	var target_position: Vector3 = inverse_target_basis * target_offset_root
	var target_velocity: Vector3 = inverse_target_basis * (
		root_velocity
		- target_state["linear_velocity_root_mps"]
		- target_state["angular_velocity_root_rps"].cross(target_offset_root)
	)
	var target_basis: Basis = (inverse_target_basis * root_basis).orthonormalized()
	var target_angular_velocity: Vector3 = inverse_target_basis * (
		root_angular_velocity - target_state["angular_velocity_root_rps"]
	)
	return SpatialRefScript.create(
		target_frame_id,
		target_position,
		target_basis,
		target_velocity,
		target_angular_velocity,
		time_s,
		String(spatial_ref.get("universe_id", SpatialRefScript.DEFAULT_UNIVERSE_ID)),
		String(spatial_ref.get("space_id", SpatialRefScript.DEFAULT_SPACE_ID)),
		String(spatial_ref.get("instance_id", SpatialRefScript.DEFAULT_INSTANCE_ID))
	)


func create_snapshot(time_s: float) -> Dictionary:
	var frame_snapshots: Array[Dictionary] = []
	for frame_id_value in frames.keys():
		var frame_id: String = String(frame_id_value)
		var definition: Dictionary = frames[frame_id]
		var sampled: Dictionary = get_frame_state_in_root(frame_id, time_s)
		frame_snapshots.append({
			"frame_id": frame_id,
			"parent_id": String(definition.get("parent_id", "")),
			"metadata": definition.get("metadata", {}).duplicate(true),
			"origin_root_m": _vector_to_array(sampled.get("origin_root_m", Vector3.ZERO)),
			"linear_velocity_root_mps": _vector_to_array(
				sampled.get("linear_velocity_root_mps", Vector3.ZERO)
			),
		})
	return {
		"schema": SCHEMA,
		"root_frame_id": root_frame_id,
		"universe_id": universe_id,
		"instance_id": instance_id,
		"space_id": space_id,
		"sample_time_s": time_s,
		"frame_count": frames.size(),
		"frames": frame_snapshots,
		"validation_errors": Array(validation_errors),
	}


func _identity_state() -> Dictionary:
	return {
		"origin_root_m": Vector3.ZERO,
		"basis_root_from_frame": Basis.IDENTITY,
		"linear_velocity_root_mps": Vector3.ZERO,
		"angular_velocity_root_rps": Vector3.ZERO,
	}


func _compose_states(parent_state: Dictionary, child_state: Dictionary) -> Dictionary:
	var parent_origin_root: Vector3 = parent_state.get("origin_root_m", Vector3.ZERO)
	var parent_basis: Basis = parent_state.get("basis_root_from_frame", Basis.IDENTITY)
	var parent_linear_velocity: Vector3 = parent_state.get(
		"linear_velocity_root_mps",
		Vector3.ZERO
	)
	var parent_angular_velocity: Vector3 = parent_state.get(
		"angular_velocity_root_rps",
		Vector3.ZERO
	)
	var child_origin_parent: Vector3 = child_state.get("origin_parent_m", Vector3.ZERO)
	var child_basis_parent: Basis = child_state.get(
		"basis_parent_from_child",
		Basis.IDENTITY
	)
	var child_linear_velocity: Vector3 = child_state.get(
		"linear_velocity_parent_mps",
		Vector3.ZERO
	)
	var child_angular_velocity: Vector3 = child_state.get(
		"angular_velocity_parent_rps",
		Vector3.ZERO
	)
	var parent_offset_root: Vector3 = parent_basis * child_origin_parent
	return {
		"origin_root_m": parent_origin_root + parent_offset_root,
		"basis_root_from_frame": (parent_basis * child_basis_parent).orthonormalized(),
		"linear_velocity_root_mps": (
			parent_linear_velocity
			+ parent_angular_velocity.cross(parent_offset_root)
			+ parent_basis * child_linear_velocity
		),
		"angular_velocity_root_rps": (
			parent_angular_velocity + parent_basis * child_angular_velocity
		),
	}


func _is_namespace_identifier(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges().to_lower():
		return false
	for forbidden in ["/", "\\", ":", " ", ".."]:
		if value.contains(forbidden):
			return false
	return true


func _vector_to_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]
