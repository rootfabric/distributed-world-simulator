extends SceneTree

const Adapter = preload("res://scripts/labs/t1/ts0/ts0_large_structural_proxy_adapter.gd")

const SCENE_PATH := "res://scenes/labs/construction/ts0_large_structural_visual_lab.tscn"
const PROFILES: Array[String] = ["CUBE_10K", "PYRAMID_10K"]
const MAX_SECTION_ARTIFACTS := 12

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_test_graphical_scene_contract()
	_finish()

func _test_graphical_scene_contract() -> void:
	_assert(ResourceLoader.exists(SCENE_PATH), "TS0.1 graphical scene exists")
	var packed = load(SCENE_PATH)
	_assert(packed is PackedScene, "TS0.1 graphical scene loads")
	if not (packed is PackedScene):
		return
	var lab = packed.instantiate()
	lab.auto_boot = false
	get_root().add_child(lab)
	_assert(lab is Node3D, "TS0.1 lab root is Node3D")
	for method_name in ["load_profile", "set_view_mode", "get_metrics", "get_manifest", "get_compile_stats", "get_runtime", "get_controller"]:
		_assert(lab.has_method(method_name), "TS0.1 lab exposes %s" % method_name)

	for profile_id in PROFILES:
		var loaded: Dictionary = lab.load_profile(profile_id)
		_ok(loaded, "%s compiles through C22" % profile_id)
		if not bool(loaded.get("success", false)):
			continue
		var manifest: Dictionary = lab.get_manifest()
		var compile_stats: Dictionary = lab.get_compile_stats()
		var initial_metrics: Dictionary = lab.get_metrics()
		_assert(String(lab.get_current_profile()) == profile_id, "%s becomes active profile" % profile_id)
		_assert(int(manifest["total_part_count"]) >= 10000, "%s keeps 10k canonical scale" % profile_id)
		_assert(int(manifest["total_section_count"]) > 1, "%s compiled into multiple sections" % profile_id)
		_assert(int(manifest["total_section_count"]) < int(manifest["total_part_count"]), "%s section count stays below part count" % profile_id)
		_assert(String(manifest["source_checksum"]) == String(initial_metrics["canonical_checksum"]), "%s canonical checksum reaches proxy manifest" % profile_id)
		_assert(int(compile_stats.get("culled_face_count", 0)) > 0, "%s C22 occupancy culls internal faces" % profile_id)
		_assert(int(compile_stats.get("exposed_face_count", 0)) < int(compile_stats.get("raw_face_count", 0)), "%s exposed surface is smaller than raw faces" % profile_id)
		_assert(int(compile_stats.get("shell_quad_count", 0)) > 0, "%s shell has greedy geometry" % profile_id)

		var controller = lab.get_controller()
		var artifact_count_before := int(controller.get_cache().get_artifact_count())
		var canonical_checksum := String(manifest["source_checksum"])

		var near: Dictionary = lab.set_view_mode(Adapter.MODE_NEAR)
		_ok(near, "%s near presentation" % profile_id)
		if bool(near.get("success", false)):
			_check_mode(lab, profile_id, Adapter.MODE_NEAR, "LOCAL_EXTERIOR", canonical_checksum, false)

		var mid: Dictionary = lab.set_view_mode(Adapter.MODE_MID)
		_ok(mid, "%s mid presentation" % profile_id)
		if bool(mid.get("success", false)):
			_check_mode(lab, profile_id, Adapter.MODE_MID, "SECTION_HLOD", canonical_checksum, false)

		var far: Dictionary = lab.set_view_mode(Adapter.MODE_FAR)
		_ok(far, "%s far presentation" % profile_id)
		if bool(far.get("success", false)):
			_check_mode(lab, profile_id, Adapter.MODE_FAR, "DISTANT_SHELL", canonical_checksum, true)

		var artifact_count_after := int(controller.get_cache().get_artifact_count())
		_assert(artifact_count_after == artifact_count_before, "%s near/mid/far does not grow C22 artifact cache" % profile_id)
		var mesh_stats_before: Dictionary = controller.get_mesh_cache().get_stats()
		var hits_before := int(mesh_stats_before.get("hits", 0))
		_ok(lab.set_view_mode(Adapter.MODE_FAR), "%s repeat far presentation" % profile_id)
		var mesh_stats_after: Dictionary = controller.get_mesh_cache().get_stats()
		_assert(int(mesh_stats_after.get("hits", 0)) > hits_before, "%s repeated far shell reuses C24 mesh cache" % profile_id)
		_assert(int(mesh_stats_after.get("entries", 0)) <= int(mesh_stats_after.get("max_entries", 256)), "%s C24 mesh cache entry budget respected" % profile_id)
		_assert(int(mesh_stats_after.get("gpu_bytes", 0)) <= int(mesh_stats_after.get("max_gpu_bytes", 134217728)), "%s C24 mesh cache byte budget respected" % profile_id)

	lab.free()

func _check_mode(lab, profile_id: String, requested_mode: String, expected_detail_mode: String, canonical_checksum: String, expect_single_shell: bool) -> void:
	var runtime = lab.get_runtime()
	_assert(runtime != null and is_instance_valid(runtime), "%s %s runtime exists" % [profile_id, requested_mode])
	if runtime == null or not is_instance_valid(runtime):
		return
	var metrics: Dictionary = lab.get_metrics()
	_assert(String(runtime.get_detail_mode()) == expected_detail_mode, "%s %s maps to %s" % [profile_id, requested_mode, expected_detail_mode])
	_assert(String(metrics["canonical_checksum"]) == canonical_checksum, "%s %s keeps canonical checksum" % [profile_id, requested_mode])
	_assert(int(runtime.get_proxy_mesh_count()) > 0, "%s %s has proxy meshes" % [profile_id, requested_mode])
	if expect_single_shell:
		_assert(int(runtime.get_proxy_mesh_count()) == 1, "%s FAR uses one shell mesh" % profile_id)
		_assert(int(runtime.get_collision_proxy_count()) == 0, "%s FAR has no collision proxies" % profile_id)
		_assert(int(metrics["visible_sections"]) == 0, "%s FAR has no visible section payload" % profile_id)
	else:
		_assert(int(runtime.get_proxy_mesh_count()) <= MAX_SECTION_ARTIFACTS, "%s %s proxy mesh count is bounded" % [profile_id, requested_mode])
		_assert(int(runtime.get_collision_proxy_count()) <= MAX_SECTION_ARTIFACTS, "%s %s collision proxy count is bounded" % [profile_id, requested_mode])
		_assert(int(metrics["visible_sections"]) <= MAX_SECTION_ARTIFACTS, "%s %s visible sections are bounded" % [profile_id, requested_mode])
	_assert(int(metrics["active_runtime_nodes"]) < int(metrics["canonical_part_count"]) / 20, "%s %s runtime nodes stay far below semantic parts" % [profile_id, requested_mode])
	_assert(int(runtime.get_total_proxy_triangle_count()) > 0, "%s %s has renderable triangles" % [profile_id, requested_mode])
	_assert(int(runtime.get_total_proxy_surface_count()) > 0, "%s %s has renderable surfaces" % [profile_id, requested_mode])
	for mesh_node in runtime.get_proxy_mesh_instances():
		_assert(mesh_node is MeshInstance3D, "%s %s proxy child is MeshInstance3D" % [profile_id, requested_mode])
		if mesh_node is MeshInstance3D:
			_assert(mesh_node.mesh is ArrayMesh, "%s %s uses C24 ArrayMesh" % [profile_id, requested_mode])
			_assert(bool(mesh_node.get_meta("array_mesh_backend", false)), "%s %s marks C24 backend" % [profile_id, requested_mode])

func _ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])

func _assert(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("TS0.1 10k graphical proxy acceptance: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("TS0.1 10k graphical proxy acceptance: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
