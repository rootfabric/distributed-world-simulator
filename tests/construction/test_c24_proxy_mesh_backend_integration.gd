extends SceneTree

const F = preload("res://tests/construction/fixtures/c22_compiled_proxy_fixture.gd")
const Controller = preload("res://scripts/construction/proxies/construction_proxy_streaming_controller.gd")
const Plan = preload("res://scripts/construction/proxies/construction_proxy_stream_plan.gd")

var assertions := 0
var failures: Array[String] = []
var controller
var request: Dictionary

func _init() -> void:
	request = F.compile_request()
	controller = Controller.new()
	get_root().add_child(controller)
	_ok(controller.compile_construct(request), "compile C22 large construct")
	_test_far_mesh_materialization_and_reuse()
	_test_section_local_and_interior_transitions()
	_test_damage_creates_new_shell_resource()
	_finish()

func _test_far_mesh_materialization_and_reuse() -> void:
	var first: Dictionary = controller.present("client/c24/player", F.far_interest(request))
	_ok(first, "present far")
	var runtime = first["runtime"]
	var packet: Dictionary = first["packet"]
	var artifact: Dictionary = packet["artifact_payloads"][0]
	var meshes: Array = runtime.get_proxy_mesh_instances()
	_assert(runtime.get_detail_mode() == Plan.DISTANT_SHELL, "far detail mode")
	_assert(meshes.size() == 1, "one far shell mesh")
	_assert(meshes[0] is MeshInstance3D, "far proxy is MeshInstance3D")
	_assert(meshes[0].mesh is ArrayMesh, "far proxy uses ArrayMesh")
	_assert(not (meshes[0].mesh is BoxMesh), "far proxy no longer uses bounds BoxMesh")
	_assert(bool(meshes[0].get_meta("array_mesh_backend", false)), "array mesh backend metadata")
	_assert(int(meshes[0].get_meta("vertex_count", -1)) == int(artifact["merged_quad_count"]) * 4, "far shell vertex count")
	_assert(int(meshes[0].get_meta("triangle_count", -1)) == int(artifact["merged_quad_count"]) * 2, "far shell triangle count")
	_assert(int(meshes[0].get_meta("surface_count", -1)) == Array(artifact["material_batches"]).size(), "far shell material surfaces")
	_assert(runtime.get_total_proxy_vertex_count() == int(artifact["merged_quad_count"]) * 4, "runtime vertex total")
	_assert(runtime.get_total_proxy_triangle_count() == int(artifact["merged_quad_count"]) * 2, "runtime triangle total")
	_assert(runtime.get_total_proxy_surface_count() == Array(artifact["material_batches"]).size(), "runtime surface total")
	_assert(int(first["apply_result"]["mesh_cache_hit_count"]) == 0, "first far materialization misses cache")
	var mesh_resource = meshes[0].mesh
	var signature := String(meshes[0].get_meta("mesh_signature", ""))
	_assert(not signature.is_empty(), "far mesh signature")
	_assert(_aabb_matches(mesh_resource.get_aabb(), artifact["bounds_min_m"], artifact["bounds_max_m"]), "far mesh aabb matches artifact")

	var replay: Dictionary = controller.present("client/c24/player", F.far_interest(request))
	_ok(replay, "present far replay")
	var replay_meshes: Array = runtime.get_proxy_mesh_instances()
	_assert(replay["runtime"] == runtime, "runtime node reused")
	_assert(int(replay["apply_result"]["mesh_cache_hit_count"]) == 1, "far replay hits mesh cache")
	_assert(replay_meshes[0].mesh == mesh_resource, "far replay reuses identical ArrayMesh resource")
	_assert(String(replay_meshes[0].get_meta("mesh_signature", "")) == signature, "far replay signature stable")
	var cache_stats: Dictionary = runtime.get_mesh_cache_stats()
	_assert(int(cache_stats["entries"]) == 1, "one cached shell resource")
	_assert(int(cache_stats["hits"]) == 1 and int(cache_stats["misses"]) == 1, "far cache metrics exact")
	var second_client: Dictionary = controller.present("client/c24/observer-two", F.far_interest(request))
	_ok(second_client, "present far for second client")
	_assert(second_client["runtime"] != runtime, "clients keep independent SceneTree runtimes")
	_assert(int(second_client["apply_result"]["mesh_cache_hit_count"]) == 1, "second client hits controller-wide mesh cache")
	_assert(second_client["runtime"].get_proxy_mesh_instances()[0].mesh == mesh_resource, "clients share identical ArrayMesh resource")
	cache_stats = controller.get_mesh_cache().get_stats()
	_assert(int(cache_stats["entries"]) == 1, "cross-client sharing does not duplicate GPU resource")

func _test_section_local_and_interior_transitions() -> void:
	var runtime = controller.get_runtime("client/c24/player", F.CONSTRUCT_ID)
	var section: Dictionary = controller.present("client/c24/player", F.section_interest(request))
	_ok(section, "present section HLOD")
	_assert(section["runtime"] == runtime, "section reuses runtime")
	_assert(runtime.get_detail_mode() == Plan.SECTION_HLOD, "section detail mode")
	_assert(runtime.get_proxy_mesh_count() == 12, "section mesh budget")
	_assert(runtime.get_collision_proxy_count() == 12, "section collision budget")
	_assert(runtime.get_interactive_part_count() == 0, "section exact parts absent")
	_assert(int(section["apply_result"]["mesh_cache_hit_count"]) == 0, "first section resources are cache misses")
	_assert(_all_proxy_meshes_are_array_mesh(runtime), "all section proxies use ArrayMesh")
	_assert(runtime.get_total_proxy_triangle_count() == _packet_triangle_count(section["packet"]), "section triangle total follows artifact quads")
	_assert(runtime.get_total_proxy_surface_count() == _packet_surface_count(section["packet"]), "section surface total follows batches")

	var local: Dictionary = controller.present("client/c24/player", F.local_interest(request))
	_ok(local, "present local exterior")
	_assert(runtime.get_detail_mode() == Plan.LOCAL_EXTERIOR, "local detail mode")
	_assert(runtime.get_proxy_mesh_count() <= 8, "local proxy count bounded")
	_assert(runtime.get_interactive_part_count() <= 16, "local exact parts bounded")
	_assert(_all_proxy_meshes_are_array_mesh(runtime), "all local proxies use ArrayMesh")
	_assert(runtime.get_total_proxy_triangle_count() == _packet_triangle_count(local["packet"]), "local triangle total")

	var interior: Dictionary = controller.present("client/c24/player", F.interior_interest(request))
	_ok(interior, "present interior")
	_assert(runtime.get_detail_mode() == Plan.INTERIOR_CELL, "interior detail mode")
	_assert(runtime.get_interactive_part_count() == 8, "interior exact parts retained")
	_assert(runtime.get_proxy_mesh_count() <= 7, "interior proxy context bounded")
	_assert(_all_proxy_meshes_are_array_mesh(runtime), "interior proxies use ArrayMesh, including empty cell proxy")
	_assert(runtime.get_total_proxy_triangle_count() == _packet_triangle_count(interior["packet"]), "interior triangle total")

	var far_again: Dictionary = controller.present("client/c24/player", F.far_interest(request))
	_ok(far_again, "return to far")
	_assert(int(far_again["apply_result"]["mesh_cache_hit_count"]) == 1, "return to far reuses cached shell")
	_assert(runtime.get_proxy_mesh_count() == 1, "return to one shell mesh")
	_assert(runtime.get_interactive_part_count() == 0, "return clears exact parts")
	_assert(runtime.get_collision_proxy_count() == 0, "return clears collision proxies")
	var stats: Dictionary = runtime.get_mesh_cache_stats()
	_assert(int(stats["entries"]) < 32, "transition cache remains bounded")
	_assert(int(stats["gpu_bytes"]) < 16777216, "fixture GPU resource estimate remains bounded")

func _test_damage_creates_new_shell_resource() -> void:
	var runtime = controller.get_runtime("client/c24/player", F.CONSTRUCT_ID)
	var before_mesh = runtime.get_proxy_mesh_instances()[0].mesh
	var before_signature := String(runtime.get_proxy_mesh_instances()[0].get_meta("mesh_signature", ""))
	var damaged: Dictionary = F.damaged_request(request, "part/c22/block-000000")
	var incremental: Dictionary = controller.recompile_incremental(damaged, ["part/c22/block-000000"])
	_ok(incremental, "incremental damage compile")
	_assert(bool(incremental["invalidation_plan"]["shell_rebuilt"]), "damage rebuilds shell artifact")
	request = damaged
	var after: Dictionary = controller.present("client/c24/player", F.far_interest(request))
	_ok(after, "present damaged far shell")
	var after_mesh = runtime.get_proxy_mesh_instances()[0].mesh
	var after_signature := String(runtime.get_proxy_mesh_instances()[0].get_meta("mesh_signature", ""))
	_assert(int(after["apply_result"]["mesh_cache_hit_count"]) == 0, "new shell content is cache miss")
	_assert(after_mesh != before_mesh, "changed shell gets new ArrayMesh resource")
	_assert(after_signature != before_signature, "changed shell gets new mesh signature")
	_assert(runtime.get_total_proxy_triangle_count() == _packet_triangle_count(after["packet"]), "damaged shell triangles match artifact")
	var replay: Dictionary = controller.present("client/c24/player", F.far_interest(request))
	_ok(replay, "damaged shell replay")
	_assert(int(replay["apply_result"]["mesh_cache_hit_count"]) == 1, "damaged shell replay hits cache")
	_assert(runtime.get_proxy_mesh_instances()[0].mesh == after_mesh, "damaged shell resource reused")

func _all_proxy_meshes_are_array_mesh(runtime) -> bool:
	for mesh_instance in runtime.get_proxy_mesh_instances():
		if not (mesh_instance is MeshInstance3D) or not (mesh_instance.mesh is ArrayMesh):
			return false
	return true

func _packet_triangle_count(packet: Dictionary) -> int:
	var total := 0
	for artifact in packet["artifact_payloads"]:
		total += int(artifact["merged_quad_count"]) * 2
	return total

func _packet_surface_count(packet: Dictionary) -> int:
	var total := 0
	for artifact in packet["artifact_payloads"]:
		total += Array(artifact["material_batches"]).size()
	return total

func _aabb_matches(aabb: AABB, min_value: Array, max_value: Array) -> bool:
	var expected_position := Vector3(float(min_value[0]), float(min_value[1]), float(min_value[2]))
	var expected_size := Vector3(float(max_value[0]) - float(min_value[0]), float(max_value[1]) - float(min_value[1]), float(max_value[2]) - float(min_value[2]))
	return aabb.position.is_equal_approx(expected_position) and aabb.size.is_equal_approx(expected_size)

func _ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])

func _assert(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("C24 proxy mesh backend integration: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("C24 proxy mesh backend integration: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
