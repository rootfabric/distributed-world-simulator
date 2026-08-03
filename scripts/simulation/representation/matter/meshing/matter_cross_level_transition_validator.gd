extends RefCounted

const RepresentationUtils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const MeshData = preload("res://scripts/simulation/representation/matter/meshing/contracts/matter_multiresolution_mesh_data.gd")
const Transition = preload("res://scripts/simulation/representation/matter/meshing/contracts/matter_cross_level_transition.gd")
const Boundary = preload("res://scripts/simulation/representation/matter/meshing/matter_mesh_boundary.gd")
const TransitionBuilder = preload("res://scripts/simulation/representation/matter/meshing/matter_cross_level_transition_builder.gd")

const TOLERANCE_M: float = 0.000001


static func validate_coverage(
	fine_mesh: Dictionary,
	coarse_mesh: Dictionary,
	transition: Dictionary
) -> Dictionary:
	if not bool(MeshData.validate(fine_mesh).get("success", false)) \
		or not bool(MeshData.validate(coarse_mesh).get("success", false)):
		return RepresentationUtils.failure("INVALID_MATTER_TRANSITION_VALIDATION_MESH")
	var checked: Dictionary = Transition.validate(transition)
	if not bool(checked.get("success", false)):
		return checked
	if transition["fine_representation_key"] != fine_mesh["representation_key"] \
		or transition["coarse_representation_key"] != coarse_mesh["representation_key"]:
		return RepresentationUtils.failure("MATTER_TRANSITION_VALIDATION_KEY_MISMATCH")
	if String(transition["fine_artifact_hash"]) != String(fine_mesh["content_hash"]) \
		or String(transition["coarse_artifact_hash"]) != String(coarse_mesh["content_hash"]) \
		or not Vector3(transition["origin_body_local_m"]).is_equal_approx(fine_mesh["origin_body_local_m"]):
		return RepresentationUtils.failure("MATTER_TRANSITION_VALIDATION_ARTIFACT_MISMATCH")
	var face: Dictionary = Boundary.shared_face(fine_mesh, coarse_mesh)
	if face.is_empty() \
		or int(face["axis"]) != int(transition["axis"]) \
		or int(face["direction"]) != int(transition["direction"]) \
		or absf(float(face["plane_coordinate_m"]) - float(transition["plane_coordinate_m"])) > TOLERANCE_M:
		return RepresentationUtils.failure("MATTER_TRANSITION_SHARED_FACE_MISMATCH")
	var segments: Array = Boundary.segments(
		fine_mesh, int(transition["axis"]), float(transition["plane_coordinate_m"]), TOLERANCE_M
	)
	if segments.size() != int(transition["boundary_segment_count"]) \
		or Boundary.segment_hash(segments, TOLERANCE_M) != String(transition["boundary_segment_hash"]):
		return RepresentationUtils.failure("MATTER_TRANSITION_BOUNDARY_COVERAGE_MISMATCH")
	var expected_depth_m: float = maxf(
		float(coarse_mesh["sample_spacing_m"]), float(coarse_mesh["geometric_error_m"])
	)
	if not is_equal_approx(float(transition["skirt_depth_m"]), expected_depth_m) \
		or not is_equal_approx(float(transition["geometric_error_m"]), float(coarse_mesh["geometric_error_m"])):
		return RepresentationUtils.failure("MATTER_TRANSITION_DEPTH_RULE_MISMATCH")
	var axis: int = int(transition["axis"])
	var direction: int = int(transition["direction"])
	var plane: float = float(transition["plane_coordinate_m"])
	var extruded_plane: float = plane + float(direction) * float(transition["skirt_depth_m"])
	var origin: Vector3 = transition["origin_body_local_m"]
	var vertices: PackedVector3Array = transition["vertices"]
	for segment_index in range(int(transition["boundary_segment_count"])):
		var base: int = segment_index * 8
		for local_index in [0, 1, 4, 5]:
			var world_base: Vector3 = origin + vertices[base + local_index]
			if absf(world_base[axis] - plane) > TOLERANCE_M:
				return RepresentationUtils.failure("MATTER_TRANSITION_BASE_PLANE_MISMATCH")
		for local_index in [2, 3, 6, 7]:
			var world_extruded: Vector3 = origin + vertices[base + local_index]
			if absf(world_extruded[axis] - extruded_plane) > TOLERANCE_M:
				return RepresentationUtils.failure("MATTER_TRANSITION_EXTRUSION_MISMATCH")
	var expected: Dictionary = TransitionBuilder.build(fine_mesh, coarse_mesh)
	if expected.is_empty() or String(expected["content_hash"]) != String(transition["content_hash"]):
		return RepresentationUtils.failure("MATTER_TRANSITION_GEOMETRY_MISMATCH")
	return RepresentationUtils.success({
		"boundary_segment_count": segments.size(),
		"boundary_segment_hash": String(transition["boundary_segment_hash"]),
		"skirt_depth_m": float(transition["skirt_depth_m"]),
	})
