extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const C = preload("res://scripts/construction/proxies/construction_proxy_contract_utils.gd")
const Artifact = preload("res://scripts/construction/proxies/construction_proxy_artifact.gd")
const Descriptor = preload("res://scripts/construction/proxies/construction_proxy_mesh_descriptor.gd")
const MaterialLibrary = preload("res://scripts/construction/proxies/construction_proxy_material_library.gd")

const GRID_FIELDS: Array[String] = ["kind", "axis", "direction", "plane_q2", "u", "v", "width", "height"]
const FALLBACK_FIELDS: Array[String] = ["kind", "axis", "direction", "position_m", "dimensions_m"]
const BYTES_PER_VERTEX := 32
const BYTES_PER_INDEX := 4

var _materials

func _init(material_library = null) -> void:
	_materials = material_library if material_library != null else MaterialLibrary.new()

func compile(artifact: Dictionary) -> Dictionary:
	var checked: Dictionary = Artifact.validate(artifact)
	if not bool(checked.get("success", false)):
		return checked
	var mesh := ArrayMesh.new()
	mesh.resource_name = "ConstructionProxy_%s" % String(artifact["content_hash"]).left(16)
	mesh.set_meta("construction_proxy_artifact_id", String(artifact["artifact_id"]))
	mesh.set_meta("construction_proxy_content_hash", String(artifact["content_hash"]))
	mesh.set_meta("construction_proxy_backend", Descriptor.BACKEND)

	var material_keys: Array = []
	var signature_surfaces: Array = []
	var total_vertices := 0
	var total_indices := 0
	for batch_value in artifact["material_batches"]:
		var batch: Dictionary = batch_value
		if int(batch["quad_count"]) == 0:
			return C.failure("CONSTRUCTION_PROXY_EMPTY_MATERIAL_BATCH")
		var surface_result: Dictionary = _compile_surface(batch)
		if not bool(surface_result.get("success", false)):
			return surface_result
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = surface_result["vertices"]
		arrays[Mesh.ARRAY_NORMAL] = surface_result["normals"]
		arrays[Mesh.ARRAY_TEX_UV] = surface_result["uvs"]
		arrays[Mesh.ARRAY_INDEX] = surface_result["indices"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var surface_index := mesh.get_surface_count() - 1
		var material_key := String(batch["material_key"])
		var material_result: Dictionary = _materials.resolve(material_key)
		if not bool(material_result.get("success", false)):
			return material_result
		mesh.surface_set_name(surface_index, material_key)
		mesh.surface_set_material(surface_index, material_result["material"])
		material_keys.append(material_key)
		total_vertices += int(surface_result["vertex_count"])
		total_indices += int(surface_result["index_count"])
		signature_surfaces.append(surface_result["signature_payload"])

	var signature_payload := {
		"backend": Descriptor.BACKEND,
		"artifact_content_hash": String(artifact["content_hash"]),
		"surfaces": signature_surfaces,
	}
	var mesh_signature := Utils.payload_hash(signature_payload)
	var estimated_gpu_bytes := total_vertices * BYTES_PER_VERTEX + total_indices * BYTES_PER_INDEX
	var descriptor := Descriptor.create(
		artifact,
		material_keys,
		total_vertices,
		total_indices,
		artifact["bounds_min_m"],
		artifact["bounds_max_m"],
		estimated_gpu_bytes,
		mesh_signature
	)
	checked = Descriptor.validate(descriptor)
	if not bool(checked.get("success", false)):
		return checked
	mesh.set_meta("construction_proxy_mesh_signature", mesh_signature)
	mesh.set_meta("construction_proxy_vertex_count", total_vertices)
	mesh.set_meta("construction_proxy_triangle_count", total_indices / 3)
	return C.success({"mesh": mesh, "descriptor": descriptor})

func get_material_count() -> int:
	return _materials.get_material_count()

func _compile_surface(batch: Dictionary) -> Dictionary:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var signature_quads: Array = []
	for quad_value in batch["quads"]:
		if typeof(quad_value) != TYPE_DICTIONARY:
			return C.failure("INVALID_CONSTRUCTION_PROXY_MESH_QUAD")
		var quad: Dictionary = quad_value
		var quad_result: Dictionary = _quad_geometry(quad)
		if not bool(quad_result.get("success", false)):
			return quad_result
		var base := vertices.size()
		var quad_vertices: Array = quad_result["vertices"]
		var quad_uvs: Array = quad_result["uvs"]
		var normal: Vector3 = quad_result["normal"]
		for index in range(4):
			vertices.append(quad_vertices[index])
			normals.append(normal)
			uvs.append(quad_uvs[index])
		indices.append(base)
		indices.append(base + 1)
		indices.append(base + 2)
		indices.append(base)
		indices.append(base + 2)
		indices.append(base + 3)
		signature_quads.append(quad_result["signature"])
	return C.success({
		"vertices": vertices,
		"normals": normals,
		"uvs": uvs,
		"indices": indices,
		"vertex_count": vertices.size(),
		"index_count": indices.size(),
		"signature_payload": {
			"material_key": String(batch["material_key"]),
			"quads": signature_quads,
		},
	})

func _quad_geometry(quad: Dictionary) -> Dictionary:
	var kind := String(quad.get("kind", ""))
	if kind == "GRID_QUAD":
		var exact_grid := Utils.validate_exact_fields(quad, GRID_FIELDS)
		if not bool(exact_grid.get("success", false)):
			return exact_grid
		if not _valid_axis_direction(quad):
			return C.failure("INVALID_CONSTRUCTION_PROXY_GRID_QUAD_AXIS")
		for field in ["plane_q2", "u", "v", "width", "height"]:
			if not Utils.is_json_integer(quad.get(field)):
				return C.failure("INVALID_CONSTRUCTION_PROXY_GRID_QUAD_COORDINATE")
		if int(quad["width"]) < 1 or int(quad["height"]) < 1:
			return C.failure("INVALID_CONSTRUCTION_PROXY_GRID_QUAD_SIZE")
		var plane := float(quad["plane_q2"]) * 0.5
		var u0 := float(quad["u"]) - 0.5
		var u1 := float(quad["u"] + quad["width"]) - 0.5
		var v0 := float(quad["v"]) - 0.5
		var v1 := float(quad["v"] + quad["height"]) - 0.5
		return _oriented_quad(String(quad["axis"]), int(quad["direction"]), plane, u0, u1, v0, v1, {
			"kind": kind,
			"axis": String(quad["axis"]),
			"direction": int(quad["direction"]),
			"plane_q2": int(quad["plane_q2"]),
			"u": int(quad["u"]),
			"v": int(quad["v"]),
			"width": int(quad["width"]),
			"height": int(quad["height"]),
		})
	if kind == "FALLBACK_QUAD":
		var exact_fallback := Utils.validate_exact_fields(quad, FALLBACK_FIELDS)
		if not bool(exact_fallback.get("success", false)):
			return exact_fallback
		if not _valid_axis_direction(quad) or not C.finite_vector(quad.get("position_m"), 3) or not C.finite_vector(quad.get("dimensions_m"), 3):
			return C.failure("INVALID_CONSTRUCTION_PROXY_FALLBACK_QUAD")
		var dimensions: Array = quad["dimensions_m"]
		for dimension in dimensions:
			if float(dimension) <= 0.0:
				return C.failure("INVALID_CONSTRUCTION_PROXY_FALLBACK_QUAD_SIZE")
		var axis := String(quad["axis"])
		var direction := int(quad["direction"])
		var position: Array = quad["position_m"]
		var plane := 0.0
		var u0 := 0.0
		var u1 := 0.0
		var v0 := 0.0
		var v1 := 0.0
		match axis:
			"X":
				plane = float(position[0]) + float(direction) * float(dimensions[0]) * 0.5
				u0 = float(position[1]) - float(dimensions[1]) * 0.5
				u1 = float(position[1]) + float(dimensions[1]) * 0.5
				v0 = float(position[2]) - float(dimensions[2]) * 0.5
				v1 = float(position[2]) + float(dimensions[2]) * 0.5
			"Y":
				plane = float(position[1]) + float(direction) * float(dimensions[1]) * 0.5
				u0 = float(position[0]) - float(dimensions[0]) * 0.5
				u1 = float(position[0]) + float(dimensions[0]) * 0.5
				v0 = float(position[2]) - float(dimensions[2]) * 0.5
				v1 = float(position[2]) + float(dimensions[2]) * 0.5
			"Z":
				plane = float(position[2]) + float(direction) * float(dimensions[2]) * 0.5
				u0 = float(position[0]) - float(dimensions[0]) * 0.5
				u1 = float(position[0]) + float(dimensions[0]) * 0.5
				v0 = float(position[1]) - float(dimensions[1]) * 0.5
				v1 = float(position[1]) + float(dimensions[1]) * 0.5
		return _oriented_quad(axis, direction, plane, u0, u1, v0, v1, {
			"kind": kind,
			"axis": axis,
			"direction": direction,
			"position_m": Array(position).duplicate(true),
			"dimensions_m": Array(dimensions).duplicate(true),
		})
	return C.failure("UNSUPPORTED_CONSTRUCTION_PROXY_MESH_QUAD_KIND")

func _oriented_quad(axis: String, direction: int, plane: float, u0: float, u1: float, v0: float, v1: float, signature: Dictionary) -> Dictionary:
	var corners: Array = []
	match axis:
		"X": corners = [Vector3(plane, u0, v0), Vector3(plane, u1, v0), Vector3(plane, u1, v1), Vector3(plane, u0, v1)]
		"Y": corners = [Vector3(u0, plane, v0), Vector3(u1, plane, v0), Vector3(u1, plane, v1), Vector3(u0, plane, v1)]
		"Z": corners = [Vector3(u0, v0, plane), Vector3(u1, v0, plane), Vector3(u1, v1, plane), Vector3(u0, v1, plane)]
		_: return C.failure("INVALID_CONSTRUCTION_PROXY_MESH_AXIS")
	var desired := _normal(axis, direction)
	var actual: Vector3 = (corners[1] - corners[0]).cross(corners[2] - corners[0]).normalized()
	var uv_corners: Array = [Vector2(0.0, 0.0), Vector2(u1 - u0, 0.0), Vector2(u1 - u0, v1 - v0), Vector2(0.0, v1 - v0)]
	if actual.dot(desired) < 0.0:
		corners = [corners[0], corners[3], corners[2], corners[1]]
		uv_corners = [uv_corners[0], uv_corners[3], uv_corners[2], uv_corners[1]]
	return C.success({"vertices": corners, "uvs": uv_corners, "normal": desired, "signature": signature})

func _valid_axis_direction(quad: Dictionary) -> bool:
	if typeof(quad.get("axis")) != TYPE_STRING or not Utils.is_json_integer(quad.get("direction")):
		return false
	return String(quad["axis"]) in ["X", "Y", "Z"] and int(quad["direction"]) in [-1, 1]

func _normal(axis: String, direction: int) -> Vector3:
	match axis:
		"X": return Vector3(float(direction), 0.0, 0.0)
		"Y": return Vector3(0.0, float(direction), 0.0)
		"Z": return Vector3(0.0, 0.0, float(direction))
	return Vector3.ZERO
