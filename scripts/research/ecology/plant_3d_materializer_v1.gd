extends RefCounted

const RenderDescription = preload("res://scripts/research/ecology/plant_render_description_v1.gd")
const RendererProfile = preload("res://scripts/research/ecology/plant_renderer_profile_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.plant_3d_materialization.v1"
const VERSION := "1.0.0"

static func build(description: Dictionary, profile: Dictionary) -> Dictionary:
	if not bool(RenderDescription.validate(description).get("success", false)):
		return {}
	if not bool(RendererProfile.validate(profile).get("success", false)):
		return {}
	var graph_hash := String(description["source_graph_hash"])
	var description_hash := String(description["render_description_hash"])
	var profile_id := String(profile["profile_id"])
	var active_branches := _active_branches(description, profile)
	var active_foliage := _active_foliage(description, profile)
	var sides := maxi(3, int(profile.get("branch_sides", 0))) if not active_branches.is_empty() else 0
	var branch_mesh: ArrayMesh = null
	if not active_branches.is_empty():
		branch_mesh = _build_branch_mesh(active_branches, sides)
	var foliage_multimesh: MultiMesh = null
	if not active_foliage.is_empty():
		foliage_multimesh = _build_foliage_multimesh(active_foliage)
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"derived_representation": true,
		"source_graph_hash": graph_hash,
		"render_description_hash": description_hash,
		"profile_id": profile_id,
		"profile_hash": String(profile["profile_hash"]),
		"branch_sides": sides,
		"branch_count": active_branches.size(),
		"foliage_instance_count": active_foliage.size(),
		"branch_vertex_count": _mesh_vertex_count(branch_mesh),
		"branch_triangle_count": _mesh_vertex_count(branch_mesh) / 3,
		"branch_mesh": branch_mesh,
		"foliage_multimesh": foliage_multimesh,
	}
	result["geometry_hash"] = compute_geometry_hash(description, profile, active_branches, active_foliage)
	return result

static func compute_geometry_hash(description: Dictionary, profile: Dictionary, branches: Array = [], foliage: Array = []) -> String:
	if branches.is_empty() and foliage.is_empty():
		branches = _active_branches(description, profile)
		foliage = _active_foliage(description, profile)
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		String(description.get("source_graph_hash", "")),
		String(description.get("render_description_hash", "")),
		String(profile.get("profile_id", "")),
		String(profile.get("profile_hash", "")),
	])
	for branch in branches:
		tokens.append("B|%s|%s|%s|%.9f|%.9f" % [
			String(branch.get("segment_id", "")),
			_vec_token(Array(branch.get("start", []))),
			_vec_token(Array(branch.get("end", []))),
			float(branch.get("radius_start_m", 0.0)),
			float(branch.get("radius_end_m", 0.0)),
		])
	for anchor in foliage:
		tokens.append("F|%s|%s|%.9f|%.9f" % [
			String(anchor.get("anchor_id", "")),
			_vec_token(Array(anchor.get("position", []))),
			float(anchor.get("size_m", 0.0)),
			float(anchor.get("azimuth_deg", 0.0)),
		])
	return "\n".join(tokens).sha256_text()

static func _build_branch_mesh(branches: Array, sides: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for branch in branches:
		var a := _vec3(Array(branch["start"]))
		var b := _vec3(Array(branch["end"]))
		var direction := b - a
		if direction.length_squared() <= 0.0000000001:
			continue
		var axis := direction.normalized()
		var reference := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.94 else Vector3.RIGHT
		var u := axis.cross(reference).normalized()
		var v := axis.cross(u).normalized()
		var r0 := maxf(0.0005, float(branch["radius_start_m"]))
		var r1 := maxf(0.0005, float(branch["radius_end_m"]))
		for side in range(sides):
			var t0 := TAU * float(side) / float(sides)
			var t1 := TAU * float(side + 1) / float(sides)
			var n0 := (u * cos(t0) + v * sin(t0)).normalized()
			var n1 := (u * cos(t1) + v * sin(t1)).normalized()
			var a0 := a + n0 * r0
			var a1 := a + n1 * r0
			var b0 := b + n0 * r1
			var b1 := b + n1 * r1
			_add_vertex(st, a0, n0)
			_add_vertex(st, b0, n0)
			_add_vertex(st, b1, n1)
			_add_vertex(st, a0, n0)
			_add_vertex(st, b1, n1)
			_add_vertex(st, a1, n1)
	var mesh := st.commit()
	return mesh as ArrayMesh

static func _build_foliage_multimesh(anchors: Array) -> MultiMesh:
	var leaf_mesh := QuadMesh.new()
	leaf_mesh.size = Vector2(1.0, 1.65)
	var leaf_material := StandardMaterial3D.new()
	leaf_material.albedo_color = Color(0.20, 0.68, 0.28)
	leaf_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	leaf_mesh.material = leaf_material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = leaf_mesh
	multimesh.instance_count = anchors.size()
	for index in range(anchors.size()):
		var anchor: Dictionary = anchors[index]
		var p := _vec3(Array(anchor["position"]))
		var size := maxf(0.01, float(anchor["size_m"]))
		var yaw := deg_to_rad(float(anchor["azimuth_deg"]))
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(size, size, size))
		multimesh.set_instance_transform(index, Transform3D(basis, p))
	return multimesh

static func _active_branches(description: Dictionary, profile: Dictionary) -> Array:
	var mode := String(profile.get("branch_mode", "NONE"))
	if mode in ["NONE", "LINES"]:
		return []
	var source: Array = description.get("branches", [])
	var result: Array = []
	if mode == "TRUNK_ONLY":
		for branch in source:
			if bool(branch.get("main_axis", false)):
				result.append(branch)
		return result
	var count := clampi(int(ceil(float(source.size()) * float(profile.get("branch_fraction", 0.0)))), 0, source.size())
	for index in range(count):
		result.append(source[index])
	return result

static func _active_foliage(description: Dictionary, profile: Dictionary) -> Array:
	if String(profile.get("foliage_mode", "NONE")) == "NONE":
		return []
	var source: Array = description.get("foliage_anchors", [])
	var count := clampi(int(ceil(float(source.size()) * float(profile.get("foliage_fraction", 0.0)))), 0, source.size())
	var result: Array = []
	for index in range(count):
		result.append(source[index])
	return result

static func _add_vertex(st: SurfaceTool, position: Vector3, normal: Vector3) -> void:
	st.set_normal(normal)
	st.add_vertex(position)

static func _mesh_vertex_count(mesh: ArrayMesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	var arrays := mesh.surface_get_arrays(0)
	return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()

static func _vec3(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

static func _vec_token(values: Array) -> String:
	if values.size() != 3:
		return "INVALID"
	return "%.9f,%.9f,%.9f" % [float(values[0]), float(values[1]), float(values[2])]
