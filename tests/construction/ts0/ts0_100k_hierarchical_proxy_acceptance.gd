extends SceneTree

const LabScene = preload("res://scenes/labs/construction/ts0_100k_hierarchical_visual_lab.tscn")
const Adapter = preload("res://scripts/labs/t1/ts0/ts0_large_structural_proxy_adapter.gd")

const PROFILES := {
	"CUBE_100K": {
		"parts": 97336,
		"checksum": "4aebed994f09f578ae241a9c8adb677eb5cf81d1581aea99491921c6f685e084",
	},
	"PYRAMID_100K": {
		"parts": 102510,
		"checksum": "4a721061894d65b7bee1d9502a331e0879e4ce5a8047cfe53650460e07b636e6",
	},
}

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_test_profiles()
	_finish()

func _test_profiles() -> void:
	_assert(LabScene is PackedScene, "TS0.2 graphical scene loads")
	if not (LabScene is PackedScene):
		return
	var lab = LabScene.instantiate()
	lab.auto_boot = false
	get_root().add_child(lab)
	for method_name in ["load_profile", "set_view_mode", "get_metrics", "get_manifest", "get_compile_stats", "get_hierarchy_stats", "get_controller", "get_hierarchy_runtime"]:
		_assert(lab.has_method(method_name), "TS0.2 lab exposes %s" % method_name)

	for profile_id in PROFILES:
		var expected: Dictionary = PROFILES[profile_id]
		var loaded: Dictionary = lab.load_profile(profile_id)
		_ok(loaded, "%s loads 100k canonical fixture and hierarchy" % profile_id)
		if not bool(loaded.get("success", false)):
			continue
		var manifest: Dictionary = lab.get_manifest()
		var compile_stats: Dictionary = lab.get_compile_stats()
		var hierarchy: Dictionary = lab.get_hierarchy_stats()
		var controller = lab.get_controller()

		_assert(int(manifest["total_part_count"]) == int(expected["parts"]), "%s exact canonical part count" % profile_id)
		_assert(String(manifest["source_checksum"]) == String(expected["checksum"]), "%s canonical checksum pinned" % profile_id)
		_assert(int(manifest["total_section_count"]) > 64, "%s exceeds TS0.1 flat section limit" % profile_id)
		_assert(int(compile_stats.get("culled_face_count", 0)) > 0, "%s C22 still culls internal faces" % profile_id)
		_assert(int(compile_stats.get("shell_quad_count", 0)) > 0, "%s C22 root shell exists" % profile_id)
		_assert(int(hierarchy["source_section_count"]) == int(manifest["total_section_count"]), "%s hierarchy covers every source section" % profile_id)
		_assert(int(hierarchy["cluster_count"]) > 1, "%s hierarchy has multiple coarse clusters" % profile_id)
		_assert(int(hierarchy["cluster_count"]) <= 64, "%s cluster count stays inside TS0.2 lab budget" % profile_id)
		_assert(int(hierarchy["cluster_count"]) < int(manifest["total_section_count"]), "%s hierarchy reduces section-level fanout" % profile_id)
		_assert(String(hierarchy["coverage_checksum"]).length() == 64, "%s hierarchy coverage checksum pinned" % profile_id)

		var artifact_count_before := int(controller.get_cache().get_artifact_count())
		var hierarchy_before := String(hierarchy["coverage_checksum"])
		var reload: Dictionary = lab.load_profile(profile_id)
		_ok(reload, "%s deterministic hierarchy replay" % profile_id)
		if bool(reload.get("success", false)):
			var hierarchy_after: Dictionary = lab.get_hierarchy_stats()
			_assert(String(hierarchy_after["coverage_checksum"]) == hierarchy_before, "%s hierarchy checksum deterministic" % profile_id)
		var artifact_count_after := int(controller.get_cache().get_artifact_count())
		_assert(artifact_count_after == artifact_count_before, "%s hierarchy does not publish new artifacts into C22 cache" % profile_id)

		var canonical_checksum := String(lab.get_manifest()["source_checksum"])

		var mid: Dictionary = lab.set_view_mode(Adapter.MODE_MID)
		_ok(mid, "%s MID hierarchical presentation" % profile_id)
		if bool(mid.get("success", false)):
			var m := lab.get_metrics()
			_assert(String(m["representation_mode"]) == "SECTION_HLOD", "%s MID detail mode" % profile_id)
			_assert(bool(m["coverage_complete"]), "%s MID keeps complete coverage" % profile_id)
			_assert(int(m["coverage_sections"]) == int(m["total_sections"]), "%s MID covers every source section" % profile_id)
			_assert(int(m["cluster_meshes"]) > 0, "%s MID uses coarse cluster meshes" % profile_id)
			_assert(int(m["section_meshes"]) == 0, "%s MID has no exact section refinement" % profile_id)
			_assert(int(m["proxy_meshes"]) <= int(hierarchy["cluster_count"]), "%s MID node count bounded by cluster count" % profile_id)
			_assert(int(m["proxy_meshes"]) < int(m["total_sections"]), "%s MID nodes below flat section count" % profile_id)
			_assert(int(m["triangles"]) > 0, "%s MID renderable triangles" % profile_id)
			_assert(String(m["canonical_checksum"]) == canonical_checksum, "%s MID canonical checksum invariant" % profile_id)
			_check_array_mesh_nodes(lab.get_hierarchy_runtime(), profile_id, "MID")

		var near: Dictionary = lab.set_view_mode(Adapter.MODE_NEAR)
		_ok(near, "%s NEAR hierarchical presentation" % profile_id)
		if bool(near.get("success", false)):
			var m := lab.get_metrics()
			_assert(String(m["representation_mode"]) == "LOCAL_EXTERIOR", "%s NEAR detail mode" % profile_id)
			_assert(bool(m["coverage_complete"]), "%s NEAR keeps complete coverage" % profile_id)
			_assert(int(m["coverage_sections"]) == int(m["total_sections"]), "%s NEAR covers every source section" % profile_id)
			_assert(int(m["refined_cluster_count"]) == 1, "%s NEAR refines exactly one local cluster" % profile_id)
			_assert(int(m["section_meshes"]) > 0, "%s NEAR replaces local cluster with section meshes" % profile_id)
			_assert(int(m["cluster_meshes"]) < int(hierarchy["cluster_count"]), "%s NEAR retains coarse remainder while replacing one cluster" % profile_id)
			_assert(int(m["proxy_meshes"]) < int(m["total_sections"]), "%s NEAR nodes stay below flat all-sections representation" % profile_id)
			_assert(String(m["canonical_checksum"]) == canonical_checksum, "%s NEAR canonical checksum invariant" % profile_id)
			_check_array_mesh_nodes(lab.get_hierarchy_runtime(), profile_id, "NEAR")

		var far: Dictionary = lab.set_view_mode(Adapter.MODE_FAR)
		_ok(far, "%s FAR root shell presentation" % profile_id)
		if bool(far.get("success", false)):
			var m := lab.get_metrics()
			_assert(String(m["representation_mode"]) == "DISTANT_SHELL", "%s FAR detail mode" % profile_id)
			_assert(bool(m["coverage_complete"]), "%s FAR complete root coverage" % profile_id)
			_assert(int(m["proxy_meshes"]) == 1, "%s FAR exactly one root shell mesh" % profile_id)
			_assert(int(m["collision_proxies"]) == 0, "%s FAR no collision proxies" % profile_id)
			_assert(int(m["triangles"]) > 0, "%s FAR renderable triangles" % profile_id)
			_assert(String(m["canonical_checksum"]) == canonical_checksum, "%s FAR canonical checksum invariant" % profile_id)

		_ok(lab.set_view_mode(Adapter.MODE_MID), "%s repeat MID" % profile_id)
		var mesh_stats_before: Dictionary = controller.get_mesh_cache().get_stats()
		var hits_before := int(mesh_stats_before.get("hits", 0))
		_ok(lab.set_view_mode(Adapter.MODE_MID), "%s second repeat MID" % profile_id)
		var mesh_stats_after: Dictionary = controller.get_mesh_cache().get_stats()
		_assert(int(mesh_stats_after.get("hits", 0)) > hits_before, "%s repeated cluster presentation reuses C24 cache" % profile_id)
		_assert(int(mesh_stats_after.get("entries", 0)) <= int(mesh_stats_after.get("max_entries", 256)), "%s C24 entry budget respected" % profile_id)
		_assert(int(mesh_stats_after.get("gpu_bytes", 0)) <= int(mesh_stats_after.get("max_gpu_bytes", 134217728)), "%s C24 byte budget respected" % profile_id)

	lab.free()

func _check_array_mesh_nodes(runtime, profile_id: String, mode: String) -> void:
	if runtime == null or not is_instance_valid(runtime):
		_assert(false, "%s %s hierarchy runtime exists" % [profile_id, mode])
		return
	for node in runtime.get_proxy_mesh_instances():
		_assert(node is MeshInstance3D, "%s %s hierarchy child is MeshInstance3D" % [profile_id, mode])
		if node is MeshInstance3D:
			_assert(node.mesh is ArrayMesh, "%s %s uses C24 ArrayMesh" % [profile_id, mode])
			_assert(bool(node.get_meta("array_mesh_backend", false)), "%s %s C24 metadata" % [profile_id, mode])

func _ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])

func _assert(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("TS0.2 100k hierarchical HLOD: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("TS0.2 100k hierarchical HLOD: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
