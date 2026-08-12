extends Node3D

const FINGERS: Array[String] = ["thumb", "index", "middle", "ring", "pinky"]
const SEGMENTS: Array[String] = ["Proximal", "Middle", "Distal"]
const ROUND_SEGMENT_SIDES := 8

var _source_names: Array[String] = []
var _canonical_names: Array[String] = []
var _global_rests: Array[Transform3D] = []
var _bone_map: Dictionary = {}


func _init() -> void:
	set_meta("fpe_hand_visual_schema", "planet_simulator.fpe_skinned_hand_visual_asset.v1")
	set_meta("fpe_compatible_skeleton_schema", "planet_simulator.fpe_hand_skeleton.v1")
	set_meta("fpe_rest_space_policy", "CANONICAL_COMPATIBLE_BIND_SPACE")
	set_meta("fpe_hand", "both")
	set_meta("fpe_provider_id", "fpe_s9_rounded_volumetric_skinned_hand_v2")
	set_meta("fpe_visual_quality", "ROUNDED_VOLUMETRIC_V2")

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

	_append_palm_prism(vertices, normals, bones, weights, indices)

	var bind_index := 1
	for finger in FINGERS:
		var lengths := _finger_lengths(finger)
		for segment_index in range(3):
			var length := float(lengths[segment_index])
			var radius := _finger_radius(finger, segment_index)
			_append_rounded_segment(
				vertices,
				normals,
				bones,
				weights,
				indices,
				bind_index,
				_global_rests[bind_index],
				length,
				radius,
				radius * 0.88
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
	material.metallic = 0.0
	mesh.surface_set_material(0, material)
	return mesh


func _append_palm_prism(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	bones: PackedInt32Array,
	weights: PackedFloat32Array,
	indices: PackedInt32Array
) -> void:
	# A slightly tapered octagonal palm keeps the familiar S3 proportions while
	# avoiding the slab/card silhouette that made the first S9 candidate hard to
	# read when the wrist rotated.
	var outline: Array[Vector2] = [
		Vector2(-0.044, 0.030),
		Vector2(0.044, 0.030),
		Vector2(0.054, 0.012),
		Vector2(0.052, -0.070),
		Vector2(0.035, -0.103),
		Vector2(-0.035, -0.103),
		Vector2(-0.052, -0.070),
		Vector2(-0.054, 0.012),
	]
	var half_y := 0.024

	# Top and bottom faces use independent vertices so lighting remains stable.
	var top_base := vertices.size()
	for point in outline:
		_append_weighted_vertex(
			vertices, normals, bones, weights,
			Vector3(point.x, half_y, point.y), Vector3.UP, 0, Transform3D.IDENTITY
		)
	for triangle_index in range(1, outline.size() - 1):
		indices.append(top_base)
		indices.append(top_base + triangle_index)
		indices.append(top_base + triangle_index + 1)

	var bottom_base := vertices.size()
	for point in outline:
		_append_weighted_vertex(
			vertices, normals, bones, weights,
			Vector3(point.x, -half_y, point.y), Vector3.DOWN, 0, Transform3D.IDENTITY
		)
	for triangle_index in range(1, outline.size() - 1):
		indices.append(bottom_base)
		indices.append(bottom_base + triangle_index + 1)
		indices.append(bottom_base + triangle_index)

	for edge_index in range(outline.size()):
		var next_index := (edge_index + 1) % outline.size()
		var a := outline[edge_index]
		var b := outline[next_index]
		var edge := b - a
		var outward := Vector3(edge.y, 0.0, -edge.x).normalized()
		var base := vertices.size()
		_append_weighted_vertex(vertices, normals, bones, weights, Vector3(a.x, -half_y, a.y), outward, 0, Transform3D.IDENTITY)
		_append_weighted_vertex(vertices, normals, bones, weights, Vector3(b.x, -half_y, b.y), outward, 0, Transform3D.IDENTITY)
		_append_weighted_vertex(vertices, normals, bones, weights, Vector3(b.x, half_y, b.y), outward, 0, Transform3D.IDENTITY)
		_append_weighted_vertex(vertices, normals, bones, weights, Vector3(a.x, half_y, a.y), outward, 0, Transform3D.IDENTITY)
		indices.append(base + 0)
		indices.append(base + 1)
		indices.append(base + 2)
		indices.append(base + 0)
		indices.append(base + 2)
		indices.append(base + 3)


func _append_rounded_segment(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	bones: PackedInt32Array,
	weights: PackedFloat32Array,
	indices: PackedInt32Array,
	bind_index: int,
	global_rest: Transform3D,
	length: float,
	radius_x: float,
	radius_y: float
) -> void:
	# Five rings approximate the old capsule fingers but stay inside a single
	# weighted ArrayMesh. Small overlap at each joint avoids visible gaps while
	# every phalanx remains rigidly owned by its canonical bone.
	var ring_z: Array[float] = [
		length * 0.045,
		-length * 0.08,
		-length * 0.50,
		-length * 0.91,
		-length * 1.035,
	]
	var ring_scale: Array[float] = [0.62, 0.94, 1.0, 0.88, 0.58]
	var ring_bases: Array[int] = []

	for ring_index in range(ring_z.size()):
		var base := vertices.size()
		ring_bases.append(base)
		for side_index in range(ROUND_SEGMENT_SIDES):
			var angle := TAU * float(side_index) / float(ROUND_SEGMENT_SIDES)
			var cx := cos(angle)
			var sy := sin(angle)
			var scale := ring_scale[ring_index]
			var local := Vector3(
				cx * radius_x * scale,
				sy * radius_y * scale,
				ring_z[ring_index]
			)
			var local_normal := Vector3(cx, sy, 0.0).normalized()
			_append_weighted_vertex(
				vertices, normals, bones, weights,
				local, local_normal, bind_index, global_rest
			)

	for ring_index in range(ring_bases.size() - 1):
		var a_base := ring_bases[ring_index]
		var b_base := ring_bases[ring_index + 1]
		for side_index in range(ROUND_SEGMENT_SIDES):
			var next_side := (side_index + 1) % ROUND_SEGMENT_SIDES
			indices.append(a_base + side_index)
			indices.append(b_base + side_index)
			indices.append(b_base + next_side)
			indices.append(a_base + side_index)
			indices.append(b_base + next_side)
			indices.append(a_base + next_side)

	var proximal_center := vertices.size()
	_append_weighted_vertex(
		vertices, normals, bones, weights,
		Vector3(0.0, 0.0, ring_z[0]), Vector3(0.0, 0.0, 1.0), bind_index, global_rest
	)
	var proximal_ring := ring_bases[0]
	for side_index in range(ROUND_SEGMENT_SIDES):
		var next_side := (side_index + 1) % ROUND_SEGMENT_SIDES
		indices.append(proximal_center)
		indices.append(proximal_ring + next_side)
		indices.append(proximal_ring + side_index)

	var distal_center := vertices.size()
	_append_weighted_vertex(
		vertices, normals, bones, weights,
		Vector3(0.0, 0.0, ring_z[ring_z.size() - 1]), Vector3(0.0, 0.0, -1.0), bind_index, global_rest
	)
	var distal_ring := ring_bases[ring_bases.size() - 1]
	for side_index in range(ROUND_SEGMENT_SIDES):
		var next_side := (side_index + 1) % ROUND_SEGMENT_SIDES
		indices.append(distal_center)
		indices.append(distal_ring + side_index)
		indices.append(distal_ring + next_side)


func _append_weighted_vertex(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	bones: PackedInt32Array,
	weights: PackedFloat32Array,
	local_position: Vector3,
	local_normal: Vector3,
	bind_index: int,
	global_rest: Transform3D
) -> void:
	vertices.append(global_rest * local_position)
	normals.append((global_rest.basis * local_normal).normalized())
	bones.append(bind_index)
	bones.append(0)
	bones.append(0)
	bones.append(0)
	weights.append(1.0)
	weights.append(0.0)
	weights.append(0.0)
	weights.append(0.0)


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


func _finger_radius(finger: String, segment_index: int) -> float:
	var radius := 0.0140
	match finger:
		"thumb":
			radius = 0.0155
		"middle":
			radius = 0.0145
		"ring":
			radius = 0.0135
		"pinky":
			radius = 0.0120
	var taper := [1.0, 0.93, 0.84]
	return radius * float(taper[clampi(segment_index, 0, 2)])
