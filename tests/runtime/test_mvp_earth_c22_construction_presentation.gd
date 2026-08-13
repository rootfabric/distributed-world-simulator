extends SceneTree

const AdapterScript = preload("res://scripts/app/earth_construction_presentation.gd")
const Fixture = preload("res://tests/construction/fixtures/c22_compiled_proxy_fixture.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	var adapter = AdapterScript.new()
	get_root().add_child(adapter)
	_assert(bool(adapter.setup("client/mvp/earth-a").get("success", false)), "adapter setup")
	var request: Dictionary = Fixture.compile_request()
	var far: Dictionary = adapter.apply_authoritative_projection(request, Fixture.far_interest(request))
	_assert(bool(far.get("success", false)), "far authoritative projection")
	_assert(String(far.get("details", {}).get("detail_mode", "")) == "DISTANT_SHELL", "far C22 shell")
	_assert(int(far.get("details", {}).get("proxy_mesh_count", 0)) == 1, "far has one C24 mesh")
	_assert(int(far.get("details", {}).get("collision_proxy_count", -1)) == 0, "far has no collision proxy")
	var local: Dictionary = adapter.apply_authoritative_projection(request, Fixture.local_interest(request))
	_assert(bool(local.get("success", false)), "local authoritative projection")
	_assert(String(local.get("details", {}).get("detail_mode", "")) == "LOCAL_EXTERIOR", "local C22 mode")
	_assert(int(local.get("details", {}).get("proxy_mesh_count", 99)) <= 8, "local mesh budget")
	_assert(int(local.get("details", {}).get("collision_proxy_count", -1)) == int(local.get("details", {}).get("proxy_mesh_count", -2)), "local collision follows proxy")
	var report: Dictionary = adapter.get_report()
	_assert(int(report.get("direct_authority_references", -1)) == 0, "presentation owns no authority")
	_assert(not String(report.get("source_checksum", "")).is_empty(), "canonical source checksum recorded")
	adapter.queue_free()
	_finish()


func _assert(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("MVP Earth C22/C24 construction presentation: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("MVP Earth C22/C24 construction presentation: FAIL (%d failures)" % failures.size())
	quit(1)
