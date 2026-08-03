extends SceneTree

const F = preload("res://tests/construction/fixtures/c22_compiled_proxy_fixture.gd")
const Controller = preload("res://scripts/construction/proxies/construction_proxy_streaming_controller.gd")
const Plan = preload("res://scripts/construction/proxies/construction_proxy_stream_plan.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var request := F.compile_request()
	var controller = Controller.new(); get_root().add_child(controller); _ok(controller.compile_construct(request), "compile")
	var far: Dictionary = controller.present("client/c22/player", F.far_interest(request)); _ok(far, "present far")
	var runtime = far["runtime"]
	_assert(runtime is Node3D, "runtime node")
	_assert(runtime.get_detail_mode() == Plan.DISTANT_SHELL, "far detail mode")
	_assert(runtime.get_proxy_mesh_count() == 1, "one shell MeshInstance3D")
	_assert(runtime.get_collision_proxy_count() == 0, "distant shell has no collision proxy")
	_assert(runtime.get_interactive_part_count() == 0, "zero exact child nodes far away")
	_assert(runtime.get_suppressed_part_count() == 10000, "ten thousand presentations suppressed")
	_assert(runtime.get_child(0).get_child(0) is MeshInstance3D, "shell is graphical mesh")
	var section: Dictionary = controller.present("client/c22/player", F.section_interest(request)); _ok(section, "present sections")
	_assert(runtime == section["runtime"], "same runtime reused")
	_assert(runtime.get_detail_mode() == Plan.SECTION_HLOD, "section detail mode")
	_assert(runtime.get_proxy_mesh_count() == 12, "twelve section proxy meshes replace shell")
	_assert(runtime.get_collision_proxy_count() == 12, "section HLOD has bounded collision proxies")
	_assert(runtime.get_interactive_part_count() == 0, "no exact parts at section distance")
	var local: Dictionary = controller.present("client/c22/player", F.local_interest(request)); _ok(local, "present local exterior")
	_assert(runtime.get_detail_mode() == Plan.LOCAL_EXTERIOR, "local exterior mode")
	_assert(runtime.get_proxy_mesh_count() <= 8, "bounded local proxy meshes")
	_assert(runtime.get_collision_proxy_count() == runtime.get_proxy_mesh_count(), "local proxy collision follows loaded sections")
	_assert(runtime.get_interactive_part_count() <= 16, "bounded interactive nodes")
	_assert(runtime.get_proxy_mesh_count() + runtime.get_interactive_part_count() < 30, "no ten-thousand-node SceneTree")
	var interior: Dictionary = controller.present("client/c22/player", F.interior_interest(request)); _ok(interior, "present interior")
	_assert(runtime.get_detail_mode() == Plan.INTERIOR_CELL, "interior mode")
	_assert(runtime.get_interactive_part_count() == 8, "only bridge interactive parts materialized")
	_assert(runtime.get_proxy_mesh_count() <= 7, "interior cell plus nearby HLOD")
	_assert(runtime.get_collision_proxy_count() == runtime.get_proxy_mesh_count(), "interior proxy collision is bounded")
	_assert(runtime.get_suppressed_part_count() == 9992, "remaining parts still replaced")
	for part_id in runtime.get_interactive_part_ids(): _assert(String(part_id).begins_with("part/c22/"), "interactive semantic part id")
	_finish()

func _ok(result: Dictionary, message: String) -> void: _assert(bool(result.get("success", false)), "%s: %s" % [message, result])
func _assert(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)
func _finish() -> void:
	if failures.is_empty(): print("C22 compiled proxy graphical: PASS (%d assertions)" % assertions); quit(0); return
	for failure in failures: push_error(failure)
	print("C22 compiled proxy graphical: FAIL (%d failures, %d assertions)" % [failures.size(), assertions]); quit(1)
