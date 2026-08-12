extends Node3D

const FINGERS: Array[String] = ["thumb", "index", "middle", "ring", "pinky"]
const SEGMENTS: Array[String] = ["Proximal", "Middle", "Distal"]

var _source_names: Array[String] = []
var _canonical_names: Array[String] = []
var _global_rests: Array[Transform3D] = []
var _bone_map: Dictionary = {}


func _init() -> void:
	set_meta("fpe_hand_visual_schema", "planet_simulator.fpe_skinned_hand_visual_asset.v1")
	set_meta("fpe_compatible_skeleton_schema", "planet_simulator.fpe_hand_skeleton.v1")
	set_meta("fpe_rest_space_policy", "CANONICAL_COMPATIBLE_BIND_SPACE")
	set_meta("fpe_hand", "both")
	set_meta("fpe_provider_id", "fpe_s9_volumetric_skinned_hand_v1")

	_build_bind_layout()
	set_meta("fpe_bone_map", _bone_map.duplicate(true))

	var visual := MeshInstance3D.new()
	visual.name = "VolumetricSkinnedHand"
	visual.mesh = _build_weighted_mesh()
	visual.skin = _build_named_skin()
	add_child(visual)


func _build_bind_layout() -> void:
	_source_names.clear()
	_canonical_names.clear()
	_global_rests.clear()
	_bone_map.clear()

	_register_bind("src_palm", "Palm", Transform3D.IDENTITY)
	var side := 1.0
	_add_finger_layout(
		"thumb",
		Vector3(0.052 * side, -0.005, -0.018),
		[0.052, 0.043, 0.034],
		Basis.from_euler(Vector3(deg_to_rad(-8.0), deg_to_rad(34.0 * side), deg_to_rad(-18.0 * side)))
	)
	_add_finger_layout("index", Vector3(0.040 * side, 0.0, -0.054), [0.062, 0.050, 0.038])
	_add_finger_layout("middle", Vector3(0.013 * side, 0.0, -0.058), [0.068, 0.054, 0.040])
	_add_finger_layout("ring", Vector3(-0.015 * side, -0.002, -0.054), [0.064, 0.050, 0.037])
	_add_finger_layout("pinky", Vector3(-0.040 * side, -0.004, -0.047), [0.054, 0.043, 0.032])


func _add_finger_layout(
	finger: String,
	base_origin: Vector3,
	lengths: Array,
	base_basis: Basis = Basis.IDENTITY
) -> void:
	var parent_global := Transform3D.IDENTITY
	for segment_index in range(3):
		var origin := base_origin if segment_index == 0 else Vector3(0.0, 0.0, -float(lengths[segment_index - 1]))
		var basis := base_basis if segment_index == 0 else Basis.IDENTITY
		var local_rest := Transform3D(basis, origin)
		var global_rest := parent_global * local_rest
		var canonical := "%s%s" % [finger.capitalize(), SEGMENTS[segment_index]]
		var source := "src_%s_%d" % [finger, segment_index + 1]
		_register_bind(source, canonical, global_rest)
		parent_global = global_rest


func _register_bind(source_name: String, canonical_name: String, global_rest: Transform3D) -> void:
	_source_names.append(source_name)
	_canonical_names.append(canonical_name)
	_global_rests.append(global_rest)
	_bone_map[source_name] = canonical_name


func _build_weighted_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()

	_append_box(
		vertices,
		normals,
		bones,
		weights,
		indices,
		0,
		Transform3D.IDENTITY,
		Vector3(0.0, 0.0, -0.028),
		Vector3(0.108, 0.046, 0.118)
	)

	var bind_index := 1
	for finger in FINGERS:
		var lengths := _finger_lengths(finger)
		for segment_index in range(3):
			var length := float(lengths[segment_index])
			var width := _finger_width(finger, segment_index)
			var thickness := width * 0.82
			_append_box(
				vertices,
				normals,
				bones,
				weights,
				indices,
				bind_index,
				_global_rests[bind_index],
				Vector3(0.0, 0.0, -length * 0.48),
				Vector3(width, thickness, length * 1.04)
			)
			bind_index += 1

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.76, 0.56, 0.44, 1.0)
	material.roughness = 0.86
	mesh.surface_set_material(0, material)
	return mesh


func _append_box(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	bones: PackedInt32Array,
	weights: PackedFloat32Array,
	indices: PackedInt32Array,
	bind_index: int,
	global_rest: Transform3D,
	center_local: Vector3,
	size: Vector3
) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var corners := [
		Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz), Vector3(hx, hy, -hz), Vector3(-hx, hy, -hz),
		Vector3(-hx, -hy, hz), Vector3(hx, -hy, hz), Vector3(hx, hy, hz), Vector3(-hx, hy, hz),
	]
	var faces := [
		[0, 1, 2, 3, Vector3(0, 0, -1)],
		[5, 4, 7, 6, Vector3(0, 0, 1)],
		[4, 0, 3, 7, Vector3(-1, 0, 0)],
		[1, 5, 6, 2, Vector3(1, 0, 0)],
		[3, 2, 6, 7, Vector3(0, 1, 0)],
		[4, 5, 1, 0, Vector3(0, -1, 0)],
	]
	for face in faces:
		var base := vertices.size()
		var local_normal: Vector3 = face[4]
		var world_normal := (global_rest.basis * local_normal).normalized()
		for corner_index in range(4):
			var local: Vector3 = corners[int(face[corner_index])] + center_local
			vertices.append(global_rest * local)
			normals.append(world_normal)
			bones.append(bind_index)
			bones.append(0)
			bones.append(0)
			bones.append(0)
			weights.append(1.0)
			weights.append(0.0)
			weights.append(0.0)
			weights.append(0.0)
		indices.append(base + 0)
		indices.append(base + 1)
		indices.append(base + 2)
		indices.append(base + 0)
		indices.append(base + 2)
		indices.append(base + 3)


func _build_named_skin() -> Skin:
	var skin := Skin.new()
	skin.set_bind_count(_source_names.size())
	for bind_index in range(_source_names.size()):
		skin.set_bind_name(bind_index, StringName(_source_names[bind_index]))
		skin.set_bind_pose(bind_index, _global_rests[bind_index].affine_inverse())
	return skin


func _finger_lengths(finger: String) -> Array:
	match finger:
		"thumb":
			return [0.052, 0.043, 0.034]
		"index":
			return [0.062, 0.050, 0.038]
		"middle":
			return [0.068, 0.054, 0.040]
		"ring":
			return [0.064, 0.050, 0.037]
		_:
			return [0.054, 0.043, 0.032]


func _finger_width(finger: String, segment_index: int) -> float:
	var base := 0.025
	match finger:
		"thumb":
			base = 0.029
		"middle":
			base = 0.026
		"ring":
			base = 0.024
		"pinky":
			base = 0.021
	return base * (1.0 - float(segment_index) * 0.11)
