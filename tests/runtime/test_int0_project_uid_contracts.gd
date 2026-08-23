extends SceneTree

const PROJECT_PATH := "res://project.godot"
const PLUGIN_PATH := "res://addons/breakpoint_mcp/plugin.gd"
const AUTOLOAD_SCRIPT_PATH := "res://addons/breakpoint_mcp/runtime_bridge.gd"
const AUTOLOAD_UID_PATH := "res://addons/breakpoint_mcp/runtime_bridge.gd.uid"
const AUTOLOAD_UID := "uid://cpjc0o64cgs1"
const SELF_UID_PATH := "res://tests/runtime/test_int0_project_uid_contracts.gd.uid"
const SELF_UID := "uid://ciuuux044fklg"
const REQUIRE_IMPORTED_UIDS_ARG := "--require-imported-uids"

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	var project_source := _read(PROJECT_PATH)
	var plugin_source := _read(PLUGIN_PATH)
	var uid_source := _read(AUTOLOAD_UID_PATH).strip_edges()
	var self_uid_source := _read(SELF_UID_PATH).strip_edges()
	var require_imported_uids := OS.get_cmdline_user_args().has(REQUIRE_IMPORTED_UIDS_ARG)

	_assert(
		project_source.contains('BreakpointRuntimeBridge="*%s"' % AUTOLOAD_SCRIPT_PATH),
		"INT0 autoload uses the runtime-safe tracked resource path"
	)
	_assert(
		not project_source.contains('BreakpointRuntimeBridge="*%s"' % AUTOLOAD_UID),
		"INT0 autoload does not use a UID reference that fails cold runtime startup"
	)
	_assert(uid_source == AUTOLOAD_UID, "autoload UID sidecar remains tracked for resource identity")
	_assert(FileAccess.file_exists(AUTOLOAD_SCRIPT_PATH), "autoload runtime bridge source exists")
	_assert(ResourceLoader.exists(AUTOLOAD_SCRIPT_PATH), "autoload resource path resolves directly")
	_assert(FileAccess.file_exists(SELF_UID_PATH), "project UID contract tracks its own UID sidecar")
	_assert(self_uid_source == SELF_UID, "project UID contract sidecar has the accepted UID")
	_assert(
		plugin_source.contains("ProjectSettings.has_setting(setting_name)"),
		"breakpoint plugin preserves an already tracked runtime autoload"
	)
	_assert(
		plugin_source.contains("if _owns_runtime_autoload:")
		and plugin_source.contains("remove_autoload_singleton(RUNTIME_AUTOLOAD)"),
		"breakpoint plugin removes only an autoload it owns"
	)

	# UID -> path resolution is backed by Godot's imported UID cache. A cold checkout
	# intentionally has no tracked .godot cache, so direct source-contract execution
	# must not fail merely because editor import has not happened yet. The V0 preflight
	# reruns this same contract with --require-imported-uids after two completed import
	# passes, where both UID mappings are required to resolve.
	if require_imported_uids:
		_assert(ResourceLoader.exists(AUTOLOAD_UID), "autoload UID resolves after editor import")
		_assert(ResourceLoader.exists(SELF_UID), "project UID contract UID resolves after editor import")

	_finish(require_imported_uids)


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		failures.append("Missing source: %s" % path)
		return ""
	return FileAccess.get_file_as_string(path)


func _assert(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)


func _finish(require_imported_uids: bool) -> void:
	var mode := "imported-uids" if require_imported_uids else "cold-source"
	if failures.is_empty():
		print("INT0 project UID contracts: PASS (%d assertions, %s)" % [assertions, mode])
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("INT0 project UID contracts: FAIL (%d assertions, %d failures, %s)" % [assertions, failures.size(), mode])
	quit(1)