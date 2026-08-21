extends SceneTree

const F = preload("res://tests/construction/fixtures/c24_proxy_mesh_fixture.gd")
const Backend = preload("res://scripts/construction/proxies/construction_proxy_array_mesh_backend.gd")
const Cache = preload("res://scripts/construction/proxies/construction_proxy_mesh_cache.gd")
const Descriptor = preload("res://scripts/construction/proxies/construction_proxy_mesh_descriptor.gd")
const MaterialLibrary = preload("res://scripts/construction/proxies/construction_proxy_material_library.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_test_array_mesh_contract()
	_test_winding_normals_and_uvs()
	_test_empty_artifact()
	_test_fail_closed_payload_validation()
	_test_content_addressed_lru_cache()
	_test_oversized_mesh_bypasses_cache()
	_test_bounded_material_library()
	_finish()

func _test_array_mesh_contract() -> void:
	var artifact: Dictionary = F.sample_artifact()
	var backend = Backend.new()
	var first: Dictionary = backend.compile(artifact)
	_ok(first, "compile sample artifact")
	var mesh: ArrayMesh = first["mesh"]
	var descriptor: Dictionary = first["descriptor"]
	_ok(Descriptor.validate(descriptor), "descriptor validates")
	_assert(mesh is ArrayMesh, "backend returns ArrayMesh")
	_assert(String(mesh.get_meta("construction_proxy_backend")) == Descriptor.BACKEND, "mesh backend metadata")
	_assert(String(mesh.get_meta("construction_proxy_front_face_winding")) == Backend.FRONT_FACE_WINDING, "mesh records clockwise front-face contract")
	_assert(mesh.get_surface_count() == int(descriptor["surface_count"]), "surface count matches descriptor")
	_assert(int(descriptor["vertex_count"]) == int(artifact["merged_quad_count"]) * 4, "four vertices per greedy quad")
	_assert(int(descriptor["index_count"]) == int(artifact["merged_quad_count"]) * 6, "six indices per greedy quad")
	_assert(int(descriptor["triangle_count"]) == int(artifact["merged_quad_count"]) * 2, "two triangles per greedy quad")
	_assert(int(descriptor["estimated_gpu_bytes"]) == int(descriptor["vertex_count"]) * 32 + int(descriptor["index_count"]) * 4, "gpu byte estimate")
	_assert(backend.get_material_count() == int(descriptor["surface_count"]), "one cached material per material key")
	for surface_index in range(mesh.get_surface_count()):
		var material = mesh.surface_get_material(surface_index)
		_assert(material is StandardMaterial3D, "surface material is StandardMaterial3D")
		_assert(String(material.get_meta("construction_proxy_material_key")) == mesh.surface_get_name(surface_index), "material key metadata")
	var second: Dictionary = backend.compile(artifact)
	_ok(second, "deterministic second compile")
	_assert(String(second["descriptor"]["mesh_signature"]) == String(descriptor["mesh_signature"]), "mesh signature deterministic")
	_assert(String(second["descriptor"]["checksum"]) == String(descriptor["checksum"]), "descriptor checksum deterministic")
	var corrupt: Dictionary = descriptor.duplicate(true)
	corrupt["triangle_count"] = int(corrupt["triangle_count"]) + 1
	_err(Descriptor.validate(corrupt), "CONSTRUCTION_PROXY_MESH_DESCRIPTOR_TRIANGLE_COUNT_MISMATCH", "descriptor count corruption")

func _test_winding_normals_and_uvs() -> void:
	var result: Dictionary = Backend.new().compile(F.sample_artifact())
	_ok(result, "compile geometry arrays")
	var mesh: ArrayMesh = result["mesh"]
	for surface_index in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		_assert(vertices.size() == normals.size(), "normal count matches vertices")
		_assert(vertices.size() == uvs.size(), "uv count matches vertices")
		_assert(indices.size() % 6 == 0, "quad index layout")
		for offset in range(0, indices.size(), 6):
			var a: Vector3 = vertices[indices[offset]]
			var b: Vector3 = vertices[indices[offset + 1]]
			var c: Vector3 = vertices[indices[offset + 2]]
			var geometric := (b - a).cross(c - a).normalized()
			# Godot treats clockwise triangles as front-facing. Relative to the
			# outward stored normal, the mathematical cross product points inward.
			_assert(geometric.dot(normals[indices[offset]]) < -0.999999, "Godot-clockwise triangle faces stored outward normal")
			_assert(uvs[indices[offset]].is_finite(), "uv finite")
	var aabb := mesh.get_aabb()
	_assert(aabb.size.x > 0.0 and aabb.size.y > 0.0 and aabb.size.z > 0.0, "generated mesh has non-empty aabb")

func _test_empty_artifact() -> void:
	var result: Dictionary = Backend.new().compile(F.empty_artifact())
	_ok(result, "compile empty interior artifact")
	_assert(result["mesh"] is ArrayMesh, "empty artifact still returns ArrayMesh")
	_assert(result["mesh"].get_surface_count() == 0, "empty artifact has zero surfaces")
	_assert(int(result["descriptor"]["vertex_count"]) == 0, "empty artifact vertices")
	_assert(int(result["descriptor"]["triangle_count"]) == 0, "empty artifact triangles")
	_ok(Descriptor.validate(result["descriptor"]), "empty descriptor validates")

func _test_fail_closed_payload_validation() -> void:
	_err(Backend.new().compile(F.invalid_grid_artifact()), "INVALID_CONSTRUCTION_PROXY_GRID_QUAD_SIZE", "zero-width quad rejected")
	var artifact: Dictionary = F.sample_artifact()
	artifact = artifact.duplicate(true)
	artifact["material_batches"] = Array(artifact["material_batches"]).duplicate(true)
	artifact["material_batches"][0] = Dictionary(artifact["material_batches"][0]).duplicate(true)
	artifact["material_batches"][0]["quads"] = Array(artifact["material_batches"][0]["quads"]).duplicate(true)
	artifact["material_batches"][0]["quads"][0] = Dictionary(artifact["material_batches"][0]["quads"][0]).duplicate(true)
	artifact["material_batches"][0]["quads"][0]["unexpected"] = true
	artifact["content_hash"] = preload("res://scripts/construction/proxies/construction_proxy_artifact.gd").compute_content_hash(artifact)
	artifact["artifact_id"] = "proxy-artifact/%s" % artifact["content_hash"]
	artifact["checksum"] = preload("res://scripts/construction/proxies/construction_proxy_artifact.gd").compute_checksum(artifact)
	var result: Dictionary = Backend.new().compile(artifact)
	_assert(not bool(result.get("success", false)), "unknown quad field rejected")

	var string_direction: Dictionary = F.sample_artifact("-string-direction")
	string_direction["material_batches"][0]["quads"][0]["direction"] = "1"
	_rehash_artifact(string_direction)
	_err(Backend.new().compile(string_direction), "INVALID_CONSTRUCTION_PROXY_FALLBACK_QUAD", "string direction rejected")
	var numeric_axis: Dictionary = F.sample_artifact("-numeric-axis")
	numeric_axis["material_batches"][0]["quads"][0]["axis"] = 1
	_rehash_artifact(numeric_axis)
	_err(Backend.new().compile(numeric_axis), "INVALID_CONSTRUCTION_PROXY_FALLBACK_QUAD", "numeric axis rejected")

func _rehash_artifact(artifact: Dictionary) -> void:
	var artifact_contract = preload("res://scripts/construction/proxies/construction_proxy_artifact.gd")
	artifact["content_hash"] = artifact_contract.compute_content_hash(artifact)
	artifact["artifact_id"] = "proxy-artifact/%s" % artifact["content_hash"]
	artifact["checksum"] = artifact_contract.compute_checksum(artifact)

func _test_content_addressed_lru_cache() -> void:
	var cache = Cache.new(2, 1048576)
	var first_artifact: Dictionary = F.sample_artifact("-a")
	var second_artifact: Dictionary = F.sample_artifact("-b")
	var third_artifact: Dictionary = F.sample_artifact("-c")
	var first: Dictionary = cache.materialize(first_artifact)
	_ok(first, "cache first miss")
	_assert(not bool(first["cache_hit"]), "first materialization is miss")
	var replay: Dictionary = cache.materialize(first_artifact)
	_ok(replay, "cache replay")
	_assert(bool(replay["cache_hit"]), "second materialization is hit")
	_assert(first["mesh"] == replay["mesh"], "cache returns identical mesh resource")
	_ok(cache.materialize(second_artifact), "cache second artifact")
	_ok(cache.materialize(first_artifact), "refresh first artifact LRU")
	_ok(cache.materialize(third_artifact), "cache third artifact")
	var stats: Dictionary = cache.get_stats()
	_assert(int(stats["entries"]) == 2, "entry budget enforced")
	_assert(int(stats["evictions"]) == 1, "least recently used entry evicted")
	_assert(cache.has_content_hash(String(first_artifact["content_hash"])), "recently touched entry retained")
	_assert(not cache.has_content_hash(String(second_artifact["content_hash"])), "older entry evicted")
	_assert(cache.has_content_hash(String(third_artifact["content_hash"])), "new entry retained")
	_assert(int(stats["hits"]) == 2 and int(stats["misses"]) == 3, "cache metrics bounded and exact")

func _test_oversized_mesh_bypasses_cache() -> void:
	var cache = Cache.new(2, 1)
	var artifact: Dictionary = F.sample_artifact("-oversized")
	var first: Dictionary = cache.materialize(artifact)
	_ok(first, "oversized mesh materializes")
	_assert(not bool(first["cache_hit"]), "oversized mesh is not a hit")
	_assert(bool(first["cache_bypassed"]), "oversized mesh explicitly bypasses cache")
	_assert(cache.get_entry_count() == 0 and cache.get_total_gpu_bytes() == 0, "oversized mesh cannot exceed cache budget")
	var second: Dictionary = cache.materialize(artifact)
	_ok(second, "oversized mesh rematerializes")
	_assert(first["mesh"] != second["mesh"], "bypassed mesh resource is not retained")
	var stats: Dictionary = cache.get_stats()
	_assert(int(stats["hits"]) == 0 and int(stats["misses"]) == 2, "oversized attempts remain misses")
	_assert(int(stats["oversized_bypasses"]) == 2 and int(stats["evictions"]) == 0, "oversized bypass metric exact")

func _test_bounded_material_library() -> void:
	var library = MaterialLibrary.new(2)
	var first: Dictionary = library.resolve("material/a")
	var second: Dictionary = library.resolve("material/b")
	_ok(first, "first material resolves")
	_ok(second, "second material resolves")
	var replay: Dictionary = library.resolve("material/a")
	_ok(replay, "material replay resolves")
	_assert(bool(replay["cache_hit"]), "material replay is a hit")
	_ok(library.resolve("material/c"), "third material resolves")
	_assert(library.get_material_count() == 2, "material entry budget enforced")
	_assert(library.has_material("material/a") and library.has_material("material/c"), "recent and new materials retained")
	_assert(not library.has_material("material/b"), "least recently used material evicted")
	var stats: Dictionary = library.get_stats()
	_assert(int(stats["hits"]) == 1 and int(stats["misses"]) == 3 and int(stats["evictions"]) == 1, "material cache metrics exact")

func _ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])

func _err(result: Dictionary, code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [message, result])

func _assert(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("C24 proxy mesh backend contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("C24 proxy mesh backend contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
