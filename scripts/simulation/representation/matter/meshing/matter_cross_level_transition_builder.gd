extends RefCounted

const RepresentationUtils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const RepresentationKey = preload("res://scripts/simulation/representation/contracts/representation_key.gd")
const MeshData = preload("res://scripts/simulation/representation/matter/meshing/contracts/matter_multiresolution_mesh_data.gd")
const Transition = preload("res://scripts/simulation/representation/matter/meshing/contracts/matter_cross_level_transition.gd")
const Boundary = preload("res://scripts/simulation/representation/matter/meshing/matter_mesh_boundary.gd")

const AXIS_NAMES: Array[String] = ["x", "y", "z"]


static func build(fine_mesh: Dictionary, coarse_mesh: Dictionary) -> Dictionary:
	if not bool(MeshData.validate(fine_mesh).get("success", false)) \
		or not bool(MeshData.validate(coarse_mesh).get("success", false)):
		return {}
	var fine_key: Dictionary = fine_mesh["representation_key"]
	var coarse_key: Dictionary = coarse_mesh["representation_key"]
	if int(coarse_key["lod_level"]) != int(fine_key["lod_level"]) + 1:
		return {}
	var fine_source: Dictionary = fine_key["source_revision"]
	var coarse_source: Dictionary = coarse_key["source_revision"]
	if String(fine_source["source_id"]) != String(coarse_source["source_id"]) \
		or int(fine_source["authority_epoch"]) != int(coarse_source["authority_epoch"]):
		return {}
	var face: Dictionary = Boundary.shared_face(fine_mesh, coarse_mesh)
	if face.is_empty():
		return {}
	var axis: int = int(face["axis"])
	var direction: int = int(face["direction"])
	var plane_coordinate_m: float = float(face["plane_coordinate_m"])
	var segments: Array = Boundary.segments(fine_mesh, axis, plane_coordinate_m)
	var boundary_hash: String = Boundary.segment_hash(segments)
	var pair_descriptor: Array = [
		{"role": "FINE", "key_checksum": String(fine_key["checksum"]), "artifact_hash": String(fine_mesh["content_hash"])},
		{"role": "COARSE", "key_checksum": String(coarse_key["checksum"]), "artifact_hash": String(coarse_mesh["content_hash"])},
	]
	var pair_hash: String = RepresentationUtils.payload_hash(pair_descriptor)
	var dependency_hash: String = RepresentationUtils.payload_hash({
		"fine_source_checksum": String(fine_source["checksum"]),
		"coarse_source_checksum": String(coarse_source["checksum"]),
		"boundary_segment_hash": boundary_hash,
	})
	var transition_source: Dictionary = SourceRevision.create(
		"MATTER",
		String(fine_source["source_id"]),
		int(fine_source["authority_epoch"]),
		maxi(int(fine_source["source_revision"]), int(coarse_source["source_revision"])),
		pair_hash,
		dependency_hash
	)
	if transition_source.is_empty():
		return {}
	var direction_name: String = "positive" if direction > 0 else "negative"
	var variant_id: String = "representation-variant/matter-transition/%s-%s/lod-%d-to-%d" % [
		AXIS_NAMES[axis], direction_name, int(fine_key["lod_level"]), int(coarse_key["lod_level"])
	]
	var transition_key: Dictionary = RepresentationKey.create(
		transition_source,
		String(fine_key["scope_id"]),
		int(fine_key["lod_level"]),
		String(fine_key["artifact_kind"]),
		variant_id
	)
	if transition_key.is_empty():
		return {}
	var skirt_depth_m: float = maxf(
		float(coarse_mesh["sample_spacing_m"]), float(coarse_mesh["geometric_error_m"])
	)
	var offset := Vector3.ZERO
	offset[axis] = float(direction) * skirt_depth_m
	var origin: Vector3 = fine_mesh["origin_body_local_m"]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for raw_segment in segments:
		var segment: Dictionary = raw_segment
		var point_a: Vector3 = segment["point_a"]
		var point_b: Vector3 = segment["point_b"]
		var point_c: Vector3 = point_b + offset
		var point_d: Vector3 = point_a + offset
		var tangent: Vector3 = point_b - point_a
		var face_normal: Vector3 = tangent.cross(offset)
		if face_normal.length_squared() <= 0.000000000001:
			continue
		face_normal = face_normal.normalized()
		var color_a: Color = segment["color_a"]
		var color_b: Color = segment["color_b"]
		var start: int = vertices.size()
		for point in [point_a, point_b, point_c, point_d]:
			vertices.append(Vector3(point) - origin)
			normals.append(face_normal)
		for color in [color_a, color_b, color_b, color_a]:
			colors.append(color)
		indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))
		var back_start: int = vertices.size()
		for point in [point_a, point_b, point_c, point_d]:
			vertices.append(Vector3(point) - origin)
			normals.append(-face_normal)
		for color in [color_a, color_b, color_b, color_a]:
			colors.append(color)
		indices.append_array(PackedInt32Array([
			back_start, back_start + 2, back_start + 1,
			back_start, back_start + 3, back_start + 2,
		]))
	return Transition.create(
		transition_key,
		fine_key,
		coarse_key,
		String(fine_mesh["content_hash"]),
		String(coarse_mesh["content_hash"]),
		axis,
		direction,
		plane_coordinate_m,
		skirt_depth_m,
		float(coarse_mesh["geometric_error_m"]),
		segments.size(),
		boundary_hash,
		origin,
		vertices,
		normals,
		colors,
		indices
	)
