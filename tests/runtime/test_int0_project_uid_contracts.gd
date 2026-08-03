extends SceneTree

const PROJECT_PATH := "res://project.godot"
const AUTOLOAD_SCRIPT_PATH := "res://addons/breakpoint_mcp/runtime_bridge.gd"
const AUTOLOAD_UID_PATH := "res://addons/breakpoint_mcp/runtime_bridge.gd.uid"
const AUTOLOAD_UID := "uid://cpjc0o64cgs1"
const SELF_UID_PATH := "res://tests/runtime/test_int0_project_uid_contracts.gd.uid"
const SELF_UID := "uid://ciuuux044fklg"

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	var project_source := _read(PROJECT_PATH)
	var uid_source := _read(AUTOLOAD_UID_PATH).strip_edges()
	var self_uid_source := _read(SELF_UID_PATH).strip_edges()

	_assert(
		project_source.contains('BreakpointRuntimeBridge="*%s"' % AUTOLOAD_UID),
		"INT0 autoload uses the canonical tracked UID"
	)
	_assert(
		not project_source.contains('BreakpointRuntimeBridge="*res://addons/breakpoint_mcp/runtime_bridge.gd"'),
		"INT0 autoload does not retain the import-rewritten path form"
	)
	_assert(uid_source == AUTOLOAD_UID, "autoload UID sidecar matches project.godot")
	_assert(FileAccess.file_exists(AUTOLOAD_SCRIPT_PATH), "autoload runtime bridge source exists")
	_assert(ResourceLoader.exists(AUTOLOAD_UID), "autoload UID resolves after editor import")
	_assert(FileAccess.file_exists(SELF_UID_PATH), "project UID contract tracks its own UID sidecar")
	_assert(self_uid_source == SELF_UID, "project UID contract sidecar has the accepted UID")
	_assert(ResourceLoader.exists(SELF_UID), "project UID contract UID resolves after editor import")

	_finish()


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		failures.append("Missing source: %s" % path)
		return ""
	return FileAccess.get_file_as_string(path)


func _assert(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("INT0 project UID contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("INT0 project UID contracts: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
